import 'dart:io';

import 'package:flutter_hbb/models/mobile_platform_capability_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS exposes only App Store compliant mobile capabilities', () {
    const capabilities = MobilePlatformCapabilities.ios;

    expect(capabilities.canControlRemoteDevice, isTrue);
    expect(capabilities.canHostViewOnlyBroadcast, isTrue);
    expect(capabilities.canReceiveRemoteInput, isFalse);
    expect(capabilities.canUseSystemOverlay, isFalse);
    expect(capabilities.canStartOnBoot, isFalse);
    expect(capabilities.canUseAccessibilityControl, isFalse);
    expect(capabilities.canRunPersistentBackgroundService, isFalse);
    expect(capabilities.canUseVoiceCall, isTrue);
    expect(capabilities.canTransferFiles, isTrue);
    expect(capabilities.canSyncClipboardInForeground, isTrue);
    expect(capabilities.canSyncClipboardInBackground, isFalse);
  });

  test('Android capabilities remain unchanged', () {
    const capabilities = MobilePlatformCapabilities.android;

    expect(capabilities.canControlRemoteDevice, isTrue);
    expect(capabilities.canHostViewOnlyBroadcast, isFalse);
    expect(capabilities.canReceiveRemoteInput, isTrue);
    expect(capabilities.canUseSystemOverlay, isTrue);
    expect(capabilities.canStartOnBoot, isTrue);
    expect(capabilities.canUseAccessibilityControl, isTrue);
    expect(capabilities.canRunPersistentBackgroundService, isTrue);
    expect(capabilities.canSyncClipboardInBackground, isTrue);
  });

  test('mobile pages use the capability policy instead of claiming parity', () {
    final server = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();

    expect(server, contains('mobilePlatformCapabilities'));
    expect(server, contains('canHostViewOnlyBroadcast'));
    expect(server, contains('final appBarActions = isIOS'));
    expect(server, contains('? const <Widget>[]'));
    expect(settings, contains('mobilePlatformCapabilities'));
    expect(settings, contains('canRunPersistentBackgroundService'));
    expect(settings, contains('canUseSystemOverlay'));
  });
}
