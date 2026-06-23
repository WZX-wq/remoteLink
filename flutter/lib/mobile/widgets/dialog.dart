import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

void _showSuccess() {
  showToast(translate("Successful"));
}

void setTemporaryPasswordLengthDialog(
    OverlayDialogManager dialogManager) async {
  List<String> lengths = ['6', '8', '10'];
  String length = await bind.mainGetOption(key: "temporary-password-length");
  var index = lengths.indexOf(length);
  if (index < 0) index = 0;
  length = lengths[index];
  dialogManager.show((setState, close, context) {
    setLength(newValue) {
      final oldValue = length;
      if (oldValue == newValue) return;
      setState(() {
        length = newValue;
      });
      bind.mainSetOption(key: "temporary-password-length", value: newValue);
      bind.mainUpdateTemporaryPassword();
      Future.delayed(Duration(milliseconds: 200), () {
        close();
        _showSuccess();
      });
    }

    return CustomAlertDialog(
      title: Text(translate("Set one-time password length")),
      content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: lengths
              .map(
                (value) => Row(
                  children: [
                    Text(value),
                    Radio(
                        value: value, groupValue: length, onChanged: setLength),
                  ],
                ),
              )
              .toList()),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showServerSettings(OverlayDialogManager dialogManager,
    void Function(VoidCallback) setState) async {
  Map<String, dynamic> options = {};
  try {
    options = jsonDecode(await bind.mainGetOptions());
  } catch (e) {
    print("Invalid server config: $e");
  }
  showServerSettingsWithValue(
      ServerConfig.fromOptions(options), dialogManager, setState);
}

String _managedServerSummary() {
  if (kqUiPrefersChinese()) {
    return '专用网络已配置';
  }
  return translate('Dedicated network is configured');
}

String _managedServerDescription() {
  if (kqUiPrefersChinese()) {
    return '服务器信息由应用内置管理，不在这里显示。';
  }
  return translate('Server information is managed by the app and hidden here.');
}

String _normalizeServerSettingValue(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _sameServerSettingValue(String a, String b) {
  return _normalizeServerSettingValue(a) == _normalizeServerSettingValue(b);
}

ServerConfig _buildinServerConfig() {
  return ServerConfig(
    idServer: bind.mainGetBuildinOption(key: 'custom-rendezvous-server'),
    relayServer: bind.mainGetBuildinOption(key: 'relay-server'),
    apiServer: bind.mainGetBuildinOption(key: 'api-server'),
    key: bind.mainGetBuildinOption(key: 'key'),
  );
}

bool _serverSettingsUsesManagedSummary(ServerConfig serverConfig) {
  if (!isMobile || isWeb) {
    return false;
  }
  final buildinConfig = _buildinServerConfig();
  final hasBuildinServerConfig = buildinConfig.idServer.isNotEmpty ||
      buildinConfig.relayServer.isNotEmpty ||
      buildinConfig.apiServer.isNotEmpty ||
      buildinConfig.key.isNotEmpty;
  if (!hasBuildinServerConfig) {
    return false;
  }
  return _sameServerSettingValue(
          serverConfig.idServer, buildinConfig.idServer) &&
      _sameServerSettingValue(
          serverConfig.relayServer, buildinConfig.relayServer) &&
      _sameServerSettingValue(
          serverConfig.apiServer, buildinConfig.apiServer) &&
      _sameServerSettingValue(serverConfig.key, buildinConfig.key);
}

ServerConfig _editableServerConfig(ServerConfig serverConfig) {
  if (!isMobile || isWeb) {
    return serverConfig;
  }
  final buildinConfig = _buildinServerConfig();
  return ServerConfig(
    idServer:
        _sameServerSettingValue(serverConfig.idServer, buildinConfig.idServer)
            ? ''
            : serverConfig.idServer,
    relayServer: _sameServerSettingValue(
            serverConfig.relayServer, buildinConfig.relayServer)
        ? ''
        : serverConfig.relayServer,
    apiServer:
        _sameServerSettingValue(serverConfig.apiServer, buildinConfig.apiServer)
            ? ''
            : serverConfig.apiServer,
    key: _sameServerSettingValue(serverConfig.key, buildinConfig.key)
        ? ''
        : serverConfig.key,
  );
}

void showServerSettingsWithValue(
    ServerConfig serverConfig,
    OverlayDialogManager dialogManager,
    void Function(VoidCallback)? upSetState) async {
  if (_serverSettingsUsesManagedSummary(serverConfig)) {
    dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('ID/Relay Server')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _managedServerSummary(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _managedServerDescription(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          dialogButton('Custom', onPressed: () {
            close();
            showServerSettingsWithValue(
                ServerConfig(), dialogManager, upSetState);
          }, isOutline: true),
          dialogButton('OK', onPressed: close),
        ],
      );
    }, backDismiss: true, clickMaskDismiss: true);
    return;
  }

  var isInProgress = false;
  final editableConfig = _editableServerConfig(serverConfig);
  final initialIdServer = editableConfig.idServer;
  final initialRelayServer = editableConfig.relayServer;
  final initialApiServer = editableConfig.apiServer;
  final initialKey = editableConfig.key;
  final idCtrl = TextEditingController(text: initialIdServer);
  final relayCtrl = TextEditingController(text: initialRelayServer);
  final apiCtrl = TextEditingController(text: initialApiServer);
  final keyCtrl = TextEditingController(text: initialKey);

  RxString idServerMsg = ''.obs;
  RxString relayServerMsg = ''.obs;
  RxString apiServerMsg = ''.obs;

  final controllers = [idCtrl, relayCtrl, apiCtrl, keyCtrl];
  final errMsgs = [
    idServerMsg,
    relayServerMsg,
    apiServerMsg,
  ];

  dialogManager.show((setState, close, context) {
    Future<bool> submit() async {
      setState(() {
        isInProgress = true;
      });
      bool ret = await setServerConfig(
          null,
          errMsgs,
          ServerConfig(
              idServer: idCtrl.text.trim(),
              relayServer: relayCtrl.text.trim(),
              apiServer: apiCtrl.text.trim(),
              key: keyCtrl.text.trim()));
      setState(() {
        isInProgress = false;
      });
      return ret;
    }

    Widget buildField(
        String label, TextEditingController controller, String errorMsg,
        {String? Function(String?)? validator, bool autofocus = false}) {
      if (isDesktop || isWeb) {
        return Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(label),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: controller,
                decoration: InputDecoration(
                  errorText: errorMsg.isEmpty ? null : errorMsg,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                ),
                validator: validator,
                autofocus: autofocus,
              ).workaroundFreezeLinuxMint(),
            ),
          ],
        );
      }

      return TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorMsg.isEmpty ? null : errorMsg,
        ),
        validator: validator,
      ).workaroundFreezeLinuxMint();
    }

    return CustomAlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(translate('ID/Relay Server'))),
          ...ServerConfigImportExportWidgets.call(controllers, errMsgs),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Form(
          child: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildField(translate('ID Server'), idCtrl, idServerMsg.value,
                      autofocus: true),
                  SizedBox(height: 8),
                  if (!isIOS && !isWeb) ...[
                    buildField(translate('Relay Server'), relayCtrl,
                        relayServerMsg.value),
                    SizedBox(height: 8),
                  ],
                  buildField(
                    translate('API Server'),
                    apiCtrl,
                    apiServerMsg.value,
                    validator: (v) {
                      if (v != null && v.isNotEmpty) {
                        if (!(v.startsWith('http://') ||
                            v.startsWith("https://"))) {
                          return translate("invalid_http");
                        }
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 8),
                  buildField(translate('Key'), keyCtrl, ''),
                  if (isInProgress)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              )),
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: () {
          close();
        }, isOutline: true),
        dialogButton(
          'OK',
          onPressed: () async {
            if (await submit()) {
              close();
              showToast(translate('Successful'));
              upSetState?.call(() {});
            } else {
              showToast(translate('Failed'));
            }
          },
        ),
      ],
    );
  });
}

void setPrivacyModeDialog(
  OverlayDialogManager dialogManager,
  List<TToggleMenu> privacyModeList,
  RxString privacyModeState,
) async {
  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Privacy mode')),
      content: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: privacyModeList
              .map((value) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: value.child,
                    value: value.value,
                    onChanged: value.onChanged,
                  ))
              .toList()),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}
