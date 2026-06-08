#!/usr/bin/env bash

set -euo pipefail

MODE="${MODE:-release}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-21}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_DIR="${ROOT_DIR}/flutter"
JNI_DIR="${FLUTTER_DIR}/android/app/src/main/jniLibs/${ANDROID_ABI}"

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "ANDROID_NDK_HOME is required" >&2
  exit 1
fi

export ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME}}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME}}"

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

rustup target add "${RUST_TARGET}"
bash "${NDK_SCRIPT}"

mkdir -p "${JNI_DIR}"
cp "target/${RUST_TARGET}/release/liblibrustdesk.so" "${JNI_DIR}/librustdesk.so"
cp "${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/${NDK_LIB_DIR}/libc++_shared.so" "${JNI_DIR}/"
"${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" "${JNI_DIR}/librustdesk.so"
"${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" "${JNI_DIR}/libc++_shared.so"

test -s "${JNI_DIR}/librustdesk.so"
test -s "${JNI_DIR}/libc++_shared.so"

cd "${FLUTTER_DIR}"

extra_args=()
if [[ "${MODE}" == "release" ]]; then
  extra_args+=(--obfuscate --split-debug-info ./split-debug-info)
fi

flutter build apk --split-per-abi --target-platform "${FLUTTER_TARGET}" "--${MODE}" "${extra_args[@]}"
flutter build appbundle --target-platform "${FLUTTER_TARGET}" "--${MODE}" "${extra_args[@]}"

apk_path="build/app/outputs/flutter-apk/app-arm64-v8a-${MODE}.apk"
aab_path="$(find build/app/outputs -name '*.aab' | sort | tail -n 1)"

jar tf "${apk_path}" | grep -q '^lib/arm64-v8a/librustdesk\.so$'
jar tf "${apk_path}" | grep -q '^lib/arm64-v8a/libc++_shared\.so$'
jar tf "${aab_path}" | grep -q '^base/lib/arm64-v8a/librustdesk\.so$'
jar tf "${aab_path}" | grep -q '^base/lib/arm64-v8a/libc++_shared\.so$'

echo "Built ${apk_path}"
echo "Built ${aab_path}"
