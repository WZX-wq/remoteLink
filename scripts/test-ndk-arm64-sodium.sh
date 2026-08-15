#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

ndk_home="${temp_dir}/ndk"
host_tag="darwin-arm64"
ndk_bin_dir="${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/bin"
fake_bin_dir="${temp_dir}/bin"
vcpkg_root="${temp_dir}/vcpkg"
capture_file="${temp_dir}/sodium-lib-dir"
target_dir="${temp_dir}/target"

mkdir -p \
  "${ndk_home}/toolchains/llvm/prebuilt/${host_tag}/sysroot" \
  "${ndk_bin_dir}" \
  "${fake_bin_dir}" \
  "${vcpkg_root}/installed/arm64-android/lib"
touch "${vcpkg_root}/installed/arm64-android/lib/libsodium.a"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''%s\n'\'' "${SODIUM_LIB_DIR:-}" > "${SODIUM_CAPTURE_FILE}"' \
  'mkdir -p "${CARGO_TARGET_DIR}/aarch64-linux-android/release"' \
  'touch "${CARGO_TARGET_DIR}/aarch64-linux-android/release/liblibrustdesk.so"' \
  > "${fake_bin_dir}/cargo"
chmod +x "${fake_bin_dir}/cargo"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${REPORT_UNDEFINED_SODIUM:-0}" == "1" ]]; then' \
  '  printf '\''                 U sodium_base64_encoded_len\n'\''' \
  'fi' \
  > "${ndk_bin_dir}/llvm-nm"
chmod +x "${ndk_bin_dir}/llvm-nm"

ANDROID_NDK_HOME="${ndk_home}" \
VCPKG_ROOT="${vcpkg_root}" \
SODIUM_CAPTURE_FILE="${capture_file}" \
CARGO_TARGET_DIR="${target_dir}" \
PATH="${fake_bin_dir}:${PATH}" \
"${root_dir}/flutter/ndk_arm64.sh"

expected_sodium_dir="${vcpkg_root}/installed/arm64-android/lib"
test "$(<"${capture_file}")" = "${expected_sodium_dir}"

if ANDROID_NDK_HOME="${ndk_home}" \
  VCPKG_ROOT="${vcpkg_root}" \
  SODIUM_CAPTURE_FILE="${capture_file}" \
  CARGO_TARGET_DIR="${target_dir}" \
  REPORT_UNDEFINED_SODIUM=1 \
  PATH="${fake_bin_dir}:${PATH}" \
  "${root_dir}/flutter/ndk_arm64.sh" \
  >"${temp_dir}/stdout" 2>"${temp_dir}/stderr"; then
  echo "ndk_arm64.sh accepted a library with undefined sodium symbols" >&2
  exit 1
fi

grep -q "undefined libsodium symbols" "${temp_dir}/stderr"
