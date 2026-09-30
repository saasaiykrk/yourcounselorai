import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config.dart';

/// Email one-time-code sign-in. The only thing the app asks Supabase for is a
/// session; every other request goes through our backend.
abstract interface class AuthService {
  bool get isSignedIn;

  /// Emails a 6-digit code.
  Future<void> requestCode(String email);

  /// Signs in with the emailed code. Throws [AuthFailure] if it is wrong or expired.
  Future<void> verifyCode(String email, String code);

  /// Bearer token for the backend, or null when signed out.
  Future<String?> accessToken();

  Future<void> signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Preview and dev builds: any email and any 6 digits sign in; the backend
/// (in `DEV_MODE=1`) accepts the dev token. Never used in a live build.
class DevAuthService implements AuthService {
  DevAuthService(this._token);

  final String _token;
  bool _signedIn = false;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Future<void> requestCode(String email) async {}

  @override
  Future<void> verifyCode(String email, String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) throw const AuthFailure('Enter the 6-digit code.');
    _signedIn = true;
  }

  @override
  Future<String?> accessToken() async => _signedIn ? _token : null;

  @override
  Future<void> signOut() async => _signedIn = false;
}

/// Live builds: Supabase Auth email OTP. The Supabase project must use
/// asymmetric JWT signing keys, which the backend verifies via JWKS.
class SupabaseAuthService implements AuthService {
  sb.GoTrueClient get _auth => sb.Supabase.instance.client.auth;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  Future<void> requestCode(String email) async {
    try {
      await _auth.signInWithOtp(email: email, shouldCreateUser: true);
    } on sb.AuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> verifyCode(String email, String code) async {
    try {
      await _auth.verifyOTP(email: email, token: code, type: sb.OtpType.email);
    } on sb.AuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<String?> accessToken() async {
    final session = _auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      try {
        return (await _auth.refreshSession()).session?.accessToken;
      } on sb.AuthException {
        return null;
      }
    }
    return session.accessToken;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static String _friendly(sb.AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) {
      return 'That code is wrong or has expired. Try again or resend it.';
    }
    if (m.contains('rate') || e.statusCode == '429') {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    return 'Could not sign in. Check your connection and try again.';
  }
}

/// Keeps the Supabase session in the phone's encrypted storage
/// (Keychain on iPhone, Keystore-backed on Android), never in plain files.
class SecureSessionStorage extends sb.LocalStorage {
  const SecureSessionStorage();

  static const _key = 'yc_supabase_session';
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: _key, value: persistSessionString);
}

Future<void> initAuthBackend() async {
  if (AppConfig.mode != AppMode.live) return;
  await sb.Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const sb.FlutterAuthClientOptions(localStorage: SecureSessionStorage(), detectSessionInUri: false),
  );
}
