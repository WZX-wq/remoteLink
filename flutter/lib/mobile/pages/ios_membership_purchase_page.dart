import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../common/kq_theme.dart';
import '../../models/platform_model.dart';
import '../../models/user_model.dart';
import '../kq_ios_in_app_purchase.dart';
import '../privacy/kq_privacy_policy.dart';

const _kqTermsOfServiceUrl = String.fromEnvironment(
  'KQ_TERMS_OF_SERVICE_URL',
  defaultValue:
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
);

class KqIosMembershipPurchasePage extends StatefulWidget {
  const KqIosMembershipPurchasePage({
    super.key,
    required this.packages,
  });

  final List<KqMemberPackage> packages;

  @override
  State<KqIosMembershipPurchasePage> createState() =>
      _KqIosMembershipPurchasePageState();
}

class _KqIosMembershipPurchasePageState
    extends State<KqIosMembershipPurchasePage> {
  late final KqIosMembershipPurchaseController _controller;

  @override
  void initState() {
    super.initState();
    _controller = KqIosMembershipPurchaseController(
      config: KqIosInAppPurchaseConfig.fromEnvironment(),
      accessTokenProvider: () =>
          bind.mainGetLocalOption(key: 'access_token').trim(),
      refreshMembership: (KqIosPurchaseVerificationResult verification) async {
        await gFFI.userModel.applyVerifiedAppleMembership(
          expireAt: verification.expireAt,
        );
      },
    )..addListener(_onControllerChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  String _text(String zh, String en) =>
      kqUiPrefersChinese() ? zh : translate(en);

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _statusText() {
    final feedback = _controller.feedback;
    if (feedback != null) {
      return _feedbackText(feedback);
    }
    switch (_controller.phase) {
      case KqIosMembershipPurchasePhase.initial:
      case KqIosMembershipPurchasePhase.loading:
        return _text(
            '正在获取 Apple 会员套餐...', 'Loading Apple membership products...');
      case KqIosMembershipPurchasePhase.purchasing:
        return _text('正在等待 Apple 支付和验证...',
            'Waiting for Apple payment and verification...');
      case KqIosMembershipPurchasePhase.restoring:
        return _text('正在恢复 Apple 购买记录...', 'Restoring Apple purchases...');
      case KqIosMembershipPurchasePhase.completed:
        return _text('会员权益已更新，可继续升级套餐。',
            'Membership benefits have been updated. You can still upgrade plans.');
      case KqIosMembershipPurchasePhase.failed:
        if (_controller.hasUnavailableProducts) {
          return _text(
            '当前暂时无法购买会员，请稍后重试。',
            'Membership is temporarily unavailable. Please try again later.',
          );
        }
        return _text('暂时无法完成 Apple 会员服务，请稍后重试。',
            'Apple membership service is temporarily unavailable. Please try again.');
      case KqIosMembershipPurchasePhase.ready:
        return _text('通过 Apple 安全完成购买。', 'Purchase securely through Apple.');
    }
  }

  String _feedbackText(KqIosMembershipPurchaseFeedback feedback) {
    switch (feedback) {
      case KqIosMembershipPurchaseFeedback.configurationInvalid:
        return _text('Apple 会员服务尚未配置完整。',
            'Apple membership service is not fully configured.');
      case KqIosMembershipPurchaseFeedback.storeUnavailable:
        return _text('Apple 支付服务当前不可用，请稍后重试。',
            'Apple payment service is currently unavailable.');
      case KqIosMembershipPurchaseFeedback.productUnavailable:
        return _text('当前暂时无法获取会员套餐，请稍后重试。',
            'Membership plans are temporarily unavailable.');
      case KqIosMembershipPurchaseFeedback.paymentCancelled:
        return _text('已取消 Apple 支付，可重新购买。',
            'Apple payment was cancelled. You can try again.');
      case KqIosMembershipPurchaseFeedback.paymentFailed:
        return _text('Apple 支付未完成，请重试。',
            'Apple payment could not be completed. Please try again.');
      case KqIosMembershipPurchaseFeedback.existingSubscriptionRequiresRestore:
        return _text(
          '此 Apple ID 已有有效订阅，请点击“恢复购买”同步会员权益；如需变更套餐，请在 Apple 订阅管理中操作。',
          'This Apple ID already has an active subscription. Restore purchases to sync benefits, or manage the subscription in Apple settings to change plans.',
        );
      case KqIosMembershipPurchaseFeedback.accountAuthenticationRequired:
        return _text('登录已失效，请重新登录后再购买。',
            'Your login has expired. Please sign in again before purchasing.');
      case KqIosMembershipPurchaseFeedback.purchaseAlreadyLinked:
        return _text('这笔 Apple 购买已关联其他账号。',
            'This Apple purchase is already linked to another account.');
      case KqIosMembershipPurchaseFeedback.verificationServiceUnavailable:
        return _text(
          'Apple 付款可能已完成，但会员验证服务暂不可用。请不要重复购买，稍后点击恢复购买。',
          'Apple payment may have completed, but membership verification is unavailable. Do not repurchase; restore purchases later.',
        );
      case KqIosMembershipPurchaseFeedback.verificationFailed:
        return _text('Apple 交易验证失败，请恢复购买后重试。',
            'Apple transaction verification failed. Please restore purchases and try again.');
      case KqIosMembershipPurchaseFeedback.purchaseFinalizationFailed:
        return _text('交易已验证，正在等待 Apple 完成交易。',
            'The transaction was verified and is waiting for Apple to finish it.');
      case KqIosMembershipPurchaseFeedback.unknownProduct:
        return _text('Apple 返回了未配置的会员商品。',
            'Apple returned a membership product that is not configured.');
      case KqIosMembershipPurchaseFeedback.localStoreKitTestCompleted:
        return _text('本机 StoreKit 测试已完成，未开通会员权益。',
            'Local StoreKit test completed. Membership benefits were not granted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final configured = _controller.config.isConfigured;
    final configuredPackageIds =
        _controller.config.packageToProductId.keys.toList(growable: false);
    final packagesById = {
      for (final package in widget.packages) package.id.toString(): package,
    };
    return Scaffold(
      backgroundColor: q.surface,
      body: SafeArea(
        child: Column(
          children: [
            _IosMembershipHeader(
              title: _text('开通会员', 'Upgrade membership'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                children: [
                  _IosMembershipIntro(
                    title: _text('会员解锁 1080p 高清 / 60 FPS',
                        'Membership unlocks 1080p HD / 60 FPS'),
                    subtitle: _text(
                      '基础版使用标清 / 30 FPS，付款和恢复购买由 Apple 处理。',
                      'Basic uses SD / 30 FPS. Apple handles payment and purchase restoration.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!configured)
                    _IosMembershipNotice(
                      icon: Icons.info_outline_rounded,
                      color: q.warning,
                      message: _text(
                        '此构建尚未配置 Apple 会员商品和权益验证服务，暂时不能购买。',
                        'This build has not configured Apple membership products and entitlement verification yet.',
                      ),
                    )
                  else if (configuredPackageIds.isEmpty)
                    _IosMembershipNotice(
                      icon: Icons.info_outline_rounded,
                      color: q.warning,
                      message: _text(
                        '当前会员套餐尚未配置对应的 Apple 商品，暂时不能购买。',
                        'The current membership plan is not mapped to an Apple product yet.',
                      ),
                    )
                  else ...[
                    if (_controller.isBusy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    for (final packageId in configuredPackageIds) ...[
                      _IosMembershipPackageTile(
                        package: packagesById[packageId],
                        product: _controller.productForPackage(
                          packageId,
                        ),
                        unavailable: _controller.isProductMissing(
                          packageId,
                        ),
                        enabled: _controller.canPurchase &&
                            _controller.isPackageAvailable(
                              packageId,
                            ),
                        isMembershipActive: _controller.hasVerifiedMembership,
                        onBuy: () => _controller.buy(packageId),
                        text: _text,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  const SizedBox(height: 14),
                  _IosMembershipNotice(
                    icon:
                        _controller.phase == KqIosMembershipPurchasePhase.failed
                            ? Icons.error_outline_rounded
                            : Icons.verified_user_outlined,
                    color:
                        _controller.phase == KqIosMembershipPurchasePhase.failed
                            ? q.offline
                            : q.primary,
                    message: _statusText(),
                  ),
                  if (configured && _controller.hasUnavailableProducts) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _controller.isBusy
                            ? null
                            : () => unawaited(_controller.initialize()),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_text('重新获取套餐', 'Reload plans')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _IosMembershipLegalFooter(
                    text: _text,
                    onPrivacy: () => unawaited(
                      _openLegalUrl(
                        KqPrivacyPolicy.publicUriFor(isIOS: true)?.toString() ??
                            '',
                      ),
                    ),
                    onTerms: () => unawaited(
                      _openLegalUrl(_kqTermsOfServiceUrl),
                    ),
                    onRestore: configured && !_controller.isBusy
                        ? _controller.restorePurchases
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosMembershipHeader extends StatelessWidget {
  const _IosMembershipHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: q.ink),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: q.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosMembershipIntro extends StatelessWidget {
  const _IosMembershipIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.84 : 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line.withOpacity(0.64)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEACB74).withOpacity(0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Color(0xFFE09B27),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: q.muted, fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IosMembershipPackageTile extends StatelessWidget {
  const _IosMembershipPackageTile({
    required this.package,
    required this.product,
    required this.unavailable,
    required this.enabled,
    required this.isMembershipActive,
    required this.onBuy,
    required this.text,
  });

  final KqMemberPackage? package;
  final ProductDetails? product;
  final bool unavailable;
  final bool enabled;
  final bool isMembershipActive;
  final VoidCallback onBuy;
  final String Function(String zh, String en) text;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final price = product?.price ?? text('暂不可用', 'Unavailable');
    final packageName = package?.displayName ??
        product?.title ??
        text('鲲穹会员', 'Kunqiong Membership');
    final memberPackage = package;
    final isLifetime = (memberPackage?.days ?? 0) >= 999999 ||
        (product?.id.endsWith('.lifetime') ?? false);
    final durationLabel = memberPackage == null
        ? text('自动续订套餐', 'Auto-renewing plan')
        : isLifetime
            ? text('永久有效', 'Lifetime')
            : memberPackage.durationLabel;
    final subtitle = unavailable
        ? text('Apple 暂未返回此套餐，请稍后重新获取。',
            'Apple has not made this plan available yet. Reload later.')
        : isLifetime
            ? text(
                '一次性购买，永久有效。开通后可使用 1080p 高清 / 60 FPS 远程控制。',
                'One-time purchase with permanent access. Unlock 1080p HD / 60 FPS remote control.',
              )
            : text(
                '自动续订。开通后可使用 1080p 高清 / 60 FPS 远程控制。',
                'Auto-renews. Unlock 1080p HD / 60 FPS remote control.',
              );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.line.withOpacity(0.58)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  packageName,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$durationLabel  $subtitle',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: q.muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  color: q.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: enabled ? onBuy : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: q.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: q.primary.withOpacity(0.24),
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    isMembershipActive
                        ? text('升级', 'Upgrade')
                        : text('购买', 'Buy'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IosMembershipNotice extends StatelessWidget {
  const _IosMembershipNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(q.isDark ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.36)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: q.muted, fontSize: 13, height: 1.42),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosMembershipLegalFooter extends StatelessWidget {
  const _IosMembershipLegalFooter({
    required this.text,
    required this.onPrivacy,
    required this.onTerms,
    required this.onRestore,
  });

  final String Function(String zh, String en) text;
  final VoidCallback onPrivacy;
  final VoidCallback onTerms;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final bulletStyle = TextStyle(color: q.muted, fontSize: 12, height: 1.42);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.68 : 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.line.withOpacity(0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: q.primary, size: 19),
              const SizedBox(width: 8),
              Text(
                text('订阅说明', 'Subscription terms'),
                style: TextStyle(
                  color: q.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _IosMembershipBullet(
            text: text(
              '订阅会按所选套餐周期自动续订，购买前以 Apple 付款页显示的价格和周期为准。',
              'The subscription auto-renews by the selected plan period. The Apple payment sheet shows the final price and period before purchase.',
            ),
            style: bulletStyle,
          ),
          _IosMembershipBullet(
            text: text(
              '付款将在确认购买时从 Apple ID 扣款；如需取消，请在到期前至少 24 小时到 Apple ID 订阅管理中关闭自动续订。',
              'Payment is charged to your Apple ID at confirmation. To cancel, turn off auto-renewal in Apple ID subscriptions at least 24 hours before the current period ends.',
            ),
            style: bulletStyle,
          ),
          _IosMembershipBullet(
            text: text(
              '会员权益将在服务端验证 Apple 交易后生效；恢复购买用于重装、换机或同步当前 Apple ID 已购买的权益。',
              'Membership activates after server verification. Restore purchases is used after reinstalling, changing devices, or syncing eligible purchases for the current Apple ID.',
            ),
            style: bulletStyle,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: onPrivacy,
                style: _footerActionStyle(q),
                child: Text(text('隐私政策', 'Privacy policy')),
              ),
              _IosMembershipFooterDot(color: q.muted),
              TextButton(
                onPressed: onTerms,
                style: _footerActionStyle(q),
                child: Text(text('用户协议', 'Terms of use')),
              ),
              _IosMembershipFooterDot(color: q.muted),
              TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text(text('恢复购买', 'Restore purchases')),
                style: _footerActionStyle(q),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _footerActionStyle(KqTheme q) {
    return TextButton.styleFrom(
      foregroundColor: q.primary,
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    );
  }
}

class _IosMembershipBullet extends StatelessWidget {
  const _IosMembershipBullet({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: q.primary.withOpacity(0.72),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

class _IosMembershipFooterDot extends StatelessWidget {
  const _IosMembershipFooterDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text('·', style: TextStyle(color: color.withOpacity(0.72))),
    );
  }
}
