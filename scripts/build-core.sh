#!/usr/bin/env bash
# Compile le cœur Rust pour iPhone (arm64).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/core"

if ! rustup target list --installed | grep -qx "aarch64-apple-ios"; then
  echo "==> Installation de la cible Rust aarch64-apple-ios"
  rustup target add aarch64-apple-ios
fi

echo "==> Compilation du cœur Rust (release, aarch64-apple-ios)"
cargo build --release --target aarch64-apple-ios
