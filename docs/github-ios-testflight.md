# GitHub Actions TestFlight 发布

本项目的 TestFlight 构建使用 GitHub Actions 的 macOS runner 完成：

```text
代码推送到 main
  -> GitHub Actions 构建 iOS Release
  -> Apple Distribution 签名
  -> 上传 App Store Connect
  -> Apple 处理 build
  -> TestFlight 测试者收到新版本
```

TestFlight 安装不需要蒲公英网站，也不需要每次下载 IPA。iPhone 只需要安装一次 TestFlight 并接受测试邀请。Apple 处理完成后，TestFlight 中会显示新版本；测试者可以在 TestFlight 中开启自动更新。

## 当前证书检查结果

本机目录 `C:\Users\admin\Desktop\开发文件\苹果签名` 当前只有：

- `RemoteLink-Apple-Development.p12`
- `RemoteLink-Development.mobileprovision`
- `RemoteLink-Broadcast-Development.mobileprovision`

这些是 Development 开发签名材料，不能用于 TestFlight。不要把它们改名后继续上传，必须在 Apple Developer 后台重新创建 App Store 分发材料。

项目的两个 Bundle ID 是：

```text
主 App：com.kunqiong.remotelink
ReplayKit 广播扩展：com.kunqiong.remotelink.broadcast
Team ID：G4C3ADW2F4
App Group：group.com.kunqiong.remotelink
```

## 一、Apple Developer 后台

1. 确认主 App ID `com.kunqiong.remotelink` 已存在。
2. 确认扩展 App ID `com.kunqiong.remotelink.broadcast` 已存在。
3. 两个 App ID 都启用 App Groups，并加入 `group.com.kunqiong.remotelink`。
4. 创建 **Apple Distribution** 证书，导出带密码的 `.p12` 文件。
5. 为主 App 创建 **App Store Connect** provisioning profile。
6. 为广播扩展创建 **App Store Connect** provisioning profile。
7. 下载两个 `.mobileprovision` 文件。

不要选择 Development profile，也不要选择 Ad Hoc profile。TestFlight 使用 App Store Connect 分发 profile。

## 二、App Store Connect 后台

1. 创建或确认 Bundle ID 为 `com.kunqiong.remotelink` 的 iOS App 记录。
2. 创建当前版本 `1.4.6`，版本号必须与工作流的 `build_name` 一致。
3. 创建 App Store Connect API Key，角色使用 **App Manager** 或具备上传构建权限的角色。
4. 下载 `.p8` 私钥，并记录 Key ID、Issuer ID。
5. 在 TestFlight 中创建内部测试组，添加测试者 Apple ID。

扩展 Bundle ID 不需要单独创建 App Store 商店记录，但必须有自己的 App ID 和 App Store Connect provisioning profile。

## 三、GitHub Secrets

进入 GitHub 仓库 `Settings -> Secrets and variables -> Actions -> New repository secret`，新增以下 Secrets：

| Secret 名称 | 内容 |
| --- | --- |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Apple Distribution `.p12` 文件的 Base64 内容 |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `IOS_MAIN_APPSTORE_PROFILE_BASE64` | 主 App App Store Connect `.mobileprovision` 的 Base64 内容 |
| `IOS_BROADCAST_APPSTORE_PROFILE_BASE64` | 广播扩展 App Store Connect `.mobileprovision` 的 Base64 内容 |
| `APPSTORE_API_KEY_ID` | App Store Connect API Key 的 Key ID |
| `APPSTORE_ISSUER_ID` | App Store Connect API Key 的 Issuer ID |
| `APPSTORE_API_PRIVATE_KEY` | `.p8` 文件的完整文本，包含 BEGIN/END PRIVATE KEY |

不要把 `.p12`、`.mobileprovision`、`.p8`、密码或 API Key 提交到 GitHub 代码仓库。GitHub Actions 只通过 `secrets.NAME` 读取它们。

Windows 生成二进制文件 Base64 的命令：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\Apple-Distribution.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\RemoteLink-AppStore.mobileprovision"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\RemoteLink-Broadcast-AppStore.mobileprovision"))
```

将每条命令输出的单行文本分别粘贴到对应 Secret。`APPSTORE_API_PRIVATE_KEY` 直接粘贴 `.p8` 文件的完整内容，不要转成截图，也不要粘贴到 workflow 文件。

## 四、GitHub Variables

进入同一页面的 `Variables` 标签，新增以下 Repository variables。它们会作为 Dart define 编译到 TestFlight 包中：

```text
KQ_PRIVACY_POLICY_URL=https://你的正式域名/隐私政策地址
KQ_ACCOUNT_DELETE_URL=https://你的正式域名/账号注销接口
KQ_IOS_IAP_PRODUCTS={"1":"com.kunqiong.remotelink.member.monthly"}
KQ_IOS_IAP_VERIFY_URL=https://你的正式域名/苹果购买验签接口
```

四个地址必须使用 HTTPS，并且账号注销、Apple 交易验签接口必须已经部署。工作流会在构建前检查这些配置；配置缺失或接口不存在时不会继续上传。

## 五、运行方式

工作流文件：`.github/workflows/ios-testflight-build.yml`

- 推送到 `main`：自动构建并上传最新版本。
- GitHub Actions 页面手动运行：可填写 `build_name`，留空则读取 `flutter/pubspec.yaml`。
- build number 使用 GitHub Run ID 和 Run Attempt 生成，重跑不会重复使用开发包的固定 build number。

运行完成后，打开 App Store Connect：

```text
My Apps -> 鲲穹远程桌面 -> TestFlight
```

等待 Apple 处理完成，再将构建加入内部测试组。测试 iPhone 首次安装 TestFlight 并接受邀请，之后直接在 TestFlight 中获取版本，不再访问蒲公英安装页面。

## 常见失败

- `Missing required TestFlight signing secret`：GitHub Secrets 未配置完整。
- `not an App Store distribution profile`：误用了 Development 或 Ad Hoc profile。
- `No profiles found`：profile 的 Bundle ID 与主 App/广播扩展不匹配。
- App Store Connect `invalid credentials`：API Key、Issuer ID 或 `.p8` 私钥不匹配，或 API Key 权限不足。
- `CFBundleVersion` 重复：不要手工固定 build number，使用工作流自动生成的编号。
- TestFlight 暂时看不到构建：先等待 Apple 处理完成，再检查 App Store Connect 的构建处理状态和邮件通知。
