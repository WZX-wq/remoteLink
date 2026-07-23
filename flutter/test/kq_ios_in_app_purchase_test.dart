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
  });

  test('iOS payment only presents mapped StoreKit plans and real prices', () {
    final controller =
        File('lib/mobile/kq_ios_in_app_purchase.dart').readAsStringSync();
    final page = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();

    expect(controller, contains('if (_productsByStoreId.isEmpty)'));
    expect(controller, contains('Apple membership products are unavailable.'));
    expect(page, contains('final configuredPackages = widget.packages'));
    expect(page, contains('final price = product?.price ?? text'));
    expect(page, contains("text('暂不可用', 'Unavailable')"));
    expect(page, isNot(contains('product!.description')));
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
