#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_script="${root_dir}/flutter/build_android.sh"

if grep -Fq -- '--split-per-abi' "${build_script}"; then
  echo "Android build must overwrite the fixed app-release.apk artifact" >&2
  exit 1
fi

grep -Fq 'apk_path="build/app/outputs/flutter-apk/app-${MODE}.apk"' "${build_script}"
