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

class KqBrowserProtocolRegistrationResult {
  const KqBrowserProtocolRegistrationResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

Future<KqFirewallRepairResult> repairKqFirewallRules() async {
  return const KqFirewallRepairResult(
    success: false,
    message: 'Automatic firewall repair is not supported on this system.',
  );
}

Future<KqBrowserProtocolRegistrationResult>
    registerKqBrowserRemoteProtocols() async {
  return const KqBrowserProtocolRegistrationResult(
    success: false,
    message:
        'Browser remote-control registration is not supported on this system.',
  );
}
