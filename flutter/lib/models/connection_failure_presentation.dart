class KqConnectionFailureCopy {
  const KqConnectionFailureCopy({required this.zhCn, required this.en});

  final String zhCn;
  final String en;
}

bool shouldCloseKqConnectionFailure({
  required bool isKqApp,
  required bool isDesktopPlatform,
  required bool isMobilePlatform,
  required bool isIOSPlatform,
  required bool isWebPlatform,
  required String type,
  required String title,
  required String text,
}) {
  if (!isKqApp ||
      isWebPlatform ||
      type != 'error' ||
      title != 'Connection Error') {
    return false;
  }
  if (isMobilePlatform) {
    return isIOSPlatform;
  }
  if (!isDesktopPlatform) {
    return false;
  }
  return text.contains('KQ_VPN_ROUTE_BLOCKED') ||
      text.contains('KQ_CONNECTION_START_TIMEOUT');
}

KqConnectionFailureCopy presentKqConnectionFailure(String text) {
  final raw = text.trim();
  final lower = raw.toLowerCase();

  if (lower.contains('kq_vpn_route_blocked')) {
    return const KqConnectionFailureCopy(
      zhCn: '检测到 VPN 正在影响远程连接，本次连接已停止。请关闭 VPN，或允许鲲穹远程桌面绕过 VPN 后重试。',
      en: 'A VPN is interfering with the remote connection, so this attempt was stopped. Turn off the VPN or allow KQ RemoteLink to bypass it, then try again.',
    );
  }
  if (lower.contains('kq_connection_start_timeout')) {
    return const KqConnectionFailureCopy(
      zhCn: '连接超过 30 秒仍未建立，本次连接已停止。请确认对方设备在线，并检查 VPN、防火墙或当前网络后重试。',
      en: 'The connection was not established within 30 seconds and was stopped. Check that the peer is online and review the VPN, firewall, and network before trying again.',
    );
  }
  if (lower.contains('kq_video_first_frame_timeout')) {
    return const KqConnectionFailureCopy(
      zhCn: '连接已建立，但远程画面未能正常显示，本次连接已停止。请重试；如果仍然失败，请重启客户端。',
      en: 'The connection was established, but the remote image could not be displayed. This attempt was stopped. Try again, and restart the app if it keeps failing.',
    );
  }
  if (raw == 'Timeout' ||
      raw == 'Remote desktop is offline' ||
      lower.contains('timed out')) {
    return const KqConnectionFailureCopy(
      zhCn: '对方设备暂时无法连接，请确认对方在线并且网络正常。',
      en: 'The peer device cannot be reached. Check that it is online and the network is working.',
    );
  }
  if (lower.contains('rendezvous') || lower.contains('relay')) {
    return const KqConnectionFailureCopy(
      zhCn: '连接服务暂时不可用，请稍后重试，或检查本机网络。',
      en: 'The connection service is temporarily unavailable. Try again later or check your network.',
    );
  }
  if (raw.contains('10054') ||
      lower.contains('reset') ||
      lower.contains('refused') ||
      lower.contains('socket')) {
    return const KqConnectionFailureCopy(
      zhCn: '连接已中断，请检查对方设备和网络后重试。',
      en: 'The connection was interrupted. Check the peer device and network, then try again.',
    );
  }
  if (lower.contains('password')) {
    return const KqConnectionFailureCopy(
      zhCn: '验证码或密码不正确，请重新输入。',
      en: 'The verification code or password is incorrect. Please try again.',
    );
  }
  return const KqConnectionFailureCopy(
    zhCn: '连接失败，请确认对方设备在线，并检查网络是否正常。',
    en: 'Connection failed. Check that the peer device is online and the network is working.',
  );
}
