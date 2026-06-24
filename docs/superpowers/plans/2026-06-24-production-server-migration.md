# Production Server Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move KQ Remote Link from the current test server `43.154.197.96` to the production server without breaking remote-control connectivity, account/member APIs, downloads, or payment callbacks.

**Architecture:** Bring up the production hbbs/hbbr/API stack first, verify it independently, then switch client build defaults and deployment URLs from the test host to the production host. Keep the old test server online as a rollback target until production Windows and Android builds pass real connection and payment smoke tests.

**Tech Stack:** RustDesk hbbs/hbbr, Docker Compose, Gitea Actions, Flutter/Rust client build, Node project API, nginx reverse proxy, Alipay/WeChat callback URLs.

---

## Blocking Inputs Required Before Execution

- Production public host: IP or domain that will replace `43.154.197.96`.
- Public protocol for project API and downloads: `http` or `https`.
- Whether production will reuse the existing hbbs key pair or generate a new one.
- Production Gitea/runner target: same Gitea runner or a new production runner.
- Production deploy directory, expected default: `/www/wwwroot/KQromoteLink`.
- Production database credentials for `KQ_DB_HOST`, `KQ_DB_PORT`, `KQ_DB_USER`, `KQ_DB_PASSWORD`, `KQ_DB_NAME`.
- Production payment callback URLs registered in Alipay/WeChat merchant consoles.
- Whether the download page should expose the production Windows/Android packages immediately after deploy.

## Files And Responsibilities

- `.gitea/workflows/deploy.yml`: Gitea deployment environment; currently hardcodes `43.154.197.96` for `PUBLIC_HOST`, API URL, Windows download URL, and Android download URL.
- `deploy/deploy-rustdesk-server.sh`: server deploy defaults; currently defaults `PUBLIC_HOST` to `43.154.197.96` and derives API/download URLs from it.
- `deploy/check-rustdesk-server.sh`: post-deploy health checks; currently defaults public API checks to `43.154.197.96`.
- `deploy/rustdesk-server.compose.yml`: compose defaults for API/download URLs and hbbs relay command.
- `deploy/custom-client.example.json`: template for generated client defaults.
- `src/common.rs`: built-in Windows/mobile client defaults for rendezvous server, relay server, and `kq-project-api-server`.
- `flutter/lib/desktop/pages/desktop_home_page.dart`: invite URL fallback currently points at `http://43.154.197.96/kq-api/invite`.
- `scripts/test-kq-release.ps1` and `scripts/verify-kq-remote-link.ps1`: acceptance checks currently assert the test host; update them to assert production values after the migration.
- `scripts/deploy/deploy-android.sh`: Android download metadata fallback.
- `C:\Users\admin\Documents\CodexObsidian\Projects\KQremoteLink\project-memory.md`: durable migration facts after execution.

### Task 1: Production Server Preflight

**Files:**
- No repo changes.
- Server-side checks only.

- [ ] **Step 1: Confirm ports are open on the production host**

Required public ports:

```text
TCP 21115
TCP 21116
UDP 21116
TCP 21117
TCP 21118 optional
TCP 21119 optional
TCP/HTTP path for /kq-api, usually reverse-proxied to 127.0.0.1:21120
```

- [ ] **Step 2: Confirm runtime dependencies on the production host**

Run on production:

```bash
docker --version
docker compose version || docker-compose --version
nginx -v || true
ss -ltnup | grep -E '21115|21116|21117|21120' || true
```

Expected: Docker and docker compose are available; required ports are not occupied by unrelated services.

- [ ] **Step 3: Decide hbbs key strategy**

If existing users must keep connecting without reinstalling clients, reuse the existing `KQ_HBBS_PUBLIC_KEY` and `KQ_HBBS_SECRET_KEY` on production.

If rotating keys, every client build must embed the new public key and older installed clients may fail until updated.

### Task 2: Production Deployment Config

**Files:**
- Modify: `.gitea/workflows/deploy.yml`
- Modify: `deploy/deploy-rustdesk-server.sh`
- Modify: `deploy/check-rustdesk-server.sh`
- Modify: `deploy/rustdesk-server.compose.yml`

- [ ] **Step 1: Replace deploy host defaults**

Replace every deployment default that points to `43.154.197.96` with the confirmed production host.

Run:

```powershell
rg -n "43\\.154\\.197\\.96|http://43\\.154\\.197\\.96" .gitea deploy scripts server src flutter
```

Expected after edits: only historical docs or explicit rollback notes still contain the test host.

- [ ] **Step 2: Configure production API and download URLs**

Use one consistent public base:

```text
KQ_PUBLIC_API_URL=<production public base>/kq-api/api
KQ_DOWNLOAD_URL=<production public base>/kq-api/download/windows
KQ_ANDROID_DOWNLOAD_URL=<production public base>/kq-api/download/android
```

If production uses HTTPS, all three must use HTTPS, and payment callbacks must match the same public host.

- [ ] **Step 3: Validate deploy scripts**

Run locally:

```powershell
& 'E:\Git\bin\bash.exe' -n deploy\deploy-rustdesk-server.sh
& 'E:\Git\bin\bash.exe' -n deploy\check-rustdesk-server.sh
& 'E:\Git\bin\bash.exe' -n scripts\deploy\deploy.sh
```

Expected: exit code 0 for all scripts.

### Task 3: Client Default Migration

**Files:**
- Modify: `src/common.rs`
- Modify: `deploy/custom-client.example.json`
- Modify: `flutter/lib/desktop/pages/desktop_home_page.dart`
- Modify: `scripts/test-kq-release.ps1`
- Modify: `scripts/verify-kq-remote-link.ps1`
- Modify: `scripts/deploy/deploy-android.sh`

- [ ] **Step 1: Replace built-in RustDesk servers**

In `src/common.rs`, replace:

```text
43.154.197.96:21116
43.154.197.96:21117
http://43.154.197.96/kq-api/api
```

with the production rendezvous, relay, and API URLs.

- [ ] **Step 2: Replace desktop invite fallback**

In `flutter/lib/desktop/pages/desktop_home_page.dart`, replace:

```text
http://43.154.197.96/kq-api/invite
```

with the production invite URL.

- [ ] **Step 3: Update test assertions**

Update release verification scripts so a production build fails if any test-host default is still embedded in release-critical code.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-kq-release.ps1 -NoReport
```

Expected: production host checks pass and old test-host checks fail if reintroduced.

### Task 4: Payment And Account Endpoint Migration

**Files:**
- Modify only if host/callback values are currently hardcoded in deployment secrets or env files.

- [ ] **Step 1: Keep login center endpoints unchanged unless product owner says otherwise**

Current login/member upstreams include:

```text
https://login.kunqiongai.com
https://api-web.kunqiongai.com
```

Do not change these just because hbbs/hbbr moved.

- [ ] **Step 2: Update payment callback URLs**

Alipay and WeChat notify URLs must point to production:

```text
<production public base>/kq-api/api/alipay/notify
<production public base>/kq-api/api/wechat-pay/notify
```

The exact URLs must also be registered in the merchant consoles.

- [ ] **Step 3: Verify Android Alipay current flow**

Current decision is HTML checkout form flow, not App Pay SDK. After migration, verify order creation returns web-form payment fields and does not depend on the old App Pay callback path.

### Task 5: Deploy To Production

**Files:**
- No additional code changes after Tasks 2-4.

- [ ] **Step 1: Push migration branch**

Run after local tests pass:

```powershell
git status --short
git add .gitea/workflows/deploy.yml deploy src flutter scripts
git commit -m "Deploy KQ Remote Link to production server"
git push gitea HEAD
```

Expected: Gitea workflow starts for the pushed commit.

- [ ] **Step 2: Watch Gitea Actions**

Expected deploy log lines:

```text
hbbs/hbbr health check passed
KQ API listens on 127.0.0.1:21120
Public API URL .../kq-api/api
```

- [ ] **Step 3: Verify production public health**

Run from local machine:

```powershell
curl.exe -fsS "<production public base>/kq-api/api/health"
curl.exe -I "<production public base>/kq-api/download/android"
curl.exe -I "<production public base>/kq-api/download/windows"
```

Expected: health returns JSON success; downloads return HTTP 200 and expected content types.

### Task 6: Build And Smoke Test Production Clients

**Files:**
- Build artifacts only.

- [ ] **Step 1: Build Android with a higher versionCode**

Run:

```powershell
cd flutter
flutter build apk --no-pub --release --target-platform android-arm64 --build-name 1.4.6 --build-number <next higher versionCode>
```

Expected: APK builds successfully and embeds production API/server defaults.

- [ ] **Step 2: Build Windows installer/package**

Use the current project packaging flow, then verify the generated release manifest and installer hash.

- [ ] **Step 3: Remote-control acceptance**

Install the production build on two devices and verify:

```text
login
online device list
remote screen
mouse
keyboard
clipboard
file transfer
Android-to-PC landscape full-screen behavior
payment entry opens and order creation succeeds
```

### Task 7: Rollback

**Files:**
- No new code if rollback uses old server/build.

- [ ] **Step 1: Keep test server alive**

Do not shut down `43.154.197.96` until production has passed two-device remote control and payment smoke tests.

- [ ] **Step 2: If production fails before client release**

Revert the migration commit:

```powershell
git revert <migration commit>
git push gitea HEAD
```

- [ ] **Step 3: If production fails after clients are installed**

Either ship a new client build pointing back to the test server, or use the app's configurable server settings only if they are intentionally exposed for that build.

## Self-Review

- Spec coverage: migration covers server, client defaults, API/download URLs, payment callbacks, verification, and rollback.
- Placeholder scan: production host values are explicitly listed as blocking inputs because they are not known yet; do not execute replacement steps until those real values are provided.
- Type consistency: file paths and option names match the current project search results.

