import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../common/kq_theme.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/mobile_platform_capability_policy.dart';
import 'page_shape.dart';
import 'scan_page.dart';

const kqMobileSettingsGroupAppearance = 'Appearance';
const kqMobileSettingsGroupRemoteAccess = 'Remote Access';

class SettingsPage extends StatefulWidget implements PageShape {
  SettingsPage({
    super.key,
    this.showAccountGroup = true,
    this.initialGroupTitle,
    this.singleGroupOnly = false,
    this.detailTitle,
  });

  final bool showAccountGroup;
  final String? initialGroupTitle;
  final bool singleGroupOnly;
  final String? detailTitle;

  @override
  final title = translate("Settings");

  @override
  final icon = Icon(Icons.tune_rounded);

  @override
  final appBarActions = bind.isDisableSettings() ? [] : [ScanButton()];

  @override
  State<SettingsPage> createState() => _SettingsState();
}

const url = 'https://kunqiongai.com/';

enum KeepScreenOn {
  never,
  duringControlled,
  serviceOn,
}

String _keepScreenOnToOption(KeepScreenOn value) {
  switch (value) {
    case KeepScreenOn.never:
      return 'never';
    case KeepScreenOn.duringControlled:
      return 'during-controlled';
    case KeepScreenOn.serviceOn:
      return 'service-on';
  }
}

KeepScreenOn optionToKeepScreenOn(String value) {
  switch (value) {
    case 'never':
      return KeepScreenOn.never;
    case 'service-on':
      return KeepScreenOn.serviceOn;
    default:
      return KeepScreenOn.duringControlled;
  }
}

class _SettingsState extends State<SettingsPage> with WidgetsBindingObserver {
  final _hasIgnoreBattery =
      false; //androidVersion >= 26; // remove because not work on every device
  var _ignoreBatteryOpt = false;
  var _enableStartOnBoot = false;
  var _checkUpdateOnStartup = false;
  var _showTerminalExtraKeys = false;
  var _floatingWindowDisabled = false;
  var _keepScreenOn = KeepScreenOn.duringControlled; // relay on floating window
  var _denyLANDiscovery = false;
  var _onlyWhiteList = false;
  var _enableRecordSession = false;
  var _enableHardwareCodec = false;
  var _autoRecordIncomingSession = false;
  var _autoRecordOutgoingSession = false;
  var _allowAutoDisconnect = false;
  var _fingerprint = "";
  var _buildDate = "";
  var _autoDisconnectTimeout = "";
  var _preventSleepWhileConnected = true;

  _SettingsState() {
    _denyLANDiscovery = !option2bool(kOptionEnableLanDiscovery,
        bind.mainGetOptionSync(key: kOptionEnableLanDiscovery));
    _onlyWhiteList = whitelistNotEmpty();
    _enableRecordSession = option2bool(kOptionEnableRecordSession,
        bind.mainGetOptionSync(key: kOptionEnableRecordSession));
    _enableHardwareCodec = option2bool(kOptionEnableHwcodec,
        bind.mainGetOptionSync(key: kOptionEnableHwcodec));
    _autoRecordIncomingSession = option2bool(kOptionAllowAutoRecordIncoming,
        bind.mainGetOptionSync(key: kOptionAllowAutoRecordIncoming));
    _autoRecordOutgoingSession = option2bool(kOptionAllowAutoRecordOutgoing,
        bind.mainGetLocalOption(key: kOptionAllowAutoRecordOutgoing));
    _allowAutoDisconnect = option2bool(kOptionAllowAutoDisconnect,
        bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
    _autoDisconnectTimeout =
        bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
    _preventSleepWhileConnected =
        mainGetLocalBoolOptionSync(kOptionKeepAwakeDuringOutgoingSessions);
    _showTerminalExtraKeys =
        mainGetLocalBoolOptionSync(kOptionEnableShowTerminalExtraKeys);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var update = false;

      if (_hasIgnoreBattery) {
        if (await checkAndUpdateIgnoreBatteryStatus()) {
          update = true;
        }
      }

      if (await checkAndUpdateStartOnBoot()) {
        update = true;
      }

      // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
      var enableStartOnBoot =
          await gFFI.invokeMethod(AndroidChannel.kGetStartOnBootOpt);
      if (enableStartOnBoot) {
        if (!await canStartOnBoot()) {
          enableStartOnBoot = false;
          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
        }
      }

      if (enableStartOnBoot != _enableStartOnBoot) {
        update = true;
        _enableStartOnBoot = enableStartOnBoot;
      }

      var checkUpdateOnStartup =
          mainGetLocalBoolOptionSync(kOptionEnableCheckUpdate);
      if (checkUpdateOnStartup != _checkUpdateOnStartup) {
        update = true;
        _checkUpdateOnStartup = checkUpdateOnStartup;
      }

      var floatingWindowDisabled =
          bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) == "Y" ||
              !await AndroidPermissionManager.check(kSystemAlertWindow);
      if (floatingWindowDisabled != _floatingWindowDisabled) {
        update = true;
        _floatingWindowDisabled = floatingWindowDisabled;
      }

      final keepScreenOn = _floatingWindowDisabled
          ? KeepScreenOn.never
          : optionToKeepScreenOn(
              bind.mainGetLocalOption(key: kOptionKeepScreenOn));
      if (keepScreenOn != _keepScreenOn) {
        update = true;
        _keepScreenOn = keepScreenOn;
      }

      final fingerprint = await bind.mainGetFingerprint();
      if (_fingerprint != fingerprint) {
        update = true;
        _fingerprint = fingerprint;
      }

      final buildDate = await bind.mainGetBuildDate();
      if (_buildDate != buildDate) {
        update = true;
        _buildDate = buildDate;
      }

      if (update) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      () async {
        final ibs = await checkAndUpdateIgnoreBatteryStatus();
        final sob = await checkAndUpdateStartOnBoot();
        if (ibs || sob) {
          setState(() {});
        }
      }();
    }
  }

  Future<bool> checkAndUpdateIgnoreBatteryStatus() async {
    final res = await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations);
    if (_ignoreBatteryOpt != res) {
      _ignoreBatteryOpt = res;
      return true;
    } else {
      return false;
    }
  }

  Future<bool> checkAndUpdateStartOnBoot() async {
    if (!await canStartOnBoot() && _enableStartOnBoot) {
      _enableStartOnBoot = false;
      debugPrint(
          "checkAndUpdateStartOnBoot and set _enableStartOnBoot -> false");
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
      return true;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      kqMobileLanguageEpoch.value;
      Provider.of<FfiModel>(context);
      final outgoingOnly = bind.isOutgoingOnly();
      final incomingOnly = bind.isIncomingOnly();
      final customClientSection = CustomSettingsSection(
          child: Column(
        children: [
          if (bind.isCustomClient())
            Align(
              alignment: Alignment.center,
              child: loadPowered(context),
            ),
          Align(
            alignment: Alignment.center,
            child: loadLogo(),
          )
        ],
      ));
      final List<AbstractSettingsTile> enhancementsTiles = [];
      final List<AbstractSettingsTile> shareScreenTiles = [
        SettingsTile.switchTile(
          title: Text(_settingsText('Deny LAN discovery')),
          initialValue: _denyLANDiscovery,
          onToggle: isOptionFixed(kOptionEnableLanDiscovery)
              ? null
              : (v) async {
                  await bind.mainSetOption(
                      key: kOptionEnableLanDiscovery,
                      value: bool2option(kOptionEnableLanDiscovery, !v));
                  final newValue = !option2bool(kOptionEnableLanDiscovery,
                      await bind.mainGetOption(key: kOptionEnableLanDiscovery));
                  setState(() {
                    _denyLANDiscovery = newValue;
                  });
                },
        ),
        SettingsTile.switchTile(
          title: Row(children: [
            Expanded(child: Text(_settingsText('Use IP Whitelisting'))),
            Offstage(
                    offstage: !_onlyWhiteList,
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Color.fromARGB(255, 255, 204, 0)))
                .marginOnly(left: 5)
          ]),
          initialValue: _onlyWhiteList,
          onToggle: (_) async {
            update() async {
              final onlyWhiteList = whitelistNotEmpty();
              if (onlyWhiteList != _onlyWhiteList) {
                setState(() {
                  _onlyWhiteList = onlyWhiteList;
                });
              }
            }

            changeWhiteList(callback: update);
          },
        ),
        SettingsTile.switchTile(
          title: Text(_settingsText('Enable recording session')),
          initialValue: _enableRecordSession,
          onToggle: isOptionFixed(kOptionEnableRecordSession)
              ? null
              : (v) async {
                  await mainSetBoolOption(kOptionEnableRecordSession, v);
                  final newValue =
                      await mainGetBoolOption(kOptionEnableRecordSession);
                  setState(() {
                    _enableRecordSession = newValue;
                  });
                },
        ),
        SettingsTile.switchTile(
          title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_settingsText("auto_disconnect_option_tip")),
                      Offstage(
                          offstage: !_allowAutoDisconnect,
                          child: Text(
                            '${_autoDisconnectTimeout.isEmpty ? '10' : _autoDisconnectTimeout} min',
                            style: Theme.of(context).textTheme.bodySmall,
                          )),
                    ])),
                Offstage(
                    offstage: !_allowAutoDisconnect,
                    child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.edit,
                          size: 20,
                        ),
                        onPressed: isOptionFixed(kOptionAutoDisconnectTimeout)
                            ? null
                            : () async {
                                final timeout =
                                    await changeAutoDisconnectTimeout(
                                        _autoDisconnectTimeout);
                                setState(() {
                                  _autoDisconnectTimeout = timeout;
                                });
                              }))
              ]),
          initialValue: _allowAutoDisconnect,
          onToggle: isOptionFixed(kOptionAllowAutoDisconnect)
              ? null
              : (_) async {
                  _allowAutoDisconnect = !_allowAutoDisconnect;
                  String value = bool2option(
                      kOptionAllowAutoDisconnect, _allowAutoDisconnect);
                  await bind.mainSetOption(
                      key: kOptionAllowAutoDisconnect, value: value);
                  setState(() {});
                },
        )
      ];
      if (_hasIgnoreBattery) {
        enhancementsTiles.insert(
            0,
            SettingsTile.switchTile(
                initialValue: _ignoreBatteryOpt,
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_settingsText(
                          'Keep Kunqiong Remote Desktop background service')),
                      Text('* ${_settingsText('Ignore Battery Optimizations')}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                onToggle: (v) async {
                  if (v) {
                    await AndroidPermissionManager.request(
                        kRequestIgnoreBatteryOptimizations);
                  } else {
                    final res = await gFFI.dialogManager.show<bool>(
                        (setState, close, context) => CustomAlertDialog(
                              title: Text(_settingsText("Open System Setting")),
                              content: Text(_settingsText(
                                  "android_open_battery_optimizations_tip")),
                              actions: [
                                dialogButton("Cancel",
                                    onPressed: () => close(), isOutline: true),
                                dialogButton(
                                  "Open System Setting",
                                  onPressed: () => close(true),
                                ),
                              ],
                            ));
                    if (res == true) {
                      AndroidPermissionManager.startAction(
                          kActionApplicationDetailsSettings);
                    }
                  }
                }));
      }
      enhancementsTiles.add(SettingsTile.switchTile(
          initialValue: _enableStartOnBoot,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_settingsText('Start on boot')),
            Text(
                '* ${_settingsText('Start the screen sharing service on boot, requires special permissions')}',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          onToggle: (toValue) async {
            if (toValue) {
              // 1. request kIgnoreBatteryOptimizations
              if (!await AndroidPermissionManager.check(
                  kRequestIgnoreBatteryOptimizations)) {
                if (!await AndroidPermissionManager.request(
                    kRequestIgnoreBatteryOptimizations)) {
                  return;
                }
              }

              // 2. request kSystemAlertWindow
              if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
                if (!await AndroidPermissionManager.request(
                    kSystemAlertWindow)) {
                  return;
                }
              }

              // (Optional) 3. request input permission
            }
            setState(() => _enableStartOnBoot = toValue);

            gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, toValue);
          }));

      if (!bind.isCustomClient()) {
        enhancementsTiles.add(
          SettingsTile.switchTile(
            initialValue: _checkUpdateOnStartup,
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_settingsText('Check for software update on startup')),
            ]),
            onToggle: (bool toValue) async {
              await mainSetLocalBoolOption(kOptionEnableCheckUpdate, toValue);
              setState(() => _checkUpdateOnStartup = toValue);
            },
          ),
        );
      }

      enhancementsTiles.add(
        SettingsTile.switchTile(
          initialValue: _showTerminalExtraKeys,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_settingsText('Show terminal extra keys')),
          ]),
          onToggle: (bool v) async {
            await mainSetLocalBoolOption(kOptionEnableShowTerminalExtraKeys, v);
            final newValue =
                mainGetLocalBoolOptionSync(kOptionEnableShowTerminalExtraKeys);
            setState(() {
              _showTerminalExtraKeys = newValue;
            });
          },
        ),
      );

      onFloatingWindowChanged(bool toValue) async {
        if (toValue) {
          if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
            if (!await AndroidPermissionManager.request(kSystemAlertWindow)) {
              return;
            }
          }
        }
        final disable = !toValue;
        bind.mainSetLocalOption(
            key: kOptionDisableFloatingWindow,
            value: disable ? 'Y' : defaultOptionNo);
        setState(() => _floatingWindowDisabled = disable);
        gFFI.serverModel.androidUpdatekeepScreenOn();
      }

      enhancementsTiles.add(SettingsTile.switchTile(
          initialValue: !_floatingWindowDisabled,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_settingsText('Floating window')),
            Text('* ${_settingsText('floating_window_tip')}',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          onToggle: bind.mainIsOptionFixed(key: kOptionDisableFloatingWindow)
              ? null
              : onFloatingWindowChanged));

      enhancementsTiles.add(_getPopupDialogRadioEntry(
        title: _settingsText('Keep screen on'),
        list: [
          _RadioEntry('Never', _keepScreenOnToOption(KeepScreenOn.never)),
          _RadioEntry('During controlled',
              _keepScreenOnToOption(KeepScreenOn.duringControlled)),
          _RadioEntry('During service is on',
              _keepScreenOnToOption(KeepScreenOn.serviceOn)),
        ],
        getter: () => _keepScreenOnToOption(_floatingWindowDisabled
            ? KeepScreenOn.never
            : optionToKeepScreenOn(
                bind.mainGetLocalOption(key: kOptionKeepScreenOn))),
        asyncSetter:
            isOptionFixed(kOptionKeepScreenOn) || _floatingWindowDisabled
                ? null
                : (value) async {
                    await bind.mainSetLocalOption(
                        key: kOptionKeepScreenOn, value: value);
                    setState(() => _keepScreenOn = optionToKeepScreenOn(value));
                    gFFI.serverModel.androidUpdatekeepScreenOn();
                  },
      ));

      final disabledSettings = bind.isDisableSettings();
      final hideSecuritySettings =
          bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) == 'Y';
      final accountSections = <AbstractSettingsSection>[
        if (widget.showAccountGroup && !bind.isDisableAccount())
          SettingsSection(
            title: Text(_settingsText('Account')),
            tiles: [
              SettingsTile(
                title: Obx(() => Text(gFFI.userModel.userName.value.isEmpty
                    ? _settingsText('Login')
                    : '${_settingsText('Logout')} (${gFFI.userModel.accountLabelWithHandle})')),
                leading: Obx(() {
                  final avatar = bind.mainResolveAvatarUrl(
                      avatar: gFFI.userModel.avatar.value);
                  return buildAvatarWidget(
                        avatar: avatar,
                        size: 28,
                        borderRadius: null,
                        fallback: Icon(Icons.person),
                      ) ??
                      Icon(Icons.person);
                }),
                onPressed: (context) {
                  if (gFFI.userModel.userName.value.isEmpty) {
                    loginDialog();
                  } else {
                    logOutConfirmDialog();
                  }
                },
              ),
            ],
          ),
      ];

      final appearanceSections = <AbstractSettingsSection>[
        SettingsSection(
            title: Text(widget.detailTitle == null
                ? _settingsText("General preferences")
                : _settingsText(widget.detailTitle!)),
            tiles: [
              SettingsTile(
                  title: Text(_settingsText('Language')),
                  leading: Icon(Icons.translate_rounded),
                  onPressed: (context) {
                    showLanguageSettings(gFFI.dialogManager);
                  }),
              SettingsTile(
                title: Text(_settingsText(
                    Theme.of(context).brightness == Brightness.light
                        ? 'Light Theme'
                        : 'Dark Theme')),
                leading: Icon(Theme.of(context).brightness == Brightness.light
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded),
                onPressed: (context) {
                  showThemeSettings(gFFI.dialogManager);
                },
              ),
              if (!incomingOnly)
                SettingsTile.switchTile(
                  title: Text(_settingsText(
                      'keep-awake-during-outgoing-sessions-label')),
                  initialValue: _preventSleepWhileConnected,
                  onToggle: (v) async {
                    await mainSetLocalBoolOption(
                        kOptionKeepAwakeDuringOutgoingSessions, v);
                    setState(() {
                      _preventSleepWhileConnected = v;
                    });
                  },
                ),
            ]),
      ];

      final remoteAccessSections = <AbstractSettingsSection>[
        if (mobilePlatformCapabilities.canShowScreenSharingSettings &&
            !disabledSettings &&
            !outgoingOnly &&
            !hideSecuritySettings)
          SettingsSection(
            title: Text(_settingsText("Share screen")),
            tiles: shareScreenTiles,
          ),
        if (mobilePlatformCapabilities.canRunPersistentBackgroundService &&
            mobilePlatformCapabilities.canUseSystemOverlay &&
            !disabledSettings &&
            !outgoingOnly &&
            !hideSecuritySettings)
          SettingsSection(
            title: Text(_settingsText("Background service")),
            tiles: enhancementsTiles,
          ),
      ];

      final displaySections = <AbstractSettingsSection>[
        if (!bind.isIncomingOnly()) defaultDisplaySection(),
        if (isAndroid)
          SettingsSection(title: Text(_settingsText('Hardware Codec')), tiles: [
            SettingsTile.switchTile(
              title: Text(_settingsText('Enable hardware codec')),
              initialValue: _enableHardwareCodec,
              onToggle: isOptionFixed(kOptionEnableHwcodec)
                  ? null
                  : (v) async {
                      await mainSetBoolOption(kOptionEnableHwcodec, v);
                      final newValue =
                          await mainGetBoolOption(kOptionEnableHwcodec);
                      setState(() {
                        _enableHardwareCodec = newValue;
                      });
                    },
            ),
          ]),
        if (isAndroid)
          SettingsSection(
            title: Text(_settingsText("Recording")),
            tiles: [
              if (!outgoingOnly)
                SettingsTile.switchTile(
                  title: Text(
                      _settingsText('Automatically record incoming sessions')),
                  initialValue: _autoRecordIncomingSession,
                  onToggle: isOptionFixed(kOptionAllowAutoRecordIncoming)
                      ? null
                      : (v) async {
                          await bind.mainSetOption(
                              key: kOptionAllowAutoRecordIncoming,
                              value: bool2option(
                                  kOptionAllowAutoRecordIncoming, v));
                          final newValue = option2bool(
                              kOptionAllowAutoRecordIncoming,
                              await bind.mainGetOption(
                                  key: kOptionAllowAutoRecordIncoming));
                          setState(() {
                            _autoRecordIncomingSession = newValue;
                          });
                        },
                ),
              if (!incomingOnly)
                SettingsTile.switchTile(
                  title: Text(
                      _settingsText('Automatically record outgoing sessions')),
                  initialValue: _autoRecordOutgoingSession,
                  onToggle: isOptionFixed(kOptionAllowAutoRecordOutgoing)
                      ? null
                      : (v) async {
                          await bind.mainSetLocalOption(
                              key: kOptionAllowAutoRecordOutgoing,
                              value: bool2option(
                                  kOptionAllowAutoRecordOutgoing, v));
                          final newValue = option2bool(
                              kOptionAllowAutoRecordOutgoing,
                              bind.mainGetLocalOption(
                                  key: kOptionAllowAutoRecordOutgoing));
                          setState(() {
                            _autoRecordOutgoingSession = newValue;
                          });
                        },
                ),
              SettingsTile(
                title: Text(_settingsText("Directory")),
                description: Text(bind.mainVideoSaveDirectory(root: false)),
              ),
            ],
          ),
      ];

      final aboutSections = <AbstractSettingsSection>[
        SettingsSection(
          title: Text(_settingsText("About")),
          tiles: [
            SettingsTile(
                onPressed: (context) async {
                  await launchUrl(Uri.parse(url));
                },
                title: Text('${_settingsText("Version: ")}$version'),
                value: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('kunqiongai.com',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                      )),
                ),
                leading: Icon(Icons.info_rounded)),
            SettingsTile(
                title: Text(_settingsText("Build Date")),
                value: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(_buildDate),
                ),
                leading: Icon(Icons.query_builder_rounded)),
            if (isAndroid)
              SettingsTile(
                  onPressed: (context) => onCopyFingerprint(_fingerprint),
                  title: Text(_settingsText("Fingerprint")),
                  value: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(_fingerprint),
                  ),
                  leading: Icon(Icons.fingerprint_rounded)),
            SettingsTile(
              title: Text(_settingsText("Privacy Statement")),
              onPressed: (context) =>
                  launchUrlString('https://kunqiongai.com/'),
              leading: Icon(Icons.privacy_tip_rounded),
            )
          ],
        ),
      ];

      final groups = [
        if (accountSections.isNotEmpty)
          _SettingsGroupData(
            key: 'Account',
            title: _settingsText('Account'),
            subtitle: Obx(() => Text(gFFI.userModel.userName.value.isEmpty
                ? _settingsText(
                    'Login to sync devices, favorites, and membership.')
                : gFFI.userModel.accountLabelWithHandle)),
            icon: Icons.person_rounded,
            color: KqTheme.of(context).primary,
            sections: accountSections,
          ),
        _SettingsGroupData(
          key: kqMobileSettingsGroupAppearance,
          title: _settingsText('Appearance'),
          subtitle: Text(_settingsText('Language, theme, and app behavior')),
          icon: Icons.palette_rounded,
          color: KqTheme.of(context).primary,
          sections: appearanceSections,
        ),
        if (remoteAccessSections.isNotEmpty)
          _SettingsGroupData(
            key: kqMobileSettingsGroupRemoteAccess,
            title: _settingsText('Remote Access'),
            subtitle: Text(_settingsText('Security, permissions, and service')),
            icon: Icons.admin_panel_settings_rounded,
            color: KqTheme.of(context).warning,
            sections: remoteAccessSections,
          ),
        if (displaySections.isNotEmpty)
          _SettingsGroupData(
            key: 'Display & Performance',
            title: _settingsText('Display & Performance'),
            subtitle:
                Text(_settingsText('Image quality, codec, and recording')),
            icon: Icons.speed_rounded,
            color: KqTheme.of(context).online,
            sections: displaySections,
          ),
        _SettingsGroupData(
          key: 'About & Support',
          title: _settingsText('About & Support'),
          subtitle: Text(_settingsText('Version, website, and privacy')),
          icon: Icons.support_agent_rounded,
          color: KqTheme.of(context).primaryDeep,
          sections: aboutSections,
        ),
      ];
      if (widget.singleGroupOnly) {
        return _MobileSettingsSingleGroup(
          groups: groups,
          groupKey: widget.initialGroupTitle,
        );
      }
      return _MobileSettingsOverview(
        groups: groups,
        initialGroupTitle: widget.initialGroupTitle,
        footer: customClientSection,
      );
    });
  }

  Future<bool> canStartOnBoot() async {
    // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
    if (_hasIgnoreBattery && !_ignoreBatteryOpt) {
      return false;
    }
    if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
      return false;
    }
    return true;
  }

  defaultDisplaySection() {
    return SettingsSection(
      title: Text(_settingsText("Display Settings")),
      tiles: [
        SettingsTile(
            title: Text(_settingsText('Display Settings')),
            leading: Icon(Icons.desktop_windows_outlined),
            trailing: Icon(Icons.arrow_forward_ios),
            onPressed: (context) {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return _DisplayPage();
              }));
            })
      ],
    );
  }
}

class _SettingsGroupData {
  const _SettingsGroupData({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.sections,
  });

  final String key;
  final String title;
  final Widget subtitle;
  final IconData icon;
  final Color color;
  final List<AbstractSettingsSection> sections;
}

class _MobileSettingsSingleGroup extends StatelessWidget {
  const _MobileSettingsSingleGroup({
    required this.groups,
    required this.groupKey,
  });

  final List<_SettingsGroupData> groups;
  final String? groupKey;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final requestedGroupKey = groupKey?.trim();
    final group = requestedGroupKey == null || requestedGroupKey.isEmpty
        ? (groups.isEmpty ? null : groups[0])
        : groups.firstWhereOrNull((item) =>
            item.key == requestedGroupKey ||
            item.title == requestedGroupKey ||
            _settingsText(item.key) == requestedGroupKey);
    if (group == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 96),
        children: [
          Container(
            decoration: BoxDecoration(
              color: q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: q.line),
              boxShadow: [
                BoxShadow(
                  color: q.shadow.withOpacity(q.isDark ? 0.76 : 0.62),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _SettingsGroupBody(sections: group.sections),
          ),
        ],
      ),
    );
  }
}

class _MobileSettingsOverview extends StatefulWidget {
  const _MobileSettingsOverview({
    required this.groups,
    required this.footer,
    this.initialGroupTitle,
  });

  final List<_SettingsGroupData> groups;
  final Widget footer;
  final String? initialGroupTitle;

  @override
  State<_MobileSettingsOverview> createState() =>
      _MobileSettingsOverviewState();
}

class _MobileSettingsOverviewState extends State<_MobileSettingsOverview> {
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    final title = widget.initialGroupTitle;
    if (title == null || title.isEmpty) return;
    final index = widget.groups.indexWhere((group) =>
        group.key == title ||
        group.title == title ||
        _settingsText(group.key) == title);
    if (index >= 0) {
      _expandedIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 104),
        children: [
          ...List.generate(widget.groups.length, (index) {
            final group = widget.groups[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SettingsGroupCard(
                group: group,
                expanded: _expandedIndex == index,
                onTap: () {
                  setState(() {
                    _expandedIndex = _expandedIndex == index ? null : index;
                  });
                },
              ),
            );
          }),
          if (widget.footer is! SizedBox) ...[
            const SizedBox(height: 2),
            Opacity(opacity: 0.9, child: widget.footer),
          ],
        ],
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({
    required this.group,
    required this.expanded,
    required this.onTap,
  });

  final _SettingsGroupData group;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: expanded ? q.primary.withOpacity(0.28) : q.line,
        ),
        boxShadow: [
          BoxShadow(
            color: q.shadow.withOpacity(q.isDark ? 0.78 : 0.65),
            blurRadius: expanded ? 18 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: group.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: group.color.withOpacity(0.16),
                          ),
                        ),
                        child: Icon(group.icon, color: group.color, size: 21),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: q.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            DefaultTextStyle(
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: q.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                              child: group.subtitle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: expanded ? q.primary : q.muted,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: _SettingsGroupBody(
                sections: group.sections,
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroupBody extends StatelessWidget {
  const _SettingsGroupBody({
    required this.sections,
  });

  final List<AbstractSettingsSection> sections;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final theme = SettingsThemeData(
      settingsListBackground: Colors.transparent,
      settingsSectionBackground: Colors.transparent,
      leadingIconsColor: q.primary,
      titleTextColor: q.muted,
      settingsTileTextColor: q.ink,
      tileDescriptionTextColor: q.muted,
      trailingTextColor: q.muted,
      dividerColor: q.line,
      tileHighlightColor: q.primary.withOpacity(0.08),
      inactiveTitleColor: q.muted.withOpacity(0.55),
      inactiveSubtitleColor: q.muted.withOpacity(0.45),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: q.surfaceSoft.withOpacity(q.isDark ? 0.34 : 0.38),
        border: Border(top: BorderSide(color: q.line)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: q.primary,
                secondary: q.online,
                surface: Colors.transparent,
              ),
          listTileTheme: ListTileThemeData(
            iconColor: q.primary,
            textColor: q.ink,
            tileColor: Colors.transparent,
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          radioTheme: RadioThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return q.muted.withOpacity(0.38);
              }
              return q.primary;
            }),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return q.muted.withOpacity(0.45);
              }
              if (states.contains(WidgetState.selected)) return q.primary;
              return q.panelStrong;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return q.line.withOpacity(0.45);
              }
              if (states.contains(WidgetState.selected)) {
                return q.primary.withOpacity(q.isDark ? 0.46 : 0.34);
              }
              return q.muted.withOpacity(q.isDark ? 0.28 : 0.18);
            }),
          ),
          splashColor: q.primary.withOpacity(0.08),
          highlightColor: q.primary.withOpacity(0.06),
        ),
        child: SettingsList(
          sections: sections,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          platform: DevicePlatform.android,
          lightTheme: theme,
          darkTheme: theme,
          contentPadding: const EdgeInsets.only(bottom: 8),
        ),
      ),
    );
  }
}

String _settingsText(String key) {
  if (kqUiPrefersSimplifiedChinese()) return _settingsZh[key] ?? translate(key);
  return translate(key);
}

const _settingsZh = {
  'Account': '账户',
  'Login': '登录',
  'Logout': '退出登录',
  'Appearance': '外观',
  'Remote Access': '远程访问',
  'Display & Performance': '显示与性能',
  'About & Support': '关于与支持',
  'General preferences': '常用偏好',
  'General settings': '通用设置',
  'Security settings': '安全设置',
  'Background service': '后台服务',
  'Hardware Codec': '硬件编解码',
  'Recording': '录制',
  'Language, theme, and app behavior': '语言、主题和应用行为',
  'Security, permissions, and service': '安全、权限和服务',
  'Image quality, codec, and recording': '画质、编码和录制',
  'Version, website, and privacy': '版本、官网和隐私',
  'Login to sync devices, favorites, and membership.': '登录后同步设备、收藏和会员权益。',
  'Language': '语言',
  'Light Theme': '明亮主题',
  'Dark Theme': '暗黑主题',
  'Default': '默认',
  'Light': '明亮',
  'Dark': '黑暗',
  'Follow System': '跟随系统',
  'Share screen': '共享屏幕',
  'Enable hardware codec': '启用硬件编解码',
  'Automatically record incoming sessions': '自动录制传入会话',
  'Automatically record outgoing sessions': '自动录制传出会话',
  'Directory': '目录',
  'About': '关于',
  'Version: ': '版本：',
  'Build Date': '构建日期',
  'Fingerprint': '指纹',
  'Privacy Statement': '隐私声明',
  'About Kunqiong Remote Desktop': '关于鲲穹远程桌面',
  'Display Settings': '显示设置',
  'Default View Style': '默认显示方式',
  'Scale original': '原始尺寸',
  'Scale adaptive': '适应窗口',
  'Default Image Quality': '默认图像质量',
  'Good image quality': '画质最优化',
  'Balanced': '平衡',
  'Optimize reaction time': '速度最优化',
  'Custom': '自定义',
  'Default Codec': '默认编解码',
  'Auto': '自动',
  'Other Default Options': '其它默认选项',
  'Manage trusted devices': '管理可信设备',
  'Keep screen on': '保持屏幕开启',
  'Never': '从不',
  'During controlled': '被控期间',
  'During service is on': '服务开启期间',
  'enable-2fa-title': '启用两步验证',
  'Telegram bot': 'Telegram 机器人',
  'Enable trusted devices': '启用可信设备',
  'enable-trusted-devices-tip': '可信设备可减少重复验证',
  'Deny LAN discovery': '禁止局域网发现',
  'Use IP Whitelisting': '使用 IP 白名单',
  'Enable recording session': '启用会话录制',
  'auto_disconnect_option_tip': '空闲时自动断开连接',
  'Keep Kunqiong Remote Desktop background service': '保持鲲穹远程桌面后台服务',
  'Ignore Battery Optimizations': '忽略电池优化',
  'Open System Setting': '打开系统设置',
  'android_open_battery_optimizations_tip': '请在系统设置中关闭电池优化，以保持后台服务稳定运行。',
  'Start on boot': '开机启动',
  'Start the screen sharing service on boot, requires special permissions':
      '开机后自动启动屏幕共享服务，需要授予相关权限',
  'Check for software update on startup': '启动时检查软件更新',
  'Show terminal extra keys': '显示终端扩展按键',
  'Floating window': '悬浮窗',
  'floating_window_tip': '关闭后，被控时不会显示悬浮控制窗',
  'keep-awake-during-outgoing-sessions-label': '远控期间保持屏幕唤醒',
};

void showLanguageSettings(OverlayDialogManager dialogManager) async {
  try {
    final langs =
        _kqSortMobileLangs(json.decode(await bind.mainGetLangs()) as List);
    final savedLang = bind.mainGetLocalOption(key: kCommConfKeyLang);
    var lang = _kqNormalizeMobileLang(savedLang);
    if (savedLang.trim().isEmpty ||
        savedLang.trim().toLowerCase() == 'default') {
      await bind.mainSetLocalOption(key: kCommConfKeyLang, value: lang);
      if (!isWeb) await bind.mainChangeLanguage(lang: lang);
    }
    dialogManager.show((setState, close, context) {
      final q = KqTheme.of(context);
      setLang(v) async {
        v = _kqNormalizeMobileLang(v);
        if (lang != v) {
          setState(() {
            lang = v;
          });
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: v);
          if (!isWeb) await bind.mainChangeLanguage(lang: v);
          kqNotifyMobileLanguageChanged();
          Future.delayed(Duration(milliseconds: 200), close);
        }
      }

      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      final options = [
        if (isOptFixed && defaultOptionLang.isNotEmpty)
          (
            key: defaultOptionLang,
            title: _settingsText('Default'),
            subtitle: null
          ),
        for (final e in langs)
          (
            key: e[0] as String,
            title: kqLanguageDisplayParts(e[0] as String, e[1] as String).title,
            subtitle:
                kqLanguageDisplayParts(e[0] as String, e[1] as String).subtitle,
          ),
      ];
      return SafeArea(
        minimum: const EdgeInsets.fromLTRB(32, 14, 32, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: Material(
              color: q.panelStrong.withOpacity(q.isDark ? 0.96 : 0.99),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                    child: Row(
                      children: [
                        Icon(Icons.translate_rounded,
                            color: q.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _settingsText('Language'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: q.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: translate('Close'),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, color: q.muted),
                          onPressed: close,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: q.line),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        return _KqLanguageOptionTile(
                          value: option.key,
                          title: option.title,
                          subtitle: option.subtitle,
                          selected: option.key == lang,
                          enabled: !isOptFixed,
                          onChanged: setLang,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }, backDismiss: true, clickMaskDismiss: true);
  } catch (e) {
    //
  }
}

class _KqLanguageOptionTile extends StatelessWidget {
  const _KqLanguageOptionTile({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final textColor = enabled ? q.ink : q.muted.withOpacity(0.58);
    final selectedColor = enabled ? q.primary : q.muted.withOpacity(0.58);
    return Material(
      color: selected ? q.primary.withOpacity(q.isDark ? 0.16 : 0.08) : null,
      child: InkWell(
        onTap: enabled ? () => onChanged(value) : null,
        child: SizedBox(
          height: subtitle == null ? 44 : 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: q.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? selectedColor : q.muted.withOpacity(0.72),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _kqNormalizeMobileLang(String value) {
  final lang = value.trim().toLowerCase();
  if (lang.isEmpty || lang == 'default') {
    return 'zh-cn';
  }
  return lang;
}

List<dynamic> _kqSortMobileLangs(List<dynamic> langs) {
  final copy = List<dynamic>.from(langs);
  int priority(dynamic item) {
    final key = item is List && item.isNotEmpty
        ? item[0].toString().trim().toLowerCase()
        : '';
    if (key == 'zh-cn') return 0;
    if (key == 'zh-tw') return 1;
    return 2;
  }

  copy.sort((a, b) {
    final pa = priority(a);
    final pb = priority(b);
    if (pa != pb) return pa.compareTo(pb);
    final ka = a is List && a.isNotEmpty ? a[0].toString() : '';
    final kb = b is List && b.isNotEmpty ? b[0].toString() : '';
    return ka.compareTo(kb);
  });
  return copy;
}

void showThemeSettings(OverlayDialogManager dialogManager) async {
  var themeMode = MyTheme.getThemeModePreference();

  dialogManager.show((setState, close, context) {
    setTheme(v) {
      if (themeMode != v) {
        setState(() {
          themeMode = v;
        });
        MyTheme.changeDarkMode(themeMode);
        Future.delayed(Duration(milliseconds: 200), close);
      }
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return CustomAlertDialog(
      content: Column(children: [
        getRadio(Text(_settingsText('Light')), ThemeMode.light, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(_settingsText('Dark')), ThemeMode.dark, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(_settingsText('Follow System')), ThemeMode.system,
            themeMode, isOptFixed ? null : setTheme)
      ]),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showAbout(OverlayDialogManager dialogManager) {
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(_settingsText('About Kunqiong Remote Desktop')),
      content: Wrap(direction: Axis.vertical, spacing: 12, children: [
        Text('${_settingsText('Version: ')}$version'),
        InkWell(
            onTap: () async {
              const url = 'https://kunqiongai.com/';
              await launchUrl(Uri.parse(url));
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('kunqiongai.com',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  )),
            )),
      ]),
      actions: [],
    );
  }, clickMaskDismiss: true, backDismiss: true);
}

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.qr_code_scanner),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) => ScanPage(),
          ),
        );
      },
    );
  }
}

class _DisplayPage extends StatefulWidget {
  const _DisplayPage();

  @override
  State<_DisplayPage> createState() => __DisplayPageState();
}

class __DisplayPageState extends State<_DisplayPage> {
  @override
  Widget build(BuildContext context) {
    final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    var codecList = [
      _RadioEntry('Auto', 'auto'),
      _RadioEntry('VP8', 'vp8'),
      _RadioEntry('VP9', 'vp9'),
      _RadioEntry('AV1', 'av1'),
      if (h264) _RadioEntry('H264', 'h264'),
      if (h265) _RadioEntry('H265', 'h265')
    ];
    RxBool showCustomImageQuality = false.obs;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios)),
        title: Text(_settingsText('Display Settings')),
        centerTitle: true,
      ),
      body: SettingsList(sections: [
        SettingsSection(
          tiles: [
            _getPopupDialogRadioEntry(
              title: _settingsText('Default View Style'),
              list: [
                _RadioEntry('Scale original', kRemoteViewStyleOriginal),
                _RadioEntry('Scale adaptive', kRemoteViewStyleAdaptive)
              ],
              getter: () =>
                  bind.mainGetUserDefaultOption(key: kOptionViewStyle),
              asyncSetter: isOptionFixed(kOptionViewStyle)
                  ? null
                  : (value) async {
                      await bind.mainSetUserDefaultOption(
                          key: kOptionViewStyle, value: value);
                    },
            ),
            _getPopupDialogRadioEntry(
              title: _settingsText('Default Image Quality'),
              list: [
                _RadioEntry('Good image quality', kRemoteImageQualityBest),
                _RadioEntry('Balanced', kRemoteImageQualityBalanced),
                _RadioEntry('Optimize reaction time', kRemoteImageQualityLow),
                _RadioEntry('Custom', kRemoteImageQualityCustom),
              ],
              getter: () {
                final v =
                    bind.mainGetUserDefaultOption(key: kOptionImageQuality);
                showCustomImageQuality.value = v == kRemoteImageQualityCustom;
                return v;
              },
              asyncSetter: isOptionFixed(kOptionImageQuality)
                  ? null
                  : (value) async {
                      await bind.mainSetUserDefaultOption(
                          key: kOptionImageQuality, value: value);
                      showCustomImageQuality.value =
                          value == kRemoteImageQualityCustom;
                    },
              tail: customImageQualitySetting(),
              showTail: showCustomImageQuality,
              notCloseValue: kRemoteImageQualityCustom,
            ),
            _getPopupDialogRadioEntry(
              title: _settingsText('Default Codec'),
              list: codecList,
              getter: () =>
                  bind.mainGetUserDefaultOption(key: kOptionCodecPreference),
              asyncSetter: isOptionFixed(kOptionCodecPreference)
                  ? null
                  : (value) async {
                      await bind.mainSetUserDefaultOption(
                          key: kOptionCodecPreference, value: value);
                    },
            ),
          ],
        ),
        SettingsSection(
          title: Text(_settingsText('Other Default Options')),
          tiles:
              otherDefaultSettings().map((e) => otherRow(e.$1, e.$2)).toList(),
        ),
      ]),
    );
  }

  SettingsTile otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    return SettingsTile.switchTile(
      initialValue: value,
      title: Text(_settingsText(label)),
      onToggle: isOptFixed
          ? null
          : (b) async {
              await bind.mainSetUserDefaultOption(
                  key: key, value: b ? 'Y' : defaultOptionNo);
              setState(() {});
            },
    );
  }
}

class _ManageTrustedDevices extends StatefulWidget {
  const _ManageTrustedDevices();

  @override
  State<_ManageTrustedDevices> createState() => __ManageTrustedDevicesState();
}

class __ManageTrustedDevicesState extends State<_ManageTrustedDevices> {
  RxList<TrustedDevice> trustedDevices = RxList.empty(growable: true);
  RxList<Uint8List> selectedDevices = RxList.empty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_settingsText('Manage trusted devices')),
        centerTitle: true,
        actions: [
          Obx(() => IconButton(
              icon: Icon(Icons.delete, color: Colors.white),
              onPressed: selectedDevices.isEmpty
                  ? null
                  : () {
                      confrimDeleteTrustedDevicesDialog(
                          trustedDevices, selectedDevices);
                    }))
        ],
      ),
      body: FutureBuilder(
          future: TrustedDevice.get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('${_settingsText('Error')}: ${snapshot.error}'),
              );
            }
            final devices = snapshot.data as List<TrustedDevice>;
            trustedDevices = devices.obs;
            return trustedDevicesTable(trustedDevices, selectedDevices);
          }),
    );
  }
}

class _RadioEntry {
  final String label;
  final String value;
  _RadioEntry(this.label, this.value);
}

typedef _RadioEntryGetter = String Function();
typedef _RadioEntrySetter = Future<void> Function(String);

SettingsTile _getPopupDialogRadioEntry({
  required String title,
  required List<_RadioEntry> list,
  required _RadioEntryGetter getter,
  required _RadioEntrySetter? asyncSetter,
  Widget? tail,
  RxBool? showTail,
  String? notCloseValue,
}) {
  RxString groupValue = ''.obs;
  RxString valueText = ''.obs;

  init() {
    groupValue.value = getter();
    final e = list.firstWhereOrNull((e) => e.value == groupValue.value);
    if (e != null) {
      valueText.value = e.label;
    }
  }

  init();

  void showDialog() async {
    gFFI.dialogManager.show((setState, close, context) {
      final onChanged = asyncSetter == null
          ? null
          : (String? value) async {
              if (value == null) return;
              await asyncSetter(value);
              init();
              if (value != notCloseValue) {
                close();
              }
            };

      return CustomAlertDialog(
          content: Obx(
        () => Column(children: [
          ...list
              .map((e) => getRadio(Text(_settingsText(e.label)), e.value,
                  groupValue.value, onChanged))
              .toList(),
          Offstage(
            offstage:
                !(tail != null && showTail != null && showTail.value == true),
            child: tail,
          ),
        ]),
      ));
    }, backDismiss: true, clickMaskDismiss: true);
  }

  return SettingsTile(
    title: Text(_settingsText(title)),
    onPressed: asyncSetter == null ? null : (context) => showDialog(),
    value: Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Obx(() => Text(_settingsText(valueText.value))),
    ),
  );
}
