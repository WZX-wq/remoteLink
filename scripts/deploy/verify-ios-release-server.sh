#!/usr/bin/env bash
set -euo pipefail

require_https_url() {
  local name="$1"
  local value="${!name:-}"
  if [[ ! "${value}" =~ ^https://[^/]+(/.*)?$ ]]; then
    echo "${name} must be a complete HTTPS URL." >&2
    exit 1
  fi
}

require_https_url KQ_PUBLIC_API_URL
require_https_url KQ_ACCOUNT_DELETE_URL
require_https_url KQ_IOS_IAP_VERIFY_URL

if [[ -z "${KQ_IOS_IAP_PRODUCTS:-}" ]]; then
  echo "KQ_IOS_IAP_PRODUCTS is required." >&2
  exit 1
fi

node --input-type=module - "${KQ_IOS_IAP_PRODUCTS}" <<'NODE'
const raw = process.argv[2] || '';
try {
  const value = JSON.parse(raw);
  if (!value || Array.isArray(value) || typeof value !== 'object') process.exit(1);
  const ids = Object.values(value).map((item) => String(item || '').trim());
  if (!ids.length || ids.some((item) => !item) || new Set(ids).size !== ids.length) process.exit(1);
} catch (_) {
  process.exit(1);
}
NODE

health_url="${KQ_PUBLIC_API_URL%/}/health"
if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 20 "${health_url}" >/dev/null; then
  echo "KQ public API health endpoint is not reachable: ${health_url}" >&2
  exit 1
fi

verify_authenticated_route() {
  local url="$1"
  local label="$2"
  local status
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 20 --request POST "${url}" \
    --header 'Content-Type: application/json' --data '{}' || true)"
  case "${status}" in
    400|401|403|422)
      echo "${label}: routed (HTTP ${status})"
      ;;
    *)
      echo "${label}: expected an authenticated validation response, got HTTP ${status:-no response}." >&2
      exit 1
      ;;
  esac
}

verify_authenticated_route "${KQ_ACCOUNT_DELETE_URL}" 'Account deletion endpoint'
verify_authenticated_route "${KQ_IOS_IAP_VERIFY_URL}" 'Apple purchase verification endpoint'
echo 'iOS release server readiness checks passed.'
