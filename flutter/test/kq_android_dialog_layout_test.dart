import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android dialogs use a focused shell without changing other platforms',
      () {
    final common = File('lib/common.dart').readAsStringSync();
    final dialogStart = common.indexOf('class CustomAlertDialog');
    final dialogEnd = common.indexOf('Widget createDialogContent', dialogStart);
    final dialog = common.substring(dialogStart, dialogEnd);

    expect(dialog, contains('if (isAndroid)'));
    expect(dialog, contains('_AndroidFocusedDialog'));
    expect(dialog, contains('BorderRadius.circular(8)'));
    expect(dialog, contains('SingleChildScrollView'));
    expect(dialog, contains('MediaQuery.sizeOf(context)'));
    expect(dialog, contains(': AlertDialog('),
        reason: 'Non-Android platforms must keep the existing dialog path');
  });

  test('Android dialog actions use explicit roles and stable button geometry',
      () {
    final common = File('lib/common.dart').readAsStringSync();

    expect(common, contains('enum AndroidDialogActionRole'));
    expect(common, contains('AndroidDialogActionRole.primary'));
    expect(common, contains('AndroidDialogActionRole.secondary'));
    expect(common, contains('AndroidDialogActionRole.cancel'));
    expect(common, contains('AndroidDialogActionRole.destructive'));
    expect(common, contains('class AndroidDialogAction'));
    expect(common, contains('AndroidDialogActionRole? role'));
    expect(common, contains('_resolvedAndroidDialogActions'));
    expect(common, contains('action.role ??'));
    expect(common, contains('_AndroidDialogActionRoleScope'));
    expect(common, contains('roleOf(context)'));
    expect(common, contains('_scopedAndroidDialogActions'));
    expect(common, contains('final minimumSize = const Size(0, 44);'));
    expect(common, contains('Wrap('),
        reason: 'Unknown custom action widgets need a safe wrapping fallback');
    expect(
      common,
      isNot(contains("text.toLowerCase().contains('delete')")),
      reason: 'Destructive intent must never be inferred from translated text',
    );
  });

  test('Android shared message boxes use the focused title region', () {
    final common = File('lib/common.dart').readAsStringSync();
    final start = common.indexOf('void msgBox(');
    final end = common.indexOf('Color? _msgboxColor', start);
    final msgBox = common.substring(start, end);

    expect(msgBox, contains('title: isAndroid'));
    expect(msgBox, contains('androidTitleIcon:'));
    expect(msgBox, contains('androidMsgboxContent'));
    expect(msgBox, contains('AndroidDialogActionRole.cancel'));
    expect(common, contains('Widget androidMsgboxContent('));
  });

  test('Android destructive confirmations use an explicit destructive role',
      () {
    final dialogs = File('lib/common/widgets/dialog.dart').readAsStringSync();
    final deleteStart = dialogs.indexOf('void deleteConfirmDialog(');
    final deleteEnd = dialogs.indexOf('void editAbTagDialog(', deleteStart);
    final deleteDialog = dialogs.substring(deleteStart, deleteEnd);
    final trustedStart =
        dialogs.indexOf('void confrimDeleteTrustedDevicesDialog(');
    final trustedEnd =
        dialogs.indexOf('void manageTrustedDeviceDialog()', trustedStart);
    final trustedDialog = dialogs.substring(trustedStart, trustedEnd);

    expect(
      deleteDialog,
      contains('androidRole: AndroidDialogActionRole.destructive'),
    );
    expect(
      trustedDialog,
      contains('androidConfirmRole: AndroidDialogActionRole.destructive'),
    );
  });

  test('Android destructive file and password actions are explicitly styled',
      () {
    final files = File('lib/models/file_model.dart').readAsStringSync();
    final removeStart = files.indexOf('Future<bool?> showRemoveDialog(');
    final removeEnd = files.indexOf('void sendRemoveFile(', removeStart);
    final removeDialog = files.substring(removeStart, removeEnd);

    final dialogs = File('lib/common/widgets/dialog.dart').readAsStringSync();
    final passwordStart = dialogs.indexOf('void setSharedAbPasswordDialog(');
    final passwordEnd =
        dialogs.indexOf('void CommonConfirmDialog(', passwordStart);
    final passwordDialog = dialogs.substring(passwordStart, passwordEnd);

    expect(
      removeDialog,
      contains('androidRole: AndroidDialogActionRole.destructive'),
    );
    expect(
      passwordDialog,
      contains('androidRole: AndroidDialogActionRole.destructive'),
    );
    expect(
      passwordDialog,
      contains('androidRole: AndroidDialogActionRole.primary'),
    );
  });

  test('Android cancel actions keep their role even when ordered last', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final screenshotStart = model.indexOf('  _handleScreenshot(');
    final screenshotEnd =
        model.indexOf('  _handlePrinterRequest(', screenshotStart);
    final screenshot = model.substring(screenshotStart, screenshotEnd);
    final printerStart = screenshotEnd;
    final printerEnd =
        model.indexOf('  _handleUseTextureRender(', printerStart);
    final printer = model.substring(printerStart, printerEnd);

    expect(
      screenshot,
      contains('androidRole: AndroidDialogActionRole.cancel'),
    );
    expect(
      printer,
      contains('androidRole: AndroidDialogActionRole.cancel'),
    );
  });

  test('Android loading dialogs use the shared fixed action area', () {
    final common = File('lib/common.dart').readAsStringSync();
    final start = common.indexOf('  String showLoading(');
    final end = common.indexOf('  void resetMobileActionsOverlay(', start);
    final loading = common.substring(start, end);

    expect(loading, contains('actions: isAndroid && showCancel'));
    expect(
      loading,
      contains('androidRole: AndroidDialogActionRole.cancel'),
    );
  });
}
