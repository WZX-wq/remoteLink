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
    required this.localStoreKitTestMode,
  });

  static const productsJson =
      String.fromEnvironment('KQ_IOS_IAP_PRODUCTS', defaultValue: '');
  static const verificationUrlValue =
      String.fromEnvironment('KQ_IOS_IAP_VERIFY_URL', defaultValue: '');
  static const localStoreKitTestModeValue = bool.fromEnvironment(
    'KQ_IOS_IAP_LOCAL_STOREKIT_TEST',
    defaultValue: false,
  );

  factory KqIosInAppPurchaseConfig.fromEnvironment() {
    return KqIosInAppPurchaseConfig.fromValues(
      productsJson: productsJson,
      verificationUrl: verificationUrlValue,
      localStoreKitTestMode: localStoreKitTestModeValue,
    );
  }

  factory KqIosInAppPurchaseConfig.fromValues({
    required String productsJson,
    required String verificationUrl,
    bool localStoreKitTestMode = false,
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
      localStoreKitTestMode: localStoreKitTestMode && kDebugMode,
    );
  }

  final Map<String, String> packageToProductId;
  final Uri? verificationUrl;
  final String? configurationError;
  final bool localStoreKitTestMode;

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

enum KqIosMembershipPurchaseFeedback {
  configurationInvalid,
  storeUnavailable,
  productUnavailable,
  paymentCancelled,
  paymentFailed,
  existingSubscriptionRequiresRestore,
  accountAuthenticationRequired,
  purchaseAlreadyLinked,
  verificationServiceUnavailable,
  verificationFailed,
  purchaseFinalizationFailed,
  unknownProduct,
  localStoreKitTestCompleted,
}

class KqIosPurchaseVerificationException implements Exception {
  const KqIosPurchaseVerificationException(this.feedback);

  final KqIosMembershipPurchaseFeedback feedback;

  @override
  String toString() => 'KqIosPurchaseVerificationException(${feedback.name})';
}

@visibleForTesting
KqIosMembershipPurchaseFeedback kqIosMembershipVerificationFeedbackForStatus(
    int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    return KqIosMembershipPurchaseFeedback.accountAuthenticationRequired;
  }
  if (statusCode == 409) {
    return KqIosMembershipPurchaseFeedback.purchaseAlreadyLinked;
  }
  if (statusCode >= 500) {
    return KqIosMembershipPurchaseFeedback.verificationServiceUnavailable;
  }
  return KqIosMembershipPurchaseFeedback.verificationFailed;
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

class KqIosPurchaseVerificationResult {
  const KqIosPurchaseVerificationResult({
    required this.active,
    required this.expireAt,
  });

  final bool active;
  final String expireAt;
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
  final Future<void> Function(KqIosPurchaseVerificationResult verification)
      refreshMembership;
  final InAppPurchase _store;
  final Map<String, ProductDetails> _productsByStoreId = {};
  final Set<String> _verifyingPurchaseKeys = <String>{};
  final Set<String> _pendingVerificationPurchaseKeys = <String>{};
  final Set<String> _verifiedPurchaseKeys = <String>{};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _purchaseUpdateTimeout;
  Set<String> _notFoundProductIds = const <String>{};
  bool _requiresRestoreBeforePurchase = false;

  KqIosMembershipPurchasePhase phase = KqIosMembershipPurchasePhase.initial;
  KqIosMembershipPurchaseFeedback? feedback;
  String? statusMessage;

  bool get isBusy =>
      phase == KqIosMembershipPurchasePhase.loading ||
      phase == KqIosMembershipPurchasePhase.purchasing ||
      phase == KqIosMembershipPurchasePhase.restoring;

  bool get isReady => phase == KqIosMembershipPurchasePhase.ready;

  bool get hasVerifiedMembership =>
      phase == KqIosMembershipPurchasePhase.completed;

  bool get hasPendingVerification =>
      _pendingVerificationPurchaseKeys.isNotEmpty;

  bool get requiresRestoreBeforePurchase => _requiresRestoreBeforePurchase;

  bool get canPurchase =>
      !isBusy &&
      !hasPendingVerification &&
      !requiresRestoreBeforePurchase &&
      _productsByStoreId.isNotEmpty;

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
    if (isBusy) return;
    if (!config.isConfigured) {
      _setFailure(
        KqIosMembershipPurchaseFeedback.configurationInvalid,
        config.configurationError ?? 'StoreKit is not configured.',
      );
      return;
    }
    _diagnostic('initialize_started',
        requestedProducts: config.packageToProductId.length);
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_, __) {
        _diagnostic('purchase_stream_error');
        _setFailure(
          KqIosMembershipPurchaseFeedback.storeUnavailable,
          'Unable to receive Apple purchase updates.',
        );
      },
      onDone: () => _diagnostic('purchase_stream_closed'),
    );
    phase = KqIosMembershipPurchasePhase.loading;
    feedback = null;
    statusMessage = null;
    notifyListeners();
    try {
      if (!await _store.isAvailable()) {
        _diagnostic('store_unavailable');
        _setFailure(
          KqIosMembershipPurchaseFeedback.storeUnavailable,
          'Apple payment service is unavailable.',
        );
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
      _diagnostic(
        'products_loaded',
        requestedProducts: config.packageToProductId.length,
        returnedProducts: _productsByStoreId.length,
        missingProducts: _notFoundProductIds.length,
        responseHasError: response.error != null,
      );
      if (response.error != null) {
        _setFailure(
          KqIosMembershipPurchaseFeedback.productUnavailable,
          'Unable to load Apple membership products.',
        );
        return;
      }
      if (_productsByStoreId.isEmpty) {
        _setFailure(
          KqIosMembershipPurchaseFeedback.productUnavailable,
          'Apple membership products are unavailable.',
        );
        return;
      }
      if (phase != KqIosMembershipPurchasePhase.loading) {
        notifyListeners();
        return;
      }
      phase = KqIosMembershipPurchasePhase.ready;
      feedback = null;
      statusMessage = null;
      notifyListeners();
    } catch (_) {
      _diagnostic('products_load_failed');
      _setFailure(
        KqIosMembershipPurchaseFeedback.productUnavailable,
        'Unable to load Apple membership products.',
      );
    }
  }

  Future<void> buy(String packageId) async {
    if (isBusy) return;
    if (hasPendingVerification) {
      _diagnostic('purchase_blocked_pending_verification');
      _setFailure(
        KqIosMembershipPurchaseFeedback.verificationServiceUnavailable,
        'An earlier Apple purchase is waiting for server verification.',
      );
      return;
    }
    if (requiresRestoreBeforePurchase) {
      _diagnostic('purchase_blocked_restore_required');
      _setFailure(
        KqIosMembershipPurchaseFeedback.existingSubscriptionRequiresRestore,
        'An existing Apple subscription must be restored before another purchase.',
      );
      return;
    }
    final product = productForPackage(packageId);
    if (product == null) {
      _setFailure(
        KqIosMembershipPurchaseFeedback.productUnavailable,
        'This membership product is unavailable in the App Store.',
      );
      return;
    }
    if (!config.localStoreKitTestMode && accessTokenProvider().trim().isEmpty) {
      _setFailure(
        KqIosMembershipPurchaseFeedback.accountAuthenticationRequired,
        'Account login is required before starting an Apple purchase.',
      );
      return;
    }
    phase = KqIosMembershipPurchasePhase.purchasing;
    feedback = null;
    statusMessage = null;
    notifyListeners();
    try {
      _diagnostic('purchase_started');
      final accepted = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!accepted) {
        _diagnostic('purchase_not_accepted');
        _setFailure(
          KqIosMembershipPurchaseFeedback.paymentFailed,
          'Apple could not start the purchase.',
        );
      } else {
        _schedulePurchaseUpdateTimeout();
      }
    } catch (error) {
      _cancelPurchaseUpdateTimeout();
      _diagnostic(
        'purchase_start_failed',
        exceptionType: error.runtimeType.toString(),
      );
      _setFailure(
        KqIosMembershipPurchaseFeedback.paymentFailed,
        'Apple could not start the purchase.',
      );
    }
  }

  Future<void> restorePurchases() async {
    if (isBusy) return;
    if (!config.localStoreKitTestMode && accessTokenProvider().trim().isEmpty) {
      _setFailure(
        KqIosMembershipPurchaseFeedback.accountAuthenticationRequired,
        'Account login is required before restoring Apple purchases.',
      );
      return;
    }
    phase = KqIosMembershipPurchasePhase.restoring;
    _cancelPurchaseUpdateTimeout();
    feedback = null;
    statusMessage = null;
    notifyListeners();
    try {
      _diagnostic('restore_started');
      await _store.restorePurchases();
      if (phase == KqIosMembershipPurchasePhase.restoring) {
        if (requiresRestoreBeforePurchase) {
          _diagnostic('restore_finished_without_transaction');
          _setFailure(
            KqIosMembershipPurchaseFeedback.existingSubscriptionRequiresRestore,
            'Apple did not return the existing subscription for restoration.',
          );
        } else {
          phase = KqIosMembershipPurchasePhase.ready;
          statusMessage = 'Restore request sent. Checking Apple purchases.';
          notifyListeners();
        }
      }
    } catch (error) {
      _diagnostic(
        'restore_failed',
        exceptionType: error.runtimeType.toString(),
      );
      _setFailure(
        KqIosMembershipPurchaseFeedback.paymentFailed,
        'Unable to restore Apple purchases.',
      );
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    _diagnostic('purchase_update_received', purchaseCount: purchases.length);
    _cancelPurchaseUpdateTimeout();
    for (final purchase in purchases) {
      _diagnostic(
        'purchase_details_received',
        productId: purchase.productID,
        purchaseStatus: purchase.status.name,
        pendingComplete: purchase.pendingCompletePurchase,
      );
      if (purchase.status == PurchaseStatus.pending) {
        phase = KqIosMembershipPurchasePhase.purchasing;
        feedback = null;
        statusMessage = 'Waiting for Apple payment confirmation.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        _diagnostic('purchase_cancelled');
        _setFailure(
          KqIosMembershipPurchaseFeedback.paymentCancelled,
          'Apple payment was cancelled.',
        );
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _diagnostic(
          'purchase_error',
          productId: purchase.productID,
          storeErrorSource: purchase.error?.source,
          storeErrorCode: purchase.error?.code,
        );
        _setFailure(
          KqIosMembershipPurchaseFeedback.paymentFailed,
          'Apple payment could not be completed.',
        );
        if (purchase.pendingCompletePurchase) {
          await _completePurchase(purchase, reportFailure: false);
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final packageId = config.packageForProduct(purchase.productID);
      if (packageId == null) {
        _pendingVerificationPurchaseKeys.add(_purchaseKey(purchase));
        _diagnostic('unknown_product_received');
        _setFailure(
          KqIosMembershipPurchaseFeedback.unknownProduct,
          'Apple returned an unknown membership product.',
        );
        continue;
      }
      final purchaseKey = _purchaseKey(purchase);
      if (_verifiedPurchaseKeys.contains(purchaseKey)) {
        _diagnostic(
          'duplicate_verified_purchase_completed',
          pendingComplete: purchase.pendingCompletePurchase,
        );
        if (purchase.pendingCompletePurchase &&
            !await _completePurchase(purchase)) {
          continue;
        }
        _pendingVerificationPurchaseKeys.remove(purchaseKey);
        _requiresRestoreBeforePurchase = false;
        phase = KqIosMembershipPurchasePhase.completed;
        feedback = null;
        statusMessage = 'Membership benefits are active.';
        notifyListeners();
        continue;
      }
      if (!_verifyingPurchaseKeys.add(purchaseKey)) {
        _diagnostic('duplicate_purchase_update_ignored');
        continue;
      }
      _pendingVerificationPurchaseKeys.add(purchaseKey);
      phase = KqIosMembershipPurchasePhase.purchasing;
      feedback = null;
      statusMessage = 'Verifying Apple purchase.';
      notifyListeners();
      try {
        if (config.localStoreKitTestMode) {
          _diagnostic('local_storekit_purchase_received');
          if (purchase.pendingCompletePurchase &&
              !await _completePurchase(purchase)) {
            continue;
          }
          _pendingVerificationPurchaseKeys.remove(purchaseKey);
          _requiresRestoreBeforePurchase = false;
          phase = KqIosMembershipPurchasePhase.completed;
          _verifiedPurchaseKeys.add(purchaseKey);
          feedback = KqIosMembershipPurchaseFeedback.localStoreKitTestCompleted;
          statusMessage =
              'Local StoreKit test completed without granting membership.';
          notifyListeners();
          continue;
        }
        final verifiedMembership = await _verifyPurchase(packageId, purchase);
        if (purchase.pendingCompletePurchase &&
            !await _completePurchase(purchase)) {
          continue;
        }
        _pendingVerificationPurchaseKeys.remove(purchaseKey);
        _requiresRestoreBeforePurchase = false;
        _verifiedPurchaseKeys.add(purchaseKey);
        try {
          await refreshMembership(verifiedMembership)
              .timeout(const Duration(seconds: 5));
        } on TimeoutException {
          _diagnostic('membership_state_sync_timed_out');
        } catch (error) {
          _diagnostic(
            'membership_state_sync_failed',
            exceptionType: error.runtimeType.toString(),
          );
        }
        phase = KqIosMembershipPurchasePhase.completed;
        feedback = null;
        statusMessage = purchase.status == PurchaseStatus.restored
            ? 'Apple purchases restored.'
            : 'Membership benefits are active.';
        notifyListeners();
      } catch (error) {
        final purchaseFeedback = error is KqIosPurchaseVerificationException
            ? error.feedback
            : KqIosMembershipPurchaseFeedback.verificationFailed;
        _diagnostic('purchase_verification_failed');
        _setFailure(
          purchaseFeedback,
          'Unable to verify the Apple purchase. Please restore purchases later.',
        );
      } finally {
        _verifyingPurchaseKeys.remove(purchaseKey);
      }
    }
  }

  Future<KqIosPurchaseVerificationResult> _verifyPurchase(
    String packageId,
    PurchaseDetails purchase,
  ) async {
    final token = accessTokenProvider().trim();
    if (token.isEmpty) {
      throw const KqIosPurchaseVerificationException(
        KqIosMembershipPurchaseFeedback.accountAuthenticationRequired,
      );
    }
    final endpoint = config.verificationUrl;
    if (endpoint == null) {
      throw const KqIosPurchaseVerificationException(
        KqIosMembershipPurchaseFeedback.configurationInvalid,
      );
    }
    final payload = KqIosPurchaseVerificationPayload.fromPurchase(
      packageId: packageId,
      purchase: purchase,
    );
    _diagnostic(
      'server_verification_started',
      packageId: packageId,
      productId: payload.productId,
      transactionPresent: payload.transactionId.isNotEmpty,
      endpointHost: endpoint.host,
      endpointPath: endpoint.path,
    );
    late http.Response response;
    try {
      response = await http
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
    } on TimeoutException {
      _diagnostic(
        'server_verification_timeout',
        endpointHost: endpoint.host,
        endpointPath: endpoint.path,
      );
      throw const KqIosPurchaseVerificationException(
        KqIosMembershipPurchaseFeedback.verificationServiceUnavailable,
      );
    } on http.ClientException {
      _diagnostic(
        'server_verification_network_error',
        endpointHost: endpoint.host,
        endpointPath: endpoint.path,
      );
      throw const KqIosPurchaseVerificationException(
        KqIosMembershipPurchaseFeedback.verificationServiceUnavailable,
      );
    }
    _diagnostic(
      'server_verification_response',
      httpStatus: response.statusCode,
      packageId: packageId,
      productId: payload.productId,
      endpointHost: endpoint.host,
      endpointPath: endpoint.path,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KqIosPurchaseVerificationException(
        kqIosMembershipVerificationFeedbackForStatus(response.statusCode),
      );
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) {
        throw const KqIosPurchaseVerificationException(
          KqIosMembershipPurchaseFeedback.verificationFailed,
        );
      }
      final code = int.tryParse(body['code'].toString());
      if (code != null && code != 0 && code != 200) {
        throw const KqIosPurchaseVerificationException(
          KqIosMembershipPurchaseFeedback.verificationFailed,
        );
      }
      _diagnostic('server_verification_succeeded');
      return KqIosPurchaseVerificationResult(
        active:
            (body['status'] ?? '').toString().trim().toLowerCase() != 'expired',
        expireAt: (body['expire_at'] ?? '').toString(),
      );
    } on FormatException {
      throw const KqIosPurchaseVerificationException(
        KqIosMembershipPurchaseFeedback.verificationFailed,
      );
    }
  }

  String _purchaseKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) {
      return '${purchase.productID}:$purchaseId';
    }
    return '${purchase.productID}:${purchase.verificationData.serverVerificationData.hashCode}';
  }

  Future<bool> _completePurchase(
    PurchaseDetails purchase, {
    bool reportFailure = true,
  }) async {
    try {
      await _store.completePurchase(purchase);
      _diagnostic('purchase_completed');
      return true;
    } catch (_) {
      _diagnostic('purchase_completion_failed');
      if (reportFailure) {
        _setFailure(
          KqIosMembershipPurchaseFeedback.purchaseFinalizationFailed,
          'Apple payment was verified, but could not be finalized.',
        );
      }
      return false;
    }
  }

  void _schedulePurchaseUpdateTimeout() {
    _purchaseUpdateTimeout?.cancel();
    _purchaseUpdateTimeout = Timer(const Duration(seconds: 30), () {
      if (phase != KqIosMembershipPurchasePhase.purchasing ||
          hasPendingVerification ||
          _verifyingPurchaseKeys.isNotEmpty) {
        return;
      }
      _requiresRestoreBeforePurchase = true;
      _diagnostic('purchase_update_timeout');
      unawaited(_restoreExistingSubscriptionAfterTimeout());
    });
  }

  Future<void> _restoreExistingSubscriptionAfterTimeout() async {
    if (phase != KqIosMembershipPurchasePhase.purchasing ||
        hasPendingVerification ||
        _verifyingPurchaseKeys.isNotEmpty) {
      return;
    }
    phase = KqIosMembershipPurchasePhase.restoring;
    feedback = null;
    statusMessage = 'Checking the existing Apple subscription.';
    notifyListeners();
    try {
      _diagnostic('restore_started_after_purchase_timeout');
      await _store.restorePurchases();
      if (phase == KqIosMembershipPurchasePhase.restoring) {
        _diagnostic('restore_finished_without_transaction');
        _setFailure(
          KqIosMembershipPurchaseFeedback.existingSubscriptionRequiresRestore,
          'Apple did not return the existing subscription for restoration.',
        );
      }
    } catch (error) {
      _diagnostic(
        'restore_failed_after_purchase_timeout',
        exceptionType: error.runtimeType.toString(),
      );
      _setFailure(
        KqIosMembershipPurchaseFeedback.existingSubscriptionRequiresRestore,
        'Unable to restore the existing Apple subscription.',
      );
    }
  }

  void _cancelPurchaseUpdateTimeout() {
    _purchaseUpdateTimeout?.cancel();
    _purchaseUpdateTimeout = null;
  }

  void _diagnostic(
    String event, {
    int? requestedProducts,
    int? returnedProducts,
    int? missingProducts,
    int? purchaseCount,
    int? httpStatus,
    bool? responseHasError,
    String? packageId,
    String? productId,
    bool? transactionPresent,
    String? storeErrorSource,
    String? storeErrorCode,
    String? purchaseStatus,
    bool? pendingComplete,
    String? exceptionType,
    String? endpointHost,
    String? endpointPath,
  }) {
    final fields = <String>[
      if (requestedProducts != null) 'requested=$requestedProducts',
      if (returnedProducts != null) 'returned=$returnedProducts',
      if (missingProducts != null) 'missing=$missingProducts',
      if (purchaseCount != null) 'purchases=$purchaseCount',
      if (httpStatus != null) 'http_status=$httpStatus',
      if (responseHasError != null) 'response_error=$responseHasError',
      if (packageId != null) 'package=$packageId',
      if (productId != null) 'product=$productId',
      if (transactionPresent != null) 'transaction_present=$transactionPresent',
      if (storeErrorSource != null) 'store_error_source=$storeErrorSource',
      if (storeErrorCode != null) 'store_error_code=$storeErrorCode',
      if (purchaseStatus != null) 'purchase_status=$purchaseStatus',
      if (pendingComplete != null) 'pending_complete=$pendingComplete',
      if (exceptionType != null) 'exception_type=$exceptionType',
      if (endpointHost != null) 'endpoint_host=$endpointHost',
      if (endpointPath != null) 'endpoint_path=$endpointPath',
    ];
    debugPrint(
        'KQ_IAP event=$event${fields.isEmpty ? '' : ' ${fields.join(' ')}'}');
  }

  void _setFailure(
    KqIosMembershipPurchaseFeedback purchaseFeedback,
    String message,
  ) {
    phase = KqIosMembershipPurchasePhase.failed;
    feedback = purchaseFeedback;
    statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelPurchaseUpdateTimeout();
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
