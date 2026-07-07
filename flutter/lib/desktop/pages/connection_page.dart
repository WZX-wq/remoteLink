// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

class KqLowerCaseTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // kq-v226-password-input-lowercase-formatter
    final lowerText = newValue.text.toLowerCase();
    if (lowerText == newValue.text) {
      return newValue;
    }

    int clampOffset(int offset) =>
        offset < 0 ? offset : min(offset, lowerText.length);

    return newValue.copyWith(
      text: lowerText,
      selection: newValue.selection.copyWith(
        baseOffset: clampOffset(newValue.selection.baseOffset),
        extentOffset: clampOffset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final q = KqTheme.of(context);
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
              onTap: () async {
                await start_service(true);
              },
              child: Text(translate("Start service"),
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    fontSize: em,
                    color: q.primaryDeep,
                    fontWeight: FontWeight.w700,
                  ))).marginOnly(left: em),
        );

    basicWidget() {
      final statusColor = _statusColor(q);
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: q.line.withOpacity(0.9)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 10,
              width: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _buildConnStatusMsg(context, q)),
            if (!isIncomingOnly) startServiceWidget(),
          ],
        ),
      );
    }

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: Alignment.centerLeft)
                    .marginOnly(top: 2.0, left: 22.0),
              ],
            )
          : basicWidget()),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  Color _statusColor(KqTheme q) {
    if (_svcStopped.value ||
        stateGlobal.svcStatus.value == SvcStatus.connecting) {
      return q.warning;
    }
    return stateGlobal.svcStatus.value == SvcStatus.ready
        ? q.online
        : q.offline;
  }

  String _safeStatusTitle() {
    if (_svcStopped.value) return translate("Service is not running");
    if (stateGlobal.svcStatus.value == SvcStatus.connecting) {
      return translate("connecting_status");
    }
    if (stateGlobal.svcStatus.value == SvcStatus.notReady) {
      return translate("not_ready_status");
    }
    return translate('Ready');
  }

  String _safeStatusDetail() {
    if (_svcStopped.value) return '远程连接暂不可用';
    if (stateGlobal.svcStatus.value == SvcStatus.connecting) {
      return '正在建立安全连接';
    }
    if (stateGlobal.svcStatus.value == SvcStatus.ready) {
      return '安全中继已就绪';
    }
    return '请检查网络或服务状态';
  }

  _buildConnStatusMsg(BuildContext context, KqTheme q) {
    widget.onSvcStatusChanged?.call();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _safeStatusTitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: q.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _safeStatusDetail(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: q.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  final bool showOnlineStatusFooter;
  final bool showRecentPeers;

  const ConnectionPage({
    Key? key,
    this.showOnlineStatusFooter = true,
    this.showRecentPeers = true,
  }) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final _passwordController = TextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  bool _connectAsFileTransfer = false;
  bool _passwordVisible = false;
  bool _rememberPassword = false;

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  final _menuOpen = false.obs;

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  void _selectConnectionMode({required bool fileTransfer}) {
    // kq-v224-file-transfer-mode-selection
    if (_connectAsFileTransfer == fileTransfer) return;
    setState(() {
      _connectAsFileTransfer = fileTransfer;
    });
  }

  void _connectWithSelectedMode() {
    if (!_canConnect) {
      // kq-v226-empty-id-connect-guard
      return;
    }
    onConnect(isFileTransfer: _connectAsFileTransfer);
  }

  bool get _canConnect =>
      // kq-v237-password-required-to-connect
      _idController.id.trim().isNotEmpty &&
      _passwordController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    final q = KqTheme.of(context);
    final connectionForm = _buildRemoteIDTextField(context);
    return Container(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            if (widget.showRecentPeers)
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  connectionForm,
                  const SizedBox(height: 18),
                  const Expanded(child: PeerTabPage()),
                ],
              ))
            else
              connectionForm,
            if (widget.showOnlineStatusFooter && !isOutgoingOnly)
              Divider(height: 1, color: q.line),
            if (widget.showOnlineStatusFooter && !isOutgoingOnly)
              const OnlineStatusWidget().marginSymmetric(vertical: 10)
          ],
        ),
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false}) {
    var id = _idController.id;
    final password = _passwordController.text.trim().toLowerCase();
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        password: password.isEmpty ? null : password,
        rememberPassword: _rememberPassword);
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    final q = KqTheme.of(context);
    final formOnly = !widget.showRecentPeers;
    final canConnect = _canConnect;
    final inputHeight = formOnly ? 38.0 : 46.0;
    final inputTextStyle = TextStyle(
      // kq-v223-password-field-tight-38-height
      // kq-v223-password-field-matches-id-font-size
      fontFamily: 'WorkSans',
      fontSize: formOnly ? 14 : 16,
      height: formOnly ? 1.25 : 1.35,
      color: q.ink,
      fontWeight: FontWeight.w600,
    );
    final inputHintStyle = TextStyle(
      color: q.muted,
      fontSize: formOnly ? 14 : 15,
      fontWeight: FontWeight.w500,
    );

    InputDecoration kqConnectionInputDecoration({
      String? hintText,
    }) {
      return InputDecoration(
        // kq-v224-identical-id-password-input-decoration
        filled: true,
        fillColor: q.field,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: q.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: q.primary, width: 1.4),
        ),
        counterText: '',
        hintText: hintText,
        hintStyle: inputHintStyle,
        contentPadding: EdgeInsets.fromLTRB(
          14,
          formOnly ? 9 : 13,
          44,
          formOnly ? 9 : 13,
        ),
      );
    }

    Widget kqConnectionInputFrame({required Widget child}) {
      // kq-v224-identical-id-password-inputs
      // kq-v224-identical-id-password-input-frame
      return SizedBox(height: inputHeight, child: child);
    }

    Widget kqConnectionTextField({
      required TextEditingController controller,
      FocusNode? focusNode,
      String? hintText,
      bool obscureText = false,
      List<TextInputFormatter>? inputFormatters,
      ValueChanged<String>? onChanged,
      ValueChanged<String>? onSubmitted,
      Widget? trailing,
    }) {
      // kq-v225-single-input-component-for-id-and-code
      return kqConnectionInputFrame(
        child: Stack(
          children: [
            Positioned.fill(
              child: TextField(
                controller: controller,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                focusNode: focusNode,
                obscureText: obscureText,
                style: inputTextStyle,
                maxLines: 1,
                cursorColor: q.primary,
                decoration: kqConnectionInputDecoration(hintText: hintText),
                inputFormatters: inputFormatters,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ).workaroundFreezeLinuxMint(),
            ),
            if (trailing != null)
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                width: 32,
                // kq-v223-password-field-tight-suffix-slot
                // kq-v225-trailing-overlay-does-not-affect-textfield-height
                child: Center(child: trailing),
              ),
          ],
        ),
      );
    }

    final passwordInput = kqConnectionTextField(
      controller: _passwordController,
      obscureText: !_passwordVisible,
      // kq-v222-password-hint-hidden-under-label
      hintText: formOnly ? null : translate('Verification code'),
      inputFormatters: [KqLowerCaseTextInputFormatter()],
      onChanged: (_) {
        // kq-v237-password-change-refreshes-connect-state
        setState(() {});
      },
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        // kq-v223-password-eye-no-extra-padding
        padding: EdgeInsets.zero,
        tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
        icon: Transform.translate(
          // kq-v238-password-eye-visual-center
          offset: const Offset(0, -2),
          child: Icon(
            _passwordVisible ? Icons.visibility : Icons.visibility_off,
            size: 18,
            color: q.muted,
          ),
        ),
        onPressed: () {
          setState(() {
            _passwordVisible = !_passwordVisible;
          });
        },
      ),
      onSubmitted: (_) {
        _connectWithSelectedMode();
      },
    );
    Widget labelWrap(String label, Widget child) {
      if (!formOnly) return child;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: q.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      );
    }

    Widget modeOption({
      required bool selected,
      required String label,
      VoidCallback? onTap,
    }) {
      // kq-v222-mode-option-consistent-typography
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 17,
            color: selected ? q.primary : q.line,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: q.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      );

      if (onTap == null) {
        return SizedBox(height: 30, child: Center(child: content));
      }

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(height: 30, child: Center(child: content)),
        ),
      );
    }

    Widget rememberPasswordOption() {
      // kq-v229-connect-remember-password-choice
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _rememberPassword = !_rememberPassword;
            });
          },
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _rememberPassword
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: _rememberPassword ? q.primary : q.line,
                ),
                const SizedBox(width: 7),
                Text(
                  translate('Remember password'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    var w = Container(
      width: double.infinity,
      padding: EdgeInsets.zero,
      child: Ink(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (formOnly)
              Row(
                children: [
                  Icon(Icons.people_alt_outlined, color: q.ink, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '远程协助他人',
                    style: TextStyle(
                      color: q.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ).marginOnly(bottom: 17)
            else
              Text(
                '远程协助他人',
                style: TextStyle(
                  color: q.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ).marginOnly(bottom: 22),
            Row(
              crossAxisAlignment:
                  formOnly ? CrossAxisAlignment.end : CrossAxisAlignment.center,
              children: [
                Expanded(
                    flex: formOnly ? 4 : 1,
                    child: labelWrap(
                        '对方识别码',
                        RawAutocomplete<Peer>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              _autocompleteOpts = const Iterable<Peer>.empty();
                            } else if (_allPeersLoader.peers.isEmpty &&
                                !_allPeersLoader.isPeersLoaded) {
                              Peer emptyPeer = Peer(
                                id: '',
                                username: '',
                                hostname: '',
                                alias: '',
                                platform: '',
                                tags: [],
                                hash: '',
                                password: '',
                                forceAlwaysRelay: false,
                                rdpPort: '',
                                rdpUsername: '',
                                loginName: '',
                                device_group_name: '',
                                note: '',
                              );
                              _autocompleteOpts = [emptyPeer];
                            } else {
                              String textWithoutSpaces =
                                  textEditingValue.text.replaceAll(" ", "");
                              if (int.tryParse(textWithoutSpaces) != null) {
                                textEditingValue = TextEditingValue(
                                  text: textWithoutSpaces,
                                  selection: textEditingValue.selection,
                                );
                              }
                              String textToFind =
                                  textEditingValue.text.toLowerCase();
                              _autocompleteOpts = _allPeersLoader.peers
                                  .where((peer) =>
                                      peer.id
                                          .toLowerCase()
                                          .contains(textToFind) ||
                                      peer.username
                                          .toLowerCase()
                                          .contains(textToFind) ||
                                      peer.hostname
                                          .toLowerCase()
                                          .contains(textToFind) ||
                                      peer.alias
                                          .toLowerCase()
                                          .contains(textToFind))
                                  .toList();
                            }
                            return _autocompleteOpts;
                          },
                          focusNode: _idFocusNode,
                          textEditingController: _idEditingController,
                          fieldViewBuilder: (
                            BuildContext context,
                            TextEditingController fieldTextEditingController,
                            FocusNode fieldFocusNode,
                            VoidCallback onFieldSubmitted,
                          ) {
                            updateTextAndPreserveSelection(
                                fieldTextEditingController, _idController.text);
                            return Obx(() => kqConnectionTextField(
                                  controller: fieldTextEditingController,
                                  focusNode: fieldFocusNode,
                                  hintText: _idInputFocused.value
                                      ? null
                                      : translate('Enter Remote ID'),
                                  inputFormatters: [IDTextInputFormatter()],
                                  onChanged: (v) {
                                    final wasConnectable = _canConnect;
                                    _idController.id = v;
                                    if (wasConnectable != _canConnect) {
                                      setState(() {});
                                    }
                                  },
                                  onSubmitted: (_) {
                                    _connectWithSelectedMode();
                                  },
                                ));
                          },
                          onSelected: (option) {
                            setState(() {
                              _idController.id = option.id;
                              FocusScope.of(context).unfocus();
                            });
                          },
                          optionsViewBuilder: (BuildContext context,
                              AutocompleteOnSelected<Peer> onSelected,
                              Iterable<Peer> options) {
                            options = _autocompleteOpts;
                            double maxHeight = options.length * 50;
                            if (options.length == 1) {
                              maxHeight = 52;
                            } else if (options.length == 3) {
                              maxHeight = 146;
                            } else if (options.length == 4) {
                              maxHeight = 193;
                            }
                            maxHeight = maxHeight.clamp(0, 200);

                            return Align(
                              alignment: Alignment.topLeft,
                              child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: q.shadow,
                                        blurRadius: 18,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Material(
                                        color: q.panelStrong,
                                        elevation: 4,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 460,
                                          ),
                                          child: _allPeersLoader
                                                      .peers.isEmpty &&
                                                  !_allPeersLoader.isPeersLoaded
                                              ? Container(
                                                  height: 80,
                                                  child: Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ))
                                              : Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 5),
                                                  child: ListView(
                                                    children: options
                                                        .map((peer) =>
                                                            AutocompletePeerTile(
                                                                onSelect: () =>
                                                                    onSelected(
                                                                        peer),
                                                                peer: peer))
                                                        .toList(),
                                                  ),
                                                ),
                                        ),
                                      ))),
                            );
                          },
                        ))),
                const SizedBox(width: 10),
                if (formOnly)
                  Expanded(
                    flex: 3,
                    child: labelWrap(
                        translate('Verification code'), passwordInput),
                  )
                else
                  SizedBox(
                    width: 174,
                    child: passwordInput,
                  ),
                const SizedBox(width: 10),
                SizedBox(
                  height: formOnly ? 42 : 46,
                  width: formOnly ? 100 : 190,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: q.primary,
                      // kq-v226-connect-button-disabled-grey-blue
                      disabledBackgroundColor: const Color(0xFFBFD2EA),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white.withOpacity(0.88),
                      elevation: formOnly ? 8 : 0,
                      shadowColor: q.primary.withOpacity(0.24),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(formOnly ? 6 : 12),
                      ),
                    ),
                    onPressed: canConnect ? _connectWithSelectedMode : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (formOnly) ...[
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            translate("Connect"),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  formOnly ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(top: formOnly ? 12.0 : 13.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                modeOption(
                  selected: !_connectAsFileTransfer,
                  onTap: () {
                    _selectConnectionMode(fileTransfer: false);
                  },
                  label: '远程桌面',
                ),
                const SizedBox(width: 16),
                modeOption(
                  selected: _connectAsFileTransfer,
                  label: translate('Transfer file'),
                  onTap: () {
                    _selectConnectionMode(fileTransfer: true);
                  },
                ),
                const SizedBox(width: 16),
                Flexible(child: rememberPasswordOption()),
                if (!formOnly) ...[
                  const SizedBox(width: 8),
                  Container(
                    height: 34.0,
                    width: 34.0,
                    decoration: BoxDecoration(
                      color: q.field,
                      border: Border.all(color: q.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          var offset = Offset(0, 0);
                          return Obx(() => InkWell(
                                child: _menuOpen.value
                                    ? Transform.rotate(
                                        angle: pi,
                                        child: Icon(IconFont.more,
                                            size: 14, color: q.ink),
                                      )
                                    : Icon(IconFont.more,
                                        size: 14, color: q.ink),
                                onTapDown: (e) {
                                  offset = e.globalPosition;
                                },
                                onTap: () async {
                                  _menuOpen.value = true;
                                  final x = offset.dx;
                                  final y = offset.dy;
                                  final menuItems = <(String, VoidCallback)>[
                                    (
                                      'Terminal',
                                      () => onConnect(isTerminal: true)
                                    ),
                                  ];
                                  await mod_menu
                                      .showMenu(
                                    context: context,
                                    position: RelativeRect.fromLTRB(x, y, x, y),
                                    items: menuItems
                                        .map((e) => MenuEntryButton<String>(
                                              childBuilder:
                                                  (TextStyle? style) => Text(
                                                translate(e.$1),
                                                style: style,
                                              ),
                                              proc: () => e.$2(),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal:
                                                      kDesktopMenuPadding.left),
                                              dismissOnClicked: true,
                                            ))
                                        .map((e) => e.build(
                                            context,
                                            const MenuConfig(
                                                commonColor:
                                                    CustomPopupMenuTheme
                                                        .commonColor,
                                                height:
                                                    CustomPopupMenuTheme.height,
                                                dividerHeight:
                                                    CustomPopupMenuTheme
                                                        .dividerHeight)))
                                        .expand((i) => i)
                                        .toList(),
                                    elevation: 8,
                                  )
                                      .then((_) {
                                    _menuOpen.value = false;
                                  });
                                },
                              ));
                        },
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
    if (formOnly) {
      return w;
    }
    return Container(
        constraints: const BoxConstraints(maxWidth: 860), child: w);
  }
}
