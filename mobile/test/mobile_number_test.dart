// The mobile number check matches the server's (normalize_mobile in app/main.py).
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/mobile_number.dart';

void main() {
  test('numbers are stored in one form', () {
    const cases = {
      '98765 43210': '+919876543210',
      '+91 98765-43210': '+919876543210',
      '09876543210': '+919876543210',
      '919876543210': '+919876543210',
      '+44 7911 123456': '+447911123456',
      '0044 7911 123456': '+447911123456',
      '+1 (415) 555-0132': '+14155550132',
      '+971 50 123 4567': '+971501234567',
      '+61 412 345 678': '+61412345678',
    };
    cases.forEach((raw, want) => expect(normalizeMobile(raw), want, reason: raw));
  });

  test('wrong numbers are refused', () {
    for (final bad in [
      '',
      '12345',
      '5876543210',
      '+91 12345 67890',
      '98765 4321a',
      '+1',
      'call me',
      '+91 98765 432100',
    ]) {
      expect(normalizeMobile(bad), isNull, reason: bad);
    }
  });
}
