#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
OUTPUT_DIR="${OUTPUT_DIR:-/www/wwwroot/KQromoteLink/android}"

mkdir -p "${OUTPUT_DIR}"

apk_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.apk' | sort | tail -n 1 || true)"
if [[ -z "${apk_path}" ]]; then
  echo "No APK artifact found in ${ARTIFACT_DIR}" >&2
  exit 1
fi

install -m 0644 "${apk_path}" "${OUTPUT_DIR}/Kunqiong-Remote-Desktop.apk"
echo "Android APK published to ${OUTPUT_DIR}/Kunqiong-Remote-Desktop.apk"

aab_path="$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.aab' | sort | tail -n 1 || true)"
if [[ -n "${aab_path}" ]]; then
  install -m 0644 "${aab_path}" "${OUTPUT_DIR}/Kunqiong-Remote-Desktop.aab"
  echo "Android AAB published to ${OUTPUT_DIR}/Kunqiong-Remote-Desktop.aab"
else
  echo "No AAB artifact found in ${ARTIFACT_DIR}; APK deploy completed."
fi

(
  cd "${OUTPUT_DIR}"
  sha256sum Kunqiong-Remote-Desktop.apk Kunqiong-Remote-Desktop.aab 2>/dev/null \
    > SHA256SUMS.txt || sha256sum Kunqiong-Remote-Desktop.apk > SHA256SUMS.txt
)

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
      display: grid;
      place-items: center;
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
      padding: 28px;
      border: 1px solid rgba(255,255,255,.72);
      border-radius: 18px;
      background: var(--panel);
      box-shadow: 0 28px 72px rgba(15, 42, 72, .16);
      backdrop-filter: blur(16px);
    }
    h1 { margin: 0 0 10px; font-size: 26px; letter-spacing: 0; }
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
    @media (prefers-color-scheme: dark) {
      :root { --ink: #e8f2ff; --muted: #9bb6d3; --panel: rgba(18, 29, 43, .88); --line: rgba(76, 137, 184, .48); }
      body { background: linear-gradient(135deg, #102033 0%, #14283d 45%, #1d274a 100%); }
    }
  </style>
</head>
<body>
  <main>
    <h1>鲲穹远程桌面 Android</h1>
    <p>下载安装包后，在手机上允许安装并打开应用。首次使用请按引导开启屏幕共享、无障碍、后台运行和悬浮窗等权限。</p>
    <a class="button" href="Kunqiong-Remote-Desktop.apk">下载 Android APK</a>
    <div class="secondary">
      <a href="Kunqiong-Remote-Desktop.aab">AAB 包</a>
      <a href="SHA256SUMS.txt">校验文件</a>
    </div>
  </main>
</body>
</html>
HTML

echo "Android download page published to ${OUTPUT_DIR}/index.html"
