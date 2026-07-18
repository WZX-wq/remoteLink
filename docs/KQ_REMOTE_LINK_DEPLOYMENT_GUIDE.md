# KQremoteLink 部署说明

本文档用于交接和执行 **鲲穹远程桌面 / KQremoteLink** 的上线部署。覆盖服务端、下载资源、Windows/Android/iOS 客户端构建发布、上线验证和回滚。

## 1. 部署目标

### 1.1 正式域名

正式服务统一使用：

```text
remotelink.kunqiongai.com
```

客户端默认应连接：

```text
ID 服务：remotelink.kunqiongai.com:21116
中继服务：remotelink.kunqiongai.com:21117
项目 API：https://remotelink.kunqiongai.com/kq-api/api
安卓下载：https://remotelink.kunqiongai.com/kq-api/download/android
Windows 下载：https://remotelink.kunqiongai.com/kq-api/download/windows
```

### 1.2 需要部署的组件

| 组件 | 说明 |
| --- | --- |
| `hbbs` | RustDesk ID / rendezvous 服务 |
| `hbbr` | RustDesk relay / 中继服务 |
| KQ API | 登录、会员、设备、下载、支付等项目 API |
| Nginx | 对外反代 `/kq-api/*`，并提供下载直链 |
| Windows 客户端 | 安装版 `.exe`，当前未签名时不要上传正式下载位 |
| Android 客户端 | `.apk`，发布到 API 下载目录 |
| iOS 客户端 | 通过 Codemagic/TestFlight 构建和分发 |

### 1.3 功能模块完成状态

上线交接时按下面状态验收，避免把测试中能力误当成正式可用能力。

#### 已完成 / 可进入上线验收

| 模块 | 当前状态 | 上线验收重点 |
| --- | --- | --- |
| 私有远控服务 | `hbbs` / `hbbr` 部署脚本、健康检查脚本、端口规则已整理 | 域名 `remotelink.kunqiongai.com`、`21116/tcp+udp`、`21117/tcp` 可用 |
| 客户端私有服务器配置 | 支持域名版 ID 服务、中继服务、KQ API、`hbbs` 公钥配置 | 新安装客户端默认连接正式域名，不再指向旧 IP |
| KQ API 基础服务 | 登录态、会员信息、设备列表、最近连接、下载、支付相关接口已接入 API 服务 | `/kq-api/api/health` 正常，数据库表已创建，客户端请求带 token |
| 数据库结构 | 已提供 `deploy/kq-production-db.sql`，包含当前 API 使用的 5 张表和旧索引迁移 | 正式库 `kq_remote_link` 创建成功，API 账号有读写/建表/改表权限 |
| 下载服务 | Android / Windows 下载直链和限流配置已整理 | Android 直链返回 APK；Windows 仅在签名包准备好后开放 |
| Windows 客户端 | 远程协助、验证码连接、设备/设置页、语言切换、深色模式等近期问题已修复 | 新安装后默认正式域名；未签名安装包不要放正式下载位 |
| Android 客户端远控电脑 | 手机远控电脑默认横屏全屏、右侧工具栏、鼠标操作使用应用自带映射逻辑 | 真机连接 Windows，鼠标、键盘、剪贴板、横屏全屏表现正常 |
| 账号设备列表 | 移动设备/桌面设备读取当前账号登录设备；最近连接读取本地连接记录 | 设备列表排除本机；最近连接不再越刷越多；空列表也显示分组 |
| 最近连接 | 已调整为本地最近连接记录，默认不展开，支持刷新动画 | 进入页面不应先显示 0 再闪跳；刷新动画可见且不重复插入数据 |
| 个人中心 | 顶部用户区域进入个人中心，展示用户名和手机号 | 不直接退出登录，不展示项目服务器内部信息 |
| Android / 内部测试支付 | Android 保留“提交表单拉起支付宝”的方案；iOS 只有显式内部 Ad Hoc 开关才允许外部支付 | Android 已安装支付宝可拉起；iOS TestFlight/App Store 不启用支付宝或微信支付 |

#### 部分完成 / 需要按场景继续验证

| 模块 | 当前状态 | 风险 / 待确认 |
| --- | --- | --- |
| Android 支付宝未安装处理 | 已要求未安装时提示并取消，不显示假二维码 | 需要用未安装支付宝的真机再测一次，确认不再出现 `784` 或假二维码 |
| Android 录屏保存 | 已提出支持选择保存位置，并在结束后提示文件位置 | 需要确认实际录屏文件路径、权限和结束提示在真机上完整可用 |
| 会员画质 | 会员可解锁更高清晰度/帧率的文案和入口已接入 | 需要用会员/非会员账号分别验证 720p/1080p、30/60 FPS 限制 |
| 多语言 | 简体/繁体/英文等页面文案做过多轮修复 | 仍需抽查所有主页面、弹窗、支付态、设备空态是否还有英文残留 |
| iOS 客户端登录/连接其他设备 | iOS 主 App 可通过 Codemagic/TestFlight 构建，目标是与 Android/Windows 对等 | 需要 TestFlight 包真机验收登录、设备列表、主动远控 Windows/Android |
| iOS 会员购买 | App Store/TestFlight 构建已切到 StoreKit 入口，会员权益需服务端验证 Apple 交易后生效 | 需要配置 App Store Connect 商品、`KQ_IOS_IAP_PRODUCTS`、`KQ_IOS_IAP_VERIFY_URL`，并用 Sandbox 真机验证购买和恢复购买 |

#### 未完成 / 暂不按正式功能开放

| 模块 | 当前状态 | 不开放原因 |
| --- | --- | --- |
| 微信支付原生拉起 | 当前先隐藏微信支付，不作为正式支付方式开放 | 多轮测试仍无法稳定拉起微信支付，待后续按微信支付正式参数和 SDK/Universal Link 方案重做 |
| iOS 作为被控端完整屏幕共享 | 目前只是 ReplayKit Broadcast Extension 采集链路 MVP | 还没有把 ReplayKit sample buffer 接入完整远控传输链路，不能承诺 iPhone 被控共享屏幕可用 |
| iOS 远程控制本机鼠标键盘 | 不作为目标能力 | iOS 系统限制，不能像 Android/Windows 那样开放完整被控输入控制 |
| Windows 正式下载位 | 未签名安装包暂不上传正式 Windows 下载位 | 避免浏览器、安全软件把未签名包识别为不安全 |
| 生产 hbbs 私钥自动填充 | 本地模板留空，未硬编码现用私钥 | 现用 `id_ed25519` 私钥只应从服务器导出，不能本地猜测或重新生成替代 |

## 2. 服务器要求

### 2.1 基础环境

目标 Linux 服务器需要：

- Docker Engine
- Docker Compose plugin 或 `docker-compose`
- Nginx
- `bash`
- `curl`
- `ss` 或 `netstat`
- 可访问公网的域名解析：`remotelink.kunqiongai.com`

### 2.2 端口放行

云安全组和服务器防火墙都需要放行：

| 协议 | 端口 | 用途 |
| --- | --- | --- |
| TCP | `21115` | NAT 类型检测 |
| TCP | `21116` | ID / rendezvous 服务 |
| UDP | `21116` | UDP 打洞 |
| TCP | `21117` | relay 中继服务 |
| TCP | `21118` | Web 支持预留 |
| TCP | `21119` | Web 支持预留 |
| TCP | `80/443` | Nginx / HTTPS |

最低必须有：

```text
21115/tcp
21116/tcp
21116/udp
21117/tcp
443/tcp
```

## 3. 服务端部署

### 3.1 标准安装目录

推荐安装目录：

```text
/www/wwwroot/KQromoteLink
```

备用目录：

```text
/opt/kq-remote-link-server
```

### 3.2 部署命令

在服务器上进入项目目录后执行：

```bash
cd /www/wwwroot/KQromoteLink

PUBLIC_HOST=remotelink.kunqiongai.com \
INSTALL_DIR=/www/wwwroot/KQromoteLink \
KQ_ENABLE_API=Y \
COMPOSE_PROFILES=api \
./deploy/deploy-rustdesk-server.sh
```

如果只部署远控基础服务，不部署项目 API：

```bash
cd /www/wwwroot/KQromoteLink

PUBLIC_HOST=remotelink.kunqiongai.com \
INSTALL_DIR=/www/wwwroot/KQromoteLink \
KQ_ENABLE_API=N \
./deploy/deploy-rustdesk-server.sh
```

### 3.3 固定 hbbs/hbbr 密钥

客户端私有服务器配置依赖 `hbbs` 公钥。正式环境建议提前固定密钥，不要每次部署随机生成。

在本地生成：

```powershell
.\scripts\new-kq-server-key-pair.ps1
```

部署时注入：

```bash
export KQ_HBBS_PUBLIC_KEY="$(cat /www/wwwroot/KQromoteLink/data/id_ed25519.pub)"
export KQ_HBBS_SECRET_KEY="$(cat /www/wwwroot/KQromoteLink/data/id_ed25519)"

PUBLIC_HOST=remotelink.kunqiongai.com \
INSTALL_DIR=/www/wwwroot/KQromoteLink \
KQ_ENABLE_API=Y \
COMPOSE_PROFILES=api \
./deploy/deploy-rustdesk-server.sh
```

服务端公钥落盘位置：

```text
/www/wwwroot/KQromoteLink/data/id_ed25519.pub
```

### 3.4 API 环境变量

API 相关变量一般写入：

```text
/www/wwwroot/KQromoteLink/.env
```

常用变量：

```bash
KQ_API_PORT=21120
KQ_API_PUBLIC_PATH=/kq-api
KQ_PUBLIC_API_URL=https://remotelink.kunqiongai.com/kq-api/api

KQ_DOWNLOAD_URL=https://remotelink.kunqiongai.com/kq-api/download/windows
KQ_DOWNLOAD_FILE_PATH=/app/public/downloads/Kunqiong-Remote-Desktop-Setup.exe
KQ_DOWNLOAD_FILE_NAME=Kunqiong-Remote-Desktop-Setup.exe

KQ_ANDROID_DOWNLOAD_URL=https://remotelink.kunqiongai.com/kq-api/download/android
KQ_ANDROID_DOWNLOAD_FILE_PATH=/app/public/downloads/Kunqiong-Remote-Desktop.apk
KQ_ANDROID_DOWNLOAD_FILE_NAME=Kunqiong-Remote-Desktop.apk
```

### 3.5 数据库初始化脚本

数据库初始化脚本已整理为：

```text
deploy/kq-production-db.sql
```

它会创建正式库 `kq_remote_link`，并初始化 API 当前使用的表：

- `kq_users`
- `kq_connection_history`
- `kq_account_devices`
- `kq_member_orders`
- `kq_member_snapshots`

在数据库服务器上用有建库权限的账号执行：

```bash
mysql -h 127.0.0.1 -P 3306 -u root -p < deploy/kq-production-db.sql
```

支付相关变量按正式申请结果配置：

```bash
# 支付宝
KQ_ALIPAY_APP_ID=2021006163671041
KQ_ALIPAY_PRIVATE_KEY=
KQ_ALIPAY_PUBLIC_KEY=
KQ_ALIPAY_NOTIFY_URL=https://remotelink.kunqiongai.com/kq-api/api/payment/alipay/notify
KQ_ALIPAY_GATEWAY_URL=https://openapi.alipay.com/gateway.do
```

不要把正式支付私钥提交到仓库。

## 4. 服务端验证

部署完成后执行：

```bash
cd /www/wwwroot/KQromoteLink

INSTALL_DIR=/www/wwwroot/KQromoteLink \
COMPOSE_PROFILES=api \
KQ_PUBLIC_API_URL=https://remotelink.kunqiongai.com/kq-api/api \
./deploy/check-rustdesk-server.sh
```

必须确认：

- `kq-remote-link-hbbs` 运行中
- `kq-remote-link-hbbr` 运行中
- 如果启用 API：`kq-remote-link-api` 运行中
- TCP `21115/21116/21117` 有监听
- UDP `21116` 有监听
- 公网 API 健康检查可访问：

```bash
curl -fsS https://remotelink.kunqiongai.com/kq-api/api/health
```

下载直链检查：

```bash
curl -I https://remotelink.kunqiongai.com/kq-api/download/android
curl -I https://remotelink.kunqiongai.com/kq-api/download/windows
```

Windows 包未签名时，先不要放到正式 Windows 下载位。

## 5. 客户端私有服务器配置

客户端配置模板：

```text
deploy/custom-client.example.json
```

正式值应为：

```json
{
  "custom-rendezvous-server": "remotelink.kunqiongai.com:21116",
  "relay-server": "remotelink.kunqiongai.com:21117",
  "kq-project-api-server": "https://remotelink.kunqiongai.com/kq-api/api",
  "key": "从 /www/wwwroot/KQromoteLink/data/id_ed25519.pub 读取到的公钥",
  "hide-server-settings": "Y"
}
```

验证私有服务器可达：

```powershell
$ServerKey = ssh root@remotelink.kunqiongai.com "cat /www/wwwroot/KQromoteLink/data/id_ed25519.pub"

.\scripts\test-kq-server.ps1 `
  -RendezvousServer "remotelink.kunqiongai.com:21116" `
  -RelayServer "remotelink.kunqiongai.com:21117" `
  -ApiServer "https://remotelink.kunqiongai.com/kq-api/api/health" `
  -ServerKey $ServerKey
```

## 6. Windows 客户端构建和发布

### 6.1 构建

常用构建命令：

```powershell
.\scripts\build-windows-flutter.ps1 -SkipPortablePack
```


### 6.2 安装包

生成安装版：

```powershell
.\scripts\new-kq-windows-installer.ps1 `
  -ReleaseDir ".\flutter\build\windows\x64\runner\Release" `
  -OutputRoot "D:\RemoteLink\artifacts" `
  -InstallerName "Kunqiong-Remote-Desktop-Setup.exe"
```

输出示例：

```text
D:\RemoteLink\artifacts\Kunqiong-Remote-Desktop-Setup.exe
```

### 6.3 上传规则

- 已签名安装包：可以上传到正式下载目录。
- 未签名安装包：先不要上传正式下载位，避免浏览器或安全软件拦截。
- 上传后需要同步 `.env` 中的版本和 SHA256：

```bash
KQ_DOWNLOAD_VERSION=2026.06.26.2060
KQ_DOWNLOAD_SHA256=4C3E608C6AF09F6BEE70597DA0691253F0771C0E1E6F7CD8200F87A05826341A
```

正式下载目录：

```text
/www/wwwroot/KQromoteLink/api/public/downloads/Kunqiong-Remote-Desktop-Setup.exe
```

## 7. Android 客户端构建和发布

### 7.1 构建 APK

```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

常见输出：

```text
flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### 7.2 发布到服务器

把 APK 放入服务器的 `artifacts` 目录后执行：

```bash
cd /www/wwwroot/KQromoteLink

ARTIFACT_DIR=artifacts \
OUTPUT_DIR=/www/wwwroot/KQromoteLink/android \
API_DOWNLOAD_DIR=/www/wwwroot/KQromoteLink/api/public/downloads \
scripts/deploy/deploy-android.sh
```

脚本会：

- 发布 APK 到 `/www/wwwroot/KQromoteLink/android/Kunqiong-Remote-Desktop.apk`
- 发布 APK 到 `/www/wwwroot/KQromoteLink/api/public/downloads/Kunqiong-Remote-Desktop.apk`
- 生成 `SHA256SUMS.txt`
- 更新 `.env` 中的 Android 下载信息
- 重启 KQ API

验证：

```bash
curl -I https://remotelink.kunqiongai.com/kq-api/download/android
```

## 8. iOS 客户端构建和发布

iOS 不能在 Windows 本地直接签名构建

### 8.1 GitHub 仓库

当前 workflow：

```text
kq-remote-link-ios-nosign
kq-remote-link-ios-testflight
```

### 8.2 App 信息

主 App：

```text
Bundle ID: com.kunqiong.remotelink
```

ReplayKit Broadcast Extension：

```text
Bundle ID: com.kunqiong.remotelink.broadcast
```

App Group：

```text
group.com.kunqiong.remotelink
```

### 8.3 Apple Developer 配置

在 Apple Developer 后台确认：

1. `com.kunqiong.remotelink` App ID 存在。
2. `com.kunqiong.remotelink.broadcast` App ID 存在。
3. 两个 App ID 都启用 App Groups。
4. 两个 App ID 都加入 `group.com.kunqiong.remotelink`。
5. App Store Connect 已创建对应 App。
6. Codemagic 能获取主 App 和扩展的 App Store provisioning profile。

### 8.4 Codemagic 环境变量组

环境变量组：

```text
appstore_credentials
```

需要包含：

```text
APP_STORE_CONNECT_PRIVATE_KEY
APP_STORE_CONNECT_KEY_IDENTIFIER
APP_STORE_CONNECT_ISSUER_ID
```

### 8.5 iOS 合规与会员配置

TestFlight / App Store 构建需要额外配置：

```text
KQ_PRIVACY_POLICY_URL=https://remotelink.kunqiongai.com/kq-api/privacy
KQ_ACCOUNT_DELETE_URL=https://remotelink.kunqiongai.com/kq-api/api/auth/account/delete
KQ_IOS_IAP_PRODUCTS={"1":"com.kunqiong.remotelink.member.monthly"}
KQ_IOS_IAP_VERIFY_URL=https://remotelink.kunqiongai.com/kq-api/api/membership/apple/verify
```

说明：

- App 内已经提供隐私政策页面，但 App Store Connect 仍需要填写可公开访问的隐私政策 URL。
- iOS“注销账号”入口已经接入配置化服务端接口；未配置或服务端不可用时会提示暂不可用，不能作为正式验收通过。
- App Store/TestFlight 构建必须使用 Apple In-App Purchase。支付宝/微信外部支付只允许 `KQ_IOS_INTERNAL_DIRECT_PAYMENT=true` 的内部 Ad Hoc 测试包使用，不要用于提交审核。
- StoreKit 商品 ID 必须与服务端会员套餐一一映射，服务端验证 Apple 交易成功后才能发放会员权益。

### 8.6 构建顺序

先跑无签名构建：

```text
KQ Remote Link iOS - No Signing Build
```

通过后再跑 TestFlight：

```text
KQ Remote Link iOS - TestFlight
```

TestFlight 成功后，在 App Store Connect 中提交内部测试或外部测试。

## 9. 上线顺序

推荐顺序：

1. 确认 DNS：`remotelink.kunqiongai.com` 指向正式服务器。
2. 放行端口：`21115-21119/tcp`、`21116/udp`、`443/tcp`。
3. 部署 `hbbs/hbbr`。
4. 部署 KQ API。
5. 配置 Nginx `/kq-api/*`。
6. 获取并记录 `hbbs` public key。
7. 用正式域名和 public key 构建客户端配置。
8. 构建 Android APK 并发布下载。
9. Windows 安装包签名后再发布下载。
10. iOS 构建
11. 做双设备远控验收。

## 10. 上线验收清单

### 10.1 服务端

- [ ] `docker ps` 或 `systemctl status` 显示 hbbs/hbbr 正常。
- [ ] `21116/tcp` 可连。
- [ ] `21116/udp` 已放行。
- [ ] `21117/tcp` 可连。
- [ ] `https://remotelink.kunqiongai.com/kq-api/api/health` 返回正常。
- [ ] Android 下载链接返回 APK。
- [ ] Windows 下载链接仅在安装包已签名后开放。

### 10.2 客户端

- [ ] Windows 新安装后默认连接正式域名。
- [ ] Android 新安装后默认连接正式域名。
- [ ] iOS TestFlight 包能登录。
- [ ] 同账号设备列表能显示除本机外的设备。
- [ ] 最近连接只显示本地最近连接记录。
- [ ] Android 支付宝已安装时能拉起支付宝。
- [ ] Android 支付宝未安装时提示并取消支付，不显示假二维码。
- [ ] iOS TestFlight 使用 Apple Sandbox 账号完成会员购买和恢复购买。
- [ ] iOS App 内可以查看隐私政策，个人中心可以发起注销账号申请。
- [ ] 远控连接可建立。
- [ ] 鼠标、键盘、剪贴板可用。
- [ ] 跨网络场景可走 relay。

### 10.3 iOS 屏幕共享

当前 iOS 屏幕共享是 ReplayKit 采集链路 MVP：

- [ ] 分享页有“开始屏幕共享”入口。
- [ ] 能拉起 iOS 系统屏幕广播面板。
- [ ] 系统面板里能看到鲲穹远程桌面 Broadcast Extension。
- [ ] 开始广播后，App 内采集状态能显示视频帧数和分辨率。

说明：当前还未把 ReplayKit sample buffer 接入完整远控传输链路，不能把 iOS 当作完整被控端。

## 11. 回滚方案

### 11.1 服务端回滚

如果新服务异常：

```bash
cd /www/wwwroot/KQromoteLink
git log --oneline -n 10
```

从输出中复制上一版稳定提交 ID 后执行回滚。下面用当前已知的上一版提交 `e591f4334` 演示，实际回滚时以现场 `git log` 输出确认为准：

```bash
git checkout e591f4334

PUBLIC_HOST=remotelink.kunqiongai.com \
INSTALL_DIR=/www/wwwroot/KQromoteLink \
KQ_ENABLE_API=Y \
COMPOSE_PROFILES=api \
./deploy/deploy-rustdesk-server.sh
```

### 11.2 下载资源回滚

保留上一版 APK / EXE：

```text
/www/wwwroot/KQromoteLink/api/public/downloads/
```

回滚时把旧包覆盖回：

```text
Kunqiong-Remote-Desktop.apk
Kunqiong-Remote-Desktop-Setup.exe
```

然后重启 API：

```bash
systemctl restart kq-remote-link-api.service
```

如果 API 是 Docker：

```bash
docker restart kq-remote-link-api
```

### 11.3 iOS 回滚

iOS 通过 App Store Connect/TestFlight 回滚：

1. 停止分发问题 build。
2. 重新启用上一稳定 TestFlight build。
3. 必要时回退 GitHub `main` 到上一稳定提交，再重新跑 Codemagic。

## 12. 常见问题

### 客户端仍连接旧 IP

检查：

- 客户端是否带了旧 `custom.txt`
- `custom-client.example.json` 是否仍有旧 IP
- Windows/Android/iOS 是否是最新构建
- 本地缓存配置是否覆盖了打包默认配置

### 设备列表为空

检查：

- API 是否健康
- 当前账号是否真的登录同一账号
- 服务端设备上报接口是否正常
- 本机过滤逻辑是否过滤掉了当前设备
- 移动设备/桌面设备是否读取账号登录设备，而不是最近连接

### 支付点击后显示未登录

检查：

- App 登录态是否同步到支付接口
- API 是否收到 token
- App 包名、签名、支付宝开放平台配置是否一致
- 支付宝 App 是否已安装
- Android 或内部 Ad Hoc iOS 是否走原生拉起路径，而不是二维码 fallback
- TestFlight/App Store iOS 是否误开了 `KQ_IOS_INTERNAL_DIRECT_PAYMENT`
- StoreKit 商品 ID、会员套餐 ID 和服务端交易验证接口是否一致

### Codemagic iOS 签名失败

检查：

- 主 App profile 是否存在
- Broadcast Extension profile 是否存在
- App Group 是否同时加到主 App 和扩展
- `appstore_credentials` 环境变量是否齐全
- App Store Connect 是否已创建 `com.kunqiong.remotelink` 的 App 记录，且 API Key 具备 App Manager 权限

## 13. 关键文件索引

| 文件 | 用途 |
| --- | --- |
| `deploy/deploy-rustdesk-server.sh` | 服务端主部署脚本 |
| `deploy/check-rustdesk-server.sh` | 服务端健康检查 |
| `deploy/kq-production.env.example` | 正式环境变量模板 |
| `deploy/kq-production-db.sql` | 正式数据库初始化脚本 |
| `deploy/custom-client.example.json` | 私有服务器客户端配置模板 |
| `scripts/new-kq-custom-client-config.ps1` | 生成并签名 `custom.txt` |
| `scripts/test-kq-server.ps1` | 客户端侧测试服务器连通性 |
| `scripts/new-kq-windows-installer.ps1` | Windows 安装包生成 |
| `scripts/deploy/deploy-android.sh` | Android APK 发布 |
| `codemagic.yaml` | iOS Codemagic 构建 |
| `flutter/ios/KQScreenBroadcast/` | iOS ReplayKit Broadcast Extension |
