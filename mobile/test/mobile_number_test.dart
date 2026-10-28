// The mobile number: the country code picker, the number written the country's way, and the value sent
// to the server (it matches normalize_mobile in app/main.py, which checks it again).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/content/countries.dart';
import 'package:your_counselor/core/mobile_number.dart';
import 'package:your_counselor/core/widgets/mobile_number_field.dart';

Country _c(String iso) => kCountries.firstWhere((c) => c.iso == iso);

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

  test('each country writes its numbers its own way', () {
    expect(formatNational('9876543210', kIndia), '98765 43210');
    expect(formatNational('98765', kIndia), '98765');
    expect(formatNational('4155550132', _c('US')), '(415) 555-0132');
    expect(formatNational('41555', _c('US')), '(415) 55');
    expect(formatNational('7911123456', _c('GB')), '791 112 3456');
  });

  test('the value joins the country code and drops a leading 0 or a repeated code', () {
    expect(mobileValue(kIndia, '98765 43210'), '+919876543210');
    expect(mobileValue(kIndia, '098765 43210'), '+919876543210');
    expect(mobileValue(kIndia, '91 98765 43210'), '+919876543210');
    expect(mobileValue(kIndia, '91234 56789'), '+919123456789', reason: 'a number that starts with 91 is kept');
    expect(mobileValue(_c('GB'), '07911 123456'), '+447911123456');
    expect(mobileValue(_c('US'), '(415) 555-0132'), '+14155550132');
    expect(mobileValue(kIndia, '12345'), isNull);
    expect(mobileValue(_c('GB'), '79'), isNull);
  });

  test('a saved number is split back into its country', () {
    expect(splitMobile('+919876543210')?.country.iso, 'IN');
    expect(splitMobile('+447911123456')?.national, '7911123456');
    expect(splitMobile('+14155550132')?.country.iso, 'US', reason: '+1 shared: the United States');
    expect(splitMobile('+971501234567')?.country.iso, 'AE');
    expect(splitMobile(null), isNull);
  });

  group('the field', () {
    Future<List<MobileInput>> pump(WidgetTester tester, {String? initial}) async {
      final seen = <MobileInput>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: MobileNumberField(initial: initial, onChanged: seen.add, fieldKey: const ValueKey('m')),
            ),
          ),
        ),
      );
      return seen;
    }

    String text(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('m'))).controller!.text;

    testWidgets('India by default; the number is spaced as it is typed', (tester) async {
      final seen = await pump(tester);
      expect(find.text('+91'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('m')), '9876543210');
      await tester.pump();
      expect(text(tester), '98765 43210');
      expect(seen.last, (value: '+919876543210', typed: true));
    });

    testWidgets('another country is picked from a searchable list', (tester) async {
      final seen = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('country-code')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('country-search')), 'united k');
      await tester.pumpAndSettle();
      await tester.tap(find.text('United Kingdom'));
      await tester.pumpAndSettle();
      expect(find.text('+44'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('m')), '07911123456');
      await tester.pump();
      expect(seen.last.value, '+447911123456');
    });

    testWidgets('a number pasted with + picks its country', (tester) async {
      final seen = await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('m')), '+1 415 555 0132');
      await tester.pump();
      expect(find.text('+1'), findsOneWidget);
      expect(text(tester), '(415) 555-0132');
      expect(seen.last.value, '+14155550132');
    });

    testWidgets('a wrong number says what is wanted, for the chosen country', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('m')), '12345');
      await tester.pump();
      expect(find.text('A 10-digit mobile number, like 98765 43210'), findsOneWidget);
    });

    testWidgets('a saved number opens with its country', (tester) async {
      await pump(tester, initial: '+971501234567');
      expect(find.text('+971'), findsOneWidget);
      expect(text(tester), '501 234 567');
    });
  });
}
