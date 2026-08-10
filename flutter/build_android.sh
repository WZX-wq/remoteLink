#!/usr/bin/env bash

set -euo pipefail

MODE="${MODE:-release}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-21}"
ANDROID_BUILD_NUMBER="${ANDROID_BUILD_NUMBER:-4068}"
ANDROID_RELEASE_MIN_VERSION_CODE="${KQ_ANDROID_MIN_VERSION_CODE:-4067}"
ANDROID_RELEASE_EXPECTED_SIGNER_SHA256="${KQ_ANDROID_EXPECTED_CERT_SHA256:-f9111b87482946b01d90f433b8b00dcf94cec08728891a7d9b5d08150c6caf17}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT_DIR}/flutter/android_release_publish.sh"
FLUTTER_DIR="${ROOT_DIR}/flutter"
JNI_DIR="${FLUTTER_DIR}/android/app/src/main/jniLibs/${ANDROID_ABI}"

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

detect_ndk_host_tag() {
  local prebuilt_dir="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt"
  local uname_s uname_m
  uname_s="$(uname -s 2>/dev/null || true)"
  uname_m="$(uname -m 2>/dev/null || true)"
  local candidates=()

  case "${uname_s}" in
    Linux*) candidates+=(linux-x86_64) ;;
    Darwin*)
      if [[ "${uname_m}" == "arm64" ]]; then
        candidates+=(darwin-arm64 darwin-x86_64)
      else
        candidates+=(darwin-x86_64 darwin-arm64)
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) candidates+=(windows-x86_64) ;;
  esac

  candidates+=(linux-x86_64 windows-x86_64 darwin-arm64 darwin-x86_64)
  local tag
  for tag in "${candidates[@]}"; do
    if [[ -d "${prebuilt_dir}/${tag}" ]]; then
      echo "${tag}"
      return 0
    fi
  done

  echo "Unable to find an Android NDK LLVM prebuilt directory under ${prebuilt_dir}" >&2
  ls -1 "${prebuilt_dir}" >&2 || true
  return 1
}

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "ANDROID_NDK_HOME is required" >&2
  exit 1
fi

export ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME}}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME}}"
NDK_HOST_TAG="$(detect_ndk_host_tag)"
NDK_PREBUILT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}"
LLVM_STRIP="${NDK_PREBUILT}/bin/llvm-strip"
if [[ ! -x "${LLVM_STRIP}" && -x "${LLVM_STRIP}.exe" ]]; then
  LLVM_STRIP="${LLVM_STRIP}.exe"
fi
if [[ ! -x "${LLVM_STRIP}" ]]; then
  echo "llvm-strip was not found in ${NDK_PREBUILT}/bin" >&2
  exit 1
fi

case "${ANDROID_ABI}" in
  arm64-v8a)
    RUST_TARGET="aarch64-linux-android"
    FLUTTER_TARGET="android-arm64"
    NDK_LIB_DIR="aarch64-linux-android"
    NDK_SCRIPT="${FLUTTER_DIR}/ndk_arm64.sh"
  ;;
  *)
    echo "Unsupported ANDROID_ABI '${ANDROID_ABI}'. Current local package path supports arm64-v8a first." >&2
    exit 1
  ;;
esac

cd "${ROOT_DIR}"

if [[ -z "${VCPKG_ROOT:-}" ]]; then
  echo "VCPKG_ROOT is required for the Android RustDesk native build" >&2
  exit 1
fi

./flutter/build_android_deps.sh "${ANDROID_ABI}"

SODIUM_LIB_DIR="${VCPKG_ROOT}/installed/arm64-android/lib"
if [[ -f "${SODIUM_LIB_DIR}/libsodium.a" && ! -f "${SODIUM_LIB_DIR}/liblibsodium.a" ]]; then
  cp "${SODIUM_LIB_DIR}/libsodium.a" "${SODIUM_LIB_DIR}/liblibsodium.a"
fi
export SODIUM_LIB_DIR

rustup target add "${RUST_TARGET}"
bash "${NDK_SCRIPT}"

mkdir -p "${JNI_DIR}"
cp "target/${RUST_TARGET}/release/liblibrustdesk.so" "${JNI_DIR}/librustdesk.so"
cp "${NDK_PREBUILT}/sysroot/usr/lib/${NDK_LIB_DIR}/libc++_shared.so" "${JNI_DIR}/"
"${LLVM_STRIP}" "${JNI_DIR}/librustdesk.so"
"${LLVM_STRIP}" "${JNI_DIR}/libc++_shared.so"

test -s "${JNI_DIR}/librustdesk.so"
test -s "${JNI_DIR}/libc++_shared.so"

cd "${FLUTTER_DIR}"

flutter_pubspec_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
ANDROID_BUILD_NAME="${ANDROID_BUILD_NAME:-${flutter_pubspec_version%%+*}}"
if [[ -z "${ANDROID_BUILD_NAME}" || ! "${ANDROID_BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo 'ANDROID_BUILD_NAME and ANDROID_BUILD_NUMBER must define a valid Android version' >&2
  exit 1
fi
ANDROID_RELEASE_VERSION="${ANDROID_BUILD_NAME}+${ANDROID_BUILD_NUMBER}"

extra_args=()
if [[ "${MODE}" == "release" ]]; then
  extra_args+=(--obfuscate --split-debug-info ./split-debug-info)
fi

flutter build apk --target-platform "${FLUTTER_TARGET}" "--${MODE}" --build-name "${ANDROID_BUILD_NAME}" --build-number "${ANDROID_BUILD_NUMBER}" "${extra_args[@]}"
flutter build appbundle --target-platform "${FLUTTER_TARGET}" "--${MODE}" --build-name "${ANDROID_BUILD_NAME}" --build-number "${ANDROID_BUILD_NUMBER}" "${extra_args[@]}"

apk_path="build/app/outputs/flutter-apk/app-${MODE}.apk"
aab_path="$(find build/app/outputs -name '*.aab' | sort | tail -n 1)"

jar tf "${apk_path}" | grep -q '^lib/arm64-v8a/librustdesk\.so$'
jar tf "${apk_path}" | grep -q '^lib/arm64-v8a/libc++_shared\.so$'
jar tf "${aab_path}" | grep -q '^base/lib/arm64-v8a/librustdesk\.so$'
jar tf "${aab_path}" | grep -q '^base/lib/arm64-v8a/libc++_shared\.so$'

echo "Built ${apk_path}"
echo "Built ${aab_path}"

published_apk_path="${ROOT_DIR}/server/public/downloads/Kunqiong-Remote-Desktop.apk"
publish_verified_android_apk_if_release "${MODE}" "${apk_path}" "${published_apk_path}" "${ANDROID_RELEASE_VERSION}" "${ANDROID_RELEASE_MIN_VERSION_CODE}" "${ANDROID_RELEASE_EXPECTED_SIGNER_SHA256}"
