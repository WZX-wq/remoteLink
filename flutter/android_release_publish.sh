#!/usr/bin/env bash

publish_android_apk_if_release() (
  local mode="$1"
  local source_apk="$2"
  local published_apk="$3"
  local published_dir temp_apk=""

  cleanup_temporary_apk() {
    if [[ -n "${temp_apk}" ]]; then
      rm -f "${temp_apk}"
    fi
  }

  if [[ "${mode}" != "release" ]]; then
    return 0
  fi

  trap cleanup_temporary_apk EXIT
  trap 'cleanup_temporary_apk; exit 143' HUP INT TERM

  published_dir="$(dirname "${published_apk}")"
  if ! mkdir -p "${published_dir}"; then
    echo "Unable to create Android APK publish directory: ${published_dir}" >&2
    return 1
  fi

  if ! temp_apk="$(mktemp "${published_dir}/.$(basename "${published_apk}").tmp.XXXXXX")"; then
    echo "Unable to create temporary Android APK publish file" >&2
    return 1
  fi

  if ! cp -p -f "${source_apk}" "${temp_apk}"; then
    rm -f "${temp_apk}"
    return 1
  fi

  if ! cmp -s "${source_apk}" "${temp_apk}"; then
    rm -f "${temp_apk}"
    return 1
  fi

  if ! mv -f "${temp_apk}" "${published_apk}"; then
    return 1
  fi
  temp_apk=""

  if ! cmp -s "${source_apk}" "${published_apk}"; then
    return 1
  fi

  echo "Published ${published_apk}"
)
