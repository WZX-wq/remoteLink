#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/kq-remote-link-server}"
COMPOSE_FILE="${COMPOSE_FILE:-rustdesk-server.compose.yml}"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "docker compose or docker-compose is required on the target server" >&2
  exit 1
fi

cd "${INSTALL_DIR}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "compose file not found: ${INSTALL_DIR}/${COMPOSE_FILE}" >&2
  exit 1
fi

require_container() {
  local name="$1"
  local running
  running="$(sudo docker inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || true)"
  if [[ "${running}" != "true" ]]; then
    echo "container is not running: ${name}" >&2
    sudo "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" ps || true
    exit 1
  fi
}

list_listeners() {
  if command -v ss >/dev/null 2>&1; then
    sudo ss -lntup
  elif command -v netstat >/dev/null 2>&1; then
    sudo netstat -lntup
  else
    return 1
  fi
}

require_listener() {
  local proto="$1"
  local port="$2"
  local listeners
  if ! listeners="$(list_listeners)"; then
    echo "Neither ss nor netstat is available; cannot verify ${proto}/${port}" >&2
    exit 1
  fi
  if ! printf '%s\n' "${listeners}" | awk -v proto="${proto}" -v port=":${port}" '
    BEGIN { found = 0 }
    tolower($1) ~ tolower(proto) && $0 ~ port { found = 1 }
    END { exit(found ? 0 : 1) }
  '; then
    echo "missing listener: ${proto}/${port}" >&2
    printf '%s\n' "${listeners}" | awk 'NR == 1 || /:21115|:21116|:21117|:21118|:21119/'
    exit 1
  fi
}

warn_listener() {
  local proto="$1"
  local port="$2"
  local listeners
  if ! listeners="$(list_listeners)"; then
    echo "Neither ss nor netstat is available; skipping optional ${proto}/${port}"
    return
  fi
  if ! printf '%s\n' "${listeners}" | awk -v proto="${proto}" -v port=":${port}" '
    BEGIN { found = 0 }
    tolower($1) ~ tolower(proto) && $0 ~ port { found = 1 }
    END { exit(found ? 0 : 1) }
  '; then
    echo "optional listener is not present yet: ${proto}/${port}"
  fi
}

echo "== Containers =="
sudo "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" ps

require_container kq-remote-link-hbbs
require_container kq-remote-link-hbbr

echo ""
echo "== Listening ports =="
list_listeners | awk 'NR == 1 || /:21115|:21116|:21117|:21118|:21119/'
require_listener tcp 21115
require_listener tcp 21116
require_listener udp 21116
require_listener tcp 21117
warn_listener tcp 21118
warn_listener tcp 21119

echo ""
echo "== hbbs public key =="
if [[ -s "${INSTALL_DIR}/data/id_ed25519.pub" ]]; then
  sudo cat "${INSTALL_DIR}/data/id_ed25519.pub"
else
  echo "Missing ${INSTALL_DIR}/data/id_ed25519.pub" >&2
  exit 1
fi

echo ""
echo "== Recent logs =="
sudo "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" logs --tail=60 hbbs hbbr

echo ""
echo "hbbs/hbbr health check passed."
