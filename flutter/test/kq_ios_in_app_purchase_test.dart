import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/mobile/kq_ios_in_app_purchase.dart';
import 'package:flutter_hbb/mobile/pages/ios_membership_purchase_page.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StoreKit configuration maps server packages to product IDs', () {
    final config = KqIosInAppPurchaseConfig.fromValues(
      productsJson:
          '{"monthly":"com.kunqiong.remotelink.member.monthly","yearly":"com.kunqiong.remotelink.member.yearly"}',
      verificationUrl: 'https://api.example.com/iap/verify',
    );

    expect(config.isConfigured, isTrue);
    expect(
      config.productForPackage('monthly'),
      'com.kunqiong.remotelink.member.monthly',
    );
    expect(config.packageForProduct('com.kunqiong.remotelink.member.yearly'),
        'yearly');
  });

  test('StoreKit configuration rejects an insecure verification endpoint', () {
    final config = KqIosInAppPurchaseConfig.fromValues(
      productsJson: '{"monthly":"com.kunqiong.remotelink.member.monthly"}',
      verificationUrl: 'http://api.example.com/iap/verify',
    );

    expect(config.isConfigured, isFalse);
    expect(config.configurationError, isNotEmpty);
  });

  test('StoreKit verification status maps to an actionable safe state', () {
    expect(
      kqIosMembershipVerificationFeedbackForStatus(401),
      KqIosMembershipPurchaseFeedback.accountAuthenticationRequired,
    );
    expect(
      kqIosMembershipVerificationFeedbackForStatus(403),
      KqIosMembershipPurchaseFeedback.accountAuthenticationRequired,
    );
    expect(
      kqIosMembershipVerificationFeedbackForStatus(409),
      KqIosMembershipPurchaseFeedback.purchaseAlreadyLinked,
    );
    expect(
      kqIosMembershipVerificationFeedbackForStatus(503),
      KqIosMembershipPurchaseFeedback.verificationServiceUnavailable,
    );
    expect(
      kqIosMembershipVerificationFeedbackForStatus(400),
      KqIosMembershipPurchaseFeedback.verificationFailed,
    );
  });

  test('local StoreKit configuration matches production product IDs', () {
    final configuration = jsonDecode(
      File('ios/Runner/KQMembership.storekit').readAsStringSync(),
    ) as Map<String, dynamic>;
    final groups = configuration['subscriptionGroups'] as List<dynamic>;
    final group = groups.single as Map<String, dynamic>;
    final subscriptions = group['subscriptions'] as List<dynamic>;
    final subscriptionsByProductId = {
      for (final subscription in subscriptions.cast<Map<String, dynamic>>())
        subscription['productID'] as String: subscription,
    };
    final products = configuration['products'] as List<dynamic>;
    final productsByProductId = {
      for (final product in products.cast<Map<String, dynamic>>())
        product['productID'] as String: product,
    };
    final scheme = File(
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ).readAsStringSync();

    expect(subscriptionsByProductId.keys, {
      'com.kunqiong.remotelink.member.monthly',
      'com.kunqiong.remotelink.member.quarterly',
      'com.kunqiong.remotelink.member.halfyear',
      'com.kunqiong.remotelink.member.yearly',
    });
    expect(
      subscriptionsByProductId['com.kunqiong.remotelink.member.monthly']
          ?['recurringSubscriptionPeriod'],
      'P1M',
    );
    expect(
      subscriptionsByProductId['com.kunqiong.remotelink.member.quarterly']
          ?['recurringSubscriptionPeriod'],
      'P3M',
    );
    expect(
      subscriptionsByProductId['com.kunqiong.remotelink.member.halfyear']
          ?['recurringSubscriptionPeriod'],
      'P6M',
    );
    expect(
      subscriptionsByProductId['com.kunqiong.remotelink.member.yearly']
          ?['recurringSubscriptionPeriod'],
      'P1Y',
    );
    expect(
      productsByProductId['com.kunqiong.remotelink.member.lifetime']?['type'],
      'NonConsumable',
    );
    expect(scheme, contains('../Runner/KQMembership.storekit'));
  });

  test('release build rejects the local StoreKit test switch', () {
    final script = File('build_ios.sh').readAsStringSync();

    expect(script, contains('KQ_IOS_IAP_LOCAL_STOREKIT_TEST is debug-only'));
  });

  test(
      'StoreKit verification payload contains mapped package and transaction data',
      () {
    const payload = KqIosPurchaseVerificationPayload(
      packageId: 'monthly',
      productId: 'com.kunqiong.remotelink.member.monthly',
      transactionId: 'transaction-1',
      serverVerificationData: 'signed-transaction',
      localVerificationData: 'local-transaction',
      source: 'app_store',
    );

    expect(payload.toJson(), <String, String>{
      'package_id': 'monthly',
      'product_id': 'com.kunqiong.remotelink.member.monthly',
      'transaction_id': 'transaction-1',
      'server_verification_data': 'signed-transaction',
      'local_verification_data': 'local-transaction',
      'source': 'app_store',
    });
  });

  test('StoreKit verification result applies the server-issued expiry', () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller, contains('class KqIosPurchaseVerificationResult'));
    expect(controller, contains("expireAt: (body['expire_at'] ?? '')"));
    expect(controller, contains('final verifiedMembership ='));
    expect(controller, contains('refreshMembership(verifiedMembership)'));
    expect(page, contains('KqIosPurchaseVerificationResult verification'));
    expect(page, contains('applyVerifiedAppleMembership'));
  });

  test('Apple verification does not overwrite the server-issued expiry', () {
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();
    final callbackStart = page.indexOf(
      'refreshMembership: (KqIosPurchaseVerificationResult verification) async',
    );
    final callbackEnd = page.indexOf('    )..addListener', callbackStart);
    expect(callbackStart, greaterThanOrEqualTo(0));
    expect(callbackEnd, greaterThan(callbackStart));

    final callbackSource = page.substring(callbackStart, callbackEnd);
    expect(callbackSource, contains('applyVerifiedAppleMembership'));
    expect(
        callbackSource, isNot(contains('refreshMembership(showError: true)')));
  });

  test(
      'iOS account page opens StoreKit purchase UI instead of external payment',
      () {
    final source =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();

    expect(source, contains('KqIosMembershipPurchasePage'));
    expect(source, contains('appleInAppPurchaseRequired'));
  });

  test('purchase completion failure cannot be overwritten by success', () {
    final source =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();

    expect(source, contains('purchase.pendingCompletePurchase &&'));
    expect(source, contains('!await _completePurchase(purchase)'));
    expect(source, contains('_verifyingPurchaseKeys'));
    expect(source, contains('localStoreKitTestMode && kDebugMode'));
  });

  test(
      'server-verified Apple transactions finish before local membership state sync',
      () {
    final source =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final verificationStart = source.indexOf('final verifiedMembership =');
    final completionStart = source.indexOf(
      'await _completePurchase(purchase)',
      verificationStart,
    );
    final membershipSyncStart = source.indexOf(
      'refreshMembership(verifiedMembership)',
      verificationStart,
    );

    expect(verificationStart, greaterThanOrEqualTo(0));
    expect(completionStart, greaterThan(verificationStart));
    expect(membershipSyncStart, greaterThan(completionStart));
  });

  test('iOS payment only presents mapped StoreKit plans and real prices', () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller, contains('if (_productsByStoreId.isEmpty)'));
    expect(controller, contains('Apple membership products are unavailable.'));
    expect(page, contains('final configuredPackageIds ='));
    expect(page, contains('config.packageToProductId.keys'));
    expect(page, contains('final price = product?.price ?? text'));
    expect(page, contains("text('暂不可用', 'Unavailable')"));
    expect(page, isNot(contains('product!.description')));
  });

  test('iOS StoreKit purchase does not depend on the legacy package API', () {
    final account =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(
        account,
        contains(
            'if (route == KqIosMembershipPaymentRoute.appleInAppPurchaseRequired)'));
    expect(account, contains('keepExistingOnFailure: true'));
    expect(page, contains('final configuredPackageIds ='));
    expect(page, contains('config.packageToProductId.keys'));
  });

  test('iOS payment keeps StoreKit diagnostics out of the customer-facing UI',
      () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller, contains('unavailableProductIds.join'));
    expect(controller, contains('debugPrint'));
    expect(page, isNot(contains('Apple 未返回商品')));
    expect(page, isNot(contains('请确认 App Store Connect 商品 ID')));
    expect(page, contains('当前暂时无法购买会员，请稍后重试'));
  });

  test('iOS purchase page exposes subscription terms and restore affordance',
      () {
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(page, contains('KQ_TERMS_OF_SERVICE_URL'));
    expect(page, contains('_IosMembershipLegalFooter'));
    expect(page, contains('订阅会按所选套餐周期自动续订'));
    expect(page, contains('付款将在确认购买时从 Apple ID 扣款'));
    expect(page, contains('隐私政策'));
    expect(page, contains('用户协议'));
    expect(page, contains('恢复购买'));
    expect(page, contains('TextButton.icon('));
    expect(page, isNot(contains('OutlinedButton.icon(')));
  });

  test('iOS payment distinguishes Apple payment from verification outage', () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller, contains('server_verification_started'));
    expect(controller, contains('transaction_present='));
    expect(controller, contains('endpoint_host='));
    expect(controller, contains('endpoint_path='));
    expect(controller, contains('store_error_code='));
    expect(controller, contains('store_error_source='));
    expect(page, contains('Apple 付款可能已完成，但会员验证服务暂不可用'));
    expect(page, contains('请不要重复购买'));
  });

  test(
      'iOS purchase page allows changing membership plan after verified purchase',
      () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller,
        isNot(contains('phase != KqIosMembershipPurchasePhase.completed')));
    expect(controller, contains('bool get hasVerifiedMembership'));
    expect(page, contains('isMembershipActive:'));
    expect(page, contains("text('升级', 'Upgrade')"));
  });

  test('iOS membership and screen sharing pages compile', () {
    expect(KqIosMembershipPurchasePage, isNotNull);
    expect(ServerInfo, isNotNull);
  });

  test('StoreKit dependency resolves with CI Flutter 3.44.5', () {
    final workflow =
        File('../.github/workflows/ios-preflight.yml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();

    expect(workflow, contains('FLUTTER_VERSION: "3.44.5"'));
    expect(pubspec, contains('in_app_purchase: 3.2.3'));
    expect(lock, contains('  in_app_purchase:'));
    expect(lock, contains('  in_app_purchase_platform_interface:'));
    expect(lock, contains('  in_app_purchase_storekit:'));
  });

  test(
      'a successfully verified transaction is not verified again in the same page',
      () {
    final source =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();

    expect(source, contains('_verifiedPurchaseKeys'));
    expect(source, contains('duplicate_verified_purchase_completed'));
  });

  test(
      'a duplicate verified Apple transaction is still completed and leaves the purchasing state',
      () {
    final source =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final duplicateStart =
        source.indexOf('if (_verifiedPurchaseKeys.contains(purchaseKey))');
    final duplicateEnd = source.indexOf(
      'if (!_verifyingPurchaseKeys.add(purchaseKey))',
      duplicateStart,
    );

    expect(duplicateStart, greaterThanOrEqualTo(0));
    expect(duplicateEnd, greaterThan(duplicateStart));
    final duplicateBranch = source.substring(duplicateStart, duplicateEnd);
    expect(duplicateBranch, contains('duplicate_verified_purchase_completed'));
    expect(duplicateBranch, contains('await _completePurchase(purchase)'));
    expect(duplicateBranch, isNot(contains('_verifyPurchase(')));
    expect(
      duplicateBranch,
      contains('phase = KqIosMembershipPurchasePhase.completed'),
    );
  });

  test(
      'an unverified Apple transaction blocks another checkout until it is restored',
      () {
    final source =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final buyStart = source.indexOf('Future<void> buy(String packageId) async');
    final checkoutStart = source.indexOf('_store.buyNonConsumable', buyStart);
    final verificationCatch = source.indexOf(
        '} catch (error) {', source.indexOf('final verifiedMembership ='));
    final verificationFinally =
        source.indexOf('} finally {', verificationCatch);

    expect(source, contains('_pendingVerificationPurchaseKeys'));
    expect(source, contains('bool get hasPendingVerification'));
    expect(source, contains('!hasPendingVerification'));
    expect(buyStart, greaterThanOrEqualTo(0));
    expect(checkoutStart, greaterThan(buyStart));
    expect(
      source.indexOf('if (hasPendingVerification)', buyStart),
      lessThan(checkoutStart),
    );
    expect(verificationCatch, greaterThanOrEqualTo(0));
    expect(verificationFinally, greaterThan(verificationCatch));
    expect(
      source.indexOf('_pendingVerificationPurchaseKeys.add(purchaseKey)',
          verificationCatch),
      lessThan(verificationFinally),
      );
    });

  test('a pending Apple update keeps the purchase recovery timeout armed', () {
    final source =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final updateStart =
        source.indexOf('Future<void> _handlePurchaseUpdates(');
    final updateEnd = source.indexOf('  Future<KqIosPurchaseVerificationResult>',
        updateStart);
    expect(updateStart, greaterThanOrEqualTo(0));
    expect(updateEnd, greaterThan(updateStart));
    final updateSource = source.substring(updateStart, updateEnd);
    final pendingBranch =
        updateSource.indexOf('if (purchase.status == PurchaseStatus.pending)');
    final firstCancel = updateSource.indexOf('_cancelPurchaseUpdateTimeout()');
    expect(pendingBranch, greaterThanOrEqualTo(0));
    expect(firstCancel, greaterThan(pendingBranch));
  });

  test(
      'an existing Apple subscription times out into restore instead of waiting forever',
      () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller, contains('existingSubscriptionRequiresRestore'));
    expect(controller, contains('_requiresRestoreBeforePurchase'));
    expect(controller, contains('!requiresRestoreBeforePurchase'));
    expect(controller, contains('purchase_update_timeout'));
    expect(controller, contains('_schedulePurchaseUpdateTimeout'));
    expect(controller, contains('_restoreExistingSubscriptionAfterTimeout'));
    expect(
        controller,
        contains(
            'KqIosMembershipPurchaseFeedback.existingSubscriptionRequiresRestore'));
    expect(page, contains('此 Apple ID 已有有效订阅'));
    expect(page, contains('同步会员权益'));
  });
}
