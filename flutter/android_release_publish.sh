#!/usr/bin/env bash

find_android_sdk_tool() {
  local tool_name="$1"
  local tool_path

  if [[ -z "${ANDROID_HOME:-}" || ! -d "${ANDROID_HOME}/build-tools" ]]; then
    echo 'ANDROID_HOME with Android build-tools is required for release verification' >&2
    return 1
  fi

  tool_path="$(find "${ANDROID_HOME}/build-tools" -type f -name "${tool_name}" -print | sort | tail -n 1)"
  if [[ -z "${tool_path}" || ! -x "${tool_path}" ]]; then
    echo "Android SDK ${tool_name} was not found under ${ANDROID_HOME}/build-tools" >&2
    return 1
  fi

  printf '%s\n' "${tool_path}"
}

verify_android_release_apk() {
  local apk_path="$1"
  local minimum_version_code="$2"
  local expected_signer_sha256="$3"
  local aapt2_path apksigner_path badging version_code signer_sha256

  if [[ ! -f "${apk_path}" ]]; then
    echo "Android APK was not found for release verification: ${apk_path}" >&2
    return 1
  fi
  if [[ ! "${minimum_version_code}" =~ ^[0-9]+$ ]]; then
    echo "Android release minimum versionCode is invalid: ${minimum_version_code}" >&2
    return 1
  fi

  expected_signer_sha256="$(printf '%s' "${expected_signer_sha256}" | tr '[:upper:]' '[:lower:]')"
  if [[ ! "${expected_signer_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
    echo 'Android release signer SHA-256 is invalid' >&2
    return 1
  fi

  if ! aapt2_path="$(find_android_sdk_tool aapt2)"; then
    return 1
  fi
  if ! apksigner_path="$(find_android_sdk_tool apksigner)"; then
    return 1
  fi
  if ! badging="$("${aapt2_path}" dump badging "${apk_path}")"; then
    echo 'Unable to inspect Android APK versionCode' >&2
    return 1
  fi
  version_code="$(printf '%s\n' "${badging}" | sed -n "s/.*versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -n 1)"
  if [[ ! "${version_code}" =~ ^[0-9]+$ || "${version_code}" -le "${minimum_version_code}" ]]; then
    echo "Android APK versionCode must be greater than ${minimum_version_code}: ${version_code:-missing}" >&2
    return 1
  fi

  if ! signer_sha256="$("${apksigner_path}" verify --verbose --print-certs "${apk_path}" | awk -F ': ' '/V2 Signer: certificate SHA-256 digest:/ { print $NF; exit }')"; then
    echo 'Unable to inspect Android APK signer' >&2
    return 1
  fi
  signer_sha256="$(printf '%s' "${signer_sha256}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${signer_sha256}" != "${expected_signer_sha256}" ]]; then
    echo "Android APK signer does not match the required release certificate: ${signer_sha256:-missing}" >&2
    return 1
  fi
}

publish_android_apk_if_release() (
  local mode="$1"
  local source_apk="$2"
  local published_apk="$3"
  local android_version="${4:-}"
  local published_dir temp_apk="" metadata_path temp_metadata="" apk_sha256

  cleanup_temporary_artifacts() {
    if [[ -n "${temp_apk}" ]]; then
      rm -f "${temp_apk}"
    fi
    if [[ -n "${temp_metadata}" ]]; then
      rm -f "${temp_metadata}"
    fi
  }

  if [[ "${mode}" != "release" ]]; then
    return 0
  fi
  if [[ ! "${android_version}" =~ ^[0-9A-Za-z.+_-]+$ ]]; then
    echo "Android release version metadata is invalid: ${android_version:-missing}" >&2
    return 1
  fi

  trap cleanup_temporary_artifacts EXIT
  trap 'cleanup_temporary_artifacts; exit 143' HUP INT TERM

  published_dir="$(dirname "${published_apk}")"
  metadata_path="${published_apk}.json"
  if ! mkdir -p "${published_dir}"; then
    echo "Unable to create Android APK publish directory: ${published_dir}" >&2
    return 1
  fi

  if ! temp_apk="$(mktemp "${published_dir}/.$(basename "${published_apk}").tmp.XXXXXX")"; then
    echo 'Unable to create temporary Android APK publish file' >&2
    return 1
  fi
  if ! cp -p -f "${source_apk}" "${temp_apk}"; then
    return 1
  fi
  if ! cmp -s "${source_apk}" "${temp_apk}"; then
    return 1
  fi
  if ! apk_sha256="$(shasum -a 256 "${source_apk}" | awk '{ print toupper($1) }')"; then
    echo 'Unable to calculate Android APK SHA-256' >&2
    return 1
  fi
  if ! temp_metadata="$(mktemp "${published_dir}/.$(basename "${metadata_path}").tmp.XXXXXX")"; then
    echo 'Unable to create temporary Android APK metadata file' >&2
    return 1
  fi
  if ! printf '{"version":"%s","sha256":"%s"}\n' "${android_version}" "${apk_sha256}" > "${temp_metadata}"; then
    return 1
  fi
  if ! chmod 0644 "${temp_metadata}"; then
    return 1
  fi
  if ! mv -f "${temp_metadata}" "${metadata_path}"; then
    return 1
  fi
  temp_metadata=""
  if ! mv -f "${temp_apk}" "${published_apk}"; then
    return 1
  fi
  temp_apk=""
  if ! cmp -s "${source_apk}" "${published_apk}"; then
    return 1
  fi

  echo "Published ${published_apk}"
)

publish_verified_android_apk_if_release() {
  local mode="$1"
  local source_apk="$2"
  local published_apk="$3"
  local android_version="$4"
  local minimum_version_code="$5"
  local expected_signer_sha256="$6"

  if [[ "${mode}" != "release" ]]; then
    return 0
  fi
  if ! verify_android_release_apk "${source_apk}" "${minimum_version_code}" "${expected_signer_sha256}"; then
    return 1
  fi
  publish_android_apk_if_release "${mode}" "${source_apk}" "${published_apk}" "${android_version}"
}
