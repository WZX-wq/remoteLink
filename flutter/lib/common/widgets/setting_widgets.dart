import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

customImageQualityWidget(
    {required double initQuality,
    required double initFps,
    required Function(double)? setQuality,
    required Function(double)? setFps,
    required bool showFps,
    double maxFps = kMaxFps,
    double maxQuality = kMaxQuality,
    String? fpsCaption}) {
  final effectiveMaxQuality =
      maxQuality.clamp(kMinQuality, kMaxMoreQuality).toDouble();
  final defaultQuality =
      kDefaultQuality.clamp(kMinQuality, effectiveMaxQuality).toDouble();
  if (initQuality < kMinQuality || initQuality > effectiveMaxQuality) {
    initQuality = defaultQuality;
  }
  final effectiveMaxFps = maxFps.clamp(kMinFps, kMaxFps).toDouble();
  if (initFps < kMinFps || initFps > effectiveMaxFps) {
    initFps = kDefaultFps.clamp(kMinFps, effectiveMaxFps).toDouble();
  }
  final qualityValue = initQuality.obs;
  final fpsValue = initFps.obs;

  return Column(
    children: [
        Obx(() => Row(
            children: [
              Builder(builder: (context) {
                final sliderMax = effectiveMaxQuality;
                final sliderDivisions =
                    (((sliderMax - kMinQuality) / 5)
                            .round()
                            .clamp(1, 1000))
                        .toInt();
                return Expanded(
                  flex: 3,
                  child: Slider(
                    value: qualityValue.value
                        .clamp(kMinQuality, sliderMax)
                        .toDouble(),
                    min: kMinQuality,
                    max: sliderMax,
                    divisions: sliderDivisions,
                    onChanged: setQuality == null
                        ? null
                        : (double value) async {
                            qualityValue.value = value;
                          },
                    onChangeEnd: setQuality == null
                        ? null
                        : (double value) {
                            qualityValue.value = value;
                            setQuality(value);
                          },
                  ),
                );
              }),
              Expanded(
                  flex: 1,
                  child: Text(
                    '${qualityValue.value.round()}%',
                    style: const TextStyle(fontSize: 15),
                  )),
              Expanded(
                  flex: isMobile ? 2 : 1,
                  child: Text(
                    translate('Bitrate'),
                    style: const TextStyle(fontSize: 15),
                  )),
            ],
          )),
      if (showFps)
        Obx(() => Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: fpsValue.value,
                    min: kMinFps,
                    max: effectiveMaxFps,
                    divisions: ((effectiveMaxFps - kMinFps) / 5).round(),
                    onChanged: setFps == null
                        ? null
                        : (double value) async {
                            fpsValue.value = value;
                          },
                    onChangeEnd: setFps == null
                        ? null
                        : (double value) {
                            fpsValue.value = value;
                            setFps(value);
                          },
                  ),
                ),
                Expanded(
                    flex: 1,
                    child: Text(
                      '${fpsValue.value.round()}',
                      style: const TextStyle(fontSize: 15),
                    )),
                Expanded(
                    flex: 2,
                    child: Text(
                      translate('FPS'),
                      style: const TextStyle(fontSize: 15),
                    ))
              ],
            )),
      if (showFps && fpsCaption != null && fpsCaption.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            fpsCaption,
            style: TextStyle(
              color: Theme.of(Get.context!).textTheme.bodySmall?.color,
              fontSize: 12,
            ),
          ).paddingOnly(left: 12),
        ),
    ],
  );
}

customImageQualitySetting() {
  final qualityKey = 'custom_image_quality';
  final fpsKey = 'custom-fps';
  final isKqApp = appName == '鲲穹远程桌面';

  final initQuality =
      (double.tryParse(bind.mainGetUserDefaultOption(key: qualityKey)) ??
          kDefaultQuality);
  final isQuanlityFixed = isOptionFixed(qualityKey);
  final initFps =
      (double.tryParse(bind.mainGetUserDefaultOption(key: fpsKey)) ??
          kDefaultFps);
  final isFpsFixed = isOptionFixed(fpsKey);

  return customImageQualityWidget(
      initQuality: initQuality,
      initFps: initFps,
      setQuality: isQuanlityFixed
          ? null
          : (v) {
              bind.mainSetUserDefaultOption(
                  key: qualityKey, value: v.toString());
            },
      setFps: isFpsFixed
          ? null
          : (v) {
              bind.mainSetUserDefaultOption(
                  key: fpsKey,
                  value: gFFI.userModel.clampRemoteFps(v).toString());
            },
      showFps: true,
      maxFps: gFFI.userModel.remoteMaxFps.toDouble(),
      maxQuality: isKqApp
          ? gFFI.userModel.remoteCustomQualitySelection.toDouble()
          : kMaxQuality,
      fpsCaption: gFFI.userModel.remoteEntitlementHint);
}

List<Widget> ServerConfigImportExportWidgets(
  List<TextEditingController> controllers,
  List<RxString> errMsgs,
) {
  import() {
    Clipboard.getData(Clipboard.kTextPlain).then((value) {
      importConfig(controllers, errMsgs, value?.text);
    });
  }

  export() {
    final text = ServerConfig(
            idServer: controllers[0].text.trim(),
            relayServer: controllers[1].text.trim(),
            apiServer: controllers[2].text.trim(),
            key: controllers[3].text.trim())
        .encode();
    debugPrint("ServerConfig export: $text");
    Clipboard.setData(ClipboardData(text: text));
    showToast(translate('Export server configuration successfully'));
  }

  return [
    Tooltip(
      message: translate('Import server config'),
      child: IconButton(
          icon: Icon(Icons.paste, color: Colors.grey), onPressed: import),
    ),
    Tooltip(
        message: translate('Export Server Config'),
        child: IconButton(
            icon: Icon(Icons.copy, color: Colors.grey), onPressed: export))
  ];
}

List<(String, String)> otherDefaultSettings() {
  List<(String, String)> v = [
    ('View Mode', kOptionViewOnly),
    if ((isDesktop || isWebDesktop))
      ('show_monitors_tip', kKeyShowMonitorsToolbar),
    if ((isDesktop || isWebDesktop))
      ('Collapse toolbar', kOptionCollapseToolbar),
    ('Show remote cursor', kOptionShowRemoteCursor),
    ('Follow remote cursor', kOptionFollowRemoteCursor),
    ('Follow remote window focus', kOptionFollowRemoteWindow),
    if ((isDesktop || isWebDesktop)) ('Zoom cursor', kOptionZoomCursor),
    ('Show quality monitor', kOptionShowQualityMonitor),
    ('Mute', kOptionDisableAudio),
    if (isDesktop) ('Enable file copy and paste', kOptionEnableFileCopyPaste),
    ('Disable clipboard', kOptionDisableClipboard),
    ('Lock after session end', kOptionLockAfterSessionEnd),
    ('Privacy mode', kOptionPrivacyMode),
    ('True color (4:4:4)', kOptionI444),
    ('Reverse mouse wheel', kKeyReverseMouseWheel),
    ('swap-left-right-mouse', kOptionSwapLeftRightMouse),
    if (isDesktop)
      (
        'Show displays as individual windows',
        kKeyShowDisplaysAsIndividualWindows
      ),
    if (isDesktop)
      (
        'Use all my displays for the remote session',
        kKeyUseAllMyDisplaysForTheRemoteSession
      ),
    ('Keep terminal sessions on disconnect', kOptionTerminalPersistent),
  ];

  return v;
}

class TrackpadSpeedWidget extends StatefulWidget {
  final SimpleWrapper<int> value;
  // If null, no debouncer will be applied.
  final Function(int)? onDebouncer;

  TrackpadSpeedWidget({Key? key, required this.value, this.onDebouncer});

  @override
  TrackpadSpeedWidgetState createState() => TrackpadSpeedWidgetState();
}

class TrackpadSpeedWidgetState extends State<TrackpadSpeedWidget> {
  final TextEditingController _controller = TextEditingController();
  late final Debouncer<int> debouncerSpeed;

  set value(int v) => widget.value.value = v;
  int get value => widget.value.value;

  void updateValue(int newValue) {
    setState(() {
      value = newValue.clamp(kMinTrackpadSpeed, kMaxTrackpadSpeed);
      // Scale the trackpad speed value to a percentage for display purposes.
      _controller.text = value.toString();
      if (widget.onDebouncer != null) {
        debouncerSpeed.setValue(value);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    debouncerSpeed = Debouncer<int>(
      Duration(milliseconds: 1000),
      onChanged: widget.onDebouncer,
      initialValue: widget.value.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.text.isEmpty) {
      _controller.text = value.toString();
    }
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Slider(
            value: value.toDouble(),
            min: kMinTrackpadSpeed.toDouble(),
            max: kMaxTrackpadSpeed.toDouble(),
            divisions: ((kMaxTrackpadSpeed - kMinTrackpadSpeed) / 10).round(),
            onChanged: (double v) => updateValue(v.round()),
          ),
        ),
        Expanded(
            flex: 1,
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onSubmitted: (text) {
                      int? v = int.tryParse(text);
                      if (v != null) {
                        updateValue(v);
                      }
                    },
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    ),
                  ),
                ).marginOnly(right: 8.0),
                Text(
                  '%',
                  style: const TextStyle(fontSize: 15),
                )
              ],
            )),
      ],
    );
  }
}
