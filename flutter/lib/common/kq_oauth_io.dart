import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/kq_oauth_payload.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const kKqOauthProvider = 'kunqiong';
const kKqOauthProviderKey = 'external_auth_provider';

const _apiBaseUrl = 'https://api-web.kunqiongai.com';
const _loginBaseUrl = 'https://login.kunqiongai.com';
const _secretKey = '7530bfb1ad6c41627b0f0620078fa5ed';
const _passwordLoginPath = '/api/auth/login';
const _registerPath = '/api/auth/register';
const _smsSendPath = '/api/sms/send';
const _smsLoginPath = '/api/auth/login/phone';
const _passwordResetPath = '/api/auth/password/reset';
const _webLoginUrlPath = '/soft_desktop/get_web_login_url';
const _desktopTokenPath = '/user/desktop_get_token';
const _checkLoginPath = '/user/check_login';
const _userInfoPath = '/soft_desktop/get_user_info';
const _logoutPath = '/logout';

class KqOauthException implements Exception {
  final String message;

  KqOauthException(this.message);

  @override
  String toString() => message;
}

class KqOauth {
  static _AuthView? _activeBrowser;
  static Future<LoginResponse>? _activeLogin;
  static bool _cancelRequested = false;

  static bool get isActive =>
      bind.mainGetLocalOption(key: kKqOauthProviderKey) == kKqOauthProvider;

  static Future<LoginResponse> login() async {
    if (_activeLogin != null) {
      await _cancelActiveLogin();
    }
    _cancelRequested = false;
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

  static Future<LoginResponse> loginWithPassword({
    required String username,
    required String password,
  }) async {
    final body = await _postLoginJson(_passwordLoginPath, {
      'username': username.trim(),
      'password': password,
    });
    final response = _toNativeLoginResponse(body);
    await _storeLogin(response, body);
    return response;
  }

  static Future<void> sendSmsCode({
    required String phone,
    String purpose = 'login',
  }) async {
    await _postLoginJson(_smsSendPath, {
      'phone': phone.trim(),
      'purpose': purpose,
    });
  }

  static Future<LoginResponse> loginWithSms({
    required String phone,
    required String code,
  }) async {
    final body = await _postLoginJson(_smsLoginPath, {
      'phone': phone.trim(),
      'code': code.trim(),
    });
    final response = _toNativeLoginResponse(body);
    await _storeLogin(response, body);
    return response;
  }

  static Future<LoginResponse> registerWithPhone({
    required String username,
    required String phone,
    required String code,
    required String password,
  }) async {
    final body = await _postLoginJson(_registerPath, {
      'username': username.trim(),
      'phone': phone.trim(),
      'code': code.trim(),
      'password': password,
      'password_confirmation': password,
    });
    try {
      final response = _toNativeLoginResponse(body);
      await _storeLogin(response, body);
      return response;
    } on KqOauthException {
      return loginWithPassword(username: phone, password: password);
    }
  }

  static Future<LoginResponse> resetPasswordWithPhone({
    required String phone,
    required String code,
    required String password,
  }) async {
    await _postLoginJson(_passwordResetPath, {
      'phone': phone.trim(),
      'code': code.trim(),
      'password': password,
      'password_confirmation': password,
    });
    return loginWithPassword(username: phone, password: password);
  }

  static Future<LoginResponse> _loginOnce() async {
    final existing = await _restoreExistingLogin();
    if (existing != null) {
      return existing;
    }

    final encodedNonce = encodeKqDesktopLoginNonce(
      generateKqDesktopLoginNonce(secretKey: _secretKey),
    );
    final webLoginUrl = await _getWebLoginUrl();
    final loginUri = buildKqDesktopLoginUri(
      webLoginUrl: webLoginUrl,
      clientNonce: encodedNonce,
    );

    final authBrowser = await _openAuthorization(loginUri);
    _activeBrowser = authBrowser;
    try {
      final token = await _pollToken(encodedNonce, authBrowser);
      await authBrowser?.close();
      final userInfoResponse = await _getUserInfo(token);
      final response = _toLoginResponse(token, userInfoResponse);
      await _storeLogin(response, userInfoResponse);
      return response;
    } finally {
      await authBrowser?.close();
      if (identical(_activeBrowser, authBrowser)) {
        _activeBrowser = null;
      }
    }
  }

  static void cancel() {
    unawaited(_cancelActiveLogin());
  }

  static Future<void> logout() async {
    final token = bind.mainGetLocalOption(key: 'access_token').trim();
    if (token.isEmpty) {
      return;
    }
    try {
      await _postForm(
        _logoutPath,
        headers: {'token': token},
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Local logout must still succeed when the web API is unavailable.
    }
  }

  static Future<bool> checkLogin() async {
    final token = bind.mainGetLocalOption(key: 'access_token').trim();
    if (token.isEmpty) {
      return false;
    }
    final body = await _postForm(_checkLoginPath, body: {'token': token});
    return parseKqCheckLoginResult(body);
  }

  static Future<LoginResponse?> _restoreExistingLogin() async {
    if (!isActive) {
      return null;
    }
    final token = bind.mainGetLocalOption(key: 'access_token').trim();
    if (token.isEmpty) {
      return null;
    }
    try {
      if (!await checkLogin()) {
        await _clearStoredLogin();
        return null;
      }
      final userInfoResponse = await _getUserInfo(token);
      final response = _toLoginResponse(token, userInfoResponse);
      await _storeLogin(response, userInfoResponse);
      return response;
    } catch (_) {
      await _clearStoredLogin();
      return null;
    }
  }

  static Future<void> _cancelActiveLogin() async {
    _cancelRequested = true;
    final browser = _activeBrowser;
    _activeBrowser = null;
    _activeLogin = null;
    if (browser != null) {
      unawaited(browser.close());
    }
  }

  static Future<String> _getWebLoginUrl() async {
    final body = await _postForm(_webLoginUrlPath);
    try {
      return extractKqWebLoginUrl(body);
    } on FormatException catch (err) {
      throw KqOauthException(err.message);
    }
  }

  static Future<String> _pollToken(
      String encodedNonce, _AuthView? authBrowser) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (_cancelRequested) {
        throw KqOauthException('Authorization canceled.');
      }
      if (authBrowser != null && await authBrowser.isUserClosed()) {
        throw KqOauthException('Authorization canceled.');
      }
      try {
        final body = await _postForm(_desktopTokenPath, body: {
          'client_type': 'desktop',
          'client_nonce': encodedNonce,
        }).timeout(const Duration(seconds: 8));
        final token = extractKqDesktopTokenIfReady(body);
        if (token != null) {
          return token;
        }
      } catch (err) {
        if (err is KqOauthException) {
          rethrow;
        }
        // The server can return "not logged in yet" or transient network
        // errors while the user is still completing the browser login.
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw KqOauthException('Authorization timed out.');
  }

  static Future<Map<String, dynamic>> _getUserInfo(String token) async {
    return await _postForm(_userInfoPath, headers: {'token': token});
  }

  static Future<Map<String, dynamic>> _postForm(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? body,
  }) async {
    final requestHeaders = {
      'Content-Type': 'application/x-www-form-urlencoded',
      ...?headers,
    };
    final resp = await http.post(
      Uri.parse('$_apiBaseUrl$path'),
      headers: requestHeaders,
      body: body == null ? null : Uri(queryParameters: body).query,
    );
    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw KqOauthException('Invalid Kunqiong API response.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final message = (decoded['msg'] ?? decoded['message'])?.toString();
      throw KqOauthException(message == null || message.isEmpty
          ? 'Kunqiong API request failed.'
          : message);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> _postLoginJson(
    String path,
    Map<String, String> body,
  ) async {
    final resp = await http.post(
      Uri.parse('$_loginBaseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw KqOauthException('Invalid Kunqiong login response.');
    }
    final code = int.tryParse((decoded['code'] ?? '').toString());
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        (code != null && code != 200)) {
      throw KqOauthException(_extractLoginErrorMessage(decoded));
    }
    return decoded;
  }

  static String _extractLoginErrorMessage(Map<String, dynamic> decoded) {
    final errors = decoded['errors'];
    if (errors is Map) {
      final parts = <String>[];
      for (final value in errors.values) {
        if (value is Iterable) {
          parts.addAll(value
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty));
        } else if (value != null) {
          final text = value.toString().trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
      if (parts.isNotEmpty) {
        return parts.toSet().join('\n');
      }
    }
    final message = (decoded['message'] ?? decoded['msg'])?.toString().trim();
    return message == null || message.isEmpty
        ? 'Kunqiong login request failed.'
        : message;
  }

  static Future<_AuthView?> _openAuthorization(Uri authUri) async {
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

    if (Platform.isAndroid || Platform.isIOS) {
      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.inAppWebView,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );
      if (!launched) {
        throw KqOauthException('Unable to open the Kunqiong login page.');
      }
      return const _InAppAuthView();
    }

    final launched =
        await launchUrl(authUri, mode: LaunchMode.externalApplication);
    if (!launched) {
      final detail = managedBrowserError == null
          ? ''
          : ' Managed browser error: $managedBrowserError';
      throw KqOauthException('Unable to open the Kunqiong login page.$detail');
    }
    return null;
  }

  static LoginResponse _toLoginResponse(
      String token, Map<String, dynamic> userInfoResponse) {
    final payload = _parseLoginPayload(token, userInfoResponse);
    return LoginResponse.fromJson({
      'type': HttpType.kAuthResTypeToken,
      'access_token': payload.accessToken,
      'user': payload.user,
    });
  }

  static LoginResponse _toNativeLoginResponse(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! Map) {
      throw KqOauthException('Kunqiong login response data is empty.');
    }
    final accessToken =
        (data['api_web_token'] ?? data['access_token'] ?? '').toString().trim();
    final jwtToken = (data['access_token'] ?? '').toString().trim();
    final user = normalizeKqOauthUser(data['user']);
    if (accessToken.isEmpty || user == null) {
      throw KqOauthException(
          'Kunqiong login response is missing token or user.');
    }
    return LoginResponse.fromJson({
      'type': HttpType.kAuthResTypeToken,
      'access_token': accessToken,
      'user': {
        ...user,
        'api_web_token': accessToken,
        'kq_token': jwtToken,
        'token': jwtToken,
      },
    });
  }

  static KqOauthLoginPayload _parseLoginPayload(
      String token, Map<String, dynamic> userInfoResponse) {
    try {
      return parseKqOauthLoginPayload(
        token: token,
        userInfoResponse: userInfoResponse,
      );
    } on FormatException catch (err) {
      throw KqOauthException(err.message);
    }
  }

  static Future<void> _storeLogin(
      LoginResponse response, Map<String, dynamic> rawUserInfoResponse) async {
    await bind.mainSetLocalOption(
        key: 'access_token', value: response.access_token ?? '');
    final rawData = rawUserInfoResponse['data'];
    String apiWebToken = '';
    String jwtToken = '';
    if (rawData is Map) {
      apiWebToken = (rawData['api_web_token'] ?? '').toString().trim();
      jwtToken = (rawData['access_token'] ?? '').toString().trim();
    }
    if (apiWebToken.isNotEmpty) {
      await bind.mainSetLocalOption(
          key: 'kq_api_web_token', value: apiWebToken);
      await bind.mainSetLocalOption(key: 'api_web_token', value: apiWebToken);
    }
    if (jwtToken.isNotEmpty) {
      await bind.mainSetLocalOption(key: 'kq_token', value: jwtToken);
      await bind.mainSetLocalOption(key: 'user_token', value: jwtToken);
    }
    await bind.mainSetLocalOption(
        key: kKqOauthProviderKey, value: kKqOauthProvider);
    await bind.mainSetLocalOption(
      key: 'user_info',
      value: jsonEncode({
        'id': response.user?.id ?? '',
        'name': response.user?.name ?? '',
        'display_name': response.user?.displayName ?? '',
        'avatar': response.user?.avatar ?? '',
        'email': response.user?.email ?? '',
        'status': 1,
        'api_web_token': apiWebToken,
        'kq_token': jwtToken,
        'token': jwtToken,
        'external_auth_provider': kKqOauthProvider,
        'external_auth_raw': rawUserInfoResponse,
      }),
    );
  }

  static Future<void> _clearStoredLogin() async {
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    await bind.mainSetLocalOption(key: kKqOauthProviderKey, value: '');
  }
}

abstract class _AuthView {
  Future<void> close();

  Future<bool> isUserClosed();
}

class _InAppAuthView implements _AuthView {
  const _InAppAuthView();

  @override
  Future<void> close() async {
    try {
      await closeInAppWebView();
    } catch (_) {
      // Some platforms cannot close an already-dismissed in-app WebView.
    }
  }

  @override
  Future<bool> isUserClosed() async => false;
}

class _ManagedAuthBrowser implements _AuthView {
  final Process _process;
  final Directory _profileDir;
  bool _closed = false;

  _ManagedAuthBrowser._(this._process, this._profileDir);

  static Future<_ManagedAuthBrowser?> start(Uri authUri) async {
    final browserPath = _findBrowserPath();
    if (browserPath == null) {
      return null;
    }

    final profileDir = await Directory.systemTemp.createTemp('kq_login_');
    try {
      final process = await Process.start(browserPath, [
        '--user-data-dir=${profileDir.path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-sync',
        '--app=${authUri.toString()}',
        '--window-size=1360,820',
      ]);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      return _ManagedAuthBrowser._(process, profileDir);
    } catch (_) {
      await _deleteProfileDir(profileDir);
      rethrow;
    }
  }

  @override
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

  @override
  Future<bool> isUserClosed() async {
    if (_closed) {
      return true;
    }
    if (Platform.isWindows) {
      return !await _hasWindowsBrowserProcesses();
    }
    return _process.exitCode
        .timeout(
          const Duration(milliseconds: 1),
          onTimeout: () => -1,
        )
        .then((code) => code != -1);
  }

  Future<bool> _hasWindowsBrowserProcesses() async {
    final profilePath = _profileDir.path.replaceAll("'", "''");
    final script = "\$profile = '$profilePath'; "
        "\$process = Get-CimInstance Win32_Process | "
        "Where-Object { \$_.ProcessId -ne \$PID -and \$_.CommandLine -and \$_.CommandLine.Contains(\$profile) } | "
        "Select-Object -First 1; "
        "if (\$null -eq \$process) { '0' } else { '1' }";
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 3));
      return result.stdout.toString().trim() == '1';
    } catch (err) {
      _logCleanupFailure('detect browser close', err);
      return true;
    }
  }

  Future<void> _terminateWindowsBrowserProcesses() async {
    final profilePath = _profileDir.path.replaceAll("'", "''");
    final script = "\$profile = '$profilePath'; "
        "Get-CimInstance Win32_Process | "
        "Where-Object { \$_.ProcessId -ne \$PID -and \$_.CommandLine -and \$_.CommandLine.Contains(\$profile) } | "
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
      stderr.writeln('KQ login browser cleanup failed ($action): $error');
    } catch (_) {
      // Cleanup logging must not affect login.
    }
  }
}
