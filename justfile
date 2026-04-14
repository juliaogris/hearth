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

# Auto-bump patch version, tag, and create GitHub release.
release:
    #!/usr/bin/env bash
    set -euo pipefail
    nexttag=$({ { git tag --list --merged HEAD --sort=-v:refname; echo v0.0.0; } \
      | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+$" \
      | head -n 1 \
      | awk -F . '{ print $1 "." $2 "." $3 + 1 }'; } \
      | head -n 1)
    git tag "$nexttag"
    git push origin "$nexttag"
    gh release create "$nexttag" --generate-notes
