import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/kq_network_risk.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;
  final RxBool _postInstallActionBusy = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    final q = KqTheme.of(context);
    return _buildBlock(
        child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: q.pageGradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _KqHomeBackdrop(theme: q)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isIncomingOnly ? 12 : 18,
              16,
              18,
              16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildLeftPane(context),
                if (!isIncomingOnly) const SizedBox(width: 18),
                if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildKqHero(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: q.panelGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: q.panelStrong,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: q.iconBorder),
                  boxShadow: [
                    BoxShadow(
                      color: q.primary.withOpacity(q.isDark ? 0.24 : 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Image.asset('assets/icon.png', fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '鲲穹远程桌面',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '私有安全中继',
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
            ],
          ),
        ],
      ),
    );
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: const _KqProductTagline(),
        ),
      buildKqHero(context),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      if (!isOutgoingOnly) buildPostInstallPermissionReminder(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final q = KqTheme.of(context);
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 276.0 : 276.0,
        decoration: BoxDecoration(
          color: q.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: q.line.withOpacity(q.isDark ? 0.9 : 0.8)),
          boxShadow: [
            BoxShadow(
              color: q.shadow,
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 14,
                left: 18,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    child: Obx(
                      () => AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        width: 40,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _editHover.value
                              ? q.primary.withOpacity(0.16)
                              : q.primary.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _editHover.value
                                ? q.primary
                                : q.primary.withOpacity(0.28),
                            width: 1.2,
                          ),
                          boxShadow: [
                            if (_editHover.value)
                              BoxShadow(
                                color: q.primary.withOpacity(0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                          ],
                        ),
                        child: Icon(
                          Icons.settings_rounded,
                          color: _editHover.value
                              ? q.primary
                              : textColor?.withOpacity(0.72),
                          size: 20,
                        ),
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget buildPostInstallPermissionReminder(BuildContext context) {
    if (!isWindows ||
        bind.isDisableInstallation() ||
        !bind.mainIsInstalled() ||
        bind.mainIsInstalledDaemon(prompt: false)) {
      return const SizedBox();
    }
    final q = KqTheme.of(context);
    return Obx(() {
      final busy = _postInstallActionBusy.value;
      return Container(
        // kq-home-post-install-permission-reminder
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: q.primary.withOpacity(q.isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: q.primary.withOpacity(0.28)),
          boxShadow: [
            BoxShadow(
              color: q.primary.withOpacity(q.isDark ? 0.16 : 0.1),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _KqSmallIcon(icon: Icons.admin_panel_settings_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '用户主动授权',
                    style: TextStyle(
                      color: q.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '启用后台服务后，被控端离线重启后仍可接入；低误报安装包不会静默申请权限。',
              style: TextStyle(
                color: q.muted,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _KqPermissionReminderButton(
              label: '启用后台服务',
              icon: Icons.verified_user_outlined,
              primary: true,
              busy: busy,
              onPressed: () => _runPostInstallAction(() async {
                await bind.mainStartService();
                await mainSetBoolOption(kOptionStopService, false);
                showToast('已发起后台服务安装，请在系统授权弹窗中确认。');
              }),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _KqPermissionReminderButton(
                    label: '修复防火墙',
                    icon: Icons.security_update_good_outlined,
                    busy: busy,
                    onPressed: () => _runPostInstallAction(() async {
                      final result = await repairKqFirewallRules();
                      showToast(result.message);
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KqPermissionReminderButton(
                    label: '推荐权限',
                    icon: Icons.tune_rounded,
                    busy: busy,
                    onPressed: () => _runPostInstallAction(() async {
                      await bind.mainSetOption(
                          key: kOptionEnablePermChangeInAcceptWindow,
                          value: 'Y');
                      await bind.mainSetOption(
                          key: kOptionAllowRemoteConfigModification,
                          value: 'N');
                      showToast('已应用推荐远控权限。');
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _KqPermissionReminderButton(
              label: '浏览器远控入口',
              icon: Icons.link_rounded,
              busy: busy,
              onPressed: () => _runPostInstallAction(() async {
                final result = await registerKqBrowserRemoteProtocols();
                showToast(result.message);
              }),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _runPostInstallAction(Future<void> Function() action) async {
    if (_postInstallActionBusy.value) return;
    _postInstallActionBusy.value = true;
    try {
      await action();
    } finally {
      _postInstallActionBusy.value = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  buildRightPane(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.72 : 0.74),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: q.line.withOpacity(0.82)),
        boxShadow: [
          BoxShadow(
            color: q.shadow,
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: const ConnectionPage(),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    final q = KqTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: q.panelStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
        boxShadow: [
          BoxShadow(
            color: q.shadow,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _KqSmallIcon(icon: Icons.fingerprint_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate("ID"),
                  style: TextStyle(
                    fontSize: 13,
                    color: q.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              buildPopupMenu(context),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(ClipboardData(text: model.serverId.text));
                    showToast(translate("Copied"));
                  },
                  child: AnimatedBuilder(
                    animation: model.serverId,
                    builder: (context, _) => Text(
                      model.serverId.text.isEmpty ? '--' : model.serverId.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: translate('Copy'),
                splashRadius: 18,
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: q.primary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: model.serverId.text));
                  showToast(translate("Copied"));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final q = KqTheme.of(context);
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 16,
            backgroundColor:
                hover.value ? q.primary.withOpacity(0.12) : q.surfaceSoft,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? q.primary : textColor?.withOpacity(0.55),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool shareHover = false.obs;
    RxBool editHover = false.obs;
    final q = KqTheme.of(context);
    const actionButtonSize = 22.0;
    const actionButtonGap = 2.0;
    final actionButtons = <Widget>[
      if (model.selectedPasswordCanRefresh)
        AnimatedRotationWidget(
          onPressed: () => model.refreshSelectedPassword(),
          child: Tooltip(
            message: translate('Refresh Password'),
            child: _KqPasswordToolButton(
              icon: Icons.refresh_rounded,
              hover: refreshHover,
              iconSize: 16,
              size: actionButtonSize,
            ),
          ),
          onHover: (value) => refreshHover.value = value,
        ),
      if (model.selectedPasswordCanShare)
        InkWell(
          borderRadius: BorderRadius.circular(999),
          child: Tooltip(
            message: '复制并分享',
            child: _KqPasswordToolButton(
              icon: Icons.ios_share_rounded,
              hover: shareHover,
              size: actionButtonSize,
            ),
          ),
          onTap: () => _copyRemoteAssistShare(model),
          onHover: (value) => shareHover.value = value,
        ),
      if (!bind.isDisableSettings())
        InkWell(
          borderRadius: BorderRadius.circular(999),
          child: Tooltip(
            message: translate('Change Password'),
            child: _KqPasswordToolButton(
              icon: Icons.edit_rounded,
              hover: editHover,
              size: actionButtonSize,
            ),
          ),
          onTap: () => _showKqPasswordDialog(model),
          onHover: (value) => editHover.value = value,
        ),
    ];
    final actionButtonStack = <Widget>[];
    for (final action in actionButtons) {
      if (actionButtonStack.isNotEmpty) {
        actionButtonStack.add(const SizedBox(height: actionButtonGap));
      }
      actionButtonStack.add(action);
    }
    final actionColumnHeight = actionButtons.isEmpty
        ? 0.0
        : actionButtons.length * actionButtonSize +
            (actionButtons.length - 1) * actionButtonGap;
    final compactContentHeight =
        actionColumnHeight < 62.0 ? 62.0 : actionColumnHeight;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: const EdgeInsets.fromLTRB(12, 9, 9, 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            q.panelStrong,
            q.surfaceSoft.withOpacity(q.isDark ? 0.54 : 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
        boxShadow: [
          BoxShadow(
            color: q.shadow,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              key: const ValueKey('kq-password-compact-panel'),
              height: compactContentHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _KqSmallIcon(icon: Icons.password_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PopupMenuButton<KqPasswordKind>(
                            tooltip: '选择验证码类型',
                            initialValue: model.selectedPasswordKind,
                            onSelected: model.setSelectedPasswordKind,
                            color: q.panelStrong,
                            elevation: 8,
                            shadowColor: q.primary.withOpacity(0.16),
                            offset: const Offset(0, 4),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: q.line),
                            ),
                            itemBuilder: (context) => KqPasswordKind.values
                                .map(
                                  (kind) => PopupMenuItem<KqPasswordKind>(
                                    value: kind,
                                    height: 40,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    child: _KqPasswordKindMenuItem(
                                      label: _kqPasswordKindLabel(kind),
                                      selected:
                                          kind == model.selectedPasswordKind,
                                    ),
                                  ),
                                )
                                .toList(),
                            child: Container(
                              constraints: const BoxConstraints(
                                minHeight: 26,
                                maxWidth: 134,
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 9),
                              decoration: BoxDecoration(
                                color: q.surfaceSoft,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: q.line),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: AutoSizeText(
                                      model.selectedPasswordLabel,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: q.muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      minFontSize: 11,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: q.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onDoubleTap: () {
                      if (model.selectedPasswordCanCopy) {
                        Clipboard.setData(
                            ClipboardData(text: model.selectedPasswordText));
                        showToast(translate("Copied"));
                      }
                    },
                    child: Container(
                      key: const ValueKey('kq-password-value-row'),
                      height: 28,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedBuilder(
                        animation: model.selectedPasswordController,
                        builder: (context, _) => AutoSizeText(
                          model.selectedPasswordText,
                          maxLines: 1,
                          minFontSize: 14,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: q.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (actionButtons.isNotEmpty) ...[
            const SizedBox(width: 8),
            SizedBox(
              key: const ValueKey('kq-password-action-column'),
              width: actionButtonSize,
              height: compactContentHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: actionButtonStack,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyRemoteAssistShare(ServerModel model) async {
    final id = model.serverId.text.replaceAll(RegExp(r'\s+'), '').trim();
    final password = model.selectedPasswordText.trim();
    if (id.isEmpty || id == '--' || !model.selectedPasswordCanShare) {
      showToast('设备号或验证码还未就绪');
      return;
    }
    final link = _buildKqInviteLink(id: id, password: password);
    final text = [
      '使用 鲲穹远程桌面 即可对我发起远程协助',
      '设备ID：${formatID(id)}',
      '设备验证码：$password',
      '点击链接可直接发起远程协助：$link',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    showToast('已复制远程协助分享信息');
  }

  String _buildKqInviteLink({required String id, required String password}) {
    final base = _kqInviteBaseUrl();
    final payload = base64UrlEncode(utf8.encode(jsonEncode({
      'id': id,
      'password': password,
      'ts': DateTime.now().millisecondsSinceEpoch,
    })));
    return '$base?i=$payload';
  }

  String _kqInviteBaseUrl() {
    final configured =
        bind.mainGetBuildinOption(key: 'kq-share-invite-url').trim();
    if (configured.isNotEmpty) {
      return configured.replaceFirst(RegExp(r'/+$'), '');
    }
    final apiBase = bind
        .mainGetBuildinOption(key: 'kq-project-api-server')
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');
    if (apiBase.endsWith('/api')) {
      return '${apiBase.substring(0, apiBase.length - 4)}/invite';
    }
    return 'https://remotelink.kunqiongai.com/kq-api/invite';
  }

  String _kqPasswordKindLabel(KqPasswordKind kind) {
    switch (kind) {
      case KqPasswordKind.oneTime:
        return '一次性验证码';
      case KqPasswordKind.daily:
        return '今日验证码';
      case KqPasswordKind.permanent:
        return '长期验证码';
    }
  }

  void _showKqPasswordDialog(ServerModel model) {
    final editingKind = model.selectedPasswordKind;
    final controller = TextEditingController(
      text: model.selectedPasswordCanCopy ? model.selectedPasswordText : '',
    );
    final confirmController = TextEditingController(text: '');
    final maxLength = bind.mainMaxEncryptLen();
    var errMsg = '';
    var confirmErrMsg = '';
    var submitting = false;

    gFFI.dialogManager.show((setState, close, context) {
      final isPermanent = editingKind == KqPasswordKind.permanent;
      final title = _kqPasswordKindLabel(editingKind);
      final canRemovePermanent =
          isPermanent && model.localPermanentPasswordSet && !submitting;

      submit() async {
        if (submitting) {
          return;
        }
        setState(() {
          errMsg = '';
          confirmErrMsg = '';
          submitting = true;
        });
        final value = controller.text.trim();
        if (value.isEmpty) {
          setState(() {
            errMsg = '验证码不能为空';
            submitting = false;
          });
          return;
        }
        if (isPermanent && confirmController.text.trim() != value) {
          setState(() {
            confirmErrMsg = translate("The confirmation is not identical.");
            submitting = false;
          });
          return;
        }
        var ok = true;
        if (editingKind == KqPasswordKind.oneTime) {
          await model.setOneTimePassword(value);
        } else if (editingKind == KqPasswordKind.daily) {
          await model.setDailyPassword(value);
        } else {
          ok = await model.setPermanentPasswordPreview(value);
        }
        if (!ok) {
          setState(() {
            errMsg = translate("Failed");
            submitting = false;
          });
          return;
        }
        showToast('已更新$title');
        close();
      }

      removePermanent() async {
        if (submitting) {
          return;
        }
        setState(() {
          errMsg = '';
          confirmErrMsg = '';
          submitting = true;
        });
        final ok = await model.removePermanentPassword();
        if (!ok) {
          setState(() {
            errMsg = translate("Failed");
            submitting = false;
          });
          return;
        }
        showToast('已移除$title');
        close();
      }

      return CustomAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.key_rounded, color: MyTheme.accent),
            Text('修改$title').paddingOnly(left: 10),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 430),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: false,
                decoration: InputDecoration(
                  labelText: title,
                  errorText: errMsg.isEmpty ? null : errMsg,
                ),
                enabled: !submitting,
                maxLength: maxLength,
                onChanged: (_) {
                  if (errMsg.isNotEmpty) {
                    setState(() => errMsg = '');
                  }
                },
              ).workaroundFreezeLinuxMint(),
              if (isPermanent) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: false,
                  decoration: InputDecoration(
                    labelText: translate('Confirmation'),
                    errorText: confirmErrMsg.isEmpty ? null : confirmErrMsg,
                  ),
                  enabled: !submitting,
                  maxLength: maxLength,
                  onChanged: (_) {
                    if (confirmErrMsg.isNotEmpty) {
                      setState(() => confirmErrMsg = '');
                    }
                  },
                ).workaroundFreezeLinuxMint(),
                const SizedBox(height: 4),
                Text(
                  '长期验证码会同时更新远程连接使用的长期密码，并在本机可见。',
                  style: TextStyle(
                    color: KqTheme.of(context).muted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
              if (submitting)
                const LinearProgressIndicator().marginOnly(top: 12),
            ],
          ),
        ),
        actions: [
          dialogButton("Cancel", onPressed: close, isOutline: true),
          if (canRemovePermanent)
            dialogButton(
              "Remove",
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: removePermanent,
              isOutline: true,
            ),
          dialogButton(
            "OK",
            icon: const Icon(Icons.done_rounded),
            onPressed: submitting ? null : submit,
          ),
        ],
        onSubmit: submitting ? null : submit,
        onCancel: close,
      );
    });
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }
    if (bind.isCustomClient()) {
      return Container();
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 58, 146, 232),
                  Color.fromARGB(255, 121, 199, 250),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
            "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance
            .bumpMouse(dx: call.arguments['dx'], dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

class _KqProductTagline extends StatelessWidget {
  const _KqProductTagline();

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 2),
      alignment: Alignment.center,
      child: Text(
        '鲲穹AI旗下产品',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: q.primaryDeep,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _KqSmallIcon extends StatelessWidget {
  final IconData icon;

  const _KqSmallIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: q.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: q.primary.withOpacity(0.2)),
      ),
      child: Icon(icon, size: 16, color: q.primary),
    );
  }
}

class _KqPermissionReminderButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final bool busy;
  final Future<void> Function() onPressed;

  const _KqPermissionReminderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primary ? Colors.white : q.primary,
            ),
          )
        else
          Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    if (primary) {
      return SizedBox(
        width: double.infinity,
        height: 34,
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: q.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: q.primary.withOpacity(0.45),
            disabledForegroundColor: Colors.white.withOpacity(0.86),
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: q.primary,
          disabledForegroundColor: q.primary.withOpacity(0.42),
          side: BorderSide(color: q.primary.withOpacity(0.28)),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: child,
      ),
    );
  }
}

class _KqPasswordKindMenuItem extends StatelessWidget {
  final String label;
  final bool selected;

  const _KqPasswordKindMenuItem({
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      width: 136,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? q.surfaceSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? q.primaryDeep : q.ink,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                height: 1.1,
                letterSpacing: 0,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.check_rounded, size: 16, color: q.primary),
          ],
        ],
      ),
    );
  }
}

class _KqPasswordToolButton extends StatelessWidget {
  final IconData icon;
  final RxBool hover;
  final double iconSize;
  final double size;

  const _KqPasswordToolButton({
    required this.icon,
    required this.hover,
    this.iconSize = 19,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final muted = Theme.of(context).textTheme.titleLarge?.color;
    return Obx(
      () => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hover.value ? q.primary.withOpacity(0.12) : q.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: hover.value ? q.primary.withOpacity(0.24) : q.line,
          ),
        ),
        child: Icon(
          icon,
          color: hover.value ? q.primary : muted?.withOpacity(0.52),
          size: iconSize,
        ),
      ),
    );
  }
}

class _KqHomeBackdrop extends StatelessWidget {
  final KqTheme theme;

  const _KqHomeBackdrop({required this.theme});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _KqHomeBackdropPainter(theme));
  }
}

class _KqHomeBackdropPainter extends CustomPainter {
  final KqTheme theme;

  const _KqHomeBackdropPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color =
          (theme.isDark ? const Color(0xFF365A7B) : const Color(0xFFBBDDF6))
              .withOpacity(theme.isDark ? 0.14 : 0.18)
      ..strokeWidth = 1;
    const step = 44.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final diagonalPaint = Paint()
      ..color = theme.primary.withOpacity(theme.isDark ? 0.1 : 0.08)
      ..strokeWidth = 1.4;
    for (double x = -size.height; x < size.width; x += 180) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        diagonalPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      await bind.mainSetOption(
        key: kOptionKqPermanentPasswordPreview,
        value: pass,
      );
      await gFFI.serverModel.updatePasswordModel();
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            await bind.mainSetOption(
                key: kOptionKqPermanentPasswordPreview, value: "");
            await gFFI.serverModel.updatePasswordModel();
            close();
          },
          buttonStyle:
              ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
