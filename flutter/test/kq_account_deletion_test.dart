import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/common/kq_account_deletion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('account deletion has a production endpoint when Dart define is omitted',
      () {
    expect(
      KqAccountDeletionApi.endpointUrl,
      'https://remotelink.kunqiongai.com/kq-api/api/auth/account/delete',
    );
    expect(KqAccountDeletionApi.fromEnvironment().isConfigured, isTrue);
  });

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

  test('account deletion treats upstream deleted response as completed',
      () async {
    Uri? sentUri;
    Map<String, String>? sentHeaders;
    String? sentBody;
    final api = KqAccountDeletionApi(
      endpoint: Uri.parse('https://api.example.com/account/delete'),
      post: (uri, headers, body) async {
        sentUri = uri;
        sentHeaders = headers;
        sentBody = body;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'status': 'deleted',
            'message': '账号已注销',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      },
    );

    final result = await api.requestDeletion(
      token: 'access-token',
      confirmation: 'DELETE',
    );

    expect(sentUri.toString(), 'https://api.example.com/account/delete');
    expect(sentHeaders?['Authorization'], 'Bearer access-token');
    expect(sentHeaders?['Content-Type'], 'application/json');
    expect(sentHeaders?['Accept'], 'application/json');
    expect(jsonDecode(sentBody!), <String, dynamic>{'confirmation': 'DELETE'});
    expect(result.pending, isFalse);
    expect(result.message, '账号已注销');
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

  test('account deletion warns that all Kunqiong account data will be removed',
      () {
    final page =
        File('lib/mobile/pages/account_deletion_page.dart').readAsStringSync();

    expect(page, contains('注销账号会清理鲲穹账户的所有数据，请您谨慎注销。'));
  });

  test('account deletion warning keeps Apple wording in the iOS branch only',
      () {
    final page =
        File('lib/mobile/pages/account_deletion_page.dart').readAsStringSync();
    final warningStart = page.indexOf('_DeletionWarningCard(');
    final warningEnd = page.indexOf('const SizedBox(height: 14)', warningStart);

    expect(warningStart, greaterThanOrEqualTo(0));
    expect(warningEnd, greaterThan(warningStart));
    final warning = page.substring(warningStart, warningEnd);
    final platformConditional = RegExp(
      r'isIOS\s*\?\s*_text\(([\s\S]*?)\)\s*:\s*_text\(',
    ).firstMatch(warning);

    expect(warning, contains('注销账号会清理鲲穹账户的所有数据，请您谨慎注销。'));
    expect(
      warning,
      contains('提交后将删除账号及不再需要保留的相关数据。'),
    );
    expect(warning,
        contains('Deleting the account clears all Kunqiong account data.'));
    expect(platformConditional, isNotNull);
    if (platformConditional == null) return;
    expect(platformConditional.group(1), contains('Apple 自动续订'));
    expect(
      warning.substring(platformConditional.end),
      isNot(contains('Apple')),
    );
  });

  test('successful deletion clears all account-scoped local data', () {
    final page =
        File('lib/mobile/pages/account_deletion_page.dart').readAsStringSync();
    final userModel = File('lib/models/user_model.dart').readAsStringSync();
    final projectApi =
        File('lib/common/kq_project_api.dart').readAsStringSync();

    expect(page, contains('clearLocalAccountDataAfterDeletion()'));
    expect(page, isNot(contains('await gFFI.userModel.logOut();')));
    expect(userModel,
        contains('Future<void> clearLocalAccountDataAfterDeletion()'));
    expect(userModel, contains('await KqOauth.logout();'));
    expect(userModel,
        contains('if (e is _KqDeletedAccountSessionException) rethrow;'));
    expect(userModel, contains('mainLoadRecentPeersForAb'));
    expect(userModel, contains('await bind.mainRemovePeer(id: peerId);'));
    expect(userModel, contains('await bind.mainStoreFav(favs: const []);'));
    expect(userModel, contains('KqProjectApi.clearAccountLocalState();'));
    expect(userModel, contains('recentPeersModel.clear();'));
    expect(userModel, contains('favoritePeersModel.clear();'));
    expect(userModel, contains('memberPackages.clear();'));
    expect(userModel, contains('await reset(resetOther: true);'));
    expect(userModel, contains('} finally {'));
    expect(projectApi, contains('static void clearAccountLocalState()'));
    expect(projectApi, contains('_cachedAccountDevicesOptionKey'));
    expect(projectApi, contains('_hiddenAccountDevicesOptionKey'));
    expect(projectApi, contains('_deletedRecentPeerOptionKey'));
  });
}
