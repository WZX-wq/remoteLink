#!/usr/bin/env bash
set -Eeuo pipefail

STEP="${1:-}"
if [[ -z "${STEP}" ]]; then
  echo "Usage: $0 <step>" >&2
  exit 2
fi
shift || true

REPO_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
cd "${REPO_ROOT}"

CI_ARTIFACT_DIR="${CI_ARTIFACT_DIR:-artifacts/ci}"
PUBLIC_CI_DIR="${PUBLIC_CI_DIR:-/www/wwwroot/KQromoteLink/android/ci}"
CI_ENV_FILE="${CI_ENV_FILE:-${CI_ARTIFACT_DIR}/android-build.env}"
mkdir -p "${CI_ARTIFACT_DIR}"

publish_ci_file() {
  local file="$1"
  if [[ -s "${file}" ]] && mkdir -p "${PUBLIC_CI_DIR}" >/dev/null 2>&1; then
    cp "${file}" "${PUBLIC_CI_DIR}/latest-$(basename "${file}")" >/dev/null 2>&1 || true
  fi
}

selected_env() {
  for key in \
    GITHUB_RUN_ID \
    GITHUB_RUN_NUMBER \
    GITHUB_SHA \
    GITHUB_REF_NAME \
    FLUTTER_VERSION \
    RUST_VERSION \
    CARGO_NDK_VERSION \
    NDK_PACKAGE_VERSION \
    ANDROID_SDK_ROOT \
    ANDROID_NDK_HOME \
    ANDROID_ABI \
    ANDROID_API_LEVEL \
    BUILD_MODE \
    CARGO_FEATURES \
    VCPKG_ROOT \
    FLUTTER_ROOT; do
    local value=""
    if [[ -v "${key}" ]]; then
      value="${!key}"
    fi
    printf '%s=%s\n' "${key}" "${value}"
  done
}

tool_versions() {
  uname -a || true
  df -h . || true
  for tool in git curl unzip zip python3 cmake ninja pkg-config clang g++ java javac rustup cargo flutter sdkmanager jar; do
    if command -v "${tool}" >/dev/null 2>&1; then
      echo "${tool}: $(command -v "${tool}")"
      case "${tool}" in
        java|javac) "${tool}" -version 2>&1 | head -n 2 || true ;;
        flutter) "${tool}" --version 2>&1 | head -n 6 || true ;;
        sdkmanager) "${tool}" --version 2>&1 | head -n 2 || true ;;
        *) "${tool}" --version 2>&1 | head -n 2 || true ;;
      esac
    else
      echo "${tool}: missing"
    fi
  done
}

collect_vcpkg_logs() {
  if [[ -n "${VCPKG_ROOT:-}" && -d "${VCPKG_ROOT}/buildtrees" ]]; then
    find "${VCPKG_ROOT}/buildtrees" -name '*.log' -type f | sort | tail -n 12 | while read -r log_file; do
      echo ""
      echo "===== ${log_file} ====="
      tail -n 220 "${log_file}" || true
    done
  fi
}

on_error() {
  local line="$1"
  local status="$2"
  trap - ERR
  local failure_file="${CI_ARTIFACT_DIR}/CI_FAILURE_STEP.txt"
  {
    echo "step=${STEP}"
    echo "line=${line}"
    echo "exit_status=${status}"
    echo "time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "## Selected environment"
    selected_env
    echo ""
    echo "## Tool versions"
    tool_versions
    echo ""
    echo "## Recent vcpkg logs"
    collect_vcpkg_logs
  } > "${failure_file}" 2>&1 || true
  publish_ci_file "${failure_file}"
  echo "Android CI step failed: ${STEP}. Diagnostic file: ${failure_file}" >&2
}

trap 'status=$?; on_error "$LINENO" "$status"; exit "$status"' ERR

find_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    echo "${JAVA_HOME}"
    return 0
  fi

  local java_bin
  java_bin="$(command -v java 2>/dev/null || true)"
  if [[ -n "${java_bin}" ]]; then
    java_bin="$(readlink -f "${java_bin}" 2>/dev/null || echo "${java_bin}")"
    dirname "$(dirname "${java_bin}")"
    return 0
  fi

  local found
  found="$(find /usr/lib/jvm -maxdepth 3 -type f -path '*/bin/java' 2>/dev/null | sort | head -n 1 || true)"
  if [[ -n "${found}" ]]; then
    dirname "$(dirname "${found}")"
  fi
}

setup_common_env() {
  export FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
  export RUST_VERSION="${RUST_VERSION:-1.75}"
  export CARGO_NDK_VERSION="${CARGO_NDK_VERSION:-3.1.2}"
  export NDK_PACKAGE_VERSION="${NDK_PACKAGE_VERSION:-28.2.13676358}"
  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/artifacts/android-sdk}"
  export ANDROID_HOME="${ANDROID_SDK_ROOT}"
  export ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-21}"
  export ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
  export BUILD_MODE="${BUILD_MODE:-release}"
  export CARGO_FEATURES="${CARGO_FEATURES:-flutter,hwcodec}"
  export VCPKG_COMMIT_ID="${VCPKG_COMMIT_ID:-120deac3062162151622ca4860575a33844ba10b}"
  export VCPKG_ROOT="${VCPKG_ROOT:-/opt/artifacts/vcpkg}"
  export FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/artifacts/flutter/${FLUTTER_VERSION}}"
  export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
  export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
  export ANDROID_JNI_LIB_DIR="${ANDROID_JNI_LIB_DIR:-flutter/android/app/src/main/jniLibs}"

  local java_home
  java_home="$(find_java_home || true)"
  if [[ -n "${java_home}" ]]; then
    export JAVA_HOME="${java_home}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
  fi

  export ANDROID_NDK_HOME="${ANDROID_SDK_ROOT}/ndk/${NDK_PACKAGE_VERSION}"
  export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME}"
  export ANDROID_NDK="${ANDROID_NDK_HOME}"
  export PATH="${FLUTTER_ROOT}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${HOME}/.cargo/bin:${PATH}"
}

require_command() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Required command is missing: ${tool}" >&2
    return 1
  fi
}

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

  echo "Android NDK LLVM prebuilt directory was not found under ${prebuilt_dir}" >&2
  ls -1 "${prebuilt_dir}" >&2 || true
  return 1
}

prepare_build_tools() {
  setup_common_env
  export DEBIAN_FRONTEND=noninteractive

  local can_install_with_apt="N"
  local apt_cmd=""
  if command -v apt-get >/dev/null 2>&1; then
    if [[ "$(id -u)" == "0" ]]; then
      apt_cmd="apt-get"
      can_install_with_apt="Y"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      apt_cmd="sudo apt-get"
      can_install_with_apt="Y"
    fi
  fi

  if [[ "${can_install_with_apt}" == "Y" ]]; then
    ${apt_cmd} update
    ${apt_cmd} install -y \
      autoconf \
      automake \
      clang \
      cmake \
      curl \
      file \
      git \
      g++ \
      gettext \
      libclang-dev \
      libglib2.0-dev \
      libgtk-3-dev \
      liblzma-dev \
      libssl-dev \
      libtool \
      nasm \
      ninja-build \
      openjdk-17-jdk-headless \
      pkg-config \
      python3 \
      unzip \
      wget \
      xz-utils \
      zip
  else
    echo "apt-get is unavailable or cannot run without an interactive password; using runner preinstalled tools."
  fi

  tool_versions | tee "${CI_ARTIFACT_DIR}/PREPARE_BUILD_TOOLS.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/PREPARE_BUILD_TOOLS.txt"
}

install_flutter() {
  setup_common_env
  require_command git
  require_command curl
  mkdir -p "$(dirname "${FLUTTER_ROOT}")"
  if [[ ! -d "${FLUTTER_ROOT}/.git" ]]; then
    rm -rf "${FLUTTER_ROOT}"
    git clone --depth=1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
  fi
  git -C "${FLUTTER_ROOT}" fetch --depth=1 origin "refs/tags/${FLUTTER_VERSION}:refs/tags/${FLUTTER_VERSION}" || true
  git -C "${FLUTTER_ROOT}" checkout --force "${FLUTTER_VERSION}"
  git -C "${FLUTTER_ROOT}" reset --hard "${FLUTTER_VERSION}"

  local patch_file="${REPO_ROOT}/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff"
  if git -C "${FLUTTER_ROOT}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    echo "Flutter dropdown patch already applied"
  else
    git -C "${FLUTTER_ROOT}" apply "${patch_file}"
  fi

  flutter config --no-analytics
  flutter --version | tee "${CI_ARTIFACT_DIR}/FLUTTER_VERSION.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/FLUTTER_VERSION.txt"
}

install_android_sdk() {
  setup_common_env
  require_command curl
  require_command unzip
  if [[ -z "${JAVA_HOME:-}" || ! -x "${JAVA_HOME}/bin/java" ]]; then
    echo "Java runtime was not found" >&2
    return 1
  fi

  mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
  if [[ ! -x "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -L --retry 5 --retry-delay 5 \
      -o "${tmp_dir}/cmdline-tools.zip" \
      https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
    unzip -q "${tmp_dir}/cmdline-tools.zip" -d "${tmp_dir}"
    rm -rf "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
    mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
    mv "${tmp_dir}/cmdline-tools/"* "${ANDROID_SDK_ROOT}/cmdline-tools/latest/"
    rm -rf "${tmp_dir}"
  fi

  yes | sdkmanager --licenses >/dev/null || true
  sdkmanager \
    "platform-tools" \
    "platforms;android-34" \
    "build-tools;34.0.0" \
    "ndk;${NDK_PACKAGE_VERSION}"
  test -x "${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/$(detect_ndk_host_tag)/bin/llvm-strip"
}

install_vcpkg() {
  setup_common_env
  require_command git
  mkdir -p "$(dirname "${VCPKG_ROOT}")"

  if [[ -x "${VCPKG_ROOT}/vcpkg" && ! -d "${VCPKG_ROOT}/.git" ]]; then
    echo "Using preinstalled vcpkg at ${VCPKG_ROOT}/vcpkg"
    "${VCPKG_ROOT}/vcpkg" version | tee "${CI_ARTIFACT_DIR}/VCPKG_VERSION.txt" || true
    publish_ci_file "${CI_ARTIFACT_DIR}/VCPKG_VERSION.txt"
    return 0
  fi

  if [[ ! -d "${VCPKG_ROOT}/.git" ]]; then
    rm -rf "${VCPKG_ROOT}"
    git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"
  fi

  if ! git -C "${VCPKG_ROOT}" fetch --depth=1 origin "${VCPKG_COMMIT_ID}"; then
    if [[ -x "${VCPKG_ROOT}/vcpkg" ]]; then
      echo "vcpkg fetch failed; continuing with cached executable at ${VCPKG_ROOT}/vcpkg"
    else
      return 1
    fi
  else
    git -C "${VCPKG_ROOT}" checkout --force "${VCPKG_COMMIT_ID}"
  fi

  if [[ ! -x "${VCPKG_ROOT}/vcpkg" ]]; then
    "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics
  else
    echo "Reusing existing vcpkg executable at ${VCPKG_ROOT}/vcpkg"
  fi
  test -x "${VCPKG_ROOT}/vcpkg"
  "${VCPKG_ROOT}/vcpkg" version | tee "${CI_ARTIFACT_DIR}/VCPKG_VERSION.txt" || true
  publish_ci_file "${CI_ARTIFACT_DIR}/VCPKG_VERSION.txt"
}

install_rust() {
  setup_common_env
  require_command curl
  if ! command -v rustup >/dev/null 2>&1; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal
    export PATH="${HOME}/.cargo/bin:${PATH}"
  fi
  rustup toolchain install "${RUST_VERSION}" --profile minimal --component rustfmt
  rustup default "${RUST_VERSION}"
  rustup target add aarch64-linux-android
  if ! cargo ndk --version 2>/dev/null | grep -q "${CARGO_NDK_VERSION}"; then
    cargo install cargo-ndk --version "${CARGO_NDK_VERSION}" --locked
  fi
  cargo ndk --version | tee "${CI_ARTIFACT_DIR}/CARGO_NDK_VERSION.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/CARGO_NDK_VERSION.txt"
}

compute_version() {
  setup_common_env
  local version_line build_name build_number
  version_line="$(grep -E '^version:' flutter/pubspec.yaml | head -n 1 | sed 's/^version:[[:space:]]*//')"
  build_name="${version_line%%+*}"
  build_number="${version_line##*+}"
  if [[ "${version_line}" == "${build_name}" ]]; then
    build_number="$(git rev-list --count HEAD)"
  fi

  case "${BUILD_MODE}" in
    release|profile|debug) ;;
    *)
      echo "Unsupported Android build mode: ${BUILD_MODE}" >&2
      return 1
      ;;
  esac

  {
    printf 'BUILD_NAME=%s\n' "${build_name}"
    printf 'BUILD_NUMBER=%s\n' "${build_number}"
  } > "${CI_ENV_FILE}"
  cat "${CI_ENV_FILE}"
  publish_ci_file "${CI_ENV_FILE}"
}

source_build_env() {
  if [[ ! -f "${CI_ENV_FILE}" ]]; then
    compute_version
  fi
  # shellcheck disable=SC1090
  source "${CI_ENV_FILE}"
  export BUILD_NAME BUILD_NUMBER
}

build_native_deps() {
  setup_common_env
  require_command bash
  test -x "${VCPKG_ROOT}/vcpkg"
  test -d "${ANDROID_NDK_HOME}"
  bash ./flutter/build_android_deps.sh "${ANDROID_ABI}"
}

build_rust_library() {
  setup_common_env
  require_command cargo
  require_command bash
  test -d "${ANDROID_NDK_HOME}"

  local ndk_host_tag ndk_prebuilt llvm_strip jni_dir
  ndk_host_tag="$(detect_ndk_host_tag)"
  ndk_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${ndk_host_tag}"
  llvm_strip="${ndk_prebuilt}/bin/llvm-strip"
  if [[ ! -x "${llvm_strip}" && -x "${llvm_strip}.exe" ]]; then
    llvm_strip="${llvm_strip}.exe"
  fi
  test -x "${llvm_strip}"

  bash ./flutter/ndk_arm64.sh
  jni_dir="${ANDROID_JNI_LIB_DIR}/${ANDROID_ABI}"
  mkdir -p "${jni_dir}"
  cp target/aarch64-linux-android/release/liblibrustdesk.so "${jni_dir}/librustdesk.so"
  cp "${ndk_prebuilt}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "${jni_dir}/"
  "${llvm_strip}" "${jni_dir}/librustdesk.so"
  "${llvm_strip}" "${jni_dir}/libc++_shared.so"
  test -s "${jni_dir}/librustdesk.so"
  test -s "${jni_dir}/libc++_shared.so"
  ls -lh "${jni_dir}" | tee "${CI_ARTIFACT_DIR}/JNI_LIBS.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/JNI_LIBS.txt"
}

flutter_pub_get() {
  setup_common_env
  require_command flutter
  pushd flutter
  flutter pub get
  popd
}

analyze_mobile() {
  setup_common_env
  require_command flutter
  pushd flutter
  flutter pub get
  flutter analyze --no-fatal-infos \
    lib/common/widgets/login.dart \
    lib/mobile/pages/home_page.dart \
    lib/mobile/pages/connection_page.dart \
    lib/mobile/pages/account_page.dart \
    lib/mobile/pages/settings_page.dart \
    lib/mobile/pages/server_page.dart \
    lib/mobile/pages/remote_page.dart \
    lib/mobile/pages/file_manager_page.dart
  popd
}

build_flutter_artifacts() {
  setup_common_env
  source_build_env
  require_command flutter
  pushd flutter
  flutter pub get

  local extra_args=()
  if [[ "${BUILD_MODE}" == "release" ]]; then
    extra_args+=(--obfuscate --split-debug-info=./split-debug-info)
  fi
  flutter build apk --"${BUILD_MODE}" --build-name "${BUILD_NAME}" --build-number "${BUILD_NUMBER}" --target-platform android-arm64 --split-per-abi "${extra_args[@]}"
  flutter build appbundle --"${BUILD_MODE}" --build-name "${BUILD_NAME}" --build-number "${BUILD_NUMBER}" --target-platform android-arm64 "${extra_args[@]}"

  mkdir -p ../artifacts
  cp "build/app/outputs/flutter-apk/app-arm64-v8a-${BUILD_MODE}.apk" "../artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.apk"
  local aab_path
  aab_path="$(find build/app/outputs -name '*.aab' | sort | tail -n 1)"
  cp "${aab_path}" "../artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.aab"
  popd
}

verify_artifacts() {
  setup_common_env
  require_command jar
  local apk_path="artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.apk"
  local aab_path="artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.aab"
  test -s "${apk_path}"
  test -s "${aab_path}"

  jar tf "${apk_path}" > "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  jar tf "${aab_path}" > "${CI_ARTIFACT_DIR}/AAB_FILES.txt"

  grep -q '^lib/arm64-v8a/librustdesk\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  grep -q '^lib/arm64-v8a/libc++_shared\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  grep -q '^lib/arm64-v8a/libapp\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  grep -q '^lib/arm64-v8a/libflutter\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"

  grep -q '^base/lib/arm64-v8a/librustdesk\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
  grep -q '^base/lib/arm64-v8a/libc++_shared\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
  grep -q '^base/lib/arm64-v8a/libapp\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
  grep -q '^base/lib/arm64-v8a/libflutter\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"

  sha256sum "${apk_path}" "${aab_path}" | tee artifacts/SHA256SUMS.txt
  publish_ci_file "artifacts/SHA256SUMS.txt"
}

record_success() {
  setup_common_env
  local file="${CI_ARTIFACT_DIR}/CI_SUCCESS.txt"
  {
    echo "step=${STEP}"
    echo "time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    selected_env
  } > "${file}"
  publish_ci_file "${file}"
}

publish_diagnostics() {
  setup_common_env
  mkdir -p "${CI_ARTIFACT_DIR}"
  {
    echo "time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    selected_env
    echo ""
    find "${CI_ARTIFACT_DIR}" -maxdepth 1 -type f -printf '%f %s bytes\n' 2>/dev/null | sort || true
  } > "${CI_ARTIFACT_DIR}/CI_DIAGNOSTICS_INDEX.txt"

  if mkdir -p "${PUBLIC_CI_DIR}" >/dev/null 2>&1; then
    find "${CI_ARTIFACT_DIR}" -maxdepth 1 -type f | while read -r file; do
      cp "${file}" "${PUBLIC_CI_DIR}/latest-$(basename "${file}")" >/dev/null 2>&1 || true
    done
  fi

  cat "${CI_ARTIFACT_DIR}/CI_DIAGNOSTICS_INDEX.txt"
}

case "${STEP}" in
  prepare-build-tools) prepare_build_tools ;;
  install-flutter) install_flutter ;;
  install-android-sdk) install_android_sdk ;;
  install-vcpkg) install_vcpkg ;;
  install-rust) install_rust ;;
  compute-version) compute_version ;;
  build-native-deps) build_native_deps ;;
  build-rust-library) build_rust_library ;;
  flutter-pub-get) flutter_pub_get ;;
  analyze-mobile) analyze_mobile ;;
  build-flutter-artifacts) build_flutter_artifacts ;;
  verify-artifacts) verify_artifacts ;;
  record-success) record_success ;;
  publish-diagnostics) publish_diagnostics ;;
  *)
    echo "Unknown Android CI step: ${STEP}" >&2
    exit 2
    ;;
esac
