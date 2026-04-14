# Design: hearth v0

A path-addressed JSON data store with a REST API and pluggable
backends.

## Mental model

There is one conceptual JSON tree. Every node in the tree is addressed
by a URL path. Reading a path returns the subtree rooted there.
Writing to a path replaces the subtree at that location. The tree can
be arbitrarily deep but any single response is capped at 1MB.

This is the Firebase Realtime Database model.

## API

The API maps HTTP methods to tree operations. All request and response
bodies are `application/json`.

**Read:** `GET /data/user/alice/profile` returns the JSON subtree at
that path. If nothing exists there, returns `null` with `200`.

**Write:** `PUT /data/user/alice/profile` replaces the subtree at
that path with the request body. Creates intermediate nodes as needed
(PUT always succeeds regardless of whether parent paths exist).
Returns `200` with the written value.

**Merge:** `PATCH /data/user/alice/profile` merges the request body
into the existing subtree. Top-level keys in the body overwrite the
corresponding keys at the path. Keys not mentioned are left alone.
This is a shallow merge: given existing `{"a": {"x": 1, "y": 2}}`
and PATCH body `{"a": {"x": 99}}`, the result is `{"a": {"x": 99}}`
(the `y` key is lost because `a` is a top-level key in the body).
PATCH on a path holding a non-object value (scalar, array) returns
`400`. Returns `200` with the merged result.

**Create:** `POST /data/user/alice/scores` appends a new child to
the node with a server-generated UUID v7 key. Returns `201` with the
generated path. The target must be an object (or not exist yet, in
which case it is created as one). POST to a path holding a scalar
or array returns `400`.

**Delete:** `DELETE /data/user/alice/profile` removes the subtree at
that path. Returns `204` with no body. Deleting a path that does not
exist also returns `204` (idempotent).

**Query:** `GET /data/user/alice/scores?by=value&order=asc&limit=10`
returns a sorted, filtered subset of the children at the path. See
Queries below. The target must be an object. Query params on a path
holding a non-object value return `400`. If the path does not exist,
returns an empty object `{}`.

The `/data/` prefix is a namespace separator, not a semantic
constraint. Hearth stores and retrieves everything under `/data/`
without interpreting it - the tree structure is up to the client.
`/data/user/alice/profile`, `/data/questions/XYZ`, and
`/data/courses/rust-101` are all equally valid. Other top-level
prefixes are reserved for system endpoints (e.g. `/health`, and
future `/meta/` or `/admin/`).

A `GET /health` endpoint returns `200` with `{"ok": true}`.

## Error responses

All errors return a JSON body:

```json
{"error": "human-readable message"}
```

Status codes:

- `200` - successful GET, PUT, PATCH
- `201` - successful POST (child created)
- `204` - successful DELETE
- `400` - malformed JSON, invalid path segment, type mismatch
  (PATCH on a non-object, POST to a scalar, query on a non-object),
  invalid query params
- `404` - reserved but not used in v0 (GET returns `null` for
  missing paths, matching Firebase behaviour)
- `413` - response would exceed the 1MB cap

## Path structure

Paths are slash-separated sequences of string keys. They address nodes
in the JSON tree. A write to `/data/a/b/c` with value `42` produces:

```json
{ "a": { "b": { "c": 42 } } }
```

A subsequent write to `/data/a/b/d` with value `"hello"` produces:

```json
{ "a": { "b": { "c": 42, "d": "hello" } } }
```

Path segments are strings. A segment containing `/` must be
percent-encoded as `%2F` in the URL. Beyond that, any valid UTF-8
string is a valid segment.

Object keys are sorted alphabetically in all responses and on-disk
files. Insertion order is not preserved. This keeps responses
deterministic and makes the JSON files easier to read and diff.

JSON arrays are valid values but are not individually addressable by
path. `GET /data/user/alice/tags/0` returns `null`, not the first
element. Arrays are leaf values - you read and write the whole array.

## Queries

Firebase-inspired, deliberately limited:

- **by**: the field to sort by. Either a child key name or the
  special value `$key` (sort by key name). Defaults to `$key`.
- **order**: `asc` or `desc`. Defaults to `asc`.
- **Filter**: `from` (inclusive lower bound), `to` (inclusive upper
  bound), `eq` (exact match) - all filter on the field specified
  by `by`.
- **limit**: max number of results.

These constraints keep the query interface implementable by every
future backend. JSON-on-disk can scan and sort a collection in memory
(fine for small datasets). SQLite could use an index. Firestore maps
directly.

## Response cap

No single response exceeds 1MB of serialised JSON. If a subtree is
larger than this, the server returns `413` indicating the path is
too broad and the client should read a more specific subpath.

## Backend trait

The backend is an async trait with operations: read, write, merge,
delete, query. All operations take a path (as a slice of string
segments) and the relevant JSON value or query parameters. All
methods return `Result<T, Error>` with owned values to avoid
lifetime issues in the trait definition.

The trait is the central abstraction. Everything above it (HTTP
routing, serialisation, response cap enforcement) is shared.
Everything below it (storage mechanics) varies per implementation.

## JSON-on-disk backend

The first backend. Priorities are simplicity and inspectability -
you can look at the data with `cat` and `jq`.

**Sharding:** data is sharded by the first path segment under
`/data/`. Each shard lives in a separate JSON file on disk (e.g.
`data/user.json` for everything under `/data/user/`). This bounds
the size of any single file and scopes locking. The shard key comes
from the URL path, not an authenticated identity - hearth is
auth-unaware.

**Locking:** per-shard `tokio::sync::RwLock`. Reads take a read lock,
writes take a write lock. The lock map is held in memory, keyed by
shard name. Locks must not be held across `.await` points to keep
futures `Send`.

**Read path:** acquire read lock, read file with `tokio::fs`, parse
JSON, navigate to the requested path, clone the subtree, release
lock, serialise, check size cap, return.

**Write path:** acquire write lock, read file with `tokio::fs`, parse
JSON, navigate to the parent of the requested path, insert or replace
the value, serialise the full tree, write to a temp file, rename into
place (atomic on POSIX), release lock.

**Merge path:** same as write, but merge top-level keys instead of
replace.

**Query path:** acquire read lock, read the node at the path, collect
children, sort by the requested field, apply filters and limits,
return the result.

The whole shard file is read and written on every operation. This is
fine for small to medium datasets. It stops being fine when a single
shard exceeds a few MB - at that point, the SQLite backend is the
right answer.

## Configuration

Environment variables:

- `HEARTH_DATA_DIR` - root directory for data files (required)
- `HEARTH_LISTEN_ADDR` - bind address (default `127.0.0.1:8080`)
- `HEARTH_MAX_RESPONSE_SIZE` - response cap in bytes (default 1MB)

## Deployment

Hearth is a single binary. For v0 it requires a persistent filesystem
(local disk, a mounted volume, or similar). No auth - suitable for
local or trusted-network deployments only.

## Dependencies

Core: `axum`, `tokio`, `serde`, `serde_json`, `thiserror`, `uuid`.

`thiserror` for custom error types with idiomatic `From`
implementations. `tracing` and `tracing-subscriber` are added in the
config step, not the initial skeleton, to keep the hello-world step
clean.

## Build order

Each step is independently testable and committable.

1. **Skeleton** - `cargo init`, core dependencies, Axum hello-world
   with `/health` endpoint.
2. **JSON-on-disk storage** - read and write JSON files with
   `tokio::fs`. Per-shard file layout. No trait yet, just a concrete
   struct. This step teaches ownership, `Result`/`Option`,
   `serde_json::Value` navigation, and the clone-to-return pattern.
3. **Backend trait** - extract an async trait from the concrete
   implementation. This is where async trait mechanics (object safety,
   `Send` bounds) become relevant.
4. **REST API** - wire GET/PUT/PATCH/POST/DELETE to the backend trait
   through Axum routes. Path extraction from URL.
5. **Response cap** - enforce the 1MB limit.
6. **Queries** - by, order, from/to/eq, limit on collection nodes.
7. **Config** - environment variable parsing, add `tracing`.

## Composition with wicket

Hearth handles data. Wicket handles auth and access rules. They
compose naturally:

- Wicket sits in front of hearth as an auth layer.
- Wicket's path-based access rules map directly to hearth's path
  structure: a rule like `path: /data/user/{USER_ID}/**` with
  `if: user.name == USER_ID` restricts each user to their own data.
- Hearth itself is auth-unaware. It trusts that the layer in front
  has done its job. This keeps the two concerns cleanly separated.

## Build tooling

Uses [just](https://github.com/casey/just) for build recipes.
Introduced when there is something to build.

## Open questions

- **Validation:** should hearth validate writes against a schema, or
  is that a concern for a layer above it? Firebase has validation
  rules. Hearth could defer this to wicket's rule engine.
- **Events / real-time:** Firebase's killer feature is real-time
  subscriptions via WebSocket. Out of scope for v0 but worth keeping
  in mind so the backend trait doesn't preclude it.
- **Shard depth:** v0 shards by the first segment under `/data/`
  (depth 1), so everything under `/data/user/` lands in one file
  and one lock. A depth of 2 would shard by the second segment
  instead (`alice.json`, `bob.json`), giving better concurrency
  when many users write simultaneously. This could be a global
  config option or even per-prefix. Worth considering before the
  data model solidifies.
- **Reserved key prefix:** if atomic operations are added later, the
  `_` prefix would be reserved for operation keys (`_increment`,
  `_serverTimestamp`). This means user data could not have keys
  starting with `_`. Alternative: use a different encoding for
  operations (a header, a path suffix, a wrapper object).

## Future extensions

Features deferred from v0. The current design does not preclude any
of these - the per-shard locking and backend trait are the foundation
they build on.

**Atomic operations.** Server-side transforms without the client
needing to know the current value. Increment a counter, set a server
timestamp, union/remove from an array, conditional write (optimistic
concurrency). These are read-modify-write under the existing write
lock for JSON-on-disk, or native operations for backends that support
them (SQLite, Firestore). The main design decision is how to signal
an atomic op vs a normal write - options include a `_`-prefixed key
convention, a separate endpoint, or a content-type header.

**Cursor pagination.** Query responses return a cursor token for the
next page. The client passes `from` with the cursor value plus
`limit` to get the next page. Requires stable ordering across
requests and handling of documents deleted between pages.

**Collection schema.** A declaration of which paths are queryable,
guiding index creation for backends that need it (SQLite, S3). Not
needed for JSON-on-disk where any object node can be queried by
scanning in memory.

**Multi-path updates.** Write to multiple paths atomically. Either all
writes succeed or none do. Straightforward within a single shard
(one lock), harder across shards.

**Transactions.** Atomic read-then-write: read a value, compute a new
value, write it back, retry if the value changed. A higher-level
primitive than conditional writes.

**SQLite backend.** The JSON tree stored in SQLite. Gives indexing,
better query performance, and ACID transactions. The `rusqlite` crate
is mature.

**S3 backend.** For read-heavy, write-rarely workloads. Each shard is
an S3 object. Reads served from an in-memory cache, invalidated on
write.

**Firestore import/export.** Serialise the tree into Firestore's
document/collection model and back.

**CORS.** Required when browser-based apps on different origins talk
to hearth. `tower-http` provides an Axum-compatible CORS layer.

**Static file serving.** Hearth is a data store, not a file server.
A companion process (e.g. `servedir`, nginx, or a future wicket
feature) serves static assets. If co-hosting is ever wanted, Axum
can serve a directory at `/` alongside the data API.
