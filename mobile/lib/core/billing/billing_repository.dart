import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/billing_models.dart';
import 'payment_gateway.dart';

/// Plans, credits, payments and the own Anthropic key.
abstract interface class BillingRepository {
  Future<BillingPlans> plans();

  Future<BillingStatus> status();

  Future<OrderStart> createOrder({required String plan, String? reportType});

  Future<BillingOrder> verify(String orderId, CheckoutCompleted payment);

  Future<void> cancelOrder(String orderId);

  Future<BillingOrder> order(String orderId);

  Future<List<BillingOrder>> orders();

  Future<List<LedgerEntry>> ledger();

  Future<OwnKeyCheck> saveOwnKey(String apiKey);

  Future<OwnKeyCheck> checkOwnKey();

  Future<void> removeOwnKey();
}

class ApiBillingRepository implements BillingRepository {
  ApiBillingRepository(this._api);

  final ApiClient _api;

  @override
  Future<BillingPlans> plans() => _api.billingPlans();

  @override
  Future<BillingStatus> status() => _api.billingStatus();

  @override
  Future<OrderStart> createOrder({required String plan, String? reportType}) =>
      _api.createOrder(plan: plan, reportType: reportType);

  @override
  Future<BillingOrder> verify(String orderId, CheckoutCompleted p) =>
      _api.verifyPayment(orderId, razorpayOrderId: p.orderId, paymentId: p.paymentId, signature: p.signature);

  @override
  Future<void> cancelOrder(String orderId) => _api.cancelOrder(orderId);

  @override
  Future<BillingOrder> order(String orderId) => _api.order(orderId);

  @override
  Future<List<BillingOrder>> orders() => _api.orders();

  @override
  Future<List<LedgerEntry>> ledger() => _api.ledger();

  @override
  Future<OwnKeyCheck> saveOwnKey(String apiKey) => _api.saveOwnKey(apiKey);

  @override
  Future<OwnKeyCheck> checkOwnKey() => _api.checkOwnKey();

  @override
  Future<void> removeOwnKey() => _api.removeOwnKey();
}

/// Offline preview: pricing is off, so reports are free and nothing can be bought.
class PreviewBillingRepository implements BillingRepository {
  static const _off = BillingRefused(code: 'preview', message: 'Payments are not available in the preview.');

  @override
  Future<BillingPlans> plans() async => const BillingPlans(enabled: false);

  @override
  Future<BillingStatus> status() async => const BillingStatus(enabled: false);

  @override
  Future<OrderStart> createOrder({required String plan, String? reportType}) async => throw _off;

  @override
  Future<BillingOrder> verify(String orderId, CheckoutCompleted payment) async => throw _off;

  @override
  Future<void> cancelOrder(String orderId) async {}

  @override
  Future<BillingOrder> order(String orderId) async => throw const NotFound();

  @override
  Future<List<BillingOrder>> orders() async => const [];

  @override
  Future<List<LedgerEntry>> ledger() async => const [];

  @override
  Future<OwnKeyCheck> saveOwnKey(String apiKey) async => throw _off;

  @override
  Future<OwnKeyCheck> checkOwnKey() async => throw _off;

  @override
  Future<void> removeOwnKey() async {}
}
