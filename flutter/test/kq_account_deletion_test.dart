import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/common/kq_account_deletion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('account deletion requires a logged-in token and confirmation',
      () async {
    final api = KqAccountDeletionApi(
      endpoint: Uri.parse('https://api.example.com/account/delete'),
    );

    await expectLater(
      api.requestDeletion(token: '', confirmation: 'DELETE'),
      throwsA(isA<KqAccountDeletionException>()),
    );
    await expectLater(
      api.requestDeletion(token: 'token', confirmation: 'delete'),
      throwsA(isA<KqAccountDeletionException>()),
    );
  });

  test('account deletion sends a confirmed authenticated request', () async {
    final api = KqAccountDeletionApi(
      endpoint: Uri.parse('https://api.example.com/account/delete'),
      post: (uri, headers, body) async {
        expect(uri.toString(), 'https://api.example.com/account/delete');
        expect(headers['Authorization'], 'Bearer access-token');
        expect(jsonDecode(body), <String, dynamic>{'confirmation': 'DELETE'});
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'status': 'pending',
            'message': 'Deletion request received.',
          }),
          202,
        );
      },
    );

    final result = await api.requestDeletion(
      token: 'access-token',
      confirmation: 'DELETE',
    );

    expect(result.pending, isTrue);
    expect(result.message, 'Deletion request received.');
  });

  test('account deletion surfaces a server message', () async {
    final api = KqAccountDeletionApi(
      endpoint: Uri.parse('https://api.example.com/account/delete'),
      post: (_, __, ___) async => http.Response(
        jsonEncode(<String, dynamic>{'message': 'Please verify your phone.'}),
        400,
      ),
    );

    await expectLater(
      api.requestDeletion(token: 'access-token', confirmation: 'DELETE'),
      throwsA(
        isA<KqAccountDeletionException>().having(
          (error) => error.message,
          'message',
          'Please verify your phone.',
        ),
      ),
    );
  });

  test('personal center exposes the destructive account deletion route', () {
    final source =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();

    expect(source, contains('AccountDeletionPage'));
    expect(source, contains('Delete account'));
  });
}
