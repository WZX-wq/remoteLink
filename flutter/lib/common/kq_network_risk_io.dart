import 'dart:async';
import 'dart:io';

class KqNetworkRisk {
  const KqNetworkRisk({required this.hasProxy, required this.hasVpn});

  final bool hasProxy;
  final bool hasVpn;

  bool get hasRisk => hasProxy || hasVpn;
}

Future<KqNetworkRisk> detectKqNetworkRisk() async {
  final hasProxy = await _hasProxyRisk();
  final hasVpn = await _hasVpnRisk();
  return KqNetworkRisk(hasProxy: hasProxy, hasVpn: hasVpn);
}

Future<bool> _hasProxyRisk() async {
  if (_hasProxyEnvironment()) {
    return true;
  }
  if (!Platform.isWindows) {
    return false;
  }
  try {
    final result = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
    ]).timeout(const Duration(milliseconds: 900));
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('proxyenable') &&
        (output.contains('0x1') || output.contains(' 1'));
  } catch (_) {
    return false;
  }
}

bool _hasProxyEnvironment() {
  const keys = ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY'];
  for (final key in keys) {
    final value =
        Platform.environment[key] ?? Platform.environment[key.toLowerCase()];
    if (value != null && value.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}

Future<bool> _hasVpnRisk() async {
  if (!Platform.isWindows) {
    return false;
  }
  try {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r"$names = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -ExpandProperty Name; $names -join [Environment]::NewLine",
    ]).timeout(const Duration(milliseconds: 1200));
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return _vpnNamePatterns.any(output.contains);
  } catch (_) {
    return false;
  }
}

const _vpnNamePatterns = [
  'vpn',
  'tap',
  'tun',
  'wintun',
  'wireguard',
  'openvpn',
  'tailscale',
  'zerotier',
  'clash',
  'mihomo',
  'sing-box',
  'v2ray',
];
