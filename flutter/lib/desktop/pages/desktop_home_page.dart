import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/kq_project_api.dart';
import 'package:flutter_hbb/common/kq_network_risk.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/peer_model.dart';
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
const double _kqDesignerSidebarWidth = 195.0;
const double _kqDesignerHeaderHeight = 42.0;
const Color _kqDesignerBrandStart = Color(0xFF2563EB);
const Color _kqDesignerBrandMid = Color(0xFF4AADF0);
const Color _kqDesignerBrandEnd = Color(0xFF60A5FA);
const Color _kqDesignerAppBackground = Color(0xFFF8FAFC);
const Color _kqDesignerCardBorder = Color(0xFFE4E8EE);
const Color _kqDesignerTextPrimary = Color(0xFF1A2332);
const Color _kqDesignerTextSecondary = Color(0xFF6B7A8D);

Color _kqDesignerPanelColor(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.panelStrong.withOpacity(0.94) : Colors.white;
}

Color _kqDesignerPanelBorder(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.line.withOpacity(0.82) : _kqDesignerCardBorder;
}

Color _kqDesignerPanelShadow(BuildContext context, double lightOpacity) {
  final q = KqTheme.of(context);
  return q.isDark ? q.shadow : Colors.black.withOpacity(lightOpacity);
}

Color _kqDesignerPrimaryTextColor(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.ink : _kqDesignerTextPrimary;
}

Color _kqDesignerSecondaryTextColor(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.muted : _kqDesignerTextSecondary;
}

Color _kqDesignerDividerColor(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.line.withOpacity(0.7) : const Color(0xFFF0F3F8);
}

Color _kqDesignerInfoSurfaceColor(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.surfaceSoft.withOpacity(0.74) : const Color(0xFFEAF3FF);
}

Color _kqDesignerTableHeaderColor(BuildContext context) {
  final q = KqTheme.of(context);
  return q.isDark ? q.surfaceSoft.withOpacity(0.88) : const Color(0xFFBFE9FF);
}

String _kqHomeText(String zhCn, String en) {
  // kq-v233-desktop-home-locale-text
  return kqLocaleText(zhCn: zhCn, en: en);
}

final ValueNotifier<int> kqOpenDesktopHomeAccountEpoch = ValueNotifier<int>(0);

void openDesktopHomeAccountPage() {
  kqOpenDesktopHomeAccountEpoch.value++;
}

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
  SettingsTabKey? _embeddedSettingsPage;
  bool _showEmbeddedAccountPage = false;
  bool _showEmbeddedDevicesPage = false;
  bool _revealPasswordText = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;
  final RxBool _postInstallActionBusy = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    final q = KqTheme.of(context);
    final embeddedSettingsPage = _embeddedSettingsPage;
    final showAccountPage = _showEmbeddedAccountPage;
    final showDevicesPage = _showEmbeddedDevicesPage;
    return _buildBlock(
        child: Container(
      // kq-designer-desktop-shell
      decoration: BoxDecoration(
        color: q.isDark ? q.pageGradient.first : _kqDesignerAppBackground,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _KqHomeBackdrop(theme: q)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isIncomingOnly) _buildHomeSideRail(context),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isIncomingOnly ? 12 : 26,
                          isIncomingOnly ? 12 : 20,
                          isIncomingOnly ? 12 : 38,
                          isIncomingOnly ? 12 : 22,
                        ),
                        child: showAccountPage
                            ? _buildEmbeddedAccountPane(context)
                            : showDevicesPage
                                ? _buildEmbeddedDevicesPane(context)
                                : embeddedSettingsPage == null
                                    ? (isIncomingOnly
                                        ? buildLeftPane(context)
                                        : _buildRemoteAssistHome(context))
                                    : _buildEmbeddedSettingsPane(
                                        context,
                                        embeddedSettingsPage,
                                      ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ));
  }

  Widget _designerPageCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        // kq-v227-home-designer-panel-theme-colors
        color: _kqDesignerPanelColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kqDesignerPanelBorder(context)),
        boxShadow: [
          BoxShadow(
            color: _kqDesignerPanelShadow(context, 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _designerSectionCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        // kq-v227-home-designer-panel-theme-colors
        color: _kqDesignerPanelColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kqDesignerPanelBorder(context)),
        boxShadow: [
          BoxShadow(
            color: _kqDesignerPanelShadow(context, 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  void _openHomeAssist() {
    if (_embeddedSettingsPage == null &&
        !_showEmbeddedAccountPage &&
        !_showEmbeddedDevicesPage) {
      return;
    }
    setState(() {
      _embeddedSettingsPage = null;
      _showEmbeddedAccountPage = false;
      _showEmbeddedDevicesPage = false;
    });
  }

  void _openEmbeddedAccount() {
    if (bind.isDisableAccount() || _showEmbeddedAccountPage) return;
    setState(() {
      _showEmbeddedAccountPage = true;
      _embeddedSettingsPage = null;
      _showEmbeddedDevicesPage = false;
    });
  }

  void _openEmbeddedDevices() {
    if (_showEmbeddedDevicesPage) return;
    setState(() {
      _showEmbeddedDevicesPage = true;
      _showEmbeddedAccountPage = false;
      _embeddedSettingsPage = null;
    });
  }

  void _openEmbeddedSetting(SettingsTabKey page) {
    if (DesktopSettingPage.tabKeys.isEmpty) return;
    final target = DesktopSettingPage.tabKeys.contains(page)
        ? page
        : DesktopSettingPage.tabKeys.first;
    if (!_showEmbeddedAccountPage && _embeddedSettingsPage == target) return;
    setState(() {
      _showEmbeddedAccountPage = false;
      _showEmbeddedDevicesPage = false;
      _embeddedSettingsPage = target;
    });
  }

  String _homeTopBarTitle() {
    if (_showEmbeddedDevicesPage) {
      return _kqHomeText('设备', 'Devices');
    }
    if (_showEmbeddedAccountPage) {
      return _kqHomeText('我的账户', 'My account');
    }
    if (_embeddedSettingsPage != null) {
      return translate('Settings');
    }
    return _kqHomeText('远程协助', 'Remote assistance');
  }

  IconData _homeTopBarIcon() {
    if (_showEmbeddedDevicesPage) {
      return Icons.devices_rounded;
    }
    if (_showEmbeddedAccountPage) {
      return Icons.person_rounded;
    }
    if (_embeddedSettingsPage != null) {
      return Icons.settings_rounded;
    }
    return Icons.home_rounded;
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
                child: SvgPicture.asset('assets/icon.svg', fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kqHomeText('鲲穹远程桌面', 'Kunqiong Remote Desktop'),
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
                      _kqHomeText('私有安全中继', 'Private secure relay'),
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

  Widget _buildKqAssistHeader(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: q.panelGradient,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: q.line),
      ),
      child: Row(
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
                  color: q.primary.withOpacity(q.isDark ? 0.22 : 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: SvgPicture.asset('assets/icon.svg', fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kqHomeText('远程协助本机', 'Assist this device'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _kqHomeText('鲲穹AI旗下产品', 'A Kunqiong AI product'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: q.online.withOpacity(q.isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: q.online.withOpacity(0.34)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: q.online,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: q.online.withOpacity(0.36),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _kqHomeText('可被连接', 'Ready for connection'),
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSideRail(BuildContext context) {
    final useDesignerSidebar = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerSidebar) {
      return Container(
        // kq-designer-sidebar
        width: _kqDesignerSidebarWidth,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _kqDesignerBrandStart,
              _kqDesignerBrandMid,
              _kqDesignerBrandEnd,
            ],
          ),
          border:
              Border(right: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: SafeArea(
          bottom: false,
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: SvgPicture.asset(
                          'assets/icon.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kqHomeText('鲲穹远程桌面', 'Kunqiong Remote Desktop'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _kqHomeText('桌面端', 'Desktop'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                    child: Column(
                      children: [
                        _KqSideRailItem(
                          icon: Icons.desktop_windows_rounded,
                          label: _kqHomeText('远程协助', 'Remote assistance'),
                          active: _embeddedSettingsPage == null &&
                              !_showEmbeddedAccountPage &&
                              !_showEmbeddedDevicesPage,
                          onTap: _openHomeAssist,
                        ),
                        const SizedBox(height: 3),
                        _KqSideRailItem(
                          icon: Icons.devices_rounded,
                          label: _kqHomeText('设备', 'Devices'),
                          active: _showEmbeddedDevicesPage,
                          onTap: _openEmbeddedDevices,
                        ),
                        if (!bind.isDisableAccount()) ...[
                          const SizedBox(height: 3),
                          _KqSideRailItem(
                            // kq-home-my-account-entry
                            icon: Icons.person_rounded,
                            label: _kqHomeText('我的账户', 'My account'),
                            active: _showEmbeddedAccountPage,
                            onTap: _openEmbeddedAccount,
                          ),
                        ],
                        const SizedBox(height: 3),
                        _KqSideRailItem(
                          icon: Icons.settings_rounded,
                          label: translate('Settings'),
                          active: _embeddedSettingsPage != null &&
                              !_showEmbeddedAccountPage &&
                              !_showEmbeddedDevicesPage,
                          onTap: () =>
                              _openEmbeddedSetting(SettingsTabKey.general),
                        ),
                        const Spacer(),
                        _KqSideRailItem(
                          icon: Icons.public_rounded,
                          label: _kqHomeText('官网', 'Website'),
                          compact: true,
                          onTap: () => launchUrl(
                            Uri.parse('https://kunqiongai.com/'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final q = KqTheme.of(context);
    return Container(
      width: 168,
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.92 : 0.86),
        border: Border(right: BorderSide(color: q.line.withOpacity(0.82))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: q.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: q.iconBorder),
                    ),
                    child: SvgPicture.asset('assets/icon.svg',
                        fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kqHomeText('鲲穹远程桌面', 'Kunqiong Remote Desktop'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: q.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _kqHomeText('桌面端', 'Desktop'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: q.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _KqSideRailItem(
                icon: Icons.screen_share_rounded,
                label: _kqHomeText('远程协助', 'Remote assistance'),
                active:
                    _embeddedSettingsPage == null && !_showEmbeddedAccountPage,
                onTap: _openHomeAssist,
              ),
              if (!bind.isDisableAccount()) ...[
                const SizedBox(height: 8),
                _KqSideRailItem(
                  // kq-home-my-account-entry
                  icon: Icons.person_rounded,
                  label: _kqHomeText('我的账户', 'My account'),
                  active: _showEmbeddedAccountPage,
                  onTap: _openEmbeddedAccount,
                ),
              ],
              const SizedBox(height: 8),
              _KqSideRailItem(
                icon: Icons.settings_rounded,
                label: translate('Settings'),
                active:
                    _embeddedSettingsPage != null && !_showEmbeddedAccountPage,
                onTap: () => _openEmbeddedSetting(SettingsTabKey.general),
              ),
              const Spacer(),
              _KqSideRailItem(
                icon: Icons.public_rounded,
                label: _kqHomeText('官网', 'Website'),
                compact: true,
                onTap: () => launchUrl(
                  Uri.parse('https://kunqiongai.com/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTopBar(BuildContext context) {
    final useDesignerHeader = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerHeader) {
      return Container(
        // kq-designer-header-bar
        // kq-v213-login-left-titlebar
        height: _kqDesignerHeaderHeight,
        padding: const EdgeInsets.only(left: 24, right: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          border: const Border(
            bottom: BorderSide(color: Color(0xFFF0F2F6)),
          ),
        ),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _openEmbeddedAccount,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            _kqDesignerBrandMid,
                            _kqDesignerBrandStart,
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Obx(
                      () => Text(
                        gFFI.userModel.userName.value.isEmpty
                            ? '${translate('Login')} ›'
                            : '${gFFI.userModel.displayNameOrUserName} ›',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kqDesignerBrandStart,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      );
    }
    final q = KqTheme.of(context);
    final inSubpage = _embeddedSettingsPage != null || _showEmbeddedAccountPage;
    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: inSubpage ? 16 : 96),
      decoration: BoxDecoration(
        color: inSubpage
            ? q.panelStrong.withOpacity(q.isDark ? 0.72 : 0.82)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: inSubpage
            ? Border.all(color: q.line.withOpacity(0.88))
            : Border.all(color: Colors.transparent),
      ),
      child: Row(
        children: [
          if (inSubpage) ...[
            Icon(_homeTopBarIcon(), color: q.primary, size: 20),
            const SizedBox(width: 9),
            Text(
              _homeTopBarTitle(),
              style: TextStyle(
                color: q.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: q.primary.withOpacity(q.isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: q.primary.withOpacity(0.2)),
            ),
            child: Center(
              child: Text(
                _kqHomeText(
                    '会员畅享专属加速链路', 'Member exclusive acceleration route'),
                style: TextStyle(
                  color: q.primaryDeep,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildRemoteAssistHome(BuildContext context) {
    final useDesignerHome = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerHome) {
      return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // kq-home-compact-content-width
                // kq-v213-reference-home-width-812
                constraints: const BoxConstraints(maxWidth: 812),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDesignerMemberBanner(context),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 112,
                      child: _buildRemoteAssistLocalSummary(context, model),
                    ),
                    if (!bind.isOutgoingOnly())
                      buildPostInstallPermissionReminder(context)
                          .marginOnly(top: 14),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 162,
                      child: _designerSectionCard(
                        // kq-designer-connect-card
                        // kq-v213-connect-form-only-card
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        child: const ConnectionPage(
                          showOnlineStatusFooter: false,
                          showRecentPeers: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildDesignerSavedConnectionsHeader(context),
                    const SizedBox(height: 14),
                    Expanded(
                      // kq-v220-saved-connections-fill-empty-space
                      child: RecentPeersView(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, child) {
          return Container(
            // kq-remote-assist-workspace
            width: double.infinity,
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(42, 32, 42, 26),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  // kq-home-compact-content-width
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRemoteAssistLocalSummary(context, model),
                      if (!bind.isOutgoingOnly())
                        buildPostInstallPermissionReminder(context)
                            .marginOnly(top: 18),
                      const SizedBox(height: 30),
                      Expanded(
                        child: ConnectionPage(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesignerMemberBanner(BuildContext context) {
    return Obx(() {
      // kq-v219-home-member-banner-entitlement-aware
      final q = KqTheme.of(context);
      final isMember = gFFI.userModel.isMember.value;
      final actionLabel = isMember
          ? _kqHomeText('会员已生效', 'Membership active')
          : _kqHomeText('开通会员', 'Upgrade');
      final actionIcon =
          isMember ? Icons.check_circle_rounded : Icons.chevron_right_rounded;
      final bannerGradient = q.isDark
          ? LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                q.surfaceSoft.withOpacity(0.82),
                q.panelStrong.withOpacity(0.96),
                q.surfaceSoft.withOpacity(0.72),
              ],
            )
          : const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFEFF6FF),
                Color(0xFFDBEAFE),
                Color(0xFFEFF6FF),
              ],
            );
      return Container(
        // kq-designer-home-member-banner
        // kq-v227-home-member-banner-dark-colors
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: bannerGradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                q.isDark ? q.line.withOpacity(0.76) : const Color(0x1A2563EB),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.star_rounded,
                color: q.isDark ? q.primaryDeep : _kqDesignerBrandMid,
                size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _kqHomeText(
                    '会员畅享专属加速链路', 'Member exclusive acceleration route'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: q.isDark ? q.ink : const Color(0xFF1D4ED8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _openEmbeddedAccount,
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kqDesignerBrandMid, _kqDesignerBrandStart],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(actionIcon, color: Colors.white, size: 15),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildDesignerSavedConnectionsHeader(BuildContext context) {
    return AnimatedBuilder(
      // kq-v213-saved-connections-header
      animation: gFFI.recentPeersModel,
      builder: (context, _) {
        final count = gFFI.recentPeersModel.getPeersCount();
        final primaryText = _kqDesignerPrimaryTextColor(context);
        final secondaryText = _kqDesignerSecondaryTextColor(context);
        return Row(
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              color: primaryText,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _kqHomeText('已保存的连接', 'Saved connections'),
              style: TextStyle(
                color: primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 18,
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kqDesignerBrandMid, _kqDesignerBrandStart],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
            const Spacer(),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: secondaryText,
              size: 20,
            ),
          ],
        );
      },
    );
  }

  Widget _buildRemoteAssistLocalSummary(
      BuildContext context, ServerModel model) {
    final useDesignerLocalPanels = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerLocalPanels) {
      return _designerSectionCard(
        // kq-designer-local-credential-panels
        padding: EdgeInsets.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Center(child: _buildLocalIdInline(context, model)),
              ),
            ),
            Container(width: 1, color: _kqDesignerDividerColor(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Center(child: _buildPasswordInline(context, model)),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // kq-home-local-summary-no-heading
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLocalIdInline(context, model)),
            const SizedBox(width: 66),
            Expanded(child: _buildPasswordInline(context, model)),
          ],
        ),
      ],
    );
  }

  Widget _buildLocalIdInline(BuildContext context, ServerModel model) {
    final q = KqTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _kqHomeText('本机识别码', 'This device ID'),
          style: TextStyle(
            color: q.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: model.serverId,
                builder: (context, _) => AutoSizeText(
                  model.serverId.text.isEmpty ? '--' : model.serverId.text,
                  maxLines: 1,
                  minFontSize: 20,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    height: 1.05,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: translate('Copy'),
              splashRadius: 17,
              icon: Icon(Icons.copy_outlined, size: 17, color: q.muted),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: model.serverId.text));
                showToast(translate("Copied"));
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordInline(BuildContext context, ServerModel model) {
    final q = KqTheme.of(context);
    final canChangePassword = !bind.isDisableSettings();
    final actions = <Widget>[
      _KqInlineIconButton(
        tooltip: _revealPasswordText
            ? _kqHomeText('隐藏验证码', 'Hide verification code')
            : _kqHomeText('显示验证码', 'Show verification code'),
        icon: _revealPasswordText
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        onTap: () => setState(() => _revealPasswordText = !_revealPasswordText),
      ),
      if (model.selectedPasswordCanRefresh)
        _KqInlineIconButton(
          tooltip: translate('Refresh Password'),
          icon: Icons.refresh_rounded,
          onTap: () => model.refreshSelectedPassword(),
        ),
      if (model.selectedPasswordCanShare)
        _KqInlineIconButton(
          tooltip: _kqHomeText('复制并分享', 'Copy and share'),
          icon: Icons.ios_share_rounded,
          onTap: () => _copyRemoteAssistShare(model),
        ),
      if (canChangePassword)
        _KqInlineIconButton(
          tooltip: translate('Change Password'),
          icon: Icons.edit_rounded,
          onTap: () => _showKqPasswordDialog(model),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PopupMenuButton<KqPasswordKind>(
          tooltip: _kqHomeText('选择验证码类型', 'Choose verification code type'),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: _KqPasswordKindMenuItem(
                    label: _kqPasswordKindLabel(kind),
                    selected: kind == model.selectedPasswordKind,
                  ),
                ),
              )
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                model.selectedPasswordLabel,
                style: TextStyle(
                  color: q.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: q.muted),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: AutoSizeText(
                kqPasswordTextForUi(
                  rawText: model.selectedPasswordText,
                  reveal: _revealPasswordText,
                ),
                maxLines: 1,
                minFontSize: 18,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: q.ink,
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  height: 1.05,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ],
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
      _buildKqAssistHeader(context),
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
          color: q.panelStrong.withOpacity(q.isDark ? 0.74 : 0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: q.line.withOpacity(q.isDark ? 0.9 : 0.8)),
          boxShadow: [
            BoxShadow(
              color: q.shadow.withOpacity(q.isDark ? 0.8 : 0.72),
              blurRadius: 22,
              offset: const Offset(0, 12),
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
                        {_openEmbeddedSetting(DesktopSettingPage.tabKeys[0])}
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
                    _kqHomeText('用户主动授权', 'User-initiated authorization'),
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
              _kqHomeText('启用后台服务后，被控端离线重启后仍可接入；低误报安装包不会静默申请权限。',
                  'After enabling the background service, this device can still be reached after restart. Low false-positive installers never request permissions silently.'),
              style: TextStyle(
                color: q.muted,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _KqPermissionReminderButton(
              label: _kqHomeText('启用后台服务', 'Enable background service'),
              icon: Icons.verified_user_outlined,
              primary: true,
              busy: busy,
              onPressed: () => _runPostInstallAction(() async {
                await bind.mainStartService();
                await mainSetBoolOption(kOptionStopService, false);
                showToast(_kqHomeText('已发起后台服务安装，请在系统授权弹窗中确认。',
                    'Background service setup started. Please confirm in the system authorization prompt.'));
              }),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _KqPermissionReminderButton(
                    label: _kqHomeText('修复防火墙', 'Repair firewall'),
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
                    label: _kqHomeText('推荐权限', 'Recommended permissions'),
                    icon: Icons.tune_rounded,
                    busy: busy,
                    onPressed: () => _runPostInstallAction(() async {
                      await bind.mainSetOption(
                          key: kOptionEnablePermChangeInAcceptWindow,
                          value: 'Y');
                      await bind.mainSetOption(
                          key: kOptionAllowRemoteConfigModification,
                          value: 'N');
                      showToast(_kqHomeText('已应用推荐远控权限。',
                          'Recommended remote-control permissions applied.'));
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _KqPermissionReminderButton(
              label: _kqHomeText('浏览器远控入口', 'Browser remote-control entry'),
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
        color: q.panelStrong.withOpacity(q.isDark ? 0.64 : 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: q.line.withOpacity(0.72)),
        boxShadow: [
          BoxShadow(
            color: q.shadow.withOpacity(q.isDark ? 0.72 : 0.58),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: const ConnectionPage(showOnlineStatusFooter: false),
    );
  }

  Widget _buildEmbeddedSettingsPane(
    BuildContext context,
    SettingsTabKey initialTabkey,
  ) {
    final q = KqTheme.of(context);
    final useDesignerSettingsShell = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerSettingsShell) {
      return Container(
        // kq-settings-reference-shell
        // kq-v218-settings-reference-shell-unframed
        color: q.isDark ? q.pageGradient.first : _kqDesignerAppBackground,
        child: ClipRect(
          child: DesktopSettingPage(
            key: ValueKey<SettingsTabKey>(initialTabkey),
            initialTabkey: initialTabkey,
            embedded: true,
          ),
        ),
      );
    }
    return Container(
      // kq-settings-reference-shell
      decoration: BoxDecoration(
        color: q.isDark ? q.panelStrong.withOpacity(0.7) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.line.withOpacity(q.isDark ? 0.72 : 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DesktopSettingPage(
          key: ValueKey<SettingsTabKey>(initialTabkey),
          initialTabkey: initialTabkey,
          embedded: true,
        ),
      ),
    );
  }

  Widget _buildEmbeddedAccountPane(BuildContext context) {
    final q = KqTheme.of(context);
    final useDesignerAccountShell = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerAccountShell) {
      return Container(
        // kq-account-reference-shell
        // kq-v217-account-page-unframed
        color: q.isDark ? q.pageGradient.first : _kqDesignerAppBackground,
        child: const DesktopAccountPage(embedded: true),
      );
    }
    return Container(
      // kq-account-reference-shell
      decoration: BoxDecoration(
        color: q.isDark ? q.panelStrong.withOpacity(0.7) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.line.withOpacity(q.isDark ? 0.72 : 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: const ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        child: DesktopAccountPage(embedded: true),
      ),
    );
  }

  Widget _buildEmbeddedDevicesPane(BuildContext context) {
    return const _KqDesignerDevicesPane();
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    final q = KqTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 13),
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
                  _kqHomeText('本机识别码', 'This device ID'),
                  style: TextStyle(
                    fontSize: 13,
                    color: q.muted,
                    fontWeight: FontWeight.w800,
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
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
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
      onTap: () => _openEmbeddedSetting(SettingsTabKey.general),
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
    RxBool revealHover = false.obs;
    RxBool shareHover = false.obs;
    RxBool editHover = false.obs;
    final q = KqTheme.of(context);
    const actionButtonSize = 22.0;
    const actionButtonGap = 2.0;
    final actionButtons = <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(999),
        child: Tooltip(
          message: _revealPasswordText
              ? _kqHomeText('隐藏验证码', 'Hide verification code')
              : _kqHomeText('显示验证码', 'Show verification code'),
          child: _KqPasswordToolButton(
            icon: _revealPasswordText
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            hover: revealHover,
            iconSize: 15,
            size: actionButtonSize,
          ),
        ),
        onTap: () => setState(() => _revealPasswordText = !_revealPasswordText),
        onHover: (value) => revealHover.value = value,
      ),
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
            message: _kqHomeText('复制并分享', 'Copy and share'),
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
                            tooltip: _kqHomeText(
                                '选择验证码类型', 'Choose verification code type'),
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
                          kqPasswordTextForUi(
                            rawText: model.selectedPasswordText,
                            reveal: _revealPasswordText,
                          ),
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
      showToast(_kqHomeText(
          '设备号或验证码还未就绪', 'Device ID or verification code is not ready yet'));
      return;
    }
    final link = _buildKqInviteLink(id: id, password: password);
    final text = [
      _kqHomeText('使用 鲲穹远程桌面 即可对我发起远程协助',
          'Use Kunqiong Remote Desktop to start remote assistance with me'),
      '${_kqHomeText('设备ID', 'Device ID')}: ${formatID(id)}',
      '${_kqHomeText('设备验证码', 'Verification code')}: $password',
      '${_kqHomeText('点击链接可直接发起远程协助', 'Open the link to start remote assistance')}: $link',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    showToast(
        _kqHomeText('已复制远程协助分享信息', 'Remote assistance share info copied'));
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
        return _kqHomeText('一次性验证码', 'One-time verification code');
      case KqPasswordKind.daily:
        return _kqHomeText('今日验证码', 'Today verification code');
      case KqPasswordKind.permanent:
        return _kqHomeText('长期验证码', 'Permanent verification code');
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
      final canRandomGenerate =
          kqPasswordKindSupportsRandomGenerate(editingKind) && !submitting;

      fillRandomPassword() {
        final value = model.generateVerificationCodePreview();
        controller.text = value;
        if (isPermanent) {
          confirmController.text = value;
        }
        setState(() {
          errMsg = '';
          confirmErrMsg = '';
        });
      }

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
            errMsg =
                _kqHomeText('验证码不能为空', 'Verification code cannot be empty');
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
        showToast('${_kqHomeText('已更新', 'Updated')} $title');
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
        showToast('${_kqHomeText('已移除', 'Removed')} $title');
        close();
      }

      return CustomAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.key_rounded, color: MyTheme.accent),
            Text('${_kqHomeText('修改', 'Edit')} $title').paddingOnly(left: 10),
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
                  _kqHomeText(
                    '长期验证码会同时更新远程连接使用的长期密码，并在本机可见。',
                    'The permanent verification code also updates the permanent password used for remote connections and remains visible on this device.',
                  ),
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
            _kqHomeText('随机验证码', 'Random code'),
            icon: const Icon(Icons.casino_outlined),
            onPressed: canRandomGenerate ? fillRandomPassword : null,
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
    kqOpenDesktopHomeAccountEpoch.addListener(_openEmbeddedAccount);
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
        await windowOnTop(null);
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
      } else if (call.method == kWindowShowToast) {
        final text = (call.arguments is Map ? call.arguments['text'] : null)
                ?.toString() ??
            '';
        if (text.trim().isNotEmpty) {
          showToast(text, timeout: const Duration(seconds: 6));
        }
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
    kqOpenDesktopHomeAccountEpoch.removeListener(_openEmbeddedAccount);
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

class _KqSideRailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool compact;

  const _KqSideRailItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.compact = false,
  });

  @override
  State<_KqSideRailItem> createState() => _KqSideRailItemState();
}

class _KqSideRailItemState extends State<_KqSideRailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final useDesignerSidebarItem = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerSidebarItem) {
      final active = widget.active;
      final bg = active
          ? Colors.white.withOpacity(0.2)
          : (_hover
              ? const Color(0xFF155AC8).withOpacity(0.34)
              : Colors.transparent);
      final fg =
          active || _hover ? Colors.white : Colors.white.withOpacity(0.9);
      return InkWell(
        // kq-v231-sidebar-hover-readable-colors
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.transparent,
        splashColor: Colors.white.withOpacity(0.08),
        highlightColor: Colors.white.withOpacity(0.04),
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hover = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: widget.compact ? 38 : 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active || _hover
                  ? Colors.white.withOpacity(_hover && !active ? 0.22 : 0.0)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              if (active)
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                )
              else
                const SizedBox(width: 12),
              Icon(widget.icon, color: fg, size: widget.compact ? 17 : 18),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: widget.compact ? 14 : 14.5,
                    fontWeight:
                        active || _hover ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final q = KqTheme.of(context);
    final active = widget.active;
    final bg = active
        ? q.primary.withOpacity(q.isDark ? 0.2 : 0.1)
        : (_hover ? q.surfaceSoft.withOpacity(0.86) : Colors.transparent);
    final fg = active || _hover ? q.primaryDeep : q.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: Colors.transparent,
      splashColor: q.primary.withOpacity(0.08),
      highlightColor: q.primary.withOpacity(0.04),
      onTap: widget.onTap,
      onHover: (value) => setState(() => _hover = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: widget.compact ? 36 : 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active || _hover
                ? q.primary.withOpacity(active ? 0.28 : 0.22)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: fg, size: widget.compact ? 17 : 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? q.ink : fg,
                  fontSize: widget.compact ? 12 : 13,
                  fontWeight:
                      active || _hover ? FontWeight.w900 : FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KqInlineIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _KqInlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_KqInlineIconButton> createState() => _KqInlineIconButtonState();
}

class _KqInlineIconButtonState extends State<_KqInlineIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hover = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hover
                ? q.primary.withOpacity(q.isDark ? 0.22 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            widget.icon,
            color: _hover ? q.primaryDeep : q.muted,
            size: 17,
          ),
        ),
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
        _kqHomeText('鲲穹AI旗下产品', 'A Kunqiong AI product'),
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

const Duration _kqDesignerDevicesOnlineRefresh = Duration(seconds: 5);
const String _kqDesignerDevicesQueryOnlinesEvent = 'callback_query_onlines';
const String _kqDesignerManualDevicesOptionKey = 'kq_designer_manual_devices';

class _KqDesignerDevicesPane extends StatefulWidget {
  const _KqDesignerDevicesPane();

  @override
  State<_KqDesignerDevicesPane> createState() => _KqDesignerDevicesPaneState();
}

class _KqDesignerDevicesPaneState extends State<_KqDesignerDevicesPane> {
  Timer? _onlineRefreshTimer;
  Timer? _accountDeviceRetryTimer;
  List<Peer> _accountDevicePeers = [];
  List<Peer> _manualDevicePeers = [];
  bool _accountDevicesLoading = false;
  DateTime? _accountDevicesLoadedAt;
  DateTime? _accountDevicesLastFailedAt;
  bool _accountDeviceCacheRestored = false;
  bool _disposed = false;
  late final String _accountDeviceOnlineHandlerName;

  @override
  void initState() {
    super.initState();
    _accountDeviceOnlineHandlerName =
        'kq designer account devices ${identityHashCode(this)}';
    platformFFI.registerEventHandler(
      _kqDesignerDevicesQueryOnlinesEvent,
      _accountDeviceOnlineHandlerName,
      (evt) async {
        _handleAccountDeviceOnlineState(evt);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreManualDevices();
      _restoreCachedAccountDevices();
      _refreshDevices(forceAccountDevices: true);
    });
    _onlineRefreshTimer = Timer.periodic(
      // kq-v214-devices-online-refresh
      _kqDesignerDevicesOnlineRefresh,
      (_) => _queryDeviceOnlineStates(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _onlineRefreshTimer?.cancel();
    _accountDeviceRetryTimer?.cancel();
    platformFFI.unregisterEventHandler(
      _kqDesignerDevicesQueryOnlinesEvent,
      _accountDeviceOnlineHandlerName,
    );
    super.dispose();
  }

  List<Peer> _recentPeers() {
    final seen = <String>{};
    final peers = <Peer>[];
    for (final peer in gFFI.recentPeersModel.peers) {
      final id = kqNormalizePeerId(peer.id);
      if (id.isEmpty || !seen.add(id)) continue;
      peers.add(peer);
    }
    return peers;
  }

  List<Peer> _allDevicePeers(
    List<Peer> recentPeers,
    List<Peer> accountDevicePeers,
    List<Peer> manualDevicePeers,
  ) {
    final seen = <String>{};
    final peers = <Peer>[];

    void addPeer(Peer peer) {
      final id = kqNormalizePeerId(peer.id);
      final key = id.isNotEmpty ? 'id:$id' : _accountDeviceDisplayKey(peer);
      if (key.isEmpty || !seen.add(key)) return;
      peers.add(peer);
    }

    for (final peer in accountDevicePeers) {
      addPeer(peer);
    }
    for (final peer in manualDevicePeers) {
      addPeer(peer);
    }
    for (final peer in recentPeers) {
      addPeer(peer);
    }
    return peers;
  }

  void _refreshDevices({bool forceAccountDevices = false}) {
    bind.mainLoadRecentPeers();
    _ensureAccountDevicesLoaded(force: forceAccountDevices);
    _queryDeviceOnlineStates();
  }

  void _queryDeviceOnlineStates() {
    final ids = <String>{};
    for (final peer in [
      ..._recentPeers(),
      ..._accountDevicePeers,
      ..._manualDevicePeers
    ]) {
      final id = kqNormalizePeerId(peer.id);
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    if (ids.isEmpty) return;
    bind.queryOnlines(ids: ids.toList(growable: false));
  }

  void _ensureAccountDevicesLoaded({bool force = false}) {
    if (_accountDevicesLoading) return;
    final loadedAt = _accountDevicesLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(seconds: 30)) {
      return;
    }
    final failedAt = _accountDevicesLastFailedAt;
    if (!force &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(seconds: 5)) {
      return;
    }
    _accountDevicesLoading = true;
    () async {
      try {
        await KqProjectApi.syncCurrentAccountDevice(force: force);
        final currentDeviceKey = await KqProjectApi.currentAccountDeviceKey();
        final currentDeviceId =
            kqNormalizePeerId((await bind.mainGetMyId()).trim());
        final accountDevices = await KqProjectApi.tryFetchAccountDevices();
        if (accountDevices == null) {
          _accountDevicesLastFailedAt = DateTime.now();
          _scheduleAccountDeviceRetry();
          return;
        }
        final accountDeviceOnlineStates = _accountDeviceOnlineStates();
        final visibleAccountDevices = accountDevices
            .where((peer) => !_isCurrentAccountDevice(
                  peer,
                  currentDeviceKey,
                  currentDeviceId,
                ))
            .toList();
        final dedupedAccountDevices =
            _dedupeAccountDevicePeers(visibleAccountDevices);
        _restoreAccountDeviceOnlineStates(
          dedupedAccountDevices,
          accountDeviceOnlineStates,
        );
        KqProjectApi.cacheAccountDevices(dedupedAccountDevices);
        await _applyLocalAliasesToAccountDevices(dedupedAccountDevices);
        if (_disposed || !mounted) return;
        setState(() {
          _accountDevicePeers = dedupedAccountDevices;
          _accountDevicesLoadedAt = DateTime.now();
          _accountDevicesLastFailedAt = null;
        });
        _queryAccountDeviceOnlines(dedupedAccountDevices);
      } finally {
        _accountDevicesLoading = false;
      }
    }();
  }

  void _restoreCachedAccountDevices() {
    if (_accountDeviceCacheRestored) return;
    _accountDeviceCacheRestored = true;
    final cached = KqProjectApi.loadCachedAccountDevices();
    if (cached.isEmpty) return;
    () async {
      await _applyLocalAliasesToAccountDevices(cached);
      if (_disposed || !mounted) return;
      setState(() {
        _accountDevicePeers = cached;
      });
      _queryAccountDeviceOnlines(cached);
    }();
  }

  void _restoreManualDevices() {
    try {
      final raw =
          bind.getLocalFlutterOption(k: _kqDesignerManualDevicesOptionKey);
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is! List) return;
      final peers = decoded
          .whereType<Map>()
          .map((item) => Peer.fromJson(Map<String, dynamic>.from(item)))
          .where((peer) => kqNormalizePeerId(peer.id).isNotEmpty)
          .toList();
      if (peers.isEmpty) return;
      setState(() {
        _manualDevicePeers = peers;
      });
      _queryDeviceOnlines(peers);
    } catch (e) {
      debugPrint('KQ designer manual devices restore failed: $e');
    }
  }

  void _cacheManualDevices() {
    try {
      bind.setLocalFlutterOption(
        k: _kqDesignerManualDevicesOptionKey,
        v: jsonEncode(_manualDevicePeers.map((peer) => peer.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('KQ designer manual devices cache failed: $e');
    }
  }

  Future<void> _applyLocalAliasesToAccountDevices(List<Peer> peers) async {
    for (final peer in peers) {
      final alias =
          (await bind.mainGetPeerOption(id: peer.id, key: 'alias')).trim();
      if (alias.isNotEmpty) {
        peer.alias = alias;
      }
    }
  }

  void _scheduleAccountDeviceRetry() {
    if (_accountDeviceRetryTimer?.isActive ?? false) return;
    _accountDeviceRetryTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed || !mounted) return;
      _ensureAccountDevicesLoaded(force: true);
    });
  }

  List<Peer> _dedupeAccountDevicePeers(List<Peer> peers) {
    final seen = <String>{};
    final deduped = <Peer>[];
    for (final peer in peers) {
      final key = _accountDeviceDisplayKey(peer);
      if (key.isEmpty || seen.add(key)) {
        deduped.add(peer);
      }
    }
    return deduped;
  }

  String _accountDeviceDisplayKey(Peer peer) {
    final name = (peer.alias.trim().isNotEmpty ? peer.alias : peer.hostname)
        .trim()
        .toLowerCase();
    if (name.isEmpty) {
      return kqNormalizePeerId(peer.id);
    }
    return '${peer.platform.trim().toLowerCase()}|$name';
  }

  Map<String, bool> _accountDeviceOnlineStates() {
    final states = <String, bool>{};
    for (final peer in _accountDevicePeers) {
      if (!peer.onlineStateKnown) continue;
      final id = kqNormalizePeerId(peer.id);
      if (id.isNotEmpty) {
        states[id] = peer.online;
      }
      final displayKey = _accountDeviceDisplayKey(peer);
      if (displayKey.isNotEmpty) {
        states[displayKey] = peer.online;
      }
    }
    return states;
  }

  void _restoreAccountDeviceOnlineStates(
    List<Peer> peers,
    Map<String, bool> states,
  ) {
    for (final peer in peers) {
      final state = states[kqNormalizePeerId(peer.id)] ??
          states[_accountDeviceDisplayKey(peer)];
      if (state == null) continue;
      peer.onlineStateKnown = true;
      peer.online = state;
    }
  }

  void _queryAccountDeviceOnlines(List<Peer> peers) {
    _queryDeviceOnlines(peers);
  }

  void _queryDeviceOnlines(List<Peer> peers) {
    final ids = <String>[];
    for (final peer in peers) {
      final id = kqNormalizePeerId(peer.id);
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    if (ids.isEmpty) return;
    bind.queryOnlines(ids: ids);
  }

  void _handleAccountDeviceOnlineState(Map<String, dynamic> evt) {
    final onlineSet = (evt['onlines'] ?? '')
        .toString()
        .split(',')
        .map(kqNormalizePeerId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final offlineSet = (evt['offlines'] ?? '')
        .toString()
        .split(',')
        .map(kqNormalizePeerId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (_applyOnlineStateToDevicePeers(onlineSet, offlineSet) && mounted) {
      setState(() {});
    }
  }

  bool _applyOnlineStateToDevicePeers(
    Set<String> onlineSet,
    Set<String> offlineSet,
  ) {
    var changed = false;
    for (final peer in [..._accountDevicePeers, ..._manualDevicePeers]) {
      final id = kqNormalizePeerId(peer.id);
      if (onlineSet.contains(id)) {
        if (!peer.onlineStateKnown || !peer.online) {
          peer.onlineStateKnown = true;
          peer.online = true;
          changed = true;
        }
      } else if (offlineSet.contains(id)) {
        if (!peer.onlineStateKnown || peer.online) {
          peer.onlineStateKnown = true;
          peer.online = false;
          changed = true;
        }
      }
    }
    return changed;
  }

  bool _isCurrentAccountDevice(
    Peer peer,
    String currentDeviceKey,
    String currentDeviceId,
  ) {
    final peerDeviceKey = peer.accountDeviceKey.trim();
    if (peerDeviceKey.isNotEmpty &&
        !_isLegacyAccountDeviceKey(peer, peerDeviceKey)) {
      return currentDeviceKey.isNotEmpty && peerDeviceKey == currentDeviceKey;
    }
    return currentDeviceId.isNotEmpty &&
        kqNormalizePeerId(peer.id) == currentDeviceId;
  }

  bool _isLegacyAccountDeviceKey(Peer peer, String peerDeviceKey) {
    return kqNormalizePeerId(peerDeviceKey) == kqNormalizePeerId(peer.id);
  }

  void _showAddDeviceDialog() {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final deviceTypeMenuController = MenuController();
    var platform = kPeerPlatformWindows;
    var errorText = '';
    var submitting = false;

    gFFI.dialogManager.show((setState, close, context) {
      void closeDialog([dynamic result]) {
        deviceTypeMenuController.close();
        close(result);
      }

      void selectPlatform(String value) {
        setState(() => platform = value);
      }

      Widget platformMenuItem(String value, String label) {
        return MenuItemButton(
          onPressed: submitting ? null : () => selectPlatform(value),
          child: Text(label),
        );
      }

      Future<void> submit() async {
        if (submitting) return;
        final id = kqNormalizePeerId(idController.text);
        final alias = nameController.text.trim();
        if (id.isEmpty) {
          setState(() {
            errorText = _kqHomeText('请输入设备识别码', 'Enter the device ID');
          });
          return;
        }
        setState(() {
          errorText = '';
          submitting = true;
        });
        final peer = Peer.fromJson({
          'id': id,
          'alias': alias,
          'hostname': alias,
          'platform': platform,
          'onlineStateKnown': false,
        });
        KqProjectApi.clearRecentPeerDeleted(id);
        if (alias.isNotEmpty) {
          await bind.mainSetPeerOption(id: id, key: 'alias', value: alias);
        }
        unawaited(KqProjectApi.recordPeer(peer));
        if (!mounted || _disposed) return;
        this.setState(() {
          final index = _manualDevicePeers
              .indexWhere((item) => kqNormalizePeerId(item.id) == id);
          if (index >= 0) {
            _manualDevicePeers[index] = peer;
          } else {
            _manualDevicePeers.insert(0, peer);
          }
          _cacheManualDevices();
        });
        _queryDeviceOnlines([peer]);
        bind.mainLoadRecentPeers();
        showToast(_kqHomeText('已添加设备', 'Device added'));
        closeDialog();
      }

      return CustomAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_to_queue_rounded, color: MyTheme.accent),
            Text(_kqHomeText('添加远控设备', 'Add remote device'))
                .paddingOnly(left: 10),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: _kqHomeText('设备识别码', 'Device ID'),
                  hintText: '123 456 789',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
                enabled: !submitting,
                onChanged: (_) {
                  if (errorText.isNotEmpty) {
                    setState(() => errorText = '');
                  }
                },
                onSubmitted: (_) => submit(),
              ).workaroundFreezeLinuxMint(),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: _kqHomeText('设备名称（可选）', 'Device name (optional)'),
                ),
                enabled: !submitting,
                onSubmitted: (_) => submit(),
              ).workaroundFreezeLinuxMint(),
              const SizedBox(height: 12),
              MenuAnchor(
                controller: deviceTypeMenuController,
                crossAxisUnconstrained: false,
                menuChildren: [
                  platformMenuItem(kPeerPlatformWindows, 'Windows'),
                  platformMenuItem(kPeerPlatformMacOS, 'macOS'),
                  platformMenuItem(kPeerPlatformLinux, 'Linux'),
                  platformMenuItem(kPeerPlatformAndroid, 'Android'),
                  platformMenuItem(kPeerPlatformIOS, 'iOS'),
                ],
                builder: (context, controller, child) => InkWell(
                  onTap: submitting
                      ? null
                      : () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: _kqHomeText('设备类型', 'Device type'),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    isEmpty: false,
                    child: Text(platform),
                  ),
                ),
              ),
              if (submitting)
                const LinearProgressIndicator().marginOnly(top: 12),
            ],
          ),
        ),
        actions: [
          dialogButton('Cancel', onPressed: closeDialog, isOutline: true),
          dialogButton(
            'Add',
            icon: const Icon(Icons.add_rounded),
            onPressed: submitting ? null : submit,
          ),
        ],
        onCancel: closeDialog,
      );
    }, backDismiss: true, clickMaskDismiss: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gFFI.recentPeersModel,
      builder: (context, _) {
        final allRecentPeers = _recentPeers();
        final recentPeers = allRecentPeers.take(4).toList(growable: false);
        final accountDevicePeers = _accountDevicePeers.toList(growable: false);
        final manualDevicePeers = _manualDevicePeers.toList(growable: false);
        final allDevicePeers = _allDevicePeers(
            allRecentPeers, accountDevicePeers, manualDevicePeers);
        return Container(
          // kq-designer-devices-page
          // kq-v214-devices-reference-page
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KqDesignerDevicesSectionHeader(
                icon: Icons.access_time_rounded,
                title: _kqHomeText('最近连接', 'Recent connections'),
              ),
              const SizedBox(height: 10),
              SizedBox(
                // kq-v214-devices-recent-strip
                height: 112,
                child: recentPeers.isEmpty
                    ? const _KqDesignerDevicesEmptyState(compact: true)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: recentPeers.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          return _KqDesignerDeviceRecentCard(
                            peer: recentPeers[index],
                            highlighted: index == 0,
                            onConnect: () => _connectToPeer(recentPeers[index]),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 22),
              _KqDesignerDevicesSectionHeader(
                icon: Icons.desktop_windows_outlined,
                title: _kqHomeText('全部设备', 'All devices'),
                count: allDevicePeers.length,
                trailing: _KqDesignerDevicesAddButton(
                  onPressed: _showAddDeviceDialog,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                // kq-v214-devices-table
                // kq-v215-devices-account-source
                child: _KqDesignerDevicesTable(
                  peers: allDevicePeers,
                  onConnect: _connectToPeer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connectToPeer(Peer peer) {
    final id = kqNormalizePeerId(peer.id);
    if (id.isEmpty) return;
    // kq-v214-devices-connect-action
    connect(context, id);
  }
}

class _KqDesignerDevicesSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final Widget? trailing;

  const _KqDesignerDevicesSectionHeader({
    required this.icon,
    required this.title,
    this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kqDesignerBrandMid),
          const SizedBox(width: 8),
          Text(
            count == null ? title : '$title  $count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _kqDesignerPrimaryTextColor(context),
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _KqDesignerDevicesAddButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _KqDesignerDevicesAddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: Text(_kqHomeText('添加设备', 'Add device')),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: q.isDark ? q.primaryDeep : const Color(0xFF1E73F8),
          backgroundColor: q.isDark
              ? q.surfaceSoft.withOpacity(0.54)
              : const Color(0xFFF2F7FF),
          side: BorderSide(
            color:
                q.isDark ? q.line.withOpacity(0.86) : const Color(0xFFCFE0FF),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _KqDesignerDeviceRecentCard extends StatelessWidget {
  final Peer peer;
  final bool highlighted;
  final VoidCallback onConnect;

  const _KqDesignerDeviceRecentCard({
    required this.peer,
    required this.highlighted,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      width: 180,
      height: 112,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        // kq-v227-devices-recent-card-dark-colors
        color: _kqDesignerPanelColor(context),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: highlighted
              ? (q.isDark
                  ? q.primary.withOpacity(0.7)
                  : const Color(0xFFB8D5FF))
              : _kqDesignerPanelBorder(context),
        ),
        boxShadow: [
          if (highlighted)
            BoxShadow(
              color: q.primary.withOpacity(q.isDark ? 0.2 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _KqDesignerDevicePlatformIcon(peer: peer, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kqDesignerDeviceName(peer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kqDesignerPrimaryTextColor(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _kqDesignerPeerId(peer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.isDark
                            ? _kqDesignerSecondaryTextColor(context)
                            : const Color(0xFF8A9BB0),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              _KqDesignerDeviceStatus(peer: peer),
              const Spacer(),
              _KqDesignerDevicesConnectButton(onPressed: onConnect),
            ],
          ),
        ],
      ),
    );
  }
}

class _KqDesignerDevicesTable extends StatelessWidget {
  final List<Peer> peers;
  final ValueChanged<Peer> onConnect;

  const _KqDesignerDevicesTable({
    required this.peers,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // kq-v227-devices-table-dark-colors
        color: _kqDesignerPanelColor(context),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _kqDesignerPanelBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _KqDesignerDevicesTableHeader(),
          Expanded(
            child: peers.isEmpty
                ? const _KqDesignerDevicesEmptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: peers.length,
                    separatorBuilder: (context, _) => Divider(
                      height: 1,
                      thickness: 1,
                      color: _kqDesignerDividerColor(context),
                    ),
                    itemBuilder: (context, index) => _KqDesignerDevicesTableRow(
                      peer: peers[index],
                      onConnect: () => onConnect(peers[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KqDesignerDevicesTableHeader extends StatelessWidget {
  const _KqDesignerDevicesTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: _kqDesignerTableHeaderColor(context),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: _KqDesignerDevicesHeaderText(
              _kqHomeText('设备名称', 'Device name'),
            ),
          ),
          Expanded(
            flex: 24,
            child: _KqDesignerDevicesHeaderText(
              _kqHomeText('识别码', 'ID'),
            ),
          ),
          Expanded(
            flex: 18,
            child: _KqDesignerDevicesHeaderText(
              _kqHomeText('系统', 'System'),
            ),
          ),
          Expanded(
            flex: 16,
            child: _KqDesignerDevicesHeaderText(
              _kqHomeText('状态', 'Status'),
            ),
          ),
          const SizedBox(width: 74),
        ],
      ),
    );
  }
}

class _KqDesignerDevicesTableRow extends StatelessWidget {
  final Peer peer;
  final VoidCallback onConnect;

  const _KqDesignerDevicesTableRow({
    required this.peer,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              flex: 34,
              child: Row(
                children: [
                  _KqDesignerDevicePlatformIcon(peer: peer, size: 25),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _kqDesignerDeviceName(peer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kqDesignerPrimaryTextColor(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 24,
              child: Text(
                _kqDesignerPeerId(peer),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KqTheme.of(context).isDark
                      ? _kqDesignerSecondaryTextColor(context)
                      : const Color(0xFF667894),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Expanded(
              flex: 18,
              child: Text(
                _kqDesignerDeviceSystem(peer),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KqTheme.of(context).isDark
                      ? _kqDesignerSecondaryTextColor(context)
                      : const Color(0xFF6E7F98),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Expanded(
              flex: 16,
              child: _KqDesignerDeviceStatus(peer: peer),
            ),
            SizedBox(
              width: 74,
              child: Align(
                alignment: Alignment.centerRight,
                child: _KqDesignerDevicesConnectButton(onPressed: onConnect),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KqDesignerDevicesHeaderText extends StatelessWidget {
  final String text;

  const _KqDesignerDevicesHeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: KqTheme.of(context).isDark
            ? KqTheme.of(context).primaryDeep
            : const Color(0xFF0072B8),
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _KqDesignerDevicePlatformIcon extends StatelessWidget {
  final Peer peer;
  final double size;

  const _KqDesignerDevicePlatformIcon({
    required this.peer,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _kqDesignerDeviceIcon(peer);
    final q = KqTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _kqDesignerInfoSurfaceColor(context),
        borderRadius: BorderRadius.circular(size >= 30 ? 6 : 4),
      ),
      child: Icon(
        icon,
        size: size >= 30 ? 21 : 17,
        color: q.isDark ? q.primaryDeep : const Color(0xFF2874F0),
      ),
    );
  }
}

class _KqDesignerDeviceStatus extends StatelessWidget {
  final Peer peer;

  const _KqDesignerDeviceStatus({required this.peer});

  @override
  Widget build(BuildContext context) {
    final known = peer.onlineStateKnown;
    final online = peer.online;
    final color = !known
        ? const Color(0xFF94A3B8)
        : online
            ? const Color(0xFF16C784)
            : const Color(0xFFA8B2C0);
    final label = !known
        ? _kqHomeText('检测中', 'Checking')
        : (online ? _kqHomeText('在线', 'Online') : _kqHomeText('离线', 'Offline'));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _KqDesignerDevicesConnectButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _KqDesignerDevicesConnectButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return SizedBox(
      width: 54,
      height: 30,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: q.isDark ? q.primaryDeep : const Color(0xFF1E73F8),
          backgroundColor: q.isDark
              ? q.surfaceSoft.withOpacity(0.54)
              : const Color(0xFFF2F7FF),
          side: BorderSide(
            color:
                q.isDark ? q.line.withOpacity(0.86) : const Color(0xFFCFE0FF),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        child: Text(translate('Connect')),
      ),
    );
  }
}

class _KqDesignerDevicesEmptyState extends StatelessWidget {
  final bool compact;

  const _KqDesignerDevicesEmptyState({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: compact
          ? BoxDecoration(
              color: _kqDesignerPanelColor(context),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _kqDesignerPanelBorder(context)),
            )
          : null,
      child: Text(
        _kqHomeText('暂无设备记录', 'No device records'),
        style: TextStyle(
          color: _kqDesignerSecondaryTextColor(context).withOpacity(0.86),
          fontSize: compact ? 13 : 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

String _kqDesignerDeviceName(Peer peer) {
  final alias = peer.alias.trim();
  if (alias.isNotEmpty) return alias;
  final hostname = peer.hostname.trim();
  if (hostname.isNotEmpty) return hostname;
  final username = peer.username.trim();
  if (username.isNotEmpty) return username;
  final id = kqNormalizePeerId(peer.id);
  return id.isEmpty ? _kqHomeText('未知设备', 'Unknown device') : id;
}

String _kqDesignerPeerId(Peer peer) {
  final id = kqNormalizePeerId(peer.id);
  if (id.length <= 3) return id.isEmpty ? '--' : id;
  final chunks = <String>[];
  for (var i = 0; i < id.length; i += 3) {
    final end = i + 3 > id.length ? id.length : i + 3;
    chunks.add(id.substring(i, end));
  }
  return chunks.join(' ');
}

String _kqDesignerDeviceSystem(Peer peer) {
  final platform = peer.platform.trim().toLowerCase();
  if (platform == kPeerPlatformWindows.toLowerCase() ||
      platform.contains('windows')) {
    return 'Windows';
  }
  if (platform == kPeerPlatformMacOS.toLowerCase() ||
      platform.contains('mac')) {
    return 'macOS';
  }
  if (platform == kPeerPlatformLinux.toLowerCase() ||
      platform.contains('linux')) {
    return 'Linux';
  }
  if (platform == kPeerPlatformAndroid.toLowerCase() ||
      platform.contains('android')) {
    return 'Android';
  }
  if (platform == kPeerPlatformIOS.toLowerCase() ||
      platform.contains('ios') ||
      platform.contains('iphone') ||
      platform.contains('ipad')) {
    return 'iOS';
  }
  return platform.isEmpty ? '--' : peer.platform;
}

IconData _kqDesignerDeviceIcon(Peer peer) {
  final platform = peer.platform.trim().toLowerCase();
  if (platform == kPeerPlatformWindows.toLowerCase() ||
      platform.contains('windows')) {
    return Icons.window_rounded;
  }
  if (platform == kPeerPlatformMacOS.toLowerCase() ||
      platform.contains('mac')) {
    return Icons.apple;
  }
  if (platform == kPeerPlatformLinux.toLowerCase() ||
      platform.contains('linux')) {
    return Icons.rocket_launch_rounded;
  }
  if (platform == kPeerPlatformAndroid.toLowerCase() ||
      platform.contains('android')) {
    return Icons.android_rounded;
  }
  if (platform == kPeerPlatformIOS.toLowerCase() ||
      platform.contains('ios') ||
      platform.contains('iphone') ||
      platform.contains('ipad')) {
    return Icons.phone_iphone_rounded;
  }
  return Icons.devices_rounded;
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
