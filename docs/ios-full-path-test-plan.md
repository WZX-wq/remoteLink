# 远程桌面 iOS 全路径测试与上线验收文档

> 文档版本：2.0（基于源码路径全覆盖）
> 适用版本：远程桌面 iOS 1.4.6 及后续候选版本
> 主应用 Bundle ID：`com.kunqiong.remotelink`
> ReplayKit 扩展 Bundle ID：`com.kunqiong.remotelink.broadcast`
> App Group：`group.com.kunqiong.remotelink`
> 最低系统版本：iOS 13.0
> 生成日期：2026-07-21
> 依据源码：`flutter/ios/Runner/AppDelegate.swift`、`flutter/ios/KQScreenBroadcast/SampleHandler.swift`、`src/ios_broadcast.rs`、`flutter/lib/mobile/kq_ios_in_app_purchase.dart`、`flutter/lib/common/kq_account_deletion.dart`、`flutter/lib/models/mobile_platform_capability_policy.dart`、`flutter/lib/models/mobile_voice_call_policy.dart`、`flutter/lib/mobile/ios_membership_payment_policy.dart`

---

## 1. 测试目标

本测试文档基于 iOS 实际源码路径全覆盖生成，目标是在上线前关闭所有已知阻断和高优先级问题，确保功能上线可用不报错。

**覆盖原则：**
- 每个源码模块的每个公开路径（函数、状态转换、错误分支）至少对应一条用例。
- 每个错误码、异常分支、边界条件必须有对应验证。
- 网络中断、权限拒绝、服务异常、支付失败等可预期异常，App 必须给出用户可理解的提示，并能安全返回、重试或恢复。
- 测试不能承诺线上永远不发生异常，但必须在上线前证明所有失败路径都有可理解的降级。

---

## 2. iOS 平台边界（源自 `mobile_platform_capability_policy.dart`）

以下是既定产品边界，测试时不得将其误报为缺陷：

| 能力 | iOS 值 | 说明 |
|---|---|---|
| `canControlRemoteDevice` | ✅ | iOS 可控制其他设备 |
| `canHostViewOnlyBroadcast` | ✅ | 可通过 ReplayKit 发起仅观看的屏幕共享 |
| `canReceiveRemoteInput` | ❌ | 被观看的 iOS ReplayKit 屏幕共享为只读，不接受远端键鼠或触控控制 |
| `canUseSystemOverlay` | ❌ | 不支持悬浮窗 |
| `canStartOnBoot` | ❌ | 不支持开机自启 |
| `canUseAccessibilityControl` | ❌ | 不支持无障碍控制 |
| `canRunPersistentBackgroundService` | ❌ | 不支持长期后台常驻服务 |
| `canUseVoiceCall` | ✅ | 支持语音通话 |
| `canTransferFiles` | ✅ | 支持文件传输 |
| `canSyncClipboardInForeground` | ✅ | 支持前台剪贴板同步 |
| `canSyncClipboardInBackground` | ❌ | 不得在后台持续读取或同步剪贴板 |

**支付边界（源自 `ios_membership_payment_policy.dart`）：**
- iOS 会员支付只能使用 Apple StoreKit；不得出现微信、支付宝、二维码或支付链接跳转。
- `KQ_IOS_INTERNAL_DIRECT_PAYMENT=true` 仅允许用于受控内部 Ad Hoc 测试，App Store/TestFlight 构建必须为 `false`。

---

## 3. 上线阻断门槛

任一阻断项未通过，本版本不得提交 TestFlight 外部测试或发布正式环境。

| 编号 | 阻断项 | 通过标准 |
|---|---|---|
| G-01 | 签名与安装包 | macOS/Codemagic 产出可安装 IPA；主 App、ReplayKit 扩展、App Group 签名正确；版本号和构建号唯一。 |
| G-02 | 自动化检查 | `scripts/test-kq-ios-code-readiness.ps1` 全部通过；Flutter、Rust、Node.js、iOS 配置检查无新增分析错误。 |
| G-03 | 真机核心流程 | 至少一台 iPhone 和一台 iPad 完成登录、连接、视频、输入、文件、语音、ReplayKit 验收。 |
| G-04 | 账号注销 | 身份服务真实删除已登录账号并撤销会话；不能只删除项目服务端镜像数据。 |
| G-05 | Apple 内购 | App Store Connect 商品、服务端交易验证、Apple Server Notifications V2 已配置，并完成 Sandbox 验证。 |
| G-06 | 服务端部署 | 测试服务器已部署候选版本，登录、会员、注销、交易验证、通知和隐私地址均可访问。 |
| G-07 | 隐私与合规 | 隐私政策公开地址可访问；隐私标签和加密出口合规项已在 App Store Connect 确认。 |
| G-08 | 缺陷关闭 | 不存在 P0/P1 缺陷；P2 缺陷有书面影响说明、规避方式和产品负责人批准。 |

---

## 4. 测试环境和数据

### 4.1 设备与网络矩阵

| 类型 | 最低覆盖 | 建议补充 |
|---|---|---|
| iPhone | 一台 iOS 13 兼容验证设备、一台当前主流系统真机 | 小屏和大屏机型、当前最新支持系统 |
| iPad | 一台可横竖屏切换的 iPad 真机 | 分屏、外接键盘、Magic Mouse 或触控板 |
| 被控端 | Windows 或 macOS 被控端各一台 | 一台局域网直连、一台仅经中继连接 |
| 网络 | 同一局域网 Wi-Fi、外网 Wi-Fi、蜂窝网络 | 弱网、断网恢复、VPN/代理受限网络 |

### 4.2 账号和数据

| 名称 | 用途 |
|---|---|
| 普通账号 A | 登录、远程连接、基础画质、文件操作。 |
| 会员账号 B | 会员画质、已购恢复、会员权益。 |
| 可注销账号 C | 专用于真实账号注销，不复用日常账号。 |
| Apple Sandbox 账号 | StoreKit 购买、取消、续费和恢复。 |
| 被控端 D/E | D 用于局域网直连，E 用于中继连接；各自配置独立识别码和验证码。 |
| 文件集 | 1 KB 文本、100 MB 文件、中文/空格/长文件名、同名文件、无访问权限文件。 |

### 4.3 执行前检查

- [ ] 记录 App 版本、构建号、测试人员、设备型号、iOS 版本、网络和服务端环境。
- [ ] 测试环境使用独立账号、独立 Apple Sandbox 账号和非生产测试文件。
- [ ] 被控端 D/E 在线，已验证直连和中继路径可用。
- [ ] 已准备录屏、截图和日志导出；缺陷记录需包含发生时间和复现步骤。
- [ ] 关闭旧版本 App 或确认升级路径，避免旧会话和旧缓存干扰结果。

---

## 5. 自动化与构建检查

在仓库根目录执行以下检查。任何命令失败必须记录原因，不得跳过后直接发布。

### 5.1 iOS 代码就绪检查（`scripts/test-kq-ios-code-readiness.ps1`）

该脚本依次执行以下子检查，任一失败即终止：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-kq-ios-code-readiness.ps1
```

**子检查清单：**

| 检查脚本 | 覆盖范围 |
|---|---|
| `test-kq-ios-build-readiness.ps1` | iOS 工程结构、Bundle ID、部署目标、签名配置 |
| `test-kq-ios-rust-linkage.ps1` | Rust `aarch64-apple-ios` 链接、`liblibrustdesk.a` 产物 |
| `test-kq-ios-mobile-ui.ps1` | 移动端 UI 页面、安全区、导航 |
| `test-kq-ios-payment.ps1` | StoreKit 配置、支付策略、验证 URL |
| `test-kq-ios-broadcast-extension.ps1` | ReplayKit 扩展、App Group、bridge |
| `test_ios_release_config.py` | App Store 发布配置（隐私 URL、注销 URL、IAP 商品、验证 URL、HTTPS、禁止直付） |

**Flutter 回归测试（由就绪脚本调用）：**

| 测试文件 | 覆盖范围 |
|---|---|
| `test/kq_remote_video_render_test.dart` | 远程视频渲染 |
| `test/kq_ios_mobile_connection_test.dart` | 移动端连接流程 |
| `test/kq_ios_video_render_test.dart` | iOS 视频渲染 |
| `test/kq_ios_input_toolbar_test.dart` | 输入工具栏 |
| `test/kq_ios_membership_quality_test.dart` | 会员画质 |
| `test/kq_ios_voice_files_clipboard_test.dart` | 语音、文件、剪贴板 |
| `test/kq_ios_platform_capability_test.dart` | 平台能力策略 |
| `test/kq_ios_foreground_clipboard_test.dart` | 前台剪贴板 |
| `test/kq_ios_file_transfer_test.dart` | 文件传输 |
| `test/kq_ios_broadcast_status_contract_test.dart` | ReplayKit 状态契约 |
| `test/kq_ios_privacy_policy_test.dart` | 隐私政策 |
| `test/kq_account_deletion_test.dart` | 账号注销 |
| `test/kq_ios_in_app_purchase_test.dart` | Apple 内购 |
| `test/kq_ios_release_policy_test.dart` | 发布策略 |
| `test/member_session_state_test.dart` | 会员会话状态 |

**Rust 测试（由就绪脚本调用）：**

| 命令 | 覆盖范围 |
|---|---|
| `cargo test -p scrap external_frame` | ReplayKit 帧邮箱 |
| `cargo test kq_remote_video_quality_tests --lib` | 接收端画质 |

### 5.2 服务端测试

```shell
node --test server/test/account-deletion.test.js server/test/apple-entitlement.test.js server/test/apple-iap.test.js server/test/apple-notifications.test.js server/test/deployment-config.test.js
```

### 5.3 Flutter 分析与单元测试

```shell
cd flutter
flutter pub get
flutter analyze
flutter test
```

### 5.4 iOS 构建

```shell
# 未签名（验证原生依赖与 Xcode 工程）
cd flutter
BUILD_MODE=ios ./build_ios.sh

# 已签名 IPA
BUILD_MODE=ipa FLUTTER_BUILD_NAME=<版本号> FLUTTER_BUILD_NUMBER=<递增构建号> ./build_ios.sh
```

### 5.5 自动化检查结果记录

| 检查项 | 结果（通过/失败/阻塞） | 执行人 | 日期 | 说明 |
|---|---|---|---|---|
| iOS 静态配置与发布策略检查 |  |  |  |  |
| Flutter 分析与完整测试 |  |  |  |  |
| Rust 视频、画质、ReplayKit 帧邮箱测试 |  |  |  |  |
| Node.js 账号、内购、通知、部署测试 |  |  |  |  |
| 未签名 iOS 构建 |  |  |  |  |
| 已签名 IPA 构建 |  |  |  |  |

---

## 6. 功能测试用例

用例结果填写为：通过、失败、阻塞、不适用。失败项必须关联缺陷编号。

### A. 安装、启动和升级

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-A01 | 首次安装 | 安装签名 IPA，首次启动。 | 安装成功，无闪退；名称、图标、版本和初始页面正确。 |
| IOS-A02 | 冷启动 | 完全结束 App 后连续启动 3 次。 | 每次成功启动，无白屏、卡死或异常弹窗。 |
| IOS-A03 | 热启动 | 登录后切后台 10 秒，再返回前台。 | 保持或恢复原页面；不重复登录、不崩溃。 |
| IOS-A04 | 覆盖升级 | 从上一测试版本覆盖安装当前版本。 | 会话、保存设备和设置按预期保留；无数据迁移错误。 |
| IOS-A05 | 卸载重装 | 卸载 App 后重新安装并登录。 | 本地数据按 iOS 规则清理；可重新登录和连接。 |
| IOS-A06 | 低存储空间 | 在接近系统低存储状态下启动、导入文件、连接。 | 不崩溃；空间不足时有明确提示，不产生损坏文件。 |

### B. 登录、注册、会话和账号

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-B01 | 密码登录 | 输入有效账号和正确密码。 | 登录成功，进入首页；用户和会员状态正确。 |
| IOS-B02 | 错误密码 | 输入错误密码。 | 提示可理解，不泄露敏感信息，不进入首页。 |
| IOS-B03 | 短信登录 | 获取并输入有效验证码。 | 登录成功；倒计时、重复获取和过期提示正确。 |
| IOS-B04 | 无效验证码 | 输入错误或过期验证码。 | 提示错误，可重新获取，不死循环加载。 |
| IOS-B05 | 注册 | 使用未注册账号完成注册。 | 注册后可登录；重复注册有明确提示。 |
| IOS-B06 | 找回密码 | 完成验证码校验并设置新密码。 | 新密码可登录，旧密码按身份服务规则失效。 |
| IOS-B07 | 登录网络异常 | 登录中关闭网络或让服务端返回错误。 | 有可理解提示，可返回和重试，无内部错误码。 |
| IOS-B08 | 会话过期 | 登录后使令牌失效，再访问受保护页面。 | 安全退出并要求重新登录，不显示他人数据。 |
| IOS-B09 | 主动退出 | 在账户或设置页退出登录。 | 清理会话，返回登录页；受保护页面要求重新登录。 |
| IOS-B10 | 多设备会话 | 同账号在两端登录、退出或被服务端撤销。 | 行为符合身份服务约定；被撤销端有提示且不能继续请求接口。 |

### C. 首页、设备、设置和权限

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-C01 | 页面导航 | 进入远程协助、设备、账户、设置并逐层返回。 | 导航与返回栈正确，无空白页和重复页面。 |
| IOS-C02 | iPhone 安全区 | 在刘海/灵动岛机型浏览主要页面。 | 标题、按钮、底部操作不被系统区域遮挡。 |
| IOS-C03 | iPad 横竖屏 | 在登录、设备、远程页切换横竖屏。 | 版面不重叠、不裁切；连接和输入不中断。 |
| IOS-C04 | 本地网络允许 | 首次连接局域网设备时允许本地网络权限。 | 可发现/连接局域网设备；权限说明与用途一致。 |
| IOS-C05 | 本地网络拒绝 | 拒绝本地网络权限后再次连接局域网设备。 | 说明限制和设置入口，不反复弹系统框或卡住。 |
| IOS-C06 | 文件/相册权限 | 从 Files 导入、保存、取消选择；拒绝后重新授权。 | 允许时可操作；拒绝或取消时安全返回，不崩溃。 |
| IOS-C07 | 麦克风权限入口 | 首次语音时允许、拒绝、到设置页重新授权。 | 每种状态正确识别，不进入假通话状态。 |
| IOS-C08 | 不支持能力 | 检查设置和远程页。 | 不显示或承诺悬浮窗、开机自启、无障碍控制、后台常驻。 |

### D. 远程连接和会话状态

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-D01 | 局域网直连 | 输入 D 的识别码和验证码连接。 | 进入远程页，视频和输入可用。 |
| IOS-D02 | 外网中继 | 使用 E 在非同一局域网连接。 | 通过中继成功连接，视频、输入、文件可用。 |
| IOS-D03 | 错误识别码 | 输入不存在或格式错误的识别码。 | 不连接；提示识别码无效或设备不可达。 |
| IOS-D04 | 错误验证码 | 输入正确识别码和错误验证码。 | 不进入远程页；提示验证码错误，不泄露连接信息。 |
| IOS-D05 | 被控端离线 | 关闭被控端后发起连接。 | 合理等待后提示设备离线，可返回或重试。 |
| IOS-D06 | 连接超时 | 模拟握手或首帧超时。 | 显示用户可理解的超时提示，不长期转圈。 |
| IOS-D07 | 取消连接 | 连接中点击取消或返回。 | 立即停止连接，回到来源页，不残留后台会话。 |
| IOS-D08 | 远端断开 | 已连接时由被控端断开。 | 提示连接结束，回到可再次连接状态。 |
| IOS-D09 | 网络切换 | 已连接时 Wi-Fi 切蜂窝网络，再切回 Wi-Fi。 | 可恢复则恢复；不可恢复时可重连，不崩溃。 |
| IOS-D10 | 后台恢复 | 连接中切后台 30 秒后恢复。 | 按 iOS 限制暂停/恢复；不出现假在线、永久黑屏或错误输入状态。 |
| IOS-D11 | 多次连接 | 连续连接、断开、再次连接同一设备 5 次。 | 每次状态独立，无重复连接、内存异常或页面错乱。 |
| IOS-D12 | 失败文案 | 模拟服务器不可用、中继不可用、VPN 阻断、连接拒绝。 | 显示可理解文案；不显示 socket error、内部标记或裸异常。 |

### E. 视频、画质和远程输入

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-E01 | 首帧显示 | 连接性能正常的被控端。 | 合理时间内显示首帧，不持续黑屏、灰屏或加载。 |
| IOS-E02 | 视频稳定 | 保持会话 10 分钟，并在被控端播放动态画面。 | 画面持续刷新；短暂卡顿后可恢复，不永久冻结。 |
| IOS-E03 | 旋转显示 | 远程画面期间旋转 iPhone/iPad。 | 画面比例、工具栏、触控坐标正确，无拉伸和遮挡。 |
| IOS-E04 | 缩放平移 | 单指拖动、双指缩放、连续放大缩小。 | 画面平滑移动，缩放边界正常，不误触远端。 |
| IOS-E05 | 普通画质 | 普通账号连接后查看画面和帧率。 | 请求基础档位 720p/30 FPS，不人为模糊或黑屏。 |
| IOS-E06 | 会员画质 | 会员账号连接同一被控端进行对比。 | 请求 1080p/60 FPS；端侧能力不足时合理降级且无假会员状态。 |
| IOS-E07 | 单击双击 | 在远端桌面单击、双击图标。 | 远端响应一次且位置正确，不出现重复点击。 |
| IOS-E08 | 拖动长按 | 拖动远端窗口，长按触发对应行为。 | 起止位置正确；长按只产生一次按下和释放。 |
| IOS-E09 | 滚动和手势 | 在远端页面上下滚动、双指缩放。 | 方向和幅度正确，不与画面缩放冲突。 |
| IOS-E10 | 软键盘 | 输入中英文、数字、换行、删除。 | 字符完整到达远端；键盘不遮挡关键操作。 |
| IOS-E11 | 硬件键盘 | 测试 Esc、Tab、Home、End、Delete、方向键、Page Up/Down。 | 对应按键正确发送，无重复或丢键。 |
| IOS-E12 | Magic Mouse | 单击、双击、移动、滚轮。 | 鼠标事件正确，不同时产生重复触控点击。 |
| IOS-E13 | 视频异常恢复 | 模拟视频流中断、首帧超时、后台恢复。 | 有明确提示和重连路径，不需要强制杀死 App。 |

### F. 语音、文件和剪贴板

> **源码依据：** `AppDelegate.swift` 的 `start_ios_voice_capture` / `stop_ios_voice_capture` 方法、`mobile_voice_call_policy.dart` 的 `mobileVoiceCallClosedMessage` 函数。

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-F01 | 语音建立 | 首次发起语音并允许麦克风。 | 双方可听见，音量正常，无明显回声。 |
| IOS-F02 | 语音生命周期 | 发起、接听、主动结束、远端结束。 | 状态提示正确；结束后麦克风资源释放。 |
| IOS-F03 | 语音异常 | 对方拒绝、对方忙、无人接听、网络中断。 | 分别显示可理解提示，可重新发起，不崩溃。 |
| IOS-F04 | Files 导入 | 选择单个、多文件、中文名和长文件名。 | 文件加入队列，名称、大小和数量正确。 |
| IOS-F05 | 文件发送 | 发送 1 KB 和 100 MB 文件至被控端。 | 进度、成功状态和远端完整性正确。 |
| IOS-F06 | 取消和恢复 | 传输中取消；断网形成暂停后点击继续。 | 取消后不继续；暂停项可继续或删除，状态准确。 |
| IOS-F07 | 文件异常 | 同名、无权限、空间不足、远端断开。 | 有明确结果，不生成损坏文件或永久停在进行中。 |
| IOS-F08 | 前台剪贴板 | App 前台时复制中英文、换行、长文本并在远端粘贴。 | 文本同步正确，不泄露给无关会话。 |
| IOS-F09 | 后台剪贴板 | 切后台后在本机复制新文本。 | App 不在后台持续读取或同步；回前台后按用户操作恢复。 |

#### F.2 语音通话关闭提示文案（源自 `mobile_voice_call_policy.dart`）

| ID | 输入 reason | 预期提示 |
|---|---|---|
| IOS-F10 | 空字符串或 `"end connection"` | 返回 `null`（不显示额外提示） |
| IOS-F11 | 包含 `"closed"` 或 `"hangup"` | `"对方已结束语音通话"` |
| IOS-F12 | 包含 `"reject"` 或 `"declin"` | `"对方拒绝了语音通话"` |
| IOS-F13 | 包含 `"busy"` 或 `"another call"` | `"对方正在通话中，请稍后重试"` |
| IOS-F14 | 包含 `"timeout"` / `"no response"` / `"not answer"` | `"对方未接听，请稍后重试"` |
| IOS-F15 | 包含 `"microphone"` / `"permission"` / `"input device"` | `"无法使用麦克风，请检查系统权限后重试"` |
| IOS-F16 | 包含 `"failed"` 或 `"start"` | `"语音通话未能开始，请稍后重试"` |
| IOS-F17 | 其他非空字符串 | `"语音通话已结束"` |

#### F.3 iOS 语音采集原生路径（源自 `AppDelegate.swift`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-F18 | 空会话 ID | 调用 `start_ios_voice_capture("")` 或纯空白。 | 返回 `false`，不启动音频引擎。 |
| IOS-F19 | 正常采集 | 传入非空会话 ID，允许麦克风。 | `AVAudioEngine` 启动，48 kHz 采样，按 960 帧分批发送。 |
| IOS-F20 | 重复启动 | 在已采集状态下再次调用 `start_ios_voice_capture`。 | 先停止旧采集再启动新采集，不残留旧 tap。 |
| IOS-F21 | 停止采集 | 调用 `stop_ios_voice_capture`。 | 移除 input tap、停止引擎、释放会话 ID、停用 `AVAudioSession`。 |
| IOS-F22 | 采样率转换 | 设备返回非 48 kHz 采样率。 | 线性插值重采样到 48 kHz 后发送，不崩溃。 |
| IOS-F23 | 多通道降混 | 设备返回多通道音频。 | 按通道均值降混为单声道后发送。 |
| IOS-F24 | 缓冲区回收 | 持续采集使 `voiceAudioReadIndex` 超过 9600。 | 执行 `removeFirst` 回收，索引归零，不持续内存增长。 |

### G. ReplayKit 屏幕共享和观看状态

> **源码依据：** `SampleHandler.swift`、`src/ios_broadcast.rs`、`KQBroadcastBridge.h`。

#### G.1 基本共享流程

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-G01 | 启动共享 | 打开 ReplayKit 选择器，选择本 App 扩展并开始。 | 系统选择器正常显示，广播状态进入进行中。 |
| IOS-G02 | 共享配置 | 首次启动共享后连接观看端。 | 主 App 与扩展使用同一设备配置，观看端可定位正确设备。 |
| IOS-G03 | 直连观看 | 同局域网由另一设备观看 iOS 屏幕。 | 可收到视频和应用音频，帧计数持续增加。 |
| IOS-G04 | 中继观看 | 外网环境通过中继观看。 | 可收到视频和应用音频；中继状态和失败提示正确。 |
| IOS-G05 | 观看人数 | 无观看端、一个观看端、多个观看端依次连接/断开。 | 显示真实人数；无人观看时明确显示等待状态。 |
| IOS-G06 | 暂停恢复 | 广播中锁屏、切换 App、暂停后恢复。 | 状态、帧数和观看端表现一致；可继续或明确提示重新开始。 |
| IOS-G07 | 停止共享 | 从控制中心或 App 停止广播。 | 广播停止，观看端收到结束状态，资源释放。 |
| IOS-G08 | 只读边界 | 从观看端尝试发送键鼠或触控。 | iOS 共享端不接收远程控制；界面不承诺可控制共享端。 |
| IOS-G09 | 音频隔离 | 同时运行 ReplayKit 与语音通话。 | 应用音频走 ReplayKit，麦克风语音走通话；无重复、串音或回声。 |

#### G.2 ReplayKit 状态机（源自 `SampleHandler.swift` 的 `publishStatus`）

| ID | 状态转换 | 触发 | App Group 键值预期 |
|---|---|---|---|
| IOS-G10 | → `started` | `broadcastStarted` | `kq_broadcast_state="started"`，`transportState="waiting_for_frame"`，帧计数归零 |
| IOS-G11 | → `capturing`（视频） | 首帧或每 30 帧视频 | `kq_broadcast_state="capturing"`，`kq_broadcast_video_frames` 递增，`transportState="ready"` |
| IOS-G12 | → `capturing`（音频） | 首帧或每 100 帧应用音频 | `kq_broadcast_app_audio_frames` 递增，`kq_broadcast_audio_supported=true` |
| IOS-G13 | → `paused` | `broadcastPaused` | `kq_broadcast_state="paused"`，调用 `kq_ios_broadcast_pause()` |
| IOS-G14 | → `resumed` | `broadcastResumed` | `kq_broadcast_state="resumed"`，调用 `kq_ios_broadcast_resume()` |
| IOS-G15 | → `finished` | `broadcastFinished` | `kq_broadcast_state="finished"`，`transportState="stopped"`，调用 `kq_ios_broadcast_stop()` |
| IOS-G16 | → `failed` | 帧提交失败 | `kq_broadcast_state="failed"`，`kq_broadcast_error_code` 非空 |

#### G.3 ReplayKit 错误码（源自 `SampleHandler.swift` 的 `publishFailure`）

| ID | 错误码 | 触发条件 | 预期行为 |
|---|---|---|---|
| IOS-G17 | `missing_pixel_buffer` | `CMSampleBufferGetImageBuffer` 返回 nil | 发布失败状态，不崩溃 |
| IOS-G18 | `unsupported_pixel_format` | 像素格式非 `kCVPixelFormatType_32BGRA` | 发布失败状态，不崩溃 |
| IOS-G19 | `pixel_buffer_lock_failed` | `CVPixelBufferLockBaseAddress` 失败 | 发布失败状态，不崩溃 |
| IOS-G20 | `missing_base_address` | `CVPixelBufferGetBaseAddress` 返回 nil | 发布失败状态，不崩溃 |
| IOS-G21 | `frame_submit_<N>` | `kq_ios_broadcast_push_bgra` 返回非 0 | 发布失败状态，记录错误码 |
| IOS-G22 | `app_group_unavailable` | `sharedConfigDirectory` 返回 nil | 发布失败状态，不启动传输 |
| IOS-G23 | `transport_start_<N>` | `kq_ios_broadcast_start` 返回非 0 | 发布失败状态，不标记 `transportStarted` |
| IOS-G24 | `audio_submit_<N>` | 应用音频提交失败 | 视频继续流式传输，状态含错误码 |

#### G.4 Rust 侧传输状态（源自 `src/ios_broadcast.rs`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-G25 | 启动传输 | `kq_ios_broadcast_start` 传入有效配置目录。 | 返回 `0`，`ACTIVE=true`，`PAUSED=false`，启动 host 线程。 |
| IOS-G26 | 无效配置目录 | 传入空或无效 UTF-8 路径。 | 返回 `1`（`ERR_INVALID_CONFIG_DIR`），不启动。 |
| IOS-G27 | 暂停时推帧 | `kq_ios_broadcast_pause` 后调用 `kq_ios_broadcast_push_bgra`。 | 返回 `ERR_PAUSED`，不提交帧。 |
| IOS-G28 | 无效帧数据 | 传入 null 指针或 `data_len=0`。 | 返回 `2`（`ERR_INVALID_FRAME`）。 |
| IOS-G29 | 帧过大 | 帧数据超过邮箱容量。 | 返回 `3`（`ERR_FRAME_TOO_LARGE`）。 |
| IOS-G30 | 分辨率切换 | 连续推送不同分辨率的帧。 | 触发 `video_service::refresh()`，观看端收到新分辨率。 |
| IOS-G31 | 恢复传输 | `kq_ios_broadcast_resume` 后推帧。 | `PAUSED=false`，触发 `video_service::refresh()`，帧正常提交。 |
| IOS-G32 | 停止传输 | `kq_ios_broadcast_stop`。 | `ACTIVE=false`，`PAUSED=false`，清理帧邮箱，重启 RendezvousMediator。 |
| IOS-G33 | 观看人数计算 | `kq_ios_broadcast_active_viewer_count` 在不同连接数下。 | 返回完成服务端订阅流程的活跃连接数。 |
| IOS-G34 | 音频推送 | `kq_ios_broadcast_push_audio_f32` 传入有效 F32 样本。 | 返回 `0`，样本进入音频队列。 |
| IOS-G35 | 无效音频 | 传入 null 指针或 `sample_count=0`。 | 返回 `ERR_INVALID_AUDIO`，不崩溃。 |

#### G.5 视频缩放路径（源自 `SampleHandler.swift` 的 `normalizedVideoSize`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-G36 | 无需缩放 | 长边 ≤ 1920 的帧。 | 直接提交原始帧，不分配缩放缓冲。 |
| IOS-G37 | 需要缩放 | 长边 > 1920 的帧。 | 按比例缩放到长边 1920，宽高偶数对齐，使用 `vImageScale_ARGB8888` 高质量重采样。 |
| IOS-G38 | 缩放缓冲复用 | 连续推送不同尺寸的缩放帧。 | `scaledFrame` 按需重新分配，不每次创建新数组。 |

#### G.6 App Group 状态读取（源自 `AppDelegate.swift` 的 `getBroadcastStatus`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-G39 | App Group 不可用 | `UserDefaults(suiteName:)` 返回 nil。 | 返回 `state="unavailable"`，`errorCode="app_group_unavailable"`。 |
| IOS-G40 | 正常读取 | 广播进行中读取状态。 | 返回完整状态字典，`isFresh=true`（5 秒内更新）。 |
| IOS-G41 | 状态过期 | 超过 5 秒未更新。 | `isFresh=false`。 |

#### G.7 广播配置目录迁移（源自 `AppDelegate.swift` 的 `prepareBroadcastConfigDirectory`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-G42 | 首次创建 | App Group 容器存在但目录不存在。 | 创建目录，返回路径。 |
| IOS-G43 | 迁移旧配置 | 目录为空且传入 `legacyDir`。 | 复制旧配置文件到新目录，不覆盖已存在文件。 |
| IOS-G44 | 已有配置 | 目录非空。 | 不执行迁移，直接返回路径。 |
| IOS-G45 | App Group 不可用 | `containerURL` 返回 nil。 | 返回 `FlutterError(code: "app_group_unavailable")`。 |
| IOS-G46 | 迁移失败 | 源目录不可读或磁盘错误。 | 返回 `FlutterError(code: "config_migration_failed")`。 |

### H. 会员、Apple 内购、隐私和账号注销

> **源码依据：** `kq_ios_in_app_purchase.dart`、`ios_membership_payment_policy.dart`、`kq_account_deletion.dart`。

#### H.1 会员入口与支付策略

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-H01 | 会员入口 | 普通账号进入会员购买页。 | 仅显示 Apple StoreKit 商品和恢复购买，不显示第三方支付。 |
| IOS-H02 | 内部直付开关 | `KQ_IOS_INTERNAL_DIRECT_PAYMENT=true` 的内部构建。 | 允许外部支付入口（仅限内部 Ad Hoc）。 |
| IOS-H03 | App Store 禁止直付 | `KQ_IOS_INTERNAL_DIRECT_PAYMENT=false` 的发布构建。 | 强制 Apple IAP，不显示外部支付。 |

#### H.2 StoreKit 配置解析（源自 `KqIosInAppPurchaseConfig.fromValues`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-H04 | 有效配置 | 传入有效 JSON 和 HTTPS 验证 URL。 | `isConfigured=true`，`packageToProductId` 非空，`verificationUrl` 非 null。 |
| IOS-H05 | 空 JSON | 传入空字符串。 | `configurationError="StoreKit product mapping is missing."`。 |
| IOS-H06 | 非法 JSON | 传入非 JSON 字符串。 | `configurationError="StoreKit product mapping is invalid."`。 |
| IOS-H07 | 空 ID | JSON 含空键或空值。 | `configurationError="StoreKit product mapping contains an empty ID."`。 |
| IOS-H08 | 重复商品 ID | 两个 package 映射到同一 product ID。 | `configurationError="Each membership package must use a distinct StoreKit product ID."`。 |
| IOS-H09 | 非 HTTPS 验证 URL | 传入 `http://` 或无效 URL。 | `configurationError="StoreKit verification must use a configured HTTPS endpoint."`。 |

#### H.3 StoreKit 购买流程（源自 `KqIosMembershipPurchaseController`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-H10 | 商品加载 | 使用已配置 Sandbox 商品进入购买页。 | 商品名称、价格、周期和权益正确；不可用时提示清晰。 |
| IOS-H11 | 首次购买 | Apple Sandbox 账号购买月度会员。 | Apple 支付成功后经服务端验证，权益及时生效。 |
| IOS-H12 | 取消购买 | 在 Apple 支付弹窗中取消。 | 回到购买页，不错误开通会员，不形成假订单。 |
| IOS-H13 | 验证失败 | 模拟服务端不可用、签名错误、交易无效。 | 不开通权益；可重试，并可通过恢复购买恢复。 |
| IOS-H14 | 恢复购买 | 已购买后重装或换设备，点击恢复购买。 | 恢复有效权益，不重复扣费。 |
| IOS-H15 | 重复购买 | 有有效订阅时再次进入购买。 | 按 Apple 规则处理；订单和权益不重复、不降级。 |
| IOS-H16 | 续费通知 | 在 Sandbox 触发续费/续期事件。 | 服务端验证通知后正确延长到期时间。 |
| IOS-H17 | 撤销/退款/过期 | 触发退款、撤销或过期通知。 | 只影响对应订单，权益重新计算正确，不误伤其他订单。 |
| IOS-H18 | 未知商品 | Apple 返回未映射的 product ID。 | 提示 `"Apple returned an unknown membership product."`，不崩溃。 |
| IOS-H19 | 未登录验证 | 无 access token 时触发验证。 | 抛出 `"Account login is required for Apple purchase verification."`。 |
| IOS-H20 | 验证超时 | 服务端超过 15 秒未响应。 | 提示验证失败，可通过恢复购买重试。 |
| IOS-H21 | 完成交易失败 | `completePurchase` 抛出异常。 | 提示 `"Apple payment was verified, but could not be finalized."`。 |
| IOS-H22 | StoreKit 不可用 | `_store.isAvailable()` 返回 false。 | 提示 `"Apple payment service is unavailable."`。 |
| IOS-H23 | 商品未找到 | `notFoundIDs` 非空。 | `isProductMissing` 返回 true，UI 显示商品不可用。 |
| IOS-H24 | 购买流错误 | `purchaseStream` 发出 `onError`。 | 提示 `"Unable to receive Apple purchase updates."`。 |

#### H.4 隐私政策

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-H25 | 隐私政策 | 从账户/设置打开隐私政策和公开 URL。 | 页面可读、链接可访问，内容与 App Store 版本一致。 |

#### H.5 账号注销（源自 `KqAccountDeletionApi`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-H26 | 注销确认 | 使用账号 C 进入注销页并提交。 | 清楚提示不可逆影响及 Apple 订阅需在 Apple 侧取消；未确认不得删除。 |
| IOS-H27 | 未登录 | 无 token 时调用 `requestDeletion`。 | 抛出 `KqAccountDeletionFailure.notLoggedIn`，提示 `"Please log in first."`。 |
| IOS-H28 | 确认文本错误 | 输入非 `"DELETE"` 的确认文本。 | 抛出 `KqAccountDeletionFailure.confirmationRequired`，提示 `"Enter DELETE to confirm account deletion."`。 |
| IOS-H29 | 未配置端点 | `KQ_ACCOUNT_DELETE_URL` 未设置或非 HTTPS。 | 抛出 `KqAccountDeletionFailure.serviceUnavailable`，提示 `"Account deletion is not configured on the server."`。 |
| IOS-H30 | 真实账号注销 | 身份服务返回 200 `{"success":true,"status":"deleted"}`。 | App 清理本地会话；外部账号和会话按约定删除/撤销。 |
| IOS-H31 | 异步注销 | 身份服务返回 202 `{"success":true,"status":"pending"}`。 | App 清理本地会话，提示删除请求已提交。 |
| IOS-H32 | 注销超时 | 服务端超过 12 秒未响应。 | 抛出 `KqAccountDeletionFailure.requestFailed`，提示 `"The deletion request timed out. Please try again later."`。 |
| IOS-H33 | 注销网络失败 | 网络中断或连接失败。 | 抛出 `KqAccountDeletionFailure.requestFailed`，提示 `"Unable to submit the deletion request. Please try again later."`。 |
| IOS-H34 | 注销服务端错误 | 返回非 2xx 或 `success:false`。 | 不清空本地账号，不假装成功；提示可理解并可重试。 |
| IOS-H35 | 注销响应码异常 | 返回 `code` 非 0/200/202。 | 抛出异常，不假装成功。 |

### I. 稳定性、安全性和兼容性

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-I01 | 长时间会话 | 保持远程视频和语音 30 分钟。 | 无崩溃、明显内存持续增长、严重发热或无法操作。 |
| IOS-I02 | 弱网恢复 | 在高延迟、丢包网络下连接、传文件、观看共享。 | 可理解降级或失败；网络恢复后可重连/继续，不数据错乱。 |
| IOS-I03 | 并发操作 | 视频期间切换画质、打开键盘、文件操作、切后台恢复。 | UI 不重叠、不假死，连接状态一致。 |
| IOS-I04 | 敏感信息 | 检查日志、错误弹窗、截图预览和剪贴板。 | 不展示验证码、令牌、完整密码或其他敏感数据。 |
| IOS-I05 | HTTPS 接口失败 | 配置无效 HTTPS 地址，调用隐私、注销、内购验证接口。 | 拒绝不安全地址或失败响应，不将失败当成功。 |
| IOS-I06 | 深浅色模式 | 切换系统深色和浅色模式浏览主要页面。 | 文字、图标可见，按钮可点击，无颜色重叠。 |
| IOS-I07 | 辅助功能 | 使用大号字体和 VoiceOver 浏览登录、连接、购买、注销。 | 关键控件可识别，文字不重叠、不裁切。 |
| IOS-I08 | 崩溃回归 | 执行所有失败路径后重启 App。 | 无连续崩溃，可恢复到安全页面继续使用。 |

### J. 平台能力策略验证（源自 `mobile_platform_capability_policy.dart`）

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-J01 | iOS 能力集 | 在 iOS 设备读取 `mobilePlatformCapabilities`。 | 返回 `MobilePlatformCapabilities.ios`，11 个能力值与第 2 节一致。 |
| IOS-J02 | 控制远端 | iOS 作为控制端连接被控端。 | `canControlRemoteDevice=true`，可发送键鼠。 |
| IOS-J03 | 被控只读 | iOS 作为 ReplayKit 被观看端。 | `canReceiveRemoteInput=false`，不接收远端输入。 |
| IOS-J04 | 禁止悬浮窗 | 检查设置页。 | `canUseSystemOverlay=false`，不显示悬浮窗入口。 |
| IOS-J05 | 禁止开机自启 | 检查设置页。 | `canStartOnBoot=false`，不显示开机自启入口。 |
| IOS-J06 | 禁止无障碍控制 | 检查设置页。 | `canUseAccessibilityControl=false`，不显示无障碍入口。 |
| IOS-J07 | 禁止后台常驻 | 检查设置页。 | `canRunPersistentBackgroundService=false`，不显示常驻服务入口。 |
| IOS-J08 | 后台剪贴板禁止 | 切后台后复制文本。 | `canSyncClipboardInBackground=false`，不同步。 |

### K. 2FA 双因素认证

> **源码依据：** `src/auth_2fa.rs`、`wire_main_generate2fa`、`wire_main_verify2fa`、`wire_session_send2fa`。

| ID | 测试路径 | 操作 | 预期结果 |
|---|---|---|---|
| IOS-K01 | 生成 2FA | 已登录用户在设置页生成 2FA。 | 返回 TOTP 密钥和二维码，可绑定到认证器 App。 |
| IOS-K02 | 验证 2FA | 输入正确的 6 位 TOTP 码。 | 验证成功，2FA 生效。 |
| IOS-K03 | 错误 2FA 码 | 输入错误或过期码。 | 验证失败，提示可理解，不泄露正确码。 |
| IOS-K04 | 登录 2FA | 已开启 2FA 的账号登录。 | 密码验证后要求输入 2FA 码，正确后进入首页。 |
| IOS-K05 | 2FA 网络异常 | 验证时网络中断。 | 提示可理解，可重试，不崩溃。 |
| IOS-K06 | 禁用 2FA | 已开启 2FA 的用户关闭 2FA。 | 需二次确认，关闭后登录不再要求 2FA。 |

---

## 7. 测试结果与缺陷记录

### 7.1 用例执行汇总

| 模块 | 总数 | 通过 | 失败 | 阻塞 | 不适用 | 结论 |
|---|---:|---:|---:|---:|---:|---|
| A. 安装、启动和升级 | 6 |  |  |  |  |  |
| B. 登录、注册、会话和账号 | 10 |  |  |  |  |  |
| C. 首页、设备、设置和权限 | 8 |  |  |  |  |  |
| D. 远程连接和会话状态 | 12 |  |  |  |  |  |
| E. 视频、画质和远程输入 | 13 |  |  |  |  |  |
| F. 语音、文件和剪贴板 | 24 |  |  |  |  |  |
| G. ReplayKit 屏幕共享和观看状态 | 46 |  |  |  |  |  |
| H. 会员、Apple 内购、隐私和账号注销 | 35 |  |  |  |  |  |
| I. 稳定性、安全性和兼容性 | 8 |  |  |  |  |  |
| J. 平台能力策略验证 | 8 |  |  |  |  |  |
| K. 2FA 双因素认证 | 6 |  |  |  |  |  |
| **合计** | **176** |  |  |  |  |  |

### 7.2 缺陷记录模板

| 字段 | 填写内容 |
|---|---|
| 缺陷编号 |  |
| 关联用例 ID |  |
| 优先级 | P0 阻断 / P1 高 / P2 中 / P3 低 |
| 设备与系统 |  |
| App 版本与构建号 |  |
| 网络与服务端环境 |  |
| 前置条件 |  |
| 复现步骤 |  |
| 实际结果 |  |
| 预期结果 |  |
| 截图、录屏、日志 |  |
| 负责人和修复版本 |  |
| 回归结果 |  |

---

## 8. 最终验收结论

- [ ] G-01 至 G-08 所有上线阻断项均通过。
- [ ] 176 条用例全部执行；失败和阻塞用例已关闭或有书面豁免。
- [ ] P0/P1 缺陷为 0；P2 缺陷已评审并有上线规避方案。
- [ ] 测试服务器完成全路径验证，正式环境关键接口、商品映射和权限与测试环境一致。
- [ ] 已覆盖 iPhone、iPad、直连、Relay、弱网和 Apple Sandbox。

| 角色 | 姓名 | 结论（通过/不通过） | 日期 | 备注 |
|---|---|---|---|---|
| 测试负责人 |  |  |  |  |
| 开发负责人 | 韦忠祥 |  |  |  |
| 产品负责人 |  |  |  |  |
| 发布负责人 |  |  |  |  |

---

## 9. 当前外部前置条件

截至 2026-07-21，代码层的 iOS 适配、ReplayKit 观看状态、暂停文件传输和 Apple 会员通知处理已完成重点检查；以下事项仍需按本文件完成真实环境验证：

1. 可用的 macOS/Xcode 或 Codemagic 签名环境，以及主 App、ReplayKit 扩展和 App Group 的证书与描述文件。
2. 已部署且可访问的身份服务真实账号注销接口。
3. App Store Connect 的 StoreKit 商品、Apple Server API 凭证和 Server Notifications V2 公开通知地址。
4. 测试服务器安全部署权限，以及 iPhone/iPad 真机、直连和中继网络环境。

以上任一项未满足时，应在测试记录中填写"阻塞"，不得用代码静态检查替代真实发布验收。

---

## 10. 源码路径覆盖追溯

本节证明每个源码模块的每个公开路径均有对应测试用例。

| 源码文件 | 公开路径 | 对应用例 |
|---|---|---|
| `AppDelegate.swift` `registerNativeChannel` | `show_broadcast_picker` | IOS-G01 |
| `AppDelegate.swift` `registerNativeChannel` | `get_broadcast_status` | IOS-G39-G41 |
| `AppDelegate.swift` `registerNativeChannel` | `prepare_broadcast_config_dir` | IOS-G42-G46 |
| `AppDelegate.swift` `registerNativeChannel` | `request_microphone_permission` | IOS-C07, IOS-F01 |
| `AppDelegate.swift` `registerNativeChannel` | `start_ios_voice_capture` | IOS-F18-F23 |
| `AppDelegate.swift` `registerNativeChannel` | `stop_ios_voice_capture` | IOS-F21 |
| `AppDelegate.swift` `startIOSVoiceCapture` | 空会话 ID 分支 | IOS-F18 |
| `AppDelegate.swift` `startIOSVoiceCapture` | 重复启动分支 | IOS-F20 |
| `AppDelegate.swift` `processIOSVoiceSamples` | 采样率转换 | IOS-F22 |
| `AppDelegate.swift` `enqueueIOSVoiceBuffer` | 多通道降混 | IOS-F23 |
| `AppDelegate.swift` `processIOSVoiceSamples` | 缓冲区回收 | IOS-F24 |
| `AppDelegate.swift` `getBroadcastStatus` | App Group 不可用 | IOS-G39 |
| `AppDelegate.swift` `getBroadcastStatus` | 正常读取 | IOS-G40 |
| `AppDelegate.swift` `getBroadcastStatus` | 状态过期 | IOS-G41 |
| `AppDelegate.swift` `prepareBroadcastConfigDirectory` | 首次创建 | IOS-G42 |
| `AppDelegate.swift` `migrateBroadcastConfiguration` | 迁移旧配置 | IOS-G43 |
| `AppDelegate.swift` `prepareBroadcastConfigDirectory` | 已有配置 | IOS-G44 |
| `AppDelegate.swift` `prepareBroadcastConfigDirectory` | App Group 不可用 | IOS-G45 |
| `AppDelegate.swift` `prepareBroadcastConfigDirectory` | 迁移失败 | IOS-G46 |
| `SampleHandler.swift` `broadcastStarted` | 启动 | IOS-G10 |
| `SampleHandler.swift` `broadcastPaused` | 暂停 | IOS-G13 |
| `SampleHandler.swift` `broadcastResumed` | 恢复 | IOS-G14 |
| `SampleHandler.swift` `broadcastFinished` | 结束 | IOS-G15 |
| `SampleHandler.swift` `processSampleBuffer` video | 视频帧 | IOS-G11 |
| `SampleHandler.swift` `processSampleBuffer` audioApp | 应用音频 | IOS-G12 |
| `SampleHandler.swift` `processSampleBuffer` audioMic | 麦克风隔离 | IOS-G09 |
| `SampleHandler.swift` `processSampleBuffer` unknown | 未知类型 | IOS-G16 |
| `SampleHandler.swift` `publishFailure` | `missing_pixel_buffer` | IOS-G17 |
| `SampleHandler.swift` `publishFailure` | `unsupported_pixel_format` | IOS-G18 |
| `SampleHandler.swift` `publishFailure` | `pixel_buffer_lock_failed` | IOS-G19 |
| `SampleHandler.swift` `publishFailure` | `missing_base_address` | IOS-G20 |
| `SampleHandler.swift` `publishFailure` | `frame_submit_` | IOS-G21 |
| `SampleHandler.swift` `publishFailure` | `app_group_unavailable` | IOS-G22 |
| `SampleHandler.swift` `publishFailure` | `transport_start_` | IOS-G23 |
| `SampleHandler.swift` `publishFailure` | `audio_submit_` | IOS-G24 |
| `SampleHandler.swift` `submitVideoFrame` | 无需缩放 | IOS-G36 |
| `SampleHandler.swift` `submitVideoFrame` | 需要缩放 | IOS-G37 |
| `SampleHandler.swift` `submitVideoFrame` | 缓冲复用 | IOS-G38 |
| `SampleHandler.swift` `submitApplicationAudio` | 格式描述缺失（返回 10） | IOS-G24 |
| `SampleHandler.swift` `submitApplicationAudio` | 缓冲分配失败（返回 11-17） | IOS-G24 |
| `ios_broadcast.rs` `kq_ios_broadcast_start` | 有效配置 | IOS-G25 |
| `ios_broadcast.rs` `kq_ios_broadcast_start` | 无效配置 | IOS-G26 |
| `ios_broadcast.rs` `kq_ios_broadcast_push_bgra` | 暂停时推帧 | IOS-G27 |
| `ios_broadcast.rs` `kq_ios_broadcast_push_bgra` | 无效帧 | IOS-G28 |
| `ios_broadcast.rs` `kq_ios_broadcast_push_bgra` | 帧过大 | IOS-G29 |
| `ios_broadcast.rs` `kq_ios_broadcast_push_bgra` | 分辨率切换 | IOS-G30 |
| `ios_broadcast.rs` `kq_ios_broadcast_resume` | 恢复传输 | IOS-G31 |
| `ios_broadcast.rs` `kq_ios_broadcast_stop` | 停止传输 | IOS-G32 |
| `ios_broadcast.rs` `kq_ios_broadcast_active_viewer_count` | 观看人数 | IOS-G33 |
| `ios_broadcast.rs` `kq_ios_broadcast_push_audio_f32` | 有效音频 | IOS-G34 |
| `ios_broadcast.rs` `kq_ios_broadcast_push_audio_f32` | 无效音频 | IOS-G35 |
| `kq_ios_in_app_purchase.dart` `KqIosInAppPurchaseConfig.fromValues` | 有效配置 | IOS-H04 |
| `kq_ios_in_app_purchase.dart` `KqIosInAppPurchaseConfig.fromValues` | 空 JSON | IOS-H05 |
| `kq_ios_in_app_purchase.dart` `KqIosInAppPurchaseConfig.fromValues` | 非法 JSON | IOS-H06 |
| `kq_ios_in_app_purchase.dart` `KqIosInAppPurchaseConfig.fromValues` | 空 ID | IOS-H07 |
| `kq_ios_in_app_purchase.dart` `KqIosInAppPurchaseConfig.fromValues` | 重复商品 ID | IOS-H08 |
| `kq_ios_in_app_purchase.dart` `KqIosInAppPurchaseConfig.fromValues` | 非 HTTPS | IOS-H09 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController.initialize` | StoreKit 不可用 | IOS-H22 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController.initialize` | 商品未找到 | IOS-H23 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController.buy` | 首次购买 | IOS-H11 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController.buy` | 取消购买 | IOS-H12 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController._handlePurchaseUpdates` | 未知商品 | IOS-H18 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController._handlePurchaseUpdates` | 购买流错误 | IOS-H24 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController._verifyPurchase` | 未登录 | IOS-H19 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController._verifyPurchase` | 验证失败 | IOS-H13 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController._verifyPurchase` | 验证超时 | IOS-H20 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController._completePurchase` | 完成失败 | IOS-H21 |
| `kq_ios_in_app_purchase.dart` `KqIosMembershipPurchaseController.restorePurchases` | 恢复购买 | IOS-H14 |
| `ios_membership_payment_policy.dart` `routeFor` | App Store 禁止直付 | IOS-H03 |
| `ios_membership_payment_policy.dart` `routeFor` | 内部直付开关 | IOS-H02 |
| `kq_account_deletion.dart` `requestDeletion` | 未登录 | IOS-H27 |
| `kq_account_deletion.dart` `requestDeletion` | 确认文本错误 | IOS-H28 |
| `kq_account_deletion.dart` `requestDeletion` | 未配置端点 | IOS-H29 |
| `kq_account_deletion.dart` `requestDeletion` | 真实注销 | IOS-H30 |
| `kq_account_deletion.dart` `requestDeletion` | 异步注销 | IOS-H31 |
| `kq_account_deletion.dart` `requestDeletion` | 超时 | IOS-H32 |
| `kq_account_deletion.dart` `requestDeletion` | 网络失败 | IOS-H33 |
| `kq_account_deletion.dart` `requestDeletion` | 服务端错误 | IOS-H34 |
| `kq_account_deletion.dart` `requestDeletion` | 响应码异常 | IOS-H35 |
| `mobile_platform_capability_policy.dart` `ios` | 11 个能力值 | IOS-J01-J08 |
| `mobile_voice_call_policy.dart` `mobileVoiceCallClosedMessage` | 7 种 reason | IOS-F10-F17 |
| `auth_2fa.rs` `generate2fa` / `verify2fa` / `send2fa` | 2FA 全流程 | IOS-K01-K06 |
