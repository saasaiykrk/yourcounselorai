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
