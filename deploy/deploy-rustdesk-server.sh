#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/kq-remote-link-server}"
COMPOSE_FILE="${COMPOSE_FILE:-rustdesk-server.compose.yml}"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_COMPOSE="${SCRIPT_DIR}/${COMPOSE_FILE}"

if [[ ! -f "${SOURCE_COMPOSE}" ]]; then
  echo "compose file not found: ${SOURCE_COMPOSE}" >&2
  exit 1
fi

"${SUDO[@]}" mkdir -p "${INSTALL_DIR}/data"
"${SUDO[@]}" cp "${SOURCE_COMPOSE}" "${INSTALL_DIR}/rustdesk-server.compose.yml"
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

"${SUDO[@]}" "${COMPOSE_CMD[@]}" -f rustdesk-server.compose.yml pull
open_firewall_ports
"${SUDO[@]}" "${COMPOSE_CMD[@]}" -f rustdesk-server.compose.yml up -d
"${SUDO[@]}" "${COMPOSE_CMD[@]}" -f rustdesk-server.compose.yml ps

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
