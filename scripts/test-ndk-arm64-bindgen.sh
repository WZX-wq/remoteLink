#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

ndk_home="${temp_dir}/ndk"
host_tag="darwin-arm64"
bin_dir="${temp_dir}/bin"
capture_file="${temp_dir}/bindgen-args"
vcpkg_root="${temp_dir}/vcpkg"
target_dir="${temp_dir}/target"

mkdir -p \
  "${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/sysroot" \
  "${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/bin" \
  "${bin_dir}" \
  "${vcpkg_root}/installed/arm64-android/lib"
touch "${vcpkg_root}/installed/arm64-android/lib/libsodium.a"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "${BINDGEN_EXTRA_CLANG_ARGS:-}" > "${BINDGEN_CAPTURE_FILE}"' \
  'mkdir -p "${CARGO_TARGET_DIR}/aarch64-linux-android/release"' \
  'touch "${CARGO_TARGET_DIR}/aarch64-linux-android/release/liblibrustdesk.so"' \
  > "${bin_dir}/cargo"
chmod +x "${bin_dir}/cargo"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit 0' \
  > "${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/bin/llvm-nm"
chmod +x "${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/bin/llvm-nm"

ANDROID_NDK_HOME="${ndk_home}" \
VCPKG_ROOT="${vcpkg_root}" \
BINDGEN_CAPTURE_FILE="${capture_file}" \
CARGO_TARGET_DIR="${target_dir}" \
PATH="${bin_dir}:${PATH}" \
"${root_dir}/flutter/ndk_arm64.sh"

expected="--target=aarch64-linux-android21 --sysroot=${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/sysroot"
test "$(<"${capture_file}")" = "${expected}"
