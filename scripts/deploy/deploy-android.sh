#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
OUTPUT_DIR="${OUTPUT_DIR:-/www/wwwroot/KQromoteLink/android}"

mkdir -p "${OUTPUT_DIR}"

apk_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.apk' | sort | tail -n 1 || true)"
if [[ -z "${apk_path}" ]]; then
  echo "No APK artifact found in ${ARTIFACT_DIR}" >&2
  exit 1
fi

install -m 0644 "${apk_path}" "${OUTPUT_DIR}/Kunqiong-Remote-Desktop.apk"
echo "Android APK published to ${OUTPUT_DIR}/Kunqiong-Remote-Desktop.apk"

aab_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.aab' | sort | tail -n 1 || true)"
if [[ -n "${aab_path}" ]]; then
  install -m 0644 "${aab_path}" "${OUTPUT_DIR}/Kunqiong-Remote-Desktop.aab"
  echo "Android AAB published to ${OUTPUT_DIR}/Kunqiong-Remote-Desktop.aab"
else
  echo "No AAB artifact found in ${ARTIFACT_DIR}; APK deploy completed."
fi
