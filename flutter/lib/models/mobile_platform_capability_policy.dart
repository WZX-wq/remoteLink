import 'package:flutter/foundation.dart';

class MobilePlatformCapabilities {
  const MobilePlatformCapabilities({
    required this.canControlRemoteDevice,
    required this.canHostViewOnlyBroadcast,
    required this.canReceiveRemoteInput,
    required this.canUseSystemOverlay,
    required this.canStartOnBoot,
    required this.canUseAccessibilityControl,
    required this.canRunPersistentBackgroundService,
    required this.canUseVoiceCall,
    required this.canTransferFiles,
    required this.canSyncClipboardInForeground,
    required this.canSyncClipboardInBackground,
  });

  static const ios = MobilePlatformCapabilities(
    canControlRemoteDevice: true,
    canHostViewOnlyBroadcast: true,
    canReceiveRemoteInput: false,
    canUseSystemOverlay: false,
    canStartOnBoot: false,
    canUseAccessibilityControl: false,
    canRunPersistentBackgroundService: false,
    canUseVoiceCall: true,
    canTransferFiles: true,
    canSyncClipboardInForeground: true,
    canSyncClipboardInBackground: false,
  );

  static const android = MobilePlatformCapabilities(
    canControlRemoteDevice: true,
    canHostViewOnlyBroadcast: false,
    canReceiveRemoteInput: true,
    canUseSystemOverlay: true,
    canStartOnBoot: true,
    canUseAccessibilityControl: true,
    canRunPersistentBackgroundService: true,
    canUseVoiceCall: true,
    canTransferFiles: true,
    canSyncClipboardInForeground: true,
    canSyncClipboardInBackground: true,
  );

  static const unsupported = MobilePlatformCapabilities(
    canControlRemoteDevice: false,
    canHostViewOnlyBroadcast: false,
    canReceiveRemoteInput: false,
    canUseSystemOverlay: false,
    canStartOnBoot: false,
    canUseAccessibilityControl: false,
    canRunPersistentBackgroundService: false,
    canUseVoiceCall: false,
    canTransferFiles: false,
    canSyncClipboardInForeground: false,
    canSyncClipboardInBackground: false,
  );

  final bool canControlRemoteDevice;
  final bool canHostViewOnlyBroadcast;
  final bool canReceiveRemoteInput;
  final bool canUseSystemOverlay;
  final bool canStartOnBoot;
  final bool canUseAccessibilityControl;
  final bool canRunPersistentBackgroundService;
  final bool canUseVoiceCall;
  final bool canTransferFiles;
  final bool canSyncClipboardInForeground;
  final bool canSyncClipboardInBackground;
}

MobilePlatformCapabilities get mobilePlatformCapabilities {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return MobilePlatformCapabilities.ios;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return MobilePlatformCapabilities.android;
  }
  return MobilePlatformCapabilities.unsupported;
}
