#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
simulator_triplet="$repo_dir/res/vcpkg/triplets/arm64-ios-simulator.cmake"
libvpx_port="$repo_dir/res/vcpkg/libvpx/portfile.cmake"
libvpx_simulator_patch="$repo_dir/res/vcpkg/libvpx/0005-enable-arm64-ios-simulator.patch"
verify_script="$repo_dir/scripts/ci/verify-ios-vcpkg-libraries.sh"
vcpkg_manifest="$repo_dir/vcpkg.json"
magnum_opus_build="$repo_dir/libs/magnum-opus/build.rs"
static_prep_script="$repo_dir/scripts/ci/prepare-ios-rust-static-libs.sh"

require_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Eq "$pattern" "$path"; then
    echo "$message" >&2
    exit 1
  fi
}

if [[ ! -f "$simulator_triplet" ]]; then
  echo "Missing project-owned iOS Simulator vcpkg triplet." >&2
  exit 1
fi

require_contains "$simulator_triplet" 'VCPKG_CMAKE_SYSTEM_NAME iOS' \
  'Simulator triplet must target iOS.'
require_contains "$simulator_triplet" 'VCPKG_OSX_SYSROOT iphonesimulator' \
  'Simulator triplet must select the iPhoneSimulator SDK.'
require_contains "$libvpx_port" 'VCPKG_OSX_SYSROOT STREQUAL "iphonesimulator"' \
  'libvpx must distinguish the Simulator SDK from iPhoneOS.'
require_contains "$libvpx_port" 'arm64-iphonesimulator-gcc' \
  'libvpx must use its arm64 iPhoneSimulator target.'
if [[ ! -f "$libvpx_simulator_patch" ]]; then
  echo 'Missing persistent libvpx arm64 iOS Simulator patch.' >&2
  exit 1
fi
require_contains "$libvpx_port" '0005-enable-arm64-ios-simulator.patch' \
  'libvpx overlay port must apply the arm64 iOS Simulator patch.'
require_contains "$libvpx_simulator_patch" 'arm64-iphonesimulator-gcc' \
  'libvpx patch must declare the arm64 iPhoneSimulator target.'
require_contains "$libvpx_simulator_patch" 'sim_arch="-arch arm64"' \
  'libvpx patch must select arm64 for iPhoneSimulator builds.'
require_contains "$libvpx_simulator_patch" 'xcrun --sdk iphonesimulator --find' \
  'libvpx patch must select iPhoneSimulator developer tools.'
require_contains "$libvpx_simulator_patch" 'mios-simulator-version-min' \
  'libvpx patch must link against the iOS Simulator platform.'
require_contains "$verify_script" 'ios-simulator' \
  'The native-library verifier must recognize iOS Simulator triplets.'
require_contains "$verify_script" 'IOSSIMULATOR' \
  'The native-library verifier must validate Simulator object metadata.'
require_contains "$vcpkg_manifest" '"platform": "android \| ios"' \
  'libsodium must be declared for iOS so Simulator builds can link it from vcpkg.'
if [[ ! -f "$magnum_opus_build" ]]; then
  echo 'Missing project-owned magnum-opus build patch for iOS Simulator.' >&2
  exit 1
fi
require_contains "$magnum_opus_build" 'target_triple\.ends_with\("-ios-sim"\)' \
  'magnum-opus must resolve the iOS Simulator vcpkg triplet from the Rust target.'
require_contains "$magnum_opus_build" 'VCPKG_INSTALLED_ROOT' \
  'magnum-opus must honor the configured vcpkg installed root.'

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
tmp_target="$tmp_root/target/aarch64-apple-ios-sim/release"
tmp_vcpkg="$tmp_root/vcpkg"
mkdir -p "$tmp_target" "$tmp_vcpkg/installed/arm64-ios-simulator/lib"
touch "$tmp_target/liblibrustdesk.a" "$tmp_vcpkg/installed/arm64-ios-simulator/lib/libjpeg.a"
(
  cd "$tmp_root"
  VCPKG_ROOT="$tmp_vcpkg" bash "$static_prep_script" "$tmp_target"
)
if [[ ! -f "$tmp_target/libjpeg.a" ]]; then
  echo 'Static-library preparation must copy Simulator libjpeg.a for an iOS Simulator Rust target.' >&2
  exit 1
fi

echo 'KQ iOS Simulator vcpkg configuration checks passed'
