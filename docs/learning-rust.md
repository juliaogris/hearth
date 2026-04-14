# Learning Rust with hearth

First time ever writing Rust. The plan is to build hearth step by step,
learning the language through a real project rather than exercises.

Claude generates most of the code, but I run all commands myself in the
terminal (`cargo init`, `cargo build`, `cargo test`, etc.) and read
through each generated file before moving on. The goal is to understand
what the code does and why, not to type it all from scratch.

## Checklist

Each step matches the build order in [DESIGN.md](DESIGN.md). Items
within a step are the Rust concepts that step introduces.

### Step 1: Skeleton

- [ ] Run `cargo init`, look at the generated files (`Cargo.toml`,
  `src/main.rs`)
- [ ] Add dependencies to `Cargo.toml` (`axum`, `tokio`, `serde`,
  `serde_json`, `thiserror`, `uuid`)
- [ ] Write a `main` function that starts an Axum server
- [ ] Add a `GET /health` handler returning `{"ok": true}`
- [ ] Run `cargo build`, `cargo run`, `cargo clippy -- -D warnings`
- [ ] Set up a `justfile` with build, run, lint, and test recipes

**Rust concepts:** crate structure, `Cargo.toml`, `fn main`,
`async`/`await` basics, the `#[tokio::main]` macro, basic types
(`String`, `&str`), `println!`.

### Step 2: JSON-on-disk storage

- [ ] Create a `Store` struct holding a data directory path
- [ ] Implement `read`: load a JSON file, navigate to a path, return
  the subtree
- [ ] Implement `write`: navigate to parent path, insert value, write
  file back atomically (write temp file, rename)
- [ ] Implement `merge`: shallow merge of top-level keys
- [ ] Implement `create`: generate a UUID v7 key, insert child
- [ ] Implement `delete`: remove subtree, write file back
- [ ] Add per-shard file layout (one JSON file per top-level segment)
- [ ] Add per-shard `tokio::sync::RwLock`
- [ ] Write tests with `#[tokio::test]` and temp directories

**Rust concepts:** ownership and borrowing (`&`, `&mut`, moves),
`Result<T, E>` and the `?` operator, `Option<T>`, pattern matching
(`match`, `if let`), `serde_json::Value` navigation, `Clone` and when
you need it, `String` vs `&str` in practice, `Vec`, `HashMap`,
closures (for lock map), `tokio::fs` for async file I/O, writing tests.

### Step 3: Backend trait

- [ ] Define an async `Backend` trait with methods for read, write,
  merge, create, delete, query
- [ ] Implement the trait for the `Store` struct
- [ ] Use `Arc<dyn Backend>` (or generics) in the app state
- [ ] Understand why `Send + Sync` bounds are needed

**Rust concepts:** traits (Rust's answer to Go interfaces), async
traits, `dyn Trait` vs generics, `Arc` and `Send + Sync`, object
safety rules, the difference between static and dynamic dispatch.

### Step 4: REST API

- [ ] Wire `GET /data/*path` to backend `read`
- [ ] Wire `PUT /data/*path` to backend `write`
- [ ] Wire `PATCH /data/*path` to backend `merge`
- [ ] Wire `POST /data/*path` to backend `create`
- [ ] Wire `DELETE /data/*path` to backend `delete`
- [ ] Extract the path from the URL and split into segments
- [ ] Parse JSON request bodies, return proper error responses
- [ ] Write integration tests that hit the HTTP endpoints

**Rust concepts:** Axum extractors (`Path`, `Json`, `State`), error
handling with custom error types and `IntoResponse`, HTTP status codes,
routing, how Axum's type system enforces handler signatures.

### Step 5: Response cap

- [ ] Check serialised response size before sending
- [ ] Return `413` if the response exceeds 1 MB
- [ ] Write a test with a large subtree

**Rust concepts:** byte length of serialised data, middleware vs
inline checks, when to use `Bytes` vs `String`.

### Step 6: Queries

- [ ] Parse query parameters (`by`, `order`, `from`, `to`, `eq`,
  `limit`)
- [ ] Sort children by the requested field
- [ ] Apply filters and limits
- [ ] Return `400` for queries on non-object nodes
- [ ] Write tests for each query combination

**Rust concepts:** `Ord` and sorting, iterators (`filter`, `take`,
`collect`), `serde` deserialization for query params, enums for
query options, more pattern matching.

### Step 7: Config and tracing

- [ ] Parse environment variables into config structs
- [ ] Add `tracing` and `tracing-subscriber` for structured logging
- [ ] Log requests, errors, and startup info
- [ ] Write tests for config parsing

**Rust concepts:** `std::env`, `From`/`Into` conversions, the
`tracing` ecosystem, structured logging, `Display` trait for
custom types.
