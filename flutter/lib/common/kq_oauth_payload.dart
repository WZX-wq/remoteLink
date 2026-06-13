import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class KqDesktopLoginNonce {
  final String nonce;
  final int timestamp;
  final String signature;

  const KqDesktopLoginNonce({
    required this.nonce,
    required this.timestamp,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'nonce': nonce,
        'timestamp': timestamp,
        'signature': signature,
      };
}

class KqOauthLoginPayload {
  final String accessToken;
  final Map<String, dynamic> user;

  const KqOauthLoginPayload({
    required this.accessToken,
    required this.user,
  });
}

KqDesktopLoginNonce generateKqDesktopLoginNonce({
  required String secretKey,
  String? nonce,
  int? timestamp,
}) {
  final rawNonce = nonce ?? const Uuid().v4().replaceAll('-', '');
  final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final message = utf8.encode('$rawNonce|$ts');
  final key = utf8.encode(secretKey);
  final signature = base64Encode(Hmac(sha256, key).convert(message).bytes);
  return KqDesktopLoginNonce(
    nonce: rawNonce,
    timestamp: ts,
    signature: signature,
  );
}

String encodeKqDesktopLoginNonce(KqDesktopLoginNonce signedNonce) {
  final json = jsonEncode(signedNonce.toJson());
  return base64UrlEncode(utf8.encode(json)).replaceAll('=', '');
}

Uri buildKqDesktopLoginUri({
  required String webLoginUrl,
  required String clientNonce,
}) {
  return Uri.parse(webLoginUrl).replace(queryParameters: {
    'client_type': 'desktop',
    'client_nonce': clientNonce,
  });
}

Map<String, dynamic> extractKqApiData(Map<String, dynamic> body,
    {String fallbackMessage = 'Kunqiong API request failed'}) {
  if (!_isSuccessCode(body['code'])) {
    final message = (body['msg'] ?? body['message'])?.toString();
    throw FormatException(
        message == null || message.isEmpty ? fallbackMessage : message);
  }
  final data = body['data'];
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  if (data == null) {
    return {};
  }
  throw const FormatException('Kunqiong API response data is invalid.');
}

String extractKqWebLoginUrl(Map<String, dynamic> body) {
  final data = extractKqApiData(body,
      fallbackMessage: 'Failed to get Kunqiong web login URL.');
  final loginUrl = data['login_url']?.toString().trim();
  if (loginUrl == null || loginUrl.isEmpty) {
    throw const FormatException('Kunqiong web login URL is missing.');
  }
  return loginUrl;
}

String? extractKqDesktopTokenIfReady(Map<String, dynamic> body) {
  if (!_isSuccessCode(body['code'])) {
    return null;
  }
  final data = body['data'];
  if (data is! Map) {
    return null;
  }
  final token = data['token']?.toString().trim();
  return token == null || token.isEmpty ? null : token;
}

bool parseKqCheckLoginResult(Map<String, dynamic> body) =>
    _isSuccessCode(body['code']);

KqOauthLoginPayload parseKqOauthLoginPayload({
  required String token,
  required Map<String, dynamic> userInfoResponse,
}) {
  final data = extractKqApiData(userInfoResponse,
      fallbackMessage: 'Failed to get Kunqiong user info.');
  final user = normalizeKqOauthUser(data['user_info']);
  if (token.trim().isEmpty || user == null) {
    throw const FormatException(
        'Kunqiong login response is missing token or user.');
  }
  return KqOauthLoginPayload(accessToken: token.trim(), user: user);
}

bool _isSuccessCode(dynamic value) {
  if (value is int) return value == 1;
  if (value is String) return int.tryParse(value) == 1;
  return false;
}

Map<String, dynamic>? normalizeKqOauthUser(dynamic value) {
  if (value is! Map) return null;
  final nickname = (value['nickname'] ??
          value['username'] ??
          value['name'] ??
          value['id'] ??
          '')
      .toString()
      .trim();
  if (nickname.isEmpty) return null;
  final id = (value['id'] ?? nickname).toString();
  return {
    'id': id,
    'name': nickname,
    'display_name': nickname,
    'avatar': (value['avatar'] ?? value['avatar_url'])?.toString() ?? '',
    'email': value['email']?.toString() ?? '',
    'status': 1,
    'is_admin': false,
  };
}
