#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/kq-remote-link-server}"
COMPOSE_FILE="${COMPOSE_FILE:-rustdesk-server.compose.yml}"
PUBLIC_HOST="${PUBLIC_HOST:-43.154.197.96}"
KQ_RELAY_SERVER="${KQ_RELAY_SERVER:-${PUBLIC_HOST}:21117}"
KQ_SERVER_KEY="${KQ_SERVER_KEY:-_}"
KQ_HBBS_PUBLIC_KEY="${KQ_HBBS_PUBLIC_KEY:-}"
KQ_HBBS_SECRET_KEY="${KQ_HBBS_SECRET_KEY:-}"

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  echo "This script must run as root or with sudo available." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required on the target server" >&2
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
    KQ_RELAY_SERVER="${KQ_RELAY_SERVER}" KQ_SERVER_KEY="${KQ_SERVER_KEY}" "${COMPOSE_CMD[@]}" "$@"
  else
    "${SUDO[@]}" env "KQ_RELAY_SERVER=${KQ_RELAY_SERVER}" "KQ_SERVER_KEY=${KQ_SERVER_KEY}" "${COMPOSE_CMD[@]}" "$@"
  fi
}

docker_exec_read() {
  local container="$1"
  local path="$2"
  "${SUDO[@]}" docker exec "${container}" cat "${path}" 2>/dev/null || true
}

validate_key_pair_env() {
  if [[ -z "${KQ_HBBS_PUBLIC_KEY}" && -z "${KQ_HBBS_SECRET_KEY}" ]]; then
    return
  fi
  if [[ -z "${KQ_HBBS_PUBLIC_KEY}" || -z "${KQ_HBBS_SECRET_KEY}" ]]; then
    echo "KQ_HBBS_PUBLIC_KEY and KQ_HBBS_SECRET_KEY must be set together." >&2
    exit 1
  fi
  if ! printf '%s' "${KQ_HBBS_PUBLIC_KEY}" | base64 -d >/dev/null 2>&1; then
    echo "KQ_HBBS_PUBLIC_KEY is not valid base64." >&2
    exit 1
  fi
  if ! printf '%s' "${KQ_HBBS_SECRET_KEY}" | base64 -d >/dev/null 2>&1; then
    echo "KQ_HBBS_SECRET_KEY is not valid base64." >&2
    exit 1
  fi
}

seed_server_key_pair() {
  validate_key_pair_env
  if [[ -z "${KQ_HBBS_PUBLIC_KEY}" ]]; then
    return
  fi
  echo "Seeding hbbs/hbbr key pair from environment."
  printf '%s\n' "${KQ_HBBS_PUBLIC_KEY}" | "${SUDO[@]}" tee "${INSTALL_DIR}/data/id_ed25519.pub" >/dev/null
  printf '%s\n' "${KQ_HBBS_SECRET_KEY}" | "${SUDO[@]}" tee "${INSTALL_DIR}/data/id_ed25519" >/dev/null
  "${SUDO[@]}" chmod 600 "${INSTALL_DIR}/data/id_ed25519"
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
    key="$("${SUDO[@]}" "${COMPOSE_CMD[@]}" -f rustdesk-server.compose.yml logs --tail=200 hbbs 2>/dev/null \
      | sed -n 's/.*Key: //p' \
      | tail -n 1 \
      | tr -d '\r')"
  fi
  printf '%s' "${key}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_COMPOSE="${SCRIPT_DIR}/${COMPOSE_FILE}"

if [[ ! -f "${SOURCE_COMPOSE}" ]]; then
  echo "compose file not found: ${SOURCE_COMPOSE}" >&2
  exit 1
fi

"${SUDO[@]}" mkdir -p "${INSTALL_DIR}/data"
"${SUDO[@]}" cp "${SOURCE_COMPOSE}" "${INSTALL_DIR}/rustdesk-server.compose.yml"
seed_server_key_pair
cd "${INSTALL_DIR}"

open_firewall_ports() {
  if command -v firewall-cmd >/dev/null 2>&1 && "${SUDO[@]}" firewall-cmd --state >/dev/null 2>&1; then
    "${SUDO[@]}" firewall-cmd --permanent --add-port=21115-21119/tcp
    "${SUDO[@]}" firewall-cmd --permanent --add-port=21116/udp
    "${SUDO[@]}" firewall-cmd --reload
    echo "firewalld allowed tcp/21115-21119 and udp/21116"
    return
  fi

  if command -v ufw >/dev/null 2>&1 && "${SUDO[@]}" ufw status 2>/dev/null | grep -qi "Status: active"; then
    "${SUDO[@]}" ufw allow 21115:21119/tcp
    "${SUDO[@]}" ufw allow 21116/udp
    echo "ufw allowed tcp/21115-21119 and udp/21116"
    return
  fi

  if command -v iptables >/dev/null 2>&1; then
    for port in 21115 21116 21117 21118 21119; do
      "${SUDO[@]}" iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null \
        || "${SUDO[@]}" iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT
    done
    "${SUDO[@]}" iptables -C INPUT -p udp --dport 21116 -j ACCEPT 2>/dev/null \
      || "${SUDO[@]}" iptables -I INPUT -p udp --dport 21116 -j ACCEPT
    echo "iptables allowed tcp/21115-21119 and udp/21116"
    return
  fi

  echo "No supported local firewall tool was found; verify tcp/21115-21119 and udp/21116 manually."
}

echo "Using RustDesk relay server: ${KQ_RELAY_SERVER}"
echo "Using RustDesk server key mode: managed key pair"
compose -f rustdesk-server.compose.yml pull
open_firewall_ports
compose -f rustdesk-server.compose.yml up -d --force-recreate
compose -f rustdesk-server.compose.yml ps

echo "Waiting for hbbs key generation..."
for _ in $(seq 1 20); do
  public_key="$(extract_public_key)"
  if [[ -n "${public_key}" ]] && printf '%s' "${public_key}" | base64 -d >/dev/null 2>&1; then
    printf '%s\n' "${public_key}" | "${SUDO[@]}" tee "${INSTALL_DIR}/data/id_ed25519.pub" >/dev/null
    break
  fi
  sleep 1
done

echo ""
echo "KQ Remote Link hbbs/hbbr deployment directory: ${INSTALL_DIR}"
echo "Open firewall/security-group ports:"
echo "  TCP 21115, 21116, 21117, 21118, 21119"
echo "  UDP 21116"

if [[ -f "${INSTALL_DIR}/data/id_ed25519.pub" ]]; then
  echo ""
  echo "hbbs public key:"
  "${SUDO[@]}" cat "${INSTALL_DIR}/data/id_ed25519.pub"
else
  echo ""
  echo "hbbs public key is not present yet. Check container logs if it is not created after startup."
fi
