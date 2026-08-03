import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'expired local membership is not treated as active while refresh is unavailable',
      () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final activeStart =
        source.indexOf('  static bool get isLocalMemberActiveForCurrentUser {');
    final activeEnd = source.indexOf('\n  _updateLocalUserInfo()', activeStart);
    expect(activeStart, greaterThanOrEqualTo(0));
    expect(activeEnd, greaterThan(activeStart));
    final activeSource = source.substring(activeStart, activeEnd);

    expect(source, contains('static bool _isMembershipExpired('));
    expect(activeSource, contains('_isMembershipExpired('));
  });

  test('membership refresh clears a stale account session without credentials',
      () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final refreshStart = source.indexOf('  Future<void> refreshMembership({');
    final refreshEnd =
        source.indexOf('  Future<http.Response> _postMemberApi(', refreshStart);
    final refreshSource = source.substring(refreshStart, refreshEnd);
    final missingCredentialsStart =
        refreshSource.indexOf('if (candidates.isEmpty) {');
    final missingCredentialsEnd =
        refreshSource.indexOf('Object? lastError;', missingCredentialsStart);
    final missingCredentials =
        refreshSource.substring(missingCredentialsStart, missingCredentialsEnd);

    expect(
      source,
      contains(
          'bool get isLogin => userName.isNotEmpty && hasLoginCredential;'),
    );
    expect(missingCredentials, contains('await reset();'));
    expect(missingCredentials, contains("translate('Please log in first')"));
  });

  test('membership refresh clears a session when every credential is rejected',
      () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final refreshStart = source.indexOf('  Future<void> refreshMembership({');
    final refreshEnd =
        source.indexOf('  Future<http.Response> _postMemberApi(', refreshStart);
    final refreshSource = source.substring(refreshStart, refreshEnd);

    expect(refreshSource, contains('var allCredentialsRejected = true;'));
    expect(
      refreshSource,
      contains('if (allCredentialsRejected && isCurrentRefresh()) {'),
    );
    expect(refreshSource, contains('await reset();'));
  });

  test('deleted accounts remain visible when login refreshes automatically',
      () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final refreshStart = source.indexOf('  Future<void> refreshMembership({');
    final refreshEnd =
        source.indexOf('  Future<http.Response> _postMemberApi(', refreshStart);
    final refreshSource = source.substring(refreshStart, refreshEnd);
    final deletedStart = refreshSource
        .indexOf('} on _KqDeletedAccountSessionException catch (e) {');
    final deletedEnd = refreshSource.indexOf('} catch (e) {', deletedStart);

    expect(deletedStart, greaterThanOrEqualTo(0));
    expect(deletedEnd, greaterThan(deletedStart));
    final deletedHandler = refreshSource.substring(deletedStart, deletedEnd);
    expect(deletedHandler, contains('await reset();'));
    expect(deletedHandler, contains('showToast(e.message);'));
    expect(deletedHandler, isNot(contains('if (showError)')));
  });

  test('membership refresh preserves cached benefits on transient errors', () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final refreshStart = source.indexOf('  Future<void> refreshMembership({');
    final refreshEnd =
        source.indexOf('  Future<http.Response> _postMemberApi(', refreshStart);
    expect(refreshStart, greaterThanOrEqualTo(0));
    expect(refreshEnd, greaterThan(refreshStart));
    final refreshSource = source.substring(refreshStart, refreshEnd);

    expect(refreshSource, contains('bool keepExistingOnFailure = true'));
    expect(refreshSource, contains('if (keepExistingOnFailure) {'));
    expect(refreshSource, contains('memberLastError.value = message;'));
    final preserveStart = refreshSource.indexOf('if (keepExistingOnFailure) {');
    final clearStart = refreshSource.indexOf(
        "await setCurrentMemberStatus(false, expireAt: '', error: message);");
    expect(preserveStart, greaterThanOrEqualTo(0));
    expect(clearStart, greaterThan(preserveStart));
    expect(
      refreshSource.substring(preserveStart, clearStart),
      contains('return;'),
    );
  });

  test(
      'configured project membership API does not fall back to upstream data on outage',
      () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final methodStart = source.indexOf('  Future<Map?> _getProjectMemberInfo(');
    final methodEnd = source.indexOf(
        '  Future<KqMemberOrder?> _createProjectMemberOrder(', methodStart);
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final methodSource = source.substring(methodStart, methodEnd);

    expect(methodSource,
        contains("throw StateError('KQ project membership API returned"));
    expect(methodSource, contains('rethrow;'));
    expect(methodSource,
        isNot(contains('KQ project API member refresh fallback')));
  });

  test('membership refresh clears login state when project account was deleted',
      () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final refreshStart = source.indexOf('  Future<void> refreshMembership({');
    final refreshEnd =
        source.indexOf('  Future<http.Response> _postMemberApi(', refreshStart);
    expect(refreshStart, greaterThanOrEqualTo(0));
    expect(refreshEnd, greaterThan(refreshStart));
    final refreshSource = source.substring(refreshStart, refreshEnd);

    expect(source, contains('class _KqDeletedAccountSessionException'));
    expect(source, contains('response.statusCode == 410'));
    expect(source, contains('账号已注销，请重新注册后再登录。'));
    expect(
      refreshSource,
      contains('} on _KqDeletedAccountSessionException catch (e) {'),
    );
    final deletedStart = refreshSource
        .indexOf('} on _KqDeletedAccountSessionException catch (e) {');
    final deletedEnd = refreshSource.indexOf('} catch (e) {', deletedStart);
    expect(deletedStart, greaterThanOrEqualTo(0));
    expect(deletedEnd, greaterThan(deletedStart));
    final deletedHandler = refreshSource.substring(deletedStart, deletedEnd);
    expect(deletedHandler, contains('await reset();'));
    expect(deletedHandler, contains('showToast(e.message);'));
    expect(deletedHandler, contains('return;'));
  });

  test('Apple verification can immediately apply the returned expiry', () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final methodStart =
        source.indexOf('  Future<void> applyVerifiedAppleMembership({');
    final methodEnd = source.indexOf('  bool _memberBool(', methodStart);
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final methodSource = source.substring(methodStart, methodEnd);

    expect(source, contains('Future<void> applyVerifiedAppleMembership'));
    expect(source, contains("normalizedExpireAt.toLowerCase() == 'unlimited'"));
    expect(source, contains("normalizedExpireAt == '9999-12-31 23:59:59'"));
    final serialIncrement = methodSource.indexOf('_membershipRefreshSerial++;');
    final memberStatusUpdate = methodSource.indexOf('await _setMemberStatus(');
    expect(serialIncrement, greaterThanOrEqualTo(0));
    expect(memberStatusUpdate, greaterThan(serialIncrement));
    expect(
      source,
      contains(
          "await _setMemberStatus(active, expireAt: normalizedExpireAt, error: '')"),
    );
  });

  test('desktop account page does not render cached user data as a login', () {
    final source =
        File('lib/desktop/pages/desktop_setting_page.dart').readAsStringSync();
    final accountStart =
        source.indexOf('class _AccountState extends State<_Account>');
    final accountEnd = source.indexOf('  Widget _accountShell(', accountStart);
    final accountSource = source.substring(accountStart, accountEnd);

    expect(accountSource, contains('if (!gFFI.userModel.isLogin) {'));
    expect(accountSource, isNot(contains('userName.value.isEmpty')));
  });
}
