/// Every way a backend call can fail, mapped to what the app should show
/// (SPEC-week1 §4: 401 sign in again · 403 verification pending · 404 start
/// again · 422 identifiers · 429 daily limit).
sealed class ApiException implements Exception {
  const ApiException();
}

/// 401: bad or expired sign-in.
final class Unauthorized extends ApiException {
  const Unauthorized();
}

/// 403: registration not verified yet, or consent missing.
final class NotVerified extends ApiException {
  const NotVerified();
}

/// 404: conversation or reply no longer available.
final class NotFound extends ApiException {
  const NotFound();
}

/// 422 identifiers_detected: the server's cleaner found something the phone missed.
final class IdentifiersDetected extends ApiException {
  const IdentifiersDetected(this.types);

  /// Types only, e.g. ["PHONE"]; the server never returns the values.
  final List<String> types;
}

/// 429: daily consult limit reached.
final class DailyLimitReached extends ApiException {
  const DailyLimitReached();
}

/// 409: the request does not fit where things are, e.g. the previous step of a
/// guided consultation is still being processed, or more information is needed.
final class Conflict extends ApiException {
  const Conflict([this.detail]);

  final String? detail;
}

/// 402 payment_required: pricing is on and there is no credit for this report (or, for [plan]
/// "byok", the own-key access fee is not paid). Nothing was generated.
final class PaymentRequired extends ApiException {
  const PaymentRequired({required this.message, this.reportType, this.plan, this.price, this.currency = 'INR'});

  final String message;

  /// guided · direct (null for the own-key fee).
  final String? reportType;

  /// "byok" when the own-key access fee is due; otherwise null.
  final String? plan;

  /// The per-report price in paise, from the server's pricing, or null if not sold singly.
  final int? price;
  final String currency;
}

/// 424 byok_failed: the clinician's own Anthropic key could not be used. The platform key is never
/// used instead; [code] says why (invalid_key, no_access, rate_limited, insufficient_balance,
/// provider_error, not_configured).
final class OwnKeyFailed extends ApiException {
  const OwnKeyFailed({required this.code, required this.message, this.retry = false});

  final String code;
  final String message;

  /// Trying again later may work (rate limit, Anthropic outage, low balance topped up).
  final bool retry;
}

/// A plan, payment or own-key request the server refused with a reason to show as is
/// (e.g. not_purchasable, payments_unavailable, invalid_signature, byok_invalid).
final class BillingRefused extends ApiException {
  const BillingRefused({required this.code, required this.message, this.status});

  final String code;
  final String message;
  final int? status;
}

/// No connection, or the server took longer than the timeout.
final class NetworkProblem extends ApiException {
  const NetworkProblem({this.timedOut = false});

  final bool timedOut;
}

/// Anything else (5xx, unexpected 4xx, malformed response).
final class ServerProblem extends ApiException {
  const ServerProblem(this.statusCode);

  final int? statusCode;
}

/// Plain-language names for the cleaner's tag types.
String describeIdentifierType(String type) => switch (type) {
  'PHONE' => 'Phone number',
  'EMAIL' => 'Email address',
  'URL' => 'Web link',
  'HANDLE' => 'Social media handle',
  'ID' => 'ID number',
  'DOB' => 'Date of birth',
  'ADDRESS' => 'Address',
  'PINCODE' => 'PIN code',
  'NAME' => 'Name',
  'ORG' => 'Workplace or school',
  'POSSIBLE_NAME' => 'Possible name',
  _ => 'Identifier',
};
