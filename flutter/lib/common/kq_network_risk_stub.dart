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
  return const KqNetworkRisk(hasProxy: false, hasVpn: false);
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
  return const KqFirewallRepairResult(
    success: false,
    message: '当前系统不支持自动修复防火墙。',
  );
}
