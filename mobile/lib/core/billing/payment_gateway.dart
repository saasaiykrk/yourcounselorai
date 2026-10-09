import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../api/billing_models.dart';

/// What Razorpay's checkout reported. This is never proof of payment: the app sends it to the
/// server, which checks the signature and asks Razorpay itself before granting anything.
sealed class CheckoutResult {
  const CheckoutResult();
}

final class CheckoutCompleted extends CheckoutResult {
  const CheckoutCompleted({required this.orderId, required this.paymentId, required this.signature});

  final String orderId;
  final String paymentId;
  final String signature;
}

final class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

final class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.message);

  final String message;
}

/// Opens a payment screen for an order the server created.
abstract interface class PaymentGateway {
  /// False where Razorpay's checkout can't run (web, desktop).
  bool get supported;

  Future<CheckoutResult> open(CheckoutDetails details);
}

/// Razorpay Standard Checkout (Android and iOS). Holds only the public key id from the server.
class RazorpayGateway implements PaymentGateway {
  @override
  bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<CheckoutResult> open(CheckoutDetails d) {
    final done = Completer<CheckoutResult>();
    final razorpay = Razorpay();
    void finish(CheckoutResult r) {
      if (!done.isCompleted) done.complete(r);
      razorpay.clear();
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final (order, payment, signature) = (r.orderId, r.paymentId, r.signature);
      finish(
        order == null || payment == null || signature == null
            ? const CheckoutFailed('The payment screen returned an incomplete answer.')
            : CheckoutCompleted(orderId: order, paymentId: payment, signature: signature),
      );
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      finish(
        r.code == Razorpay.PAYMENT_CANCELLED
            ? const CheckoutCancelled()
            : CheckoutFailed(
                r.code == Razorpay.NETWORK_ERROR
                    ? 'No connection during payment.'
                    : 'The payment did not go through. You have not been charged for this attempt.',
              ),
      );
    });
    // A wallet app took over: the server learns the outcome from Razorpay (webhook or the next check).
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) => finish(const CheckoutCancelled()));
    try {
      razorpay.open({
        'key': d.key,
        'order_id': d.orderId,
        'amount': d.amount,
        'currency': d.currency,
        'name': d.name,
        'description': d.description,
        'theme': {'color': '#6A11BA'},
        'retry': {'enabled': true, 'max_count': 2},
      });
    } catch (_) {
      finish(const CheckoutFailed("Couldn't open the payment screen."));
    }
    return done.future;
  }
}

/// Where payments can't run (preview, web). Never pretends a payment happened.
class UnsupportedPaymentGateway implements PaymentGateway {
  const UnsupportedPaymentGateway();

  @override
  bool get supported => false;

  @override
  Future<CheckoutResult> open(CheckoutDetails details) async =>
      const CheckoutFailed('Payments work in the Android and iPhone app only.');
}
