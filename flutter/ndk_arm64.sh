#!/usr/bin/env bash
set -euo pipefail

ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-21}"
CARGO_FEATURES="${CARGO_FEATURES:-flutter,hwcodec,vram}"

cargo ndk --platform "${ANDROID_API_LEVEL}" --target aarch64-linux-android build --release --features "${CARGO_FEATURES}"
