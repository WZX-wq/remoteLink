#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
OUTPUT_DIR="${OUTPUT_DIR:-/www/wwwroot/KQromoteLink/windows}"
API_DOWNLOAD_DIR="${API_DOWNLOAD_DIR:-/www/wwwroot/KQromoteLink/api/public/downloads}"
CANONICAL_FILE_NAME="${KQ_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop-Setup.exe}"

if [[ -n "${KQ_WINDOWS_INSTALLER_PATH:-}" ]]; then
  installer_path="${KQ_WINDOWS_INSTALLER_PATH}"
else
  installer_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -type f -name '*.exe' \
    ! -iname 'unins*.exe' ! -iname 'uninstall*.exe' -printf '%T@:%p\n' 2>/dev/null \
    | sort -n | tail -n 1 | cut -d: -f2- || true)"
fi

if [[ -z "${installer_path}" || ! -f "${installer_path}" ]]; then
  echo "No Windows installer artifact found. Set KQ_WINDOWS_INSTALLER_PATH or place one .exe in ${ARTIFACT_DIR}." >&2
  exit 1
fi

detect_version() {
  local filename="$1"
  sed -nE 's/.*([0-9]+\.[0-9]+(\.[0-9]+){0,2}).*/\1/p' <<<"${filename}" | head -n 1
}

detected_version="$(detect_version "$(basename "${installer_path}")" || true)"
windows_version="${KQ_DOWNLOAD_VERSION:-${BUILD_NAME:-${detected_version:-}}}"
if [[ -z "${windows_version}" ]]; then
  echo "KQ_DOWNLOAD_VERSION is required when the installer filename has no version." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${API_DOWNLOAD_DIR}"
install -m 0644 "${installer_path}" "${OUTPUT_DIR}/${CANONICAL_FILE_NAME}"
install -m 0644 "${installer_path}" "${API_DOWNLOAD_DIR}/${CANONICAL_FILE_NAME}"

windows_sha256="$(sha256sum "${installer_path}" | awk '{print $1}')"
printf '%s  %s\n' "${windows_sha256}" "${CANONICAL_FILE_NAME}" > "${OUTPUT_DIR}/SHA256SUMS.txt"
install -m 0644 "${OUTPUT_DIR}/SHA256SUMS.txt" "${API_DOWNLOAD_DIR}/SHA256SUMS-windows.txt"

ENV_FILE="${KQ_API_ENV_FILE:-/www/wwwroot/KQromoteLink/.env}"
if [[ -f "${ENV_FILE}" ]]; then
  tmp_env="$(mktemp)"
  grep -Ev '^(KQ_DOWNLOAD_URL|KQ_DOWNLOAD_FILE_PATH|KQ_DOWNLOAD_FILE_NAME|KQ_DOWNLOAD_VERSION|KQ_DOWNLOAD_SHA256)=' "${ENV_FILE}" > "${tmp_env}" || true
  {
    printf 'KQ_DOWNLOAD_URL=%s\n' "${KQ_DOWNLOAD_URL:-https://remotelink.kunqiongai.com/kq-api/download/windows}"
    printf 'KQ_DOWNLOAD_FILE_PATH=%s\n' "/app/public/downloads/${CANONICAL_FILE_NAME}"
    printf 'KQ_DOWNLOAD_FILE_NAME=%s\n' "${CANONICAL_FILE_NAME}"
    printf 'KQ_DOWNLOAD_VERSION=%s\n' "${windows_version}"
    printf 'KQ_DOWNLOAD_SHA256=%s\n' "${windows_sha256}"
  } >> "${tmp_env}"
  install -m 0600 "${tmp_env}" "${ENV_FILE}"
  rm -f "${tmp_env}"
  echo "Windows download environment updated in ${ENV_FILE}"
fi

if command -v docker >/dev/null 2>&1 && docker inspect kq-remote-link-api >/dev/null 2>&1; then
  docker restart kq-remote-link-api >/dev/null
elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files kq-remote-link-api.service >/dev/null 2>&1; then
  systemctl restart kq-remote-link-api.service
fi

echo "Windows installer published as ${CANONICAL_FILE_NAME}"
echo "Version: ${windows_version}"
echo "SHA256: ${windows_sha256}"
