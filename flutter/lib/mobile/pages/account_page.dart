import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../common/kq_theme.dart';
import '../../common/widgets/login.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/user_model.dart';
import 'page_shape.dart';
import 'settings_page.dart';

class AccountPage extends StatefulWidget implements PageShape {
  AccountPage({super.key});

  @override
  final title = _mineText('Me');

  @override
  final icon = const Icon(Icons.person_rounded);

  @override
  final appBarActions = const <Widget>[];

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Future<void> _saveRemotePerformance({
    String? resolutionTier,
    int? fps,
  }) async {
    final user = gFFI.userModel;
    await user.setRemotePerformanceProfile(
      resolutionTier: resolutionTier ?? user.remoteResolutionSelection,
      fps: fps ?? user.remoteFpsSelection,
    );
    if (mounted) {
      setState(() {});
    }
    showToast(
        '${translate('Remote experience updated')}: ${user.remoteQualityLabel}');
  }

  Future<void> _handleAccountTap(bool isLogin) async {
    if (isLogin) {
      logOutConfirmDialog();
    } else {
      await loginDialog();
    }
  }

  Future<void> _openMembershipSheet() async {
    final user = gFFI.userModel;
    if (!user.isLogin) {
      final loggedIn = await loginDialog();
      if (loggedIn != true) return;
    }
    await gFFI.userModel.refreshMembership(showError: true);
    final packages = gFFI.userModel.memberPackages.toList();
    if (packages.isEmpty) {
      showToast(translate('No purchasable membership packages available'));
      return;
    }
    if (!mounted) return;
    _showMemberRechargeSheet(packages);
  }

  void _showMemberRechargeSheet(List<KqMemberPackage> packages) {
    final user = gFFI.userModel;
    var selectedPackage = packages.first;
    KqMemberOrder? order;
    var creatingOrder = false;
    var statusText = '';
    var statusIsError = false;
    var alive = true;
    Timer? pollTimer;

    void stopPolling() {
      pollTimer?.cancel();
      pollTimer = null;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: KqTheme.of(context).panelStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        final q = KqTheme.of(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void startPolling(KqMemberOrder nextOrder) {
              stopPolling();
              var tick = 0;
              pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
                tick += 1;
                if (tick > 60) {
                  timer.cancel();
                  if (alive) {
                    setSheetState(() {
                      statusText = translate(
                          'Payment status timed out. Refresh benefits later.');
                      statusIsError = false;
                    });
                  }
                  return;
                }
                () async {
                  try {
                    final status =
                        await user.checkMemberOrder(nextOrder.orderNo);
                    if (!alive) return;
                    if (status.isPaid) {
                      timer.cancel();
                      await user.refreshMembership();
                      if (!alive) return;
                      setSheetState(() {
                        statusText = translate(
                            'Payment successful. Membership benefits refreshed.');
                        statusIsError = false;
                      });
                      Navigator.of(sheetContext).pop();
                      showToast(translate('Membership benefits active'));
                    } else {
                      setSheetState(() {
                        statusText =
                            translate('Waiting for payment confirmation...');
                        statusIsError = false;
                      });
                    }
                  } catch (e) {
                    if (alive) {
                      setSheetState(() {
                        statusText = e.toString();
                        statusIsError = true;
                      });
                    }
                  }
                }();
              });
            }

            Future<void> createOrder() async {
              if (creatingOrder) return;
              setSheetState(() {
                creatingOrder = true;
                order = null;
                statusText = translate('Creating order...');
                statusIsError = false;
              });
              try {
                final nextOrder = await user.createMemberOrder(
                  packageId: selectedPackage.id,
                  payType: 1,
                );
                if (!alive) return;
                setSheetState(() {
                  order = nextOrder;
                  statusText = translate('Scan with WeChat to pay');
                  statusIsError = false;
                });
                startPolling(nextOrder);
              } catch (e) {
                if (!alive) return;
                setSheetState(() {
                  statusText = e.toString();
                  statusIsError = true;
                });
                showToast(e.toString());
              } finally {
                if (alive) {
                  setSheetState(() => creatingOrder = false);
                }
              }
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  2,
                  18,
                  18 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEACB74).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFEACB74),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              translate('Upgrade Kunqiong Membership'),
                              style: TextStyle(
                                color: q.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        translate(
                            'Membership unlocks 1080p / 60 FPS. Free users keep 720p / 30 FPS.'),
                        style: TextStyle(
                          color: q.muted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: packages
                            .map(
                              (item) => _MemberPackageTile(
                                package: item,
                                selected: item.id == selectedPackage.id,
                                onTap: () {
                                  setSheetState(() {
                                    selectedPackage = item;
                                    order = null;
                                    statusText = '';
                                    statusIsError = false;
                                    stopPolling();
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      if (order != null) ...[
                        const SizedBox(height: 16),
                        _MemberOrderPanel(order: order!),
                      ],
                      if (statusText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusIsError ? q.offline : q.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: creatingOrder ? null : createOrder,
                          icon: creatingOrder
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.qr_code_2_rounded),
                          label: Text(creatingOrder
                              ? translate('Creating')
                              : translate('Create payment order')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      alive = false;
      stopPolling();
    });
  }

  void _openRemoteExperiencePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RemoteExperiencePage(
          onSave: _saveRemotePerformance,
        ),
      ),
    );
  }

  void _openSettingsDetail({
    required String title,
    required String groupTitle,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsDetailPage(
          title: title,
          groupTitle: groupTitle,
        ),
      ),
    );
  }

  Future<void> _openLicenseDialog() async {
    try {
      final license = await bind.mainGetLicense();
      if (!mounted) return;
      final q = KqTheme.of(context);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_mineText('Software license agreement')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Text(
                license.trim().isEmpty
                    ? _mineText('No license information')
                    : license,
                style: TextStyle(color: q.ink, height: 1.35),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(translate('Close')),
            ),
          ],
        ),
      );
    } catch (e) {
      showToast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return Obx(() {
      final user = gFFI.userModel;
      final isLogin = user.userName.value.isNotEmpty;
      final avatar = bind.mainResolveAvatarUrl(avatar: user.avatar.value);
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 156),
        children: [
          _MineToolbar(
            onNotificationTap: () => showToast(_mineText('No notifications')),
          ),
          const SizedBox(height: 22),
          _ProfileHeader(
            avatar: avatar,
            title: isLogin ? user.displayNameOrUserName : translate('Login'),
            subtitle: isLogin
                ? user.accountLabelWithHandle
                : translate(
                    'Sign in to unlock device sync and membership tools.'),
            badge: user.membershipName,
            isMember: user.isMember.value,
            onTap: () => _handleAccountTap(isLogin),
          ),
          const SizedBox(height: 16),
          _MembershipBanner(
            isMember: user.isMember.value,
            qualityLabel: user.remoteQualityLabel,
            expireAt: user.memberExpireAt.value,
            loading: user.isRefreshingMembership.value,
            onPrimaryTap: _openMembershipSheet,
            onRefreshTap: isLogin
                ? () async {
                    await user.refreshMembership(showError: true);
                  }
                : null,
          ),
          const SizedBox(height: 14),
          _MenuSection(
            children: [
              _MenuRow(
                title: _mineText('Remote quality and FPS'),
                value: user.remoteQualityLabel,
                onTap: _openRemoteExperiencePage,
              ),
              _MenuRow(
                title: _mineText('General settings'),
                onTap: () => _openSettingsDetail(
                  title: _mineText('General settings'),
                  groupTitle: 'Appearance',
                ),
              ),
              _MenuRow(
                title: _mineText('Security settings'),
                onTap: () => _openSettingsDetail(
                  title: _mineText('Security settings'),
                  groupTitle: 'Remote Access',
                ),
              ),
              _MenuRow(
                title: _mineText('Mobile device management'),
                onTap: () => _openSettingsDetail(
                  title: _mineText('Mobile device management'),
                  groupTitle: 'Connection & Network',
                ),
              ),
              _MenuRow(
                title: _mineText('Contact us'),
                onTap: () => launchUrl(Uri.parse('https://kunqiongai.com/')),
              ),
              _MenuRow(
                title: _mineText('Software license agreement'),
                onTap: _openLicenseDialog,
              ),
              _MenuRow(
                title: _mineText('Privacy policy'),
                onTap: () => launchUrl(Uri.parse('https://kunqiongai.com/')),
                showDivider: false,
              ),
            ],
          ),
          if (isLogin) ...[
            const SizedBox(height: 14),
            _LogoutButton(onTap: logOutConfirmDialog),
          ],
        ],
      );
    });
  }
}

class _MineToolbar extends StatelessWidget {
  const _MineToolbar({required this.onNotificationTap});

  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: _mineText('Notifications'),
          onPressed: onNotificationTap,
          icon: Icon(Icons.notifications_none_rounded, color: q.muted),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.isMember,
    required this.onTap,
  });

  final String avatar;
  final String title;
  final String subtitle;
  final String badge;
  final bool isMember;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final badgeColor =
        isMember ? const Color(0xFFEACB74) : q.muted.withOpacity(0.88);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: q.online.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: q.panelStrong.withOpacity(0.78),
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: buildAvatarWidget(
                        avatar: avatar,
                        size: 64,
                        fallback: Icon(
                          Icons.person_rounded,
                          color: q.online,
                          size: 38,
                        ),
                      ) ??
                      Icon(Icons.person_rounded, color: q.online, size: 38),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: q.ink,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: badgeColor.withOpacity(0.26),
                            ),
                          ),
                          child: Text(
                            isMember ? 'VIP' : badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: q.ink, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembershipBanner extends StatelessWidget {
  const _MembershipBanner({
    required this.isMember,
    required this.qualityLabel,
    required this.expireAt,
    required this.loading,
    required this.onPrimaryTap,
    required this.onRefreshTap,
  });

  final bool isMember;
  final String qualityLabel;
  final String expireAt;
  final bool loading;
  final VoidCallback onPrimaryTap;
  final Future<void> Function()? onRefreshTap;

  @override
  Widget build(BuildContext context) {
    final title = isMember
        ? translate('Membership benefits unlocked')
        : translate('Upgrade Kunqiong Membership');
    final subtitle = isMember && expireAt.trim().isNotEmpty
        ? '${translate('Membership valid until')} $expireAt'
        : translate(
            'Membership unlocks 1080p / 60 FPS. Free users keep 720p / 30 FPS.');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF141621),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEACB74).withOpacity(0.36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -42,
            top: -58,
            child: Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFEACB74).withOpacity(0.12),
                  width: 18,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: const BoxDecoration(
                color: Color(0xFF2E2F37),
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                isMember ? 'VIP' : _mineText('Free plan'),
                style: const TextStyle(
                  color: Color(0xFFEACB74),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 46, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFE7A4),
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.76),
                              fontSize: 13,
                              height: 1.28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: onPrimaryTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD24D),
                        foregroundColor: const Color(0xFF3A2B00),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        translate(isMember ? 'Renew membership' : 'Upgrade'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.verified_rounded,
                        color: Color(0xFFFFD24D), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${translate('Remote quality')}: $qualityLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFE7A4),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onRefreshTap != null)
                      TextButton.icon(
                        onPressed: loading ? null : onRefreshTap,
                        icon: loading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(translate('Refresh membership')),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFE7A4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line.withOpacity(0.56)),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    required this.onTap,
    this.value,
    this.showDivider = true,
  });

  final String title;
  final String? value;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Icon(Icons.chevron_right_rounded, color: q.muted, size: 26),
                ],
              ),
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(left: 18, right: 18),
                child: Divider(height: 1, color: q.line.withOpacity(0.56)),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.logout_rounded),
      label: Text(translate('Logout')),
      style: OutlinedButton.styleFrom(
        foregroundColor: q.offline,
        side: BorderSide(color: q.offline.withOpacity(0.28)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

typedef _RemotePerformanceSave = Future<void> Function({
  String? resolutionTier,
  int? fps,
});

class _RemoteExperiencePage extends StatefulWidget {
  const _RemoteExperiencePage({
    required this.onSave,
  });

  final _RemotePerformanceSave onSave;

  @override
  State<_RemoteExperiencePage> createState() => _RemoteExperiencePageState();
}

class _RemoteExperiencePageState extends State<_RemoteExperiencePage> {
  var _saving = false;

  Future<void> _apply({String? resolutionTier, int? fps}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(resolutionTier: resolutionTier, fps: fps);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Scaffold(
      backgroundColor: q.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: q.pageGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _KqDetailHeader(title: _mineText('Remote quality and FPS')),
              Expanded(
                child: Obx(() {
                  final user = gFFI.userModel;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 96),
                    children: [
                      _RemoteExperienceHero(
                        label: user.remoteQualityLabel,
                        isMember: user.isMember.value,
                        hint: user.remoteEntitlementHint,
                      ),
                      const SizedBox(height: 14),
                      _RemoteExperienceControl(
                        saving: _saving,
                        onResolutionTap: (resolutionTier) =>
                            _apply(resolutionTier: resolutionTier),
                        onFpsTap: (fps) => _apply(fps: fps),
                      ),
                      const SizedBox(height: 14),
                      _RemoteExperienceNote(isMember: user.isMember.value),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KqDetailHeader extends StatelessWidget {
  const _KqDetailHeader({required this.title});

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
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: q.ink),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

class _RemoteExperienceHero extends StatelessWidget {
  const _RemoteExperienceHero({
    required this.label,
    required this.isMember,
    required this.hint,
  });

  final String label;
  final bool isMember;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: q.isDark
              ? const [Color(0xFF19324A), Color(0xFF101E2D)]
              : const [Color(0xFFFFFFFF), Color(0xFFE6F4FF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: q.line),
        boxShadow: [
          BoxShadow(
            color: q.shadow.withOpacity(q.isDark ? 0.75 : 0.68),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: q.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: q.primary.withOpacity(0.18)),
            ),
            child: Icon(Icons.tune_rounded, color: q.primary, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: q.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            (isMember ? q.online : q.primary).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isMember ? 'VIP' : _mineText('Free plan'),
                        style: TextStyle(
                          color: isMember ? q.online : q.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.muted,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteExperienceNote extends StatelessWidget {
  const _RemoteExperienceNote({required this.isMember});

  final bool isMember;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isMember ? q.online : q.warning).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isMember ? q.online : q.warning).withOpacity(0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isMember
                ? Icons.workspace_premium_rounded
                : Icons.lock_outline_rounded,
            color: isMember ? q.online : q.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMember
                  ? _mineText('Membership quality unlocked')
                  : _mineText('Upgrade to unlock 1080p and 60 FPS'),
              style: TextStyle(
                color: q.ink,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteExperienceControl extends StatelessWidget {
  const _RemoteExperienceControl({
    required this.onResolutionTap,
    required this.onFpsTap,
    this.saving = false,
  });

  final ValueChanged<String> onResolutionTap;
  final ValueChanged<int> onFpsTap;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final user = gFFI.userModel;
    final isMember = user.isMember.value;
    final resolution = user.remoteResolutionSelection;
    final fps = user.remoteFpsSelection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OptionGroup(
          title: translate('Clarity'),
          icon: Icons.high_quality_rounded,
          children: [
            _QualityOption(
              label: '720p',
              caption: _mineText('Balanced quality'),
              selected: resolution == UserModel.remoteResolution720p,
              enabled: !saving,
              onTap: () => onResolutionTap(UserModel.remoteResolution720p),
            ),
            _QualityOption(
              label: '1080p',
              caption: isMember
                  ? _mineText('HD quality')
                  : _mineText('Members only'),
              selected: resolution == UserModel.remoteResolution1080p,
              locked: !isMember,
              enabled: !saving,
              onTap: isMember
                  ? () => onResolutionTap(UserModel.remoteResolution1080p)
                  : () =>
                      showToast(translate('Members can use 1080p / 60 FPS')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _OptionGroup(
          title: translate('Frame rate'),
          icon: Icons.speed_rounded,
          children: [
            _QualityOption(
              label: '30 FPS',
              caption: _mineText('Stable'),
              selected: fps == UserModel.freeMaxFps,
              enabled: !saving,
              onTap: () => onFpsTap(UserModel.freeMaxFps),
            ),
            _QualityOption(
              label: '${UserModel.memberMaxFps} FPS',
              caption:
                  isMember ? _mineText('Smooth') : _mineText('Members only'),
              selected: fps == UserModel.memberMaxFps,
              locked: !isMember,
              enabled: !saving,
              onTap: isMember
                  ? () => onFpsTap(UserModel.memberMaxFps)
                  : () =>
                      showToast(translate('Members can use 1080p / 60 FPS')),
            ),
          ],
        ),
      ],
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: q.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: q.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        ),
      ],
    );
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
    this.locked = false,
    this.enabled = true,
  });

  final String label;
  final String caption;
  final bool selected;
  final bool locked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final Color borderColor;
    final Color backgroundColor;
    final Color labelColor;
    if (selected) {
      borderColor = q.primary;
      backgroundColor = q.primary.withOpacity(0.12);
      labelColor = q.primaryDeep;
    } else if (locked) {
      borderColor = q.line.withOpacity(0.72);
      backgroundColor = q.surface.withOpacity(0.58);
      labelColor = q.muted.withOpacity(0.72);
    } else {
      borderColor = q.line;
      backgroundColor = q.surfaceSoft.withOpacity(0.74);
      labelColor = q.ink;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                locked
                    ? Icons.lock_rounded
                    : (selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined),
                color: locked ? q.muted.withOpacity(0.72) : q.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberPackageTile extends StatelessWidget {
  const _MemberPackageTile({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final KqMemberPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 150,
        constraints: const BoxConstraints(minHeight: 124),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? q.primary.withOpacity(0.12) : q.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? q.primary.withOpacity(0.62) : q.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: q.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: q.primary, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _priceLabel(package.priceYuan),
              style: TextStyle(
                color: q.primaryDeep,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              package.durationLabel,
              style: TextStyle(
                color: q.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              package.displayBenefitText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: q.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberOrderPanel extends StatelessWidget {
  const _MemberOrderPanel({required this.order});

  final KqMemberOrder order;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: q.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: q.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 176,
              height: 176,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _MemberOrderPayCode(order: order),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            order.displayPackageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: q.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${translate('Order No.')} ${order.orderNo}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: q.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${translate('Amount due')} ${_priceLabel(order.payAmount)}',
            style: TextStyle(
              color: q.primaryDeep,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberOrderPayCode extends StatelessWidget {
  const _MemberOrderPayCode({required this.order});

  final KqMemberOrder order;

  @override
  Widget build(BuildContext context) {
    final image = order.qrcodeImgUrl.trim();
    if (image.startsWith('data:image')) {
      final comma = image.indexOf(',');
      if (comma > 0) {
        try {
          return Image.memory(
            base64Decode(image.substring(comma + 1)),
            fit: BoxFit.contain,
          );
        } catch (_) {}
      }
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(image, fit: BoxFit.contain);
    }
    if (order.codeUrl.trim().isNotEmpty) {
      return QrImageView(
        data: order.codeUrl.trim(),
        version: QrVersions.auto,
      );
    }
    return const Icon(Icons.qr_code_2_rounded, size: 52);
  }
}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({
    required this.title,
    required this.groupTitle,
  });

  final String title;
  final String groupTitle;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Scaffold(
      backgroundColor: q.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: q.pageGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _KqDetailHeader(title: title),
              Expanded(
                child: SettingsPage(
                  showAccountGroup: false,
                  initialGroupTitle: groupTitle,
                  singleGroupOnly: true,
                  detailTitle: title,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _priceLabel(double price) {
  if (price == price.roundToDouble()) {
    return '¥${price.toStringAsFixed(0)}';
  }
  return '¥${price.toStringAsFixed(2)}';
}

String _mineText(String key) {
  final zh = localeName.toString().toLowerCase().startsWith('zh');
  final map = zh ? _mineZh : _mineEn;
  return map[key] ?? translate(key);
}

const _mineZh = {
  'Me': '我的',
  'Notifications': '通知',
  'No notifications': '暂无通知',
  'Free plan': '免费版',
  'Remote quality and FPS': '画质与帧率',
  'General settings': '通用设置',
  'Security settings': '安全设置',
  'Mobile device management': '网络与连接',
  'Contact us': '联系我们',
  'Software license agreement': '软件许可协议',
  'Privacy policy': '隐私政策',
  'No license information': '暂无许可协议信息',
  'Balanced quality': '均衡清晰',
  'HD quality': '高清画质',
  'Members only': '会员专享',
  'Stable': '稳定流畅',
  'Smooth': '更顺滑',
  'Membership quality unlocked': '会员画质已解锁，可使用 1080p 和 60 FPS。',
  'Upgrade to unlock 1080p and 60 FPS':
      '当前账号最多可用 720p / 30 FPS，开通会员后可使用 1080p / 60 FPS。',
};

const _mineEn = {
  'Me': 'Me',
  'Notifications': 'Notifications',
  'No notifications': 'No notifications',
  'Free plan': 'Free plan',
  'Remote quality and FPS': 'Quality & FPS',
  'General settings': 'General settings',
  'Security settings': 'Security settings',
  'Mobile device management': 'Network & Connection',
  'Contact us': 'Contact us',
  'Software license agreement': 'Software license agreement',
  'Privacy policy': 'Privacy policy',
  'No license information': 'No license information',
  'Balanced quality': 'Balanced quality',
  'HD quality': 'HD quality',
  'Members only': 'Members only',
  'Stable': 'Stable',
  'Smooth': 'Smooth',
  'Membership quality unlocked':
      'Membership quality unlocked. 1080p and 60 FPS are available.',
  'Upgrade to unlock 1080p and 60 FPS':
      'Current account supports up to 720p / 30 FPS. Upgrade to use 1080p / 60 FPS.',
};
