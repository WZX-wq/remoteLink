#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
OUTPUT_DIR="${OUTPUT_DIR:-/www/wwwroot/KQromoteLink/android}"
API_DOWNLOAD_DIR="${API_DOWNLOAD_DIR:-/www/wwwroot/KQromoteLink/api/public/downloads}"

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${API_DOWNLOAD_DIR}"

apk_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.apk' | sort | tail -n 1 || true)"
if [[ -z "${apk_path}" ]]; then
  echo "No APK artifact found in ${ARTIFACT_DIR}" >&2
  exit 1
fi

find_aapt() {
  if command -v aapt >/dev/null 2>&1; then
    command -v aapt
    return 0
  fi

  local sdk_root
  for sdk_root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    if [[ -n "${sdk_root}" && -d "${sdk_root}/build-tools" ]]; then
      find "${sdk_root}/build-tools" -type f -name aapt 2>/dev/null | sort -V | tail -n 1
      return 0
    fi
  done

  return 1
}

detect_apk_version() {
  local apk="$1"
  local aapt badging version_name version_code
  aapt="$(find_aapt || true)"
  if [[ -z "${aapt}" ]]; then
    return 1
  fi

  badging="$("${aapt}" dump badging "${apk}" 2>/dev/null || true)"
  version_name="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"${badging}" | head -n 1)"
  version_code="$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"${badging}" | head -n 1)"
  if [[ -z "${version_name}" || -z "${version_code}" ]]; then
    return 1
  fi

  printf '%s+%s\n' "${version_name}" "${version_code}"
}

install -m 0644 "${apk_path}" "${OUTPUT_DIR}/Kunqiong-Remote-Desktop.apk"
install -m 0644 "${apk_path}" "${API_DOWNLOAD_DIR}/Kunqiong-Remote-Desktop.apk"
echo "Android APK published to ${OUTPUT_DIR}/Kunqiong-Remote-Desktop.apk"
echo "Android APK published to ${API_DOWNLOAD_DIR}/Kunqiong-Remote-Desktop.apk for API downloads"

aab_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.aab' | sort | tail -n 1 || true)"
if [[ -n "${aab_path}" ]]; then
  install -m 0644 "${aab_path}" "${OUTPUT_DIR}/Kunqiong-Remote-Desktop.aab"
  install -m 0644 "${aab_path}" "${API_DOWNLOAD_DIR}/Kunqiong-Remote-Desktop.aab"
  echo "Android AAB published to ${OUTPUT_DIR}/Kunqiong-Remote-Desktop.aab"
else
  echo "No AAB artifact found in ${ARTIFACT_DIR}; APK deploy completed."
fi

(
  cd "${OUTPUT_DIR}"
  sha256sum Kunqiong-Remote-Desktop.apk Kunqiong-Remote-Desktop.aab 2>/dev/null \
    > SHA256SUMS.txt || sha256sum Kunqiong-Remote-Desktop.apk > SHA256SUMS.txt
)
install -m 0644 "${OUTPUT_DIR}/SHA256SUMS.txt" "${API_DOWNLOAD_DIR}/SHA256SUMS-android.txt"
android_sha256="$(awk '/Kunqiong-Remote-Desktop\.apk$/ { print $1; exit }' "${OUTPUT_DIR}/SHA256SUMS.txt")"
detected_android_version="$(detect_apk_version "${apk_path}" || true)"
android_version="${KQ_ANDROID_DOWNLOAD_VERSION:-${detected_android_version:-${BUILD_NAME:-1.4.6}+${BUILD_NUMBER:-2067}}}"

ENV_FILE="${KQ_API_ENV_FILE:-/www/wwwroot/KQromoteLink/.env}"
if [[ -f "${ENV_FILE}" ]]; then
  tmp_env="$(mktemp)"
  grep -Ev '^(KQ_ANDROID_DOWNLOAD_URL|KQ_ANDROID_DOWNLOAD_FILE_PATH|KQ_ANDROID_DOWNLOAD_FILE_NAME|KQ_ANDROID_DOWNLOAD_VERSION|KQ_ANDROID_DOWNLOAD_SHA256)=' "${ENV_FILE}" > "${tmp_env}" || true
  {
    printf 'KQ_ANDROID_DOWNLOAD_URL=%s\n' "${KQ_ANDROID_DOWNLOAD_URL:-http://43.154.197.96/kq-api/download/android}"
    printf 'KQ_ANDROID_DOWNLOAD_FILE_PATH=%s\n' "${KQ_ANDROID_DOWNLOAD_FILE_PATH:-/app/public/downloads/Kunqiong-Remote-Desktop.apk}"
    printf 'KQ_ANDROID_DOWNLOAD_FILE_NAME=%s\n' "${KQ_ANDROID_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop.apk}"
    printf 'KQ_ANDROID_DOWNLOAD_VERSION=%s\n' "${android_version}"
    printf 'KQ_ANDROID_DOWNLOAD_SHA256=%s\n' "${android_sha256}"
  } >> "${tmp_env}"
  install -m 0600 "${tmp_env}" "${ENV_FILE}"
  rm -f "${tmp_env}"
  echo "Android download environment updated in ${ENV_FILE}"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files kq-remote-link-api.service >/dev/null 2>&1; then
  systemctl restart kq-remote-link-api.service || true
elif command -v docker >/dev/null 2>&1 && docker inspect kq-remote-link-api >/dev/null 2>&1; then
  docker restart kq-remote-link-api >/dev/null || true
fi

cat > "${OUTPUT_DIR}/index.html" <<'HTML'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>鲲穹远程桌面 Android 下载</title>
  <style>
    :root {
      color-scheme: light dark;
      --ink: #102338;
      --muted: #5f7894;
      --line: rgba(65, 150, 218, .28);
      --panel: rgba(255, 255, 255, .84);
      --primary: #1686e8;
      --primary-2: #0f66c2;
    }
    * { box-sizing: border-box; }
    body {
      min-height: 100vh;
      margin: 0;
      padding: 24px;
      font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at 12% 18%, rgba(67, 203, 230, .32), transparent 25rem),
        radial-gradient(circle at 88% 8%, rgba(76, 139, 238, .34), transparent 28rem),
        linear-gradient(135deg, #edf9ff, #f8fbff 48%, #eaf1ff);
    }
    main {
      width: min(520px, 100%);
      margin: 8vh auto 0;
      padding: 28px;
      border: 1px solid rgba(255,255,255,.72);
      border-radius: 18px;
      background: var(--panel);
      box-shadow: 0 28px 72px rgba(15, 42, 72, .16);
      backdrop-filter: blur(16px);
    }
    .brand { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
    .mark {
      width: 44px;
      height: 44px;
      display: grid;
      place-items: center;
      border-radius: 14px;
      color: #fff;
      font-weight: 900;
      background: linear-gradient(135deg, var(--primary), #41c7ee);
      box-shadow: 0 14px 32px rgba(20, 124, 222, .24);
    }
    h1 { margin: 0; font-size: 25px; letter-spacing: 0; }
    p { margin: 0 0 22px; color: var(--muted); line-height: 1.7; font-weight: 700; }
    a.button {
      width: 100%;
      min-height: 48px;
      border-radius: 12px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: #fff;
      text-decoration: none;
      font-weight: 900;
      background: linear-gradient(135deg, var(--primary), var(--primary-2));
      box-shadow: 0 14px 30px rgba(20, 124, 222, .26);
    }
    .secondary {
      display: flex;
      justify-content: center;
      gap: 16px;
      margin-top: 16px;
      font-size: 13px;
      font-weight: 800;
    }
    .secondary a { color: var(--primary-2); text-decoration: none; }
    .tips {
      margin-top: 22px;
      padding-top: 18px;
      border-top: 1px solid var(--line);
      color: var(--muted);
      font-size: 13px;
      line-height: 1.7;
    }
    @media (prefers-color-scheme: dark) {
      :root { --ink: #e8f2ff; --muted: #9bb6d3; --panel: rgba(18, 29, 43, .88); --line: rgba(76, 137, 184, .48); }
      body { background: linear-gradient(135deg, #102033 0%, #14283d 45%, #1d274a 100%); }
    }
  </style>
</head>
<body>
  <main>
    <div class="brand">
      <div class="mark">KQ</div>
      <h1>鲲穹远程桌面</h1>
    </div>
    <p>下载并安装手机端后，按应用内引导开启必要权限，即可登录账号、连接设备并进行远程协助。</p>
    <a class="button" href="/kq-api/download/android">下载安卓安装包</a>
    <div class="secondary">
      <a href="SHA256SUMS.txt">查看校验信息</a>
    </div>
    <div class="tips">如系统提示需要允许安装，请在手机设置中授权当前浏览器或文件管理器安装应用。首次远程控制前，请根据页面提示开启屏幕共享、无障碍、后台运行等权限。</div>
  </main>
</body>
</html>
HTML

echo "Android download page published to ${OUTPUT_DIR}/index.html"
