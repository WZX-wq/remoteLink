#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="${ROOT_DIR}/flutter/build_android.sh"
publish_helper="${ROOT_DIR}/flutter/android_release_publish.sh"
expected_signer='f9111b87482946b01d90f433b8b00dcf94cec08728891a7d9b5d08150c6caf17'

if [[ ! -f "${build_script}" || ! -f "${publish_helper}" ]]; then
  echo 'Android release build files are missing' >&2
  exit 1
fi

source "${publish_helper}"

if ! declare -F publish_verified_android_apk_if_release >/dev/null; then
  echo 'Android release guard helper function is missing' >&2
  exit 1
fi

require_exactly_once() {
  local candidate="$1"
  local expected="$2"
  local count

  count="$(awk -v expected="${expected}" '{
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line == expected) count++
  } END { print count + 0 }' "${candidate}")"
  if [[ "${count}" -ne 1 ]]; then
    echo "Expected exactly one Android release guard behavior: ${expected}" >&2
    exit 1
  fi
}

require_exactly_once "${build_script}" 'ANDROID_BUILD_NUMBER="${ANDROID_BUILD_NUMBER:-4068}"'
require_exactly_once "${build_script}" 'ANDROID_RELEASE_MIN_VERSION_CODE="${KQ_ANDROID_MIN_VERSION_CODE:-4067}"'
require_exactly_once "${build_script}" 'ANDROID_RELEASE_EXPECTED_SIGNER_SHA256="${KQ_ANDROID_EXPECTED_CERT_SHA256:-f9111b87482946b01d90f433b8b00dcf94cec08728891a7d9b5d08150c6caf17}"'
require_exactly_once "${build_script}" 'flutter build apk --target-platform "${FLUTTER_TARGET}" "--${MODE}" --build-name "${ANDROID_BUILD_NAME}" --build-number "${ANDROID_BUILD_NUMBER}" "${extra_args[@]}"'
require_exactly_once "${build_script}" 'flutter build appbundle --target-platform "${FLUTTER_TARGET}" "--${MODE}" --build-name "${ANDROID_BUILD_NAME}" --build-number "${ANDROID_BUILD_NUMBER}" "${extra_args[@]}"'
require_exactly_once "${build_script}" 'publish_verified_android_apk_if_release "${MODE}" "${apk_path}" "${published_apk_path}" "${ANDROID_RELEASE_VERSION}" "${ANDROID_RELEASE_MIN_VERSION_CODE}" "${ANDROID_RELEASE_EXPECTED_SIGNER_SHA256}"'

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/kq-android-release-guard.XXXXXX")"
trap 'rm -rf "${fixture_dir}"' EXIT

source_apk="${fixture_dir}/source.apk"
published_apk="${fixture_dir}/published.apk"
fake_android_home="${fixture_dir}/android-sdk"
fake_tools="${fake_android_home}/build-tools/99.0.0"

mkdir -p "${fake_tools}"
printf 'new APK\n' > "${source_apk}"
printf 'old APK\n' > "${published_apk}"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "package: name='"'"'com.carriez.flutter_hbb'"'"' versionCode='"'"'%s'"'"'\\n" "${KQ_TEST_ANDROID_VERSION_CODE:?}"' \
  > "${fake_tools}/aapt2"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "V2 Signer: certificate SHA-256 digest: %s\\n" "${KQ_TEST_ANDROID_SIGNER_SHA256:?}"' \
  > "${fake_tools}/apksigner"
chmod +x "${fake_tools}/aapt2" "${fake_tools}/apksigner"

assert_unchanged() {
  local expected="$1"
  if ! cmp -s "${published_apk}" <(printf '%s\n' "${expected}"); then
    echo 'Release guard published an incompatible APK' >&2
    exit 1
  fi
}

if ANDROID_HOME="${fake_android_home}" KQ_TEST_ANDROID_VERSION_CODE=4067 KQ_TEST_ANDROID_SIGNER_SHA256="${expected_signer}" \
  publish_verified_android_apk_if_release release "${source_apk}" "${published_apk}" '1.4.6+4067' 4067 "${expected_signer}" >/dev/null 2>&1; then
  echo 'Low-version Android release unexpectedly published' >&2
  exit 1
fi
assert_unchanged 'old APK'

if ANDROID_HOME="${fake_android_home}" KQ_TEST_ANDROID_VERSION_CODE=4068 KQ_TEST_ANDROID_SIGNER_SHA256='0000000000000000000000000000000000000000000000000000000000000000' \
  publish_verified_android_apk_if_release release "${source_apk}" "${published_apk}" '1.4.6+4068' 4067 "${expected_signer}" >/dev/null 2>&1; then
  echo 'Wrong-signer Android release unexpectedly published' >&2
  exit 1
fi
assert_unchanged 'old APK'

if ANDROID_HOME="${fixture_dir}/missing-sdk" KQ_TEST_ANDROID_VERSION_CODE=4068 KQ_TEST_ANDROID_SIGNER_SHA256="${expected_signer}" \
  publish_verified_android_apk_if_release release "${source_apk}" "${published_apk}" '1.4.6+4068' 4067 "${expected_signer}" >/dev/null 2>&1; then
  echo 'Uninspectable Android release unexpectedly published' >&2
  exit 1
fi
assert_unchanged 'old APK'

ANDROID_HOME="${fake_android_home}" KQ_TEST_ANDROID_VERSION_CODE=4068 KQ_TEST_ANDROID_SIGNER_SHA256="${expected_signer}" \
  publish_verified_android_apk_if_release release "${source_apk}" "${published_apk}" '1.4.6+4068' 4067 "${expected_signer}" >/dev/null
cmp -s "${source_apk}" "${published_apk}"
expected_sha256="$(shasum -a 256 "${source_apk}" | awk '{ print toupper($1) }')"
grep -Fq "\"version\":\"1.4.6+4068\"" "${published_apk}.json"
grep -Fq "\"sha256\":\"${expected_sha256}\"" "${published_apk}.json"
