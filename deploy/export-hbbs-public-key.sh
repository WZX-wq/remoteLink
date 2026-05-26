#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/KQromoteLink}"
CONTAINER_NAME="${CONTAINER_NAME:-kq-remote-link-hbbs}"

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  echo "This script must run as root or with sudo available." >&2
  exit 1
fi

docker_exec_read() {
  local path="$1"
  "${SUDO[@]}" docker exec "${CONTAINER_NAME}" sh -c "test -s '${path}' && cat '${path}'" 2>/dev/null || true
}

find_public_key() {
  local key
  for path in /root/id_ed25519.pub /data/id_ed25519.pub /app/id_ed25519.pub; do
    key="$(docker_exec_read "${path}")"
    if [[ -n "${key}" ]]; then
      printf '%s' "${key}"
      return
    fi
  done

  key="$("${SUDO[@]}" docker logs "${CONTAINER_NAME}" 2>&1 \
    | sed -n 's/.*Key: //p' \
    | tail -n 1 \
    | tr -d '\r')"
  printf '%s' "${key}"
}

public_key="$(find_public_key)"
if [[ -z "${public_key}" ]]; then
  echo "No hbbs public key found in ${CONTAINER_NAME} or its logs." >&2
  echo "Container files:" >&2
  "${SUDO[@]}" docker exec "${CONTAINER_NAME}" sh -c "find /root /data /app -maxdepth 1 -type f 2>/dev/null || true" >&2 || true
  exit 1
fi

"${SUDO[@]}" mkdir -p "${INSTALL_DIR}/data"
printf '%s\n' "${public_key}" | "${SUDO[@]}" tee "${INSTALL_DIR}/data/id_ed25519.pub" >/dev/null
printf '%s\n' "${public_key}"
