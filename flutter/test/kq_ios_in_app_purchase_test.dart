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

  test('local StoreKit configuration matches the production product ID', () {
    final configuration = jsonDecode(
      File('ios/Runner/KQMembership.storekit').readAsStringSync(),
    ) as Map<String, dynamic>;
    final groups = configuration['subscriptionGroups'] as List<dynamic>;
    final group = groups.single as Map<String, dynamic>;
    final subscriptions = group['subscriptions'] as List<dynamic>;
    final subscription = subscriptions.single as Map<String, dynamic>;
    final scheme = File(
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ).readAsStringSync();

    expect(subscription['productID'], 'com.kunqiong.remotelink.member.monthly');
    expect(subscription['type'], 'RecurringSubscription');
    expect(subscription['recurringSubscriptionPeriod'], 'P1M');
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
}
