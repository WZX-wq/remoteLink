export function normalizePrivacyPolicyPlatform(platform) {
  return typeof platform === 'string' && platform.trim().toLowerCase() === 'ios'
    ? 'ios'
    : 'generic';
}

export function privacyPolicyPage(platform) {
  const membershipPolicy =
    normalizePrivacyPolicyPlatform(platform) === 'ios'
      ? `<p>App Store 版本的会员购买和恢复购买由 Apple 的应用内购买完成。我们仅处理验证会员权益所需的交易信息。删除账号不会自动取消 Apple 订阅；如有自动续订订阅，请先在 Apple 订阅管理中取消。</p>
      <p class="english">Membership purchase and restoration in the App Store build are handled by Apple In-App Purchase. We process only transaction information needed to verify membership entitlements. Deleting an account does not automatically cancel an Apple subscription.</p>`
      : `<p>会员购买、恢复与权益验证由适用的支付渠道和服务完成。我们仅处理验证会员权益所需的交易信息。删除账号不会自动取消已在其他渠道开通的自动续订服务，请在对应渠道中管理。</p>
      <p class="english">Membership purchase, restoration, and entitlement verification are handled by the applicable payment channel and service. We process only transaction information needed to verify membership entitlements. Deleting an account does not automatically cancel an auto-renewing service started through another channel; manage it in that channel.</p>`;

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <meta name="robots" content="index,follow" />
  <title>鲲穹远程桌面隐私政策</title>
  <style>
    :root { color-scheme: light; --ink: #172b45; --muted: #5f7185; --line: #d9e2ec; --link: #0b74c9; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #f6f8fb; color: var(--ink); font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif; line-height: 1.7; }
    main { width: min(860px, calc(100% - 32px)); margin: 0 auto; padding: 42px 0 64px; }
    header { margin-bottom: 34px; border-bottom: 1px solid var(--line); padding-bottom: 24px; }
    h1 { margin: 0 0 10px; font-size: 30px; letter-spacing: 0; }
    header p, .intro { margin: 0; color: var(--muted); }
    section { padding: 22px 0; border-bottom: 1px solid var(--line); }
    h2 { margin: 0 0 12px; font-size: 20px; letter-spacing: 0; }
    h2 span { color: var(--muted); font-weight: 500; font-size: 15px; }
    p { margin: 10px 0; }
    .english { color: var(--muted); font-size: 15px; }
    a { color: var(--link); }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>鲲穹远程桌面隐私政策</h1>
      <p>Kunqiong Remote Link Privacy Policy</p>
    </header>
    <p class="intro">本政策说明我们如何处理账号、远程协助和会员服务相关的数据。</p>
    <section>
      <h2>我们收集的数据 <span>Data we collect</span></h2>
      <p>为了创建和保护账号，我们会处理用户名、手机号、登录凭证和账号资料。</p>
      <p>为了提供远程协助，我们会处理设备识别信息、连接识别码、远程画面、输入操作，以及您主动选择传输的应用声音、语音、文件和剪贴板内容。</p>
      <p class="english">To create and protect an account, we process your username, phone number, sign-in credentials, and account profile. To provide remote assistance, we process device and connection identifiers, remote display frames, input actions, and the application audio, voice data, files, and clipboard content you choose to transmit.</p>
    </section>
    <section>
      <h2>数据如何使用 <span>How we use data</span></h2>
      <p>这些数据仅用于登录验证、建立远程连接、传输您发起的内容、保障服务安全、处理会员权益和提供技术支持。我们不会将您的个人数据用于跨应用跟踪，也不会出售您的个人数据。</p>
      <p class="english">We use this data only to authenticate you, establish remote sessions, transfer content you initiate, protect service security, process membership entitlements, and provide support. We do not use personal data for cross-app tracking or sell personal data.</p>
    </section>
    <section>
      <h2>数据共享与安全 <span>Data sharing and security</span></h2>
      <p>远程画面、应用声音、语音、控制指令、文件和剪贴板内容只会按您的操作发送给当前远程会话的另一端。我们仅在提供服务、安全防护、支付验证或法律要求所必需的范围内，与受约束的服务提供方处理数据。</p>
      <p class="english">Remote display frames, application audio, voice content, control instructions, files, and clipboard data are sent only to the other side of the remote session you start. We process data with bound service providers only when necessary to provide the service, protect security, verify payment, or comply with law.</p>
    </section>
    <section>
      <h2>保存、删除与您的选择 <span>Retention, deletion, and your choices</span></h2>
      <p>我们会在提供服务和履行法律义务所需的期限内保存账号和服务数据。您可以在系统设置中管理麦克风、照片和文件等权限，也可以随时退出登录。</p>
      <p>您可以在个人中心发起账号注销。注销会删除账号和不再需要保留的相关数据；法律要求保留的数据会在法定期限届满后删除。</p>
      <p class="english">We retain account and service data only for the period needed to provide the service and meet legal obligations. You can manage permissions in system settings, sign out at any time, and initiate account deletion from Personal center.</p>
    </section>
    <section>
      <h2>会员与支付 <span>Membership and payments</span></h2>
      ${membershipPolicy}
    </section>
    <section>
      <h2>联系我们 <span>Contact us</span></h2>
      <p>如需咨询隐私、数据访问、更正或删除，请通过应用内“联系我们”渠道提交请求。本政策会在功能或数据处理方式发生重大变化时更新。</p>
      <p class="english">For privacy, data-access, correction, or deletion requests, use the Contact us channel in the app. We update this policy when there are material changes to features or data handling.</p>
    </section>
  </main>
</body>
</html>`;
}
