#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
submodule_dir="${repo_root}/libs/hbb_common"
patch_file="${repo_root}/patches/hbb_common/kq-local-changes.patch"

if [[ ! -d "${submodule_dir}/.git" && ! -f "${submodule_dir}/.git" ]]; then
  echo "hbb_common submodule is not initialized: ${submodule_dir}" >&2
  exit 1
fi

if [[ ! -f "${patch_file}" ]]; then
  echo "hbb_common patch file is missing: ${patch_file}" >&2
  exit 1
fi

if git -C "${submodule_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
  echo "hbb_common KQ patch already applied"
  exit 0
fi

git -C "${submodule_dir}" apply --check "${patch_file}"
git -C "${submodule_dir}" apply "${patch_file}"
echo "hbb_common KQ patch applied"
