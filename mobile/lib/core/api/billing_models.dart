/// Plans, credits, payments and the clinician's own Anthropic key, as the backend sends them.
/// Every price comes from the server (the admin's pricing); the app never decides one.
/// Money is in minor units (paise for INR).
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

/// "₹1,999" / "₹199.50" (Indian digit grouping), or "$11.99" / "$1,199" for US dollars (outside India).
String formatMoney(int paise, [String currency = 'INR']) {
  if (currency == 'USD') {
    final dollars = paise ~/ 100, cents = paise % 100;
    final grouped = '$dollars'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return cents == 0 ? '\$$grouped' : '\$$grouped.${cents.toString().padLeft(2, '0')}';
  }
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
  'guided' => 'AI-Guided report',
  'direct' => 'Quick consult report',
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
    this.badge = '',
    this.periods = const [],
    this.priceMonth = 0,
    this.priceYear = 0,
    this.wasMonth = 0,
    this.wasYear = 0,
    this.includes = const {},
    this.table = const {},
    this.trialDays = 0,
    this.guidedPerMonth = 0,
    this.extraPrice = 0,
    this.instructions = '',
  });

  factory PlanOffer.fromJson(Map<String, dynamic> j) => PlanOffer(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? 'tier',
    name: j['name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    features: _strings(j['features']),
    prices: {for (final e in ((j['prices'] as Map?) ?? const {}).entries) '${e.key}': _int(e.value)},
    badge: j['badge'] as String? ?? '',
    periods: _strings(j['periods']),
    priceMonth: _int(j['price_month']),
    priceYear: _int(j['price_year']),
    wasMonth: _int(j['was_month']),
    wasYear: _int(j['was_year']),
    includes: _strings(j['includes']).toSet(),
    table: {for (final e in ((j['table'] as Map?) ?? const {}).entries) '${e.key}': e.value as String?},
    trialDays: _int(j['trial_days']),
    guidedPerMonth: _int(j['guided_per_month']),
    extraPrice: _int(j['extra_price']),
    instructions: j['instructions'] as String? ?? '',
  );

  /// per_report · learn · practice · byok_scale · scale
  final String id;

  /// per_report · tier (a plan bought by the month or the year)
  final String kind;
  final String name;
  final String description;
  final List<String> features;

  /// per_report: {"guided": paise, "direct": paise}.
  final Map<String, int> prices;

  /// A plan: "Launch offer" or empty; month · year on sale; prices; struck-through old prices (0 = none).
  final String badge;
  final List<String> periods;
  final int priceMonth;
  final int priceYear;
  final int wasMonth;
  final int wasYear;

  /// What the plan unlocks: library · pdf · booking · appointments · guided_own_key · guided_included.
  final Set<String> includes;

  /// The comparison table: row key → "Included" / other text, or null for "Not included".
  final Map<String, String?> table;

  /// Learn: free days for new clinicians. Scale: AI-Guided reports a month and the extra report price.
  final int trialDays;
  final int guidedPerMonth;
  final int extraPrice;

  /// BYOK Scale: how to create a key.
  final String instructions;

  bool get isTier => kind == 'tier';

  int price(String period) => period == 'year' ? priceYear : priceMonth;

  int was(String period) => period == 'year' ? wasYear : wasMonth;
}

/// One row of the plans table, in order (key matches [PlanOffer.table]).
class PlanRow {
  const PlanRow(this.key, this.label);

  final String key;
  final String label;
}

class BillingPlans {
  const BillingPlans({
    required this.enabled,
    this.currency = 'INR',
    this.plans = const [],
    this.rows = const [],
    this.paymentsAvailable = false,
  });

  factory BillingPlans.fromJson(Map<String, dynamic> j) => BillingPlans(
    enabled: j['enabled'] == true,
    currency: j['currency'] as String? ?? 'INR',
    plans: [for (final p in (j['plans'] as List? ?? const [])) PlanOffer.fromJson(p as Map<String, dynamic>)],
    rows: [for (final r in (j['rows'] as List? ?? const [])) PlanRow('${(r as Map)['key']}', '${r['label']}')],
    paymentsAvailable: j['payments_available'] == true,
  );

  /// Pricing is switched on; while off, everything is free and unlocked.
  final bool enabled;
  final String currency;
  final List<PlanOffer> plans;
  final List<PlanRow> rows;

  /// The server can take payments now.
  final bool paymentsAvailable;

  List<PlanOffer> get tiers => plans.where((p) => p.isTier).toList();

  PlanOffer? get perReport => plans.where((p) => p.kind == 'per_report').firstOrNull;
}

/// The plan the clinician is on now (the highest one running).
class CurrentPlan {
  const CurrentPlan({required this.id, required this.name, this.period, this.trial = false, this.expiresAt});

  static CurrentPlan? fromJson(Object? j) => j is Map<String, dynamic>
      ? CurrentPlan(
          id: j['id'] as String,
          name: j['name'] as String? ?? '',
          period: j['period'] as String?,
          trial: j['trial'] == true,
          expiresAt: _date(j['expires_at']),
        )
      : null;

  final String id;
  final String name;

  /// month · year · trial · admin
  final String? period;
  final bool trial;
  final DateTime? expiresAt;
}

/// On Scale: this month's AI-Guided reports.
class ScaleStatus {
  const ScaleStatus({this.guidedLeft = 0, this.perMonth = 0, this.extraPrice = 0, this.resetsAt});

  static ScaleStatus? fromJson(Object? j) => j is Map<String, dynamic>
      ? ScaleStatus(
          guidedLeft: _int(j['guided_left']),
          perMonth: _int(j['per_month']),
          extraPrice: _int(j['extra_price']),
          resetsAt: _date(j['resets_at']),
        )
      : null;

  final int guidedLeft;
  final int perMonth;
  final int extraPrice;
  final DateTime? resetsAt;
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
    this.period,
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
    period: j['period'] as String?,
  );

  final String id;
  final String plan;

  /// A plan: month · year · trial · admin.
  final String? period;

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
    this.included = false,
    this.connected = false,
    this.status,
    this.last4,
    this.lastError,
    this.instructions = '',
  });

  factory OwnKeyStatus.fromJson(Map<String, dynamic>? j) => j == null
      ? const OwnKeyStatus()
      : OwnKeyStatus(
          available: j['available'] == true,
          included: j['included'] == true,
          connected: j['connected'] == true,
          status: j['status'] as String?,
          last4: j['last4'] as String?,
          lastError: j['last_error'] as String?,
          instructions: j['instructions'] as String? ?? '',
        );

  /// The admin sells BYOK Scale.
  final bool available;

  /// The clinician is on BYOK Scale: AI-Guided reports with their own key.
  final bool included;
  final bool connected;

  /// valid · invalid
  final String? status;

  /// The only part of the key the app ever sees.
  final String? last4;
  final String? lastError;
  final String instructions;

  bool get usable => available && included && connected && status == 'valid';
}

class BillingNotice {
  const BillingNotice(this.kind, this.message);

  factory BillingNotice.fromJson(Map<String, dynamic> j) =>
      BillingNotice(j['kind'] as String? ?? '', j['message'] as String? ?? '');

  /// expiring · no_plan · exhausted · pending_payment · byok_invalid
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
    this.plan,
    this.features = const {},
    this.scale,
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
      plan: CurrentPlan.fromJson(j['plan']),
      features: _strings(j['features']).toSet(),
      scale: ScaleStatus.fromJson(j['scale']),
    );
  }

  /// Pricing is on. While off, reports are free and none of this applies.
  final bool enabled;
  final String currency;

  /// Single-report prices, if sold singly.
  final Map<String, int>? prices;

  /// Credits usable for either report type (admin grants).
  final int anyCredits;

  /// Everything usable for a guided / direct report (includes [anyCredits]).
  final int guidedCredits;
  final int directCredits;
  final List<Entitlement> subscriptions;
  final List<Entitlement> perReport;
  final OwnKeyStatus ownKey;
  final List<BillingNotice> notices;

  /// The plan the clinician is on now, or null (none, or pricing off).
  final CurrentPlan? plan;

  /// What the plans running now unlock (everything while pricing is off).
  final Set<String> features;

  /// On Scale: this month's AI-Guided reports.
  final ScaleStatus? scale;
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
    this.period,
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
    period: j['period'] as String?,
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

  /// A plan: month · year.
  final String? period;
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
