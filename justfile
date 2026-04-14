default: build

build:
    cargo build

run:
    cargo run

test:
    cargo test

lint:
    cargo clippy -- -D warnings

fmt:
    cargo fmt

fmt-check:
    cargo fmt -- --check

check: fmt-check lint test
