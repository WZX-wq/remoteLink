#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/kq-remote-link-server}"
COMPOSE_FILE="${COMPOSE_FILE:-rustdesk-server.compose.yml}"
PUBLIC_HOST="${PUBLIC_HOST:-remotelink.kunqiongai.com}"
KQ_RELAY_SERVER="${KQ_RELAY_SERVER:-${PUBLIC_HOST}:21117}"
KQ_SERVER_KEY="${KQ_SERVER_KEY:-_}"
KQ_HBBS_PUBLIC_KEY="${KQ_HBBS_PUBLIC_KEY:-}"
KQ_HBBS_SECRET_KEY="${KQ_HBBS_SECRET_KEY:-}"
KQ_ENABLE_API="${KQ_ENABLE_API:-Y}"
KQ_API_PORT="${KQ_API_PORT:-21120}"
KQ_API_PUBLIC_PATH="${KQ_API_PUBLIC_PATH:-/kq-api}"
[[ "${KQ_API_PUBLIC_PATH}" == /* ]] || KQ_API_PUBLIC_PATH="/${KQ_API_PUBLIC_PATH}"
KQ_API_PUBLIC_PATH="${KQ_API_PUBLIC_PATH%/}"
KQ_PUBLIC_API_URL="${KQ_PUBLIC_API_URL:-https://${PUBLIC_HOST}${KQ_API_PUBLIC_PATH}/api}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"
KQ_ENABLE_LOCAL_DB="${KQ_ENABLE_LOCAL_DB:-N}"
KQ_WECHAT_PAY_ENV_NAMES=(
  KQ_WECHAT_PAY_APPID
  KQ_WECHAT_PAY_MCHID
  KQ_WECHAT_PAY_MERCHANT_SERIAL_NO
  KQ_WECHAT_PAY_PRIVATE_KEY
  KQ_WECHAT_PAY_PRIVATE_KEY_PATH
  KQ_WECHAT_PAY_API_V3_KEY
  KQ_WECHAT_PAY_NOTIFY_URL
  KQ_WECHAT_PAY_API_BASE_URL
)
KQ_WECHAT_PAY_ENV_PATTERN='^(KQ_WECHAT_PAY_APPID|KQ_WECHAT_PAY_MCHID|KQ_WECHAT_PAY_MERCHANT_SERIAL_NO|KQ_WECHAT_PAY_PRIVATE_KEY|KQ_WECHAT_PAY_PRIVATE_KEY_PATH|KQ_WECHAT_PAY_API_V3_KEY|KQ_WECHAT_PAY_NOTIFY_URL|KQ_WECHAT_PAY_API_BASE_URL)='
KQ_ALIPAY_ENV_NAMES=(
  KQ_ALIPAY_APP_ID
  KQ_ALIPAY_APPID
  KQ_ALIPAY_PRIVATE_KEY
  KQ_ALIPAY_PRIVATE_KEY_PATH
  KQ_ALIPAY_PUBLIC_KEY
  KQ_ALIPAY_PUBLIC_KEY_PATH
  KQ_ALIPAY_NOTIFY_URL
  KQ_ALIPAY_GATEWAY_URL
)
KQ_ALIPAY_ENV_PATTERN='^(KQ_ALIPAY_APP_ID|KQ_ALIPAY_APPID|KQ_ALIPAY_PRIVATE_KEY|KQ_ALIPAY_PRIVATE_KEY_PATH|KQ_ALIPAY_PUBLIC_KEY|KQ_ALIPAY_PUBLIC_KEY_PATH|KQ_ALIPAY_NOTIFY_URL|KQ_ALIPAY_GATEWAY_URL)='

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
  local env_args=(
    "COMPOSE_PROFILES=${COMPOSE_PROFILES}"
    "KQ_RELAY_SERVER=${KQ_RELAY_SERVER}"
    "KQ_SERVER_KEY=${KQ_SERVER_KEY}"
  )
  local name
  for name in \
    KQ_API_PORT KQ_API_PUBLIC_PATH KQ_PUBLIC_API_URL KQ_SUBSITE_NAME KQ_API_WEB_BASE_URL \
    KQ_DOWNLOAD_URL KQ_DOWNLOAD_FILE_PATH KQ_DOWNLOAD_FILE_NAME KQ_DOWNLOAD_VERSION \
    KQ_DOWNLOAD_SHA256 KQ_ANDROID_DOWNLOAD_URL KQ_ANDROID_DOWNLOAD_FILE_PATH \
    KQ_ANDROID_DOWNLOAD_FILE_NAME KQ_ANDROID_DOWNLOAD_VERSION KQ_ANDROID_DOWNLOAD_SHA256 \
    KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW KQ_DOWNLOAD_RATE_WINDOW_MS \
    KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT KQ_APP_SCHEME \
    KQ_DB_HOST KQ_DB_PORT KQ_DB_USER KQ_DB_PASSWORD KQ_DB_ROOT_PASSWORD KQ_DB_NAME KQ_DB_CREATE_DATABASE \
    KQ_WECHAT_PAY_APPID KQ_WECHAT_PAY_MCHID KQ_WECHAT_PAY_MERCHANT_SERIAL_NO \
    KQ_WECHAT_PAY_PRIVATE_KEY KQ_WECHAT_PAY_PRIVATE_KEY_PATH KQ_WECHAT_PAY_API_V3_KEY \
    KQ_WECHAT_PAY_NOTIFY_URL KQ_WECHAT_PAY_API_BASE_URL \
    KQ_ALIPAY_APP_ID KQ_ALIPAY_APPID KQ_ALIPAY_PRIVATE_KEY KQ_ALIPAY_PRIVATE_KEY_PATH \
    KQ_ALIPAY_PUBLIC_KEY KQ_ALIPAY_PUBLIC_KEY_PATH KQ_ALIPAY_NOTIFY_URL KQ_ALIPAY_GATEWAY_URL; do
    if [[ -n "${!name:-}" ]]; then
      env_args+=("${name}=${!name}")
    fi
  done

  if [[ "${#SUDO[@]}" -eq 0 ]]; then
    env "${env_args[@]}" "${COMPOSE_CMD[@]}" "$@"
  else
    "${SUDO[@]}" env "${env_args[@]}" "${COMPOSE_CMD[@]}" "$@"
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

env_file_has_required_db_config() {
  local env_file="$1"
  [[ -s "${env_file}" ]] || return 1
  for name in KQ_DB_HOST KQ_DB_USER KQ_DB_PASSWORD; do
    if ! grep -Eq "^${name}=.+" "${env_file}"; then
      return 1
    fi
  done
}

print_optional_wechat_pay_env() {
  local name value
  for name in "${KQ_WECHAT_PAY_ENV_NAMES[@]}"; do
    if [[ -n "${!name:-}" ]]; then
      value="${!name}"
      if [[ "${name}" == "KQ_WECHAT_PAY_PRIVATE_KEY" ]]; then
        value="${value//$'\r'/}"
        value="${value//$'\n'/\\n}"
      fi
      printf '%s=%s\n' "${name}" "${value}"
    fi
  done
}

merge_optional_wechat_pay_env() {
  local env_file="$1"
  local has_wechat_env="N"
  local name
  for name in "${KQ_WECHAT_PAY_ENV_NAMES[@]}"; do
    if [[ -n "${!name:-}" ]]; then
      has_wechat_env="Y"
      break
    fi
  done
  [[ "${has_wechat_env}" == "Y" ]] || return 0

  local tmp_env
  tmp_env="$(mktemp)"
  if [[ -s "${env_file}" ]]; then
    "${SUDO[@]}" awk -v pat="${KQ_WECHAT_PAY_ENV_PATTERN}" '$0 !~ pat' "${env_file}" > "${tmp_env}" || true
  fi
  print_optional_wechat_pay_env >> "${tmp_env}"
  "${SUDO[@]}" cp "${tmp_env}" "${env_file}"
  "${SUDO[@]}" chmod 600 "${env_file}"
  rm -f "${tmp_env}"
}

print_optional_alipay_env() {
  local name value
  for name in "${KQ_ALIPAY_ENV_NAMES[@]}"; do
    if [[ -n "${!name:-}" ]]; then
      value="${!name}"
      if [[ "${name}" == "KQ_ALIPAY_PRIVATE_KEY" || "${name}" == "KQ_ALIPAY_PUBLIC_KEY" ]]; then
        value="${value//$'\r'/}"
        value="${value//$'\n'/\\n}"
      fi
      printf '%s=%s\n' "${name}" "${value}"
    fi
  done
}

merge_optional_alipay_env() {
  local env_file="$1"
  local has_alipay_env="N"
  local name
  for name in "${KQ_ALIPAY_ENV_NAMES[@]}"; do
    if [[ -n "${!name:-}" ]]; then
      has_alipay_env="Y"
      break
    fi
  done
  [[ "${has_alipay_env}" == "Y" ]] || return 0

  local tmp_env
  tmp_env="$(mktemp)"
  if [[ -s "${env_file}" ]]; then
    "${SUDO[@]}" awk -v pat="${KQ_ALIPAY_ENV_PATTERN}" '$0 !~ pat' "${env_file}" > "${tmp_env}" || true
  fi
  print_optional_alipay_env >> "${tmp_env}"
  "${SUDO[@]}" cp "${tmp_env}" "${env_file}"
  "${SUDO[@]}" chmod 600 "${env_file}"
  rm -f "${tmp_env}"
}

source_file_has_env_pattern() {
  local source_file="$1"
  local pattern="$2"
  [[ -s "${source_file}" ]] && grep -Eq "${pattern}" "${source_file}"
}

merge_env_file_entries_by_pattern() {
  local env_file="$1"
  local source_file="$2"
  local pattern="$3"
  local tmp_env
  tmp_env="$(mktemp)"
  if [[ -s "${env_file}" ]]; then
    "${SUDO[@]}" awk -v pat="${pattern}" '$0 !~ pat' "${env_file}" > "${tmp_env}" || true
  fi
  awk -v pat="${pattern}" '$0 ~ pat' "${source_file}" >> "${tmp_env}" || true
  "${SUDO[@]}" cp "${tmp_env}" "${env_file}"
  "${SUDO[@]}" chmod 600 "${env_file}"
  rm -f "${tmp_env}"
}

merge_decrypted_optional_payment_env() {
  local env_file="$1"
  local source_file="$2"
  local merged="N"
  if source_file_has_env_pattern "${source_file}" "${KQ_WECHAT_PAY_ENV_PATTERN}"; then
    merge_env_file_entries_by_pattern "${env_file}" "${source_file}" "${KQ_WECHAT_PAY_ENV_PATTERN}"
    merged="Y"
  fi
  if source_file_has_env_pattern "${source_file}" "${KQ_ALIPAY_ENV_PATTERN}"; then
    merge_env_file_entries_by_pattern "${env_file}" "${source_file}" "${KQ_ALIPAY_ENV_PATTERN}"
    merged="Y"
  fi
  if [[ "${merged}" == "Y" ]]; then
    echo "Merged decrypted optional KQ API env into ${env_file}."
  fi
}

ensure_api_env_key_pair() {
  local should_print="${1:-Y}"
  if [[ -s "${KQ_API_ENV_PRIVATE_KEY}" && -s "${KQ_API_ENV_PUBLIC_KEY}" ]]; then
    if [[ "${should_print}" == "Y" ]]; then
      print_api_env_public_key
    fi
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
  if [[ "${should_print}" == "Y" ]]; then
    print_api_env_public_key
  fi
}

decrypt_api_env_cipher_file() {
  local cipher_file="$1"
  local plain_file="$2"
  if "${SUDO[@]}" openssl pkeyutl -decrypt -inkey "${KQ_API_ENV_PRIVATE_KEY}" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
      -in "${cipher_file}" -out "${plain_file}" >/dev/null 2>&1; then
    return 0
  fi
  if "${SUDO[@]}" openssl pkeyutl -decrypt -inkey "${KQ_API_ENV_PRIVATE_KEY}" \
      -pkeyopt rsa_padding_mode:oaep \
      -in "${cipher_file}" -out "${plain_file}" >/dev/null 2>&1; then
    return 0
  fi
  if "${SUDO[@]}" openssl rsautl -decrypt -oaep -inkey "${KQ_API_ENV_PRIVATE_KEY}" \
      -in "${cipher_file}" -out "${plain_file}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

decrypt_chunked_api_env_file() {
  local enc_file="$1"
  local plain_file="$2"
  local line cipher_file chunk_file
  : > "${plain_file}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == "KQ_API_ENV_ENC_CHUNKED_V1" ]] && continue
    cipher_file="$(mktemp)"
    chunk_file="$(mktemp)"
    if ! printf '%s' "${line}" | base64 -d > "${cipher_file}" 2>/dev/null; then
      echo "Could not base64-decode encrypted KQ API env chunk." >&2
      rm -f "${cipher_file}" "${chunk_file}"
      return 1
    fi
    if ! decrypt_api_env_cipher_file "${cipher_file}" "${chunk_file}"; then
      echo "Could not decrypt encrypted KQ API env chunk with the server-local private key." >&2
      rm -f "${cipher_file}" "${chunk_file}"
      return 1
    fi
    cat "${chunk_file}" >> "${plain_file}"
    rm -f "${cipher_file}" "${chunk_file}"
  done < "${enc_file}"
}

decrypt_api_env_file() {
  local env_file="${INSTALL_DIR}/.env"
  local runtime_db_env="N"
  ensure_api_env_key_pair Y || true
  if [[ -n "${KQ_DB_HOST:-}" && -n "${KQ_DB_USER:-}" && -n "${KQ_DB_PASSWORD:-}" ]]; then
    runtime_db_env="Y"
  fi

  if [[ ! -s "${KQ_API_ENV_ENC_FILE}" ]]; then
    if [[ "${runtime_db_env}" == "Y" ]]; then
      return 0
    fi
    if env_file_has_required_db_config "${env_file}"; then
      return 0
    fi
    echo "No encrypted KQ API env file found at ${KQ_API_ENV_ENC_FILE}; database-backed API will be skipped until it is added."
    return 0
  fi
  ensure_api_env_key_pair N

  local cipher_file plain_file
  cipher_file="$(mktemp)"
  plain_file="$(mktemp)"

  if head -n 1 "${KQ_API_ENV_ENC_FILE}" | sed 's/\r$//' | grep -qx 'KQ_API_ENV_ENC_CHUNKED_V1'; then
    if ! decrypt_chunked_api_env_file "${KQ_API_ENV_ENC_FILE}" "${plain_file}"; then
      rm -f "${cipher_file}" "${plain_file}"
      return 1
    fi
  else
    if ! base64 -d "${KQ_API_ENV_ENC_FILE}" > "${cipher_file}" 2>/dev/null; then
      echo "Could not base64-decode encrypted KQ API env file: ${KQ_API_ENV_ENC_FILE}" >&2
      rm -f "${cipher_file}" "${plain_file}"
      return 1
    fi
    if ! decrypt_api_env_cipher_file "${cipher_file}" "${plain_file}"; then
      echo "Could not decrypt ${KQ_API_ENV_ENC_FILE} with the server-local private key." >&2
      rm -f "${cipher_file}" "${plain_file}"
      return 1
    fi
  fi

  local plain_file_has_required_db_config="N"
  if env_file_has_required_db_config "${plain_file}"; then
    plain_file_has_required_db_config="Y"
  fi

  if [[ "${plain_file_has_required_db_config}" == "Y" ]]; then
    "${SUDO[@]}" cp "${plain_file}" "${env_file}"
    "${SUDO[@]}" chmod 600 "${env_file}"
    echo "Installed decrypted KQ API env to ${env_file}."
  elif env_file_has_required_db_config "${env_file}" && (
      source_file_has_env_pattern "${plain_file}" "${KQ_WECHAT_PAY_ENV_PATTERN}" ||
      source_file_has_env_pattern "${plain_file}" "${KQ_ALIPAY_ENV_PATTERN}"
    ); then
    merge_decrypted_optional_payment_env "${env_file}" "${plain_file}"
  elif [[ "${runtime_db_env}" == "Y" ]]; then
    merge_decrypted_optional_payment_env "${env_file}" "${plain_file}"
  else
    for name in KQ_DB_HOST KQ_DB_USER KQ_DB_PASSWORD; do
      if ! grep -Eq "^${name}=.+" "${plain_file}"; then
        echo "Decrypted KQ API env is missing ${name}." >&2
      fi
    done
    rm -f "${cipher_file}" "${plain_file}"
    return 1
  fi
  rm -f "${cipher_file}" "${plain_file}"
}

write_compose_env() {
  local env_file="${INSTALL_DIR}/.env"
  local missing=()
  for name in KQ_DB_HOST KQ_DB_USER KQ_DB_PASSWORD; do
    if [[ -z "${!name:-}" ]]; then
      missing+=("${name}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    if env_file_has_required_db_config "${env_file}"; then
      load_compose_env_file
      merge_optional_wechat_pay_env "${env_file}"
      merge_optional_alipay_env "${env_file}"
      echo "Using existing server-side KQ API .env with required database keys."
      return 0
    fi
    echo "KQ API is enabled but database env is missing: ${missing[*]}" >&2
    echo "Set these as Gitea secrets or create ${env_file} on the server." >&2
    return 1
  fi
  if [[ "${#missing[@]}" -eq 0 ]]; then
    load_compose_env_file
    {
      printf 'KQ_API_PORT=%s\n' "${KQ_API_PORT}"
      printf 'KQ_API_PUBLIC_PATH=%s\n' "${KQ_API_PUBLIC_PATH}"
      printf 'KQ_PUBLIC_API_URL=%s\n' "${KQ_PUBLIC_API_URL}"
      printf 'KQ_DOWNLOAD_URL=%s\n' "${KQ_DOWNLOAD_URL:-https://${PUBLIC_HOST}${KQ_API_PUBLIC_PATH}/download/windows}"
      printf 'KQ_DOWNLOAD_FILE_PATH=%s\n' "${KQ_DOWNLOAD_FILE_PATH:-/app/public/downloads/Kunqiong-Remote-Desktop-Setup.exe}"
      printf 'KQ_DOWNLOAD_FILE_NAME=%s\n' "${KQ_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop-Setup.exe}"
      printf 'KQ_DOWNLOAD_VERSION=%s\n' "${KQ_DOWNLOAD_VERSION:-2026.06.25.2030}"
      printf 'KQ_DOWNLOAD_SHA256=%s\n' "${KQ_DOWNLOAD_SHA256:-6C07977FA2FB0D6B79B104655A851EEBD8133093682B5CAD5DAEE6D8639FF616}"
      printf 'KQ_ANDROID_DOWNLOAD_URL=%s\n' "${KQ_ANDROID_DOWNLOAD_URL:-https://${PUBLIC_HOST}${KQ_API_PUBLIC_PATH}/download/android}"
      printf 'KQ_ANDROID_DOWNLOAD_FILE_PATH=%s\n' "${KQ_ANDROID_DOWNLOAD_FILE_PATH:-/app/public/downloads/Kunqiong-Remote-Desktop.apk}"
      printf 'KQ_ANDROID_DOWNLOAD_FILE_NAME=%s\n' "${KQ_ANDROID_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop.apk}"
      printf 'KQ_ANDROID_DOWNLOAD_VERSION=%s\n' "${KQ_ANDROID_DOWNLOAD_VERSION:-1.4.6+4067}"
      printf 'KQ_ANDROID_DOWNLOAD_SHA256=%s\n' "${KQ_ANDROID_DOWNLOAD_SHA256:-1158207394F9E5A875CDDDBB45A01BE7A3789557157888C6B3A9700095165C8B}"
      printf 'KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW=%s\n' "${KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW:-12}"
      printf 'KQ_DOWNLOAD_RATE_WINDOW_MS=%s\n' "${KQ_DOWNLOAD_RATE_WINDOW_MS:-60000}"
      printf 'KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT=%s\n' "${KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT:-2}"
      printf 'KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT=%s\n' "${KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT:-8}"
      printf 'KQ_APP_SCHEME=%s\n' "${KQ_APP_SCHEME:-kqremote}"
      printf 'KQ_DB_HOST=%s\n' "${KQ_DB_HOST}"
      printf 'KQ_DB_PORT=%s\n' "${KQ_DB_PORT:-3306}"
      printf 'KQ_DB_USER=%s\n' "${KQ_DB_USER}"
      printf 'KQ_DB_PASSWORD=%s\n' "${KQ_DB_PASSWORD}"
      printf 'KQ_DB_NAME=%s\n' "${KQ_DB_NAME:-kq_remote_link}"
      if [[ -n "${KQ_DB_ROOT_PASSWORD:-}" ]]; then
        printf 'KQ_DB_ROOT_PASSWORD=%s\n' "${KQ_DB_ROOT_PASSWORD}"
      fi
      if [[ -n "${KQ_DB_CREATE_DATABASE:-}" ]]; then
        printf 'KQ_DB_CREATE_DATABASE=%s\n' "${KQ_DB_CREATE_DATABASE}"
      fi
      printf 'KQ_SUBSITE_NAME=%s\n' "${KQ_SUBSITE_NAME:-https://remote.kunqiongai.com/}"
      printf 'KQ_API_WEB_BASE_URL=%s\n' "${KQ_API_WEB_BASE_URL:-https://api-web.kunqiongai.com}"
      print_optional_wechat_pay_env
      print_optional_alipay_env
    } | "${SUDO[@]}" tee "${env_file}" >/dev/null
    "${SUDO[@]}" chmod 600 "${env_file}"
  fi
}

load_compose_env_file() {
  local env_file="${INSTALL_DIR}/.env"
  [[ -s "${env_file}" ]] || return 0

  local line name value
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    name="${line%%=*}"
    value="${line#*=}"
    [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    export "${name}=${value}"
  done < <("${SUDO[@]}" cat "${env_file}" 2>/dev/null || true)
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
  load_compose_env_file
  echo "Preparing KQ API service files."
  downloads_backup="$(mktemp -d)"
  if [[ -d "${INSTALL_DIR}/api/public/downloads" ]]; then
    "${SUDO[@]}" cp -a "${INSTALL_DIR}/api/public/downloads/." "${downloads_backup}/" 2>/dev/null || true
  fi
  "${SUDO[@]}" rm -rf "${INSTALL_DIR}/api"
  "${SUDO[@]}" mkdir -p "${INSTALL_DIR}/api"
  "${SUDO[@]}" cp -R "${SOURCE_API}/." "${INSTALL_DIR}/api/"
  "${SUDO[@]}" rm -rf "${INSTALL_DIR}/api/node_modules"
  "${SUDO[@]}" mkdir -p "${INSTALL_DIR}/api/public/downloads"
  if [[ -d "${downloads_backup}" ]]; then
    "${SUDO[@]}" cp -a "${downloads_backup}/." "${INSTALL_DIR}/api/public/downloads/" 2>/dev/null || true
    rm -rf "${downloads_backup}"
  fi
  if [[ -f "${SOURCE_API}/public/downloads/Kunqiong-Remote-Desktop-Setup.exe" ]]; then
    "${SUDO[@]}" install -m 0644 \
      "${SOURCE_API}/public/downloads/Kunqiong-Remote-Desktop-Setup.exe" \
      "${INSTALL_DIR}/api/public/downloads/Kunqiong-Remote-Desktop-Setup.exe"
  fi
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
location = ${KQ_API_PUBLIC_PATH}/download/windows {
    alias ${INSTALL_DIR}/api/public/downloads/Kunqiong-Remote-Desktop-Setup.exe;
    default_type application/vnd.microsoft.portable-executable;
    add_header Content-Disposition "attachment; filename=\"Kunqiong-Remote-Desktop-Setup.exe\"" always;
    add_header Accept-Ranges "bytes" always;
    add_header Cache-Control "private, max-age=300" always;
    add_header Access-Control-Allow-Origin "*" always;
    limit_rate_after 8m;
    limit_rate 3m;
    send_timeout 600s;
}

location = ${KQ_API_PUBLIC_PATH}/download/android {
    alias ${INSTALL_DIR}/api/public/downloads/Kunqiong-Remote-Desktop.apk;
    default_type application/vnd.android.package-archive;
    add_header Content-Disposition "attachment; filename=\"Kunqiong-Remote-Desktop.apk\"" always;
    add_header Accept-Ranges "bytes" always;
    add_header Cache-Control "private, max-age=300" always;
    add_header Access-Control-Allow-Origin "*" always;
    limit_rate_after 8m;
    limit_rate 3m;
    send_timeout 600s;
}

location ^~ ${KQ_API_PUBLIC_PATH}/ {
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
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

allow_kq_in_external_docker_guard() {
  local guard_conf="/etc/kaixinniao/test-slot.conf"
  local kq_prefix="kq-remote-link-"

  if [[ ! -f "${guard_conf}" ]]; then
    return
  fi

  echo "Allowing KQ containers in external Docker guard: ${guard_conf}"
  local current_prefixes normalized new_prefixes
  current_prefixes="$("${SUDO[@]}" awk -F= '/^ALLOWED_PREFIXES=/ {print $2; exit}' "${guard_conf}" 2>/dev/null \
    | sed 's/^"//;s/"$//' \
    | tr -d '[:space:]')"
  normalized=",${current_prefixes},"
  if [[ "${normalized}" != *",${kq_prefix},"* ]]; then
    if [[ -n "${current_prefixes}" ]]; then
      new_prefixes="${current_prefixes},${kq_prefix}"
    else
      new_prefixes="${kq_prefix}"
    fi

    if "${SUDO[@]}" grep -Eq '^ALLOWED_PREFIXES=' "${guard_conf}"; then
      "${SUDO[@]}" sed -i "s|^ALLOWED_PREFIXES=.*|ALLOWED_PREFIXES=${new_prefixes}|" "${guard_conf}"
    else
      printf 'ALLOWED_PREFIXES=%s\n' "${new_prefixes}" | "${SUDO[@]}" tee -a "${guard_conf}" >/dev/null
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    "${SUDO[@]}" systemctl reset-failed kaixinniao-docker-guard.service >/dev/null 2>&1 || true
  fi
}

install_systemd_runtime_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi

  local docker_bin
  docker_bin="$(command -v docker)"
  if [[ -z "${docker_bin}" ]]; then
    return 1
  fi

  local hbbs_bin="${INSTALL_DIR}/bin/hbbs"
  local hbbr_bin="${INSTALL_DIR}/bin/hbbr"
  "${SUDO[@]}" mkdir -p "${INSTALL_DIR}/bin"
  if [[ ! -x "${hbbs_bin}" || ! -x "${hbbr_bin}" ]]; then
    echo "Extracting RustDesk server binaries from rustdesk/rustdesk-server:latest."
    local hbbs_path hbbr_path cid
    hbbs_path="$("${SUDO[@]}" docker run --rm --entrypoint sh rustdesk/rustdesk-server:latest -c 'command -v hbbs' 2>/dev/null || true)"
    hbbr_path="$("${SUDO[@]}" docker run --rm --entrypoint sh rustdesk/rustdesk-server:latest -c 'command -v hbbr' 2>/dev/null || true)"
    if [[ -z "${hbbs_path}" || -z "${hbbr_path}" ]]; then
      echo "Could not locate hbbs/hbbr inside rustdesk/rustdesk-server:latest." >&2
      return 1
    fi
    cid="$("${SUDO[@]}" docker create --entrypoint sh rustdesk/rustdesk-server:latest -c true)"
    "${SUDO[@]}" docker cp "${cid}:${hbbs_path}" "${hbbs_bin}"
    "${SUDO[@]}" docker cp "${cid}:${hbbr_path}" "${hbbr_bin}"
    "${SUDO[@]}" docker rm -f "${cid}" >/dev/null 2>&1 || true
    "${SUDO[@]}" chmod 755 "${hbbs_bin}" "${hbbr_bin}"
  fi

  echo "Installing KQ Remote Link systemd runtime services."
  "${SUDO[@]}" tee /etc/systemd/system/kq-remote-link-hbbr.service >/dev/null <<SERVICE
[Unit]
Description=KQ Remote Link hbbr relay server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=0
WorkingDirectory=${INSTALL_DIR}/data
ExecStart=${hbbr_bin}

[Install]
WantedBy=multi-user.target
SERVICE

  "${SUDO[@]}" tee /etc/systemd/system/kq-remote-link-hbbs.service >/dev/null <<SERVICE
[Unit]
Description=KQ Remote Link hbbs rendezvous server
Requires=kq-remote-link-hbbr.service
After=network-online.target kq-remote-link-hbbr.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=0
WorkingDirectory=${INSTALL_DIR}/data
ExecStart=${hbbs_bin} -r ${KQ_RELAY_SERVER}

[Install]
WantedBy=multi-user.target
SERVICE

  if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
    "${SUDO[@]}" tee /etc/systemd/system/kq-remote-link-api.service >/dev/null <<SERVICE
[Unit]
Description=KQ Remote Link project API
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=0
ExecStartPre=-${docker_bin} rm -f kq-remote-link-api
ExecStart=${docker_bin} run --name kq-remote-link-api --network host --env-file ${INSTALL_DIR}/.env -v ${INSTALL_DIR}/api/public/downloads:/app/public/downloads -e KQ_API_HOST=127.0.0.1 -e KQ_API_PORT=${KQ_API_PORT} -e KQ_PUBLIC_API_URL=${KQ_PUBLIC_API_URL} -e KQ_DOWNLOAD_URL=${KQ_DOWNLOAD_URL:-https://${PUBLIC_HOST}${KQ_API_PUBLIC_PATH}/download/windows} -e KQ_DOWNLOAD_FILE_PATH=${KQ_DOWNLOAD_FILE_PATH:-/app/public/downloads/Kunqiong-Remote-Desktop-Setup.exe} -e KQ_DOWNLOAD_FILE_NAME=${KQ_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop-Setup.exe} -e KQ_DOWNLOAD_VERSION=${KQ_DOWNLOAD_VERSION:-2026.06.25.2030} -e KQ_DOWNLOAD_SHA256=${KQ_DOWNLOAD_SHA256:-6C07977FA2FB0D6B79B104655A851EEBD8133093682B5CAD5DAEE6D8639FF616} -e KQ_ANDROID_DOWNLOAD_URL=${KQ_ANDROID_DOWNLOAD_URL:-https://${PUBLIC_HOST}${KQ_API_PUBLIC_PATH}/download/android} -e KQ_ANDROID_DOWNLOAD_FILE_PATH=${KQ_ANDROID_DOWNLOAD_FILE_PATH:-/app/public/downloads/Kunqiong-Remote-Desktop.apk} -e KQ_ANDROID_DOWNLOAD_FILE_NAME=${KQ_ANDROID_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop.apk} -e KQ_ANDROID_DOWNLOAD_VERSION=${KQ_ANDROID_DOWNLOAD_VERSION:-1.4.6+4067} -e KQ_ANDROID_DOWNLOAD_SHA256=${KQ_ANDROID_DOWNLOAD_SHA256:-1158207394F9E5A875CDDDBB45A01BE7A3789557157888C6B3A9700095165C8B} -e KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW=${KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW:-12} -e KQ_DOWNLOAD_RATE_WINDOW_MS=${KQ_DOWNLOAD_RATE_WINDOW_MS:-60000} -e KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT=${KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT:-2} -e KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT=${KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT:-8} -e KQ_APP_SCHEME=${KQ_APP_SCHEME:-kqremote} -e KQ_SUBSITE_NAME=${KQ_SUBSITE_NAME:-https://remote.kunqiongai.com/} -e KQ_API_WEB_BASE_URL=${KQ_API_WEB_BASE_URL:-https://api-web.kunqiongai.com} -e KQ_DB_POOL_SIZE=${KQ_DB_POOL_SIZE:-2} kq-remote-link-api:latest
ExecStop=${docker_bin} stop -t 10 kq-remote-link-api
ExecStopPost=-${docker_bin} rm -f kq-remote-link-api

[Install]
WantedBy=multi-user.target
SERVICE
  else
    "${SUDO[@]}" systemctl disable --now kq-remote-link-api.service >/dev/null 2>&1 || true
    "${SUDO[@]}" rm -f /etc/systemd/system/kq-remote-link-api.service
  fi

  "${SUDO[@]}" systemctl daemon-reload
  "${SUDO[@]}" systemctl enable kq-remote-link-hbbr.service kq-remote-link-hbbs.service >/dev/null
  if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
    "${SUDO[@]}" systemctl enable kq-remote-link-api.service >/dev/null
  fi

  "${SUDO[@]}" systemctl restart kq-remote-link-hbbr.service
  "${SUDO[@]}" systemctl restart kq-remote-link-hbbs.service
  if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
    "${SUDO[@]}" systemctl restart kq-remote-link-api.service
  fi
}

install_runtime_watchdog() {
  local watchdog_script="/usr/local/sbin/kq-remote-link-watchdog.sh"
  local service_file="/etc/systemd/system/kq-remote-link-watchdog.service"
  local timer_file="/etc/systemd/system/kq-remote-link-watchdog.timer"

  echo "Installing KQ Remote Link runtime watchdog."
  "${SUDO[@]}" tee "${watchdog_script}" >/dev/null <<WATCHDOG
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR}"
COMPOSE_FILE="rustdesk-server.compose.yml"

cd "\${INSTALL_DIR}"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "docker compose or docker-compose is required." >&2
  exit 1
fi

profiles=""
if [[ -d api && -s .env ]] \
    && grep -Eq '^KQ_DB_HOST=.+' .env \
    && grep -Eq '^KQ_DB_USER=.+' .env \
    && grep -Eq '^KQ_DB_PASSWORD=.+' .env; then
  profiles="api"
fi

required_services=(kq-remote-link-hbbr.service kq-remote-link-hbbs.service)
if [[ "\${profiles}" == "api" ]]; then
  required_services+=(kq-remote-link-api.service)
fi

if command -v systemctl >/dev/null 2>&1 \
    && systemctl list-unit-files kq-remote-link-hbbs.service >/dev/null 2>&1; then
  missing_services=()
  for service in "\${required_services[@]}"; do
    if ! systemctl is-active --quiet "\${service}"; then
      missing_services+=("\${service}")
    fi
  done
  if [[ "\${#missing_services[@]}" -eq 0 ]]; then
    exit 0
  fi
  systemctl start "\${missing_services[@]}" || true
  exit 0
fi

required=(kq-remote-link-hbbr kq-remote-link-hbbs)
if [[ "\${profiles}" == "api" ]]; then
  required+=(kq-remote-link-api)
fi

missing=()
for container in "\${required[@]}"; do
  running="\$(docker inspect -f '{{.State.Running}}' "\${container}" 2>/dev/null || true)"
  if [[ "\${running}" != "true" ]]; then
    missing+=("\${container}")
  fi
done

if [[ "\${#missing[@]}" -eq 0 ]]; then
  exit 0
fi

need_compose_up=N
existing=()
for container in "\${missing[@]}"; do
  if docker inspect "\${container}" >/dev/null 2>&1; then
    existing+=("\${container}")
  else
    need_compose_up=Y
  fi
done

if [[ "\${#existing[@]}" -gt 0 ]]; then
  docker start "\${existing[@]}" || need_compose_up=Y
fi

if [[ "\${need_compose_up}" == "Y" ]]; then
  COMPOSE_PROFILES="\${profiles}" "\${COMPOSE_CMD[@]}" -f "\${COMPOSE_FILE}" up -d
fi
WATCHDOG
  "${SUDO[@]}" chmod 755 "${watchdog_script}"

  if command -v systemctl >/dev/null 2>&1; then
    "${SUDO[@]}" tee "${service_file}" >/dev/null <<SERVICE
[Unit]
Description=KQ Remote Link runtime watchdog
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=${watchdog_script}
SERVICE
    "${SUDO[@]}" tee "${timer_file}" >/dev/null <<TIMER
[Unit]
Description=Run KQ Remote Link runtime watchdog every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=10s
Unit=kq-remote-link-watchdog.service

[Install]
WantedBy=timers.target
TIMER
    "${SUDO[@]}" systemctl daemon-reload || true
    "${SUDO[@]}" systemctl enable --now kq-remote-link-watchdog.timer || true
    "${SUDO[@]}" systemctl start kq-remote-link-watchdog.service || true
    return
  fi

  if [[ -d /etc/cron.d ]]; then
    "${SUDO[@]}" tee /etc/cron.d/kq-remote-link-watchdog >/dev/null <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root ${watchdog_script} >/var/log/kq-remote-link-watchdog.log 2>&1
@reboot root sleep 30; ${watchdog_script} >/var/log/kq-remote-link-watchdog.log 2>&1
CRON
  fi
}

echo "Using RustDesk relay server: ${KQ_RELAY_SERVER}"
echo "Using RustDesk server key mode: managed key pair"
compose -f rustdesk-server.compose.yml pull hbbs hbbr
open_firewall_ports
allow_kq_in_external_docker_guard
if [[ "${COMPOSE_PROFILES}" == "api" ]]; then
  if [[ "${KQ_ENABLE_LOCAL_DB}" == "Y" ]]; then
    COMPOSE_PROFILES="api,local-db" compose -f rustdesk-server.compose.yml pull db
  else
    "${SUDO[@]}" docker rm -f kq-remote-link-db >/dev/null 2>&1 || true
  fi
  compose -f rustdesk-server.compose.yml build api
fi
"${SUDO[@]}" docker rm -f kq-remote-link-api kq-remote-link-hbbs kq-remote-link-hbbr >/dev/null 2>&1 || true
if [[ "${KQ_ENABLE_LOCAL_DB}" == "Y" && "${COMPOSE_PROFILES}" == "api" ]]; then
  COMPOSE_PROFILES="api,local-db" compose -f rustdesk-server.compose.yml up -d --force-recreate
else
  if ! install_systemd_runtime_services; then
    compose -f rustdesk-server.compose.yml up -d --force-recreate
  fi
fi
install_runtime_watchdog
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
