import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

import '../common.dart';

class KqProjectApi {
  static const optionKey = 'kq_project_api_server';
  static const buildinOptionKey = 'kq-project-api-server';
  static const _deletedRecentPeerOptionKey =
      'kq_deleted_connection_history_peers';
  static const _cachedAccountDevicesOptionKey = 'kq_cached_account_devices';
  static const _deletedRecentPeerTtl = Duration(days: 30);

  static DateTime? _lastSyncAt;
  static String _lastSyncSignature = '';
  static Map<String, DateTime>? _deletedRecentPeers;
  static DateTime? _lastAccountDeviceSyncAt;

  static String get baseUrl {
    final local = bind.mainGetLocalOption(key: optionKey).trim();
    final buildin = bind.mainGetBuildinOption(key: buildinOptionKey).trim();
    final value = local.isNotEmpty ? local : buildin;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  static bool get isEnabled => baseUrl.isNotEmpty;

  static int get recentHistoryLimit =>
      UserModel.isLocalMemberActiveForCurrentUser ? 50 : 5;

  static Future<void> syncRecentPeers(List<Peer> peers) async {
    if (!isEnabled || peers.isEmpty) return;
    final token = _apiWebToken();
    if (token.isEmpty) return;
    final limit = recentHistoryLimit;
    final safePeers = filterDeletedRecentPeers(peers)
        .take(limit)
        .map(_peerToSafeJson)
        .toList();
    if (safePeers.isEmpty) return;
    final signature = safePeers.map((peer) => peer['id']).join(',');
    final now = DateTime.now();
    if (_lastSyncSignature == signature &&
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < const Duration(seconds: 8)) {
      return;
    }
    _lastSyncSignature = signature;
    _lastSyncAt = now;
    try {
      await http
          .post(
            Uri.parse('$baseUrl/connection-history/bulk'),
            headers: _headers(token),
            body: jsonEncode({'peers': safePeers}),
          )
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('KQ project API syncRecentPeers failed: $e');
    }
  }

  static Future<List<Peer>> fetchConnectionHistory() async {
    if (!isEnabled) return [];
    final token = _apiWebToken();
    if (token.isEmpty) return [];
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/connection-history'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }
      final body = jsonDecode(decode_http_response(response));
      if (body is! Map || body['items'] is! List) {
        return [];
      }
      return (body['items'] as List)
          .whereType<Map>()
          .map((item) => Peer.fromJson(Map<String, dynamic>.from(item)))
          .where((peer) => peer.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('KQ project API fetchConnectionHistory failed: $e');
      return [];
    }
  }

  static Future<void> syncCurrentAccountDevice({bool force = false}) async {
    if (!isEnabled) return;
    final token = _apiWebToken();
    if (token.isEmpty) return;
    final now = DateTime.now();
    if (!force &&
        _lastAccountDeviceSyncAt != null &&
        now.difference(_lastAccountDeviceSyncAt!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastAccountDeviceSyncAt = now;
    try {
      final peerId = (await bind.mainGetMyId()).trim();
      if (peerId.isEmpty) return;
      final deviceKey = await currentAccountDeviceKey();
      var deviceInfo = <String, dynamic>{};
      try {
        final decoded = jsonDecode(bind.mainGetLoginDeviceInfo());
        if (decoded is Map) {
          deviceInfo = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        debugPrint('KQ project API decode account device failed: $e');
      }
      final name = (deviceInfo['name'] ?? '').toString().trim();
      final os = (deviceInfo['os'] ?? '').toString().trim();
      await http
          .post(
            Uri.parse('$baseUrl/account-devices/current'),
            headers: _headers(token),
            body: jsonEncode({
              'id': peerId,
              'device_key': deviceKey,
              'alias': name,
              'hostname': name,
              'platform': _normalizeAccountDevicePlatform(os),
              'device_name': name,
              'device_type': (deviceInfo['type'] ?? '').toString(),
              'metadata': deviceInfo,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('KQ project API syncCurrentAccountDevice failed: $e');
    }
  }

  static Future<String> currentAccountDeviceKey() async {
    final uuid = (await bind.mainGetUuid()).trim();
    if (uuid.isNotEmpty) return uuid;
    return (await bind.mainGetMyId()).trim();
  }

  static Future<List<Peer>> fetchAccountDevices() async {
    return await tryFetchAccountDevices() ?? [];
  }

  static List<Peer> loadCachedAccountDevices() {
    try {
      final raw = bind.getLocalFlutterOption(k: _cachedAccountDevicesOptionKey);
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      final scope = _accountDeviceCacheScope();
      final items = decoded is Map
          ? decoded['scope'] == scope
              ? decoded['items']
              : null
          : decoded;
      if (items is! List) return [];
      return items
          .whereType<Map>()
          .map((item) => Peer.fromJson(Map<String, dynamic>.from(item)))
          .where((peer) => peer.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('KQ project API load cached account devices failed: $e');
      return [];
    }
  }

  static void cacheAccountDevices(List<Peer> peers) {
    final scope = _accountDeviceCacheScope();
    if (scope.isEmpty) return;
    try {
      bind.setLocalFlutterOption(
        k: _cachedAccountDevicesOptionKey,
        v: jsonEncode({
          'scope': scope,
          'items': peers.map(_accountDeviceToCacheJson).toList(),
        }),
      );
    } catch (e) {
      debugPrint('KQ project API cache account devices failed: $e');
    }
  }

  static Future<List<Peer>?> tryFetchAccountDevices() async {
    if (!isEnabled) return [];
    final token = _apiWebToken();
    if (token.isEmpty) return [];
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/account-devices'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'KQ project API tryFetchAccountDevices failed: HTTP ${response.statusCode}');
        return null;
      }
      final body = jsonDecode(decode_http_response(response));
      if (body is! Map || body['items'] is! List) {
        debugPrint(
            'KQ project API tryFetchAccountDevices failed: invalid body');
        return null;
      }
      return (body['items'] as List)
          .whereType<Map>()
          .map((item) => Peer.fromJson(Map<String, dynamic>.from(item)))
          .where((peer) => peer.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('KQ project API tryFetchAccountDevices failed: $e');
      return null;
    }
  }

  static Future<void> deleteConnectionHistory(String peerId) async {
    if (!isEnabled || peerId.trim().isEmpty) return;
    final token = _apiWebToken();
    if (token.isEmpty) return;
    try {
      final response = await http
          .delete(
            Uri.parse(
                '$baseUrl/connection-history/${Uri.encodeComponent(peerId)}'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'KQ project API deleteConnectionHistory failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('KQ project API deleteConnectionHistory failed: $e');
    }
  }

  static void markRecentPeerDeleted(String peerId) {
    final id = _normalizePeerId(peerId);
    if (id.isEmpty) return;
    final deleted = _loadDeletedRecentPeers();
    deleted[id] = DateTime.now();
    _storeDeletedRecentPeers(deleted);
  }

  static void clearRecentPeerDeleted(String peerId) {
    final id = _normalizePeerId(peerId);
    if (id.isEmpty) return;
    final deleted = _loadDeletedRecentPeers();
    if (deleted.remove(id) != null) {
      _storeDeletedRecentPeers(deleted);
    }
  }

  static List<Peer> filterDeletedRecentPeers(List<Peer> peers) {
    final deleted = _loadDeletedRecentPeers();
    if (deleted.isEmpty) return peers;
    return peers
        .where((peer) => !deleted.containsKey(_normalizePeerId(peer.id)))
        .toList();
  }

  static Future<void> recordPeer(Peer peer,
      {String connType = 'remote'}) async {
    if (!isEnabled) return;
    final token = _apiWebToken();
    if (token.isEmpty || peer.id.isEmpty) return;
    final json = _peerToSafeJson(peer);
    json['conn_type'] = connType;
    try {
      await http
          .post(
            Uri.parse('$baseUrl/connection-history'),
            headers: _headers(token),
            body: jsonEncode(json),
          )
          .timeout(const Duration(seconds: 6));
      clearRecentPeerDeleted(peer.id);
    } catch (e) {
      debugPrint('KQ project API recordPeer failed: $e');
    }
  }

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'token': token,
        'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _peerToSafeJson(Peer peer) => {
        'id': peer.id,
        'alias': peer.alias,
        'username': peer.username,
        'hostname': peer.hostname,
        'platform': peer.platform,
        'conn_type': 'remote',
      };

  static Map<String, dynamic> _accountDeviceToCacheJson(Peer peer) => {
        'id': peer.id,
        'username': peer.username,
        'hostname': peer.hostname,
        'platform': peer.platform,
        'alias': peer.alias,
        'online': peer.online,
        'onlineStateKnown': peer.onlineStateKnown,
        'loginName': peer.loginName,
        'device_group_name': peer.device_group_name,
        'note': peer.note,
        'same_server': peer.sameServer,
        'device_key': peer.accountDeviceKey,
      };

  static String _normalizeAccountDevicePlatform(String os) {
    final value = os.trim().toLowerCase();
    if (value.contains('android')) return kPeerPlatformAndroid;
    if (value.contains('ios') ||
        value.contains('iphone') ||
        value.contains('ipad')) {
      return 'iOS';
    }
    if (value.contains('mac') || value.contains('darwin')) {
      return kPeerPlatformMacOS;
    }
    if (value.contains('linux')) return kPeerPlatformLinux;
    if (value.contains('web')) return kPeerPlatformWebDesktop;
    return kPeerPlatformWindows;
  }

  static String _normalizePeerId(String id) =>
      id.replaceAll(RegExp(r'\s+'), '').trim();

  static String _accountDeviceCacheScope() {
    final userInfo = UserModel.getLocalUserInfo();
    if (userInfo != null) {
      for (final key in ['id', 'name', 'display_name']) {
        final value = (userInfo[key] ?? '').toString().trim();
        if (value.isNotEmpty) return '$key:$value';
      }
    }
    final token = _apiWebToken();
    if (token.isEmpty) return '';
    var hash = 0;
    for (final codeUnit in token.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x1fffffff;
    }
    return 'token:${token.length}:$hash';
  }

  static Map<String, DateTime> _loadDeletedRecentPeers() {
    final cached = _deletedRecentPeers;
    if (cached != null) {
      _pruneDeletedRecentPeers(cached);
      return cached;
    }
    final loaded = <String, DateTime>{};
    try {
      final raw = bind.getLocalFlutterOption(k: _deletedRecentPeerOptionKey);
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final id = _normalizePeerId(key.toString());
          final millis = int.tryParse(value.toString());
          if (id.isEmpty || millis == null) return;
          loaded[id] = DateTime.fromMillisecondsSinceEpoch(millis);
        });
      }
    } catch (e) {
      debugPrint('KQ project API load deleted recent peers failed: $e');
    }
    _deletedRecentPeers = loaded;
    _pruneDeletedRecentPeers(loaded);
    return loaded;
  }

  static void _storeDeletedRecentPeers(Map<String, DateTime> peers) {
    _deletedRecentPeers = peers;
    try {
      final json = peers.map((key, value) =>
          MapEntry(key, value.millisecondsSinceEpoch.toString()));
      bind.setLocalFlutterOption(
        k: _deletedRecentPeerOptionKey,
        v: jsonEncode(json),
      );
    } catch (e) {
      debugPrint('KQ project API store deleted recent peers failed: $e');
    }
  }

  static void _pruneDeletedRecentPeers(Map<String, DateTime> peers) {
    final now = DateTime.now();
    final before = peers.length;
    peers.removeWhere(
        (_, deletedAt) => now.difference(deletedAt) > _deletedRecentPeerTtl);
    if (peers.length != before) {
      _storeDeletedRecentPeers(peers);
    }
  }

  static String _apiWebToken() {
    final values = <String>[
      bind.mainGetLocalOption(key: 'access_token'),
      bind.mainGetLocalOption(key: 'kq_api_web_token'),
      bind.mainGetLocalOption(key: 'api_web_token'),
      bind.mainGetLocalOption(key: 'kq_token'),
      bind.mainGetLocalOption(key: 'user_token'),
    ];
    final userInfo = UserModel.getLocalUserInfo();
    if (userInfo != null) {
      for (final key in [
        'api_web_token',
        'apiWebToken',
        'kq_token',
        'token',
        'user_token'
      ]) {
        values.add((userInfo[key] ?? '').toString());
      }
      final raw = userInfo['external_auth_raw'];
      if (raw is Map) {
        for (final key in [
          'api_web_token',
          'apiWebToken',
          'kq_token',
          'token',
          'user_token',
          'access_token'
        ]) {
          values.add((raw[key] ?? '').toString());
        }
      }
    }
    final seen = <String>{};
    final orderedTokens = <String>[];
    for (final value in values) {
      final token = value
          .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
      if (token.isEmpty || !seen.add(token)) {
        continue;
      }
      orderedTokens.add(token);
    }
    return orderedTokens.isEmpty ? '' : orderedTokens.first;
  }
}
