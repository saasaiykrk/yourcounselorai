// Supabase sign-in errors shown in plain language, keeping only Supabase's
// error code (never the email or the typed code) for unknown cases.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:your_counselor/core/auth/auth_service.dart';

String send(sb.AuthException e) => friendlyAuthError(e, sendingCode: true);
String verify(sb.AuthException e) => friendlyAuthError(e, sendingCode: false);

void main() {
  test('rate limit', () {
    expect(send(const sb.AuthException('Email rate limit exceeded', statusCode: '429', code: 'over_email_send_rate_limit')),
        contains('Too many code requests'));
  });

  test('a bad email address is not reported as a bad code', () {
    final msg = send(const sb.AuthException('Email address "x" is invalid', statusCode: '400', code: 'email_address_invalid'));
    expect(msg, contains('email address'));
    expect(msg, isNot(contains('code is wrong')));
  });

  test('address not allowed by the default Supabase mailer', () {
    expect(send(const sb.AuthException('Email address not authorized', statusCode: '400', code: 'email_address_not_authorized')),
        contains("can't be sent to this address"));
  });

  test('sign-ups or email OTP switched off', () {
    expect(send(const sb.AuthException('Signups not allowed for otp', statusCode: '422', code: 'otp_disabled')),
        contains('switched off'));
  });

  test('mail server failure', () {
    expect(send(const sb.AuthException('Error sending magic link email', statusCode: '500', code: 'unexpected_failure')),
        contains("couldn't send the sign-in email"));
  });

  test('no connection', () {
    expect(send(sb.AuthRetryableFetchException(message: 'SocketException')), contains("Couldn't reach"));
  });

  test('wrong or expired code', () {
    expect(verify(const sb.AuthException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired')),
        contains('wrong or has expired'));
  });

  test('unknown errors keep only the Supabase code, never user input', () {
    final msg = send(const sb.AuthException('someone@example.com 123456 boom', statusCode: '400', code: 'weird_case'));
    expect(msg, contains('(weird_case)'));
    expect(msg, isNot(contains('example.com')));
    expect(msg, isNot(contains('123456')));
  });
}
