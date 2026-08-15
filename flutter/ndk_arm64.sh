#!/usr/bin/env bash
set -euo pipefail

ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-21}"
CARGO_FEATURES="${CARGO_FEATURES:-flutter,mediacodec}"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "ANDROID_NDK_HOME is required" >&2
  exit 1
fi
if [[ -z "${VCPKG_ROOT:-}" ]]; then
  echo "VCPKG_ROOT is required" >&2
  exit 1
fi

SODIUM_LIB_DIR="${VCPKG_ROOT}/installed/arm64-android/lib"
if [[ ! -f "${SODIUM_LIB_DIR}/libsodium.a" ]]; then
  echo "Missing Android libsodium static library: ${SODIUM_LIB_DIR}/libsodium.a" >&2
  exit 1
fi
export SODIUM_LIB_DIR
unset SODIUM_SHARED SODIUM_USE_PKG_CONFIG SODIUM_STATIC

ndk_prebuilt_dir="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt"
case "$(uname -s)" in
  Darwin*) ndk_host_tags=(darwin-arm64 darwin-x86_64) ;;
  Linux*) ndk_host_tags=(linux-x86_64) ;;
  *)
    echo "Unsupported Android NDK host platform: $(uname -s)" >&2
    exit 1
  ;;
esac

ndk_host_dir=""
for ndk_host_tag in "${ndk_host_tags[@]}"; do
  if [[ -d "${ndk_prebuilt_dir}/${ndk_host_tag}/sysroot" ]]; then
    ndk_host_dir="${ndk_prebuilt_dir}/${ndk_host_tag}"
    break
  fi
done
if [[ -z "${ndk_host_dir}" ]]; then
  echo "Unable to find the Android NDK sysroot under ${ndk_prebuilt_dir}" >&2
  exit 1
fi
ndk_sysroot="${ndk_host_dir}/sysroot"
llvm_nm="${ndk_host_dir}/bin/llvm-nm"
if [[ ! -x "${llvm_nm}" && -x "${llvm_nm}.exe" ]]; then
  llvm_nm="${llvm_nm}.exe"
fi
if [[ ! -x "${llvm_nm}" ]]; then
  echo "llvm-nm was not found under ${ndk_host_dir}/bin" >&2
  exit 1
fi

export BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS:+${BINDGEN_EXTRA_CLANG_ARGS} }--target=aarch64-linux-android${ANDROID_API_LEVEL} --sysroot=${ndk_sysroot}"

cargo ndk --platform "${ANDROID_API_LEVEL}" --target aarch64-linux-android build --release --lib --features "${CARGO_FEATURES}"

target_dir="${CARGO_TARGET_DIR:-target}"
native_library="${target_dir}/aarch64-linux-android/release/liblibrustdesk.so"
if [[ ! -f "${native_library}" ]]; then
  echo "Missing Android native library after Cargo build: ${native_library}" >&2
  exit 1
fi

if ! nm_output="$("${llvm_nm}" -D "${native_library}")"; then
  echo "Unable to inspect Android native library: ${native_library}" >&2
  exit 1
fi
undefined_sodium_symbols="$(printf '%s\n' "${nm_output}" | grep -E '[[:space:]]U[[:space:]]+sodium_' || true)"
if [[ -n "${undefined_sodium_symbols}" ]]; then
  echo "Android native library contains undefined libsodium symbols:" >&2
  printf '%s\n' "${undefined_sodium_symbols}" >&2
  exit 1
fi
