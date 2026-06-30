# Android Request Gate Control Design

Date: 2026-06-29

## Goal

Build a small Android admin application that can switch the KQ Remote Link middle API service between accepting business requests and maintenance mode.

## Scope

- Add a protected service-side request gate to the existing Express API.
- Keep health checks, download pages/files, static assets, invite pages, payment callbacks, and the admin gate endpoints available while maintenance mode is active.
- Block normal business API routes with HTTP 503 and a clear JSON message while maintenance mode is active.
- Store the gate state in a small JSON file so container restarts do not reset it.
- Create a separate native Android app for operators to view and toggle the gate.

## Service API

- `GET /api/admin/request-gate`: returns current gate state.
- `POST /api/admin/request-gate`: accepts JSON `{ "accepting_requests": boolean, "message": string }` and persists the state.
- Admin calls require `x-kq-admin-token` or `Authorization: Bearer <token>` matching `KQ_ADMIN_GATE_TOKEN`.
- State file defaults to `server/data/request-gate.json` locally and can be overridden by `KQ_REQUEST_GATE_STATE_FILE`.

## Android App

- Independent native Android project under `tools/request-gate-android`.
- Package: `com.kunqiong.remotelink.gatecontrol`.
- Single screen with server URL, admin token, current status, message, refresh button, and toggle button.
- Saves server URL and token in Android SharedPreferences.

## Deployment

- Add `KQ_ADMIN_GATE_TOKEN` and `KQ_REQUEST_GATE_STATE_FILE` to compose/deploy env handling.
- Mount server `./data` into the API container at `/app/data` so request gate state survives container replacement.
