# 鲲穹远程桌面 iOS 端云构建说明

本说明用于构建 **鲲穹远程桌面 iOS 客户端**，不是服务开关应用。

## 工程信息

- Flutter 工程：`flutter`
- iOS Workspace：`flutter/ios/Runner.xcworkspace`
- iOS Project：`flutter/ios/Runner.xcodeproj`
- Scheme：`Runner`
- Bundle ID：`com.carriez.flutterHbb`
- App 显示名：`鲲穹远程桌面`
- Rust iOS 静态库：`target/aarch64-apple-ios/release/liblibrustdesk.a`
- Flutter 版本：`3.24.5`
- Rust 版本：`1.75`

## Codemagic 工作流

仓库根目录已经添加 `codemagic.yaml`。

### kq-remote-link-ios-nosign

用途：无签名编译检查。

输出：

- `flutter/build/ios/iphoneos/Runner.app`

说明：

- 不生成可安装到 iPhone 的 IPA。
- 不需要 Apple 证书。
- 用来先确认 Flutter、CocoaPods、Rust iOS 静态库和 Xcode 工程能编译通过。

### kq-remote-link-ios-ipa

用途：生成可安装到 iPhone 的签名 IPA。

输出：

- `flutter/build/ios/ipa/*.ipa`

要求：

- iOS Distribution 证书。
- Ad Hoc provisioning profile。
- Provisioning profile 的 Bundle ID 必须匹配：

```text
com.carriez.flutterHbb
```

- 要安装测试的 iPhone UDID 必须加入 Ad Hoc profile。

## Codemagic 操作步骤

1. 把最新仓库推到 Codemagic 可访问的 Git 仓库。
2. 在 Codemagic 添加应用，选择本仓库。
3. 让 Codemagic 使用仓库根目录的 `codemagic.yaml`。
4. 先运行 `kq-remote-link-ios-nosign`。
5. 无签名构建通过后，在 Codemagic 上传 iOS Distribution 证书和 Ad Hoc profile。
6. 运行 `kq-remote-link-ios-ipa`。
7. 在 Artifacts 下载 `.ipa`。

## 服务端版本要求

iOS 客户端和 Android/Windows 一样，默认连接生产域名：

```text
remotelink.kunqiongai.com
```

正式服务器需要已经部署项目 API、hbbs、hbbr。否则登录、设备列表、会员、远控连接等功能会受影响。

## 本地限制

Windows 本机不能直接编译或签名 iOS IPA。本仓库当前只提供 iOS 主客户端的源码、Xcode 工程和 Codemagic 云构建配置。可安装 IPA 需要在 Codemagic 或 macOS + Xcode 环境中生成。

## 常见问题

- `No profiles for com.carriez.flutterHbb were found`
  - 没有上传匹配 Bundle ID 的 Ad Hoc provisioning profile。
- `Signing certificate ... not found`
  - 证书没有上传，或者证书和描述文件不匹配。
- 找不到 `liblibrustdesk.a`
  - Rust iOS 静态库构建失败，查看 `Build Rust iOS static library` 日志。
- CocoaPods 失败
  - 查看 `pod install` 日志，通常是 Flutter pub get 或插件依赖问题。
