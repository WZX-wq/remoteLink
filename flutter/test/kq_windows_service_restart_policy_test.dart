import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Windows foreground relaunch clears the stopped-service registration gate',
      () {
    final server = File('../src/server.rs').readAsStringSync();
    final rendezvous = File('../src/rendezvous_mediator.rs').readAsStringSync();

    expect(
      rendezvous,
      contains('!config::option2bool("stop-service"'),
      reason:
          'stop-service=Y prevents rendezvous registration and makes the PC look offline.',
    );
    expect(server,
        contains('kq_clear_windows_stopped_service_for_foreground_launch'));
    expect(
      server,
      contains('Config::set_option("stop-service".into(), "".into())'),
    );

    final startServer = server
        .indexOf('pub async fn start_server(is_server: bool, no_server: bool)');
    final clearCall = server.indexOf(
      'kq_clear_windows_stopped_service_for_foreground_launch();',
      startServer,
    );
    final startServerBody = server.substring(startServer);
    final syncBack = RegExp(r'\.send\(&Data::SyncConfig\(Some\(')
        .firstMatch(startServerBody)
        ?.start;
    final syncConfigPayload = server.indexOf(
      '(Config::get(), Config2::get()).into()',
      syncBack == null ? startServer : startServer + syncBack,
    );

    expect(clearCall, greaterThan(startServer));
    expect(syncBack, isNotNull);
    expect(startServer + syncBack!, greaterThan(clearCall));
    expect(syncConfigPayload, greaterThan(startServer + syncBack));
  });
}
