// Education tab: one card per page (the page's own title), filters, opening a page inside the app,
// fresh links on every visit, errors, links inside a page, and the 320px layout.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/billing/payment_gateway.dart';
import 'package:your_counselor/core/education/education_repository.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/features/education/education_reader_screen.dart';
import 'package:your_counselor/features/education/print_unlock.dart';
import 'package:your_counselor/features/education/education_screen.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

import 'billing_test.dart' show FakeBilling, FakeGateway, anOrder, paid;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final Object body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Repo implements EducationRepository {
  _Repo(this.result, {this.canPrint = true, this.offer});

  Object result;
  bool canPrint;
  PrintOffer? offer;
  int calls = 0;

  @override
  Future<EducationCatalog> pages() async {
    calls++;
    final r = result;
    if (r is Exception) throw r;
    return EducationCatalog(pages: r as List<EducationPage>, canPrint: canPrint, printOffer: offer);
  }
}

const _pages = [
  EducationPage(
    slug: 'cbt',
    title: 'Cognitive Behavioural Therapy (CBT)',
    kind: 'module',
    summary: 'A structured, time-limited approach.',
    url: 'https://api.test/learn/cbt?t=abc',
    canPrint: true,
    section: 'therapies',
  ),
  EducationPage(
    slug: 'therapy-comparison-chart',
    title: 'Therapy Comparison Chart',
    kind: 'reference',
    url: 'https://api.test/learn/therapy-comparison-chart?t=abc',
    canPrint: true,
    section: 'practice',
  ),
  EducationPage(
    slug: 'case-history',
    title: 'Case History and MSE Practice Handout',
    kind: 'handout',
    url: 'https://api.test/learn/file/x.pdf?t=abc',
    canPrint: true,
  ),
];

/// The same pages for a clinician without a subscription: CBT bought as a single print.
final _locked = [
  for (final p in _pages)
    EducationPage(
      slug: p.slug,
      title: p.title,
      kind: p.kind,
      url: p.url,
      summary: p.summary,
      section: p.section,
      canPrint: p.slug == 'cbt',
      printUntil: p.slug == 'cbt' ? DateTime.now().add(const Duration(hours: 5)) : null,
    ),
];

const _offer = PrintOffer(price: 4900, hours: 24);

/// Each page opened: (url, canPrint). The real reader is a web view, which widget tests can't run.
Future<List<(Uri, bool)>> _pump(WidgetTester tester, _Repo repo, {double width = 390}) async {
  final opened = <(Uri, bool)>[];
  tester.view.physicalSize = Size(width, 800) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        educationRepositoryProvider.overrideWithValue(repo),
        educationPageViewProvider.overrideWithValue((page, offer) {
          opened.add((Uri.parse(page.url), page.canPrint));
          return Scaffold(appBar: AppBar(title: Text('Reading ${page.title}')));
        }),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: '/consult')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Knowledge'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  test('the API list parses into cards with signed links', () async {
    final adapter = _Adapter({
      'pages': [
        {'slug': 'cbt', 'title': 'Cognitive Behavioural Therapy (CBT)', 'summary': 'S', 'kind': 'module', 'url': 'u1'},
        {'slug': 'pdf', 'title': 'Handout', 'kind': 'handout', 'url': 'u2'},
      ],
      'link_hours': 12,
      'can_print': true,
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    final api = ApiClient(
      baseUrl: 'https://api.test',
      token: () async => 'tok',
      timeout: const Duration(seconds: 5),
      dio: dio,
    );
    final catalog = await api.education();
    expect(catalog.printOffer, isNull);
    final pages = catalog.pages;
    expect(adapter.requests.single.path, '/v1/education');
    expect(catalog.canPrint, isTrue);
    expect(EducationCatalog.fromJson(const {'pages': []}).canPrint, isFalse, reason: 'missing means no');
    expect(pages.map((p) => (p.title, p.kindLabel, p.url)), [
      ('Cognitive Behavioural Therapy (CBT)', 'Module', 'u1'),
      ('Handout', 'Handout · PDF', 'u2'),
    ]);
  });

  testWidgets('Education is in the bottom bar and shows one card per page with its title', (tester) async {
    await _pump(tester, _Repo(List.of(_pages)));
    expect(find.text('Cognitive Behavioural Therapy (CBT)'), findsOneWidget);
    expect(find.text('Therapy Comparison Chart'), findsOneWidget);
    expect(find.text('Case History and MSE Practice Handout'), findsOneWidget);
    expect(find.textContaining('Print / Save as PDF'), findsOneWidget);
  });

  testWidgets('without a subscription: free to read, the single print offered, bought pages marked', (tester) async {
    final opened = await _pump(tester, _Repo(_locked, canPrint: false, offer: _offer));
    expect(find.textContaining('come with a subscription, or buy a single page for ₹49 (24 hours)'), findsOneWidget);
    expect(find.textContaining('Print / Save as PDF button'), findsNothing);
    expect(find.text('See plans'), findsOneWidget);
    expect(find.textContaining('Print until'), findsOneWidget, reason: 'only the page bought (CBT)');
    await tester.tap(find.text('Therapy Comparison Chart'));
    await tester.pumpAndSettle();
    expect(opened.single.$2, isFalse, reason: 'the pages stay free to read; this one is not unlocked');
  });

  testWidgets('no single print on sale: only the subscription is mentioned', (tester) async {
    await _pump(tester, _Repo(_locked, canPrint: false));
    expect(find.textContaining('Printing and saving as PDF come with a subscription.'), findsOneWidget);
    expect(find.textContaining('single page'), findsNothing);
  });

  testWidgets('a card opens the page inside the app; back returns to fresh links', (tester) async {
    final repo = _Repo(List.of(_pages));
    final opened = await _pump(tester, repo);
    await tester.tap(find.text('Therapy Comparison Chart'));
    await tester.pumpAndSettle();
    expect(opened, [(Uri.parse('https://api.test/learn/therapy-comparison-chart?t=abc'), true)]);
    expect(find.text('Reading Therapy Comparison Chart'), findsOneWidget);
    expect(find.text('Account'), findsNothing, reason: 'full screen, above the bottom bar');
    final before = repo.calls;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Therapy Comparison Chart'), findsOneWidget);
    expect(repo.calls, greaterThan(before));
  });

  test('links inside a page: other pages stay in the app, phone numbers and websites leave, the rest is ignored', () {
    final page = Uri.parse('https://api.test/learn/cbt?t=abc');
    expect(linkTarget(page, Uri.parse('https://api.test/learn/dbt?t=abc')), LinkTarget.stay);
    expect(linkTarget(page, Uri.parse('https://api.test/learn/cbt?t=abc#techniques')), LinkTarget.stay);
    expect(linkTarget(page, Uri.parse('tel:14416')), LinkTarget.phone);
    expect(linkTarget(page, Uri.parse('mailto:help@example.org')), LinkTarget.phone);
    expect(linkTarget(page, Uri.parse('https://www.who.int/')), LinkTarget.phone);
    expect(linkTarget(page, Uri.parse('https://api.test/v1/me')), LinkTarget.phone, reason: 'not a page: never inside');
    expect(linkTarget(page, Uri.parse('intent://x#Intent;end')), LinkTarget.block);
    expect(linkTarget(page, Uri.parse('file:///etc/hosts')), LinkTarget.block);
  });

  test('what may be printed is read from the server', () {
    final c = EducationCatalog.fromJson({
      'pages': [
        {
          'slug': 'cbt',
          'title': 'CBT',
          'kind': 'module',
          'url': 'u',
          'can_print': true,
          'print_until': '2030-01-01T10:00:00+00:00',
        },
        {'slug': 'dbt', 'title': 'DBT', 'kind': 'module', 'url': 'u2', 'can_print': false, 'print_until': null},
      ],
      'can_print': false,
      'print_offer': {'price': 4900, 'currency': 'INR', 'hours': 24, 'name': 'Print one page'},
    });
    expect(c.canPrint, isFalse);
    expect((c.printOffer!.price, c.printOffer!.hours), (4900, 24));
    expect(c.pages.map((p) => (p.canPrint, p.printUntil?.toUtc())), [
      (true, DateTime.utc(2030, 1, 1, 10)),
      (false, null),
    ]);
    expect(EducationCatalog.fromJson(const {'pages': [], 'print_offer': null}).printOffer, isNull);
  });

  test('the page on screen is read from its address', () {
    expect(pageSlug(Uri.parse('https://api.test/learn/dbt?t=x')), 'dbt');
    expect(pageSlug(Uri.parse('https://api.test/learn/file/x.pdf?t=x')), isNull);
    expect(pageSlug(Uri.parse('https://api.test/v1/me')), isNull);
    expect(pageSlug(null), isNull);
  });

  group('buying a single print', () {
    const page = EducationPage(slug: 'cbt', title: 'CBT', kind: 'module', url: 'https://api.test/learn/cbt?t=x');

    Future<bool?> run(
      WidgetTester tester,
      FakeBilling billing,
      FakeGateway gateway, {
      PrintOffer? offer = _offer,
    }) async {
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            billingRepositoryProvider.overrideWithValue(billing),
            paymentGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async => result = await unlockPrinting(context, ref, page, offer),
                    child: const Text('locked button'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('locked button'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('the sheet offers this page for the admin price; paying unlocks it', (tester) async {
      final billing = FakeBilling(verifyResult: anOrder('paid'));
      final gateway = FakeGateway(paid);
      await run(tester, billing, gateway);
      expect(find.text('Included with every subscription, for every page.'), findsOneWidget);
      expect(find.text('Print or save it as a PDF as often as you need for 24 hours.'), findsOneWidget);
      await tester.tap(find.text('Buy for ₹49'));
      await tester.pumpAndSettle();
      expect(billing.createdPlan, 'print::cbt', reason: 'the page is named; the server sets the price');
      expect(gateway.opened, 1);
      expect(find.text('Payment received. You can print or save this page for 24 hours.'), findsOneWidget);
    });

    testWidgets('a cancelled payment unlocks nothing', (tester) async {
      final billing = FakeBilling();
      await run(tester, billing, FakeGateway(const CheckoutCancelled()));
      await tester.tap(find.text('Buy for ₹49'));
      await tester.pumpAndSettle();
      expect(billing.cancelled, ['o1']);
      expect(find.text('Payment cancelled. Nothing was charged.'), findsOneWidget);
    });

    testWidgets('nothing on sale: only the subscriptions', (tester) async {
      final billing = FakeBilling();
      await run(tester, billing, FakeGateway(paid), offer: null);
      expect(find.textContaining('Buy for'), findsNothing);
      expect(find.text('See subscriptions'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();
      expect(billing.createdPlan, isNull);
    });
  });

  test('page titles lose the brand prefix', () {
    expect(cleanTitle('YourCounselor | Therapy Comparison Chart'), 'Therapy Comparison Chart');
    expect(cleanTitle('The Core Eight | YourCounselor'), 'The Core Eight');
    expect(cleanTitle('Cognitive Behavioural Therapy (CBT)'), 'Cognitive Behavioural Therapy (CBT)');
  });

  testWidgets('the Knowledge tabs show one section at a time', (tester) async {
    await _pump(tester, _Repo(List.of(_pages)));
    expect(find.text('Knowledge'), findsWidgets, reason: 'screen title and bottom tab');
    for (final t in ['All', 'Basics', 'Therapies', 'Practice', 'Others', 'Handouts']) {
      expect(find.widgetWithText(Tab, t), findsOneWidget, reason: t);
    }
    await tester.tap(find.widgetWithText(Tab, 'Therapies'));
    await tester.pumpAndSettle();
    expect(find.text('Cognitive Behavioural Therapy (CBT)'), findsOneWidget);
    expect(find.text('Therapy Comparison Chart'), findsNothing);
    await tester.tap(find.widgetWithText(Tab, 'Practice'));
    await tester.pumpAndSettle();
    expect(find.text('Therapy Comparison Chart'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Others'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet.'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(Tab, 'Handouts'));
    await tester.tap(find.widgetWithText(Tab, 'Handouts'));
    await tester.pumpAndSettle();
    expect(find.text('Case History and MSE Practice Handout'), findsOneWidget, reason: 'a PDF goes to Handouts');
    expect(find.text('Cognitive Behavioural Therapy (CBT)'), findsNothing);
  });

  test('a page without a section from the server: PDFs to Handouts, the rest to Others', () {
    expect(EducationPage.fromJson(const {'slug': 'x', 'kind': 'handout'}).section, 'handouts');
    expect(EducationPage.fromJson(const {'slug': 'y', 'kind': 'module'}).section, 'others');
    expect(EducationPage.fromJson(const {'slug': 'z', 'kind': 'module', 'section': 'basics'}).section, 'basics');
  });

  testWidgets('no connection: a message and Try again', (tester) async {
    final repo = _Repo(const NetworkProblem());
    await _pump(tester, repo);
    expect(find.text("Couldn't reach YourCounselor. Check your connection."), findsOneWidget);
    repo.result = List.of(_pages);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Therapy Comparison Chart'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('fits on a ${width.toInt()}px phone, five tabs included', (tester) async {
      await _pump(tester, _Repo(List.of(_pages)), width: width);
      expect(tester.takeException(), isNull);
      for (final tab in ['Consult', 'History', 'Calendar', 'Knowledge', 'Account']) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
    });
  }
}
