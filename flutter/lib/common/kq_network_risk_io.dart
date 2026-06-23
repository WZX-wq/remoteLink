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

class KqBrowserProtocolRegistrationResult {
  const KqBrowserProtocolRegistrationResult({
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

Future<KqBrowserProtocolRegistrationResult>
    registerKqBrowserRemoteProtocols() async {
  if (!Platform.isWindows) {
    return const KqBrowserProtocolRegistrationResult(
      success: false,
      message: '当前系统不支持注册浏览器远控入口。',
    );
  }
  final exe = Platform.resolvedExecutable;
  const protocols = {
    'kqremote': 'HKCU\\Software\\Classes\\kqremote',
    'rustdesk': 'HKCU\\Software\\Classes\\rustdesk',
  };
  try {
    for (final entry in protocols.entries) {
      final protocol = entry.key;
      final root = entry.value;
      final command = '$root\\shell\\open\\command';
      final setProtocol = await Process.run('reg', [
        'add',
        root,
        '/f',
        '/v',
        'URL Protocol',
        '/t',
        'REG_SZ',
        '/d',
        '',
      ]).timeout(const Duration(seconds: 10));
      if (setProtocol.exitCode != 0) {
        final output = '${setProtocol.stdout}\n${setProtocol.stderr}'.trim();
        return KqBrowserProtocolRegistrationResult(
          success: false,
          message: output.isEmpty ? '注册 $protocol:// 失败。' : output,
        );
      }
      final setCommand = await Process.run('reg', [
        'add',
        command,
        '/f',
        '/ve',
        '/t',
        'REG_SZ',
        '/d',
        '"$exe" "%1"',
      ]).timeout(const Duration(seconds: 10));
      if (setCommand.exitCode != 0) {
        final output = '${setCommand.stdout}\n${setCommand.stderr}'.trim();
        return KqBrowserProtocolRegistrationResult(
          success: false,
          message: output.isEmpty ? '写入 $protocol:// 启动命令失败。' : output,
        );
      }
    }
    return const KqBrowserProtocolRegistrationResult(
      success: true,
      message: '浏览器远控入口已启用。',
    );
  } catch (e) {
    return KqBrowserProtocolRegistrationResult(
      success: false,
      message: '注册浏览器远控入口失败：$e',
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
