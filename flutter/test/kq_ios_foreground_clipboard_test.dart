import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS foreground clipboard uses the current remote session', () {
    final remotePage = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final rustFfi = File('../src/flutter_ffi.rs').readAsStringSync();
    final session = File('../src/ui_session_interface.rs').readAsStringSync();

    expect(remotePage, contains('Clipboard.getData(Clipboard.kTextPlain)'));
    expect(remotePage, contains('bind.sessionSendClipboardText'));
    expect(rustFfi, contains('pub fn session_send_clipboard_text'));
    expect(session, contains('pub fn send_clipboard_text'));
    expect(session, contains('get_msg_if_not_support_multi_clip'));
  });

  test('Android keeps its native clipboard synchronization path', () {
    final remotePage = File('lib/mobile/pages/remote_page.dart').readAsStringSync();

    expect(remotePage, contains('gFFI.invokeMethod("try_sync_clipboard")'));
  });
}
