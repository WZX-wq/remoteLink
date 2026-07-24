#!/usr/bin/env bash
set -euo pipefail

cargo build --features flutter,hwcodec --release --target aarch64-apple-ios --lib
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/ci/prepare-ios-rust-static-libs.sh" target/aarch64-apple-ios/release
