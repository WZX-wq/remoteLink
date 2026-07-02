#!/usr/bin/env bash
set -euo pipefail

triplet="${VCPKG_TRIPLET:-arm64-ios}"
if [[ -z "${VCPKG_ROOT:-}" ]]; then
  echo "VCPKG_ROOT is required" >&2
  exit 1
fi

installed_root="${VCPKG_INSTALLED_ROOT:-$VCPKG_ROOT/installed}"
lib_dir="$installed_root/$triplet/lib"
include_dir="$installed_root/$triplet/include"

check_header() {
  local header="$1"
  local path="$include_dir/$header"
  if [[ ! -f "$path" ]]; then
    echo "Missing vcpkg header: $path" >&2
    exit 1
  fi
  echo "Found vcpkg header: $path"
}

check_archive_platform() {
  local archive="$1"
  local preferred_member_pattern="${2:-}"

  if [[ ! -f "$archive" ]]; then
    echo "Missing vcpkg archive: $archive" >&2
    exit 1
  fi

  echo "Checking iOS object platform in $archive"
  local member=""
  if [[ -n "$preferred_member_pattern" ]]; then
    member="$(ar -t "$archive" | tr -d '\r' | grep -E -m 1 "$preferred_member_pattern" || true)"
  fi
  if [[ -z "$member" ]]; then
    member="$(ar -t "$archive" | tr -d '\r' | grep -E -m 1 '\.o$' || true)"
  fi
  if [[ -z "$member" ]]; then
    echo "No object member found in $archive" >&2
    exit 1
  fi

  local tmp
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    ar -x "$archive" "$member"
  )
  local obj="$tmp/$member"
  if [[ ! -f "$obj" ]]; then
    obj="$(find "$tmp" -type f -name '*.o' | head -n 1)"
  fi
  if [[ -z "$obj" || ! -f "$obj" ]]; then
    echo "Failed to extract $member from $archive" >&2
    exit 1
  fi

  file "$obj"
  local otool_out="$tmp/otool.txt"
  otool -l "$obj" | tee "$otool_out"
  if grep -Eq 'LC_VERSION_MIN_MACOSX|platform MACOS' "$otool_out"; then
    echo "Archive $archive contains a macOS object ($member), not an iOS object." >&2
    exit 1
  fi
  if grep -Eq 'LC_VERSION_MIN_IPHONEOS|platform IOS' "$otool_out"; then
    echo "Archive $archive contains iOS object metadata."
  else
    echo "Warning: no explicit iOS platform metadata found in $member; continuing after confirming it is not macOS."
  fi
}

echo "VCPKG_ROOT=$VCPKG_ROOT"
echo "VCPKG_INSTALLED_ROOT=$installed_root"
echo "VCPKG_TRIPLET=$triplet"
echo "SDKROOT=${SDKROOT:-}"
test -d "$lib_dir" || {
  echo "Missing vcpkg lib directory: $lib_dir" >&2
  exit 1
}

check_archive_platform "$lib_dir/libyuv.a" 'convert_argb\.cc\.o$'
check_archive_platform "$lib_dir/libvpx.a" '\.o$'
check_header 'opus/opus_multistream.h'
check_archive_platform "$lib_dir/libopus.a" '\.o$'

echo "iOS vcpkg native library verification passed"
