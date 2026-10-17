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
import 'package:your_counselor/core/education/education_repository.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/features/education/education_reader_screen.dart';
import 'package:your_counselor/features/education/education_screen.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

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
  _Repo(this.result, {this.canPrint = true});

  Object result;
  bool canPrint;
  int calls = 0;

  @override
  Future<EducationCatalog> pages() async {
    calls++;
    final r = result;
    if (r is Exception) throw r;
    return EducationCatalog(pages: r as List<EducationPage>, canPrint: canPrint);
  }
}

const _pages = [
  EducationPage(
    slug: 'cbt',
    title: 'Cognitive Behavioural Therapy (CBT)',
    kind: 'module',
    summary: 'A structured, time-limited approach.',
    url: 'https://api.test/learn/cbt?t=abc',
  ),
  EducationPage(
    slug: 'therapy-comparison-chart',
    title: 'Therapy Comparison Chart',
    kind: 'reference',
    url: 'https://api.test/learn/therapy-comparison-chart?t=abc',
  ),
  EducationPage(
    slug: 'case-history',
    title: 'Case History and MSE Practice Handout',
    kind: 'handout',
    url: 'https://api.test/learn/file/x.pdf?t=abc',
  ),
];

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
        educationPageViewProvider.overrideWithValue((page, canPrint) {
          opened.add((Uri.parse(page.url), canPrint));
          return Scaffold(appBar: AppBar(title: Text('Reading ${page.title}')));
        }),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: '/consult')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Education').last);
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

  testWidgets('without a plan: still free to read, printing explained, a way to the plans', (tester) async {
    final opened = await _pump(tester, _Repo(List.of(_pages), canPrint: false));
    expect(find.textContaining('Printing and saving as PDF come with any plan'), findsOneWidget);
    expect(find.textContaining('Print / Save as PDF button'), findsNothing);
    expect(find.text('See plans'), findsOneWidget);
    await tester.tap(find.text('Therapy Comparison Chart'));
    await tester.pumpAndSettle();
    expect(opened.single.$2, isFalse, reason: 'the pages stay free to read; the reader is told: no printing');
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

  test('page titles lose the brand prefix', () {
    expect(cleanTitle('YourCounselor | Therapy Comparison Chart'), 'Therapy Comparison Chart');
    expect(cleanTitle('The Core Eight | YourCounselor'), 'The Core Eight');
    expect(cleanTitle('Cognitive Behavioural Therapy (CBT)'), 'Cognitive Behavioural Therapy (CBT)');
  });

  testWidgets('filters show one kind at a time', (tester) async {
    await _pump(tester, _Repo(List.of(_pages)));
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();
    expect(find.text('Cognitive Behavioural Therapy (CBT)'), findsOneWidget);
    expect(find.text('Therapy Comparison Chart'), findsNothing);
    await tester.tap(find.text('Handouts'));
    await tester.pumpAndSettle();
    expect(find.text('Case History and MSE Practice Handout'), findsOneWidget);
    expect(find.text('Cognitive Behavioural Therapy (CBT)'), findsNothing);
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
      for (final tab in ['Consult', 'History', 'Calendar', 'Education', 'Account']) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
    });
  }
}
