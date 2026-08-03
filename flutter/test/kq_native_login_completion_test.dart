import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native mobile login returns before supplementary account sync', () {
    final source = File('lib/common/widgets/login.dart').readAsStringSync();
    final stateStart =
        source.indexOf('class _KqNativeMobileLoginPageState extends State');
    final submitStart =
        source.indexOf('  Future<void> _submit() async {', stateStart);
    final submitEnd = source.indexOf(
        '  Future<void> _persistKqNativeLoginCredentials(', submitStart);

    expect(stateStart, greaterThanOrEqualTo(0));
    expect(submitStart, greaterThan(stateStart));
    expect(submitEnd, greaterThan(submitStart));

    final submit = source.substring(submitStart, submitEnd);
    final applied = submit.indexOf('await _applyKqLoginResponse(resp);');
    final completed = submit.indexOf('Navigator.of(context).pop(true);');

    expect(applied, greaterThanOrEqualTo(0));
    expect(completed, greaterThan(applied));
    expect(submit, isNot(contains('await UserModel.updateOtherModels();')));
  });

  test(
      'supplementary account sync is bounded and cannot surface as login failure',
      () {
    final source = File('lib/common/widgets/login.dart').readAsStringSync();
    final applyStart = source.indexOf('Future<void> _applyKqLoginResponse(');
    final syncStart =
        source.indexOf('Future<void> _syncKqLoginSupplementaryState() async {');
    final syncEnd = source.indexOf('\n}\n\n', syncStart);

    expect(applyStart, greaterThanOrEqualTo(0));
    expect(syncStart, greaterThan(applyStart));
    expect(syncEnd, greaterThan(syncStart));

    final apply = source.substring(applyStart, syncStart);
    final sync = source.substring(syncStart, syncEnd);
    expect(apply, contains('applyLoginResponse('));
    expect(apply, contains('storeLocalUserInfo: false'));
    expect(apply, contains('refreshMembership: false'));
    expect(apply, contains('unawaited(_syncKqLoginSupplementaryState());'));
    expect(sync, contains('gFFI.userModel.refreshMembership()'));
    expect(sync, contains('UserModel.updateOtherModels()'));
    expect(sync, contains('.timeout(const Duration(seconds: 8))'));
    expect(sync, contains('debugPrint('));
  });

  test('unregistered phone login opens registration with the entered phone', () {
    final source = File('lib/common/widgets/login.dart').readAsStringSync();

    expect(source, contains('err.requiresRegistration'));
    expect(source, contains('initialPhone: registrationPhone'));
    expect(source, contains('allowWhileBusy: true'));
    expect(source, contains('final String? initialPhone;'));
    expect(source, contains('_phoneController.text = initialPhone;'));
  });

  test('unregistered phone SMS request opens registration immediately', () {
    final source = File('lib/common/widgets/login.dart').readAsStringSync();
    final stateStart =
        source.indexOf('class _KqNativeMobileLoginPageState extends State');
    final smsStart = source.indexOf('  Future<void> _sendSmsCode() async {', stateStart);
    final smsEnd = source.indexOf('  void _startSmsCountdown()', smsStart);

    expect(smsStart, greaterThan(stateStart));
    expect(smsEnd, greaterThan(smsStart));
    final smsRequest = source.substring(smsStart, smsEnd);
    expect(smsRequest, contains('err.requiresRegistration'));
    expect(smsRequest, contains('_KqAccountFlow.register'));
    expect(smsRequest, contains('initialPhone: phone'));
    expect(smsRequest, contains('allowWhileBusy: true'));
  });
}
