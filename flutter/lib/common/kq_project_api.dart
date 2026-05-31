import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

import '../common.dart';

class KqProjectApi {
  static const optionKey = 'kq_project_api_server';
  static const buildinOptionKey = 'kq-project-api-server';

  static DateTime? _lastSyncAt;
  static String _lastSyncSignature = '';

  static String get baseUrl {
    final local = bind.mainGetLocalOption(key: optionKey).trim();
    final buildin = bind.mainGetBuildinOption(key: buildinOptionKey).trim();
    final value = local.isNotEmpty ? local : buildin;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  static bool get isEnabled => baseUrl.isNotEmpty;

  static int get recentHistoryLimit =>
      bind.mainGetLocalOption(key: UserModel.memberActiveKey) == 'Y' ? 50 : 5;

  static Future<void> syncRecentPeers(List<Peer> peers) async {
    if (!isEnabled || peers.isEmpty) return;
    final token = _apiWebToken();
    if (token.isEmpty) return;
    final limit = recentHistoryLimit;
    final safePeers = peers.take(limit).map(_peerToSafeJson).toList();
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

  static String _apiWebToken() {
    final values = <String>[
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
    final uuidTokens = <String>[];
    final otherTokens = <String>[];
    for (final value in values) {
      final token = value
          .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
      if (token.isEmpty || token.split('.').length == 3 || !seen.add(token)) {
        continue;
      }
      if (_looksLikeUuid(token)) {
        uuidTokens.add(token);
      } else {
        otherTokens.add(token);
      }
    }
    final ordered = [...uuidTokens, ...otherTokens];
    return ordered.isEmpty ? '' : ordered.first;
  }

  static bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);
  }
}
