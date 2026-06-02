class KqNetworkRisk {
  const KqNetworkRisk({required this.hasProxy, required this.hasVpn});

  final bool hasProxy;
  final bool hasVpn;

  bool get hasRisk => hasProxy || hasVpn;
}

Future<KqNetworkRisk> detectKqNetworkRisk() async {
  return const KqNetworkRisk(hasProxy: false, hasVpn: false);
}
