import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

import 'api_service.dart';

enum CreditPurchaseState {
  idle,
  opening,
  pending,
  verifying,
  completed,
  cancelled,
  failed,
  verificationPending,
}

class CreditPurchaseService {
  CreditPurchaseService._();

  static final instance = CreditPurchaseService._();
  static const productId = 'credits_500';

  final state = ValueNotifier(CreditPurchaseState.idle);
  final _store = InAppPurchase.instance;
  final _api = ApiService();

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future<void>.value();

  final _done = <String>{};
  final _waiting = <String, PurchaseDetails>{};

  Timer? _retry;
  int _retries = 0;

  void start() {
    _subscription ??= _store.purchaseStream.listen(
      (purchases) {
        _queue = _queue
            .catchError((Object _) {})
            .then((_) => _handle(purchases))
            .catchError((Object _) {
          state.value = CreditPurchaseState.verificationPending;
        });
      },
      onError: (Object _) {
        state.value = CreditPurchaseState.failed;
      },
    );
  }

  Future<ProductDetails?> product() async {
    start();

    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !await _store.isAvailable()) {
      return null;
    }

    final result = await _store.queryProductDetails({productId});

    if (result.error != null || result.productDetails.length != 1) {
      return null;
    }

    return result.productDetails.single;
  }

  Future<bool> buy() async {
    start();

    if ([
      CreditPurchaseState.opening,
      CreditPurchaseState.pending,
      CreditPurchaseState.verifying,
      CreditPurchaseState.verificationPending,
    ].contains(state.value)) {
      return false;
    }

    state.value = CreditPurchaseState.opening;

    try {
      final details = await product();

      if (details == null) {
        throw StateError('PRODUCT_UNAVAILABLE');
      }

      final opened = await _store.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
        autoConsume: false,
      );

      if (!opened) {
        state.value = CreditPurchaseState.failed;
      }

      return opened;
    } catch (_) {
      state.value = CreditPurchaseState.failed;
      return false;
    }
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != productId &&
    purchase.productID != 'credits_100') {
  continue;
}

      if (purchase.status == PurchaseStatus.pending) {
        state.value = CreditPurchaseState.pending;
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled ||
          purchase.status == PurchaseStatus.error) {
        state.value = purchase.status == PurchaseStatus.canceled
            ? CreditPurchaseState.cancelled
            : CreditPurchaseState.failed;

        if (purchase.pendingCompletePurchase) {
          try {
            await _store.completePurchase(purchase);
          } catch (_) {}
        }

        continue;
      }

      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }

      final token = purchase.verificationData.serverVerificationData;

      if (token.isEmpty || _done.contains(token)) continue;

      _waiting[token] = purchase;
      state.value = CreditPurchaseState.verifying;

      try {
        final verified = await _api.verifyPurchase(
          purchaseToken: token,
          productId: purchase.productID,
        );

        if (!verified) {
          throw StateError('VERIFICATION_PENDING');
        }

        final android = _store.getPlatformAddition<
            InAppPurchaseAndroidPlatformAddition>();

        final consumed = await android.consumePurchase(purchase);

        if (consumed.responseCode != BillingResponse.ok &&
            consumed.responseCode != BillingResponse.itemNotOwned) {
          throw StateError('CONSUMPTION_PENDING');
        }

        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }

        _waiting.remove(token);
        _done.add(token);
        _retries = 0;

        state.value = CreditPurchaseState.completed;
      } catch (_) {
        state.value = CreditPurchaseState.verificationPending;
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    if (_retry?.isActive == true || _retries >= 5) return;

    _retry = Timer(
      Duration(seconds: 10 * (++_retries)),
      () {
        final pending = _waiting.values.toList(growable: false);

        _queue = _queue
            .catchError((Object _) {})
            .then((_) => _handle(pending))
            .catchError((Object _) {
          state.value = CreditPurchaseState.verificationPending;
        });
      },
    );
  }

  Future<void> checkPending() async {
    start();

    try {
      _retries = 0;

      final pending = _waiting.values.toList(growable: false);

      _queue = _queue
          .catchError((Object _) {})
          .then((_) => _handle(pending));

      await _queue;
      await _store.restorePurchases();
    } catch (_) {
      state.value = CreditPurchaseState.verificationPending;
    }
  }
}