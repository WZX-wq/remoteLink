import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common/kq_project_api.dart';
import 'package:get/get.dart';
import 'platform_model.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

String kqNormalizePeerId(String id) => id.replaceAll(RegExp(r'\s+'), '').trim();

class Peer {
  final String id;
  String hash; // personal ab hash password
  String password; // shared ab password
  String username; // pc username
  String hostname;
  String platform;
  String alias;
  List<dynamic> tags;
  bool forceAlwaysRelay = false;
  String rdpPort;
  String rdpUsername;
  bool online = false;
  String loginName; //login username
  String device_group_name;
  String note;
  bool? sameServer;

  String getId() {
    if (alias != '') {
      return alias;
    }
    return id;
  }

  Peer.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? '',
        hash = json['hash'] ?? '',
        password = json['password'] ?? '',
        username = json['username'] ?? '',
        hostname = json['hostname'] ?? '',
        platform = json['platform'] ?? '',
        alias = json['alias'] ?? '',
        tags = json['tags'] ?? [],
        forceAlwaysRelay = json['forceAlwaysRelay'] == 'true',
        rdpPort = json['rdpPort'] ?? '',
        rdpUsername = json['rdpUsername'] ?? '',
        online = json['online'] == true || json['online'] == 'true',
        loginName = json['loginName'] ?? '',
        device_group_name = json['device_group_name'] ?? '',
        note = json['note'] is String ? json['note'] : '',
        sameServer = json['same_server'];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "hash": hash,
      "password": password,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "alias": alias,
      "tags": tags,
      "forceAlwaysRelay": forceAlwaysRelay.toString(),
      "rdpPort": rdpPort,
      "rdpUsername": rdpUsername,
      'online': online,
      'loginName': loginName,
      'device_group_name': device_group_name,
      'note': note,
      'same_server': sameServer,
    };
  }

  Map<String, dynamic> toCustomJson({required bool includingHash}) {
    var res = <String, dynamic>{
      "id": id,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "alias": alias,
      "tags": tags,
    };
    if (includingHash) {
      res['hash'] = hash;
    }
    return res;
  }

  Map<String, dynamic> toGroupCacheJson() {
    return <String, dynamic>{
      "id": id,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "login_name": loginName,
      "device_group_name": device_group_name,
    };
  }

  Peer({
    required this.id,
    required this.hash,
    required this.password,
    required this.username,
    required this.hostname,
    required this.platform,
    required this.alias,
    required this.tags,
    required this.forceAlwaysRelay,
    required this.rdpPort,
    required this.rdpUsername,
    this.online = false,
    required this.loginName,
    required this.device_group_name,
    required this.note,
    this.sameServer,
  });

  Peer.loading()
      : this(
          id: '...',
          hash: '',
          password: '',
          username: '...',
          hostname: '...',
          platform: '...',
          alias: '',
          tags: [],
          forceAlwaysRelay: false,
          rdpPort: '',
          rdpUsername: '',
          loginName: '',
          device_group_name: '',
          note: '',
        );
  bool equal(Peer other) {
    return id == other.id &&
        hash == other.hash &&
        password == other.password &&
        username == other.username &&
        hostname == other.hostname &&
        platform == other.platform &&
        alias == other.alias &&
        tags.equals(other.tags) &&
        forceAlwaysRelay == other.forceAlwaysRelay &&
        rdpPort == other.rdpPort &&
        rdpUsername == other.rdpUsername &&
        device_group_name == other.device_group_name &&
        loginName == other.loginName &&
        note == other.note;
  }

  Peer.copy(Peer other)
      : this(
            id: other.id,
            hash: other.hash,
            password: other.password,
            username: other.username,
            hostname: other.hostname,
            platform: other.platform,
            alias: other.alias,
            tags: other.tags.toList(),
            forceAlwaysRelay: other.forceAlwaysRelay,
            rdpPort: other.rdpPort,
            rdpUsername: other.rdpUsername,
            online: other.online,
            loginName: other.loginName,
            device_group_name: other.device_group_name,
            note: other.note,
            sameServer: other.sameServer);
}

String _kqConnectionHistoryType({
  required bool isFileTransfer,
  required bool isViewCamera,
  required bool isTerminal,
  required bool isTcpTunneling,
  required bool isRDP,
}) {
  if (isFileTransfer) return 'file_transfer';
  if (isViewCamera) return 'view_camera';
  if (isTerminal) return 'terminal';
  if (isTcpTunneling) return 'tcp_tunneling';
  if (isRDP) return 'rdp';
  return 'remote';
}

String _kqCleanHistoryPeerId(String id) {
  return id.split('?').first.split('/').first.trim();
}

Peer _kqBuildHistoryPeer(String id) {
  final peerId = _kqCleanHistoryPeerId(id);
  if (peerId.isEmpty) return Peer.fromJson({'id': ''});
  try {
    final raw = bind.mainGetPeerSync(id: peerId);
    final decoded = raw.isEmpty ? null : jsonDecode(raw);
    if (decoded is Map) {
      final config = Map<String, dynamic>.from(decoded);
      final info = config['info'] is Map
          ? Map<String, dynamic>.from(config['info'])
          : <String, dynamic>{};
      return Peer.fromJson({
        'id': peerId,
        'username': info['username'] ?? config['username'] ?? '',
        'hostname': info['hostname'] ?? config['hostname'] ?? '',
        'platform': info['platform'] ?? config['platform'] ?? '',
        'alias': config['alias'] ?? '',
        'tags': config['tags'] is List ? config['tags'] : [],
        'loginName': config['loginName'] ?? config['login_name'] ?? '',
        'device_group_name': config['device_group_name'] ?? '',
        'note': config['note'] is String ? config['note'] : '',
        'same_server': config['same_server'],
      });
    }
  } catch (e) {
    debugPrint('KQ project API build history peer failed: $e');
  }
  return Peer.fromJson({'id': peerId});
}

void recordKqConnectionHistory(String id,
    {required bool isFileTransfer,
    required bool isViewCamera,
    required bool isTerminal,
    required bool isTcpTunneling,
    required bool isRDP}) {
  if (!KqProjectApi.isEnabled) {
    return;
  }
  final peer = _kqBuildHistoryPeer(id);
  if (peer.id.isEmpty) {
    return;
  }
  unawaited(KqProjectApi.recordPeer(
    peer,
    connType: _kqConnectionHistoryType(
      isFileTransfer: isFileTransfer,
      isViewCamera: isViewCamera,
      isTerminal: isTerminal,
      isTcpTunneling: isTcpTunneling,
      isRDP: isRDP,
    ),
  ));
}

enum UpdateEvent { online, load }

typedef GetInitPeers = RxList<Peer> Function();

class Peers extends ChangeNotifier {
  final String name;
  final String loadEvent;
  List<Peer> peers = List.empty(growable: true);
  // Part of the peers that are not in the rest peers list.
  // When there're too many peers, we may want to load the front 100 peers first,
  // so we can see peers in UI quickly. `restPeerIds` is the rest peers' ids.
  // And then load all peers later.
  List<String> restPeerIds = List.empty(growable: true);
  final GetInitPeers? getInitPeers;
  UpdateEvent event = UpdateEvent.load;
  static const _cbQueryOnlines = 'callback_query_onlines';

  Peers(
      {required this.name,
      required this.getInitPeers,
      required this.loadEvent}) {
    peers = getInitPeers?.call() ?? [];
    platformFFI.registerEventHandler(_cbQueryOnlines, name, (evt) async {
      _updateOnlineState(evt);
    });
    platformFFI.registerEventHandler(loadEvent, name, (evt) async {
      _updatePeers(evt);
    });
  }

  @override
  void dispose() {
    platformFFI.unregisterEventHandler(_cbQueryOnlines, name);
    platformFFI.unregisterEventHandler(loadEvent, name);
    super.dispose();
  }

  Peer getByIndex(int index) {
    if (index < peers.length) {
      return peers[index];
    } else {
      return Peer.loading();
    }
  }

  int getPeersCount() {
    return peers.length;
  }

  void _updateOnlineState(Map<String, dynamic> evt) {
    int changedCount = 0;
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
    for (final peer in peers) {
      final id = kqNormalizePeerId(peer.id);
      if (onlineSet.contains(id)) {
        if (!peer.online) {
          changedCount += 1;
          peer.online = true;
        }
      } else if (offlineSet.contains(id)) {
        if (peer.online) {
          changedCount += 1;
          peer.online = false;
        }
      }
    }

    if (changedCount > 0) {
      event = UpdateEvent.online;
      notifyListeners();
    }
  }

  void _updatePeers(Map<String, dynamic> evt) {
    final onlineStates = _getOnlineStates();
    if (getInitPeers != null) {
      peers = getInitPeers?.call() ?? [];
    } else {
      peers = _decodePeers(evt['peers']);
    }

    restPeerIds = [];
    if (evt['ids'] != null) {
      restPeerIds = (evt['ids'] as String).split(',');
    }
    if (loadEvent == 'load_recent_peers') {
      final limit = KqProjectApi.recentHistoryLimit;
      if (peers.length > limit) {
        peers = peers.sublist(0, limit);
      }
      restPeerIds = [];
    }

    for (var peer in peers) {
      final state = onlineStates[kqNormalizePeerId(peer.id)];
      if (state != null) {
        peer.online = state;
      }
    }
    event = UpdateEvent.load;
    notifyListeners();
    if (loadEvent == 'load_recent_peers') {
      unawaited(_syncRecentPeersWithDatabase());
    }
  }

  Future<void> _syncRecentPeersWithDatabase() async {
    final localPeers = peers.map((peer) => Peer.copy(peer)).toList();
    await KqProjectApi.syncRecentPeers(localPeers);
    final remotePeers = await KqProjectApi.fetchConnectionHistory();
    if (remotePeers.isEmpty) return;
    final onlineStates = _getOnlineStates();
    for (final peer in remotePeers) {
      final state = onlineStates[kqNormalizePeerId(peer.id)];
      if (state != null) {
        peer.online = state;
      }
    }
    peers = remotePeers;
    restPeerIds = [];
    event = UpdateEvent.load;
    notifyListeners();
  }

  Map<String, bool> _getOnlineStates() {
    var onlineStates = <String, bool>{};
    for (var peer in peers) {
      final id = kqNormalizePeerId(peer.id);
      if (id.isNotEmpty) {
        onlineStates[id] = peer.online;
      }
    }
    return onlineStates;
  }

  List<Peer> _decodePeers(String peersStr) {
    try {
      if (peersStr == "") return [];
      List<dynamic> peers = json.decode(peersStr);
      return peers.map((peer) {
        return Peer.fromJson(peer as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('peers(): $e');
    }
    return [];
  }
}
