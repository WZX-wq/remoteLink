import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/autocomplete.dart';
import '../../common/widgets/login.dart';
import '../../models/model.dart';
import '../../models/mobile_platform_capability_policy.dart';
import '../../models/platform_model.dart';
import '../../models/remote_id_policy.dart';
import 'page_shape.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  static const _queryOnlinesEvent = 'callback_query_onlines';

  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  final TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _checkingRemoteId = false;
  String? _remoteIdError;
  Completer<bool?>? _remoteOnlineCompleter;
  String? _remoteOnlineQueryId;
  late final String _remoteOnlineHandlerName;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    Get.put<TextEditingController>(_idEditingController);
    _remoteOnlineHandlerName =
        'connection-page-remote-id-${identityHashCode(this)}';
    platformFFI.registerEventHandler(
      _queryOnlinesEvent,
      _remoteOnlineHandlerName,
      _handleRemoteOnlineState,
    );
    unawaited(_restoreLastConnection());
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return Obx(() {
      final user = gFFI.userModel;
      final isLogin = user.isLogin;
      return CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: _buildConnectPanel(context, isLogin: isLogin, user: user),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  if (!bind.isCustomClient() && !isIOS)
                    Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
                  _buildMembershipStrip(context, isLogin: isLogin, user: user),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 104)),
        ],
      ).marginOnly(top: 10, left: 16, right: 16);
    });
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  String get _remotePassword => _passwordController.text.trim();

  String? _validatedRemoteId() {
    final input = kqNormalizeRemoteIdentifier(_idController.id);
    if (input.isEmpty) {
      _setRemoteIdError(translate('Please enter remote ID'));
      _idFocusNode.requestFocus();
      return null;
    }

    final lowerInput = input.toLowerCase();
    final matchingPeer = _allPeersLoader.peers.firstWhereOrNull((peer) {
      return peer.id.toLowerCase() == lowerInput ||
          peer.alias.toLowerCase() == lowerInput ||
          peer.username.toLowerCase() == lowerInput ||
          peer.hostname.toLowerCase() == lowerInput;
    });
    final resolved = matchingPeer?.id ?? input;
    if (!isValidKqRemoteIdentifierFormat(resolved)) {
      _setRemoteIdError(kqLocaleText(
        zhCn: '识别码格式不正确，请检查后重新输入。',
        en: 'The device ID format is invalid. Check it and try again.',
      ));
      _idFocusNode.requestFocus();
      return null;
    }
    return resolved;
  }

  void _setRemoteIdError(String? message) {
    if (!mounted || _remoteIdError == message) return;
    setState(() => _remoteIdError = message);
    if (message != null) {
      showToast(message);
    }
  }

  Future<void> _handleRemoteOnlineState(Map<String, dynamic> event) async {
    final completer = _remoteOnlineCompleter;
    final queryId = _remoteOnlineQueryId;
    if (completer == null || completer.isCompleted || queryId == null) return;

    Set<String> idsFor(String key) => '${event[key] ?? ''}'
        .split(',')
        .map(kqNormalizePeerId)
        .where((id) => id.isNotEmpty)
        .toSet();

    if (idsFor('onlines').contains(queryId)) {
      completer.complete(true);
    } else if (idsFor('offlines').contains(queryId)) {
      completer.complete(false);
    }
  }

  Future<bool?> _queryRemoteOnline(String id) async {
    if (!kqRemoteIdentifierSupportsOnlineLookup(id)) return null;
    final normalized = kqNormalizePeerId(id);
    final completer = Completer<bool?>();
    _remoteOnlineQueryId = normalized;
    _remoteOnlineCompleter = completer;
    try {
      await bind.queryOnlines(ids: [normalized]);
      return await completer.future.timeout(
        const Duration(milliseconds: 1800),
        onTimeout: () => null,
      );
    } catch (error) {
      debugPrint('Remote ID online preflight failed: $error');
      return null;
    } finally {
      if (identical(_remoteOnlineCompleter, completer)) {
        _remoteOnlineCompleter = null;
        _remoteOnlineQueryId = null;
      }
    }
  }

  Future<bool> _ensureLoggedIn() async {
    if (gFFI.userModel.isLogin) {
      return true;
    }
    showToast(translate('Please login before remote connection'));
    final loggedIn = await loginDialog();
    if (loggedIn == true && gFFI.userModel.isLogin) {
      return true;
    }
    showToast(translate('Not logged in, remote connection unavailable'));
    return false;
  }

  void onConnect() => unawaited(_connectToRemote());

  Future<void> _connectToRemote({bool isFileTransfer = false}) async {
    if (_checkingRemoteId) return;
    final remoteId = _validatedRemoteId();
    if (remoteId == null) return;
    if (!await _ensureLoggedIn()) return;
    if (!mounted) return;
    setState(() => _checkingRemoteId = true);
    final supportsOnlineLookup =
        kqRemoteIdentifierSupportsOnlineLookup(remoteId);
    final online = await _queryRemoteOnline(remoteId);
    if (!mounted) return;
    setState(() => _checkingRemoteId = false);
    if (online == false) {
      _setRemoteIdError(kqLocaleText(
        zhCn: '识别码不存在或设备当前不在线。',
        en: 'The device ID does not exist or the device is offline.',
      ));
      return;
    }
    if (online == null && supportsOnlineLookup) {
      _setRemoteIdError(kqLocaleText(
        zhCn: '暂时无法核验识别码，请检查当前网络后重试。',
        en: 'The device ID could not be verified. Check your network and try again.',
      ));
      return;
    }
    _setRemoteIdError(null);
    connect(
      context,
      remoteId,
      isFileTransfer: isFileTransfer,
      password: _remotePassword,
      rememberPassword: _remotePassword.isNotEmpty,
    );
  }

  Future<void> _restoreLastConnection() async {
    if (isIOS) return;
    if (!isMobile) return;
    var lastRemoteId = kqLastSuccessfulMobileConnectId();
    lastRemoteId = lastRemoteId.isEmpty
        ? (await bind.mainGetLastRemoteId()).trim()
        : lastRemoteId;
    if (!mounted || lastRemoteId.isEmpty || _idController.id.isNotEmpty) {
      return;
    }
    _setRemoteId(lastRemoteId, fillRememberedPassword: true);
  }

  void _setRemoteId(String id, {bool fillRememberedPassword = true}) {
    final normalized = trimID(id).trim();
    setState(() {
      _idController.id = normalized;
      _idEditingController.text = formatID(normalized);
      if (fillRememberedPassword) {
        _passwordController.text = _rememberedPasswordFor(normalized);
      }
    });
  }

  String _rememberedPasswordFor(String id) {
    final normalized = trimID(id).trim();
    if (normalized.isEmpty) return '';
    return kqRememberedMobileConnectPassword(normalized);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
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

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    if (updateUrl.isEmpty) return const SizedBox.shrink();
    final q = KqTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await launchUrl(Uri.parse('https://kunqiongai.com/'));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: q.primary.withOpacity(q.isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: q.primary.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: q.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  translate('Download new version'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.primaryDeep,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: q.primary, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectPanel(BuildContext context,
      {required bool isLogin, required dynamic user}) {
    final q = KqTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
            blurRadius: 18,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kqMobileText('Remote connection'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      translate(
                          'Enter device ID to connect or transfer files.'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildRemoteIDTextField(),
          const SizedBox(height: 8),
          _buildRemotePasswordField(),
          const SizedBox(height: 16),
          _buildQuickActions(context),
        ],
      ),
    );
  }

  Widget _buildMembershipStrip(BuildContext context,
      {required bool isLogin, required dynamic user}) {
    final q = KqTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.52 : 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line.withOpacity(0.75)),
      ),
      child: Row(
        children: [
          _statusChip(
            context,
            isLogin ? translate('Logged in') : translate('Not logged in'),
            isLogin ? q.online : q.offline,
          ),
          const SizedBox(width: 8),
          _statusChip(context, user.membershipName, q.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              user.remoteQualityLabel,
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: q.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String text, Color color) {
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
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final q = KqTheme.of(context);
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _checkingRemoteId ? null : onConnect,
            style: FilledButton.styleFrom(
              backgroundColor: q.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_checkingRemoteId)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.near_me_rounded),
                const SizedBox(width: 8),
                Text(translate('Connect')),
              ],
            ),
          ),
        ),
        if (mobilePlatformCapabilities.canTransferFiles) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkingRemoteId
                  ? null
                  : () => unawaited(_connectToRemote(isFileTransfer: true)),
              icon: const Icon(Icons.folder_copy_outlined),
              label: Text(translate('Transfer file')),
              style: OutlinedButton.styleFrom(
                foregroundColor: q.primary,
                backgroundColor: q.primary.withOpacity(q.isDark ? 0.1 : 0.06),
                side: BorderSide(color: q.primary.withOpacity(0.36)),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemotePasswordField() {
    final q = KqTheme.of(context);
    final child = Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: q.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.line),
      ),
      child: TextField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        obscureText: !_passwordVisible,
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onConnect(),
        decoration: InputDecoration(
          border: InputBorder.none,
          icon: Icon(Icons.lock_outline_rounded, color: q.muted, size: 20),
          hintText: translate('Remote password (optional)'),
          hintStyle: TextStyle(
            color: q.muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          suffixIcon: IconButton(
            tooltip: translate(_passwordVisible ? 'Hide' : 'Show'),
            onPressed: () {
              setState(() => _passwordVisible = !_passwordVisible);
            },
            icon: Icon(
              _passwordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: q.muted,
            ),
          ),
        ),
      ),
    );
    return child;
  }

  Widget _buildRemoteIDTextField() {
    final w = SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
        child: Ink(
          decoration: BoxDecoration(
            color: KqTheme.of(context).field,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: KqTheme.of(context).line),
          ),
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Icon(
                  Icons.tag_rounded,
                  color: KqTheme.of(context).muted,
                  size: 20,
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 10, right: 8),
                  child: RawAutocomplete<Peer>(
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
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where((peer) =>
                                peer.id.toLowerCase().contains(textToFind) ||
                                peer.username
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.hostname
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.alias.toLowerCase().contains(textToFind))
                            .toList();
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted) {
                      updateTextAndPreserveSelection(
                          fieldTextEditingController, _idController.text);
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: 16,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        // keyboardType: TextInputType.number,
                        onChanged: (String text) {
                          _idController.id = text;
                          _passwordController.text =
                              _rememberedPasswordFor(_idController.id);
                          if (_remoteIdError != null) {
                            setState(() => _remoteIdError = null);
                          }
                        },
                        style: const TextStyle(
                          fontFamily: 'WorkSans',
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          hintText: translate('Enter device id or alias'),
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: KqTheme.of(context).muted,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          onConnect();
                        },
                      );
                    },
                    onSelected: (option) {
                      _setRemoteId(option.id, fillRememberedPassword: true);
                      FocusScope.of(context).unfocus();
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
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Material(
                                      elevation: 4,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 320,
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
                                                  )))
                                              : ListView(
                                                  padding:
                                                      EdgeInsets.only(top: 5),
                                                  children: options
                                                      .map((peer) =>
                                                          AutocompletePeerTile(
                                                              onSelect: () =>
                                                                  onSelected(
                                                                      peer),
                                                              peer: peer))
                                                      .toList(),
                                                ))))));
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                            _idEditingController.clear();
                            _passwordController.clear();
                          });
                        },
                        icon: Icon(Icons.clear, color: MyTheme.darkGray)),
                  )),
              SizedBox(
                width: 52,
                height: 52,
                child: IconButton(
                  icon: Icon(Icons.arrow_forward_rounded,
                      color: KqTheme.of(context).primary, size: 30),
                  onPressed: _checkingRemoteId ? null : onConnect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w,
      if (_remoteIdError != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _remoteIdError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ]);
    return child;
  }

  @override
  void dispose() {
    platformFFI.unregisterEventHandler(
        _queryOnlinesEvent, _remoteOnlineHandlerName);
    if (_remoteOnlineCompleter?.isCompleted == false) {
      _remoteOnlineCompleter?.complete(null);
    }
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    _passwordFocusNode.dispose();
    _passwordController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}

String _kqMobileText(String key) {
  if (!kqUiPrefersChinese()) {
    return translate(key);
  }
  switch (key) {
    case 'Remote connection':
      return '远程连接';
    case 'Allow remote access to this device':
      return '允许远程本设备';
    case 'Remote access is on':
      return '已允许远程访问';
    case 'Remote access is off':
      return '未允许远程访问';
    default:
      return translate(key);
  }
}
