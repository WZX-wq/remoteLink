import '../../common.dart';

class KqPrivacyPolicySection {
  const KqPrivacyPolicySection({
    required this.id,
    required this.titleZh,
    required this.titleEn,
    required this.paragraphsZh,
    required this.paragraphsEn,
  });

  final String id;
  final String titleZh;
  final String titleEn;
  final List<String> paragraphsZh;
  final List<String> paragraphsEn;

  String titleForCurrentLanguage() => kqUiPrefersChinese() ? titleZh : titleEn;

  List<String> paragraphsForCurrentLanguage() =>
      kqUiPrefersChinese() ? paragraphsZh : paragraphsEn;
}

/// The public URL must host the same text shown in the app before App Store
/// submission. A build can override it without changing the binary source.
class KqPrivacyPolicy {
  static const publicUrl = String.fromEnvironment(
    'KQ_PRIVACY_POLICY_URL',
    defaultValue: 'https://remotelink.kunqiongai.com/kq-api/privacy',
  );

  static const sections = <KqPrivacyPolicySection>[
    KqPrivacyPolicySection(
      id: 'data-collection',
      titleZh: '我们收集的数据',
      titleEn: 'Data we collect',
      paragraphsZh: [
        '为了创建和保护账号，我们会处理用户名、手机号、登录凭证和账号资料。',
        '为了提供远程协助，我们会处理设备识别信息、连接识别码、远程画面、输入操作，以及您主动选择传输的应用声音、语音、文件和剪贴板内容。',
      ],
      paragraphsEn: [
        'To create and protect an account, we process your username, phone number, sign-in credentials, and account profile.',
        'To provide remote assistance, we process device and connection identifiers, remote display frames, input actions, and the application audio, voice data, files, and clipboard content you choose to transmit.',
      ],
    ),
    KqPrivacyPolicySection(
      id: 'data-use',
      titleZh: '数据如何使用',
      titleEn: 'How we use data',
      paragraphsZh: [
        '这些数据仅用于登录验证、建立远程连接、传输您发起的内容、保障服务安全、处理会员权益和提供技术支持。',
        '我们不会将您的个人数据用于跨应用跟踪，也不会出售您的个人数据。',
      ],
      paragraphsEn: [
        'We use this data only to authenticate you, establish remote sessions, transfer content you initiate, protect service security, process membership entitlements, and provide support.',
        'We do not use personal data for cross-app tracking or sell personal data.',
      ],
    ),
    KqPrivacyPolicySection(
      id: 'data-sharing',
      titleZh: '数据共享与安全',
      titleEn: 'Data sharing and security',
      paragraphsZh: [
        '远程画面、应用声音、语音、控制指令、文件和剪贴板内容只会按您的操作发送给当前远程会话的另一端。',
        '我们仅在提供服务、安全防护、支付验证或法律要求所必需的范围内，与受约束的服务提供方处理数据。',
      ],
      paragraphsEn: [
        'Remote display frames, application audio, voice content, control instructions, files, and clipboard data are sent only to the other side of the remote session you start.',
        'We process data with bound service providers only when necessary to provide the service, protect security, verify payment, or comply with law.',
      ],
    ),
    KqPrivacyPolicySection(
      id: 'retention-deletion',
      titleZh: '保存、删除与您的选择',
      titleEn: 'Retention, deletion, and your choices',
      paragraphsZh: [
        '我们会在提供服务和履行法律义务所需的期限内保存账号和服务数据。您可以在系统设置中管理麦克风、照片和文件等权限，也可以随时退出登录。',
        '您可以在个人中心发起账号注销。注销会删除账号和不再需要保留的相关数据；法律要求保留的数据会在法定期限届满后删除。',
      ],
      paragraphsEn: [
        'We retain account and service data only for the period needed to provide the service and meet legal obligations. You can manage microphone, photos, and file permissions in system settings and can sign out at any time.',
        'You can initiate account deletion from Personal center. Deletion removes the account and related data that we do not need to retain; data required by law is removed after the applicable retention period.',
      ],
    ),
    KqPrivacyPolicySection(
      id: 'membership',
      titleZh: '会员与支付',
      titleEn: 'Membership and payments',
      paragraphsZh: [
        'App Store 版本的会员购买和恢复购买由 Apple 的应用内购买完成。我们仅处理验证会员权益所需的交易信息。',
        '删除账号不会自动取消 Apple 订阅；如有自动续订订阅，请先在 Apple 订阅管理中取消。',
      ],
      paragraphsEn: [
        'Membership purchase and purchase restoration in the App Store build are handled by Apple In-App Purchase. We process only the transaction information needed to verify membership entitlements.',
        'Deleting an account does not automatically cancel an Apple subscription. Cancel any auto-renewing subscription in Apple subscription management first.',
      ],
    ),
    KqPrivacyPolicySection(
      id: 'contact',
      titleZh: '联系我们',
      titleEn: 'Contact us',
      paragraphsZh: [
        '如需咨询隐私、数据访问、更正或删除，请通过应用内“联系我们”渠道提交请求。',
        '本政策会在功能或数据处理方式发生重大变化时更新。',
      ],
      paragraphsEn: [
        'For privacy, data-access, correction, or deletion requests, use the Contact us channel in the app.',
        'We update this policy when there are material changes to features or data handling.',
      ],
    ),
  ];

  static String titleForCurrentLanguage() =>
      kqUiPrefersChinese() ? '隐私政策' : 'Privacy policy';

  static String summaryForCurrentLanguage() => kqUiPrefersChinese()
      ? '了解我们如何处理账号、远程协助和会员服务相关的数据。'
      : 'Learn how we handle data for accounts, remote assistance, and membership services.';
}
