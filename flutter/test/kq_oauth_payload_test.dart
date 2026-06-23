import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/kq_oauth_payload.dart';

void main() {
  group('desktop login nonce', () {
    test('generates documented HMAC-SHA256 signature', () {
      final signedNonce = generateKqDesktopLoginNonce(
        secretKey: '7530bfb1ad6c41627b0f0620078fa5ed',
        nonce: 'abc',
        timestamp: 1700000000,
      );

      expect(signedNonce.nonce, 'abc');
      expect(signedNonce.timestamp, 1700000000);
      expect(
        signedNonce.signature,
        '/HxAiqC49TnaNZsZZi5ikC33I+pLbAudrLE9OtB5rd4=',
      );
    });

    test('encodes signed nonce as URL-safe base64 JSON', () {
      final encoded = encodeKqDesktopLoginNonce(const KqDesktopLoginNonce(
        nonce: 'abc',
        timestamp: 1700000000,
        signature: '/HxAiqC49TnaNZsZZi5ikC33I+pLbAudrLE9OtB5rd4=',
      ));

      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(encoded, isNot(contains('=')));

      final padded = encoded.padRight(
        encoded.length + (4 - encoded.length % 4) % 4,
        '=',
      );
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      expect(decoded['nonce'], 'abc');
      expect(decoded['timestamp'], 1700000000);
      expect(
        decoded['signature'],
        '/HxAiqC49TnaNZsZZi5ikC33I+pLbAudrLE9OtB5rd4=',
      );
    });
  });

  group('desktop login URL', () {
    test('builds web login URL with desktop client nonce', () {
      final uri = buildKqDesktopLoginUri(
        webLoginUrl: 'http://111.229.158.50:1388/login',
        clientNonce: 'nonce-1',
      );

      expect(uri.toString(),
          'http://111.229.158.50:1388/login?client_type=desktop&client_nonce=nonce-1');
      expect(uri.queryParameters['client_type'], 'desktop');
      expect(uri.queryParameters['client_nonce'], 'nonce-1');
    });
  });

  group('Kunqiong API response parsing', () {
    test('extracts web login URL from documented response', () {
      expect(
        extractKqWebLoginUrl({
          'code': 1,
          'msg': 'success',
          'data': {'login_url': 'http://111.229.158.50:1388/login'},
        }),
        'http://111.229.158.50:1388/login',
      );
    });

    test('extracts desktop token only when ready', () {
      expect(
        extractKqDesktopTokenIfReady({
          'code': 1,
          'msg': 'success',
          'data': {'token': '6143a416-e9be-4d58-8b77-450d5ad866d2'},
        }),
        '6143a416-e9be-4d58-8b77-450d5ad866d2',
      );
      expect(
        extractKqDesktopTokenIfReady({
          'code': 0,
          'msg': 'not logged in',
          'data': null,
        }),
        isNull,
      );
      expect(
        extractKqDesktopTokenIfReady({
          'code': 1,
          'msg': 'success',
          'data': {},
        }),
        isNull,
      );
    });

    test('parses check-login result from code 1', () {
      expect(parseKqCheckLoginResult({'code': 1, 'data': []}), isTrue);
      expect(parseKqCheckLoginResult({'code': 404, 'data': null}), isFalse);
    });

    test('preserves API error messages', () {
      expect(
        () => extractKqApiData({
          'code': 0,
          'msg': 'login expired',
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'login expired')),
      );
    });

    test('extracts native login token from compatible token fields', () {
      expect(
        extractKqOauthLoginToken({
          'token': 'fallback-token',
          'user': {'nickname': 'lisi'},
        }),
        'fallback-token',
      );
      expect(
        extractKqOauthLoginToken({
          'apiWebToken': 'api-web-token',
          'token': 'fallback-token',
        }),
        'api-web-token',
      );
      expect(
        extractKqOauthLoginToken({
          'user_info': {
            'api_web_token': 'nested-api-web-token',
            'nickname': 'lisi',
          },
        }),
        'nested-api-web-token',
      );
    });
  });

  group('parseKqOauthLoginPayload', () {
    test('accepts documented Kunqiong desktop user response example', () {
      final payload = parseKqOauthLoginPayload(
        token: '6143a416-e9be-4d58-8b77-450d5ad866d2',
        userInfoResponse: {
          'code': 1,
          'msg': 'success',
          'data': {
            'user_info': {
              'avatar': 'https://iamge.kunqiongai.com/avatar/touxiang.jpg',
              'nickname': 'kqai_180rKXFm5390',
            },
          },
        },
      );

      expect(payload.accessToken, '6143a416-e9be-4d58-8b77-450d5ad866d2');
      expect(payload.user['id'], 'kqai_180rKXFm5390');
      expect(payload.user['name'], 'kqai_180rKXFm5390');
      expect(payload.user['display_name'], 'kqai_180rKXFm5390');
      expect(
        payload.user['avatar'],
        'https://iamge.kunqiongai.com/avatar/touxiang.jpg',
      );
      expect(payload.user['email'], '');
    });

    test('requires token and a normalizable user', () {
      expect(
        () => parseKqOauthLoginPayload(
          token: '',
          userInfoResponse: {
            'code': 1,
            'data': {
              'user_info': {'nickname': 'lisi'},
            },
          },
        ),
        throwsFormatException,
      );
      expect(
        () => parseKqOauthLoginPayload(
          token: 'token-123',
          userInfoResponse: {'code': 1, 'data': {}},
        ),
        throwsFormatException,
      );
    });
  });

  group('normalizeKqOauthUser', () {
    test('maps Kunqiong user payload to RustDesk login user shape', () {
      expect(
        normalizeKqOauthUser({
          'id': 12,
          'nickname': 'Zhang San',
          'email': 'zhangsan@example.com',
          'avatar': null,
        }),
        {
          'id': '12',
          'name': 'Zhang San',
          'display_name': 'Zhang San',
          'avatar': '',
          'email': 'zhangsan@example.com',
          'status': 1,
          'is_admin': false,
        },
      );
    });

    test('falls back to nickname as id when optional id is missing', () {
      expect(
        normalizeKqOauthUser({'nickname': 'kqai_180rKXFm5390'}),
        {
          'id': 'kqai_180rKXFm5390',
          'name': 'kqai_180rKXFm5390',
          'display_name': 'kqai_180rKXFm5390',
          'avatar': '',
          'email': '',
          'status': 1,
          'is_admin': false,
        },
      );
    });

    test('rejects payloads without a usable identity', () {
      expect(normalizeKqOauthUser({'nickname': '   '}), isNull);
      expect(normalizeKqOauthUser(null), isNull);
      expect(normalizeKqOauthUser('bad'), isNull);
    });
  });
}
