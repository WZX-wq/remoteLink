#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/kq-remote-link-server}"
COMPOSE_FILE="${COMPOSE_FILE:-rustdesk-server.compose.yml}"
PUBLIC_HOST="${PUBLIC_HOST:-43.154.197.96}"
KQ_RELAY_SERVER="${KQ_RELAY_SERVER:-${PUBLIC_HOST}:21117}"
KQ_SERVER_KEY="${KQ_SERVER_KEY:-_}"
KQ_HBBS_PUBLIC_KEY="${KQ_HBBS_PUBLIC_KEY:-}"
KQ_HBBS_SECRET_KEY="${KQ_HBBS_SECRET_KEY:-}"
KQ_ENABLE_API="${KQ_ENABLE_API:-Y}"
KQ_API_PORT="${KQ_API_PORT:-21120}"
KQ_API_PUBLIC_PATH="${KQ_API_PUBLIC_PATH:-/kq-api}"
[[ "${KQ_API_PUBLIC_PATH}" == /* ]] || KQ_API_PUBLIC_PATH="/${KQ_API_PUBLIC_PATH}"
KQ_API_PUBLIC_PATH="${KQ_API_PUBLIC_PATH%/}"
KQ_PUBLIC_API_URL="${KQ_PUBLIC_API_URL:-http://${PUBLIC_HOST}${KQ_API_PUBLIC_PATH}/api}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"

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
    COMPOSE_PROFILES="${COMPOSE_PROFILES}" KQ_RELAY_SERVER="${KQ_RELAY_SERVER}" KQ_SERVER_KEY="${KQ_SERVER_KEY}" "${COMPOSE_CMD[@]}" "$@"
  else
    "${SUDO[@]}" env "COMPOSE_PROFILES=${COMPOSE_PROFILES}" "KQ_RELAY_SERVER=${KQ_RELAY_SERVER}" "KQ_SERVER_KEY=${KQ_SERVER_KEY}" "${COMPOSE_CMD[@]}" "$@"
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
SOURCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_API="${SOURCE_ROOT}/server"
KQ_API_ENV_ENC_FILE="${KQ_API_ENV_ENC_FILE:-${SOURCE_ROOT}/deploy/kq-api.env.enc}"
KQ_API_ENV_PRIVATE_KEY="${INSTALL_DIR}/api-env-private.pem"
KQ_API_ENV_PUBLIC_KEY="${INSTALL_DIR}/api-env-public.pem"

if [[ ! -f "${SOURCE_COMPOSE}" ]]; then
  echo "compose file not found: ${SOURCE_COMPOSE}" >&2
  exit 1
fi

"${SUDO[@]}" mkdir -p "${INSTALL_DIR}/data"
"${SUDO[@]}" cp "${SOURCE_COMPOSE}" "${INSTALL_DIR}/rustdesk-server.compose.yml"
seed_server_key_pair
cd "${INSTALL_DIR}"

print_api_env_public_key() {
  if [[ -s "${KQ_API_ENV_PUBLIC_KEY}" ]]; then
    echo "KQ_API_ENV_PUBLIC_KEY_BEGIN"
    "${SUDO[@]}" sed 's/\r$//' "${KQ_API_ENV_PUBLIC_KEY}"
    echo "KQ_API_ENV_PUBLIC_KEY_END"
  fi
}

ensure_api_env_key_pair() {
  if [[ -s "${KQ_API_ENV_PRIVATE_KEY}" && -s "${KQ_API_ENV_PUBLIC_KEY}" ]]; then
    print_api_env_public_key
    return 0
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required to generate/decrypt the encrypted KQ API env file." >&2
    return 1
  fi

  echo "Generating server-local KQ API env encryption key pair."
  "${SUDO[@]}" openssl genrsa -out "${KQ_API_ENV_PRIVATE_KEY}" 4096 >/dev/null 2>&1
  "${SUDO[@]}" chmod 600 "${KQ_API_ENV_PRIVATE_KEY}"
  "${SUDO[@]}" openssl rsa -in "${KQ_API_ENV_PRIVATE_KEY}" -pubout -out "${KQ_API_ENV_PUBLIC_KEY}" >/dev/null 2>&1
  "${SUDO[@]}" chmod 644 "${KQ_API_ENV_PUBLIC_KEY}"
  print_api_env_public_key
}

decrypt_api_env_file() {
  local env_file="${INSTALL_DIR}/.env"
  if [[ -n "${KQ_DB_HOST:-}" && -n "${KQ_DB_USER:-}" && -n "${KQ_DB_PASSWORD:-}" ]]; then
    return 0
  fi
  if [[ -s "${env_file}" ]]; then
    return 0
  fi

  if [[ ! -s "${KQ_API_ENV_ENC_FILE}" ]]; then
    ensure_api_env_key_pair || true
    echo "No encrypted KQ API env file found at ${KQ_API_ENV_ENC_FILE}; database-backed API will be skipped until it is added."
    return 0
  fi
  ensure_api_env_key_pair

  local cipher_file plain_file
  cipher_file="$(mktemp)"
  plain_file="$(mktemp)"
  trap 'rm -f "${cipher_file}" "${plain_file}"' RETURN

  if ! base64 -d "${KQ_API_ENV_ENC_FILE}" > "${cipher_file}" 2>/dev/null; then
    echo "Could not base64-decode encrypted KQ API env file: ${KQ_API_ENV_ENC_FILE}" >&2
    return 1
  fi

  if ! "${SUDO[@]}" openssl pkeyutl -decrypt -inkey "${KQ_API_ENV_PRIVATE_KEY}" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
      -in "${cipher_file}" -out "${plain_file}" >/dev/null 2>&1; then
    if ! "${SUDO[@]}" openssl pkeyutl -decrypt -inkey "${KQ_API_ENV_PRIVATE_KEY}" \
        -pkeyopt rsa_padding_mode:oaep \
        -in "${cipher_file}" -out "${plain_file}" >/dev/null 2>&1; then
      if ! "${SUDO[@]}" openssl rsautl -decrypt -oaep -inkey "${KQ_API_ENV_PRIVATE_KEY}" \
          -in "${cipher_file}" -out "${plain_file}" >/dev/null 2>&1; then
        echo "Could not decrypt ${KQ_API_ENV_ENC_FILE} with the server-local private key." >&2
        return 1
      fi
    fi
  fi

  for name in KQ_DB_HOST KQ_DB_USER KQ_DB_PASSWORD; do
    if ! grep -Eq "^${name}=" "${plain_file}"; then
      echo "Decrypted KQ API env is missing ${name}." >&2
      return 1
    fi
  done

  "${SUDO[@]}" cp "${plain_file}" "${env_file}"
  "${SUDO[@]}" chmod 600 "${env_file}"
  echo "Installed decrypted KQ API env to ${env_file}."
}

write_compose_env() {
  local env_file="${INSTALL_DIR}/.env"
  local missing=()
  for name in KQ_DB_HOST KQ_DB_USER KQ_DB_PASSWORD; do
    if [[ -z "${!name:-}" ]]; then
      missing+=("${name}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 && ! -s "${env_file}" ]]; then
    echo "KQ API is enabled but database env is missing: ${missing[*]}" >&2
    echo "Set these as Gitea secrets or create ${env_file} on the server." >&2
    return 1
  fi
  if [[ "${#missing[@]}" -eq 0 ]]; then
    {
      printf 'KQ_API_PORT=%s\n' "${KQ_API_PORT}"
      printf 'KQ_API_PUBLIC_PATH=%s\n' "${KQ_API_PUBLIC_PATH}"
      printf 'KQ_PUBLIC_API_URL=%s\n' "${KQ_PUBLIC_API_URL}"
      printf 'KQ_DB_HOST=%s\n' "${KQ_DB_HOST}"
      printf 'KQ_DB_PORT=%s\n' "${KQ_DB_PORT:-3306}"
      printf 'KQ_DB_USER=%s\n' "${KQ_DB_USER}"
      printf 'KQ_DB_PASSWORD=%s\n' "${KQ_DB_PASSWORD}"
      printf 'KQ_DB_NAME=%s\n' "${KQ_DB_NAME:-kq_remote_link}"
      printf 'KQ_SUBSITE_NAME=%s\n' "${KQ_SUBSITE_NAME:-https://remote.kunqiongai.com/}"
      printf 'KQ_API_WEB_BASE_URL=%s\n' "${KQ_API_WEB_BASE_URL:-https://api-web.kunqiongai.com}"
    } | "${SUDO[@]}" tee "${env_file}" >/dev/null
    "${SUDO[@]}" chmod 600 "${env_file}"
  fi
}

prepare_api_service() {
  if [[ "${KQ_ENABLE_API}" != "Y" ]]; then
    echo "KQ API deployment disabled."
    return
  fi
  if [[ ! -f "${SOURCE_API}/package.json" ]]; then
    echo "KQ API source not found: ${SOURCE_API}" >&2
    return 1
  fi
  decrypt_api_env_file
  if ! write_compose_env; then
    echo "KQ API deployment skipped because database configuration is incomplete."
    echo "hbbs/hbbr deployment will continue so remote desktop service can stay available."
    COMPOSE_PROFILES=""
    return 0
  fi
  echo "Preparing KQ API service files."
  "${SUDO[@]}" rm -rf "${INSTALL_DIR}/api"
  "${SUDO[@]}" mkdir -p "${INSTALL_DIR}/api"
  "${SUDO[@]}" cp -R "${SOURCE_API}/." "${INSTALL_DIR}/api/"
  "${SUDO[@]}" rm -rf "${INSTALL_DIR}/api/node_modules"
  COMPOSE_PROFILES="api"
}

prepare_api_service

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

configure_api_reverse_proxy() {
  if [[ "${COMPOSE_PROFILES}" != "api" ]]; then
    return
  fi
  if ! command -v nginx >/dev/null 2>&1; then
    echo "nginx is not installed; KQ API remains local on 127.0.0.1:${KQ_API_PORT}."
    echo "Public API URL needs a manual reverse proxy to ${KQ_PUBLIC_API_URL}."
    return
  fi

  local conf_dirs=()
  local conf_dir=""
  for candidate in /www/server/panel/vhost/nginx /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/nginx/sites-available; do
    if [[ -d "${candidate}" ]]; then
      conf_dirs+=("${candidate}")
      if [[ -z "${conf_dir}" ]]; then
        conf_dir="${candidate}"
      fi
    fi
  done
  if [[ -z "${conf_dir}" ]]; then
    echo "No nginx conf.d directory found; public API reverse proxy was not installed."
    return
  fi

  local include_file="${conf_dir}/kq-remote-link-api-location.inc"
  echo "Installing KQ API nginx reverse proxy: ${KQ_PUBLIC_API_URL}"
  "${SUDO[@]}" tee "${include_file}" >/dev/null <<NGINX
# Managed by KQ Remote Link deploy script.
location ^~ ${KQ_API_PUBLIC_PATH}/ {
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 30s;
    proxy_connect_timeout 5s;
    proxy_pass http://127.0.0.1:${KQ_API_PORT}/;
}
NGINX

  local existing_conf=""
  local public_host_regex="${PUBLIC_HOST//./\\.}"
  for dir in "${conf_dirs[@]}"; do
    while IFS= read -r file; do
      if "${SUDO[@]}" grep -Eq "server_name[[:space:]][^;]*${public_host_regex}([[:space:];]|$)" "${file}"; then
        existing_conf="${file}"
        break
      fi
    done < <(find "${dir}" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | sort)
    [[ -n "${existing_conf}" ]] && break
  done

  if [[ -z "${existing_conf}" ]]; then
    for dir in "${conf_dirs[@]}"; do
      while IFS= read -r file; do
        if "${SUDO[@]}" grep -Eqi 'gitea|proxy_pass[[:space:]]+http://127\.0\.0\.1:3000|proxy_pass[[:space:]]+http://127\.0\.0\.1:3001' "${file}"; then
          existing_conf="${file}"
          break
        fi
      done < <(find "${dir}" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | sort)
      [[ -n "${existing_conf}" ]] && break
    done
  fi

  insert_nginx_include() {
    local target_conf="$1"
    local marker="# KQ_REMOTE_LINK_API_INCLUDE"
    if "${SUDO[@]}" grep -Fq "${marker}" "${target_conf}"; then
      echo "Existing nginx vhost already includes KQ API location: ${target_conf}"
      return 0
    fi

    local tmp_file
    tmp_file="$(mktemp)"
    if ! "${SUDO[@]}" awk -v include_line="    include ${include_file}; ${marker}" '
      BEGIN { in_server = 0; depth = 0; inserted = 0 }
      {
        line = $0
        if (!inserted && !in_server && line ~ /^[[:space:]]*server[[:space:]]*\{/) {
          in_server = 1
          depth = 1
          print line
          next
        }
        if (in_server) {
          open_line = line
          close_line = line
          opens = gsub(/\{/, "{", open_line)
          closes = gsub(/\}/, "}", close_line)
          if (!inserted && depth == 1 && line ~ /^[[:space:]]*\}/) {
            print include_line
            inserted = 1
          }
          print line
          depth += opens - closes
          if (depth <= 0) {
            in_server = 0
          }
          next
        }
        print line
      }
      END { if (!inserted) exit 42 }
    ' "${target_conf}" > "${tmp_file}"; then
      rm -f "${tmp_file}"
      echo "Could not insert KQ API location into ${target_conf}." >&2
      return 1
    fi

    "${SUDO[@]}" cp "${target_conf}" "${target_conf}.bak.$(date +%Y%m%d%H%M%S)"
    "${SUDO[@]}" cp "${tmp_file}" "${target_conf}"
    rm -f "${tmp_file}"
    echo "Inserted KQ API location into existing nginx vhost: ${target_conf}"
  }

  local dedicated_conf="${conf_dir}/kq-remote-link-api.conf"
  for dir in "${conf_dirs[@]}"; do
    "${SUDO[@]}" rm -f "${dir}/kq-remote-link-api.conf"
  done

  if [[ -n "${existing_conf}" ]]; then
    insert_nginx_include "${existing_conf}"
  else
    echo "No existing nginx vhost was matched; installing a dedicated KQ API vhost."
    "${SUDO[@]}" tee "${dedicated_conf}" >/dev/null <<NGINX
# Managed by KQ Remote Link deploy script.
server {
    listen 80;
    server_name ${PUBLIC_HOST};

    include ${include_file};
}
NGINX
  fi

  local nginx_test
  if ! nginx_test="$("${SUDO[@]}" nginx -t 2>&1)"; then
    printf '%s\n' "${nginx_test}"
    echo "nginx config test failed; remove the managed KQ API include or restore the backup printed above."
    return 1
  fi
  printf '%s\n' "${nginx_test}"
  "${SUDO[@]}" nginx -s reload 2>/dev/null || "${SUDO[@]}" systemctl reload nginx 2>/dev/null || true
}

echo "Using RustDesk relay server: ${KQ_RELAY_SERVER}"
echo "Using RustDesk server key mode: managed key pair"
compose -f rustdesk-server.compose.yml pull hbbs hbbr
open_firewall_ports
if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
  compose -f rustdesk-server.compose.yml build api
fi
compose -f rustdesk-server.compose.yml up -d --force-recreate
configure_api_reverse_proxy
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
if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
  echo "KQ API listens on 127.0.0.1:${KQ_API_PORT} and is published through ${KQ_PUBLIC_API_URL}."
fi

if [[ -f "${INSTALL_DIR}/data/id_ed25519.pub" ]]; then
  echo ""
  echo "hbbs public key:"
  "${SUDO[@]}" cat "${INSTALL_DIR}/data/id_ed25519.pub"
else
  echo ""
  echo "hbbs public key is not present yet. Check container logs if it is not created after startup."
fi
