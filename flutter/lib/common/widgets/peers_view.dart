import 'dart:async';
import 'dart:collection';

import 'package:dynamic_layouts/dynamic_layouts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/kq_project_api.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import 'peer_card.dart';

typedef PeerFilter = bool Function(Peer peer);
typedef PeerCardBuilder = Widget Function(Peer peer);

enum _KqRecentDeviceSection { recent, desktop, mobile }

class PeerSortType {
  static const String remoteId = 'Remote ID';
  static const String remoteHost = 'Remote Host';
  static const String username = 'Username';
  static const String status = 'Status';

  static List<String> values = [
    PeerSortType.remoteId,
    PeerSortType.remoteHost,
    PeerSortType.username,
    PeerSortType.status
  ];
}

class LoadEvent {
  static const String recent = 'load_recent_peers';
  static const String favorite = 'load_fav_peers';
  static const String lan = 'load_lan_peers';
  static const String addressBook = 'load_address_book_peers';
  static const String group = 'load_group_peers';
}

class PeersModelName {
  static const String recent = 'recent peer';
  static const String favorite = 'fav peer';
  static const String lan = 'discovered peer';
  static const String addressBook = 'address book peer';
  static const String group = 'group peer';
}

/// for peer search text, global obs value
final peerSearchText = "".obs;

/// for peer sort, global obs value
RxString? _peerSort;
RxString get peerSort {
  _peerSort ??= bind.getLocalFlutterOption(k: kOptionPeerSorting).obs;
  return _peerSort!;
}

// list for listener
RxList<RxString> get obslist => [peerSearchText, peerSort].obs;

final peerSearchTextController =
    TextEditingController(text: peerSearchText.value);

class _PeersView extends StatefulWidget {
  final Peers peers;
  final PeerFilter? peerFilter;
  final PeerCardBuilder peerCardBuilder;
  final PeerTabIndex peerTabIndex;

  const _PeersView(
      {required this.peers,
      required this.peerCardBuilder,
      required this.peerTabIndex,
      this.peerFilter,
      Key? key})
      : super(key: key);

  @override
  _PeersViewState createState() => _PeersViewState();
}

/// State for the peer widget.
class _PeersViewState extends State<_PeersView>
    with WindowListener, WidgetsBindingObserver {
  static const int _maxQueryCount = 3;
  static const _kqRecentOnlineQueryInterval = Duration(seconds: 5);
  static const _kqQueryOnlinesEvent = 'callback_query_onlines';
  final HashMap<String, String> _emptyMessages = HashMap.from({
    LoadEvent.recent: 'empty_recent_tip',
    LoadEvent.favorite: 'empty_favorite_tip',
    LoadEvent.lan: 'empty_lan_tip',
    LoadEvent.addressBook: 'empty_address_book_tip',
  });
  double get space =>
      widget.peers.loadEvent == LoadEvent.recent && (isDesktop || isWebDesktop)
          ? 8.0
          : (isDesktop || isWebDesktop)
              ? 12.0
              : 8.0;
  final _curPeers = <String>{};
  var _lastChangeTime = DateTime.now();
  var _lastQueryPeers = <String>{};
  var _lastQueryTime = DateTime.now();
  var _lastWindowRestoreTime = DateTime.now();
  var _queryCount = 0;
  var _exit = false;
  bool _isActive = true;
  List<Peer> _accountDevicePeers = [];
  bool _accountDevicesLoading = false;
  DateTime? _accountDevicesLoadedAt;
  DateTime? _accountDevicesLastFailedAt;
  Timer? _accountDeviceRetryTimer;
  bool _accountDeviceCacheRestored = false;
  int _lastAccountDeviceLoadGeneration = -1;
  bool _lastAccountDeviceLoadWasManualRefresh = false;
  final Map<_KqRecentDeviceSection, bool> _recentExpandedSections = {
    _KqRecentDeviceSection.recent: false,
    _KqRecentDeviceSection.mobile: false,
    _KqRecentDeviceSection.desktop: false,
  };
  late final String _accountDeviceOnlineHandlerName;

  final _scrollController = ScrollController();

  _PeersViewState() {
    _startCheckOnlines();
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _accountDeviceOnlineHandlerName = '${widget.peers.name} account devices';
    platformFFI.registerEventHandler(
        _kqQueryOnlinesEvent, _accountDeviceOnlineHandlerName, (evt) async {
      _handleAccountDeviceOnlineState(evt);
    });
    _restoreCachedAccountDevices();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    platformFFI.unregisterEventHandler(
        _kqQueryOnlinesEvent, _accountDeviceOnlineHandlerName);
    _accountDeviceRetryTimer?.cancel();
    _exit = true;
    super.dispose();
  }

  @override
  void onWindowFocus() {
    _queryCount = 0;
    _isActive = true;
    _queryOnlinesNow();
  }

  @override
  void onWindowBlur() {
    // We need this comparison because window restore (on Windows) also triggers `onWindowBlur()`.
    // Maybe it's a bug of the window manager, but the source code seems to be correct.
    //
    // Although `onWindowRestore()` is called after `onWindowBlur()` in my test,
    // we need the following comparison to ensure that `_isActive` is true in the end.
    if (isWindows &&
        DateTime.now().difference(_lastWindowRestoreTime) <
            const Duration(milliseconds: 300)) {
      return;
    }
    _queryCount = _maxQueryCount;
    _isActive = false;
  }

  @override
  void onWindowRestore() {
    // Window restore (on MacOS and Linux) also triggers `onWindowFocus()`.
    // But on Windows, it triggers `onWindowBlur()`, mybe it's a bug of the window manager.
    if (!isWindows) return;
    _queryCount = 0;
    _isActive = true;
    _lastWindowRestoreTime = DateTime.now();
    _queryOnlinesNow();
  }

  @override
  void onWindowMinimize() {
    // Window minimize also triggers `onWindowBlur()`.
  }

  // This function is required for mobile.
  // `onWindowFocus` works fine for desktop.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (isDesktop || isWebDesktop) return;
    if (state == AppLifecycleState.resumed) {
      _isActive = true;
      _queryCount = 0;
    } else if (state == AppLifecycleState.inactive) {
      _isActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // We should avoid too many rebuilds. MacOS(m1, 14.6.1) on Flutter 3.19.6.
    // Continious rebuilds of `ChangeNotifierProvider` will cause memory leak.
    // Simple demo can reproduce this issue.
    return ChangeNotifierProvider<Peers>.value(
      value: widget.peers,
      child: Consumer<Peers>(builder: (context, peers, child) {
        if (peers.peers.isEmpty && !_shouldGroupRecentPeersByDeviceType) {
          gFFI.peerTabModel.setCurrentTabCachedPeers([]);
          final q = KqTheme.of(context);
          final isRecent = widget.peers.loadEvent == LoadEvent.recent;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: q.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: q.primary.withOpacity(0.16)),
                    ),
                    child: Icon(
                      isRecent
                          ? Icons.history_toggle_off_rounded
                          : Icons.inbox_rounded,
                      color: q.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isRecent
                        ? _kqPeersText('No recent connection records')
                        : translate(
                            _emptyMessages[widget.peers.loadEvent] ?? 'Empty',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: q.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isRecent
                        ? _kqPeersText(
                            'Connected devices will appear here for quick access')
                        : _kqPeersText(
                            'Records will be shown here after available devices are added'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: q.muted,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return _buildPeersView(peers);
        }
      }),
    );
  }

  onVisibilityChanged(VisibilityInfo info) {
    final peerId = _peerId((info.key as ValueKey).value);
    final normalizedPeerId = kqNormalizePeerId(peerId);
    if (normalizedPeerId.isEmpty) {
      return;
    }
    if (info.visibleFraction > 0.00001) {
      _curPeers.add(normalizedPeerId);
    } else {
      _curPeers.remove(normalizedPeerId);
    }
    _lastChangeTime = DateTime.now();
  }

  String _cardId(String id) => widget.peers.name + id;
  String _peerId(String cardId) => cardId.replaceAll(widget.peers.name, '');

  Widget _buildPeersView(Peers peers) {
    final updateEvent = peers.event;
    final body = ObxValue<RxList>((filters) {
      return FutureBuilder<List<Peer>>(
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            var peers = snapshot.data!;
            if (peers.length > 1000) peers = peers.sublist(0, 1000);
            gFFI.peerTabModel.setCurrentTabCachedPeers(peers);
            buildOnePeer(Peer peer, bool isPortrait) {
              final visibilityChild = VisibilityDetector(
                key: ValueKey(_cardId(peer.id)),
                onVisibilityChanged: onVisibilityChanged,
                child: widget.peerCardBuilder(peer),
              );
              // `Provider.of<PeerTabModel>(context)` will causes infinete loop.
              // Because `gFFI.peerTabModel.setCurrentTabCachedPeers(peers)` will trigger `notifyListeners()`.
              //
              // No need to listen the currentTab change event.
              // Because the currentTab change event will trigger the peers change event,
              // and the peers change event will trigger _buildPeersView().
              return !isPortrait
                  ? Obx(() => peerCardUiType.value == PeerUiType.list
                      ? Container(height: 45, child: visibilityChild)
                      : peerCardUiType.value == PeerUiType.grid
                          ? SizedBox(
                              // kq-recent-reference-card-size
                              // kq-v213-recent-card-264x140
                              width: widget.peers.loadEvent == LoadEvent.recent
                                  ? 264
                                  : 220,
                              height: widget.peers.loadEvent == LoadEvent.recent
                                  ? 140
                                  : 92,
                              child: visibilityChild)
                          : SizedBox(
                              width: 220, height: 42, child: visibilityChild))
                  : Container(child: visibilityChild);
            }

            // We should avoid too many rebuilds. Win10(Some machines) on Flutter 3.19.6.
            // Continious rebuilds of `ListView.builder` will cause memory leak.
            // Simple demo can reproduce this issue.
            final Widget child = Obx(() => stateGlobal.isPortrait.isTrue
                ? _shouldGroupRecentPeersByDeviceType
                    ? _buildRecentGroupedPortraitList(peers, buildOnePeer)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 104),
                        itemCount: peers.length,
                        itemBuilder: (BuildContext context, int index) {
                          return buildOnePeer(peers[index], true)
                              .marginOnly(top: index == 0 ? 0 : 12, bottom: 4);
                        },
                      )
                : peerCardUiType.value == PeerUiType.list
                    ? ListView.builder(
                        controller: _scrollController,
                        itemCount: peers.length,
                        itemBuilder: (BuildContext context, int index) {
                          return buildOnePeer(peers[index], false).marginOnly(
                              right: space,
                              top: index == 0 ? 0 : space / 2,
                              bottom: space / 2);
                        },
                      )
                    : DynamicGridView.builder(
                        gridDelegate: SliverGridDelegateWithWrapping(
                            mainAxisSpacing: space / 2,
                            crossAxisSpacing: space),
                        itemCount: peers.length,
                        itemBuilder: (BuildContext context, int index) {
                          return buildOnePeer(peers[index], false);
                        }));

            if (updateEvent == UpdateEvent.load) {
              _curPeers.clear();
              _curPeers.addAll(peers
                  .map((e) => kqNormalizePeerId(e.id))
                  .where((id) => id.isNotEmpty));
              _queryOnlines(true);
            }
            return child;
          } else {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
        },
        future: matchPeers(filters[0].value, filters[1].value, peers.peers),
      );
    }, obslist);

    return body;
  }

  bool get _shouldGroupRecentPeersByDeviceType =>
      isMobile &&
      widget.peers.loadEvent == LoadEvent.recent &&
      stateGlobal.isPortrait.isTrue;

  Widget _buildRecentGroupedPortraitList(
    List<Peer> peers,
    Widget Function(Peer peer, bool isPortrait) buildOnePeer,
  ) {
    final loadGeneration = widget.peers.loadGeneration;
    _lastAccountDeviceLoadWasManualRefresh =
        widget.peers.event == UpdateEvent.load &&
            loadGeneration != _lastAccountDeviceLoadGeneration;
    if (_lastAccountDeviceLoadWasManualRefresh) {
      _lastAccountDeviceLoadGeneration = loadGeneration;
    }
    final forceAccountDeviceReload = _lastAccountDeviceLoadWasManualRefresh;
    _ensureAccountDevicesLoaded(force: forceAccountDeviceReload);
    final groupedPeers = _groupRecentPeersByDeviceType(peers);
    final sections = [
      _KqRecentDeviceSection.recent,
      _KqRecentDeviceSection.mobile,
      _KqRecentDeviceSection.desktop,
    ];
    final children = <Widget>[];
    for (final section in sections) {
      final sectionPeers = groupedPeers[section] ?? const <Peer>[];
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 18));
      }
      final isExpanded = _recentExpandedSections[section] ?? true;
      children.add(
          _buildRecentGroupHeader(section, sectionPeers.length, isExpanded));
      if (!isExpanded) {
        continue;
      }
      for (var i = 0; i < sectionPeers.length; i++) {
        children.add(
          buildOnePeer(sectionPeers[i], true)
              .marginOnly(top: i == 0 ? 10 : 12, bottom: 4),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 104),
      children: children,
    );
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
                peer, currentDeviceKey, currentDeviceId))
            .toList();
        final dedupedAccountDevices =
            _dedupeAccountDevicePeers(visibleAccountDevices);
        _restoreAccountDeviceOnlineStates(
            dedupedAccountDevices, accountDeviceOnlineStates);
        KqProjectApi.cacheAccountDevices(dedupedAccountDevices);
        await _applyLocalAliasesToAccountDevices(dedupedAccountDevices);
        if (_exit || !mounted) return;
        setState(() {
          _accountDevicePeers = dedupedAccountDevices;
          _accountDevicesLoadedAt = DateTime.now();
          _accountDevicesLastFailedAt = null;
        });
        _queryAccountDeviceOnlines(dedupedAccountDevices);
      } finally {
        if (!_exit && mounted && _accountDevicesLoading) {
          setState(() {
            _accountDevicesLoading = false;
          });
        } else {
          _accountDevicesLoading = false;
        }
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
      if (_exit || !mounted) return;
      setState(() {
        _accountDevicePeers = cached;
      });
      _queryAccountDeviceOnlines(cached);
    }();
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
      if (_exit || !mounted) return;
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

  List<String> _accountDeviceIdsForOnlineQuery(List<Peer> peers) {
    final ids = <String>{};
    for (final peer in peers) {
      final id = kqNormalizePeerId(peer.id);
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    return ids.toList(growable: false);
  }

  void _queryAccountDeviceOnlines(List<Peer> peers) {
    final ids = _accountDeviceIdsForOnlineQuery(peers);
    if (ids.isEmpty) return;
    bind.queryOnlines(ids: ids);
  }

  void _handleAccountDeviceOnlineState(Map<String, dynamic> evt) {
    final onlineSet = (evt['onlines'] as String)
        .split(',')
        .map(kqNormalizePeerId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final offlineSet = (evt['offlines'] as String)
        .split(',')
        .map(kqNormalizePeerId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (_applyOnlineStateToAccountDevicePeers(onlineSet, offlineSet) &&
        mounted) {
      setState(() {});
    }
  }

  bool _applyOnlineStateToAccountDevicePeers(
    Set<String> onlineSet,
    Set<String> offlineSet,
  ) {
    var changed = false;
    for (final peer in _accountDevicePeers) {
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

  Map<_KqRecentDeviceSection, List<Peer>> _groupRecentPeersByDeviceType(
    List<Peer> peers,
  ) {
    final groupedPeers = {
      _KqRecentDeviceSection.recent: peers,
      _KqRecentDeviceSection.mobile:
          _accountDevicePeers.where(_isKqMobilePeer).toList(),
      _KqRecentDeviceSection.desktop:
          _accountDevicePeers.where(_isKqDesktopPeer).toList(),
    };
    return groupedPeers;
  }

  bool _isKqMobilePeer(Peer peer) {
    final platform = peer.platform.trim().toLowerCase();
    return peer.platform == kPeerPlatformAndroid ||
        platform == 'ios' ||
        platform == 'iphone' ||
        platform == 'ipad';
  }

  bool _isKqDesktopPeer(Peer peer) {
    final platform = peer.platform.trim();
    return platform.isEmpty ||
        platform == kPeerPlatformWindows ||
        platform == kPeerPlatformMacOS ||
        platform == kPeerPlatformLinux ||
        platform == kPeerPlatformWebDesktop;
  }

  Widget _buildRecentGroupHeader(
      _KqRecentDeviceSection section, int count, bool isExpanded) {
    final q = KqTheme.of(context);
    final title = _kqPeersText(_kqRecentDeviceSectionTitle(section));
    final countLabel = _recentSectionCountLabel(section, count);
    return Row(
      children: [
        Icon(_kqRecentDeviceSectionIcon(section), color: q.muted, size: 20),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            '$title($countLabel)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: q.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          icon: Icon(
            isExpanded
                ? Icons.keyboard_arrow_down_rounded
                : Icons.keyboard_arrow_right_rounded,
            color: q.muted,
            size: 24,
          ),
          onPressed: () {
            setState(() => _recentExpandedSections[section] = !isExpanded);
          },
        ),
      ],
    ).marginOnly(left: 4);
  }

  String _recentSectionCountLabel(_KqRecentDeviceSection section, int count) {
    if (_isAccountDeviceInitialLoading &&
        (section == _KqRecentDeviceSection.mobile ||
            section == _KqRecentDeviceSection.desktop)) {
      return _kqPeersText('Loading');
    }
    return count.toString();
  }

  bool get _isAccountDeviceInitialLoading =>
      _accountDevicesLoading &&
      _accountDevicesLoadedAt == null &&
      _accountDevicePeers.isEmpty;

  var _queryInterval = const Duration(seconds: 20);

  bool get _isRecentPeers => widget.peers.loadEvent == LoadEvent.recent;

  void _startCheckOnlines() {
    () async {
      final p = await bind.mainIsUsingPublicServer();
      if (_isRecentPeers) {
        _queryInterval = _kqRecentOnlineQueryInterval;
      } else if (!p) {
        _queryInterval = const Duration(seconds: 6);
      }
      while (!_exit) {
        final now = DateTime.now();
        if (!setEquals(_curPeers, _lastQueryPeers)) {
          if (now.difference(_lastChangeTime) > const Duration(seconds: 1)) {
            _queryOnlines(false);
          }
        } else {
          final skipIfIsWeb =
              isWeb && !(stateGlobal.isWebVisible && stateGlobal.isInMainPage);
          final skipIfMobile =
              (isAndroid || isIOS) && !stateGlobal.isInMainPage;
          final skipIfNotActive = skipIfIsWeb || skipIfMobile || !_isActive;
          if (!skipIfNotActive &&
              (_isRecentPeers || _queryCount < _maxQueryCount || !p)) {
            if (now.difference(_lastQueryTime) >= _queryInterval) {
              if (_onlineQueryIdsNow().isNotEmpty) {
                _queryOnlinesNow();
                _lastQueryTime = DateTime.now();
              }
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }();
  }

  _queryOnlines(bool isLoadEvent) {
    if (_onlineQueryIdsNow().isNotEmpty) {
      _queryOnlinesNow();
      _queryCount = 0;
    }
    _lastQueryPeers = {..._curPeers};
    if (isLoadEvent) {
      _lastChangeTime = DateTime.now();
    } else {
      _lastQueryTime = DateTime.now().subtract(_queryInterval);
    }
  }

  void _queryOnlinesNow() {
    final ids = _onlineQueryIdsNow();
    if (ids.isEmpty) return;
    bind.queryOnlines(ids: ids);
    _lastQueryTime = DateTime.now();
    _queryCount += 1;
  }

  List<String> _onlineQueryIdsNow() {
    final ids = <String>{..._curPeers};
    if (_isRecentPeers) {
      ids.addAll(_accountDeviceIdsForOnlineQuery(_accountDevicePeers));
    }
    return ids.toList(growable: false);
  }

  Future<List<Peer>>? matchPeers(
      String searchText, String sortedBy, List<Peer> peers) async {
    if (widget.peerFilter != null) {
      peers = peers.where((peer) => widget.peerFilter!(peer)).toList();
    }

    if (widget.peers.loadEvent == LoadEvent.recent) {
      peers = await _sortRecentPeersWithFavoritesFirst(peers);
    }

    // fallback to id sorting
    if (!PeerSortType.values.contains(sortedBy)) {
      sortedBy = PeerSortType.remoteId;
      bind.setLocalFlutterOption(
        k: kOptionPeerSorting,
        v: sortedBy,
      );
    }

    if (widget.peers.loadEvent != LoadEvent.recent) {
      switch (sortedBy) {
        case PeerSortType.remoteId:
          peers.sort((p1, p2) => p1.getId().compareTo(p2.getId()));
          break;
        case PeerSortType.remoteHost:
          peers.sort((p1, p2) =>
              p1.hostname.toLowerCase().compareTo(p2.hostname.toLowerCase()));
          break;
        case PeerSortType.username:
          peers.sort((p1, p2) =>
              p1.username.toLowerCase().compareTo(p2.username.toLowerCase()));
          break;
        case PeerSortType.status:
          peers.sort((p1, p2) => p1.online ? -1 : 1);
          break;
      }
    }

    searchText = searchText.trim();
    if (searchText.isEmpty) {
      return peers;
    }
    searchText = searchText.toLowerCase();
    final matches = await Future.wait(
        peers.map((peer) => matchPeer(searchText, peer, widget.peerTabIndex)));
    final filteredList = List<Peer>.empty(growable: true);
    for (var i = 0; i < peers.length; i++) {
      if (matches[i]) {
        filteredList.add(peers[i]);
      }
    }

    return filteredList;
  }

  Future<List<Peer>> _sortRecentPeersWithFavoritesFirst(
      List<Peer> peers) async {
    final orderedPeers = peers.toList(growable: false);
    final order = <String, int>{};
    for (var i = 0; i < orderedPeers.length; i++) {
      order[orderedPeers[i].id] = i;
    }
    final favIds = (await bind.mainGetFav()).map((id) => id.toString()).toSet();
    orderedPeers.sort((a, b) {
      final aFav = favIds.contains(a.id);
      final bFav = favIds.contains(b.id);
      if (aFav != bFav) {
        return aFav ? -1 : 1;
      }
      return (order[a.id] ?? 0).compareTo(order[b.id] ?? 0);
    });
    return orderedPeers;
  }
}

String _kqRecentDeviceSectionTitle(_KqRecentDeviceSection section) {
  switch (section) {
    case _KqRecentDeviceSection.recent:
      return 'Recent connections';
    case _KqRecentDeviceSection.desktop:
      return 'Desktop devices';
    case _KqRecentDeviceSection.mobile:
      return 'Mobile devices';
  }
}

IconData _kqRecentDeviceSectionIcon(_KqRecentDeviceSection section) {
  switch (section) {
    case _KqRecentDeviceSection.recent:
      return Icons.history_rounded;
    case _KqRecentDeviceSection.desktop:
      return Icons.desktop_windows_rounded;
    case _KqRecentDeviceSection.mobile:
      return Icons.phone_android_rounded;
  }
}

String _kqPeersText(String key) {
  if (kqUiPrefersChinese()) return _kqPeersZh[key] ?? translate(key);
  return translate(key);
}

const _kqPeersZh = {
  'Recent connections': '最近连接',
  'Desktop devices': '桌面设备',
  'Mobile devices': '移动设备',
  'Loading': '加载中',
  'No recent connection records': '暂无最近连接记录',
  'Connected devices will appear here for quick access':
      '连接过的设备会显示在这里，方便下次快速访问。',
  'Records will be shown here after available devices are added':
      '添加或同步设备后，相关记录会显示在这里。',
};

abstract class BasePeersView extends StatelessWidget {
  final PeerTabIndex peerTabIndex;
  final PeerFilter? peerFilter;
  final PeerCardBuilder peerCardBuilder;

  const BasePeersView({
    Key? key,
    required this.peerTabIndex,
    this.peerFilter,
    required this.peerCardBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Peers peers;
    switch (peerTabIndex) {
      case PeerTabIndex.recent:
        peers = gFFI.recentPeersModel;
        break;
      case PeerTabIndex.fav:
        peers = gFFI.favoritePeersModel;
        break;
      case PeerTabIndex.lan:
        peers = gFFI.lanPeersModel;
        break;
      case PeerTabIndex.ab:
        peers = gFFI.abModel.peersModel;
        break;
      case PeerTabIndex.group:
        peers = gFFI.groupModel.peersModel;
        break;
    }
    return _PeersView(
        peers: peers,
        peerFilter: peerFilter,
        peerCardBuilder: peerCardBuilder,
        peerTabIndex: peerTabIndex);
  }
}

class RecentPeersView extends BasePeersView {
  RecentPeersView(
      {Key? key, EdgeInsets? menuPadding, ScrollController? scrollController})
      : super(
          key: key,
          peerTabIndex: PeerTabIndex.recent,
          peerCardBuilder: (Peer peer) => RecentPeerCard(
            peer: peer,
            menuPadding: menuPadding,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final widget = super.build(context);
    bind.mainLoadRecentPeers();
    return widget;
  }
}

class FavoritePeersView extends BasePeersView {
  FavoritePeersView(
      {Key? key, EdgeInsets? menuPadding, ScrollController? scrollController})
      : super(
          key: key,
          peerTabIndex: PeerTabIndex.fav,
          peerCardBuilder: (Peer peer) => FavoritePeerCard(
            peer: peer,
            menuPadding: menuPadding,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final widget = super.build(context);
    bind.mainLoadFavPeers();
    return widget;
  }
}

class DiscoveredPeersView extends BasePeersView {
  DiscoveredPeersView(
      {Key? key, EdgeInsets? menuPadding, ScrollController? scrollController})
      : super(
          key: key,
          peerTabIndex: PeerTabIndex.lan,
          peerCardBuilder: (Peer peer) => DiscoveredPeerCard(
            peer: peer,
            menuPadding: menuPadding,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final widget = super.build(context);
    bind.mainLoadLanPeers();
    bind.mainDiscover();
    return widget;
  }
}

class AddressBookPeersView extends BasePeersView {
  AddressBookPeersView(
      {Key? key, EdgeInsets? menuPadding, ScrollController? scrollController})
      : super(
          key: key,
          peerTabIndex: PeerTabIndex.ab,
          peerFilter: (Peer peer) =>
              _hitTag(gFFI.abModel.selectedTags, peer.tags),
          peerCardBuilder: (Peer peer) => AddressBookPeerCard(
            peer: peer,
            menuPadding: menuPadding,
          ),
        );

  static bool _hitTag(List<dynamic> selectedTags, List<dynamic> idents) {
    if (selectedTags.isEmpty) {
      return true;
    }
    // The result of a no-tag union with normal tags, still allows normal tags to perform union or intersection operations.
    final selectedNormalTags =
        selectedTags.where((tag) => tag != kUntagged).toList();
    if (selectedTags.contains(kUntagged)) {
      if (idents.isEmpty) return true;
      if (selectedNormalTags.isEmpty) return false;
    }
    if (gFFI.abModel.filterByIntersection.value) {
      for (final tag in selectedNormalTags) {
        if (!idents.contains(tag)) {
          return false;
        }
      }
      return true;
    } else {
      for (final tag in selectedNormalTags) {
        if (idents.contains(tag)) {
          return true;
        }
      }
      return false;
    }
  }
}

class MyGroupPeerView extends BasePeersView {
  MyGroupPeerView(
      {Key? key, EdgeInsets? menuPadding, ScrollController? scrollController})
      : super(
          key: key,
          peerTabIndex: PeerTabIndex.group,
          peerFilter: filter,
          peerCardBuilder: (Peer peer) => MyGroupPeerCard(
            peer: peer,
            menuPadding: menuPadding,
          ),
        );

  static bool filter(Peer peer) {
    final model = gFFI.groupModel;
    if (model.searchAccessibleItemNameText.isNotEmpty) {
      final text = model.searchAccessibleItemNameText.value.toLowerCase();
      final searchPeersOfUser = model.users.any((user) =>
          user.name == peer.loginName &&
          (user.name.toLowerCase().contains(text) ||
              user.displayNameOrName.toLowerCase().contains(text)));
      final searchPeersOfDeviceGroup =
          peer.device_group_name.toLowerCase().contains(text) &&
              model.deviceGroups.any((g) => g.name == peer.device_group_name);
      if (!searchPeersOfUser && !searchPeersOfDeviceGroup) {
        return false;
      }
    }
    if (model.selectedAccessibleItemName.isNotEmpty) {
      if (model.isSelectedDeviceGroup.value) {
        if (model.selectedAccessibleItemName.value != peer.device_group_name) {
          return false;
        }
      } else {
        if (model.selectedAccessibleItemName.value != peer.loginName) {
          return false;
        }
      }
    }
    return true;
  }
}
