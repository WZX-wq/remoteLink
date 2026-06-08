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
TIMINGS_FILE="${TIMINGS_FILE:-${CI_ARTIFACT_DIR}/CI_TIMINGS.tsv}"
STEP_STARTED_AT="${SECONDS}"
mkdir -p "${CI_ARTIFACT_DIR}"

publish_ci_file() {
  local file="$1"
  if [[ -s "${file}" ]] && mkdir -p "${PUBLIC_CI_DIR}" >/dev/null 2>&1; then
    cp "${file}" "${PUBLIC_CI_DIR}/latest-$(basename "${file}")" >/dev/null 2>&1 || true
  fi
}

record_step_timing() {
  local status="${1:-ok}"
  mkdir -p "${CI_ARTIFACT_DIR}"
  if [[ ! -f "${TIMINGS_FILE}" ]]; then
    printf 'step\tstatus\tduration_seconds\ttime_utc\n' > "${TIMINGS_FILE}"
  fi
  printf '%s\t%s\t%s\t%s\n' "${STEP}" "${status}" "$((SECONDS - STEP_STARTED_AT))" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${TIMINGS_FILE}"
  publish_ci_file "${TIMINGS_FILE}"
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
    CARGO_TARGET_DIR \
    KQ_ANDROID_BUILD_KIND \
    KQ_ANDROID_BUILD_AAB \
    KQ_ANDROID_RUN_ANALYZE \
    VCPKG_ROOT \
    CMAKE_VERSION \
    CMAKE_ROOT \
    NINJA_VERSION \
    NINJA_ROOT \
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
  id || true
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
  record_step_timing "failed" || true
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
  export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/opt/artifacts/kq-remote-link/cargo-target/android-aarch64}"
  export CARGO_INCREMENTAL="${CARGO_INCREMENTAL:-1}"
  export KQ_ANDROID_BUILD_KIND="${KQ_ANDROID_BUILD_KIND:-fast}"
  export KQ_ANDROID_BUILD_AAB="${KQ_ANDROID_BUILD_AAB:-N}"
  export KQ_ANDROID_RUN_ANALYZE="${KQ_ANDROID_RUN_ANALYZE:-N}"
  export VCPKG_COMMIT_ID="${VCPKG_COMMIT_ID:-120deac3062162151622ca4860575a33844ba10b}"
  export VCPKG_ROOT="${VCPKG_ROOT:-/opt/artifacts/vcpkg}"
  export CMAKE_VERSION="${CMAKE_VERSION:-3.30.1}"
  export CMAKE_ROOT="${CMAKE_ROOT:-/opt/artifacts/cmake/${CMAKE_VERSION}}"
  export NINJA_VERSION="${NINJA_VERSION:-1.12.1}"
  export NINJA_ROOT="${NINJA_ROOT:-/opt/artifacts/ninja/${NINJA_VERSION}}"
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
  export PATH="${FLUTTER_ROOT}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${HOME}/.cargo/bin:${CMAKE_ROOT}/bin:${NINJA_ROOT}:${PATH}"
  export VCPKG_FORCE_SYSTEM_BINARIES="${VCPKG_FORCE_SYSTEM_BINARIES:-1}"
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

  if command -v apt-get >/dev/null 2>&1; then
    if [[ "$(id -u)" == "0" ]]; then
      apt-get update
      apt-get install -y \
        autoconf \
        automake \
        clang \
        cmake \
        curl \
        file \
        gcc-multilib \
        git \
        g++ \
        g++-multilib \
        gettext \
        libc6-dev \
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
        zip || true
    elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y \
        autoconf \
        automake \
        clang \
        cmake \
        curl \
        file \
        gcc-multilib \
        git \
        g++ \
        g++-multilib \
        gettext \
        libc6-dev \
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
        zip || true
    else
      echo "apt-get is available but cannot run without an interactive password."
    fi
  elif command -v dnf >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
    dnf install -y \
      autoconf \
      automake \
      clang \
      cmake \
      curl \
      file \
      gcc-c++ \
      glibc-devel.i686 \
      libstdc++-devel.i686 \
      gettext \
      git \
      glib2-devel \
      gtk3-devel \
      java-17-openjdk-headless \
      libtool \
      nasm \
      ninja-build \
      openssl-devel \
      pkgconf-pkg-config \
      python3 \
      unzip \
      wget \
      xz-devel \
      zip || true
  elif command -v yum >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
    yum install -y \
      autoconf \
      automake \
      clang \
      cmake \
      curl \
      file \
      gcc-c++ \
      glibc-devel.i686 \
      libstdc++-devel.i686 \
      gettext \
      git \
      glib2-devel \
      gtk3-devel \
      java-17-openjdk-headless \
      libtool \
      nasm \
      ninja-build \
      openssl-devel \
      pkgconf-pkg-config \
      python3 \
      unzip \
      wget \
      xz-devel \
      zip || true
  else
    echo "No supported non-interactive package manager was found; using runner preinstalled tools."
  fi

  tool_versions | tee "${CI_ARTIFACT_DIR}/PREPARE_BUILD_TOOLS.txt"
  {
    echo "time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for path in /usr/include/gnu/stubs.h /usr/include/gnu/stubs-32.h /usr/include/gnu/stubs-64.h; do
      if [[ -e "${path}" ]]; then
        echo "present ${path}"
      else
        echo "missing ${path}"
      fi
    done
  } | tee "${CI_ARTIFACT_DIR}/HOST_GLIBC_STUBS.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/PREPARE_BUILD_TOOLS.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/HOST_GLIBC_STUBS.txt"
}

download_with_fallback() {
  local output="$1"
  shift

  local url
  for url in "$@"; do
    echo "Downloading ${url}"
    if curl -L --fail --retry 5 --retry-delay 5 --connect-timeout 30 --max-time 600 -o "${output}" "${url}"; then
      test -s "${output}"
      return 0
    fi
    echo "Download failed: ${url}" >&2
    rm -f "${output}"
  done

  echo "All download URLs failed for ${output}" >&2
  return 1
}

install_cmake_tool() {
  setup_common_env
  mkdir -p "$(dirname "${CMAKE_ROOT}")"

  if [[ -x "${CMAKE_ROOT}/bin/cmake" ]] && "${CMAKE_ROOT}/bin/cmake" --version | head -n 1 | grep -q "${CMAKE_VERSION}"; then
    echo "Reusing cached CMake ${CMAKE_VERSION} at ${CMAKE_ROOT}"
    return 0
  fi

  local tmp_dir archive extracted_dir
  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/cmake.tar.gz"
  download_with_fallback "${archive}" \
    "https://cmake.org/files/v3.30/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
    "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"

  tar -xzf "${archive}" -C "${tmp_dir}"
  extracted_dir="${tmp_dir}/cmake-${CMAKE_VERSION}-linux-x86_64"
  test -x "${extracted_dir}/bin/cmake"

  rm -rf "${CMAKE_ROOT}"
  mkdir -p "${CMAKE_ROOT}"
  cp -a "${extracted_dir}/." "${CMAKE_ROOT}/"
  rm -rf "${tmp_dir}"

  "${CMAKE_ROOT}/bin/cmake" --version | tee "${CI_ARTIFACT_DIR}/CMAKE_VERSION.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/CMAKE_VERSION.txt"
}

install_ninja_tool() {
  setup_common_env
  mkdir -p "${NINJA_ROOT}"

  if [[ -x "${NINJA_ROOT}/ninja" ]] && "${NINJA_ROOT}/ninja" --version | grep -q "${NINJA_VERSION}"; then
    echo "Reusing cached Ninja ${NINJA_VERSION} at ${NINJA_ROOT}"
    return 0
  fi

  if command -v ninja >/dev/null 2>&1; then
    echo "Using system Ninja at $(command -v ninja)"
    ninja --version | tee "${CI_ARTIFACT_DIR}/NINJA_VERSION.txt"
    publish_ci_file "${CI_ARTIFACT_DIR}/NINJA_VERSION.txt"
    return 0
  fi

  local tmp_dir archive source_dir
  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/ninja-linux.zip"
  if ! download_with_fallback "${archive}" \
    "https://gh.llkk.cc/https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" \
    "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"; then
    rm -rf "${tmp_dir}"
    return 1
  fi

  if ! unzip -q "${archive}" -d "${tmp_dir}/ninja" || [[ ! -f "${tmp_dir}/ninja/ninja" ]]; then
    rm -rf "${tmp_dir}"
    return 1
  fi

  rm -rf "${NINJA_ROOT}"
  mkdir -p "${NINJA_ROOT}"
  cp "${tmp_dir}/ninja/ninja" "${NINJA_ROOT}/ninja"
  chmod +x "${NINJA_ROOT}/ninja"
  rm -rf "${tmp_dir}"

  "${NINJA_ROOT}/ninja" --version | tee "${CI_ARTIFACT_DIR}/NINJA_VERSION.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/NINJA_VERSION.txt"
}

install_ninja_from_source() {
  setup_common_env
  require_command python3
  require_command g++
  mkdir -p "${NINJA_ROOT}"

  local tmp_dir archive source_dir built_ninja
  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/ninja-source.zip"
  download_with_fallback "${archive}" \
    "https://gitee.com/mirrors/ninja/repository/archive/v${NINJA_VERSION}.zip" \
    "https://codeload.github.com/ninja-build/ninja/zip/refs/tags/v${NINJA_VERSION}"

  unzip -q "${archive}" -d "${tmp_dir}/source"
  source_dir="$(find "${tmp_dir}/source" -maxdepth 1 -type d -name 'ninja-*' | sort | head -n 1)"
  test -n "${source_dir}"
  pushd "${source_dir}"
  python3 configure.py --bootstrap
  built_ninja="${source_dir}/ninja"
  test -x "${built_ninja}"
  popd

  rm -rf "${NINJA_ROOT}"
  mkdir -p "${NINJA_ROOT}"
  cp "${built_ninja}" "${NINJA_ROOT}/ninja"
  chmod +x "${NINJA_ROOT}/ninja"
  rm -rf "${tmp_dir}"

  "${NINJA_ROOT}/ninja" --version | tee "${CI_ARTIFACT_DIR}/NINJA_VERSION.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/NINJA_VERSION.txt"
}

install_build_system_tools() {
  setup_common_env
  require_command curl
  require_command tar
  require_command unzip
  install_cmake_tool
  if ! install_ninja_tool; then
    echo "Prebuilt Ninja install failed; building Ninja ${NINJA_VERSION} from source."
    install_ninja_from_source
  fi
  tool_versions | tee "${CI_ARTIFACT_DIR}/BUILD_SYSTEM_TOOLS.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/BUILD_SYSTEM_TOOLS.txt"
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
  require_command cmake
  require_command ninja
  test -x "${VCPKG_ROOT}/vcpkg"
  test -d "${ANDROID_NDK_HOME}"
  cmake --version | head -n 1
  ninja --version
  bash ./flutter/build_android_deps.sh "${ANDROID_ABI}"
}

build_rust_library() {
  setup_common_env
  require_command cargo
  require_command bash
  test -d "${ANDROID_NDK_HOME}"
  mkdir -p "${CARGO_TARGET_DIR}"

  local ndk_host_tag ndk_prebuilt llvm_strip jni_dir
  ndk_host_tag="$(detect_ndk_host_tag)"
  ndk_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${ndk_host_tag}"
  llvm_strip="${ndk_prebuilt}/bin/llvm-strip"
  if [[ ! -x "${llvm_strip}" && -x "${llvm_strip}.exe" ]]; then
    llvm_strip="${llvm_strip}.exe"
  fi
  test -x "${llvm_strip}"

  if [[ -z "${BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android:-}" ]]; then
    export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--target=aarch64-linux-android${ANDROID_API_LEVEL} --sysroot=${ndk_prebuilt}/sysroot -D__ANDROID_API__=${ANDROID_API_LEVEL}"
  fi
  export BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS:-${BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android}}"
  printf '%s\n' "BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android=${BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android}" | tee "${CI_ARTIFACT_DIR}/BINDGEN_ANDROID_ARGS.txt"
  publish_ci_file "${CI_ARTIFACT_DIR}/BINDGEN_ANDROID_ARGS.txt"

  bash ./flutter/ndk_arm64.sh
  jni_dir="${ANDROID_JNI_LIB_DIR}/${ANDROID_ABI}"
  mkdir -p "${jni_dir}"
  cp "${CARGO_TARGET_DIR}/aarch64-linux-android/release/liblibrustdesk.so" "${jni_dir}/librustdesk.so"
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
  if [[ "${KQ_ANDROID_RUN_ANALYZE}" != "Y" ]]; then
    echo "Skipping Flutter analyze for fast Android test build. Set KQ_ANDROID_RUN_ANALYZE=Y for full validation."
    return 0
  fi
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

  mkdir -p ../artifacts
  cp "build/app/outputs/flutter-apk/app-arm64-v8a-${BUILD_MODE}.apk" "../artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.apk"
  if [[ "${KQ_ANDROID_BUILD_AAB}" == "Y" ]]; then
    flutter build appbundle --"${BUILD_MODE}" --build-name "${BUILD_NAME}" --build-number "${BUILD_NUMBER}" --target-platform android-arm64 "${extra_args[@]}"
    local aab_path
    aab_path="$(find build/app/outputs -name '*.aab' | sort | tail -n 1)"
    cp "${aab_path}" "../artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.aab"
  else
    echo "Skipping Android AAB for fast test build. Set KQ_ANDROID_BUILD_AAB=Y for store-ready bundle."
  fi
  popd
}

verify_artifacts() {
  setup_common_env
  require_command jar
  local apk_path="artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.apk"
  local aab_path="artifacts/Kunqiong-Remote-Desktop-Android-arm64-v8a-${BUILD_MODE}.aab"
  test -s "${apk_path}"

  jar tf "${apk_path}" > "${CI_ARTIFACT_DIR}/APK_FILES.txt"

  grep -q '^lib/arm64-v8a/librustdesk\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  grep -q '^lib/arm64-v8a/libc++_shared\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  grep -q '^lib/arm64-v8a/libapp\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"
  grep -q '^lib/arm64-v8a/libflutter\.so$' "${CI_ARTIFACT_DIR}/APK_FILES.txt"

  if [[ -s "${aab_path}" ]]; then
    jar tf "${aab_path}" > "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
    grep -q '^base/lib/arm64-v8a/librustdesk\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
    grep -q '^base/lib/arm64-v8a/libc++_shared\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
    grep -q '^base/lib/arm64-v8a/libapp\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
    grep -q '^base/lib/arm64-v8a/libflutter\.so$' "${CI_ARTIFACT_DIR}/AAB_FILES.txt"
    sha256sum "${apk_path}" "${aab_path}" | tee artifacts/SHA256SUMS.txt
  else
    echo "AAB artifact is absent by design for KQ_ANDROID_BUILD_AAB=${KQ_ANDROID_BUILD_AAB}."
    sha256sum "${apk_path}" | tee artifacts/SHA256SUMS.txt
  fi
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
  install-build-system-tools) install_build_system_tools ;;
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

record_step_timing "ok"
