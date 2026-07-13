#!/bin/bash

set -e -o pipefail

ANDROID_ABI=$1

# Build RustDesk dependencies for Android using vcpkg.json
# Required:
#   1. set VCPKG_ROOT / ANDROID_NDK path environment variables
#   2. vcpkg initialized
#   3. ndk, version: r25c or newer

if [ -z "$ANDROID_NDK_HOME" ]; then
  echo "Failed! Please set ANDROID_NDK_HOME"
  exit 1
fi

if [ -z "$VCPKG_ROOT" ]; then
  echo "Failed! Please set VCPKG_ROOT"
  exit 1
fi

# FFmpeg builds a few helper tools for the Windows host even while it is
# cross-compiling the Android libraries. On Windows, the Android NDK clang is
# also named clang.exe, and using it as FFmpeg's host compiler fails because it
# cannot find the host C runtime headers. Prefer vcpkg's desktop clang for the
# host side when available; the target compiler still comes from the NDK triplet.
if [ -z "${FFMPEG_HOST_CC:-}" ]; then
  for host_cc in \
    "$VCPKG_ROOT/downloads/tools/clang/clang-15.0.6/bin/clang.exe" \
    "$VCPKG_ROOT/downloads/tools/clang/clang-15.0.6/bin/clang"; do
    if [ -x "$host_cc" ]; then
      export FFMPEG_HOST_CC="$host_cc"
      break
    fi
  done
fi

API_LEVEL="21"

# Get directory of this script

SCRIPTDIR="$(readlink -f "$0")"
SCRIPTDIR="$(dirname "$SCRIPTDIR")"

# Check if vcpkg.json is one level up - in root directory of RD

if [ ! -f "$SCRIPTDIR/../vcpkg.json" ]; then
  echo "Failed! Please check where vcpkg.json is!"
  exit 1
fi

# NDK llvm toolchain

detect_ndk_host_tag() {
  local prebuilt_dir="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"
  local uname_s uname_m
  uname_s="$(uname -s 2>/dev/null || true)"
  uname_m="$(uname -m 2>/dev/null || true)"
  local candidates=()

  case "$uname_s" in
    Linux*) candidates+=(linux-x86_64) ;;
    Darwin*)
      if [ "$uname_m" = "arm64" ]; then
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
    if [ -d "$prebuilt_dir/$tag" ]; then
      echo "$tag"
      return 0
    fi
  done

  echo "Failed! Android NDK LLVM prebuilt directory was not found under $prebuilt_dir" >&2
  ls -1 "$prebuilt_dir" >&2 || true
  return 1
}

HOST_TAG="$(detect_ndk_host_tag)"
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
if [ ! -d "$TOOLCHAIN" ]; then
  echo "Failed! Android NDK toolchain was not found: $TOOLCHAIN" >&2
  exit 1
fi

function build {
  ANDROID_ABI=$1

  case "$ANDROID_ABI" in
  arm64-v8a)
     ABI=aarch64-linux-android$API_LEVEL
     VCPKG_TARGET=arm64-android
     ;;
  armeabi-v7a)
     ABI=armv7a-linux-androideabi$API_LEVEL
     VCPKG_TARGET=arm-neon-android
     ;;
  x86_64)
     ABI=x86_64-linux-android$API_LEVEL
     VCPKG_TARGET=x64-android
     ;;
  x86)
     ABI=i686-linux-android$API_LEVEL
     VCPKG_TARGET=x86-android
     ;;
  *)
     echo "ERROR: ANDROID_ABI must be one of: arm64-v8a, armeabi-v7a, x86_64, x86" >&2
     return 1
  esac

  echo "*** [$ANDROID_ABI][Start] Build and install vcpkg dependencies"
  pushd "$SCRIPTDIR/.."
  $VCPKG_ROOT/vcpkg install --triplet $VCPKG_TARGET --x-install-root="$VCPKG_ROOT/installed"
  popd
  head -n 100 "${VCPKG_ROOT}/buildtrees/ffmpeg/build-$VCPKG_TARGET-rel-out.log" || true
  echo "*** [$ANDROID_ABI][Finished] Build and install vcpkg dependencies"

if [ -d "$VCPKG_ROOT/installed/arm-neon-android" ]; then
  echo "*** [Start] Move arm-neon-android to arm-android"

  mv "$VCPKG_ROOT/installed/arm-neon-android" "$VCPKG_ROOT/installed/arm-android"

  echo "*** [Finished] Move arm-neon-android to arm-android"
fi
}

if [ ! -z "$ANDROID_ABI" ]; then
  build "$ANDROID_ABI"
else
  echo "Usage: build-android-deps.sh <ANDROID-ABI>" >&2
  exit 1
fi
