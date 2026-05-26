import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/kq_oauth_payload.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const kKqOauthProvider = 'kunqiong';
const kKqOauthProviderKey = 'external_auth_provider';

const _clientId = 'app_e866d8c8242e2c2b';
const _clientSecret = '19a43485a13c75fe451ec2e61148027e';
const _redirectUri = 'http://localhost:6613/oauth/callback';
const _authorizeUrl = 'https://login.kunqiongai.com/authorize.html';
const _tokenUrl = 'https://login.kunqiongai.com/api/oauth/token';
const _callbackPath = '/oauth/callback';

class KqOauthException implements Exception {
  final String message;

  KqOauthException(this.message);

  @override
  String toString() => message;
}

class KqOauth {
  static HttpServer? _activeServer;

  static bool get isActive =>
      bind.mainGetLocalOption(key: kKqOauthProviderKey) == kKqOauthProvider;

  static Future<LoginResponse> login() async {
    final state = _randomState();
    final server = await _bindCallbackServer();
    _activeServer = server;
    try {
      final authUri = buildKqOauthAuthorizeUri(
        authorizeUrl: _authorizeUrl,
        clientId: _clientId,
        redirectUri: _redirectUri,
        state: state,
      );

      final launched =
          await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw KqOauthException('Unable to open the authorization page.');
      }

      final code = await _waitForCallback(server, state);
      final body = await _exchangeToken(code);
      final response = _toLoginResponse(body);
      await _storeLogin(response, body);
      return response;
    } finally {
      await server.close(force: true);
      if (identical(_activeServer, server)) {
        _activeServer = null;
      }
    }
  }

  static void cancel() {
    final server = _activeServer;
    _activeServer = null;
    server?.close(force: true);
  }

  static Future<HttpServer> _bindCallbackServer() async {
    try {
      return await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        6613,
        v6Only: false,
      );
    } on SocketException {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, 6613);
      } on SocketException {
        throw KqOauthException(
            'Unable to listen on localhost:6613. Please close the app using that port and try again.');
      }
    }
  }

  static Future<String> _waitForCallback(
      HttpServer server, String expectedState) async {
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    final iterator = StreamIterator<HttpRequest>(server);
    try {
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining.inMilliseconds <= 0) {
          throw KqOauthException('Authorization timed out.');
        }

        final hasRequest = await iterator.moveNext().timeout(
              remaining,
              onTimeout: () =>
                  throw KqOauthException('Authorization timed out.'),
            );
        if (!hasRequest) {
          throw KqOauthException('Authorization canceled.');
        }
        final request = iterator.current;

        final error = parseKqOauthCallbackError(
          request.uri,
          expectedState,
          callbackPath: _callbackPath,
        );
        final valid = isKqOauthCallbackSuccess(
          request.uri,
          expectedState,
          callbackPath: _callbackPath,
        );

        request.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        request.response.write(_callbackHtml(valid, error));
        await request.response.close();

        if (error != null && error.isNotEmpty) {
          throw KqOauthException(error);
        }
        try {
          return parseKqOauthCallbackCode(
            request.uri,
            expectedState,
            callbackPath: _callbackPath,
          );
        } on FormatException {
          continue;
        }
      }
    } finally {
      await iterator.cancel();
    }
  }

  static Future<Map<String, dynamic>> _exchangeToken(String code) async {
    final params = {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'redirect_uri': _redirectUri,
    };
    var resp = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(params),
    );
    var decoded = _tryDecodeTokenResponse(resp);
    if (resp.statusCode != 200 || !_isTokenResponseSuccess(decoded)) {
      resp = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: params).query,
      );
      decoded = _decodeTokenResponse(resp);
    }
    final tokenBody = decoded;
    if (resp.statusCode != 200 || tokenBody == null) {
      throw KqOauthException(
          (tokenBody?['message'] ?? 'OAuth token exchange failed').toString());
    }
    return _extractTokenData(tokenBody);
  }

  static bool _isTokenResponseSuccess(Map<String, dynamic>? body) {
    if (body == null) return false;
    try {
      extractKqOauthTokenData(body);
      return true;
    } on FormatException {
      return false;
    }
  }

  static Map<String, dynamic> _extractTokenData(Map<String, dynamic> body) {
    try {
      return extractKqOauthTokenData(body);
    } on FormatException catch (err) {
      throw KqOauthException(err.message);
    }
  }

  static Map<String, dynamic>? _tryDecodeTokenResponse(http.Response resp) {
    try {
      return _decodeTokenResponse(resp);
    } on KqOauthException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic> _decodeTokenResponse(http.Response resp) {
    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw KqOauthException('Invalid token response.');
    }
    return decoded;
  }

  static LoginResponse _toLoginResponse(Map<String, dynamic> data) {
    final payload = _parseLoginPayload(data);
    return LoginResponse.fromJson({
      'type': HttpType.kAuthResTypeToken,
      'access_token': payload.accessToken,
      'user': payload.user,
    });
  }

  static KqOauthLoginPayload _parseLoginPayload(Map<String, dynamic> data) {
    try {
      return parseKqOauthLoginPayload(data);
    } on FormatException catch (err) {
      throw KqOauthException(err.message);
    }
  }

  static Future<void> _storeLogin(
      LoginResponse response, Map<String, dynamic> rawData) async {
    await bind.mainSetLocalOption(
        key: 'access_token', value: response.access_token ?? '');
    await bind.mainSetLocalOption(
        key: kKqOauthProviderKey, value: kKqOauthProvider);
    await bind.mainSetLocalOption(
      key: 'user_info',
      value: jsonEncode({
        'name': response.user?.name ?? '',
        'display_name': response.user?.displayName ?? '',
        'avatar': response.user?.avatar ?? '',
        'email': response.user?.email ?? '',
        'status': 1,
        'external_auth_provider': kKqOauthProvider,
        'external_auth_raw': rawData,
      }),
    );
  }

  static String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _callbackHtml(bool success, String? error) {
    final escape = const HtmlEscape().convert;
    final title = escape(success ? 'Login successful' : 'Login failed');
    final detail = escape(success
        ? 'You can return to the remote desktop client.'
        : (error == null || error.isEmpty ? 'Authorization failed.' : error));
    return '''
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>$title</title></head>
  <body style="font-family: sans-serif; padding: 32px;">
    <h2>$title</h2>
    <p>$detail</p>
    <script>setTimeout(function(){ window.close(); }, 1200);</script>
  </body>
</html>
''';
  }
}
