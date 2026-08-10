#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="${ROOT_DIR}/flutter/build_android.sh"
publish_helper="${ROOT_DIR}/flutter/android_release_publish.sh"

if [[ ! -f "${build_script}" ]]; then
  echo "Android build script not found: ${build_script}" >&2
  exit 1
fi

if [[ ! -f "${publish_helper}" ]]; then
  echo "Android release publish helper not found: ${publish_helper}" >&2
  exit 1
fi

source "${publish_helper}"

if ! declare -F publish_android_apk_if_release >/dev/null; then
  echo "Android release publish helper function is missing" >&2
  exit 1
fi

count_exact_statements() {
  local candidate="$1"
  local expected="$2"

  awk -v expected="${expected}" '{
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line == expected) count++
  } END { print count + 0 }' "${candidate}"
}

require_exactly_once() {
  local candidate="$1"
  local expected="$2"
  local count

  count="$(count_exact_statements "${candidate}" "${expected}")"
  if [[ "${count}" -ne 1 ]]; then
    echo "Expected exactly one Android release behavior: ${expected}" >&2
    exit 1
  fi
}

assert_no_temp_files() {
  local fixture_dir="$1"
  local unexpected

  unexpected="$(
    find "${fixture_dir}" -maxdepth 1 -type f \
      ! -name 'source.apk' \
      ! -name 'published.apk' \
      ! -name 'published.apk.json' \
      ! -name 'debug.apk' \
      ! -name 'missing-source.apk' \
      ! -name 'copy-failure.apk' \
      ! -name 'interrupted.apk' \
      ! -name 'interruption-sleep.pid' \
      ! -name 'metadata-interrupted.apk' \
      ! -name 'metadata-interrupted.apk.json' \
      ! -name 'caller-trap.apk' \
      ! -name 'caller-trap.apk.json' \
      ! -name 'caller-term-trap.marker' \
      -print
  )"
  if [[ -n "${unexpected}" ]]; then
    echo "Android release publish helper left temporary files: ${unexpected}" >&2
    exit 1
  fi
}

require_exactly_once "${build_script}" 'source "${ROOT_DIR}/flutter/android_release_publish.sh"'
require_exactly_once "${build_script}" 'apk_path="build/app/outputs/flutter-apk/app-${MODE}.apk"'
require_exactly_once "${build_script}" 'published_apk_path="${ROOT_DIR}/server/public/downloads/Kunqiong-Remote-Desktop.apk"'
require_exactly_once "${build_script}" 'publish_verified_android_apk_if_release "${MODE}" "${apk_path}" "${published_apk_path}" "${ANDROID_RELEASE_VERSION}" "${ANDROID_RELEASE_MIN_VERSION_CODE}" "${ANDROID_RELEASE_EXPECTED_SIGNER_SHA256}"'

if grep -Fq -- '--split-per-abi' "${build_script}"; then
  echo "Android build must overwrite the fixed app-release.apk artifact" >&2
  exit 1
fi

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/kq-android-release-publish.XXXXXX")"
trap 'rm -rf "${fixture_dir}"' EXIT

source_apk="${fixture_dir}/source.apk"
android_version='1.4.6+4068'
published_apk="${fixture_dir}/published.apk"
debug_apk="${fixture_dir}/debug.apk"
missing_source_apk="${fixture_dir}/missing-source.apk"
copy_failure_apk="${fixture_dir}/copy-failure.apk"
interrupted_apk="${fixture_dir}/interrupted.apk"
interruption_sleep_pid_path="${fixture_dir}/interruption-sleep.pid"
metadata_interrupted_apk="${fixture_dir}/metadata-interrupted.apk"
caller_trap_apk="${fixture_dir}/caller-trap.apk"
caller_term_trap_marker="${fixture_dir}/caller-term-trap.marker"

printf 'new release APK\n' > "${source_apk}"
chmod 0644 "${source_apk}"
printf 'old published APK\n' > "${published_apk}"
chmod 0600 "${published_apk}"
publish_android_apk_if_release release "${source_apk}" "${published_apk}" "${android_version}" >/dev/null
cmp -s "${source_apk}" "${published_apk}"
expected_sha256="$(shasum -a 256 "${source_apk}" | awk '{ print toupper($1) }')"
grep -Fq "\"version\":\"${android_version}\"" "${published_apk}.json"
grep -Fq "\"sha256\":\"${expected_sha256}\"" "${published_apk}.json"
if [[ "$(stat -f '%Lp' "${published_apk}.json")" != '644' ]]; then
  echo 'Published Android APK metadata is not server-readable' >&2
  exit 1
fi
if [[ "$(stat -f '%Lp' "${published_apk}")" != "$(stat -f '%Lp' "${source_apk}")" ]]; then
  echo "Published APK mode does not match the source APK mode" >&2
  exit 1
fi
if [[ ! -r "${published_apk}" ]]; then
  echo "Published APK is not readable" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"

printf 'debug destination must remain unchanged\n' > "${debug_apk}"
publish_android_apk_if_release debug "${source_apk}" "${debug_apk}" "${android_version}" >/dev/null
if ! cmp -s "${debug_apk}" <(printf 'debug destination must remain unchanged\n'); then
  echo "Debug publish changed the destination" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"

printf 'missing source destination must remain unchanged\n' > "${missing_source_apk}"
if publish_android_apk_if_release release "${fixture_dir}/does-not-exist.apk" "${missing_source_apk}" "${android_version}" >/dev/null 2>&1; then
  echo "Publishing a missing source APK unexpectedly succeeded" >&2
  exit 1
fi
if ! cmp -s "${missing_source_apk}" <(printf 'missing source destination must remain unchanged\n'); then
  echo "Missing source publish corrupted the destination" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"

printf 'copy failure destination must remain unchanged\n' > "${copy_failure_apk}"
cp() {
  return 1
}
if publish_android_apk_if_release release "${source_apk}" "${copy_failure_apk}" "${android_version}" >/dev/null 2>&1; then
  echo "Publishing with a copy failure unexpectedly succeeded" >&2
  exit 1
fi
unset -f cp
if ! cmp -s "${copy_failure_apk}" <(printf 'copy failure destination must remain unchanged\n'); then
  echo "Copy failure publish corrupted the destination" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"

printf 'interrupted destination must remain unchanged\n' > "${interrupted_apk}"
PUBLISH_HELPER="${publish_helper}" SOURCE_APK="${source_apk}" DESTINATION_APK="${interrupted_apk}" ANDROID_VERSION="${android_version}" \
  INTERRUPTION_SLEEP_PID_PATH="${interruption_sleep_pid_path}" \
  bash -c '
    source "${PUBLISH_HELPER}"
    cp() {
      sleep 30 &
      sleep_pid=$!
      printf "%s\n" "${sleep_pid}" > "${INTERRUPTION_SLEEP_PID_PATH}"
      wait "${sleep_pid}"
    }
    publish_android_apk_if_release release "${SOURCE_APK}" "${DESTINATION_APK}" "${ANDROID_VERSION}"
  ' >/dev/null 2>&1 &
publisher_pid=$!
for _ in {1..100}; do
  if [[ -s "${interruption_sleep_pid_path}" ]]; then
    break
  fi
  sleep 0.1
done
if [[ ! -s "${interruption_sleep_pid_path}" ]]; then
  kill -TERM "${publisher_pid}" 2>/dev/null || true
  wait "${publisher_pid}" 2>/dev/null || true
  echo "Interrupted publish did not start delayed copy" >&2
  exit 1
fi
read -r interruption_sleep_pid < "${interruption_sleep_pid_path}"
interruption_helper_pid="$(ps -o ppid= -p "${interruption_sleep_pid}" | tr -d ' ')"
if [[ ! "${interruption_helper_pid}" =~ ^[0-9]+$ ]]; then
  kill -TERM "${publisher_pid}" 2>/dev/null || true
  wait "${publisher_pid}" 2>/dev/null || true
  echo "Interrupted publish helper process was not found" >&2
  exit 1
fi
kill -TERM "${interruption_sleep_pid}" "${interruption_helper_pid}"
rm -f "${interruption_sleep_pid_path}"
if wait "${publisher_pid}" 2>/dev/null; then
  echo "Publishing interrupted by TERM unexpectedly succeeded" >&2
  exit 1
fi
if ! cmp -s "${interrupted_apk}" <(printf 'interrupted destination must remain unchanged\n'); then
  echo "Interrupted publish corrupted the destination" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"

printf 'metadata interruption destination must remain unchanged\n' > "${metadata_interrupted_apk}"
PUBLISH_HELPER="${publish_helper}" SOURCE_APK="${source_apk}" DESTINATION_APK="${metadata_interrupted_apk}" ANDROID_VERSION="${android_version}" \
  METADATA_DESTINATION="${metadata_interrupted_apk}.json" \
  bash -c '
    source "${PUBLISH_HELPER}"
    mv() {
      command mv "$@"
      if [[ "${!#}" == "${METADATA_DESTINATION}" ]]; then
        kill -TERM "${BASHPID}"
      fi
    }
    publish_android_apk_if_release release "${SOURCE_APK}" "${DESTINATION_APK}" "${ANDROID_VERSION}"
  ' >/dev/null 2>&1 &
publisher_pid=$!
if wait "${publisher_pid}" 2>/dev/null; then
  echo "Publishing interrupted after metadata promotion unexpectedly succeeded" >&2
  exit 1
fi
if ! cmp -s "${metadata_interrupted_apk}" <(printf 'metadata interruption destination must remain unchanged\n'); then
  echo "Metadata interruption exposed a new APK before its metadata was stable" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"

if ! PUBLISH_HELPER="${publish_helper}" SOURCE_APK="${source_apk}" DESTINATION_APK="${caller_trap_apk}" ANDROID_VERSION="${android_version}" \
  CALLER_TERM_TRAP_MARKER="${caller_term_trap_marker}" \
  bash -c '
    source "${PUBLISH_HELPER}"
    caller_term_handler() {
      : > "${CALLER_TERM_TRAP_MARKER}"
    }
    trap caller_term_handler TERM
    publish_android_apk_if_release release "${SOURCE_APK}" "${DESTINATION_APK}" "${ANDROID_VERSION}"
    kill -TERM "$$"
  ' >/dev/null 2>&1; then
  echo "Publish helper changed the caller TERM trap" >&2
  exit 1
fi
if [[ ! -f "${caller_term_trap_marker}" ]]; then
  echo "Caller TERM trap was not preserved" >&2
  exit 1
fi
assert_no_temp_files "${fixture_dir}"
