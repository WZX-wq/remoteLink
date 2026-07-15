#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_MODE="${BUILD_MODE:-ios}"
BUILD_NAME="${FLUTTER_BUILD_NAME:-1.4.6}"
BUILD_NUMBER="${FLUTTER_BUILD_NUMBER:-4073}"
CARGO_TARGET="${CARGO_TARGET:-aarch64-apple-ios}"
FLUTTER_ARGS=(
  --release
  --build-name "$BUILD_NAME"
  --build-number "$BUILD_NUMBER"
)

cd "$SCRIPT_DIR"
flutter pub get

cd "$SCRIPT_DIR/ios"
pod install

cd "$REPO_DIR"
cargo build --features flutter --release --target "$CARGO_TARGET" --lib

cd "$SCRIPT_DIR"
case "$BUILD_MODE" in
  ios)
    flutter build ios "${FLUTTER_ARGS[@]}" --no-codesign
    ;;
  ipa)
    flutter build ipa "${FLUTTER_ARGS[@]}"
    ;;
  *)
    echo "Unsupported BUILD_MODE=$BUILD_MODE. Use ios or ipa." >&2
    exit 1
    ;;
esac
