#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/kq-remote-link-server}"
COMPOSE_FILE="${COMPOSE_FILE:-rustdesk-server.compose.yml}"
KQ_SERVER_KEY="${KQ_SERVER_KEY:-_}"
KQ_API_PORT="${KQ_API_PORT:-21120}"
KQ_API_HEALTH_TIMEOUT="${KQ_API_HEALTH_TIMEOUT:-60}"
KQ_API_PUBLIC_PATH="${KQ_API_PUBLIC_PATH:-/kq-api}"
[[ "${KQ_API_PUBLIC_PATH}" == /* ]] || KQ_API_PUBLIC_PATH="/${KQ_API_PUBLIC_PATH}"
KQ_API_PUBLIC_PATH="${KQ_API_PUBLIC_PATH%/}"
KQ_PUBLIC_API_URL="${KQ_PUBLIC_API_URL:-https://remotelink.kunqiongai.com${KQ_API_PUBLIC_PATH}/api}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  echo "This script must run as root or with sudo available." >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "docker compose or docker-compose is required on the target server" >&2
  exit 1
fi

compose() {
  if [[ "${#SUDO[@]}" -eq 0 ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES}" KQ_SERVER_KEY="${KQ_SERVER_KEY}" "${COMPOSE_CMD[@]}" "$@"
  else
    "${SUDO[@]}" env "COMPOSE_PROFILES=${COMPOSE_PROFILES}" "KQ_SERVER_KEY=${KQ_SERVER_KEY}" "${COMPOSE_CMD[@]}" "$@"
  fi
}

api_logs() {
  echo ""
  echo "== KQ API logs =="
  compose -f "${COMPOSE_FILE}" logs --tail=160 api 2>/dev/null \
    || "${SUDO[@]}" docker logs --tail=160 kq-remote-link-api 2>/dev/null \
    || true
}

cd "${INSTALL_DIR}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "compose file not found: ${INSTALL_DIR}/${COMPOSE_FILE}" >&2
  exit 1
fi

require_container() {
  local name="$1"
  local running
  running="$("${SUDO[@]}" docker inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || true)"
  if [[ "${running}" != "true" ]]; then
    echo "container is not running: ${name}" >&2
    compose -f "${COMPOSE_FILE}" ps || true
    exit 1
  fi
}

docker_exec_read() {
  local container="$1"
  local path="$2"
  "${SUDO[@]}" docker exec "${container}" cat "${path}" 2>/dev/null || true
}

extract_public_key() {
  local key
  if [[ -s "${INSTALL_DIR}/data/id_ed25519.pub" ]]; then
    key="$("${SUDO[@]}" cat "${INSTALL_DIR}/data/id_ed25519.pub" 2>/dev/null || true)"
    if printf '%s' "${key}" | base64 -d >/dev/null 2>&1; then
      printf '%s' "${key}"
      return
    fi
  fi
  key="$(docker_exec_read kq-remote-link-hbbs /root/id_ed25519.pub)"
  if [[ -z "${key}" ]]; then
    key="$(docker_exec_read kq-remote-link-hbbs /data/id_ed25519.pub)"
  fi
  if [[ -z "${key}" ]]; then
    key="$(compose -f "${COMPOSE_FILE}" logs --tail=200 hbbs 2>/dev/null \
      | sed -n 's/.*Key: //p' \
      | tail -n 1 \
      | tr -d '\r')"
  fi
  printf '%s' "${key}"
}

list_listeners() {
  if command -v ss >/dev/null 2>&1; then
    "${SUDO[@]}" ss -lntup
  elif command -v netstat >/dev/null 2>&1; then
    "${SUDO[@]}" netstat -lntup
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

require_runtime() {
  local service="$1"
  local container="$2"
  if command -v systemctl >/dev/null 2>&1 \
      && systemctl list-unit-files "${service}" >/dev/null 2>&1 \
      && systemctl is-active --quiet "${service}"; then
    return
  fi
  require_container "${container}"
}

wait_for_api_health() {
  if ! command -v curl >/dev/null 2>&1; then
    require_listener tcp "${KQ_API_PORT}"
    return
  fi

  echo ""
  echo "== KQ API health =="
  local local_url="http://127.0.0.1:${KQ_API_PORT}/api/health"
  local deadline=$((SECONDS + KQ_API_HEALTH_TIMEOUT))
  local response_file
  local api_ready=N
  response_file="$(mktemp)"
  while (( SECONDS < deadline )); do
    if [[ "$("${SUDO[@]}" docker inspect -f '{{.State.Running}}' kq-remote-link-api 2>/dev/null || true)" != "true" ]]; then
      echo "KQ API container is not running yet; waiting for health deadline."
      sleep 2
      continue
    fi

    if curl -fsS "${local_url}" -o "${response_file}" 2>/dev/null; then
      cat "${response_file}"
      echo ""
      api_ready=Y
      break
    fi
    sleep 2
  done

  if [[ "${api_ready}" == "Y" ]]; then
    rm -f "${response_file}"
  elif ! curl -fsS "${local_url}" -o /tmp/kq-api-health.json 2>/dev/null; then
    echo "KQ API did not become healthy on ${local_url} within ${KQ_API_HEALTH_TIMEOUT}s." >&2
    list_listeners | awk -v api=":${KQ_API_PORT}" 'NR == 1 || /:21115|:21116|:21117|:21118|:21119/ || $0 ~ api' || true
    api_logs
    rm -f "${response_file}" /tmp/kq-api-health.json
    exit 1
  else
    cat /tmp/kq-api-health.json
    echo ""
    rm -f "${response_file}" /tmp/kq-api-health.json
  fi

  echo ""
  echo "== KQ API public health =="
  local public_deadline=$((SECONDS + 20))
  while (( SECONDS < public_deadline )); do
    if curl -fsS "${KQ_PUBLIC_API_URL%/}/health" -o /tmp/kq-api-public-health.json 2>/dev/null; then
      cat /tmp/kq-api-public-health.json
      echo ""
      rm -f /tmp/kq-api-public-health.json
      return
    fi
    sleep 2
  done

  echo "KQ API local health passed, but public health failed: ${KQ_PUBLIC_API_URL%/}/health" >&2
  rm -f /tmp/kq-api-public-health.json
  exit 1
}

echo "== Containers =="
compose -f "${COMPOSE_FILE}" ps

require_runtime kq-remote-link-hbbs.service kq-remote-link-hbbs
require_runtime kq-remote-link-hbbr.service kq-remote-link-hbbr
if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
  require_container kq-remote-link-api
fi

echo ""
echo "== Listening ports =="
list_listeners | awk -v api=":${KQ_API_PORT}" 'NR == 1 || /:21115|:21116|:21117|:21118|:21119/ || $0 ~ api'
require_listener tcp 21115
require_listener tcp 21116
require_listener udp 21116
require_listener tcp 21117
warn_listener tcp 21118
warn_listener tcp 21119
if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
  wait_for_api_health
fi

echo ""
echo "== hbbs public key =="
if [[ -s "${INSTALL_DIR}/data/id_ed25519.pub" ]]; then
  "${SUDO[@]}" cat "${INSTALL_DIR}/data/id_ed25519.pub"
else
  public_key="$(extract_public_key)"
  if [[ -n "${public_key}" ]]; then
    "${SUDO[@]}" mkdir -p "${INSTALL_DIR}/data"
    printf '%s\n' "${public_key}" | "${SUDO[@]}" tee "${INSTALL_DIR}/data/id_ed25519.pub" >/dev/null
    "${SUDO[@]}" cat "${INSTALL_DIR}/data/id_ed25519.pub"
  else
    echo "Missing ${INSTALL_DIR}/data/id_ed25519.pub and no key was found in the hbbs container or logs." >&2
    echo "Try: docker exec kq-remote-link-hbbs sh -c 'find /root /data -maxdepth 1 -type f -name id_ed25519.pub -print -exec cat {} \\;'" >&2
    exit 1
  fi
fi

echo ""
echo "== Recent logs =="
if command -v systemctl >/dev/null 2>&1 \
    && systemctl list-unit-files kq-remote-link-hbbs.service >/dev/null 2>&1; then
  "${SUDO[@]}" journalctl --no-pager -u kq-remote-link-hbbs.service -u kq-remote-link-hbbr.service -n 120 || true
else
  compose -f "${COMPOSE_FILE}" logs --tail=60 hbbs hbbr
fi

echo ""
echo "hbbs/hbbr health check passed."
