enum KqIosMembershipPaymentRoute {
  externalPayment,
  appleInAppPurchaseRequired,
}

/// External payment is permitted only in an explicitly marked internal iOS build.
/// App Store builds must use Apple In-App Purchase for membership entitlements.
class KqIosMembershipPaymentPolicy {
  static const _internalDirectPaymentBuild = bool.fromEnvironment(
    'KQ_IOS_INTERNAL_DIRECT_PAYMENT',
    defaultValue: false,
  );

  static KqIosMembershipPaymentRoute routeFor({
    required bool isIOS,
    bool? internalDirectPaymentEnabled,
  }) {
    if (!isIOS) {
      return KqIosMembershipPaymentRoute.externalPayment;
    }
    final allowDirect =
        internalDirectPaymentEnabled ?? _internalDirectPaymentBuild;
    return allowDirect
        ? KqIosMembershipPaymentRoute.externalPayment
        : KqIosMembershipPaymentRoute.appleInAppPurchaseRequired;
  }
}
