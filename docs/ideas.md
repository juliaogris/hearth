# Ideas

Things deferred from v0. The current design does not preclude any of
these - the per-shard locking and backend trait are the foundation
they build on.

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
- **Query default param:** a `default` query param could substitute
  a value for children missing the `by` field, so they sort into a
  known position instead of being skipped.
- **Firebase as backend:** hearth's query model is a subset of what
  Firebase Realtime Database supports, so Firebase works as a
  backend. This constrains future query additions - hearth cannot
  add query features that Firebase cannot express.

## Method override header

Support `X-HTTP-Method-Override: PATCH` on POST requests as a
fallback for networks where PATCH is blocked by proxies. An Axum
middleware rewrites the method before routing. Only applies to POST
- never override on GET. The client discovers the need by observing
a failed PATCH, not through auto-negotiation.

## Conditional write

`PUT` with an `If-None-Match: *` header creates a value only if the
path does not already exist, returning `409 Conflict` otherwise.
Atomic under the per-shard write lock. The primary use case is
claiming a unique name (e.g. a username) without a race condition.
Could land before the full atomic operations feature since it is a
simple check-then-write under an existing lock.

## Atomic operations

Server-side transforms without the client needing to know the current
value. Increment a counter, set a server timestamp, union/remove from
an array. These are read-modify-write under the existing write lock
for JSON-on-disk, or native operations for backends that support them
(SQLite, Firestore). The main design decision is how to signal an
atomic op vs a normal write - options include a `_`-prefixed key
convention, a separate endpoint, or a content-type header.

## Secondary indexes

Hearth does not enforce uniqueness on field values. When a record is
keyed by ID but needs lookup by a unique field (e.g. username), the
client maintains a secondary index as a separate path:
`PUT /data/username/alice {"user": "019078e4-..."}`. The conditional
write feature protects uniqueness at the index path. Multi-path
atomic updates would keep the primary record and index in sync.

## Write IDs / WAL

Every write gets a monotonic ID, forming a write-ahead log. This
unlocks sync ("give me everything since write 4527"), undo (replay
the log up to a point), audit trails, and conflict resolution if
the single-writer constraint is ever relaxed. Can be retrofitted:
the backend trait's write/merge/delete methods start returning a
write ID, and the storage layer appends to a log alongside the
current state. Existing data without write history has no log entries
before the migration point. The read path does not change.

## Cursor pagination

Query responses return a cursor token for the next page. The client
passes `from` with the cursor value plus `limit` to get the next
page. Requires stable ordering across requests and handling of
documents deleted between pages.

## Collection schema

A declaration of which paths are queryable, guiding index creation
for backends that need it (SQLite, S3). Not needed for JSON-on-disk
where any object node can be queried by scanning in memory.

## Multi-path updates

Write to multiple paths atomically. Either all writes succeed or
none do. Straightforward within a single shard (one lock), harder
across shards.

## Transactions

Atomic read-then-write: read a value, compute a new value, write it
back, retry if the value changed. A higher-level primitive than
conditional writes.

## SQLite backend

The JSON tree stored in SQLite. Gives indexing, better query
performance, and ACID transactions. The `rusqlite` crate is mature.

## S3 backend

For read-heavy, write-rarely workloads. Each shard is an S3 object.
Reads served from an in-memory cache, invalidated on write.

## Edge deployment

Run hearth on edge nodes with S3 (or GCS) as durable storage. On
session start, the user's shard is loaded into memory on the edge
node. Reads and writes hit local memory. Writes flush to object
storage asynchronously, with backpressure: if unconfirmed writes
exceed a threshold (count or bytes), the next write blocks until
storage confirms. Session affinity at the load balancer ensures one
edge node owns a shard at a time, avoiding multi-writer conflicts
without distributed locking. Hearth's per-shard model maps
naturally - the shard is the unit of loading, caching, and eviction.

## Firestore import/export

Serialise the tree into Firestore's document/collection model and
back.

## CORS

Required when browser-based apps on different origins talk to hearth.
`tower-http` provides an Axum-compatible CORS layer.

## Static file serving

Hearth is a data store, not a file server. A companion process (e.g.
`servedir`, nginx, or a future wicket feature) serves static assets.
If co-hosting is ever wanted, Axum can serve a directory at `/`
alongside the data API.
