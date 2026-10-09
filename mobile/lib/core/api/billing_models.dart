/// Plans, credits, payments and the clinician's own Anthropic key, as the backend sends them.
/// Every price comes from the server (the admin's pricing); the app never decides one.
/// Money is in minor units (paise for INR).
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

/// "₹1,999" / "₹199.50" (Indian digit grouping).
String formatMoney(int paise, [String currency = 'INR']) {
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  final digits = '$rupees';
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$last3';
  }
  return rest == 0 ? '$symbol$grouped' : '$symbol$grouped.${rest.toString().padLeft(2, '0')}';
}

String reportTypeLabel(String? t) => switch (t) {
  'guided' => 'Guided report',
  'direct' => 'Direct report',
  _ => 'Any report',
};

/// One plan on sale, as configured by the admin.
class PlanOffer {
  const PlanOffer({
    required this.id,
    required this.kind,
    required this.name,
    this.description = '',
    this.features = const [],
    this.prices = const {},
    this.price,
    this.reports,
    this.durationDays,
    this.fee,
    this.feeDays,
    this.instructions = '',
    this.consumesCredits = false,
    this.reportTypes = const [],
  });

  factory PlanOffer.fromJson(Map<String, dynamic> j) => PlanOffer(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? 'subscription',
    name: j['name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    features: _strings(j['features']),
    prices: {for (final e in ((j['prices'] as Map?) ?? const {}).entries) '${e.key}': _int(e.value)},
    price: (j['price'] as num?)?.toInt(),
    reports: (j['reports'] as num?)?.toInt(),
    durationDays: (j['duration_days'] as num?)?.toInt(),
    fee: (j['fee'] as num?)?.toInt(),
    feeDays: (j['fee_days'] as num?)?.toInt(),
    instructions: j['instructions'] as String? ?? '',
    consumesCredits: j['consumes_credits'] == true,
    reportTypes: _strings(j['report_types']),
  );

  /// per_report · sub_30 · sub_50 · byok
  final String id;

  /// per_report · subscription · byok
  final String kind;
  final String name;
  final String description;
  final List<String> features;

  /// per_report: {"guided": paise, "direct": paise}.
  final Map<String, int> prices;

  /// Subscriptions: price, reports included, days valid.
  final int? price;
  final int? reports;
  final int? durationDays;

  /// Own key: platform access fee (0 = free) and the days it covers.
  final int? fee;
  final int? feeDays;
  final String instructions;
  final bool consumesCredits;
  final List<String> reportTypes;
}

class BillingPlans {
  const BillingPlans({
    required this.enabled,
    this.currency = 'INR',
    this.plans = const [],
    this.paymentsAvailable = false,
  });

  factory BillingPlans.fromJson(Map<String, dynamic> j) => BillingPlans(
    enabled: j['enabled'] == true,
    currency: j['currency'] as String? ?? 'INR',
    plans: [for (final p in (j['plans'] as List? ?? const [])) PlanOffer.fromJson(p as Map<String, dynamic>)],
    paymentsAvailable: j['payments_available'] == true,
  );

  /// Pricing is switched on; while off, every report is free.
  final bool enabled;
  final String currency;
  final List<PlanOffer> plans;

  /// The server can take payments now.
  final bool paymentsAvailable;
}

/// A plan or credit the clinician holds.
class Entitlement {
  const Entitlement({
    required this.id,
    required this.plan,
    required this.state,
    this.reportType,
    this.creditsTotal = 0,
    this.creditsUsed = 0,
    this.remaining = 0,
    this.startsAt,
    this.expiresAt,
  });

  factory Entitlement.fromJson(Map<String, dynamic> j) => Entitlement(
    id: '${j['id']}',
    plan: j['plan'] as String,
    state: j['state'] as String? ?? 'active',
    reportType: j['report_type'] as String?,
    creditsTotal: _int(j['credits_total']),
    creditsUsed: _int(j['credits_used']),
    remaining: _int(j['remaining']),
    startsAt: _date(j['starts_at']),
    expiresAt: _date(j['expires_at']),
  );

  final String id;
  final String plan;

  /// active · scheduled · exhausted · expired · cancelled
  final String state;
  final String? reportType;
  final int creditsTotal;
  final int creditsUsed;
  final int remaining;
  final DateTime? startsAt;
  final DateTime? expiresAt;
}

class OwnKeyStatus {
  const OwnKeyStatus({
    this.available = false,
    this.connected = false,
    this.status,
    this.last4,
    this.lastError,
    this.fee = 0,
    this.feePaidUntil,
    this.consumesCredits = false,
    this.reportTypes = const [],
  });

  factory OwnKeyStatus.fromJson(Map<String, dynamic>? j) => j == null
      ? const OwnKeyStatus()
      : OwnKeyStatus(
          available: j['available'] == true,
          connected: j['connected'] == true,
          status: j['status'] as String?,
          last4: j['last4'] as String?,
          lastError: j['last_error'] as String?,
          fee: _int(j['fee']),
          feePaidUntil: _date(j['fee_paid_until']),
          consumesCredits: j['consumes_credits'] == true,
          reportTypes: _strings(j['report_types']),
        );

  /// The admin offers "Use My Anthropic API Key".
  final bool available;
  final bool connected;

  /// valid · invalid
  final String? status;

  /// The only part of the key the app ever sees.
  final String? last4;
  final String? lastError;
  final int fee;
  final DateTime? feePaidUntil;
  final bool consumesCredits;
  final List<String> reportTypes;

  bool get usable => available && connected && status == 'valid';

  bool get feeDue => fee > 0 && (feePaidUntil == null || feePaidUntil!.isBefore(DateTime.now()));
}

class BillingNotice {
  const BillingNotice(this.kind, this.message);

  factory BillingNotice.fromJson(Map<String, dynamic> j) =>
      BillingNotice(j['kind'] as String? ?? '', j['message'] as String? ?? '');

  /// expiring · exhausted · pending_payment · byok_invalid
  final String kind;
  final String message;
}

/// The clinician's credits, plans, own-key status and notices.
class BillingStatus {
  const BillingStatus({
    required this.enabled,
    this.currency = 'INR',
    this.prices,
    this.anyCredits = 0,
    this.guidedCredits = 0,
    this.directCredits = 0,
    this.subscriptions = const [],
    this.perReport = const [],
    this.ownKey = const OwnKeyStatus(),
    this.notices = const [],
  });

  factory BillingStatus.fromJson(Map<String, dynamic> j) {
    final b = (j['balance'] as Map?) ?? const {};
    return BillingStatus(
      enabled: j['enabled'] == true,
      currency: j['currency'] as String? ?? 'INR',
      prices: j['prices'] is Map ? {for (final e in (j['prices'] as Map).entries) '${e.key}': _int(e.value)} : null,
      anyCredits: _int(b['any']),
      guidedCredits: _int(b['guided']),
      directCredits: _int(b['direct']),
      subscriptions: [
        for (final e in (j['subscriptions'] as List? ?? const [])) Entitlement.fromJson(e as Map<String, dynamic>),
      ],
      perReport: [
        for (final e in (j['per_report'] as List? ?? const [])) Entitlement.fromJson(e as Map<String, dynamic>),
      ],
      ownKey: OwnKeyStatus.fromJson(j['byok'] as Map<String, dynamic>?),
      notices: [for (final n in (j['notices'] as List? ?? const [])) BillingNotice.fromJson(n as Map<String, dynamic>)],
    );
  }

  /// Pricing is on. While off, reports are free and none of this applies.
  final bool enabled;
  final String currency;

  /// Single-report prices, if sold singly.
  final Map<String, int>? prices;

  /// Credits usable for either report type (subscriptions, admin grants).
  final int anyCredits;

  /// Everything usable for a guided / direct report (includes [anyCredits]).
  final int guidedCredits;
  final int directCredits;
  final List<Entitlement> subscriptions;
  final List<Entitlement> perReport;
  final OwnKeyStatus ownKey;
  final List<BillingNotice> notices;

  Entitlement? get activeSubscription =>
      subscriptions.where((e) => e.state == 'active' && e.plan != 'manual').firstOrNull;
}

/// What Razorpay's checkout needs. Holds no secret: only the public key id.
class CheckoutDetails {
  const CheckoutDetails({
    required this.key,
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.name,
    required this.description,
  });

  factory CheckoutDetails.fromJson(Map<String, dynamic> j) => CheckoutDetails(
    key: j['key'] as String,
    orderId: j['order_id'] as String,
    amount: _int(j['amount']),
    currency: j['currency'] as String? ?? 'INR',
    name: j['name'] as String? ?? 'YourCounselor',
    description: j['description'] as String? ?? '',
  );

  final String key;
  final String orderId;
  final int amount;
  final String currency;
  final String name;
  final String description;
}

class BillingOrder {
  const BillingOrder({
    required this.id,
    required this.plan,
    required this.status,
    required this.amount,
    this.currency = 'INR',
    this.reportType,
    this.failureReason,
    this.refundStatus,
    this.refundedAmount = 0,
    this.createdAt,
    this.paidAt,
  });

  factory BillingOrder.fromJson(Map<String, dynamic> j) => BillingOrder(
    id: '${j['id']}',
    plan: j['plan'] as String? ?? '',
    status: j['status'] as String? ?? 'created',
    amount: _int(j['amount']),
    currency: j['currency'] as String? ?? 'INR',
    reportType: j['report_type'] as String?,
    failureReason: j['failure_reason'] as String?,
    refundStatus: j['refund_status'] as String?,
    refundedAmount: _int(j['refunded_amount']),
    createdAt: _date(j['created_at']),
    paidAt: _date(j['paid_at']),
  );

  final String id;
  final String plan;

  /// created · pending · paid · failed · cancelled
  final String status;
  final int amount;
  final String currency;
  final String? reportType;
  final String? failureReason;
  final String? refundStatus;
  final int refundedAmount;
  final DateTime? createdAt;
  final DateTime? paidAt;

  bool get paid => status == 'paid';
}

class OrderStart {
  const OrderStart(this.order, this.checkout);

  factory OrderStart.fromJson(Map<String, dynamic> j) => OrderStart(
    BillingOrder.fromJson(j['order'] as Map<String, dynamic>),
    j['checkout'] == null ? null : CheckoutDetails.fromJson(j['checkout'] as Map<String, dynamic>),
  );

  final BillingOrder order;

  /// Null for a free plan (granted at once).
  final CheckoutDetails? checkout;
}

class LedgerEntry {
  const LedgerEntry({required this.kind, required this.amount, this.reportType, this.reason, this.createdAt});

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    kind: j['kind'] as String? ?? '',
    amount: _int(j['amount']),
    reportType: j['report_type'] as String?,
    reason: j['reason'] as String?,
    createdAt: _date(j['created_at']),
  );

  /// grant · reserve · consume · release · expire · adjust · revoke
  final String kind;
  final int amount;
  final String? reportType;
  final String? reason;
  final DateTime? createdAt;

  String get label => switch (kind) {
    'grant' => 'Credits added',
    'reserve' => 'Held while a report was written',
    'consume' => 'Used for a report',
    'release' => 'Returned (report not delivered)',
    'expire' => 'Expired',
    'adjust' => 'Adjusted by the team',
    'revoke' => 'Withdrawn (refund)',
    _ => kind,
  };
}

/// The result of saving or re-checking the clinician's own key.
class OwnKeyCheck {
  const OwnKeyCheck({required this.connected, this.status, this.last4, this.code, this.message});

  factory OwnKeyCheck.fromJson(Map<String, dynamic> j) => OwnKeyCheck(
    connected: j['connected'] == true,
    status: j['status'] as String?,
    last4: j['last4'] as String?,
    code: j['code'] as String?,
    message: j['message'] as String?,
  );

  final bool connected;
  final String? status;
  final String? last4;
  final String? code;
  final String? message;
}
