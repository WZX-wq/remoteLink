#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:-target/aarch64-apple-ios/release}"
vcpkg_triplet="${VCPKG_TRIPLET:-arm64-ios}"
vcpkg_installed_root="${VCPKG_INSTALLED_ROOT:-}"

if [ ! -f "$target_dir/liblibrustdesk.a" ]; then
  echo "::error::Missing Rust iOS static library: $target_dir/liblibrustdesk.a" >&2
  exit 1
fi

if [ -z "$vcpkg_installed_root" ] && [ -n "${VCPKG_ROOT:-}" ]; then
  vcpkg_installed_root="$VCPKG_ROOT/installed"
fi

jpeg_lib=""
if [ -n "$vcpkg_installed_root" ]; then
  jpeg_lib="$vcpkg_installed_root/$vcpkg_triplet/lib/libjpeg.a"
fi
if [ -z "$jpeg_lib" ] || [ ! -f "$jpeg_lib" ]; then
  jpeg_lib="$(find "${VCPKG_ROOT:-.}" -path "*/$vcpkg_triplet/lib/libjpeg.a" -print -quit 2>/dev/null || true)"
fi
if [ -z "$jpeg_lib" ] || [ ! -f "$jpeg_lib" ]; then
  echo "::error::Missing iOS libjpeg.a from vcpkg for triplet $vcpkg_triplet." >&2
  echo "::error::Run vcpkg install --triplet $vcpkg_triplet before archiving." >&2
  exit 1
fi

cp "$jpeg_lib" "$target_dir/libjpeg.a"
echo "Prepared iOS Rust native static libs in $target_dir."
