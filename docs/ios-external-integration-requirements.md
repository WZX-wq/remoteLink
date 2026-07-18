# iOS 外部接入清单

## 已可直接使用

手机号注册复用 Android 使用的登录服务：`POST /api/auth/register`。客户端已经通过 `KqOauth.registerWithPhone` 发送用户名、手机号、短信验证码和密码，不需要新增独立的 iOS 注册接口。

内部测试 IPA 可以复用现有支付宝订单、付款页和订单轮询逻辑。构建时显式传入：

```powershell
flutter build ipa --dart-define=KQ_IOS_INTERNAL_DIRECT_PAYMENT=true
```

此开关只允许用于受控的内部 Ad Hoc 测试。没有该开关时，iOS 不会打开外部支付入口。

## App Store 版本必须补齐

会员解锁 1080p / 60 FPS 是应用内数字权益。App Store/TestFlight 版本已经切到 StoreKit 客户端入口，不能启用支付宝或微信支付。发布前还必须在 App Store Connect 和服务端补齐：

1. 每个会员套餐的产品 ID、类型、价格和有效期。
2. 服务端交易校验接口，接收 Apple 签名交易数据并更新现有会员权益。
3. 恢复购买接口和测试账号。
4. Sandbox 测试结果与 App Review 备注。

构建时通过环境变量提供：

```text
KQ_IOS_IAP_PRODUCTS={"1":"com.kunqiong.remotelink.member.monthly"}
KQ_IOS_IAP_VERIFY_URL=https://membership.example.com/api/membership/apple/verify
```

## 账号删除依赖

客户端已经在 iOS“我的”页提供受配置保护的“注销账号”入口。当前仓库没有 `api-web.kunqiongai.com` 认证服务的账号删除接口，正式发布前服务端必须提供经登录令牌认证的账号删除或删除申请接口，并明确：

1. 请求路径、方法、认证头和请求参数。
2. 删除范围，包括账号资料、会员数据、设备和远程协助记录。
3. 短信二次验证、冷静期或人工审核的响应格式。
4. 删除完成、撤销和失败时的用户可读错误信息。

构建时通过环境变量提供：

```text
KQ_ACCOUNT_DELETE_URL=https://identity.example.com/api/account/delete
```

未配置或接口不可用时，客户端会提示暂不能注销账号；这种状态不能作为 App Store 正式验收通过。

## 隐私政策和隐私清单

App 内已经提供隐私政策页面，iOS 工程也包含 `PrivacyInfo.xcprivacy`。App Store Connect 仍需要一个可公开访问的隐私政策 URL，并且 URL 内容要和 App 内文案保持一致。

构建时通过环境变量提供：

```text
KQ_PRIVACY_POLICY_URL=https://www.kunqiongai.com/privacy/
```

## 发布验证

在 macOS 或 Codemagic 运行 Archive 后，检查 Privacy Report、两个 Bundle ID 的 App Group 签名和 Broadcast 扩展，然后在真机验证手机号注册、隐私政策入口、注销账号入口、StoreKit Sandbox 购买/恢复购买、内部测试支付开关、屏幕广播、语音通话和文件传输。
