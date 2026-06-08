import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/login.dart';
import '../../common/kq_theme.dart';
import '../../common/kq_project_api.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'page_shape.dart';

class AccountPage extends StatelessWidget implements PageShape {
  AccountPage({super.key});

  @override
  final title = translate('Account');

  @override
  final icon = const Icon(Icons.person_rounded);

  @override
  final appBarActions = const <Widget>[];

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    final q = KqTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: q.pageGradient,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Obx(() {
          final user = gFFI.userModel;
          final isLogin = user.userName.value.isNotEmpty;
          final avatar = bind.mainResolveAvatarUrl(avatar: user.avatar.value);
          final loginHint = isLogin
              ? user.remoteEntitlementHint
              : translate('Login to sync devices, favorites, and membership.');
          final subtitle = isLogin
              ? user.accountLabelWithHandle
              : translate(
                  'Sign in to unlock device sync and membership tools.');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroPanel(
                isLogin: isLogin,
                avatar: avatar,
                title: isLogin
                    ? user.displayNameOrUserName
                    : translate('Not logged in'),
                subtitle: subtitle,
                hint: loginHint,
                loginAction: () async {
                  if (isLogin) {
                    logOutConfirmDialog();
                  } else {
                    await loginDialog();
                  }
                },
                refreshAction: isLogin
                    ? () async {
                        await gFFI.userModel.refreshMembership(showError: true);
                      }
                    : null,
              ),
              const SizedBox(height: 14),
              _SectionPanel(
                title: translate('Login information'),
                children: [
                  _InfoRow(
                    label: translate('Username'),
                    value: isLogin
                        ? user.userName.value
                        : translate('Not logged in'),
                  ),
                  _InfoRow(
                    label: translate('Display name'),
                    value: isLogin
                        ? (user.displayName.value.isEmpty
                            ? translate('None')
                            : user.displayName.value)
                        : translate('None'),
                  ),
                  _InfoRow(
                    label: translate('Account'),
                    value: isLogin
                        ? user.accountLabelWithHandle
                        : translate('Login'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionPanel(
                title: translate('Membership'),
                children: [
                  _InfoRow(
                    label: translate('Plan'),
                    value: user.membershipName,
                  ),
                  _InfoRow(
                    label: translate('Remote quality'),
                    value: user.remoteQualityLabel,
                  ),
                  _InfoRow(
                    label: translate('Expiration'),
                    value: user.memberExpireAt.value.isEmpty
                        ? translate('Not available')
                        : user.memberExpireAt.value,
                  ),
                  if (user.memberLastError.value.isNotEmpty)
                    _InfoRow(
                      label: translate('Last error'),
                      value: user.memberLastError.value,
                      valueColor: q.offline,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionPanel(
                title: translate('Remote preferences'),
                children: [
                  _InfoRow(
                    label: translate('Resolution'),
                    value: user.remoteResolutionLabel,
                  ),
                  _InfoRow(
                    label: translate('Frame rate'),
                    value: '${user.remoteFpsSelection} FPS',
                  ),
                  _InfoRow(
                    label: translate('Recent history'),
                    value: '${KqProjectApi.recentHistoryLimit}',
                  ),
                  _InfoRow(
                    label: translate('Avatar'),
                    value: isLogin && user.avatar.value.trim().isNotEmpty
                        ? translate('Configured')
                        : translate('Not available'),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.isLogin,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.loginAction,
    required this.refreshAction,
  });

  final bool isLogin;
  final String avatar;
  final String title;
  final String subtitle;
  final String hint;
  final VoidCallback loginAction;
  final Future<void> Function()? refreshAction;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: q.panelGradient,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: q.line),
        boxShadow: [
          BoxShadow(
            color: q.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: q.surfaceSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: q.line),
                ),
                child: buildAvatarWidget(
                      avatar: avatar,
                      size: 56,
                      borderRadius: 16,
                      fallback: Icon(Icons.person_rounded,
                          color: q.primary, size: 28),
                    ) ??
                    Icon(Icons.person_rounded, color: q.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusChip(
                          text: isLogin
                              ? translate('Logged in')
                              : translate('Offline'),
                          color: isLogin ? q.online : q.offline,
                        ),
                        _StatusChip(
                            text: gFFI.userModel.membershipName,
                            color: q.primary),
                        _StatusChip(
                            text: gFFI.userModel.remoteQualityLabel,
                            color: q.warning),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            hint,
            style: TextStyle(
              color: q.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: loginAction,
                icon:
                    Icon(isLogin ? Icons.logout_rounded : Icons.login_rounded),
                label: Text(isLogin ? translate('Logout') : translate('Login')),
              ),
              OutlinedButton.icon(
                onPressed:
                    refreshAction == null ? null : () => refreshAction?.call(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(translate('Refresh membership')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: q.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: q.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: q.ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: q.muted,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? q.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
