# Android Request Gate Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Android operator app and protected Express middleware that toggles whether business API requests are accepted.

**Architecture:** The Express API owns the request gate state and enforces it through middleware placed after CORS and before business routes. The Android app is a standalone native Java app that calls the protected admin endpoint over HTTP(S).

**Tech Stack:** Node.js 20, Express 4, node:test, Android Gradle Plugin 7.3.1, Java Android Activity.

---

### Task 1: Service Request Gate

**Files:**
- Create: `server/src/request-gate.js`
- Create: `server/test/request-gate.test.js`
- Modify: `server/src/index.js`

- [ ] Add a request gate module with persistent JSON state, admin token validation, allowed-route detection, and Express middleware.
- [ ] Add node:test coverage for default accepting state, persisted maintenance state, admin token rejection, allowed health route, and blocked business route.
- [ ] Wire `GET/POST /api/admin/request-gate` and maintenance middleware into `server/src/index.js`.

### Task 2: Deployment Env

**Files:**
- Modify: `deploy/rustdesk-server.compose.yml`
- Modify: `deploy/deploy-rustdesk-server.sh`
- Modify: `.gitea/workflows/deploy.yml`

- [ ] Add `KQ_ADMIN_GATE_TOKEN` and `KQ_REQUEST_GATE_STATE_FILE` to API env configuration.
- [ ] Mount `./data:/app/data` for the API service.
- [ ] Preserve the admin token env during deploy.

### Task 3: Android Control App

**Files:**
- Create: `tools/request-gate-android/settings.gradle`
- Create: `tools/request-gate-android/build.gradle`
- Create: `tools/request-gate-android/app/build.gradle`
- Create: `tools/request-gate-android/app/src/main/AndroidManifest.xml`
- Create: `tools/request-gate-android/app/src/main/java/com/kunqiong/remotelink/gatecontrol/MainActivity.java`

- [ ] Build a single-screen Java Android app with URL/token inputs, status text, refresh and toggle buttons.
- [ ] Use `HttpURLConnection` and `org.json` only; no external runtime dependencies.
- [ ] Persist operator settings with SharedPreferences.

### Task 4: Verification

- [ ] Run `node --test server/test/request-gate.test.js`.
- [ ] Run `node --check server/src/index.js server/src/request-gate.js`.
- [ ] Run `E:\Git\bin\bash.exe -n deploy/deploy-rustdesk-server.sh`.
- [ ] Run Gradle assemble for `tools/request-gate-android` and copy the APK to `C:\kq-remote-link-tools\android\KQ-Request-Gate-Control.apk`.
