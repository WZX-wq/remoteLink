import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('add-device dialog closes its device-type menu before dismissal', () {
    final source =
        File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
    final dialogStart = source.indexOf('  void _showAddDeviceDialog()');
    final dialogEnd = source.indexOf(
      RegExp(r'  @override\r?\n  Widget build\(BuildContext context\)'),
      dialogStart,
    );

    expect(dialogStart, greaterThanOrEqualTo(0));
    expect(dialogEnd, greaterThan(dialogStart));

    final dialogSource = source.substring(dialogStart, dialogEnd);
    expect(dialogSource,
        contains('final deviceTypeMenuController = MenuController();'));
    expect(dialogSource, contains('MenuAnchor('));
    expect(
      dialogSource,
      contains('controller: deviceTypeMenuController'),
    );
    expect(dialogSource, contains('deviceTypeMenuController.close();'));
    expect(dialogSource, isNot(contains('DropdownButtonFormField<String>(')));
    expect(dialogSource, isNot(contains('DropdownMenu<String>(')));
  });

  test('add-device dialog accepts only Windows and Android platforms', () {
    final source =
        File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
    final dialogStart = source.indexOf('  void _showAddDeviceDialog()');
    final dialogEnd = source.indexOf(
      RegExp(r'  @override\r?\n  Widget build\(BuildContext context\)'),
      dialogStart,
    );
    final dialogSource = source.substring(dialogStart, dialogEnd);

    expect(
      dialogSource,
      contains('value != kPeerPlatformWindows &&'),
    );
    expect(dialogSource, contains('value != kPeerPlatformAndroid'));
    expect(
      dialogSource,
      contains("showToast(_kqHomeText('暂不支持，待开发中', 'Not supported yet'))"),
    );
    expect(dialogSource, contains('void selectPlatform(String value)'));
  });

  testWidgets('controlled device-type menu is removed with its parent',
      (tester) async {
    final menuController = MenuController();
    late VoidCallback dismissDialog;
    var dialogVisible = true;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: StatefulBuilder(
          builder: (context, setState) {
            dismissDialog = () {
              menuController.close();
              setState(() => dialogVisible = false);
            };
            return Scaffold(
              body: dialogVisible
                  ? MenuAnchor(
                      controller: menuController,
                      menuChildren: const [
                        MenuItemButton(child: Text('macOS')),
                      ],
                      builder: (context, controller, child) => TextButton(
                        onPressed: controller.open,
                        child: const Text('Windows'),
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Windows'));
    await tester.pumpAndSettle();
    expect(find.text('macOS'), findsWidgets);

    dismissDialog();
    await tester.pumpAndSettle();
    expect(find.text('macOS'), findsNothing);
  });
}
