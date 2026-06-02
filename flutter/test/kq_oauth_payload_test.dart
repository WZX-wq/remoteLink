import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/kq_oauth_payload.dart';

void main() {
  group('buildKqOauthAuthorizeUri', () {
    test('builds authorization-code URL with required OAuth parameters', () {
      final uri = buildKqOauthAuthorizeUri(
        authorizeUrl: 'https://login.kunqiongai.com/authorize.html',
        clientId: 'app-id',
        redirectUri: 'http://localhost:6613/oauth/callback',
        state: 'state-1',
      );

      expect(uri.toString(),
          startsWith('https://login.kunqiongai.com/authorize.html?'));
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['client_id'], 'app-id');
      expect(uri.queryParameters['redirect_uri'],
          'http://localhost:6613/oauth/callback');
      expect(uri.queryParameters['state'], 'state-1');
    });
  });

  group('parseKqOauthCallbackCode', () {
    test('returns code when path and state match', () {
      final uri = Uri.parse(
          'http://localhost:6613/oauth/callback?code=abc123&state=state-1');

      expect(parseKqOauthCallbackCode(uri, 'state-1'), 'abc123');
      expect(isKqOauthCallbackSuccess(uri, 'state-1'), isTrue);
    });

    test('rejects invalid path, state, and missing code', () {
      expect(
        () => parseKqOauthCallbackCode(
          Uri.parse('http://localhost:6613/wrong?code=abc123&state=state-1'),
          'state-1',
        ),
        throwsFormatException,
      );
      expect(
        () => parseKqOauthCallbackCode(
          Uri.parse(
              'http://localhost:6613/oauth/callback?code=abc123&state=bad'),
          'state-1',
        ),
        throwsFormatException,
      );
      expect(
        () => parseKqOauthCallbackCode(
          Uri.parse('http://localhost:6613/oauth/callback?state=state-1'),
          'state-1',
        ),
        throwsFormatException,
      );
    });

    test('preserves OAuth callback error message', () {
      expect(
        () => parseKqOauthCallbackCode(
          Uri.parse(
              'http://localhost:6613/oauth/callback?error=access_denied&state=state-1'),
          'state-1',
        ),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'access_denied')),
      );
      expect(
        parseKqOauthCallbackError(
          Uri.parse(
              'http://localhost:6613/oauth/callback?error=access_denied&state=state-1'),
          'state-1',
        ),
        'access_denied',
      );
    });

    test('ignores errors from unrelated callback-server requests', () {
      final wrongPath =
          Uri.parse('http://localhost:6613/favicon.ico?error=access_denied');
      final wrongState = Uri.parse(
          'http://localhost:6613/oauth/callback?error=access_denied&state=bad');

      expect(parseKqOauthCallbackError(wrongPath, 'state-1'), isNull);
      expect(parseKqOauthCallbackError(wrongState, 'state-1'), isNull);
      expect(
        () => parseKqOauthCallbackCode(wrongPath, 'state-1'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'Unexpected OAuth callback path.')),
      );
      expect(
        () => parseKqOauthCallbackCode(wrongState, 'state-1'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'Invalid OAuth state.')),
      );
    });
  });

  group('extractKqOauthTokenData', () {
    test('accepts numeric and string success codes', () {
      final data = {
        'access_token': 'token-123',
        'user': {'username': 'wangwu'},
      };

      expect(extractKqOauthTokenData({'code': 200, 'data': data}), data);
      expect(extractKqOauthTokenData({'code': '200', 'data': data}), data);
    });

    test('preserves OAuth error messages', () {
      expect(
        () => extractKqOauthTokenData({
          'code': 401,
          'message': 'unauthorized',
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'unauthorized')),
      );
    });

    test('rejects success responses without data object', () {
      expect(
        () => extractKqOauthTokenData({'code': 200, 'data': null}),
        throwsFormatException,
      );
    });
  });

  group('parseKqOauthLoginPayload', () {
    test('accepts documented Kunqiong OAuth token response example', () {
      final tokenData = extractKqOauthTokenData({
        'code': 200,
        'message': 'success',
        'data': {
          'access_token': 'eyJ0eXAiOiJKV1QiLCJhbGc...',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'user': {
            'id': 1,
            'username': 'testuser',
            'nickname': '测试用户',
            'email': 'test@example.com',
            'phone': '13800138000',
            'avatar': null,
          },
        },
      });

      final payload = parseKqOauthLoginPayload(tokenData);

      expect(payload.accessToken, 'eyJ0eXAiOiJKV1QiLCJhbGc...');
      expect(payload.user['name'], 'testuser');
      expect(payload.user['display_name'], '测试用户');
      expect(payload.user['email'], 'test@example.com');
      expect(payload.user['avatar'], '');
    });

    test('requires access token and a normalizable user', () {
      final payload = parseKqOauthLoginPayload({
        'access_token': ' token-123 ',
        'user': {
          'username': 'lisi',
          'nickname': 'Li Si',
        },
      });

      expect(payload.accessToken, 'token-123');
      expect(payload.user['name'], 'lisi');
      expect(payload.user['display_name'], 'Li Si');
    });

    test('rejects missing access token or user', () {
      expect(
        () => parseKqOauthLoginPayload({
          'user': {'username': 'lisi'},
        }),
        throwsFormatException,
      );
      expect(
        () => parseKqOauthLoginPayload({
          'access_token': 'token-123',
        }),
        throwsFormatException,
      );
      expect(
        () => parseKqOauthLoginPayload({
          'access_token': '   ',
          'user': {'username': 'lisi'},
        }),
        throwsFormatException,
      );
    });
  });

  group('normalizeKqOauthUser', () {
    test('maps Kunqiong user payload to RustDesk login user shape', () {
      expect(
        normalizeKqOauthUser({
          'id': 12,
          'username': 'zhangsan',
          'nickname': 'Zhang San',
          'email': 'zhangsan@example.com',
          'avatar': null,
        }),
        {
          'id': '12',
          'name': 'zhangsan',
          'display_name': 'Zhang San',
          'avatar': '',
          'email': 'zhangsan@example.com',
          'status': 1,
          'is_admin': false,
        },
      );
    });

    test('falls back to id and username when optional fields are missing', () {
      expect(
        normalizeKqOauthUser({'id': 42}),
        {
          'id': '42',
          'name': '42',
          'display_name': '42',
          'avatar': '',
          'email': '',
          'status': 1,
          'is_admin': false,
        },
      );
    });

    test('rejects payloads without a usable identity', () {
      expect(normalizeKqOauthUser({'username': '   '}), isNull);
      expect(normalizeKqOauthUser(null), isNull);
      expect(normalizeKqOauthUser('bad'), isNull);
    });
  });
}
