# hearth

A tree-shaped data store addressed by paths.

Hearth is a JSON data store with a REST API, inspired by Firebase
Realtime Database. Data lives in a single conceptual JSON tree,
addressed by URL paths. Backends are pluggable - starting with
JSON-on-disk, with SQLite planned.

## Example paths

```
/data/user/alice/profile
/data/user/alice/progress
/data/user/alice/course/rust-101/test/midterm/score
/data/user/alice/project/hearth/metadata
```

## Goals

**v0: JSON-on-disk**

- REST API for reading and writing JSON subtrees by path
- JSON files on disk, sharded per top-level path segment, with
  per-shard locking
- 1MB response cap per request
- Firebase-style queries: order by one field, filter, limit

**Future**

- Atomic operations: increment, server timestamp, array union/remove,
  conditional write
- Cursor pagination for queries
- Multi-path updates: write to several paths atomically
- Transactions: atomic read-then-write
- SQLite backend
- S3 backend for read-heavy workloads
- Firestore import/export
- CORS support for browser-based clients
- Compose with [wicket](https://github.com/juliaogris/wicket) for
  auth and path-based access rules

## Development

Requires [just](https://github.com/casey/just) for task running when
there is something to build.

## License

MIT
