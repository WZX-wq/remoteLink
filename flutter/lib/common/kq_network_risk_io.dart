import 'dart:async';
import 'dart:io';

class KqNetworkRisk {
  const KqNetworkRisk({
    required this.hasProxy,
    required this.hasVpn,
    this.firewallRulesMissing = false,
  });

  final bool hasProxy;
  final bool hasVpn;
  final bool firewallRulesMissing;

  bool get hasRisk => hasProxy || hasVpn || firewallRulesMissing;
}

Future<KqNetworkRisk> detectKqNetworkRisk() async {
  final hasProxy = await _hasProxyRisk();
  final hasVpn = await _hasVpnRisk();
  final firewallRulesMissing = await _hasFirewallRuleGap();
  return KqNetworkRisk(
    hasProxy: hasProxy,
    hasVpn: hasVpn,
    firewallRulesMissing: firewallRulesMissing,
  );
}

class KqFirewallRepairResult {
  const KqFirewallRepairResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

Future<KqFirewallRepairResult> repairKqFirewallRules() async {
  if (!Platform.isWindows) {
    return const KqFirewallRepairResult(
      success: false,
      message: '当前系统不支持自动修复防火墙。',
    );
  }
  try {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['--repair-firewall'],
    ).timeout(const Duration(seconds: 60));
    final output = '${result.stdout}\n${result.stderr}'.trim();
    if (result.exitCode == 0) {
      return const KqFirewallRepairResult(
        success: true,
        message: '本机防火墙规则已修复。',
      );
    }
    return KqFirewallRepairResult(
      success: false,
      message: output.isEmpty ? '修复命令执行失败。' : output,
    );
  } catch (e) {
    return KqFirewallRepairResult(
      success: false,
      message: '修复命令启动失败：$e',
    );
  }
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

Future<bool> _hasFirewallRuleGap() async {
  if (!Platform.isWindows) {
    return false;
  }
  const ruleNames = [
    'KQRemoteLink TCP In',
    'KQRemoteLink TCP Out',
    'KQRemoteLink UDP In',
    'KQRemoteLink UDP Out',
  ];
  try {
    for (final name in ruleNames) {
      final result = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'show',
        'rule',
        'name=$name',
      ]).timeout(const Duration(milliseconds: 900));
      if (result.exitCode != 0) {
        return true;
      }
      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      if (output.contains('no rules match') ||
          output.contains('没有与指定条件匹配的规则') ||
          output.contains('找不到')) {
        return true;
      }
    }
  } catch (_) {
    return false;
  }
  return false;
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
