#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-KQromoteLink}"
INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/${PROJECT_NAME}}"
PUBLIC_HOST="${PUBLIC_HOST:-remotelink.kunqiongai.com}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "== Runner diagnostics =="
id
pwd
echo "source: ${SOURCE_DIR}"
echo "install: ${INSTALL_DIR}"
ls -ld /www /www/wwwroot "${INSTALL_DIR}" 2>/dev/null || true

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "required file not found: ${path}" >&2
    exit 1
  fi
}

require_file "${SOURCE_DIR}/deploy/rustdesk-server.compose.yml"
require_file "${SOURCE_DIR}/deploy/deploy-rustdesk-server.sh"
require_file "${SOURCE_DIR}/deploy/check-rustdesk-server.sh"
require_file "${SOURCE_DIR}/deploy/export-hbbs-public-key.sh"

chmod +x \
  "${SOURCE_DIR}/deploy/deploy-rustdesk-server.sh" \
  "${SOURCE_DIR}/deploy/check-rustdesk-server.sh" \
  "${SOURCE_DIR}/deploy/export-hbbs-public-key.sh"

echo ""
echo "== Deploy hbbs/hbbr =="
INSTALL_DIR="${INSTALL_DIR}" "${SOURCE_DIR}/deploy/deploy-rustdesk-server.sh"

echo ""
echo "== Check hbbs/hbbr =="
CHECK_COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"
if [[ "${KQ_ENABLE_API:-Y}" == "Y" ]]; then
  if [[ -n "${KQ_DB_HOST:-}" || -s "${INSTALL_DIR}/.env" ]]; then
    CHECK_COMPOSE_PROFILES="api"
  fi
fi
INSTALL_DIR="${INSTALL_DIR}" COMPOSE_PROFILES="${CHECK_COMPOSE_PROFILES}" "${SOURCE_DIR}/deploy/check-rustdesk-server.sh"

echo ""
echo "Private RustDesk server is ready."
echo "Public host: ${PUBLIC_HOST}"
echo "Client rendezvous server: ${PUBLIC_HOST}:21116"
echo "Client relay server: ${PUBLIC_HOST}:21117"
echo "Server key file: ${INSTALL_DIR}/data/id_ed25519.pub"
if [[ "${CHECK_COMPOSE_PROFILES}" == "api" ]]; then
  echo "KQ API: ${KQ_PUBLIC_API_URL:-https://${PUBLIC_HOST}/kq-api/api}"
fi
