# Designer Desktop UI Design

## Goal

Make the Windows desktop Flutter UI match the designer-provided desktop prototype under `C:\Users\admin\xwechat_files\wxid_0o85ryaukkgp22_ee41\msg\file\2026-06\鲲穹远程桌面（桌面端）\鲲穹远程桌面（桌面端）`, while preserving existing remote connection, login, membership, settings, recent-history, and device-list logic.

## Scope

- Apply the prototype visual system to desktop pages only.
- Keep the product name `鲲穹远程桌面`.
- Use the prototype hierarchy: 195px blue gradient sidebar, 42px top header, light app background with subtle grid, compact white cards, soft blue borders, and 8-12px radii.
- Include the designer navigation shape: `远程协助`, `设备`, `我的账户`, `设置`, and footer `官网`.
- Convert the current remote-assist home into the prototype layout: member banner, two-column local ID / verification-code card, remote connection card, and recent/saved connection cards.
- Convert account pages into the prototype layout. Logged-out account shows welcome/features plus login card. Logged-in account keeps profile, membership, and remote quality/FPS controls, with the quality/FPS card in the right column.
- Convert settings into the prototype tabbed settings surface: horizontal tabs for common desktop settings categories, compact cards, and existing settings controls.
- Add a devices child page using existing peer/recent data, not static prototype data.

## Non-Goals

- Do not replace existing RustDesk/KQ business logic.
- Do not copy web-only JavaScript behavior from the prototype.
- Do not add camera/view-camera entries.
- Do not change Android/mobile UI in this task.
- Do not publish the new installer to the 43 server unless separately requested.

## Acceptance Checks

- Release regression script contains markers for designer UI mode.
- Desktop home contains markers for designer sidebar, header, member banner, local credentials split card, connect form, and recent device cards.
- Account page contains markers for designer guest/login layout and logged-in right-side remote performance panel.
- Settings page contains markers for designer horizontal tabs and compact settings cards.
- Device page/entry is wired from the desktop sidebar and does not use hardcoded-only fake data.
- `dart format`, `flutter analyze --no-fatal-infos`, `scripts\test-kq-release.ps1 -NoReport`, `scripts\test-kq-oauth.ps1 -NoReport`, `scripts\verify-kq-remote-link.ps1 -SkipBuildEnvCheck`, and CodeGraph sync/status pass before delivery.
