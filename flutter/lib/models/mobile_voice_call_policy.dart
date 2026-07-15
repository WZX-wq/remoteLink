String? mobileVoiceCallClosedMessage(String reason) {
  final normalized = reason.trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'end connection') {
    return null;
  }
  if (normalized.contains('closed') || normalized.contains('hangup')) {
    return '对方已结束语音通话';
  }
  if (normalized.contains('reject') || normalized.contains('declin')) {
    return '对方拒绝了语音通话';
  }
  if (normalized.contains('busy') || normalized.contains('another call')) {
    return '对方正在通话中，请稍后重试';
  }
  if (normalized.contains('timeout') ||
      normalized.contains('no response') ||
      normalized.contains('not answer')) {
    return '对方未接听，请稍后重试';
  }
  if (normalized.contains('microphone') ||
      normalized.contains('permission') ||
      normalized.contains('input device')) {
    return '无法使用麦克风，请检查系统权限后重试';
  }
  if (normalized.contains('failed') || normalized.contains('start')) {
    return '语音通话未能开始，请稍后重试';
  }
  return '语音通话已结束';
}
