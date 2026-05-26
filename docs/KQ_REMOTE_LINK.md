# KQ Remote Link Customization

This branch turns upstream RustDesk into a company desktop remote-control client
prototype with Kunqiong OAuth login.

## What Is Implemented

- Keeps RustDesk's core remote desktop flows: local ID/password, incoming control,
  outgoing connection, file transfer, clipboard, audio, and service mode.
- Adds a desktop OAuth login button: `使用鲲穹账号登录`.
- Opens `https://login.kunqiongai.com/authorize.html` in the system browser.
- Listens for the callback at `http://localhost:6613/oauth/callback`.
- Ignores unrelated local callback-server requests during the OAuth window, so
  a stray browser request such as `/favicon.ico` does not abort login.
- Exchanges the authorization code at
  `https://login.kunqiongai.com/api/oauth/token`.
- Tries JSON token exchange first, then falls back to
  `application/x-www-form-urlencoded` for servers that expect OAuth-style form
  parameters.
- Stores the returned access token and normalized user info in RustDesk's local
  account state so existing account UI shows the logged-in user.
- Marks the session as `external_auth_provider=kunqiong`.
- Skips RustDesk Pro address-book/group cloud sync while this external token is
  active, because the supplied OAuth server is not the RustDesk Pro API server.
- Logs out external sessions locally without waiting on RustDesk's `/api/logout`.

## OAuth Parameters

- App ID: `app_e866d8c8242e2c2b`
- Authorization request includes `response_type=code`
- Callback: `http://localhost:6613/oauth/callback`
- Token endpoint: `POST /api/oauth/token`

The current prototype keeps the app secret in the desktop client because the
provided OAuth flow only documents direct token exchange. For production, move
the code-to-token exchange behind a company backend so `client_secret` is not
distributed in the app package.

## Files Changed

- `flutter/lib/common/kq_oauth.dart`
- `flutter/lib/common/kq_oauth_io.dart`
- `flutter/lib/common/kq_oauth_payload.dart`
- `flutter/lib/common/kq_oauth_stub.dart`
- `flutter/lib/common/widgets/login.dart`
- `flutter/lib/desktop/widgets/tabbar_widget.dart`
- `flutter/lib/models/user_model.dart`
- `flutter/lib/models/ab_model.dart`
- `flutter/lib/models/group_model.dart`
- `Cargo.toml`
- `flutter/windows/runner/Runner.rc`
- `flutter/macos/Runner/Configs/AppInfo.xcconfig`
- `res/rustdesk.desktop`
- `res/rustdesk-link.desktop`
- `res/rustdesk.service`
- `deploy/rustdesk-server.compose.yml`
- `deploy/custom-client.example.json`
- `docs/SERVER_DEPLOYMENT.md`
- `tools/custom_client_signer/Cargo.lock`
- `tools/custom_client_signer/Cargo.toml`
- `tools/custom_client_signer/src/main.rs`
- `scripts/check-build-env.ps1`
- `scripts/bootstrap-windows-build-env.ps1`
- `scripts/start-elevated-bootstrap.ps1`
- `scripts/start-elevated-build.ps1`
- `scripts/build-windows-flutter.ps1`
- `scripts/verify-kq-remote-link.ps1`
- `scripts/package-kq-remote-link.ps1`
- `scripts/test-kq-release.ps1`
- `scripts/run-kq-smoke-suite.ps1`
- `scripts/new-kq-manual-test-report.ps1`
- `scripts/new-kq-two-pc-acceptance.ps1`
- `scripts/collect-kq-diagnostics.ps1`
- `scripts/test-kq-oauth.ps1`
- `scripts/test-kq-server.ps1`
- `build.rs`
- `flutter/test/kq_oauth_payload_test.dart`

## Build Notes

1. Initialize submodules:

   ```powershell
   git submodule update --init --recursive
   ```

2. Install RustDesk's normal Windows build dependencies, including Rust, Flutter,
   LLVM, vcpkg dependencies, MSVC Build Tools, Windows SDK, and platform SDKs.

3. From the repository root, follow upstream RustDesk's Flutter build path for
   Windows. The Flutter SDK must be available on `PATH`.

   ```powershell
   .\scripts\bootstrap-windows-build-env.ps1
   .\scripts\check-build-env.ps1
   .\scripts\verify-kq-remote-link.ps1
   .\scripts\build-windows-flutter.ps1 -SkipPortablePack
   ```

   After a successful Windows release build, package the runnable test bundle:

   ```powershell
   .\scripts\package-kq-remote-link.ps1 -LaunchSmokeTest
   ```

   To package a signed private-server config without modifying the local release
   directory:

   ```powershell
   .\scripts\package-kq-remote-link.ps1 -CustomTxt .\custom.txt
   ```

   To generate and package a private-server client in one step:

   ```powershell
   .\scripts\new-kq-private-server-client-package.ps1 `
     -RendezvousServer "remote.example.com:21116" `
     -RelayServer "remote.example.com:21117" `
     -ServerKey "<hbbs public key>" `
     -PublicKey "<custom-client public key>" `
     -SecretKey "<custom-client secret key>" `
     -BuildClient
   ```

   To generate an acceptance report for the current release directory and zip:

   ```powershell
   .\scripts\test-kq-release.ps1 -PackageZip "C:\kq-remote-link-tools\KQ-Remote-Link-test-20260525-verified.zip"
   ```

   The test zip includes the Windows `Release` directory, release manifest,
   testing and acceptance docs, deploy templates, diagnostics/check scripts,
   and the minimal custom-client signer source needed to generate or verify
   `custom.txt`.

   To create role-specific evidence folders before a two-PC test:

   ```powershell
   .\scripts\new-kq-two-pc-acceptance.ps1 -Role Controlled -LaunchClient
   .\scripts\new-kq-two-pc-acceptance.ps1 -Role Controller -PeerId "<controlled-id>" -LaunchClient
   ```

   To preflight the Kunqiong OAuth environment before a real account login:

   ```powershell
   .\scripts\test-kq-oauth.ps1
   ```

   To run all automated package/OAuth/diagnostics checks in one command:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\run-kq-smoke-suite.ps1 -PackageZip "C:\kq-remote-link-tools\KQ-Remote-Link-test-20260525-verified.zip"
   ```

   To let the bootstrap script install Visual Studio Build Tools and enable
   Windows Developer Mode for Flutter plugin symlinks, run it from an elevated
   PowerShell session:

   ```powershell
   .\scripts\bootstrap-windows-build-env.ps1 -InstallMsvcBuildTools -EnableDeveloperMode
   ```

   From a non-elevated shell, you can also ask Windows to open an Administrator
   bootstrap window:

   ```powershell
   .\scripts\start-elevated-bootstrap.ps1
   ```

   If symlink creation still fails in a non-elevated shell after Developer Mode
   is enabled, run the Windows build in an Administrator window:

   ```powershell
   .\scripts\start-elevated-build.ps1
   ```

   Flutter Windows plugin generation needs Windows symlink support. If you do
   not use `-EnableDeveloperMode`, enable Developer Mode in Windows Settings
   before running `flutter pub get` or the build script.

## Verification In This Workspace

- `git submodule update --init --recursive` completed for `libs/hbb_common`.
- `git diff --check` passed.
- `deploy/custom-client.example.json` passed `python -m json.tool`.
- PowerShell build scripts parsed successfully.
- `scripts/verify-kq-remote-link.ps1 -SkipBuildEnvCheck` passed.
- `scripts/bootstrap-windows-build-env.ps1` installed or prepared Rust, CMake,
  Ninja, LLVM/libclang, vcpkg, MSVC Build Tools, and Flutter.
- The successful Windows build used Flutter `3.24.5`, matching upstream
  RustDesk's Windows Flutter workflow.
- `scripts/check-build-env.ps1` now also checks MSVC `cl.exe`,
  `LIBCLANG_PATH`, and Windows symlink support.
- Targeted Dart analysis passed for the OAuth/login/model changes:
  `dart analyze lib/common/kq_oauth.dart lib/common/kq_oauth_io.dart
  lib/common/kq_oauth_stub.dart lib/common/kq_oauth_payload.dart
  lib/common/widgets/login.dart lib/models/user_model.dart
  lib/models/ab_model.dart lib/models/group_model.dart
  test/kq_oauth_payload_test.dart`.
- `flutter test test/kq_oauth_payload_test.dart` passed 14 tests, covering Kunqiong token
  authorization URL construction, callback `code`/`state` validation, token
  endpoint `code`/`data` validation, token data validation, callback-server
  stray request handling, and user payload normalization into the RustDesk
  login-user shape.
- `cargo fmt --check --manifest-path tools/custom_client_signer/Cargo.toml`
  passed.
- `cargo check --manifest-path tools/custom_client_signer/Cargo.toml` passed
  after Visual Studio Build Tools were installed.
- Branding references were checked across the touched desktop metadata files.
- Full Flutter/Rust Windows release build completed successfully in this
  workspace. The current runnable output is under
  `flutter/build/windows/x64/runner/Release`.

## Manual QA Flow

1. Build and launch the desktop app.
2. Open the account login dialog.
3. Click `使用鲲穹账号登录`.
4. Confirm the system browser opens the Kunqiong authorization page.
5. Complete authorization and verify the browser reaches
   `http://localhost:6613/oauth/callback?code=...&state=...`.
6. Confirm the app shows the returned user as logged in.
7. Close the login dialog during a second OAuth attempt and verify port `6613`
   is released immediately.
8. Verify local remote-control flows still work: show local ID/password,
   connect from another client, accept/control session, clipboard, and file
   transfer.

## Productization To Do

- Move OAuth token exchange to a backend service.
- Fill `deploy/custom-client.example.json` with your production server address
  and `hbbs` public key, then bake it into a signed custom-client config.
- Replace app icons, installer metadata, service names, and bundle identifiers.
- Decide whether company user/device APIs should replace RustDesk Pro
  address-book and group APIs.
- Run full Windows packaging and two-machine remote-control QA.
