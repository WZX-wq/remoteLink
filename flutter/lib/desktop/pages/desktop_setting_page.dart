import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/common/kq_network_risk.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/printer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/plugin/manager.dart';
import 'package:flutter_hbb/plugin/widgets/desktop_settings.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';

const double _kTabWidth = 236;
const double _kTabHeight = 42;
const double _kCardFixedWidth = 540;
const double _kCardLeftMargin = 24;
const double _kContentHMargin = 15;
const double _kContentHSubMargin = _kContentHMargin + 33;
const double _kCheckBoxLeftMargin = 10;
const double _kRadioLeftMargin = 10;
const double _kListViewBottomMargin = 15;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _accentColor = MyTheme.accent;
const String _kSettingPageControllerTag = 'settingPageController';
const String _kSettingPageTabKeyTag = 'settingPageTabKey';
const Color _kqDesignerBlue = Color(0xFF2563EB);
const Color _kqDesignerBlueSoft = Color(0xFFEFF6FF);
const Color _kqDesignerCardBorder = Color(0xFFE4E8EE);
const Color _kqDesignerTextPrimary = Color(0xFF1A2332);
const Color _kqDesignerTextSecondary = Color(0xFF6B7A8D);

Color _settingsDesignerTextPrimary(BuildContext context) =>
    _settingPalette(context).primaryText;

Color _settingsDesignerTextSecondary(BuildContext context) =>
    _settingPalette(context).mutedText;

Color _settingsDesignerCardBorder(BuildContext context) =>
    _settingPalette(context).cardBorder;

Color _settingsDesignerSoftSurface(BuildContext context) {
  final palette = _settingPalette(context);
  return Theme.of(context).brightness == Brightness.dark
      ? palette.fieldFill
      : const Color(0xFFF8FAFD);
}

Color _settingsDesignerInfoSurface(BuildContext context) {
  final palette = _settingPalette(context);
  return Theme.of(context).brightness == Brightness.dark
      ? palette.cardHeaderBackground
      : const Color(0xFFF5F8FD);
}

Color _settingsDesignerBlueSurface(BuildContext context) {
  final palette = _settingPalette(context);
  return Theme.of(context).brightness == Brightness.dark
      ? palette.navSelectedBackground
      : _kqDesignerBlueSoft;
}

String _kqSettingText(String zhCn, String en) {
  // kq-v233-desktop-account-locale-text
  return kqLocaleText(zhCn: zhCn, en: en);
}

class _TabInfo {
  late final SettingsTabKey key;
  late final String label;
  late final IconData unselected;
  late final IconData selected;
  _TabInfo(this.key, this.label, this.unselected, this.selected);
}

class _SettingPalette {
  final Color pageBackground;
  final Color contentBackground;
  final Color sidebarBackground;
  final Color sidebarBorder;
  final Color navText;
  final Color navIcon;
  final Color navSelectedText;
  final Color navSelectedBackground;
  final Color navHoverBackground;
  final Color cardBackground;
  final Color cardBorder;
  final Color cardHeaderBackground;
  final Color fieldFill;
  final Color fieldBorder;
  final Color primaryText;
  final Color mutedText;
  final Color disabledText;
  final Color shadow;

  const _SettingPalette({
    required this.pageBackground,
    required this.contentBackground,
    required this.sidebarBackground,
    required this.sidebarBorder,
    required this.navText,
    required this.navIcon,
    required this.navSelectedText,
    required this.navSelectedBackground,
    required this.navHoverBackground,
    required this.cardBackground,
    required this.cardBorder,
    required this.cardHeaderBackground,
    required this.fieldFill,
    required this.fieldBorder,
    required this.primaryText,
    required this.mutedText,
    required this.disabledText,
    required this.shadow,
  });
}

_SettingPalette _settingPalette(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return const _SettingPalette(
      pageBackground: Color(0xFF0D1824),
      contentBackground: Color(0xFF102235),
      sidebarBackground: Color(0xFF12283B),
      sidebarBorder: Color(0xFF284C67),
      navText: Color(0xFFB7CFE4),
      navIcon: Color(0xFF8FB6D5),
      navSelectedText: Color(0xFFEAF7FF),
      navSelectedBackground: Color(0xFF17466D),
      navHoverBackground: Color(0xFF17354F),
      cardBackground: Color(0xFF172B3F),
      cardBorder: Color(0xFF315C7C),
      cardHeaderBackground: Color(0xFF1A354D),
      fieldFill: Color(0xFF102338),
      fieldBorder: Color(0xFF3D6888),
      primaryText: Color(0xFFEAF7FF),
      mutedText: Color(0xFFA9C3D8),
      disabledText: Color(0xFF7894AA),
      shadow: Color(0x33000000),
    );
  }
  return const _SettingPalette(
    pageBackground: Colors.white,
    contentBackground: Colors.white,
    sidebarBackground: Colors.white,
    sidebarBorder: Color(0xFFE8ECF2),
    navText: Color(0xFF5D6572),
    navIcon: Color(0xFF8A929D),
    navSelectedText: Color(0xFF26384D),
    navSelectedBackground: Color(0xFFEAF1FF),
    navHoverBackground: Color(0xFFF3F7FF),
    cardBackground: Colors.white,
    cardBorder: Color(0xFFE5EAF1),
    cardHeaderBackground: Colors.white,
    fieldFill: Color(0xFFFFFFFF),
    fieldBorder: Color(0xFFD7DEE8),
    primaryText: Color(0xFF222832),
    mutedText: Color(0xFF7B8490),
    disabledText: Color(0xFFA7AFBA),
    shadow: Color(0x00000000),
  );
}

ThemeData _settingTheme(BuildContext context, _SettingPalette palette) {
  final base = Theme.of(context);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: palette.fieldBorder),
  );
  final activeControlColor = WidgetStateProperty.resolveWith<Color?>(
    (states) {
      if (states.contains(WidgetState.disabled)) {
        return palette.disabledText.withOpacity(0.45);
      }
      if (states.contains(WidgetState.selected)) {
        return _accentColor;
      }
      return palette.fieldFill;
    },
  );
  return base.copyWith(
    cardColor: palette.cardBackground,
    scaffoldBackgroundColor: palette.contentBackground,
    hoverColor: palette.navHoverBackground,
    textTheme: base.textTheme.apply(
      bodyColor: palette.primaryText,
      displayColor: palette.primaryText,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: palette.fieldFill,
      isDense: true,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: _accentColor, width: 1.4),
      ),
      disabledBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: palette.fieldBorder.withOpacity(0.55)),
      ),
    ),
    checkboxTheme: base.checkboxTheme.copyWith(
      fillColor: activeControlColor,
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: palette.fieldBorder, width: 1.2),
    ),
    radioTheme: base.radioTheme.copyWith(
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.disabledText.withOpacity(0.6);
          }
          return _accentColor;
        },
      ),
    ),
  );
}

enum SettingsTabKey {
  general,
  safety,
  network,
  display,
  plugin,
  about,
}

class DesktopSettingPage extends StatefulWidget {
  final SettingsTabKey initialTabkey;
  final bool embedded;
  static final List<SettingsTabKey> tabKeys = [
    SettingsTabKey.general,
    if (!isWeb &&
        !bind.isOutgoingOnly() &&
        !bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      SettingsTabKey.safety,
    if (!bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) != 'Y')
      SettingsTabKey.network,
    if (!bind.isIncomingOnly()) SettingsTabKey.display,
    if (!isWeb && !bind.isIncomingOnly() && bind.pluginFeatureIsEnabled())
      SettingsTabKey.plugin,
    SettingsTabKey.about,
  ];

  DesktopSettingPage({
    Key? key,
    required this.initialTabkey,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<DesktopSettingPage> createState() =>
      _DesktopSettingPageState(initialTabkey, registerNavigation: !embedded);

  static void switch2page(SettingsTabKey page) {
    try {
      int index = tabKeys.indexOf(page);
      if (index == -1) {
        return;
      }
      if (Get.isRegistered<PageController>(tag: _kSettingPageControllerTag)) {
        DesktopTabPage.onAddSetting(initialPage: page);
        PageController controller =
            Get.find<PageController>(tag: _kSettingPageControllerTag);
        Rx<SettingsTabKey> selected =
            Get.find<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
        selected.value = page;
        controller.jumpToPage(index);
      } else {
        DesktopTabPage.onAddSetting(initialPage: page);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopSettingPageState extends State<DesktopSettingPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late PageController controller;
  late Rx<SettingsTabKey> selectedTab;
  final bool registerNavigation;

  @override
  bool get wantKeepAlive => true;

  final RxBool _block = false.obs;
  final RxBool _canBeBlocked = false.obs;
  Timer? _videoConnTimer;
  bool _syncingMemberEntitlement = false;
  DateTime? _lastMemberEntitlementSyncAt;

  _DesktopSettingPageState(
    SettingsTabKey initialTabkey, {
    required this.registerNavigation,
  }) {
    var initialIndex = DesktopSettingPage.tabKeys.indexOf(initialTabkey);
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    selectedTab = DesktopSettingPage.tabKeys[initialIndex].obs;
    controller = PageController(initialPage: initialIndex);
    if (registerNavigation) {
      Get.put<Rx<SettingsTabKey>>(selectedTab, tag: _kSettingPageTabKeyTag);
      Get.put<PageController>(controller, tag: _kSettingPageControllerTag);
    }
    controller.addListener(() {
      if (controller.page != null) {
        int page = controller.page!.toInt();
        if (page < DesktopSettingPage.tabKeys.length) {
          selectedTab.value = DesktopSettingPage.tabKeys[page];
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
      unawaited(_syncMemberEntitlementFromDisk(force: true));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncMemberEntitlementFromDisk(force: true));
    _videoConnTimer =
        periodic_immediate(Duration(milliseconds: 1000), () async {
      if (!mounted) {
        return;
      }
      _canBeBlocked.value = await canBeBlocked();
    });
  }

  @override
  void dispose() {
    super.dispose();
    if (registerNavigation) {
      Get.delete<PageController>(tag: _kSettingPageControllerTag);
      Get.delete<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
    }
    WidgetsBinding.instance.removeObserver(this);
    _videoConnTimer?.cancel();
  }

  Future<void> _syncMemberEntitlementFromDisk({bool force = false}) async {
    if (_syncingMemberEntitlement) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastMemberEntitlementSyncAt != null &&
        now.difference(_lastMemberEntitlementSyncAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastMemberEntitlementSyncAt = now;
    _syncingMemberEntitlement = true;
    try {
      final changed = await gFFI.userModel.syncMemberEntitlementFromDisk();
      if (changed && mounted) {
        setState(() {});
      }
    } finally {
      _syncingMemberEntitlement = false;
    }
  }

  List<_TabInfo> _settingTabs() {
    final List<_TabInfo> settingTabs = <_TabInfo>[];
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          settingTabs.add(_TabInfo(
              tab, 'General', Icons.settings_outlined, Icons.settings));
          break;
        case SettingsTabKey.safety:
          settingTabs.add(_TabInfo(tab, 'Security',
              Icons.enhanced_encryption_outlined, Icons.enhanced_encryption));
          break;
        case SettingsTabKey.network:
          settingTabs
              .add(_TabInfo(tab, 'Network', Icons.link_outlined, Icons.link));
          break;
        case SettingsTabKey.display:
          settingTabs.add(_TabInfo(tab, 'Display',
              Icons.desktop_windows_outlined, Icons.desktop_windows));
          break;
        case SettingsTabKey.plugin:
          settingTabs.add(_TabInfo(
              tab, 'Plugin', Icons.extension_outlined, Icons.extension));
          break;
        case SettingsTabKey.about:
          settingTabs
              .add(_TabInfo(tab, 'About', Icons.info_outline, Icons.info));
          break;
      }
    }
    return settingTabs;
  }

  List<Widget> _children() {
    final children = List<Widget>.empty(growable: true);
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          children.add(const _General());
          break;
        case SettingsTabKey.safety:
          children.add(const _Safety());
          break;
        case SettingsTabKey.network:
          children.add(const _Network());
          break;
        case SettingsTabKey.display:
          children.add(const _Display());
          break;
        case SettingsTabKey.plugin:
          children.add(const _Plugin());
          break;
        case SettingsTabKey.about:
          children.add(const _About());
          break;
      }
    }
    return children;
  }

  Widget _buildBlock({required List<Widget> children}) {
    // check both mouseMoveTime and videoConnCount
    return Obx(() {
      final videoConnBlock =
          _canBeBlocked.value && stateGlobal.videoConnCount > 0;
      return Stack(children: [
        buildRemoteBlock(
          block: _block,
          mask: false,
          use: canBeBlocked,
          child: preventMouseKeyBuilder(
            child: Row(children: children),
            block: videoConnBlock,
          ),
        ),
        if (videoConnBlock)
          Container(
            color: Colors.black.withOpacity(0.5),
          )
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = _settingPalette(context);
    final useDesignerSettingsTabs = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerSettingsTabs) {
      final content = _buildBlock(
        children: <Widget>[
          Expanded(
            child: Container(
              // kq-settings-reference-layout
              color: palette.contentBackground,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDesignerSettingsTabs(tabs: _settingTabs()),
                  Expanded(
                    child: Container(
                      color: palette.contentBackground,
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                      child: PageView(
                        controller: controller,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _children(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      return Theme(
        data: _settingTheme(context, palette),
        child: widget.embedded
            ? Material(color: palette.pageBackground, child: content)
            : Scaffold(
                backgroundColor: palette.pageBackground,
                body: content,
              ),
      );
    }
    final content = _buildBlock(
      children: <Widget>[
        Container(
          // kq-settings-reference-layout
          width: _kTabWidth,
          decoration: BoxDecoration(
            color: palette.sidebarBackground,
            border: Border(
              right: BorderSide(color: palette.sidebarBorder),
            ),
          ),
          child: Column(
            children: [
              _header(context),
              Flexible(child: _listView(tabs: _settingTabs())),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: palette.contentBackground,
            ),
            child: PageView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              children: _children(),
            ),
          ),
        )
      ],
    );
    return Theme(
      data: _settingTheme(context, palette),
      child: widget.embedded
          ? Material(color: palette.pageBackground, child: content)
          : Scaffold(
              backgroundColor: palette.pageBackground,
              body: content,
            ),
    );
  }

  Widget _buildDesignerSettingsTabs({required List<_TabInfo> tabs}) {
    return Obx(() {
      final palette = _settingPalette(context);
      return Container(
        // kq-designer-settings-tabs
        // kq-v218-settings-reference-tabs
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: palette.cardHeaderBackground,
          border: Border(bottom: BorderSide(color: palette.cardBorder)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: tabs
                .map((tab) => _buildDesignerSettingsTab(
                      tab: tab,
                      selected: tab.key == selectedTab.value,
                    ))
                .toList(),
          ),
        ),
      );
    });
  }

  Widget _buildDesignerSettingsTab({
    required _TabInfo tab,
    required bool selected,
  }) {
    final palette = _settingPalette(context);
    final iconColor = selected ? _kqDesignerBlue : palette.mutedText;
    final selectedBackground = Theme.of(context).brightness == Brightness.dark
        ? palette.navSelectedBackground
        : _kqDesignerBlueSoft;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Material(
        color: selected ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: palette.navHoverBackground,
          onTap: () {
            final index = DesktopSettingPage.tabKeys.indexOf(tab.key);
            if (index == -1) {
              return;
            }
            if (selectedTab.value != tab.key) {
              controller.jumpToPage(index);
            }
            selectedTab.value = tab.key;
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? _kqDesignerBlue : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? tab.selected : tab.unselected,
                  color: iconColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  translate(tab.label),
                  style: TextStyle(
                    color: selected ? _kqDesignerBlue : palette.mutedText,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = _settingPalette(context);
    final settingsText = Text(
      translate('Settings'),
      textAlign: TextAlign.left,
      style: TextStyle(
        color: palette.navSelectedText,
        fontSize: _kTitleFontSize,
        fontWeight: FontWeight.w700,
      ),
    );
    return Row(
      children: [
        if (isWeb)
          IconButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            icon: Icon(Icons.arrow_back),
          ).marginOnly(left: 5),
        if (isWeb)
          SizedBox(
            height: 62,
            child: Align(
              alignment: Alignment.center,
              child: settingsText,
            ),
          ).marginOnly(left: 20),
        if (!isWeb)
          SizedBox(
            height: 62,
            child: settingsText,
          ).marginOnly(left: 20, top: 10),
        const Spacer(),
      ],
    );
  }

  Widget _listView({required List<_TabInfo> tabs}) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      children: tabs.map((tab) => _listItem(tab: tab)).toList(),
    );
  }

  Widget _listItem({required _TabInfo tab}) {
    return Obx(() {
      bool selected = tab.key == selectedTab.value;
      final palette = _settingPalette(context);
      final textColor = selected ? palette.navSelectedText : palette.navText;
      final iconColor = selected ? _accentColor : palette.navIcon;
      return Padding(
        // kq-settings-reference-nav-item
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: SizedBox(
          width: _kTabWidth - 16,
          height: _kTabHeight,
          child: Material(
            color:
                selected ? palette.navSelectedBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: palette.navHoverBackground,
              onTap: () {
                if (selectedTab.value != tab.key) {
                  int index = DesktopSettingPage.tabKeys.indexOf(tab.key);
                  if (index == -1) {
                    return;
                  }
                  controller.jumpToPage(index);
                }
                selectedTab.value = tab.key;
              },
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(
                  selected ? tab.selected : tab.unselected,
                  color: iconColor,
                  size: 20,
                ).marginOnly(right: 10),
                Text(
                  translate(tab.label),
                  style: TextStyle(
                      color: textColor,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: _kContentFontSize),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

class DesktopAccountPage extends StatelessWidget {
  final bool embedded;

  const DesktopAccountPage({
    Key? key,
    this.embedded = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final palette = _settingPalette(context);
    const content = _Account();
    return Theme(
      data: _settingTheme(context, palette),
      child: embedded
          ? Material(color: palette.contentBackground, child: content)
          : Scaffold(
              backgroundColor: palette.pageBackground,
              body: content,
            ),
    );
  }
}

class _SettingsReferencePage extends StatelessWidget {
  final String marker;
  final List<Widget> children;

  const _SettingsReferencePage({
    required this.marker,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 828),
          child: Column(
            // The marker is intentionally kept in the widget tree for release
            // checks while staying invisible to the user.
            key: ValueKey<String>(marker),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _SettingsReferenceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final EdgeInsets padding;

  const _SettingsReferenceCard({
    required this.icon,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
  });

  @override
  Widget build(BuildContext context) {
    final palette = _settingPalette(context);
    return Container(
      // kq-v218-settings-reference-card
      // kq-v227-settings-dark-reference-card-colors
      margin: const EdgeInsets.only(bottom: 9),
      padding: padding,
      decoration: BoxDecoration(
        color: palette.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: _kqDesignerBlue),
              const SizedBox(width: 7),
              Text(
                translate(title),
                style: TextStyle(
                  color: palette.primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SettingsReferenceControlRow extends StatelessWidget {
  final String label;
  final Widget control;
  final String? helper;

  const _SettingsReferenceControlRow({
    required this.label,
    required this.control,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _settingPalette(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              translate(label),
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(child: control),
          if (helper != null) ...[
            const SizedBox(width: 10),
            Text(
              translate(helper!),
              style: TextStyle(color: palette.mutedText, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsReferenceCheckGrid extends StatelessWidget {
  final List<Widget> children;

  const _SettingsReferenceCheckGrid({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 10.0;
      final columns = constraints.maxWidth >= 520 ? 2 : 1;
      final itemWidth = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - gap) / columns;
      return Wrap(
        // kq-v218-settings-two-column-checks
        spacing: gap,
        runSpacing: 2,
        children: children
            .map((child) => SizedBox(width: itemWidth, child: child))
            .toList(),
      );
    });
  }
}

class _SettingsStaticCheck extends StatelessWidget {
  final String label;
  final bool checked;
  final bool enabled;

  const _SettingsStaticCheck({
    required this.label,
    this.checked = true,
    this.enabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _settingPalette(context);
    return Padding(
      padding: const EdgeInsets.only(left: _kCheckBoxLeftMargin),
      child: Row(
        children: [
          Checkbox(value: checked, onChanged: enabled ? (_) {} : null)
              .marginOnly(right: 6),
          Expanded(
            child: Text(
              translate(label),
              style: TextStyle(
                color: enabled ? palette.primaryText : palette.disabledText,
                fontSize: _kContentFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _settingsReferenceDivider() {
  return Builder(builder: (context) {
    final palette = _settingPalette(context);
    // kq-v227-settings-dark-reference-divider
    return Divider(height: 18, color: palette.cardBorder);
  });
}

Widget _settingsChoicePill(
  BuildContext context, {
  required String label,
  required bool selected,
  required bool enabled,
  required VoidCallback onTap,
  IconData? icon,
  bool pro = false,
}) {
  final palette = _settingPalette(context);
  final foreground = selected
      ? Colors.white
      : enabled
          ? palette.primaryText
          : palette.disabledText;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 35,
        constraints: const BoxConstraints(minWidth: 62),
        padding:
            EdgeInsets.fromLTRB(icon == null ? 15 : 12, 0, pro ? 10 : 15, 0),
        decoration: BoxDecoration(
          // kq-v227-settings-choice-pill-theme-colors
          color: selected ? _kqDesignerBlue : palette.fieldFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _kqDesignerBlue : palette.fieldBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              translate(label),
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            if (pro) ...[
              const SizedBox(width: 8),
              const Text(
                'PRO',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _settingsLightButton({
  required IconData icon,
  required String label,
  required VoidCallback? onPressed,
  bool primary = false,
}) {
  final child = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16),
      const SizedBox(width: 6),
      Text(translate(label)),
    ],
  );
  return primary
      ? FilledButton(onPressed: onPressed, child: child)
      : OutlinedButton(onPressed: onPressed, child: child);
}

//#region pages

class _General extends StatefulWidget {
  const _General({Key? key}) : super(key: key);

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> {
  @override
  Widget build(BuildContext context) {
    return _SettingsReferencePage(
      marker: 'kq-v218-settings-common-page',
      children: [
        _themeReferenceCard(context),
        _languageReferenceCard(context),
        if (!isWeb && !bind.isOutgoingOnly()) _audioReferenceCard(context),
        if (!isWeb) _recordReferenceCard(context),
        _otherReferenceCard(context),
      ],
    );
  }

  Widget _themeReferenceCard(BuildContext context) {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return _SettingsReferenceCard(
      icon: Icons.light_mode_outlined,
      title: 'Theme',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _settingsChoicePill(
            context,
            label: 'Light',
            selected: current == 'light',
            enabled: !isOptFixed,
            onTap: () => onChanged('light'),
          ),
          _settingsChoicePill(
            context,
            label: 'Dark',
            selected: current == 'dark',
            enabled: !isOptFixed,
            onTap: () => onChanged('dark'),
          ),
          _settingsChoicePill(
            context,
            label: 'Follow System',
            selected: current == 'system',
            enabled: !isOptFixed,
            onTap: () => onChanged('system'),
          ),
        ],
      ),
    );
  }

  Widget _languageReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.language_rounded,
      title: 'Language',
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 220, child: _languageControl()),
      ),
    );
  }

  Widget _languageControl() {
    return futureBuilder(future: () async {
      String langs = await bind.mainGetLangs();
      return {'langs': langs};
    }(), hasData: (res) {
      Map<String, String> data = res as Map<String, String>;
      List<dynamic> langsList = jsonDecode(data['langs']!);
      Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
      List<String> keys = langsMap.keys.toList();
      List<String> values = langsMap.values.toList();
      keys.insert(0, defaultOptionLang);
      values.insert(0, translate('Default'));
      String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
      if (!keys.contains(currentKey)) {
        currentKey = defaultOptionLang;
      }
      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return ComboBox(
        keys: keys,
        values: values,
        initialKey: currentKey,
        onChanged: (key) async {
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
          if (!isWeb) await bind.mainChangeLanguage(lang: key);
          if (isWeb) reloadCurrentWindow();
          if (!isWeb) reloadAllWindows();
          setState(() {});
        },
        enabled: !isOptFixed,
      );
    });
  }

  Widget _audioReferenceCard(BuildContext context) {
    builder(devices, currentDevice, setDevice) {
      return _SettingsReferenceCard(
        icon: Icons.mic_none_rounded,
        title: 'Audio Input Device',
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 220,
            child: ComboBox(
              keys: devices,
              values: devices,
              initialKey: currentDevice,
              onChanged: (key) async {
                setDevice(key);
                setState(() {});
              },
            ),
          ),
        ),
      );
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  Widget _recordReferenceCard(BuildContext context) {
    final showRootDir = isWindows && bind.mainIsInstalled();
    return futureBuilder(future: () async {
      String customDir =
          bind.mainGetLocalOption(key: kOptionVideoSaveDirectory).trim();
      String userDir = bind.mainVideoSaveDirectory(root: false);
      String rootDir =
          showRootDir ? bind.mainVideoSaveDirectory(root: true) : '';
      bool userDirExists = await Directory(userDir).exists();
      bool rootDirExists =
          showRootDir ? await Directory(rootDir).exists() : false;
      return {
        'customDir': customDir,
        'userDir': userDir,
        'rootDir': rootDir,
        'userDirExists': userDirExists,
        'rootDirExists': rootDirExists,
      };
    }(), hasData: (data) {
      final map = data as Map<String, dynamic>;
      final userDir = map['userDir'] as String;
      final rootDir = map['rootDir'] as String;
      final rootDirExists = map['rootDirExists'] as bool;
      final userDirExists = map['userDirExists'] as bool;
      final editableDir =
          showRootDir && bind.isIncomingOnly() ? rootDir : userDir;
      final editableDirExists =
          showRootDir && bind.isIncomingOnly() ? rootDirExists : userDirExists;
      return _SettingsReferenceCard(
        icon: Icons.videocam_outlined,
        title: 'Recording',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsReferenceCheckGrid(
              children: [
                if (!bind.isOutgoingOnly())
                  _OptionCheckBox(
                      context,
                      'Automatically record incoming sessions',
                      kOptionAllowAutoRecordIncoming),
                if (!bind.isIncomingOnly())
                  _OptionCheckBox(
                      context,
                      'Automatically record outgoing sessions',
                      kOptionAllowAutoRecordOutgoing,
                      isServer: false),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: editableDirExists
                        ? () => launchUrl(Uri.file(editableDir))
                        : null,
                    child: Container(
                      height: 31,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _settingsDesignerInfoSurface(context),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _settingPalette(context).cardBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_outlined,
                              size: 16,
                              color: _settingPalette(context).mutedText),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              editableDir,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _settingPalette(context).mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: _settingsLightButton(
                    icon: Icons.edit_outlined,
                    label: 'Change',
                    onPressed: isOptionFixed(kOptionVideoSaveDirectory)
                        ? null
                        : () async {
                            String? initialDirectory;
                            final customDir = map['customDir'] as String;
                            final pickerDir =
                                customDir.isNotEmpty ? customDir : editableDir;
                            if (await Directory.fromUri(
                                    Uri.directory(pickerDir))
                                .exists()) {
                              initialDirectory = pickerDir;
                            } else if (await Directory.fromUri(
                                    Uri.directory(userDir))
                                .exists()) {
                              initialDirectory = userDir;
                            }
                            String? selectedDirectory =
                                await FilePicker.platform.getDirectoryPath(
                                    initialDirectory: initialDirectory);
                            if (selectedDirectory != null) {
                              await bind.mainSetLocalOption(
                                  key: kOptionVideoSaveDirectory,
                                  value: selectedDirectory);
                              await bind.mainSetOption(
                                  key: kOptionVideoSaveDirectory,
                                  value: selectedDirectory);
                              setState(() {});
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _otherReferenceCard(BuildContext context) {
    final showAutoUpdate = isWindows && bind.mainIsInstalled();
    return _SettingsReferenceCard(
      icon: Icons.more_horiz_rounded,
      title: 'Other',
      child: _SettingsReferenceCheckGrid(
        children: [
          if (!isWeb && !bind.isIncomingOnly())
            _OptionCheckBox(context, 'Confirm before closing multiple tabs',
                kOptionEnableConfirmClosingTabs,
                isServer: false),
          if (!isWeb && !bind.isIncomingOnly())
            _OptionCheckBox(
              context,
              'Open connection in new tab',
              kOptionOpenNewConnInTabs,
              isServer: false,
            ),
          if (!isWeb && !bind.isCustomClient())
            _OptionCheckBox(
              context,
              'Check for software update on startup',
              kOptionEnableCheckUpdate,
              isServer: false,
            ),
          if (showAutoUpdate)
            _OptionCheckBox(
              context,
              'Auto update',
              kOptionAllowAutoUpdate,
              isServer: true,
            ),
          if (!bind.isIncomingOnly())
            _OptionCheckBox(
              context,
              'keep-awake-during-outgoing-sessions-label',
              kOptionKeepAwakeDuringOutgoingSessions,
              isServer: false,
            ),
          if (!bind.isDisableAccount())
            _OptionCheckBox(
              context,
              'note-at-conn-end-tip',
              kOptionAllowAskForNoteAtEndOfConnection,
              isServer: false,
              optSetter: (key, value) async {
                if (value && !gFFI.userModel.isLogin) {
                  final res = await loginDialog();
                  if (res != true) return;
                }
                await mainSetLocalBoolOption(key, value);
              },
            ),
        ],
      ),
    );
  }

  Widget theme() {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return _Card(title: 'Theme', children: [
      _Radio<String>(context,
          value: 'light',
          groupValue: current,
          label: 'Light',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'dark',
          groupValue: current,
          label: 'Dark',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'system',
          groupValue: current,
          label: 'Follow System',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget other() {
    final showAutoUpdate = isWindows && bind.mainIsInstalled();
    final children = <Widget>[
      if (!isWeb && !bind.isIncomingOnly())
        _OptionCheckBox(context, 'Confirm before closing multiple tabs',
            kOptionEnableConfirmClosingTabs,
            isServer: false),
      _OptionCheckBox(context, 'Adaptive bitrate', kOptionEnableAbr),
      if (!isWeb) wallpaper(),
      if (!isWeb && !bind.isIncomingOnly()) ...[
        _OptionCheckBox(
          context,
          'Open connection in new tab',
          kOptionOpenNewConnInTabs,
          isServer: false,
        ),
        // though this is related to GUI, but opengl problem affects all users, so put in config rather than local
        if (isLinux)
          Tooltip(
            message: translate('software_render_tip'),
            child: _OptionCheckBox(
              context,
              "Always use software rendering",
              kOptionAllowAlwaysSoftwareRender,
            ),
          ),
        if (!isWeb)
          Tooltip(
            message: translate('texture_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use texture rendering",
              kOptionTextureRender,
              optGetter: bind.mainGetUseTextureRender,
              optSetter: (k, v) async =>
                  await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
            ),
          ),
        if (isWindows)
          Tooltip(
            message: translate('d3d_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use D3D rendering",
              kOptionD3DRender,
              isServer: false,
            ),
          ),
        if (!isWeb && !bind.isCustomClient())
          _OptionCheckBox(
            context,
            'Check for software update on startup',
            kOptionEnableCheckUpdate,
            isServer: false,
          ),
        if (showAutoUpdate)
          _OptionCheckBox(
            context,
            'Auto update',
            kOptionAllowAutoUpdate,
            isServer: true,
          ),
        if (isWindows && !bind.isOutgoingOnly())
          _OptionCheckBox(
            context,
            'Capture screen using DirectX',
            kOptionDirectxCapture,
          ),
        if (!bind.isIncomingOnly()) ...[
          _OptionCheckBox(
            context,
            'Enable UDP hole punching',
            kOptionEnableUdpPunch,
            isServer: false,
          ),
          _OptionCheckBox(
            context,
            'Enable IPv6 P2P connection',
            kOptionEnableIpv6Punch,
            isServer: false,
          ),
        ],
      ],
    ];

    // Add client-side wakelock option for desktop platforms
    if (!bind.isIncomingOnly()) {
      children.add(_OptionCheckBox(
        context,
        'keep-awake-during-outgoing-sessions-label',
        kOptionKeepAwakeDuringOutgoingSessions,
        isServer: false,
      ));
    }

    if (!isWeb && bind.mainShowOption(key: kOptionAllowLinuxHeadless)) {
      children.add(_OptionCheckBox(
          context, 'Allow linux headless', kOptionAllowLinuxHeadless));
    }
    if (!bind.isDisableAccount()) {
      children.add(_OptionCheckBox(
        context,
        'note-at-conn-end-tip',
        kOptionAllowAskForNoteAtEndOfConnection,
        isServer: false,
        optSetter: (key, value) async {
          if (value && !gFFI.userModel.isLogin) {
            final res = await loginDialog();
            if (res != true) return;
          }
          await mainSetLocalBoolOption(key, value);
        },
      ));
    }
    return _Card(title: 'Other', children: children);
  }

  Widget wallpaper() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    return futureBuilder(future: () async {
      final support = await bind.mainSupportRemoveWallpaper();
      return support;
    }(), hasData: (data) {
      if (data is bool && data == true) {
        bool value = mainGetBoolOptionSync(kOptionAllowRemoveWallpaper);
        return Row(
          children: [
            Flexible(
              child: _OptionCheckBox(
                context,
                'Remove wallpaper during incoming sessions',
                kOptionAllowRemoveWallpaper,
                update: (bool v) {
                  setState(() {});
                },
              ),
            ),
            if (value)
              _CountDownButton(
                text: 'Test',
                second: 5,
                onPressed: () {
                  bind.mainTestWallpaper(second: 5);
                },
              )
          ],
        );
      }

      return Offstage();
    });
  }

  Widget hwcodec() {
    final hwcodec = bind.mainHasHwcodec();
    final vram = bind.mainHasVram();
    return Offstage(
      offstage: !(hwcodec || vram),
      child: _Card(title: 'Hardware Codec', children: [
        _OptionCheckBox(
          context,
          'Enable hardware codec',
          kOptionEnableHwcodec,
          update: (bool v) {
            if (v) {
              bind.mainCheckHwcodec();
            }
          },
        )
      ]),
    );
  }

  Widget audio(BuildContext context) {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    builder(devices, currentDevice, setDevice) {
      final child = ComboBox(
        keys: devices,
        values: devices,
        initialKey: currentDevice,
        onChanged: (key) async {
          setDevice(key);
          setState(() {});
        },
      ).marginOnly(left: _kContentHMargin);
      return _Card(title: 'Audio Input Device', children: [child]);
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  Widget record(BuildContext context) {
    final showRootDir = isWindows && bind.mainIsInstalled();
    return futureBuilder(future: () async {
      String custom_dir =
          bind.mainGetLocalOption(key: kOptionVideoSaveDirectory).trim();
      String user_dir = bind.mainVideoSaveDirectory(root: false);
      String root_dir =
          showRootDir ? bind.mainVideoSaveDirectory(root: true) : '';
      bool user_dir_exists = await Directory(user_dir).exists();
      bool root_dir_exists =
          showRootDir ? await Directory(root_dir).exists() : false;
      return {
        'custom_dir': custom_dir,
        'user_dir': user_dir,
        'root_dir': root_dir,
        'user_dir_exists': user_dir_exists,
        'root_dir_exists': root_dir_exists,
      };
    }(), hasData: (data) {
      Map<String, dynamic> map = data as Map<String, dynamic>;
      String custom_dir = map['custom_dir']!;
      String user_dir = map['user_dir']!;
      String root_dir = map['root_dir']!;
      bool root_dir_exists = map['root_dir_exists']!;
      bool user_dir_exists = map['user_dir_exists']!;
      final editable_dir =
          showRootDir && bind.isIncomingOnly() ? root_dir : user_dir;
      final editable_dir_exists = showRootDir && bind.isIncomingOnly()
          ? root_dir_exists
          : user_dir_exists;
      return _Card(title: 'Recording', children: [
        if (!bind.isOutgoingOnly())
          _OptionCheckBox(context, 'Automatically record incoming sessions',
              kOptionAllowAutoRecordIncoming),
        if (!bind.isIncomingOnly())
          _OptionCheckBox(context, 'Automatically record outgoing sessions',
              kOptionAllowAutoRecordOutgoing,
              isServer: false),
        if (showRootDir && !bind.isOutgoingOnly() && !bind.isIncomingOnly())
          Row(
            children: [
              Text(
                  '${translate(bind.isIncomingOnly() ? "Directory" : "Incoming")}:'),
              Expanded(
                child: GestureDetector(
                    onTap: root_dir_exists
                        ? () => launchUrl(Uri.file(root_dir))
                        : null,
                    child: Text(
                      root_dir,
                      softWrap: true,
                      style: root_dir_exists
                          ? const TextStyle(
                              decoration: TextDecoration.underline)
                          : null,
                    )).marginOnly(left: 10),
              ),
            ],
          ).marginOnly(left: _kContentHMargin),
        Row(
          children: [
            Text(
                '${translate((showRootDir && !bind.isOutgoingOnly()) ? (bind.isIncomingOnly() ? "Directory" : "Outgoing") : "Directory")}:'),
            Expanded(
              child: GestureDetector(
                  onTap: editable_dir_exists
                      ? () => launchUrl(Uri.file(editable_dir))
                      : null,
                  child: Text(
                    editable_dir,
                    softWrap: true,
                    style: editable_dir_exists
                        ? const TextStyle(decoration: TextDecoration.underline)
                        : null,
                  )).marginOnly(left: 10),
            ),
            ElevatedButton(
                    onPressed: isOptionFixed(kOptionVideoSaveDirectory)
                        ? null
                        : () async {
                            String? initialDirectory;
                            final picker_dir = custom_dir.isNotEmpty
                                ? custom_dir
                                : editable_dir;
                            if (await Directory.fromUri(
                                    Uri.directory(picker_dir))
                                .exists()) {
                              initialDirectory = picker_dir;
                            } else if (await Directory.fromUri(
                                    Uri.directory(user_dir))
                                .exists()) {
                              initialDirectory = user_dir;
                            }
                            String? selectedDirectory =
                                await FilePicker.platform.getDirectoryPath(
                                    initialDirectory: initialDirectory);
                            if (selectedDirectory != null) {
                              await bind.mainSetLocalOption(
                                  key: kOptionVideoSaveDirectory,
                                  value: selectedDirectory);
                              await bind.mainSetOption(
                                  key: kOptionVideoSaveDirectory,
                                  value: selectedDirectory);
                              setState(() {});
                            }
                          },
                    child: Text(translate('Change')))
                .marginOnly(left: 5),
          ],
        ).marginOnly(left: _kContentHMargin),
      ]);
    });
  }

  Widget language() {
    return futureBuilder(future: () async {
      String langs = await bind.mainGetLangs();
      return {'langs': langs};
    }(), hasData: (res) {
      Map<String, String> data = res as Map<String, String>;
      List<dynamic> langsList = jsonDecode(data['langs']!);
      Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
      List<String> keys = langsMap.keys.toList();
      List<String> values = langsMap.values.toList();
      keys.insert(0, defaultOptionLang);
      values.insert(0, translate('Default'));
      String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
      if (!keys.contains(currentKey)) {
        currentKey = defaultOptionLang;
      }
      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return ComboBox(
        keys: keys,
        values: values,
        initialKey: currentKey,
        onChanged: (key) async {
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
          if (!isWeb) await bind.mainChangeLanguage(lang: key);
          if (isWeb) reloadCurrentWindow();
          if (!isWeb) reloadAllWindows();
          setState(() {});
        },
        enabled: !isOptFixed,
      ).marginOnly(left: _kContentHMargin);
    });
  }
}

enum _AccessMode {
  custom,
  full,
  view,
}

class _Safety extends StatefulWidget {
  const _Safety({Key? key}) : super(key: key);

  @override
  State<_Safety> createState() => _SafetyState();
}

class _SafetyState extends State<_Safety> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = bind.mainIsInstalled();
  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _accessPasswordReferenceCard(context),
        _verificationReferenceCard(context),
        _encryptionReferenceCard(context),
      ],
    );
    return _SettingsReferencePage(
      marker: 'kq-v218-settings-safety-page',
      children: [
        if (locked) _unlockReferenceCard(context, 'Unlock Security Settings'),
        AbsorbPointer(
          absorbing: locked,
          child: Opacity(opacity: locked ? 0.58 : 1, child: content),
        ),
      ],
    );
  }

  Widget _unlockReferenceCard(BuildContext context, String label) {
    return _SettingsReferenceCard(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Security',
      child: Row(
        children: [
          Expanded(
            child: Text(
              translate(label),
              style: TextStyle(
                color: _settingPalette(context).mutedText,
                fontSize: 13,
              ),
            ),
          ),
          _settingsLightButton(
            icon: Icons.lock_open_rounded,
            label: label,
            primary: true,
            onPressed: () async {
              final unlockPin = bind.mainGetUnlockPin();
              if (unlockPin.isEmpty || isUnlockPinDisabled()) {
                bool checked = await callMainCheckSuperUserPermission();
                if (checked) {
                  locked = false;
                  setState(() {});
                }
              } else {
                checkUnlockPinDialog(unlockPin, () {
                  locked = false;
                  setState(() {});
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _accessPasswordReferenceCard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, child) {
        final palette = _settingPalette(context);
        final requirePassword = model.approveMode != 'click';
        return _SettingsReferenceCard(
          icon: Icons.lock_outline_rounded,
          title: _kqSettingText('访问密码', 'Access password'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsReferenceControlRow(
                label: _kqSettingText('验证码类型', 'Verification code type'),
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<KqPasswordKind>(
                    tooltip: _kqSettingText(
                        '选择验证码类型', 'Choose verification code type'),
                    initialValue: model.selectedPasswordKind,
                    onSelected: model.setSelectedPasswordKind,
                    // kq-v227-settings-access-password-dark-colors
                    color: palette.cardBackground,
                    elevation: 8,
                    shadowColor: palette.shadow,
                    offset: const Offset(0, 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: palette.cardBorder),
                    ),
                    itemBuilder: (context) => KqPasswordKind.values
                        .map((kind) => PopupMenuItem<KqPasswordKind>(
                              value: kind,
                              height: 38,
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(
                                    _settingsPasswordKindLabel(kind),
                                    style: TextStyle(
                                      color: palette.primaryText,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )),
                                  if (kind == model.selectedPasswordKind)
                                    const Icon(Icons.check_rounded,
                                        size: 16, color: _kqDesignerBlue),
                                ],
                              ),
                            ))
                        .toList(),
                    child: Container(
                      height: 42,
                      width: 220,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: palette.fieldFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.fieldBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _settingsPasswordKindLabel(
                                  model.selectedPasswordKind),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.primaryText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(Icons.expand_more_rounded,
                              size: 18, color: palette.mutedText),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.fieldFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.fieldBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        model.selectedPasswordText,
                        maxLines: 1,
                        style: TextStyle(
                          color: palette.primaryText,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    _settingsIconAction(
                      tooltip: translate('Refresh Password'),
                      icon: Icons.refresh_rounded,
                      onTap: model.selectedPasswordCanRefresh
                          ? () => model.refreshSelectedPassword()
                          : null,
                    ),
                    _settingsIconAction(
                      tooltip: translate('Copy'),
                      icon: Icons.copy_rounded,
                      onTap: model.selectedPasswordCanCopy
                          ? () => _copySelectedPassword(model)
                          : null,
                    ),
                    _settingsIconAction(
                      tooltip: _kqSettingText('复制并分享', 'Copy and share'),
                      icon: Icons.ios_share_rounded,
                      onTap: model.selectedPasswordCanShare
                          ? () => _copyRemoteAssistShare(model)
                          : null,
                    ),
                    _settingsIconAction(
                      tooltip: translate('Change Password'),
                      icon: Icons.edit_rounded,
                      onTap: bind.isDisableSettings()
                          ? null
                          : () => _showKqPasswordDialog(model),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              _SettingsReferenceCheckGrid(
                children: [
                  _settingsInlineCheckbox(
                    context,
                    label: _kqSettingText(
                        '连接时需要输入密码', 'Require password when connecting'),
                    value: requirePassword,
                    enabled: !locked && !isOptionFixed(kOptionApproveMode),
                    onChanged: (value) async {
                      await bind.mainSetOption(
                        key: kOptionApproveMode,
                        value: value ? defaultOptionApproveMode : 'click',
                      );
                      await model.updatePasswordModel();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _verificationReferenceCard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, child) {
        return _SettingsReferenceCard(
          icon: Icons.shield_outlined,
          title: _kqSettingText('验证码策略', 'Verification policy'),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: ComboBox(
                keys: const [
                  kUseTemporaryPassword,
                  kUseBothPasswords,
                  kUsePermanentPassword,
                ],
                values: [
                  _kqSettingText(
                      '随机生成（每次刷新）', 'Randomly generated on each refresh'),
                  _kqSettingText(
                      '一次性与长期都可用', 'One-time and permanent both available'),
                  _kqSettingText('长期验证码', 'Permanent verification code'),
                ],
                initialKey: model.verificationMethod,
                enabled: !locked && !isOptionFixed(kOptionVerificationMethod),
                onChanged: (method) async {
                  await model.setVerificationMethod(method);
                  await model.updatePasswordModel();
                  setState(() {});
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _encryptionReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.enhanced_encryption_outlined,
      title: _kqSettingText('加密与锁定', 'Encryption and lock'),
      child: _SettingsReferenceCheckGrid(
        children: [
          _SettingsStaticCheck(
              label: _kqSettingText('端到端加密', 'End-to-end encryption'),
              checked: true),
          if (isWindows)
            _OptionCheckBox(
              context,
              'Enable blocking user input',
              kOptionEnableBlockInput,
              enabled: !locked,
            ),
          _OptionCheckBox(
            context,
            'Lock after session end',
            kOptionLockAfterSessionEnd,
            isServer: false,
            enabled: !locked,
          ),
          if (bind.mainSupportedPrivacyModeImpls() != '[]')
            _OptionCheckBox(
              context,
              'Privacy mode',
              kOptionPrivacyMode,
              isServer: false,
              enabled: !locked,
            ),
        ],
      ),
    );
  }

  Widget _settingsIconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Builder(builder: (context) {
      final palette = _settingPalette(context);
      return Tooltip(
        message: tooltip,
        child: IconButton(
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          icon: Icon(icon, size: 17),
          color: onTap == null ? palette.disabledText : _kqDesignerBlue,
          onPressed: onTap,
        ),
      );
    });
  }

  Widget _settingsInlineCheckbox(
    BuildContext context, {
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    final palette = _settingPalette(context);
    return Padding(
      padding: const EdgeInsets.only(left: _kCheckBoxLeftMargin),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: enabled ? palette.navHoverBackground : null,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              ).marginOnly(right: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? palette.primaryText : palette.disabledText,
                    fontSize: _kContentFontSize,
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copySelectedPassword(ServerModel model) {
    Clipboard.setData(ClipboardData(text: model.selectedPasswordText.trim()));
    showToast(translate("Copied"));
  }

  Future<void> _copyRemoteAssistShare(ServerModel model) async {
    final id = model.serverId.text.replaceAll(RegExp(r'\s+'), '').trim();
    final password = model.selectedPasswordText.trim();
    if (id.isEmpty || id == '--' || !model.selectedPasswordCanShare) {
      showToast(_kqSettingText(
          '设备号或验证码还未就绪', 'Device ID or verification code is not ready yet'));
      return;
    }
    final link = _buildKqInviteLink(id: id, password: password);
    final text = [
      _kqSettingText('使用 鲲穹远程桌面 即可对我发起远程协助',
          'Use Kunqiong Remote Desktop to start remote assistance with me'),
      '${_kqSettingText('设备ID', 'Device ID')}: ${formatID(id)}',
      '${_kqSettingText('设备验证码', 'Verification code')}: $password',
      '${_kqSettingText('点击链接可直接发起远程协助', 'Open the link to start remote assistance')}: $link',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    showToast(
        _kqSettingText('已复制远程协助分享信息', 'Remote assistance share info copied'));
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

  String _settingsPasswordKindLabel(KqPasswordKind kind) {
    switch (kind) {
      case KqPasswordKind.oneTime:
        return _kqSettingText('一次性验证码', 'One-time verification code');
      case KqPasswordKind.daily:
        return _kqSettingText('今日验证码', 'Today verification code');
      case KqPasswordKind.permanent:
        return _kqSettingText('长期验证码', 'Permanent verification code');
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
      final title = _settingsPasswordKindLabel(editingKind);
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
            errMsg =
                _kqSettingText('验证码不能为空', 'Verification code cannot be empty');
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
        showToast('${_kqSettingText('已更新', 'Updated')} $title');
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
        showToast('${_kqSettingText('已移除', 'Removed')} $title');
        close();
      }

      return CustomAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.key_rounded, color: MyTheme.accent),
            Text('${_kqSettingText('修改', 'Edit')} $title')
                .paddingOnly(left: 10),
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
                  _kqSettingText('长期验证码会同时更新远程连接使用的长期密码，并在本机可见。',
                      'The permanent verification code also updates the permanent password used for remote connections and remains visible on this device.'),
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

  Widget tfa() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool has2fa = bind.mainHasValid2FaSync().obs;
      RxBool hasBot = bind.mainHasValidBotSync().obs;
      update() async {
        has2fa.value = bind.mainHasValid2FaSync();
        setState(() {});
      }

      onChanged(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-2fa-confirm-tip'), () {
            change2fa(callback: update);
          });
        } else {
          change2fa(callback: update);
        }
      }

      final tfa = GestureDetector(
        child: InkWell(
          child: Obx(() => Row(
                children: [
                  Checkbox(
                          value: has2fa.value,
                          onChanged: enabled ? onChanged : null)
                      .marginOnly(right: 5),
                  Expanded(
                      child: Text(
                    translate('enable-2fa-title'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  ))
                ],
              )),
        ),
        onTap: () {
          onChanged(!has2fa.value);
        },
      ).marginOnly(left: _kCheckBoxLeftMargin);
      if (!has2fa.value) {
        return tfa;
      }
      updateBot() async {
        hasBot.value = bind.mainHasValidBotSync();
        setState(() {});
      }

      onChangedBot(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-bot-confirm-tip'), () {
            changeBot(callback: updateBot);
          });
        } else {
          changeBot(callback: updateBot);
        }
      }

      final bot = GestureDetector(
        child: Tooltip(
          waitDuration: Duration(milliseconds: 300),
          message: translate("enable-bot-tip"),
          child: InkWell(
              child: Obx(() => Row(
                    children: [
                      Checkbox(
                              value: hasBot.value,
                              onChanged: enabled ? onChangedBot : null)
                          .marginOnly(right: 5),
                      Expanded(
                          child: Text(
                        translate('Telegram bot'),
                        style: TextStyle(
                            color: disabledTextColor(context, enabled)),
                      ))
                    ],
                  ))),
        ),
        onTap: () {
          onChangedBot(!hasBot.value);
        },
      ).marginOnly(left: _kCheckBoxLeftMargin + 30);

      final trust = Row(
        children: [
          Flexible(
            child: Tooltip(
              waitDuration: Duration(milliseconds: 300),
              message: translate("enable-trusted-devices-tip"),
              child: _OptionCheckBox(context, "Enable trusted devices",
                  kOptionEnableTrustedDevices,
                  enabled: !locked, update: (v) {
                setState(() {});
              }),
            ),
          ),
          if (mainGetBoolOptionSync(kOptionEnableTrustedDevices))
            ElevatedButton(
                onPressed: locked
                    ? null
                    : () {
                        manageTrustedDeviceDialog();
                      },
                child: Text(translate('Manage trusted devices')))
        ],
      ).marginOnly(left: 30);

      return Column(
        children: [tfa, bot, trust],
      );
    }

    return tmpWrapper();
  }

  Widget changeId() {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          return _Button('Change ID', changeIdDialog,
              enabled: !locked && model.connectStatus > 0);
        })));
  }

  Widget permissions(context) {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      String accessMode = bind.mainGetOptionSync(key: kOptionAccessMode);
      _AccessMode mode;
      if (accessMode == 'full') {
        mode = _AccessMode.full;
      } else if (accessMode == 'view') {
        mode = _AccessMode.view;
      } else {
        mode = _AccessMode.custom;
      }
      String initialKey;
      bool? fakeValue;
      switch (mode) {
        case _AccessMode.custom:
          initialKey = '';
          fakeValue = null;
          break;
        case _AccessMode.full:
          initialKey = 'full';
          fakeValue = true;
          break;
        case _AccessMode.view:
          initialKey = 'view';
          fakeValue = false;
          break;
      }

      return _FoldoutCard(
          title: 'Permissions',
          initiallyExpanded: true,
          children: [
            ComboBox(
                keys: [
                  defaultOptionAccessMode,
                  'full',
                  'view',
                ],
                values: [
                  translate('Custom'),
                  translate('Full Access'),
                  translate('Screen Share'),
                ],
                enabled: enabled && !isOptionFixed(kOptionAccessMode),
                initialKey: initialKey,
                onChanged: (mode) async {
                  await bind.mainSetOption(key: kOptionAccessMode, value: mode);
                  setState(() {});
                }).marginOnly(left: _kContentHMargin),
            _SettingSectionTitle(context, 'Control Remote Desktop'),
            Column(
              children: [
                _OptionCheckBox(
                    context, 'Enable keyboard/mouse', kOptionEnableKeyboard,
                    enabled: enabled, fakeValue: fakeValue),
                if (isWindows)
                  _OptionCheckBox(context, 'Enable remote printer',
                      kOptionEnableRemotePrinter,
                      enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(
                    context, 'Enable clipboard', kOptionEnableClipboard,
                    enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(
                    context, 'Enable file transfer', kOptionEnableFileTransfer,
                    enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(context, 'Enable audio', kOptionEnableAudio,
                    enabled: enabled, fakeValue: fakeValue),
                _SettingSectionDivider(context),
                _SettingSectionTitle(context, 'Other'),
                _OptionCheckBox(
                    context, 'Enable terminal', kOptionEnableTerminal,
                    enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(
                    context, 'Enable TCP tunneling', kOptionEnableTunnel,
                    enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(context, 'Enable remote restart',
                    kOptionEnableRemoteRestart,
                    enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(context, 'Enable recording session',
                    kOptionEnableRecordSession,
                    enabled: enabled, fakeValue: fakeValue),
                if (isWindows)
                  _OptionCheckBox(context, 'Enable blocking user input',
                      kOptionEnableBlockInput,
                      enabled: enabled, fakeValue: fakeValue),
                if (bind.mainSupportedPrivacyModeImpls() != '[]')
                  _OptionCheckBox(
                      context, 'Enable privacy mode', kOptionEnablePrivacyMode,
                      enabled: enabled, fakeValue: fakeValue),
                _OptionCheckBox(
                    context,
                    'Enable remote configuration modification',
                    kOptionAllowRemoteConfigModification,
                    enabled: enabled,
                    fakeValue: fakeValue),
              ],
            ),
          ]);
    }

    return tmpWrapper();
  }

  Widget more(BuildContext context) {
    bool enabled = !locked;
    return _FoldoutCard(title: 'Security', children: [
      if (!isChangeIdDisabled()) ...[
        _SettingSectionTitle(context, 'ID'),
        changeId(),
      ],
      _SettingSectionDivider(context),
      shareRdp(context, enabled),
      if (isWindows) ...[
        _SettingSectionDivider(context),
        _PostInstallPermissionActions(enabled: enabled),
      ],
      _SettingSectionDivider(context),
      _SettingSectionTitle(context, 'Network'),
      _OptionCheckBox(context, 'Deny LAN discovery', 'enable-lan-discovery',
          reverse: true, enabled: enabled),
      ...directIp(context),
      whitelist(),
      _SettingSectionDivider(context),
      ...autoDisconnect(context),
      _OptionCheckBox(context, 'keep-awake-during-incoming-sessions-label',
          kOptionKeepAwakeDuringIncomingSessions,
          reverse: false, enabled: enabled),
      if (bind.mainIsInstalled())
        _OptionCheckBox(context, 'allow-only-conn-window-open-tip',
            'allow-only-conn-window-open',
            reverse: false, enabled: enabled),
      if (bind.mainIsInstalled() && !isUnlockPinDisabled()) unlockPin()
    ]);
  }

  shareRdp(BuildContext context, bool enabled) {
    onChanged(bool b) async {
      await bind.mainSetShareRdp(enable: b);
      setState(() {});
    }

    bool value = bind.mainIsShareRdp();
    return Offstage(
      offstage: !(isWindows && bind.mainIsInstalled()),
      child: GestureDetector(
          child: Row(
            children: [
              Checkbox(
                      value: value,
                      onChanged: enabled ? (_) => onChanged(!value) : null)
                  .marginOnly(right: 5),
              Expanded(
                child: Text(translate('Enable RDP session sharing'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled))),
              )
            ],
          ).marginOnly(left: _kCheckBoxLeftMargin),
          onTap: enabled ? () => onChanged(!value) : null),
    );
  }

  List<Widget> directIp(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(context, 'Enable direct IP access', kOptionDirectServer,
          update: update, enabled: !locked),
      () {
        // Simple temp wrapper for PR check
        tmpWrapper() {
          bool enabled = option2bool(kOptionDirectServer,
              bind.mainGetOptionSync(key: kOptionDirectServer));
          if (!enabled) applyEnabled.value = false;
          controller.text =
              bind.mainGetOptionSync(key: kOptionDirectAccessPort);
          final isOptFixed = isOptionFixed(kOptionDirectAccessPort);
          return Offstage(
            offstage: !enabled,
            child: _SubLabeledWidget(
              context,
              'Port',
              Row(children: [
                SizedBox(
                  width: 95,
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !locked && !isOptFixed,
                    onChanged: (_) => applyEnabled.value = true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(
                          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '21118',
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ).workaroundFreezeLinuxMint().marginOnly(right: 15),
                ),
                Obx(() => ElevatedButton(
                      onPressed: applyEnabled.value &&
                              enabled &&
                              !locked &&
                              !isOptFixed
                          ? () async {
                              applyEnabled.value = false;
                              await bind.mainSetOption(
                                  key: kOptionDirectAccessPort,
                                  value: controller.text);
                            }
                          : null,
                      child: Text(
                        translate('Apply'),
                      ),
                    ))
              ]),
              enabled: enabled && !locked && !isOptFixed,
            ),
          );
        }

        return tmpWrapper();
      }(),
    ];
  }

  Widget whitelist() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool hasWhitelist = whitelistNotEmpty().obs;
      update() async {
        hasWhitelist.value = whitelistNotEmpty();
      }

      onChanged(bool? checked) async {
        changeWhiteList(callback: update);
      }

      final isOptFixed = isOptionFixed(kOptionWhitelist);
      return GestureDetector(
        child: Tooltip(
          message: translate('whitelist_tip'),
          child: Obx(() => Row(
                children: [
                  Checkbox(
                          value: hasWhitelist.value,
                          onChanged: enabled && !isOptFixed ? onChanged : null)
                      .marginOnly(right: 5),
                  Offstage(
                    offstage: !hasWhitelist.value,
                    child: MouseRegion(
                      child: const Icon(Icons.warning_amber_rounded,
                              color: Color.fromARGB(255, 255, 204, 0))
                          .marginOnly(right: 5),
                      cursor: SystemMouseCursors.click,
                    ),
                  ),
                  Expanded(
                      child: Text(
                    translate('Use IP Whitelisting'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  ))
                ],
              )),
        ),
        onTap: enabled
            ? () {
                onChanged(!hasWhitelist.value);
              }
            : null,
      ).marginOnly(left: _kCheckBoxLeftMargin);
    }

    return tmpWrapper();
  }

  Widget hide_cm(bool enabled) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: (context, model, child) {
          final enableHideCm = model.approveMode == 'password' &&
              model.verificationMethod == kUsePermanentPassword;
          onHideCmChanged(bool? b) {
            if (b != null) {
              bind.mainSetOption(
                  key: 'allow-hide-cm', value: bool2option('allow-hide-cm', b));
            }
          }

          return Tooltip(
              message: enableHideCm ? "" : translate('hide_cm_tip'),
              child: GestureDetector(
                onTap:
                    enableHideCm ? () => onHideCmChanged(!model.hideCm) : null,
                child: Row(
                  children: [
                    Checkbox(
                            value: model.hideCm,
                            onChanged: enabled && enableHideCm
                                ? onHideCmChanged
                                : null)
                        .marginOnly(right: 5),
                    Expanded(
                      child: Text(
                        translate('Hide connection management window'),
                        style: TextStyle(
                            color: disabledTextColor(
                                context, enabled && enableHideCm)),
                      ),
                    ),
                  ],
                ),
              ));
        }));
  }

  List<Widget> autoDisconnect(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(
          context, 'auto_disconnect_option_tip', kOptionAllowAutoDisconnect,
          update: update, enabled: !locked),
      () {
        bool enabled = option2bool(kOptionAllowAutoDisconnect,
            bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
        if (!enabled) applyEnabled.value = false;
        controller.text =
            bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
        final isOptFixed = isOptionFixed(kOptionAutoDisconnectTimeout);
        return Offstage(
          offstage: !enabled,
          child: _SubLabeledWidget(
            context,
            'Timeout in minutes',
            Row(children: [
              SizedBox(
                width: 95,
                child: TextField(
                  controller: controller,
                  enabled: enabled && !locked && !isOptFixed,
                  onChanged: (_) => applyEnabled.value = true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(
                        r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '10',
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ).workaroundFreezeLinuxMint().marginOnly(right: 15),
              ),
              Obx(() => ElevatedButton(
                    onPressed:
                        applyEnabled.value && enabled && !locked && !isOptFixed
                            ? () async {
                                applyEnabled.value = false;
                                await bind.mainSetOption(
                                    key: kOptionAutoDisconnectTimeout,
                                    value: controller.text);
                              }
                            : null,
                    child: Text(
                      translate('Apply'),
                    ),
                  ))
            ]),
            enabled: enabled && !locked && !isOptFixed,
          ),
        );
      }(),
    ];
  }

  Widget unlockPin() {
    bool enabled = !locked;
    RxString unlockPin = bind.mainGetUnlockPin().obs;
    update() async {
      unlockPin.value = bind.mainGetUnlockPin();
    }

    onChanged(bool? checked) async {
      changeUnlockPinDialog(unlockPin.value, update);
    }

    final isOptFixed = isOptionFixed(kOptionWhitelist);
    return GestureDetector(
      child: Obx(() => Row(
            children: [
              Checkbox(
                      value: unlockPin.isNotEmpty,
                      onChanged: enabled && !isOptFixed ? onChanged : null)
                  .marginOnly(right: 5),
              Expanded(
                  child: Text(
                translate('Unlock with PIN'),
                style: TextStyle(color: disabledTextColor(context, enabled)),
              ))
            ],
          )),
      onTap: enabled
          ? () {
              onChanged(!unlockPin.isNotEmpty);
            }
          : null,
    ).marginOnly(left: _kCheckBoxLeftMargin);
  }
}

class _Network extends StatefulWidget {
  const _Network({Key? key}) : super(key: key);

  @override
  State<_Network> createState() => _NetworkState();
}

class _NetworkState extends State<_Network> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = !isWeb && bind.mainIsInstalled();

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proxyReferenceCard(context),
        _connectionQualityReferenceCard(context),
        _advancedNetworkReferenceCard(context),
      ],
    );
    return _SettingsReferencePage(
      marker: 'kq-v218-settings-network-page',
      children: [
        if (locked) _unlockNetworkReferenceCard(context),
        AbsorbPointer(
          absorbing: locked,
          child: Opacity(opacity: locked ? 0.58 : 1, child: content),
        ),
      ],
    );
  }

  Widget _unlockNetworkReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Network',
      child: Row(
        children: [
          Expanded(
            child: Text(
              translate('Unlock Network Settings'),
              style: TextStyle(
                color: _settingPalette(context).mutedText,
                fontSize: 13,
              ),
            ),
          ),
          _settingsLightButton(
            icon: Icons.lock_open_rounded,
            label: 'Unlock Network Settings',
            primary: true,
            onPressed: () async {
              final unlockPin = bind.mainGetUnlockPin();
              if (unlockPin.isEmpty || isUnlockPinDisabled()) {
                bool checked = await callMainCheckSuperUserPermission();
                if (checked) {
                  locked = false;
                  setState(() {});
                }
              } else {
                checkUnlockPinDialog(unlockPin, () {
                  locked = false;
                  setState(() {});
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _proxyReferenceCard(BuildContext context) {
    final hideProxy =
        isWeb || bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    if (hideProxy) {
      return const Offstage();
    }
    return _SettingsReferenceCard(
      icon: Icons.credit_card_outlined,
      title: _kqSettingText('代理设置', 'Proxy settings'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _settingsLightButton(
          icon: Icons.tune_rounded,
          label: 'Socks5/Http(s) Proxy',
          onPressed: locked ? null : changeSocks5Proxy,
        ),
      ),
    );
  }

  Widget _connectionQualityReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.speed_rounded,
      title: _kqSettingText('连接质量', 'Connection quality'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsReferenceControlRow(
            label: 'Quality',
            control: SizedBox(
              width: 220,
              child: ComboBox(
                keys: const ['auto'],
                values: [_kqSettingText('自动', 'Auto')],
                initialKey: 'auto',
                enabled: false,
                onChanged: (_) {},
              ),
            ),
          ),
          _SettingsReferenceCheckGrid(
            children: [
              _OptionCheckBox(
                context,
                'Adaptive bitrate',
                kOptionEnableAbr,
                enabled: !locked,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _advancedNetworkReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.wifi_tethering_rounded,
      title: _kqSettingText('高级网络', 'Advanced network'),
      child: _SettingsReferenceCheckGrid(
        children: [
          if (!bind.isIncomingOnly())
            _OptionCheckBox(
              context,
              'Enable UDP hole punching',
              kOptionEnableUdpPunch,
              isServer: false,
              enabled: !locked,
            ),
          if (!bind.isIncomingOnly())
            _OptionCheckBox(
              context,
              'Enable IPv6 P2P connection',
              kOptionEnableIpv6Punch,
              isServer: false,
              enabled: !locked,
            ),
          if (!bind.isOutgoingOnly())
            _OptionCheckBox(
              context,
              'Disable UDP',
              kOptionDisableUdp,
              enabled: !locked,
            ),
          if (isWindows && !bind.isOutgoingOnly())
            _OptionCheckBox(
              context,
              'Capture screen using DirectX',
              kOptionDirectxCapture,
              enabled: !locked,
            ),
          if (!isWeb)
            _OptionCheckBox(
              context,
              'Use WebSocket',
              kOptionAllowWebSocket,
              enabled: !locked,
            ),
        ],
      ),
    );
  }

  Widget network(BuildContext context) {
    final hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    final hideProxy =
        isWeb || bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    final hideWebSocket = isWeb ||
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y';

    if (hideServer && hideProxy && hideWebSocket) {
      return Offstage();
    }

    // Helper function to create network setting ListTiles
    Widget listTile({
      required IconData icon,
      required String title,
      VoidCallback? onTap,
      Widget? trailing,
      bool showTooltip = false,
      String tooltipMessage = '',
    }) {
      final titleWidget = showTooltip
          ? Row(
              children: [
                Tooltip(
                  waitDuration: Duration(milliseconds: 1000),
                  message: translate(tooltipMessage),
                  child: Row(
                    children: [
                      Text(
                        translate(title),
                        style: TextStyle(fontSize: _kContentFontSize),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.help_outline,
                        size: 14,
                        color: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Text(
              translate(title),
              style: TextStyle(fontSize: _kContentFontSize),
            );

      return ListTile(
        leading: Icon(icon, color: _accentColor),
        title: titleWidget,
        enabled: !locked,
        onTap: onTap,
        trailing: trailing,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minLeadingWidth: 0,
        horizontalTitleGap: 10,
      );
    }

    Widget switchWidget(IconData icon, String title, String tooltipMessage,
            String optionKey) =>
        listTile(
          icon: icon,
          title: title,
          showTooltip: true,
          tooltipMessage: tooltipMessage,
          trailing: Switch(
            value: mainGetBoolOptionSync(optionKey),
            onChanged: locked || isOptionFixed(optionKey)
                ? null
                : (value) {
                    mainSetBoolOption(optionKey, value);
                    setState(() {});
                  },
          ),
        );

    final outgoingOnly = bind.isOutgoingOnly();

    final divider = const Divider(height: 1, indent: 16, endIndent: 16);
    return _Card(
      title: 'Network',
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideServer)
                listTile(
                  icon: Icons.dns_outlined,
                  title: 'ID/Relay Server',
                  onTap: () => showServerSettings(gFFI.dialogManager, setState),
                ),
              if (!hideProxy && !hideServer) divider,
              if (!hideProxy)
                listTile(
                  icon: Icons.network_ping_outlined,
                  title: 'Socks5/Http(s) Proxy',
                  onTap: changeSocks5Proxy,
                ),
              if (!hideWebSocket && (!hideServer || !hideProxy)) divider,
              if (!hideWebSocket)
                switchWidget(
                    Icons.web_asset_outlined,
                    'Use WebSocket',
                    '${translate('websocket_tip')}\n\n${translate('server-oss-not-support-tip')}',
                    kOptionAllowWebSocket),
              if (!isWeb)
                futureBuilder(
                  future: bind.mainIsUsingPublicServer(),
                  hasData: (isUsingPublicServer) {
                    if (isUsingPublicServer) {
                      return Offstage();
                    } else {
                      return Column(
                        children: [
                          if (!hideServer || !hideProxy || !hideWebSocket)
                            divider,
                          switchWidget(
                              Icons.no_encryption_outlined,
                              'Allow insecure TLS fallback',
                              'allow-insecure-tls-fallback-tip',
                              kOptionAllowInsecureTLSFallback),
                          if (!outgoingOnly) divider,
                          if (!outgoingOnly)
                            listTile(
                              icon: Icons.lan_outlined,
                              title: 'Disable UDP',
                              showTooltip: true,
                              tooltipMessage:
                                  '${translate('disable-udp-tip')}\n\n${translate('server-oss-not-support-tip')}',
                              trailing: Switch(
                                value: bind.mainGetOptionSync(
                                        key: kOptionDisableUdp) ==
                                    'Y',
                                onChanged:
                                    locked || isOptionFixed(kOptionDisableUdp)
                                        ? null
                                        : (value) async {
                                            await bind.mainSetOption(
                                                key: kOptionDisableUdp,
                                                value: value ? 'Y' : 'N');
                                            setState(() {});
                                          },
                              ),
                            ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Display extends StatefulWidget {
  const _Display({Key? key}) : super(key: key);

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  bool _syncingMemberEntitlement = false;
  DateTime? _lastMemberEntitlementSyncAt;

  Future<void> _syncMemberEntitlementFromDisk({bool force = false}) async {
    if (_syncingMemberEntitlement) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastMemberEntitlementSyncAt != null &&
        now.difference(_lastMemberEntitlementSyncAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastMemberEntitlementSyncAt = now;
    _syncingMemberEntitlement = true;
    try {
      final changed = await gFFI.userModel.syncMemberEntitlementFromDisk();
      if (changed && mounted) {
        setState(() {});
      }
    } finally {
      _syncingMemberEntitlement = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    unawaited(_syncMemberEntitlementFromDisk());
    final privacyModeChildren =
        !isWeb ? privacyModeImpl(context) : const <Widget>[];
    return _SettingsReferencePage(
      marker: 'kq-v218-settings-display-page',
      children: [
        _qualityReferenceCard(context),
        _viewAndScrollReferenceCard(context),
        _imageQualityCodecReferenceCard(context),
        _renderReferenceCard(context),
        _displayOptionsReferenceCard(context),
        _otherDefaultsReferenceCard(context, privacyModeChildren),
      ],
    );
  }

  Future<void> _saveRemotePerformance({
    String? resolutionTier,
    int? fps,
  }) async {
    final user = gFFI.userModel;
    await _syncMemberEntitlementFromDisk(force: true);
    await user.setRemotePerformanceProfile(
      resolutionTier: resolutionTier ?? user.remoteResolutionSelection,
      fps: fps ?? user.remoteFpsSelection,
    );
    setState(() {});
    showToast(
        '${translate('Remote experience updated')}: ${user.remoteQualityLabel}');
  }

  Widget _qualityReferenceCard(BuildContext context) {
    final user = gFFI.userModel;
    final isMember = user.isMember.value;
    final resolution = user.remoteResolutionSelection;
    final fps = user.remoteFpsSelection;
    return _SettingsReferenceCard(
      icon: Icons.desktop_windows_outlined,
      title: _kqSettingText('画质设置', 'Quality settings'),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        final resolutionControl = _SettingsReferenceControlRow(
          label: _kqSettingText('默认分辨率', 'Default resolution'),
          control: SizedBox(
            width: 220,
            child: ComboBox(
              keys: const [
                UserModel.remoteResolution720p,
                UserModel.remoteResolution1080p,
              ],
              values: const ['720p', '1080p'],
              initialKey: resolution,
              onChanged: (value) {
                if (value == UserModel.remoteResolution1080p && !isMember) {
                  showToast(translate('Members can use 1080p / 60 FPS'));
                  setState(() {});
                  return;
                }
                _saveRemotePerformance(resolutionTier: value);
              },
            ),
          ),
          helper: isMember
              ? _kqSettingText('会员已解锁', 'Membership unlocked')
              : _kqSettingText('会员可用 1080p', '1080p for members'),
        );
        final fpsControl = _SettingsReferenceControlRow(
          label: _kqSettingText('默认帧率', 'Default frame rate'),
          control: SizedBox(
            width: 220,
            child: ComboBox(
              keys: const ['30', '60'],
              values: const ['30 FPS', '60 FPS'],
              initialKey: fps >= 60 ? '60' : '30',
              onChanged: (value) {
                final nextFps = int.tryParse(value) ?? 30;
                if (nextFps >= 60 && !isMember) {
                  showToast(translate('Members can use 1080p / 60 FPS'));
                  setState(() {});
                  return;
                }
                _saveRemotePerformance(fps: nextFps);
              },
            ),
          ),
          helper: isMember
              ? _kqSettingText('会员已解锁', 'Membership unlocked')
              : _kqSettingText('会员可用 60 FPS', '60 FPS for members'),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: resolutionControl),
              const SizedBox(width: 14),
              Expanded(child: fpsControl),
            ],
          );
        }
        return Column(children: [resolutionControl, fpsControl]);
      }),
    );
  }

  Widget _viewAndScrollReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.open_in_full_rounded,
      title: 'Default View Style',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...viewStyle(context),
          _SettingSectionDivider(context),
          _SettingSectionTitle(context, 'Default Scroll Style'),
          ...scrollStyle(context),
        ],
      ),
    );
  }

  Widget _imageQualityCodecReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.high_quality_rounded,
      title: 'Default Image Quality',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...imageQuality(context),
          _SettingSectionDivider(context),
          _SettingSectionTitle(context, 'Default Codec'),
          ...codec(context),
          if (isDesktop) ...[
            _SettingSectionDivider(context),
            _SettingSectionTitle(context, 'Default trackpad speed'),
            ...trackpadSpeed(context),
          ],
        ],
      ),
    );
  }

  Widget _renderReferenceCard(BuildContext context) {
    final children = <Widget>[
      if (bind.mainHasHwcodec() || bind.mainHasVram())
        _OptionCheckBox(
          context,
          'Enable hardware codec',
          kOptionEnableHwcodec,
          update: (bool v) {
            if (v) {
              bind.mainCheckHwcodec();
            }
          },
        ),
      if (!isWeb && !bind.isIncomingOnly())
        Tooltip(
          message: translate('texture_render_tip'),
          child: _OptionCheckBox(
            context,
            "Use texture rendering",
            kOptionTextureRender,
            optGetter: bind.mainGetUseTextureRender,
            optSetter: (k, v) async =>
                await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
          ),
        ),
      if (isWindows && !bind.isIncomingOnly())
        Tooltip(
          message: translate('d3d_render_tip'),
          child: _OptionCheckBox(
            context,
            "Use D3D rendering",
            kOptionD3DRender,
            isServer: false,
          ),
        ),
      if (!bind.isOutgoingOnly()) _removeWallpaperReferenceCheck(context),
    ];
    return _SettingsReferenceCard(
      icon: Icons.bolt_rounded,
      title: _kqSettingText('渲染与性能', 'Rendering and performance'),
      child: _SettingsReferenceCheckGrid(children: children),
    );
  }

  Widget _removeWallpaperReferenceCheck(BuildContext context) {
    return futureBuilder(future: () async {
      return await bind.mainSupportRemoveWallpaper();
    }(), hasData: (data) {
      if (data is bool && data) {
        return _OptionCheckBox(
          context,
          'Remove wallpaper during incoming sessions',
          kOptionAllowRemoveWallpaper,
          update: (bool v) => setState(() {}),
        );
      }
      return const Offstage();
    });
  }

  Widget _displayOptionsReferenceCard(BuildContext context) {
    return _SettingsReferenceCard(
      icon: Icons.visibility_outlined,
      title: _kqSettingText('显示选项', 'Display options'),
      child: _SettingsReferenceCheckGrid(
        children: [
          if (isDesktop || isWebDesktop)
            _OptionCheckBox(
              context,
              'show_monitors_tip',
              kKeyShowMonitorsToolbar,
              isServer: false,
            ),
          _OptionCheckBox(
            context,
            'Show quality monitor',
            kOptionShowQualityMonitor,
            isServer: false,
          ),
          if (isDesktop || isWebDesktop)
            _OptionCheckBox(
              context,
              'Collapse toolbar',
              kOptionCollapseToolbar,
              isServer: false,
            ),
          _OptionCheckBox(
            context,
            'Show remote cursor',
            kOptionShowRemoteCursor,
            isServer: false,
          ),
        ],
      ),
    );
  }

  Widget _otherDefaultsReferenceCard(
    BuildContext context,
    List<Widget> privacyModeChildren,
  ) {
    return _SettingsReferenceCard(
      icon: Icons.tune_rounded,
      title: 'Other Default Options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (privacyModeChildren.isNotEmpty) ...[
            _SettingSectionTitle(context, 'Privacy mode'),
            ...privacyModeChildren,
            _SettingSectionDivider(context),
          ],
          ...other(context),
        ],
      ),
    );
  }

  List<Widget> viewStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionViewStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    return [
      _Radio(context,
          value: kRemoteViewStyleOriginal,
          groupValue: groupValue,
          label: 'Scale original',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteViewStyleAdaptive,
          groupValue: groupValue,
          label: 'Scale adaptive',
          onChanged: isOptFixed ? null : onChanged),
    ];
  }

  List<Widget> scrollStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionScrollStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionScrollStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionScrollStyle);

    onEdgeScrollEdgeThicknessChanged(double value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionEdgeScrollEdgeThickness, value: value.round().toString());
      setState(() {});
    }

    return [
      _Radio(context,
          value: kRemoteScrollStyleAuto,
          groupValue: groupValue,
          label: 'ScrollAuto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteScrollStyleBar,
          groupValue: groupValue,
          label: 'Scrollbar',
          onChanged: isOptFixed ? null : onChanged),
      if (!isWeb) ...[
        _Radio(context,
            value: kRemoteScrollStyleEdge,
            groupValue: groupValue,
            label: 'ScrollEdge',
            onChanged: isOptFixed ? null : onChanged),
        Offstage(
            offstage: groupValue != kRemoteScrollStyleEdge,
            child: EdgeThicknessControl(
              value: double.tryParse(bind.mainGetUserDefaultOption(
                      key: kOptionEdgeScrollEdgeThickness)) ??
                  100.0,
              onChanged: isOptionFixed(kOptionEdgeScrollEdgeThickness)
                  ? null
                  : onEdgeScrollEdgeThicknessChanged,
            )),
      ],
    ];
  }

  List<Widget> imageQuality(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionImageQuality, value: value);
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kOptionImageQuality);
    final groupValue = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    return [
      _Radio(context,
          value: kRemoteImageQualityBest,
          groupValue: groupValue,
          label: 'Good image quality',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityBalanced,
          groupValue: groupValue,
          label: 'Balanced',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityLow,
          groupValue: groupValue,
          label: 'Optimize reaction time',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityCustom,
          groupValue: groupValue,
          label: 'Custom',
          onChanged: isOptFixed ? null : onChanged),
      Offstage(
        offstage: groupValue != kRemoteImageQualityCustom,
        child: customImageQualitySetting(),
      )
    ];
  }

  List<Widget> trackpadSpeed(BuildContext context) {
    final initSpeed =
        (int.tryParse(bind.mainGetUserDefaultOption(key: kKeyTrackpadSpeed)) ??
            kDefaultTrackpadSpeed);
    final curSpeed = SimpleWrapper(initSpeed);
    void onDebouncer(int v) {
      bind.mainSetUserDefaultOption(
          key: kKeyTrackpadSpeed, value: v.toString());
      // It's better to notify all sessions that the default speed is changed.
      // But it may also be ok to take effect in the next connection.
    }

    return [
      TrackpadSpeedWidget(
        value: curSpeed,
        onDebouncer: onDebouncer,
      ),
    ];
  }

  List<Widget> codec(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionCodecPreference, value: value);
      setState(() {});
    }

    final groupValue =
        bind.mainGetUserDefaultOption(key: kOptionCodecPreference);
    var hwRadios = [];
    final isOptFixed = isOptionFixed(kOptionCodecPreference);
    try {
      final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
      final h264 = codecsJson['h264'] ?? false;
      final h265 = codecsJson['h265'] ?? false;
      if (h264) {
        hwRadios.add(_Radio(context,
            value: 'h264',
            groupValue: groupValue,
            label: 'H264',
            onChanged: isOptFixed ? null : onChanged));
      }
      if (h265) {
        hwRadios.add(_Radio(context,
            value: 'h265',
            groupValue: groupValue,
            label: 'H265',
            onChanged: isOptFixed ? null : onChanged));
      }
    } catch (e) {
      debugPrint("failed to parse supported hwdecodings, err=$e");
    }
    return [
      _Radio(context,
          value: 'auto',
          groupValue: groupValue,
          label: 'Auto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'vp8',
          groupValue: groupValue,
          label: 'VP8',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'vp9',
          groupValue: groupValue,
          label: 'VP9',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'av1',
          groupValue: groupValue,
          label: 'AV1',
          onChanged: isOptFixed ? null : onChanged),
      ...hwRadios,
    ];
  }

  List<Widget> privacyModeImpl(BuildContext context) {
    final supportedPrivacyModeImpls = bind.mainSupportedPrivacyModeImpls();
    late final List<dynamic> privacyModeImpls;
    try {
      privacyModeImpls = jsonDecode(supportedPrivacyModeImpls);
    } catch (e) {
      debugPrint('failed to parse supported privacy mode impls, err=$e');
      return const [];
    }
    if (privacyModeImpls.length < 2) {
      return const [];
    }

    final key = 'privacy-mode-impl-key';
    onChanged(String value) async {
      await bind.mainSetOption(key: key, value: value);
      setState(() {});
    }

    String groupValue = bind.mainGetOptionSync(key: key);
    if (groupValue.isEmpty) {
      groupValue = bind.mainDefaultPrivacyModeImpl();
    }
    return privacyModeImpls.map((impl) {
      final d = impl as List<dynamic>;
      return _Radio(context,
          value: d[0] as String,
          groupValue: groupValue,
          label: d[1] as String,
          onChanged: onChanged);
    }).toList();
  }

  Widget otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    onChanged(bool b) async {
      await bind.mainSetUserDefaultOption(
          key: key,
          value: b
              ? 'Y'
              : (key == kOptionEnableFileCopyPaste ? 'N' : defaultOptionNo));
      setState(() {});
    }

    return GestureDetector(
        child: Row(
          children: [
            Checkbox(
                    value: value,
                    onChanged: isOptFixed ? null : (_) => onChanged(!value))
                .marginOnly(right: 5),
            Expanded(
              child: Text(translate(label)),
            )
          ],
        ).marginOnly(left: _kCheckBoxLeftMargin),
        onTap: isOptFixed ? null : () => onChanged(!value));
  }

  List<Widget> other(BuildContext context) =>
      otherDefaultSettings().map((e) => otherRow(e.$1, e.$2)).toList();
}

class _Account extends StatefulWidget {
  const _Account({Key? key}) : super(key: key);

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  bool _syncingMemberEntitlement = false;
  DateTime? _lastMemberEntitlementSyncAt;

  Future<void> _syncMemberEntitlementFromDisk({bool force = false}) async {
    if (_syncingMemberEntitlement) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastMemberEntitlementSyncAt != null &&
        now.difference(_lastMemberEntitlementSyncAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastMemberEntitlementSyncAt = now;
    _syncingMemberEntitlement = true;
    try {
      final changed = await gFFI.userModel.syncMemberEntitlementFromDisk();
      if (changed && mounted) {
        setState(() {});
      }
    } finally {
      _syncingMemberEntitlement = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        Obx(() {
          if (gFFI.userModel.userName.value.isEmpty) {
            return _accountShell(context, _signedOutReferencePanel(context));
          }
          return _accountShell(
            context,
            _signedInReferencePanel(context),
          );
        }),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget _accountShell(BuildContext context, Widget child) {
    final palette = _settingPalette(context);
    final useDesignerAccountShell = DateTime.now().microsecondsSinceEpoch >= 0;
    if (useDesignerAccountShell) {
      return Container(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        color: palette.contentBackground,
        child: child,
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 15, 24, 0),
      decoration: BoxDecoration(
        color: palette.cardBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(
              horizontal: _kContentHMargin,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: palette.cardHeaderBackground,
              border: Border(bottom: BorderSide(color: palette.cardBorder)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_rounded, color: palette.navSelectedText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    translate('Account'),
                    style: TextStyle(
                      color: palette.primaryText,
                      fontSize: _kContentFontSize,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _membershipBadge(context),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _signedInReferencePanel(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // kq-v216-account-reference-page
        constraints: const BoxConstraints(maxWidth: 812),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileReferenceBanner(context),
            const SizedBox(height: 14),
            _membershipReferenceCard(context),
            const SizedBox(height: 14),
            _remotePerformancePanel(context),
            const SizedBox(height: 16),
            _centeredLogoutButton(context),
            const SizedBox(height: 16),
            _qualityReferenceNote(context),
          ],
        ),
      ),
    );
  }

  Widget _referenceCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Builder(builder: (context) {
      final palette = _settingPalette(context);
      return Container(
        // kq-v227-account-reference-card-theme-colors
        padding: padding,
        decoration: BoxDecoration(
          color: palette.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.cardBorder),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );
    });
  }

  Widget _profileReferenceBanner(BuildContext context) {
    final user = gFFI.userModel;
    return _referenceCard(
      // kq-v216-account-profile-banner
      padding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
      child: Row(
        children: [
          _buildReferenceAvatar(context, 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.displayNameOrUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _settingsDesignerTextPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${user.userName.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _settingsDesignerTextSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          _referenceMembershipBadge(context),
        ],
      ),
    );
  }

  Widget _referenceMembershipBadge(BuildContext context) {
    final isMember = gFFI.userModel.isMember.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _settingsDesignerBlueSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _settingsDesignerCardBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMember ? Icons.workspace_premium_outlined : Icons.layers_rounded,
            size: 14,
            color: _kqDesignerBlue,
          ),
          const SizedBox(width: 5),
          Text(
            isMember
                ? _kqSettingText('会员版', 'Member')
                : _kqSettingText('基础版', 'Basic'),
            style: const TextStyle(
              color: _kqDesignerBlue,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _membershipReferenceCard(BuildContext context) {
    final user = gFFI.userModel;
    final isMember = user.isMember.value;
    final expireAt = user.memberExpireAt.value.trim();
    final expireLabel = _memberExpireAtLabel(expireAt);
    final palette = _settingPalette(context);
    final title = isMember
        ? _kqSettingText('当前为会员版', 'Current plan: Member')
        : _kqSettingText('当前为基础版', 'Current plan: Basic');
    final subtitle = isMember
        ? '$expireLabel, ${_kqSettingText('可使用更高分辨率与帧率', 'higher resolution and frame rate available')}'
        : _kqSettingText('升级会员解锁更高分辨率与帧率',
            'Upgrade to unlock higher resolution and frame rate');
    return _referenceCard(
      // kq-v216-account-member-card
      // kq-v219-account-member-expire-at
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _referenceSectionTitle(
            icon: Icons.star_border_rounded,
            title: _kqSettingText('会员权益', 'Membership benefits'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: _settingsDesignerInfoSurface(context),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: palette.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _settingsDesignerBlueSurface(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF48A5FF),
                    size: 17,
                  ),
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
                          color: palette.primaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _showMemberRechargeDialog,
                  icon: const Icon(Icons.star_border_rounded, size: 17),
                  label: Text(isMember
                      ? _kqSettingText('续费会员', 'Renew membership')
                      : _kqSettingText('开通会员', 'Upgrade membership')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kqDesignerBlue,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: _kqDesignerBlue.withOpacity(0.28),
                    minimumSize: const Size(128, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: user.isRefreshingMembership.value
                      ? null
                      : () => gFFI.userModel.refreshMembership(showError: true),
                  icon: user.isRefreshingMembership.value
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_kqSettingText('刷新权益', 'Refresh benefits')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.primaryText,
                    minimumSize: const Size(128, 42),
                    side: BorderSide(color: palette.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _memberExpireAtLabel(String expireAt) {
    if (expireAt.isEmpty) {
      return _kqSettingText('到期时间：暂未同步', 'Expiration: not synced yet');
    }
    if (expireAt.toLowerCase() == 'unlimited') {
      return _kqSettingText('到期时间：长期有效', 'Expiration: lifetime');
    }
    final normalized = expireAt
        .replaceFirst('T', ' ')
        .replaceFirst(RegExp(r'\.\d+Z?$'), '')
        .replaceFirst(RegExp(r'Z$'), '')
        .trim();
    return '${_kqSettingText('到期时间', 'Expiration')}: $normalized';
  }

  Widget _referenceSectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Builder(builder: (context) {
      final palette = _settingPalette(context);
      return Row(
        children: [
          Icon(icon, size: 20, color: palette.primaryText),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: palette.primaryText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      );
    });
  }

  Widget _centeredLogoutButton(BuildContext context) {
    final palette = _settingPalette(context);
    return Center(
      // kq-v216-account-logout-centered
      child: OutlinedButton.icon(
        onPressed: logOutConfirmDialog,
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: Text(_kqSettingText('退出登录', 'Log out')),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFF4D4F),
          minimumSize: const Size(130, 36),
          side: BorderSide(color: palette.cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _qualityReferenceNote(BuildContext context) {
    final palette = _settingPalette(context);
    return Container(
      // kq-v216-account-quality-note
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: _settingsDesignerBlueSurface(context),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFF48A5FF), size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _kqSettingText(
                '画质与帧率说明：基础版用户可使用 720p / 30 FPS。升级会员后可解锁 1080p 高清画质及 60 FPS 高帧率，获得更加流畅、清晰的远程桌面体验。',
                'Quality and frame rate: Basic users can use 720p / 30 FPS. Members unlock 1080p HD and 60 FPS for a smoother, clearer remote desktop experience.',
              ),
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceAvatar(BuildContext context, double size) {
    final avatar =
        bind.mainResolveAvatarUrl(avatar: gFFI.userModel.avatar.value);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: _kqDesignerBlue.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        Icons.person_outline_rounded,
        size: size * 0.52,
        color: Colors.white,
      ),
    );
    return buildAvatarWidget(
          avatar: avatar,
          size: size,
          fallback: fallback,
        ) ??
        fallback;
  }

  Widget _signedOutReferencePanel(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // kq-v217-account-signed-out-reference-panel
        constraints: const BoxConstraints(maxWidth: 812, minHeight: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _referenceCard(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [_kqDesignerBlue, Color(0xFF60A5FA)],
                      ),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kqSettingText(
                              '登录鲲穹账号', 'Log in to Kunqiong account'),
                          style: TextStyle(
                            color: _settingsDesignerTextPrimary(context),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          _kqSettingText(
                            '登录后可查看会员权益、同步账号设备，并解锁对应的远控画质与帧率。',
                            'Log in to view membership benefits, sync account devices, and unlock matching remote quality and frame rates.',
                          ),
                          style: TextStyle(
                            color: _settingsDesignerTextSecondary(context),
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      // kq-v217-account-signed-out-login-action
                      onPressed: loginDialog,
                      icon: const Icon(Icons.login_rounded, size: 17),
                      label: Text(_kqSettingText('立即登录', 'Log in now')),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kqDesignerBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _referenceCard(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Row(
                children: [
                  Expanded(
                    child: _guestFeatureItem(
                      icon: Icons.verified_user_outlined,
                      title: _kqSettingText('安全远控', 'Secure remote control'),
                      subtitle: _kqSettingText('账号体系保护远程协助流程',
                          'Account protection for remote assistance flows'),
                      color: _kqDesignerBlue,
                      background: const Color(0xFFDBEAFE),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _guestFeatureItem(
                      icon: Icons.devices_rounded,
                      title: _kqSettingText('账号设备', 'Account devices'),
                      subtitle: _kqSettingText('查看登录过本账号的设备',
                          'View devices that have used this account'),
                      color: const Color(0xFF059669),
                      background: const Color(0xFFD1FAE5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _guestFeatureItem(
                      icon: Icons.bolt_rounded,
                      title: _kqSettingText('会员权益', 'Membership benefits'),
                      subtitle: _kqSettingText('会员可解锁 1080p / 60 FPS',
                          'Members can unlock 1080p / 60 FPS'),
                      color: const Color(0xFFD97706),
                      background: const Color(0xFFFEF3C7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signedOutPanel(BuildContext context) {
    return Container(
      // kq-designer-account-guest-layout
      constraints: const BoxConstraints(minHeight: 520),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Padding(
              padding: const EdgeInsets.only(right: 38),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kqSettingText(
                        '欢迎使用\n鲲穹远程桌面', 'Welcome to\nKunqiong Remote Desktop'),
                    style: TextStyle(
                      color: _settingsDesignerTextPrimary(context),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _kqSettingText(
                      '登录鲲穹账号，解锁完整的远程协作体验。\n跨设备管理、数据同步、会员专属权益，一切尽在掌握。',
                      'Log in to unlock the complete remote collaboration experience.\nManage devices, sync data, and enjoy member benefits.',
                    ),
                    style: TextStyle(
                      color: _settingsDesignerTextSecondary(context),
                      fontSize: 14,
                      height: 1.75,
                    ),
                  ),
                  const SizedBox(height: 34),
                  _guestFeatureItem(
                    icon: Icons.verified_user_outlined,
                    title: _kqSettingText('安全连接', 'Secure connection'),
                    subtitle: _kqSettingText('端到端加密，数据安全有保障',
                        'End-to-end encryption keeps data protected'),
                    color: _kqDesignerBlue,
                    background: const Color(0xFFDBEAFE),
                  ),
                  const SizedBox(height: 8),
                  _guestFeatureItem(
                    icon: Icons.devices_rounded,
                    title: _kqSettingText('多平台支持', 'Multi-platform support'),
                    subtitle: _kqSettingText('支持 Windows、Android 等设备协作',
                        'Works across Windows, Android, and more'),
                    color: const Color(0xFF059669),
                    background: const Color(0xFFD1FAE5),
                  ),
                  const SizedBox(height: 8),
                  _guestFeatureItem(
                    icon: Icons.bolt_rounded,
                    title: _kqSettingText('高清流畅', 'Clear and smooth'),
                    subtitle: _kqSettingText('会员可解锁 1080p / 60 FPS 远控体验',
                        'Members can unlock 1080p / 60 FPS remote control'),
                    color: const Color(0xFFD97706),
                    background: const Color(0xFFFEF3C7),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 9,
            child: Center(
              child: Container(
                width: 340,
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kqDesignerCardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: _kqDesignerBlue.withOpacity(0.08),
                      blurRadius: 40,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                        ),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: _kqDesignerBlue,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _kqSettingText('登录鲲穹账号', 'Log in to Kunqiong account'),
                      style: TextStyle(
                        color: _settingsDesignerTextPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _kqSettingText('同步数据、管理设备、享受会员权益',
                          'Sync data, manage devices, and enjoy member benefits'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _settingsDesignerTextSecondary(context),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: loginDialog,
                        icon: const Icon(Icons.login_rounded, size: 17),
                        label: Text(_kqSettingText('立即登录', 'Log in now')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guestFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color background,
  }) {
    return Builder(builder: (context) {
      final palette = _settingPalette(context);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: palette.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.cardBorder),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.primaryText,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ignore: unused_element
  Widget _accountOverviewPanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = gFFI.userModel;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withOpacity(0.14),
            colors.primaryContainer.withOpacity(0.16),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.insights_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kqSettingText('账户概览', 'Account overview'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.remoteEntitlementHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _accountMiniMetric(
                context,
                label: translate('Current tier'),
                value: user.membershipName,
                icon: Icons.workspace_premium_outlined,
              ),
              _accountMiniMetric(
                context,
                label: translate('Remote quality'),
                value: user.remoteQualityLabel,
                icon: Icons.speed_outlined,
              ),
              _accountMiniMetric(
                context,
                label: translate('Max frame rate'),
                value: '${user.remoteMaxFps} FPS',
                icon: Icons.videocam_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _accountBenefitChecklist(BuildContext context) {
    final user = gFFI.userModel;
    final isMember = user.isMember.value;
    return Container(
      // kq-account-legacy-benefit-checklist-unused
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _kqSettingText('会员权益', 'Membership benefits'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _accountBenefitItem(
            context,
            enabled: true,
            title: '720p / 30 FPS',
            subtitle:
                _kqSettingText('基础远控可用', 'Basic remote control available'),
          ),
          _accountBenefitItem(
            context,
            enabled: isMember,
            title: '1080p / 60 FPS',
            subtitle: translate('Member HD remote control'),
          ),
          _accountBenefitItem(
            context,
            enabled: isMember,
            title: translate('Member acceleration route'),
            subtitle: _kqSettingText(
                '会员畅享专属加速链路', 'Members enjoy an exclusive acceleration route'),
          ),
          _accountBenefitItem(
            context,
            enabled: true,
            title: _kqSettingText('本机账户设置', 'Local account settings'),
            subtitle: _kqSettingText(
                '偏好设置保存在本机', 'Preferences are saved on this device'),
          ),
        ],
      ),
    );
  }

  Widget _accountQuickActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = gFFI.userModel;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _kqSettingText('账户快捷操作', 'Account shortcuts'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _accountActionButton(
                context,
                icon: Icons.workspace_premium_outlined,
                label: translate(user.isMember.value
                    ? 'Renew membership'
                    : 'Upgrade membership'),
                primary: true,
                onPressed: _showMemberRechargeDialog,
              ),
              _accountActionButton(
                context,
                icon: user.isRefreshingMembership.value
                    ? Icons.hourglass_empty_rounded
                    : Icons.refresh_rounded,
                label: translate('Refresh benefits'),
                onPressed: user.isRefreshingMembership.value
                    ? null
                    : () => gFFI.userModel.refreshMembership(showError: true),
              ),
              _accountActionButton(
                context,
                icon: Icons.public_rounded,
                label: _kqSettingText('官网', 'Website'),
                onPressed: () => launchUrl(
                  Uri.parse('https://kunqiongai.com/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountSupportPanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: colors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _kqSettingText('画质和帧率会在新建远控会话时生效；开通或续费会员后可点击刷新权益同步状态。',
                  'Quality and frame-rate settings take effect in new remote sessions. After upgrading or renewing, refresh benefits to sync the status.'),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountMiniMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 152,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withOpacity(0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountBenefitItem(
    BuildContext context, {
    required bool enabled,
    required String title,
    required String subtitle,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: enabled ? colors.primary : colors.outline,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? null : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 7),
        Text(label),
      ],
    );
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      child: child,
    );
  }

  Future<void> _saveRemotePerformance({
    String? resolutionTier,
    int? fps,
  }) async {
    final user = gFFI.userModel;
    await _syncMemberEntitlementFromDisk(force: true);
    await user.setRemotePerformanceProfile(
      resolutionTier: resolutionTier ?? user.remoteResolutionSelection,
      fps: fps ?? user.remoteFpsSelection,
    );
    setState(() {});
    showToast(
        '${translate('Remote experience updated')}: ${user.remoteQualityLabel}');
  }

  Widget _remotePerformancePanel(BuildContext context) {
    unawaited(_syncMemberEntitlementFromDisk());
    final user = gFFI.userModel;
    final isMember = user.isMember.value;
    final resolution = user.remoteResolutionSelection;
    final fps = user.remoteFpsSelection;
    return _referenceCard(
      // kq-v216-account-remote-experience-card
      // kq-designer-account-performance-right
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _referenceSectionTitle(
            icon: Icons.desktop_windows_outlined,
            title: _kqSettingText('远控体验', 'Remote experience'),
          ),
          const SizedBox(height: 16),
          _referenceOptionRow(
            title: _kqSettingText('分辨率', 'Resolution'),
            children: [
              _referencePillOption(
                context,
                icon: Icons.desktop_windows_outlined,
                label: '720p',
                selected: resolution == UserModel.remoteResolution720p,
                enabled: true,
                onTap: () => _saveRemotePerformance(
                  resolutionTier: UserModel.remoteResolution720p,
                ),
              ),
              _referencePillOption(
                context,
                icon: Icons.desktop_windows_outlined,
                label: '1080p',
                selected: resolution == UserModel.remoteResolution1080p,
                enabled: isMember,
                locked: !isMember,
                pro: !isMember,
                onTap: () => _saveRemotePerformance(
                  resolutionTier: UserModel.remoteResolution1080p,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _referenceOptionRow(
            title: _kqSettingText('帧率', 'Frame rate'),
            children: [
              _referencePillOption(
                context,
                icon: Icons.speed_rounded,
                label: '30 FPS',
                selected: fps == 30,
                enabled: true,
                onTap: () => _saveRemotePerformance(fps: 30),
              ),
              _referencePillOption(
                context,
                icon: Icons.speed_rounded,
                label: '60 FPS',
                selected: fps == 60,
                enabled: isMember,
                locked: !isMember,
                pro: !isMember,
                onTap: () => _saveRemotePerformance(fps: 60),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _referenceOptionRow({
    required String title,
    required List<Widget> children,
  }) {
    return Builder(builder: (context) {
      final palette = _settingPalette(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          ),
        ],
      );
    });
  }

  Widget _referencePillOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
    bool locked = false,
    bool pro = false,
  }) {
    final palette = _settingPalette(context);
    final foreground = selected
        ? Colors.white
        : enabled
            ? palette.primaryText
            : palette.disabledText;
    return Material(
      // kq-v216-account-pill-option
      // kq-v227-account-remote-performance-dark-colors
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 35,
          constraints: const BoxConstraints(minWidth: 84),
          padding: EdgeInsets.fromLTRB(15, 0, pro ? 10 : 15, 0),
          decoration: BoxDecoration(
            color: selected ? _kqDesignerBlue : palette.fieldFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _kqDesignerBlue : palette.fieldBorder,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _kqDesignerBlue.withOpacity(0.24),
                      blurRadius: 9,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(locked && !enabled ? Icons.lock_outline_rounded : icon,
                  size: 14, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              if (pro) ...[
                const SizedBox(width: 8),
                const Text(
                  'PRO',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _remoteOptionGroup(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.46),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            const gap = 8.0;
            final columns =
                children.length >= 3 && constraints.maxWidth >= 420 ? 3 : 2;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: children
                  .map((child) => SizedBox(width: width, child: child))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _remoteOptionButton(
    BuildContext context, {
    required String label,
    required String caption,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
    bool locked = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.primary
        : Theme.of(context).textTheme.bodyMedium?.color ?? colors.onSurface;
    final borderColor = selected
        ? colors.primary.withOpacity(0.62)
        : Theme.of(context).dividerColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withOpacity(0.10)
                : colors.surface.withOpacity(enabled ? 1 : 0.42),
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
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
                        color: enabled ? foreground : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                locked
                    ? Icons.lock_outline
                    : selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                color: locked
                    ? colors.onSurfaceVariant
                    : selected
                        ? colors.primary
                        : colors.outline,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              translate('Account actions'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: logOutConfirmDialog,
            icon: const Icon(Icons.logout, size: 16),
            label: Text(translate('Logout')),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMemberRechargeDialog() async {
    final user = gFFI.userModel;
    if (!user.isLogin || !user.hasMemberApiCredential) {
      showToast(translate('Please log in to your Kunqiong account first'));
      return;
    }
    if (user.memberPackages.isEmpty) {
      await user.refreshMembership(showError: true);
    }
    final packages = user.memberPackages.toList();
    if (packages.isEmpty) {
      showToast(translate('No purchasable membership packages available'));
      return;
    }
    if (!mounted) return;

    KqMemberPackage selectedPackage = packages.first;
    int payType = 1;
    KqMemberOrder? order;
    bool creatingOrder = false;
    bool dialogAlive = true;
    String statusText = '';
    bool statusIsError = false;
    Timer? pollTimer;

    Future<void> openAlipayCheckout(KqMemberOrder order) async {
      if (order.alipaySubmitHtml.trim().isEmpty) {
        return;
      }
      final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}kq_member_${order.orderNo}.html');
      await file.writeAsString(order.alipaySubmitHtml, encoding: utf8);
      await launchUrl(file.uri, mode: LaunchMode.externalApplication);
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void startPolling(KqMemberOrder nextOrder) {
              pollTimer?.cancel();
              var tick = 0;
              pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
                tick += 1;
                if (tick > 60) {
                  timer.cancel();
                  if (dialogAlive) {
                    setDialogState(() {
                      statusText = translate(
                          'Payment status timed out. Refresh benefits later.');
                      statusIsError = false;
                    });
                  }
                  return;
                }
                unawaited(() async {
                  try {
                    final status =
                        await user.checkMemberOrder(nextOrder.orderNo);
                    if (!dialogAlive) return;
                    if (status.isPaid) {
                      timer.cancel();
                      await user.refreshMembership();
                      if (!dialogAlive) return;
                      setDialogState(() {
                        statusText = translate(
                            'Payment successful. Membership benefits refreshed.');
                        statusIsError = false;
                      });
                      Navigator.of(dialogContext).pop();
                      showToast(translate('Membership benefits active'));
                    } else {
                      setDialogState(() {
                        statusText =
                            translate('Waiting for payment confirmation...');
                        statusIsError = false;
                      });
                    }
                  } catch (e) {
                    if (dialogAlive) {
                      setDialogState(() {
                        statusText = e.toString();
                        statusIsError = true;
                      });
                    }
                  }
                }());
              });
            }

            Future<void> createOrder() async {
              if (creatingOrder) return;
              setDialogState(() {
                creatingOrder = true;
                order = null;
                statusText = translate('Creating order...');
                statusIsError = false;
              });
              try {
                final nextOrder = await user.createMemberOrder(
                  packageId: selectedPackage.id,
                  payType: payType,
                );
                if (!dialogAlive) return;
                setDialogState(() {
                  order = nextOrder;
                  statusText = payType == 1
                      ? translate('Scan with WeChat to pay')
                      : translate('Alipay cashier opened');
                  statusIsError = false;
                });
                if (payType == 2) {
                  await openAlipayCheckout(nextOrder);
                }
                startPolling(nextOrder);
              } catch (e) {
                if (!dialogAlive) return;
                setDialogState(() {
                  statusText = e.toString();
                  statusIsError = true;
                });
                showToast(e.toString());
              } finally {
                if (dialogAlive) {
                  setDialogState(() => creatingOrder = false);
                }
              }
            }

            final colors = Theme.of(context).colorScheme;
            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.workspace_premium_outlined,
                        color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      translate('Upgrade Kunqiong Membership'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate(
                            'Membership unlocks 1080p / 60 FPS. Free users keep 720p / 30 FPS.'),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: packages
                            .map(
                              (item) => _memberPackageTile(
                                context,
                                package: item,
                                selected: item.id == selectedPackage.id,
                                onTap: () => setDialogState(() {
                                  selectedPackage = item;
                                  order = null;
                                  statusText = '';
                                  statusIsError = false;
                                  pollTimer?.cancel();
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            translate('Payment method'),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _memberPaymentMethodChip(
                            context,
                            selected: payType == 1,
                            icon: Icons.qr_code_2,
                            label: translate('WeChat QR'),
                            onTap: () => setDialogState(() {
                              payType = 1;
                              order = null;
                              statusText = '';
                              statusIsError = false;
                              pollTimer?.cancel();
                            }),
                          ),
                          const SizedBox(width: 8),
                          _memberPaymentMethodChip(
                            context,
                            selected: payType == 2,
                            icon: Icons.open_in_browser,
                            label: translate('Alipay'),
                            onTap: () => setDialogState(() {
                              payType = 2;
                              order = null;
                              statusText = '';
                              statusIsError = false;
                              pollTimer?.cancel();
                            }),
                          ),
                        ],
                      ),
                      if (order != null) ...[
                        const SizedBox(height: 16),
                        _memberOrderPanel(context, order!),
                      ],
                      if (statusText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          statusText,
                          style: TextStyle(
                            color:
                                statusIsError ? colors.error : colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(translate('Close')),
                ),
                FilledButton.icon(
                  onPressed: creatingOrder ? null : createOrder,
                  icon: creatingOrder
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment, size: 16),
                  label: Text(creatingOrder
                      ? translate('Creating')
                      : translate('Create payment order')),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      dialogAlive = false;
      pollTimer?.cancel();
    });
  }

  Widget _memberPaymentMethodChip(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    // kq-v232-member-payment-method-selected-contrast
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withOpacity(0.14)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.primary : Theme.of(context).dividerColor,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.primary.withOpacity(0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: colors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberPackageTile(
    BuildContext context, {
    required KqMemberPackage package,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 128,
        height: 126,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withOpacity(0.12)
              : colors.surfaceContainerHighest,
          border: Border.all(
            color: selected
                ? colors.primary.withOpacity(0.62)
                : Theme.of(context).dividerColor,
            width: selected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 17, color: colors.primary),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              package.priceLabel,
              style: TextStyle(
                color: colors.primary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              package.durationLabel,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              package.displayBenefitText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberOrderPanel(BuildContext context, KqMemberOrder order) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.primary.withOpacity(0.20)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 150,
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _memberOrderPayCode(order),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.displayPackageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${translate('Order No.')} ${order.orderNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${translate('Amount due')} ¥${order.payAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  order.payType == 1
                      ? translate(
                          'Benefits will be confirmed automatically after WeChat payment')
                      : translate(
                          'Please complete the payment on the opened Alipay page'),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberOrderPayCode(KqMemberOrder order) {
    final image = order.qrcodeImgUrl.trim();
    if (image.startsWith('data:image')) {
      final comma = image.indexOf(',');
      if (comma > 0) {
        try {
          return Image.memory(
            base64Decode(image.substring(comma + 1)),
            width: 132,
            height: 132,
            fit: BoxFit.contain,
          );
        } catch (_) {
          // Fallback to generated QR code below.
        }
      }
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(
        image,
        width: 132,
        height: 132,
        fit: BoxFit.contain,
      );
    }
    if (order.codeUrl.trim().isNotEmpty) {
      return QrImageView(
        data: order.codeUrl.trim(),
        version: QrVersions.auto,
        size: 132,
      );
    }
    return const Icon(Icons.open_in_browser, size: 46);
  }

  Widget _buildUserAvatar(BuildContext context) {
    final avatar =
        bind.mainResolveAvatarUrl(avatar: gFFI.userModel.avatar.value);
    final fallback = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: 36,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    return buildAvatarWidget(
          avatar: avatar,
          size: 64,
          fallback: fallback,
        ) ??
        fallback;
  }

  Widget _membershipBadge(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isMember = gFFI.userModel.isMember.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isMember ? colors.primary : colors.secondary).withOpacity(0.10),
        border: Border.all(
          color:
              (isMember ? colors.primary : colors.secondary).withOpacity(0.22),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMember
                ? Icons.workspace_premium_outlined
                : Icons.lock_outline_rounded,
            size: 15,
            color: isMember ? colors.primary : colors.secondary,
          ),
          const SizedBox(width: 5),
          Text(
            gFFI.userModel.membershipName,
            style: TextStyle(
              color: isMember ? colors.primary : colors.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _metricTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String caption,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String label, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: colors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Checkbox extends StatefulWidget {
  final String label;
  final bool Function() getValue;
  final Future<void> Function(bool) setValue;

  const _Checkbox(
      {Key? key,
      required this.label,
      required this.getValue,
      required this.setValue})
      : super(key: key);

  @override
  State<_Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<_Checkbox> {
  var value = false;

  @override
  initState() {
    super.initState();
    value = widget.getValue();
  }

  @override
  Widget build(BuildContext context) {
    onChanged(bool b) async {
      await widget.setValue(b);
      setState(() {
        value = widget.getValue();
      });
    }

    return GestureDetector(
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (_) => onChanged(!value),
          ).marginOnly(right: 5),
          Expanded(
            child: Text(translate(widget.label)),
          )
        ],
      ).marginOnly(left: _kCheckBoxLeftMargin),
      onTap: () => onChanged(!value),
    );
  }
}

class _Plugin extends StatefulWidget {
  const _Plugin({Key? key}) : super(key: key);

  @override
  State<_Plugin> createState() => _PluginState();
}

class _PluginState extends State<_Plugin> {
  @override
  Widget build(BuildContext context) {
    bind.pluginListReload();
    final scrollController = ScrollController();
    return ChangeNotifierProvider.value(
      value: pluginManager,
      child: Consumer<PluginManager>(builder: (context, model, child) {
        return ListView(
          controller: scrollController,
          children: model.plugins.map((entry) => pluginCard(entry)).toList(),
        ).marginOnly(bottom: _kListViewBottomMargin);
      }),
    );
  }

  Widget pluginCard(PluginInfo plugin) {
    return ChangeNotifierProvider.value(
      value: plugin,
      child: Consumer<PluginInfo>(
        builder: (context, model, child) => DesktopSettingsCard(plugin: model),
      ),
    );
  }

  Widget accountAction() {
    return Obx(() => _Button(
        gFFI.userModel.userName.value.isEmpty
            ? 'Login'
            : '${translate('Logout')} (${gFFI.userModel.accountLabelWithHandle})',
        () => {
              gFFI.userModel.userName.value.isEmpty
                  ? loginDialog()
                  : logOutConfirmDialog()
            }));
  }
}

class _Printer extends StatefulWidget {
  const _Printer({super.key});

  @override
  State<_Printer> createState() => __PrinterState();
}

class __PrinterState extends State<_Printer> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      outgoing(context),
      incoming(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget outgoing(BuildContext context) {
    final isSupportPrinterDriver =
        bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true';

    Widget tipOsNotSupported() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-os-requirement-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipClientNotInstalled() {
      return Align(
        alignment: Alignment.topLeft,
        child:
            Text(translate('printer-requires-installed-{$appName}-client-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipPrinterNotInstalled() {
      final failedMsg = ''.obs;
      platformFFI.registerEventHandler(
          'install-printer-res', 'install-printer-res', (evt) async {
        if (evt['success'] as bool) {
          setState(() {});
        } else {
          failedMsg.value = evt['msg'] as String;
        }
      }, replace: true);
      return Column(children: [
        Obx(
          () => failedMsg.value.isNotEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(translate('printer-{$appName}-not-installed-tip'))
                      .marginOnly(bottom: 10.0),
                ),
        ),
        Obx(
          () => failedMsg.value.isEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(failedMsg.value,
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(color: Colors.red))
                      .marginOnly(bottom: 10.0)),
        ),
        _Button('Install {$appName} Printer', () {
          failedMsg.value = '';
          bind.mainSetCommon(key: 'install-printer', value: '');
        })
      ]).marginOnly(left: _kCardLeftMargin, bottom: 2.0);
    }

    Widget tipReady() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-{$appName}-ready-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    final installed = bind.mainIsInstalled();
    // `is-printer-installed` may fail, but it's rare case.
    // Add additional error message here if it's really needed.
    final isPrinterInstalled =
        bind.mainGetCommonSync(key: 'is-printer-installed') == 'true';

    final List<Widget> children = [];
    if (!isSupportPrinterDriver) {
      children.add(tipOsNotSupported());
    } else {
      children.addAll([
        if (!installed) tipClientNotInstalled(),
        if (installed && !isPrinterInstalled) tipPrinterNotInstalled(),
        if (installed && isPrinterInstalled) tipReady()
      ]);
    }
    return _Card(title: 'Outgoing Print Jobs', children: children);
  }

  Widget incoming(BuildContext context) {
    onRadioChanged(String value) async {
      await bind.mainSetLocalOption(
          key: kKeyPrinterIncomingJobAction, value: value);
      setState(() {});
    }

    PrinterOptions printerOptions = PrinterOptions.load();
    return _Card(title: 'Incoming Print Jobs', children: [
      _Radio(context,
          value: kValuePrinterIncomingJobDismiss,
          groupValue: printerOptions.action,
          label: 'Dismiss',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobDefault,
          groupValue: printerOptions.action,
          label: 'use-the-default-printer-tip',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobSelected,
          groupValue: printerOptions.action,
          label: 'use-the-selected-printer-tip',
          onChanged: onRadioChanged),
      if (printerOptions.printerNames.isNotEmpty)
        ComboBox(
          initialKey: printerOptions.printerName,
          keys: printerOptions.printerNames,
          values: printerOptions.printerNames,
          enabled: printerOptions.action == kValuePrinterIncomingJobSelected,
          onChanged: (value) async {
            await bind.mainSetLocalOption(
                key: kKeyPrinterSelected, value: value);
            setState(() {});
          },
        ).marginOnly(left: 10),
      _OptionCheckBox(
        context,
        'auto-print-tip',
        kKeyPrinterAllowAutoPrint,
        isServer: false,
        enabled: printerOptions.action != kValuePrinterIncomingJobDismiss,
      )
    ]);
  }
}

class _About extends StatefulWidget {
  const _About({Key? key}) : super(key: key);

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  static final Uri _companyWebsite = Uri.parse('https://kunqiongai.com/');
  static final Uri _downloadWebsite =
      Uri.parse('https://remotelink.kunqiongai.com/kq-api/download');

  @override
  Widget build(BuildContext context) {
    return futureBuilder(future: () async {
      final version = await bind.mainGetVersion();
      final buildDate = await bind.mainGetBuildDate();
      return {
        'version': version,
        'buildDate': buildDate,
      };
    }(), hasData: (data) {
      final version = data['version'].toString();
      final buildDate = data['buildDate'].toString();
      return _SettingsReferencePage(
        marker: 'kq-v218-settings-about-page',
        children: [
          _aboutHero(version),
          _SettingsReferenceCard(
            icon: Icons.article_outlined,
            title: _kqSettingText('软件信息', 'Software information'),
            child: Column(
              children: [
                _aboutInfoRow(
                    _kqSettingText('软件名称', 'Software name'),
                    _kqSettingText(
                        '鲲穹远程桌面 桌面端', 'Kunqiong Remote Desktop for desktop')),
                _settingsReferenceDivider(),
                _aboutInfoRow('Version', 'v$version (Build $buildDate)'),
                _settingsReferenceDivider(),
                _aboutInfoRow(
                  _kqSettingText('运行环境', 'Runtime environment'),
                  isWindows
                      ? 'Windows 10 / 11 (x64)'
                      : Platform.operatingSystem,
                ),
                _settingsReferenceDivider(),
                _aboutInfoRow(_kqSettingText('许可证', 'License'),
                    _kqSettingText('个人免费版', 'Personal free edition')),
              ],
            ),
          ),
          _SettingsReferenceCard(
            icon: Icons.update_rounded,
            title: _kqSettingText('更新', 'Updates'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kqSettingText(
                            '当前已是最新版本', 'You are on the latest version'),
                        style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_kqSettingText('上次检查', 'Last checked')}: ${DateTime.now().toString().substring(0, 16)}',
                        style: TextStyle(
                          color: _settingsDesignerTextSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => launchUrl(
                    _downloadWebsite,
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(_kqSettingText('检查更新', 'Check for updates')),
                ),
              ],
            ),
          ),
          _SettingsReferenceCard(
            icon: Icons.open_in_new_rounded,
            title: _kqSettingText('链接', 'Links'),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _aboutLink(_kqSettingText('官方网站', 'Official website'),
                    _companyWebsite),
                _aboutLink(
                    _kqSettingText('帮助文档', 'Help docs'), _companyWebsite),
                _aboutLink(_kqSettingText('意见反馈', 'Feedback'), _companyWebsite),
                _aboutLink(
                    _kqSettingText('隐私政策', 'Privacy policy'), _companyWebsite),
              ],
            ),
          ),
          Center(
            child: Text(
              '${_kqSettingText('鲲穹远程桌面', 'Kunqiong Remote Desktop')} v$version',
              style: TextStyle(
                color: _settingsDesignerTextSecondary(context),
                fontSize: 12,
              ),
            ),
          ).marginOnly(top: 6),
        ],
      );
    });
  }

  Widget _aboutHero(String version) {
    final palette = _settingPalette(context);
    return Container(
      // kq-v227-about-page-dark-colors
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: _settingsDesignerBlueSurface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kqDesignerBlue,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _kqDesignerBlue.withOpacity(0.24),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Image.asset(
              'assets/kq_about_logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kqSettingText('鲲穹远程桌面', 'Kunqiong Remote Desktop'),
                  style: TextStyle(
                    color: palette.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      '${_kqSettingText('版本', 'Version')} $version',
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9FFF3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _kqSettingText('最新', 'Latest'),
                        style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _kqSettingText('安全、快速、高清的远程桌面解决方案',
                      'Secure, fast, and HD remote desktop solution'),
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutInfoRow(String label, String value) {
    final palette = _settingPalette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              translate(label),
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: palette.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutLink(String label, Uri uri) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: _kqDesignerBlue,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
//#endregion

//#region components

// ignore: non_constant_identifier_names
Widget _Card(
    {required String title,
    required List<Widget> children,
    List<Widget>? title_suffix}) {
  return Builder(builder: (context) {
    final palette = _settingPalette(context);
    return Row(
      children: [
        Flexible(
          child: SizedBox(
            width: _kCardFixedWidth,
            child: Container(
              margin: const EdgeInsets.only(left: _kCardLeftMargin, top: 15),
              decoration: BoxDecoration(
                // kq-settings-reference-card
                color: palette.cardBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 42),
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kContentHMargin,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.cardHeaderBackground,
                      border: Border(
                        bottom: BorderSide(color: palette.cardBorder),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            translate(title),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              color: palette.primaryText,
                              fontSize: _kContentFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...?title_suffix
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 10,
                    ),
                    child: Column(
                      children: children
                          .map((e) => e.marginOnly(
                                top: 4,
                                right: _kContentHMargin,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  });
}

class _FoldoutCard extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _FoldoutCard({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<_FoldoutCard> createState() => _FoldoutCardState();
}

class _FoldoutCardState extends State<_FoldoutCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final palette = _settingPalette(context);
    return Row(
      children: [
        Flexible(
          child: SizedBox(
            width: _kCardFixedWidth,
            child: Container(
              margin: const EdgeInsets.only(left: _kCardLeftMargin, top: 15),
              decoration: BoxDecoration(
                // kq-settings-reference-card
                color: palette.cardBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Material(
                    color: palette.cardHeaderBackground,
                    child: InkWell(
                      hoverColor: palette.navHoverBackground,
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kContentHMargin,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: palette.cardBorder),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                translate(widget.title),
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: palette.primaryText,
                                  fontSize: _kContentFontSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.expand_more_rounded,
                                color: palette.navSelectedText,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 10),
                            child: Column(
                              children: widget.children
                                  .map((e) => e.marginOnly(
                                        top: 4,
                                        right: _kContentHMargin,
                                      ))
                                  .toList(),
                            ),
                          )
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _SettingSectionTitle(BuildContext context, String title) {
  final palette = _settingPalette(context);
  return Padding(
    padding: const EdgeInsets.only(
      left: _kContentHMargin,
      top: 6,
      bottom: 2,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        translate(title),
        style: TextStyle(
          color: palette.mutedText,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

Widget _SettingSectionDivider(BuildContext context) {
  final palette = _settingPalette(context);
  return Divider(
    height: 18,
    thickness: 1,
    color: palette.cardBorder.withOpacity(0.72),
    indent: _kContentHMargin,
  );
}

class _PostInstallPermissionActions extends StatefulWidget {
  final bool enabled;

  const _PostInstallPermissionActions({required this.enabled});

  @override
  State<_PostInstallPermissionActions> createState() =>
      _PostInstallPermissionActionsState();
}

class _PostInstallPermissionActionsState
    extends State<_PostInstallPermissionActions> {
  bool _startingService = false;
  bool _repairingFirewall = false;
  bool _registeringBrowserProtocol = false;
  bool _applyingRecommended = false;

  Future<void> _runAction(
      Future<void> Function() action, void Function(bool) setBusy) async {
    if (!widget.enabled) return;
    setState(() => setBusy(true));
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => setBusy(false));
      }
    }
  }

  Future<void> _startBackgroundService() async {
    await _runAction(() async {
      await bind.mainStartService();
      await mainSetBoolOption(kOptionStopService, false);
      showToast(_kqSettingText('已发起后台服务安装，请在系统授权弹窗中确认。',
          'Background service setup started. Please confirm in the system authorization prompt.'));
    }, (value) => _startingService = value);
  }

  Future<void> _repairFirewall() async {
    await _runAction(() async {
      final result = await repairKqFirewallRules();
      showToast(result.message);
    }, (value) => _repairingFirewall = value);
  }

  Future<void> _registerBrowserRemoteProtocol() async {
    await _runAction(() async {
      final result = await registerKqBrowserRemoteProtocols();
      showToast(result.message);
    }, (value) => _registeringBrowserProtocol = value);
  }

  Future<void> _applyRecommendedPermissions() async {
    await _runAction(() async {
      await bind.mainSetOption(
          key: kOptionEnablePermChangeInAcceptWindow, value: 'Y');
      await bind.mainSetOption(
          key: kOptionAllowRemoteConfigModification, value: 'N');
      showToast(_kqSettingText(
          '已应用推荐远控权限。', 'Recommended remote-control permissions applied.'));
    }, (value) => _applyingRecommended = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _settingPalette(context);
    final bodyColor =
        widget.enabled ? palette.primaryText : palette.disabledText;
    return Container(
      // kq-post-install-permission-actions
      margin: const EdgeInsets.only(left: _kContentHMargin, top: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.fieldFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.fieldBorder.withOpacity(0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _kqSettingText('安装后授权 / 连接增强',
                'Post-install authorization / connection enhancements'),
            style: TextStyle(
              color: bodyColor,
              fontSize: _kContentFontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _kqSettingText('用户主动点击后才会触发系统授权或修复；低误报安装包不会静默安装服务或改防火墙。',
                'System authorization or repair only starts after the user clicks. Low false-positive installers do not silently install services or change firewall rules.'),
            style: TextStyle(
              color: widget.enabled ? palette.mutedText : palette.disabledText,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _PostInstallActionButton(
            label: _kqSettingText('启用后台服务', 'Enable background service'),
            icon: Icons.admin_panel_settings_outlined,
            busy: _startingService,
            enabled: widget.enabled,
            onPressed: _startBackgroundService,
          ),
          const SizedBox(height: 8),
          _PostInstallActionButton(
            label: _kqSettingText('修复防火墙规则', 'Repair firewall rules'),
            icon: Icons.security_update_good_outlined,
            busy: _repairingFirewall,
            enabled: widget.enabled,
            onPressed: _repairFirewall,
          ),
          const SizedBox(height: 8),
          _PostInstallActionButton(
            label: _kqSettingText('浏览器远控入口', 'Browser remote-control entry'),
            icon: Icons.link_rounded,
            busy: _registeringBrowserProtocol,
            enabled: widget.enabled,
            onPressed: _registerBrowserRemoteProtocol,
          ),
          const SizedBox(height: 8),
          _PostInstallActionButton(
            label: _kqSettingText(
                '应用推荐被控权限', 'Apply recommended controlled-side permissions'),
            icon: Icons.verified_user_outlined,
            busy: _applyingRecommended,
            enabled: widget.enabled,
            onPressed: _applyRecommendedPermissions,
          ),
        ],
      ),
    );
  }
}

class _PostInstallActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final bool enabled;
  final Future<void> Function() onPressed;

  const _PostInstallActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !busy;
    return OutlinedButton.icon(
      onPressed: canTap ? onPressed : null,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(label),
      ),
    );
  }
}

// ignore: non_constant_identifier_names
Widget _OptionCheckBox(
  BuildContext context,
  String label,
  String key, {
  Function(bool)? update,
  bool reverse = false,
  bool enabled = true,
  Icon? checkedIcon,
  bool? fakeValue,
  bool isServer = true,
  bool Function()? optGetter,
  Future<void> Function(String, bool)? optSetter,
}) {
  getOpt() => optGetter != null
      ? optGetter()
      : (isServer
          ? mainGetBoolOptionSync(key)
          : mainGetLocalBoolOptionSync(key));
  bool value = getOpt();
  final isOptFixed = isOptionFixed(key);
  if (reverse) value = !value;
  var ref = value.obs;
  onChanged(option) async {
    if (option != null) {
      if (reverse) option = !option;
      final setter =
          optSetter ?? (isServer ? mainSetBoolOption : mainSetLocalBoolOption);
      await setter(key, option);
      final readOption = getOpt();
      if (reverse) {
        ref.value = !readOption;
      } else {
        ref.value = readOption;
      }
      update?.call(readOption);
    }
  }

  if (fakeValue != null) {
    ref.value = fakeValue;
    enabled = false;
  }

  final palette = _settingPalette(context);
  final canChange = enabled && !isOptFixed;
  return Obx(
    () => Padding(
      padding: const EdgeInsets.only(left: _kCheckBoxLeftMargin),
      child: Material(
        color: ref.value
            ? _accentColor.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: canChange ? palette.navHoverBackground : null,
          onTap: canChange
              ? () {
                  onChanged(!ref.value);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Checkbox(
                        value: ref.value,
                        onChanged: canChange ? onChanged : null)
                    .marginOnly(right: 6),
                Offstage(
                  offstage: !ref.value || checkedIcon == null,
                  child: checkedIcon?.marginOnly(right: 6),
                ),
                Expanded(
                  child: Text(
                    translate(label),
                    style: TextStyle(
                      color: canChange
                          ? palette.primaryText
                          : palette.disabledText,
                      fontSize: _kContentFontSize,
                      fontWeight: ref.value ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ignore: non_constant_identifier_names
Widget _Radio<T>(BuildContext context,
    {required T value,
    required T groupValue,
    required String label,
    required Function(T value)? onChanged,
    bool autoNewLine = true}) {
  final onChange2 = onChanged != null
      ? (T? value) {
          if (value != null) {
            onChanged(value);
          }
        }
      : null;
  final palette = _settingPalette(context);
  final selected = value == groupValue;
  return Padding(
    padding: const EdgeInsets.only(left: _kRadioLeftMargin),
    child: Material(
      color: selected
          ? _accentColor.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: onChange2 != null ? palette.navHoverBackground : null,
        onTap: () => onChange2?.call(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Radio<T>(
                value: value,
                groupValue: groupValue,
                onChanged: onChange2,
              ),
              Expanded(
                child: Text(
                  translate(label),
                  overflow: autoNewLine ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _kContentFontSize,
                    color: onChange2 != null
                        ? palette.primaryText
                        : palette.disabledText,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ).marginOnly(left: 5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class WaylandCard extends StatefulWidget {
  const WaylandCard({Key? key}) : super(key: key);

  @override
  State<WaylandCard> createState() => _WaylandCardState();
}

class _WaylandCardState extends State<WaylandCard> {
  final restoreTokenKey = 'wayland-restore-token';
  static const _kClearShortcutsInhibitorEventKey =
      'clear-gnome-shortcuts-inhibitor-permission-res';
  final _clearShortcutsInhibitorFailedMsg = ''.obs;
  // Don't show the shortcuts permission reset button for now.
  // Users can change it manually:
  //   "Settings" -> "Apps" -> "RustDesk" -> "Permissions" -> "Inhibit Shortcuts".
  // For resetting(clearing) the permission from the portal permission store, you can
  // use (replace <desktop-id> with the RustDesk desktop file ID):
  //   busctl --user call org.freedesktop.impl.portal.PermissionStore \
  //   /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore \
  //   DeletePermission sss "gnome" "shortcuts-inhibitor" "<desktop-id>"
  // On a native install this is typically "rustdesk.desktop"; on Flatpak it is usually
  // the exported desktop ID derived from the Flatpak app-id (e.g. "com.rustdesk.RustDesk.desktop").
  //
  // We may add it back in the future if needed.
  final showResetInhibitorPermission = false;

  @override
  void initState() {
    super.initState();
    if (showResetInhibitorPermission) {
      platformFFI.registerEventHandler(
          _kClearShortcutsInhibitorEventKey, _kClearShortcutsInhibitorEventKey,
          (evt) async {
        if (!mounted) return;
        if (evt['success'] == true) {
          setState(() {});
        } else {
          _clearShortcutsInhibitorFailedMsg.value =
              evt['msg'] as String? ?? 'Unknown error';
        }
      });
    }
  }

  @override
  void dispose() {
    if (showResetInhibitorPermission) {
      platformFFI.unregisterEventHandler(
          _kClearShortcutsInhibitorEventKey, _kClearShortcutsInhibitorEventKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return futureBuilder(
      future: bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "get"),
      hasData: (restoreToken) {
        final hasShortcutsPermission = showResetInhibitorPermission &&
            bind.mainGetCommonSync(
                    key: "has-gnome-shortcuts-inhibitor-permission") ==
                "true";

        final children = [
          if (restoreToken.isNotEmpty)
            _buildClearScreenSelection(context, restoreToken),
          if (hasShortcutsPermission)
            _buildClearShortcutsInhibitorPermission(context),
        ];
        return Offstage(
          offstage: children.isEmpty,
          child: _Card(title: 'Wayland', children: children),
        );
      },
    );
  }

  Widget _buildClearScreenSelection(BuildContext context, String restoreToken) {
    onConfirm() async {
      final msg = await bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "clear");
      gFFI.dialogManager.dismissAll();
      if (msg.isNotEmpty) {
        msgBox(gFFI.sessionId, 'custom-nocancel', 'Error', msg, '',
            gFFI.dialogManager);
      } else {
        setState(() {});
      }
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm_clear_Wayland_screen_selection_tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return _Button(
      'Clear Wayland screen selection',
      showConfirmMsgBox,
      tip: 'clear_Wayland_screen_selection_tip',
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all<Color>(
            Theme.of(context).colorScheme.error.withOpacity(0.75)),
      ),
    );
  }

  Widget _buildClearShortcutsInhibitorPermission(BuildContext context) {
    onConfirm() {
      _clearShortcutsInhibitorFailedMsg.value = '';
      bind.mainSetCommon(
          key: "clear-gnome-shortcuts-inhibitor-permission", value: "");
      gFFI.dialogManager.dismissAll();
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm-clear-shortcuts-inhibitor-permission-tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return Column(children: [
      Obx(
        () => _clearShortcutsInhibitorFailedMsg.value.isEmpty
            ? Offstage()
            : Align(
                alignment: Alignment.topLeft,
                child: Text(_clearShortcutsInhibitorFailedMsg.value,
                        style: DefaultTextStyle.of(context)
                            .style
                            .copyWith(color: Colors.red))
                    .marginOnly(bottom: 10.0)),
      ),
      _Button(
        'Reset keyboard shortcuts permission',
        showConfirmMsgBox,
        tip: 'clear-shortcuts-inhibitor-permission-tip',
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all<Color>(
              Theme.of(context).colorScheme.error.withOpacity(0.75)),
        ),
      ),
    ]);
  }
}

// ignore: non_constant_identifier_names
Widget _Button(String label, Function() onPressed,
    {bool enabled = true, String? tip, ButtonStyle? style}) {
  var button = ElevatedButton(
    onPressed: enabled ? onPressed : null,
    child: Text(
      translate(label),
    ).marginSymmetric(horizontal: 15),
    style: style,
  );
  StatefulWidget child;
  if (tip == null) {
    child = button;
  } else {
    child = Tooltip(message: translate(tip), child: button);
  }
  return Row(children: [
    child,
  ]).marginOnly(left: _kContentHMargin);
}

// ignore: non_constant_identifier_names
Widget _SubLabeledWidget(BuildContext context, String label, Widget child,
    {bool enabled = true}) {
  return Row(
    children: [
      Text(
        '${translate(label)}: ',
        style: TextStyle(color: disabledTextColor(context, enabled)),
      ),
      SizedBox(
        width: 10,
      ),
      child,
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

Widget _lock(
  bool locked,
  String label,
  Function() onUnlock,
) {
  return Offstage(
      offstage: !locked,
      child: Row(
        children: [
          Flexible(
            child: SizedBox(
              width: _kCardFixedWidth,
              child: Card(
                child: ElevatedButton(
                  child: SizedBox(
                      height: 25,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.security_sharp,
                              size: 20,
                            ),
                            Text(translate(label)).marginOnly(left: 5),
                          ]).marginSymmetric(vertical: 2)),
                  onPressed: () async {
                    final unlockPin = bind.mainGetUnlockPin();
                    if (unlockPin.isEmpty || isUnlockPinDisabled()) {
                      bool checked = await callMainCheckSuperUserPermission();
                      if (checked) {
                        onUnlock();
                      }
                    } else {
                      checkUnlockPinDialog(unlockPin, onUnlock);
                    }
                  },
                ).marginSymmetric(horizontal: 2, vertical: 4),
              ).marginOnly(left: _kCardLeftMargin),
            ).marginOnly(top: 10),
          ),
        ],
      ));
}

_LabeledTextField(
    BuildContext context,
    String label,
    TextEditingController controller,
    String errorText,
    bool enabled,
    bool secure) {
  return Table(
    columnWidths: const {
      0: FixedColumnWidth(150),
      1: FlexColumnWidth(),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${translate(label)}:',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                color: disabledTextColor(context, enabled),
              ),
            ),
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: secure,
            autocorrect: false,
            decoration: InputDecoration(
              errorText: errorText.isNotEmpty ? errorText : null,
            ),
            style: TextStyle(
              color: disabledTextColor(context, enabled),
            ),
          ).workaroundFreezeLinuxMint(),
        ],
      ),
    ],
  ).marginOnly(bottom: 8);
}

class _CountDownButton extends StatefulWidget {
  _CountDownButton({
    Key? key,
    required this.text,
    required this.second,
    required this.onPressed,
  }) : super(key: key);
  final String text;
  final VoidCallback? onPressed;
  final int second;

  @override
  State<_CountDownButton> createState() => _CountDownButtonState();
}

class _CountDownButtonState extends State<_CountDownButton> {
  bool _isButtonDisabled = false;

  late int _countdownSeconds = widget.second;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdownSeconds <= 0) {
        setState(() {
          _isButtonDisabled = false;
        });
        timer.cancel();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isButtonDisabled
          ? null
          : () {
              widget.onPressed?.call();
              setState(() {
                _isButtonDisabled = true;
                _countdownSeconds = widget.second;
              });
              _startCountdownTimer();
            },
      child: Text(
        _isButtonDisabled ? '$_countdownSeconds s' : translate(widget.text),
      ),
    );
  }
}

//#endregion

//#region dialogs

void changeSocks5Proxy() async {
  var socks = await bind.mainGetSocks();

  String proxy = '';
  String proxyMsg = '';
  String username = '';
  String password = '';
  if (socks.length == 3) {
    proxy = socks[0];
    username = socks[1];
    password = socks[2];
  }
  var proxyController = TextEditingController(text: proxy);
  var userController = TextEditingController(text: username);
  var pwdController = TextEditingController(text: password);
  RxBool obscure = true.obs;

  // proxy settings
  // The following option is a not real key, it is just used for custom client advanced settings.
  const String optionProxyUrl = "proxy-url";
  final isOptFixed = isOptionFixed(optionProxyUrl);

  var isInProgress = false;
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      setState(() {
        proxyMsg = '';
        isInProgress = true;
      });
      cancel() {
        setState(() {
          isInProgress = false;
        });
      }

      proxy = proxyController.text.trim();
      username = userController.text.trim();
      password = pwdController.text.trim();

      if (proxy.isNotEmpty) {
        String domainPort = proxy;
        if (domainPort.contains('://')) {
          domainPort = domainPort.split('://')[1];
        }
        proxyMsg = translate(await bind.mainTestIfValidServer(
            server: domainPort, testWithProxy: false));
        if (proxyMsg.isEmpty) {
          // ignore
        } else {
          cancel();
          return;
        }
      }
      await bind.mainSetSocks(
          proxy: proxy, username: username, password: password);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate('Socks5/Http(s) Proxy')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140),
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          children: [
                            Text(
                              translate('Server'),
                            ).marginOnly(right: 4),
                            Tooltip(
                              waitDuration: Duration(milliseconds: 0),
                              message: translate("default_proxy_tip"),
                              child: Icon(
                                Icons.help_outline_outlined,
                                size: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        )).marginOnly(right: 10),
                  ),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      errorText: proxyMsg.isNotEmpty ? proxyMsg : null,
                      labelText: isMobile ? translate('Server') : null,
                      helperText:
                          isMobile ? translate("default_proxy_tip") : null,
                      helperMaxLines: isMobile ? 3 : null,
                    ),
                    controller: proxyController,
                    autofocus: true,
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Username")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: TextField(
                    controller: userController,
                    decoration: InputDecoration(
                      labelText: isMobile ? translate('Username') : null,
                    ),
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Password")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: Obx(() => TextField(
                        obscureText: obscure.value,
                        decoration: InputDecoration(
                            labelText: isMobile ? translate('Password') : null,
                            suffixIcon: IconButton(
                                onPressed: () => obscure.value = !obscure.value,
                                icon: Icon(obscure.value
                                    ? Icons.visibility_off
                                    : Icons.visibility))),
                        controller: pwdController,
                        enabled: !isOptFixed,
                        maxLength: bind.mainMaxEncryptLen(),
                      ).workaroundFreezeLinuxMint()),
                ),
              ],
            ),
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress)
              const LinearProgressIndicator().marginOnly(top: 8),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        if (!isOptFixed) dialogButton('OK', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

//#endregion
