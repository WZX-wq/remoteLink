import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../common.dart';
import '../../common/kq_theme.dart';
import '../../models/platform_model.dart';
import '../../models/user_model.dart';
import '../kq_ios_in_app_purchase.dart';

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
      refreshMembership: () =>
          gFFI.userModel.refreshMembership(showError: true),
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

  String _text(String zh, String en) => kqUiPrefersChinese() ? zh : en;

  String _statusText() {
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
        return _text('会员权益已更新。', 'Membership benefits have been updated.');
      case KqIosMembershipPurchasePhase.failed:
        if (_controller.hasUnavailableProducts) {
          return _text(
            'Apple 暂未返回已配置的会员套餐，暂时无法购买。',
            'Apple has not made the configured membership product available yet.',
          );
        }
        return _text('暂时无法完成 Apple 会员服务，请稍后重试。',
            'Apple membership service is temporarily unavailable. Please try again.');
      case KqIosMembershipPurchasePhase.ready:
        return _text('通过 Apple 安全完成购买。', 'Purchase securely through Apple.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final configured = _controller.config.isConfigured;
    final configuredPackages = widget.packages
        .where(
          (package) =>
              _controller.config.productForPackage(package.id.toString()) !=
              null,
        )
        .toList(growable: false);
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
                    title: _text('会员解锁 1080p / 60 FPS',
                        'Membership unlocks 1080p / 60 FPS'),
                    subtitle: _text(
                      '基础版使用 720p / 30 FPS，付款和恢复购买由 Apple 处理。',
                      'Basic uses 720p / 30 FPS. Apple handles payment and purchase restoration.',
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
                  else if (configuredPackages.isEmpty)
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
                    for (final package in configuredPackages) ...[
                      _IosMembershipPackageTile(
                        package: package,
                        product: _controller.productForPackage(
                          package.id.toString(),
                        ),
                        unavailable: _controller.isProductMissing(
                          package.id.toString(),
                        ),
                        enabled: _controller.isReady &&
                            _controller.isPackageAvailable(
                              package.id.toString(),
                            ),
                        onBuy: () => _controller.buy(package.id.toString()),
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
                  SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: configured && !_controller.isBusy
                          ? _controller.restorePurchases
                          : null,
                      icon: const Icon(Icons.restore_rounded),
                      label:
                          Text(_text('恢复 Apple 购买', 'Restore Apple purchases')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: q.primary,
                        side: BorderSide(color: q.primary.withOpacity(0.55)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _text(
                      '会员权益将在服务端验证 Apple 交易后生效。',
                      'Membership benefits activate after the server verifies the Apple transaction.',
                    ),
                    style:
                        TextStyle(color: q.muted, fontSize: 12, height: 1.45),
                    textAlign: TextAlign.center,
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
    required this.onBuy,
    required this.text,
  });

  final KqMemberPackage package;
  final ProductDetails? product;
  final bool unavailable;
  final bool enabled;
  final VoidCallback onBuy;
  final String Function(String zh, String en) text;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final price = product?.price ?? text('暂不可用', 'Unavailable');
    final subtitle = unavailable
        ? text('Apple 暂未返回此套餐，请稍后重新获取。',
            'Apple has not made this plan available yet. Reload later.')
        : text(
            '开通后可使用 1080p / 60 FPS 远程控制。',
            'Unlock 1080p / 60 FPS remote control.',
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
                  package.displayName,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${package.durationLabel}  $subtitle',
                  maxLines: 2,
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
                  child: Text(text('购买', 'Buy')),
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
