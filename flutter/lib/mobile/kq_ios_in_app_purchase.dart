import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

class KqIosInAppPurchaseConfig {
  const KqIosInAppPurchaseConfig._({
    required this.packageToProductId,
    required this.verificationUrl,
    required this.configurationError,
  });

  static const productsJson =
      String.fromEnvironment('KQ_IOS_IAP_PRODUCTS', defaultValue: '');
  static const verificationUrlValue =
      String.fromEnvironment('KQ_IOS_IAP_VERIFY_URL', defaultValue: '');

  factory KqIosInAppPurchaseConfig.fromEnvironment() {
    return KqIosInAppPurchaseConfig.fromValues(
      productsJson: productsJson,
      verificationUrl: verificationUrlValue,
    );
  }

  factory KqIosInAppPurchaseConfig.fromValues({
    required String productsJson,
    required String verificationUrl,
  }) {
    final packageToProductId = <String, String>{};
    String? configurationError;
    try {
      final decoded = jsonDecode(productsJson.trim());
      if (decoded is! Map) {
        configurationError = 'StoreKit product mapping is missing.';
      } else {
        for (final entry in decoded.entries) {
          final packageId = entry.key.toString().trim();
          final productId = entry.value.toString().trim();
          if (packageId.isEmpty || productId.isEmpty) {
            configurationError =
                'StoreKit product mapping contains an empty ID.';
            break;
          }
          packageToProductId[packageId] = productId;
        }
        if (packageToProductId.isEmpty && configurationError == null) {
          configurationError = 'StoreKit product mapping is missing.';
        }
        if (packageToProductId.values.toSet().length !=
            packageToProductId.length) {
          configurationError =
              'Each membership package must use a distinct StoreKit product ID.';
        }
      }
    } catch (_) {
      configurationError = 'StoreKit product mapping is invalid.';
    }

    final parsedVerificationUrl = Uri.tryParse(verificationUrl.trim());
    if (parsedVerificationUrl == null ||
        parsedVerificationUrl.scheme != 'https' ||
        parsedVerificationUrl.host.isEmpty) {
      configurationError ??=
          'StoreKit verification must use a configured HTTPS endpoint.';
    }

    return KqIosInAppPurchaseConfig._(
      packageToProductId: Map.unmodifiable(packageToProductId),
      verificationUrl: parsedVerificationUrl != null &&
              parsedVerificationUrl.scheme == 'https' &&
              parsedVerificationUrl.host.isNotEmpty
          ? parsedVerificationUrl
          : null,
      configurationError: configurationError,
    );
  }

  final Map<String, String> packageToProductId;
  final Uri? verificationUrl;
  final String? configurationError;

  bool get isConfigured =>
      packageToProductId.isNotEmpty &&
      verificationUrl != null &&
      configurationError == null;

  String? productForPackage(String packageId) =>
      packageToProductId[packageId.trim()];

  String? packageForProduct(String productId) {
    for (final entry in packageToProductId.entries) {
      if (entry.value == productId.trim()) return entry.key;
    }
    return null;
  }
}

class KqIosPurchaseVerificationPayload {
  const KqIosPurchaseVerificationPayload({
    required this.packageId,
    required this.productId,
    required this.transactionId,
    required this.serverVerificationData,
    required this.localVerificationData,
    required this.source,
  });

  factory KqIosPurchaseVerificationPayload.fromPurchase({
    required String packageId,
    required PurchaseDetails purchase,
  }) {
    return KqIosPurchaseVerificationPayload(
      packageId: packageId,
      productId: purchase.productID,
      transactionId: purchase.purchaseID ?? '',
      serverVerificationData: purchase.verificationData.serverVerificationData,
      localVerificationData: purchase.verificationData.localVerificationData,
      source: purchase.verificationData.source,
    );
  }

  final String packageId;
  final String productId;
  final String transactionId;
  final String serverVerificationData;
  final String localVerificationData;
  final String source;

  Map<String, String> toJson() => <String, String>{
        'package_id': packageId,
        'product_id': productId,
        'transaction_id': transactionId,
        'server_verification_data': serverVerificationData,
        'local_verification_data': localVerificationData,
        'source': source,
      };
}

enum KqIosMembershipPurchasePhase {
  initial,
  loading,
  ready,
  purchasing,
  restoring,
  completed,
  failed,
}

/// Owns the StoreKit transaction subscription for one membership purchase page.
/// Membership state is refreshed only after the configured server verifies the
/// Apple transaction; the client never grants a local entitlement itself.
class KqIosMembershipPurchaseController extends ChangeNotifier {
  KqIosMembershipPurchaseController({
    required this.config,
    required this.accessTokenProvider,
    required this.refreshMembership,
    InAppPurchase? store,
  }) : _store = store ?? InAppPurchase.instance;

  final KqIosInAppPurchaseConfig config;
  final String Function() accessTokenProvider;
  final Future<void> Function() refreshMembership;
  final InAppPurchase _store;
  final Map<String, ProductDetails> _productsByStoreId = {};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Set<String> _notFoundProductIds = const <String>{};

  KqIosMembershipPurchasePhase phase = KqIosMembershipPurchasePhase.initial;
  String? statusMessage;

  bool get isBusy =>
      phase == KqIosMembershipPurchasePhase.loading ||
      phase == KqIosMembershipPurchasePhase.purchasing ||
      phase == KqIosMembershipPurchasePhase.restoring;

  bool get isReady => phase == KqIosMembershipPurchasePhase.ready;

  bool get hasUnavailableProducts => _notFoundProductIds.isNotEmpty;

  Set<String> get unavailableProductIds =>
      Set<String>.unmodifiable(_notFoundProductIds);

  String get unavailableProductIdsText => unavailableProductIds.join(', ');

  bool isPackageAvailable(String packageId) {
    final productId = config.productForPackage(packageId);
    return productId != null && _productsByStoreId.containsKey(productId);
  }

  ProductDetails? productForPackage(String packageId) {
    final productId = config.productForPackage(packageId);
    return productId == null ? null : _productsByStoreId[productId];
  }

  bool isProductMissing(String packageId) {
    final productId = config.productForPackage(packageId);
    return productId != null && _notFoundProductIds.contains(productId);
  }

  Future<void> initialize() async {
    if (!config.isConfigured) {
      _setFailure(config.configurationError ?? 'StoreKit is not configured.');
      return;
    }
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_) => _setFailure('Unable to receive Apple purchase updates.'),
      onDone: () => _purchaseSubscription?.cancel(),
    );
    phase = KqIosMembershipPurchasePhase.loading;
    statusMessage = null;
    notifyListeners();
    try {
      if (!await _store.isAvailable()) {
        _setFailure('Apple payment service is unavailable.');
        return;
      }
      final response = await _store.queryProductDetails(
        config.packageToProductId.values.toSet(),
      );
      _productsByStoreId
        ..clear()
        ..addEntries(
          response.productDetails
              .map((product) => MapEntry(product.id, product)),
        );
      _notFoundProductIds = response.notFoundIDs.toSet();
      if (_notFoundProductIds.isNotEmpty) {
        debugPrint(
          'StoreKit did not return configured product IDs: '
          '${_notFoundProductIds.join(', ')}',
        );
      }
      if (response.error != null) {
        _setFailure('Unable to load Apple membership products.');
        return;
      }
      if (_productsByStoreId.isEmpty) {
        _setFailure('Apple membership products are unavailable.');
        return;
      }
      phase = KqIosMembershipPurchasePhase.ready;
      statusMessage = null;
      notifyListeners();
    } catch (_) {
      _setFailure('Unable to load Apple membership products.');
    }
  }

  Future<void> buy(String packageId) async {
    if (isBusy) return;
    final product = productForPackage(packageId);
    if (product == null) {
      _setFailure('This membership product is unavailable in the App Store.');
      return;
    }
    phase = KqIosMembershipPurchasePhase.purchasing;
    statusMessage = null;
    notifyListeners();
    try {
      final accepted = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!accepted) {
        _setFailure('Apple could not start the purchase.');
      }
    } catch (_) {
      _setFailure('Apple could not start the purchase.');
    }
  }

  Future<void> restorePurchases() async {
    if (isBusy) return;
    phase = KqIosMembershipPurchasePhase.restoring;
    statusMessage = null;
    notifyListeners();
    try {
      await _store.restorePurchases();
      if (phase == KqIosMembershipPurchasePhase.restoring) {
        phase = KqIosMembershipPurchasePhase.ready;
        statusMessage = 'Restore request sent. Checking Apple purchases.';
        notifyListeners();
      }
    } catch (_) {
      _setFailure('Unable to restore Apple purchases.');
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        phase = KqIosMembershipPurchasePhase.purchasing;
        statusMessage = 'Waiting for Apple payment confirmation.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        _setFailure('Apple payment was cancelled.');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _setFailure('Apple payment could not be completed.');
        if (purchase.pendingCompletePurchase) {
          await _completePurchase(purchase);
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final packageId = config.packageForProduct(purchase.productID);
      if (packageId == null) {
        _setFailure('Apple returned an unknown membership product.');
        continue;
      }
      phase = KqIosMembershipPurchasePhase.purchasing;
      statusMessage = 'Verifying Apple purchase.';
      notifyListeners();
      try {
        await _verifyPurchase(packageId, purchase);
        await refreshMembership();
        if (purchase.pendingCompletePurchase &&
            !await _completePurchase(purchase)) {
          continue;
        }
        phase = KqIosMembershipPurchasePhase.completed;
        statusMessage = purchase.status == PurchaseStatus.restored
            ? 'Apple purchases restored.'
            : 'Membership benefits are active.';
        notifyListeners();
      } catch (_) {
        _setFailure(
            'Unable to verify the Apple purchase. Please restore purchases later.');
      }
    }
  }

  Future<void> _verifyPurchase(
    String packageId,
    PurchaseDetails purchase,
  ) async {
    final token = accessTokenProvider().trim();
    if (token.isEmpty) {
      throw StateError(
          'Account login is required for Apple purchase verification.');
    }
    final endpoint = config.verificationUrl;
    if (endpoint == null) {
      throw StateError('Apple purchase verification is not configured.');
    }
    final payload = KqIosPurchaseVerificationPayload.fromPurchase(
      packageId: packageId,
      purchase: purchase,
    );
    final response = await http
        .post(
          endpoint,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload.toJson()),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Apple purchase verification failed.');
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['success'] == false) {
        throw StateError('Apple purchase verification failed.');
      }
      final code = int.tryParse((body is Map ? body['code'] : '').toString());
      if (code != null && code != 0 && code != 200) {
        throw StateError('Apple purchase verification failed.');
      }
    } on FormatException {
      throw StateError('Apple purchase verification returned invalid data.');
    }
  }

  Future<bool> _completePurchase(PurchaseDetails purchase) async {
    try {
      await _store.completePurchase(purchase);
      return true;
    } catch (_) {
      _setFailure('Apple payment was verified, but could not be finalized.');
      return false;
    }
  }

  void _setFailure(String message) {
    phase = KqIosMembershipPurchasePhase.failed;
    statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
