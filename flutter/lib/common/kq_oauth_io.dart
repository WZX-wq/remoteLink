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
const _callbackPort = 6613;
const _authorizeUrl = 'https://login.kunqiongai.com/authorize.html';
const _tokenUrl = 'https://login.kunqiongai.com/api/oauth/token';
const _callbackPath = '/oauth/callback';

class KqOauthException implements Exception {
  final String message;

  KqOauthException(this.message);

  @override
  String toString() => message;
}

class _CallbackServer {
  final HttpServer server;
  final String redirectUri;

  const _CallbackServer(this.server, this.redirectUri);
}

class KqOauth {
  static HttpServer? _activeServer;
  static Future<LoginResponse>? _activeLogin;

  static bool get isActive =>
      bind.mainGetLocalOption(key: kKqOauthProviderKey) == kKqOauthProvider;

  static Future<LoginResponse> login() async {
    final activeLogin = _activeLogin;
    if (activeLogin != null) {
      return activeLogin;
    }
    final loginFuture = _loginOnce();
    _activeLogin = loginFuture;
    try {
      return await loginFuture;
    } finally {
      if (identical(_activeLogin, loginFuture)) {
        _activeLogin = null;
      }
    }
  }

  static Future<LoginResponse> _loginOnce() async {
    final state = _randomState();
    final callback = await _bindCallbackServer();
    _activeServer = callback.server;
    try {
      final authUri = buildKqOauthAuthorizeUri(
        authorizeUrl: _authorizeUrl,
        clientId: _clientId,
        redirectUri: _redirectUri,
        state: state,
      );

      final authBrowser = await _openAuthorization(authUri);
      try {
        final code = await _waitForCallback(callback.server, state);
        await authBrowser?.close();
        final body = await _exchangeToken(code);
        final response = _toLoginResponse(body);
        await _storeLogin(response, body);
        return response;
      } finally {
        await authBrowser?.close();
      }
    } finally {
      await callback.server.close(force: true);
      if (identical(_activeServer, callback.server)) {
        _activeServer = null;
      }
    }
  }

  static void cancel() {
    final server = _activeServer;
    _activeServer = null;
    _activeLogin = null;
    server?.close(force: true);
  }

  static Future<_CallbackServer> _bindCallbackServer() async {
    await _activeServer?.close(force: true);
    _activeServer = null;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        _callbackPort,
        v6Only: false,
      );
      return _CallbackServer(server, _redirectUri);
    } on SocketException {
      try {
        final server =
            await HttpServer.bind(InternetAddress.loopbackIPv4, _callbackPort);
        return _CallbackServer(server, _redirectUri);
      } on SocketException {
        throw KqOauthException(
            'Login callback port 6613 is already in use. Close the existing login page and try again.');
      }
    }
  }

  static Future<_ManagedAuthBrowser?> _openAuthorization(Uri authUri) async {
    Object? managedBrowserError;
    if (Platform.isWindows) {
      try {
        final browser = await _ManagedAuthBrowser.start(authUri);
        if (browser != null) {
          return browser;
        }
      } catch (err) {
        managedBrowserError = err;
      }
    }

    final launched =
        await launchUrl(authUri, mode: LaunchMode.externalApplication);
    if (!launched) {
      final detail = managedBrowserError == null
          ? ''
          : ' Managed browser error: $managedBrowserError';
      throw KqOauthException('Unable to open the authorization page.$detail');
    }
    return null;
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
    if (success) {
      return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Login completed</title>
    <script>
      function closePage() {
        try { window.opener = null; } catch (_) {}
        window.open('', '_self');
        window.close();
      }
      function showFallback() {
        var el = document.getElementById('fallback');
        if (el) el.style.display = 'block';
      }
      window.addEventListener('load', function() {
        closePage();
        setTimeout(closePage, 100);
        setTimeout(closePage, 400);
        setTimeout(closePage, 900);
        setTimeout(showFallback, 1200);
      });
    </script>
  </head>
  <body style="font-family:sans-serif;padding:24px;color:#1f2937;">
    <div id="fallback" style="display:none;">
      <h2 style="margin:0 0 12px;font-size:20px;">Login completed</h2>
      <p style="margin:0;font-size:14px;">Kunqiong Remote Desktop login is complete. You can close this page.</p>
    </div>
  </body>
</html>
''';
    }
    final title = escape('Login failed');
    final detail = escape(
        error == null || error.isEmpty ? 'Authorization failed.' : error);
    return '''
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>$title</title></head>
  <body style="font-family: sans-serif; padding: 32px;">
    <h2>$title</h2>
    <p>$detail</p>
  </body>
</html>
''';
  }
}

class _ManagedAuthBrowser {
  final Process _process;
  final Directory _profileDir;
  bool _closed = false;

  _ManagedAuthBrowser._(this._process, this._profileDir);

  static Future<_ManagedAuthBrowser?> start(Uri authUri) async {
    final browserPath = _findBrowserPath();
    if (browserPath == null) {
      return null;
    }

    final profileDir = await Directory.systemTemp.createTemp('kq_oauth_');
    try {
      final process = await Process.start(browserPath, [
        '--user-data-dir=${profileDir.path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-sync',
        '--app=${authUri.toString()}',
        '--window-size=980,760',
      ]);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      return _ManagedAuthBrowser._(process, profileDir);
    } catch (_) {
      await _deleteProfileDir(profileDir);
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    if (Platform.isWindows) {
      await _terminateWindowsBrowserProcesses();
    } else {
      _process.kill();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _deleteProfileDir(_profileDir);
  }

  Future<void> _terminateWindowsBrowserProcesses() async {
    final profilePath = _profileDir.path.replaceAll("'", "''");
    final script = "\$profile = '$profilePath'; "
        "Get-CimInstance Win32_Process | "
        "Where-Object { \$_.CommandLine -and \$_.CommandLine.Contains(\$profile) } | "
        "ForEach-Object { Invoke-CimMethod -InputObject \$_ -MethodName Terminate | Out-Null }";
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 3));
    } catch (err) {
      _logCleanupFailure('terminate by profile', err);
    }

    try {
      await Process.run('taskkill', [
        '/PID',
        _process.pid.toString(),
        '/T',
        '/F',
      ]).timeout(const Duration(seconds: 3));
    } catch (err) {
      _logCleanupFailure('terminate by pid', err);
    }
  }

  static String? _findBrowserPath() {
    final env = Platform.environment;
    final candidates = <String?>[
      _joinPath(env['ProgramFiles(x86)'],
          ['Microsoft', 'Edge', 'Application', 'msedge.exe']),
      _joinPath(env['PROGRAMFILES(X86)'],
          ['Microsoft', 'Edge', 'Application', 'msedge.exe']),
      _joinPath(env['ProgramFiles'],
          ['Microsoft', 'Edge', 'Application', 'msedge.exe']),
      _joinPath(env['PROGRAMFILES'],
          ['Microsoft', 'Edge', 'Application', 'msedge.exe']),
      _joinPath(env['LOCALAPPDATA'],
          ['Microsoft', 'Edge', 'Application', 'msedge.exe']),
      _joinPath(env['ProgramFiles'],
          ['Google', 'Chrome', 'Application', 'chrome.exe']),
      _joinPath(env['PROGRAMFILES'],
          ['Google', 'Chrome', 'Application', 'chrome.exe']),
      _joinPath(env['ProgramFiles(x86)'],
          ['Google', 'Chrome', 'Application', 'chrome.exe']),
      _joinPath(env['PROGRAMFILES(X86)'],
          ['Google', 'Chrome', 'Application', 'chrome.exe']),
      _joinPath(env['LOCALAPPDATA'],
          ['Google', 'Chrome', 'Application', 'chrome.exe']),
    ];

    for (final candidate in candidates) {
      if (candidate != null && File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static String? _joinPath(String? root, List<String> parts) {
    if (root == null || root.isEmpty) {
      return null;
    }
    return ([root, ...parts]).join(Platform.pathSeparator);
  }

  static Future<void> _deleteProfileDir(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (err) {
      _logCleanupFailure('delete profile', err);
    }
  }

  static void _logCleanupFailure(String action, Object error) {
    try {
      stderr.writeln('KQ OAuth browser cleanup failed ($action): $error');
    } catch (_) {
      // Nothing else to do; cleanup logging must not affect login.
    }
  }
}
