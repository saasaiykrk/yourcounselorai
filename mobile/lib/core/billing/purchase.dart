import '../api/api_exceptions.dart';
import '../api/billing_models.dart';
import 'billing_repository.dart';
import 'payment_gateway.dart';

/// How a purchase ended, as far as the SERVER knows. "Done" only ever comes from an order the
/// server marked paid after checking with Razorpay.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

final class PurchaseDone extends PurchaseOutcome {
  const PurchaseDone(this.order);

  final BillingOrder order;
}

/// The bank has not confirmed yet. Credits appear once it does (the app checks again later).
final class PurchasePending extends PurchaseOutcome {
  const PurchasePending(this.orderId);

  final String orderId;
}

final class PurchaseCancelled extends PurchaseOutcome {
  const PurchaseCancelled();
}

final class PurchaseFailed extends PurchaseOutcome {
  const PurchaseFailed(this.message);

  final String message;
}

/// One purchase: the server creates and prices the order → Razorpay checkout → the server
/// verifies (signature + Razorpay's own record) → a short wait for a payment still confirming.
class PurchaseFlow {
  PurchaseFlow(this._repo, this._gateway, {this.pollEvery = const Duration(seconds: 3), this.pollTimes = 5});

  final BillingRepository _repo;
  final PaymentGateway _gateway;
  final Duration pollEvery;
  final int pollTimes;

  Future<PurchaseOutcome> buy({required String plan, String? reportType}) async {
    final OrderStart start;
    try {
      start = await _repo.createOrder(plan: plan, reportType: reportType);
    } on BillingRefused catch (e) {
      return PurchaseFailed(e.message);
    } on NetworkProblem {
      return const PurchaseFailed("Couldn't reach Your Counselor. Check your connection and try again.");
    } on ApiException {
      return const PurchaseFailed("Couldn't start the payment. Try again.");
    }
    final checkout = start.checkout;
    if (checkout == null) {
      // A free plan: the server granted it already, if it says so.
      return start.order.paid ? PurchaseDone(start.order) : PurchasePending(start.order.id);
    }
    if (!_gateway.supported) {
      await _quietly(() => _repo.cancelOrder(start.order.id));
      return const PurchaseFailed('Payments work in the Android and iPhone app only.');
    }
    final result = await _gateway.open(checkout);
    switch (result) {
      case CheckoutCancelled():
        await _quietly(() => _repo.cancelOrder(start.order.id));
        return const PurchaseCancelled();
      case CheckoutFailed(:final message):
        return PurchaseFailed(message);
      case CheckoutCompleted():
        return _confirm(start.order.id, result);
    }
  }

  Future<PurchaseOutcome> _confirm(String orderId, CheckoutCompleted payment) async {
    BillingOrder? order;
    try {
      order = await _repo.verify(orderId, payment);
    } on BillingRefused catch (e) {
      return PurchaseFailed(e.message);
    } on ApiException {
      // Not reachable right now: the server still learns of the payment from Razorpay.
      return PurchasePending(orderId);
    }
    for (var i = 0; i < pollTimes && !order!.paid && order.status == 'pending'; i++) {
      await Future<void>.delayed(pollEvery);
      try {
        order = await _repo.order(orderId);
      } on ApiException {
        break;
      }
    }
    return switch (order!.status) {
      'paid' => PurchaseDone(order),
      'failed' => PurchaseFailed(
        order.failureReason == null ? 'The payment failed.' : 'The payment failed: ${order.failureReason}',
      ),
      _ => PurchasePending(orderId),
    };
  }

  static Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
