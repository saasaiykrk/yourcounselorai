// Education tab: one card per page (the page's own title), filters, opening a page in the browser,
// fresh links on every visit, errors, and the 320px layout.
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

Future<List<Uri>> _pump(WidgetTester tester, _Repo repo, {double width = 390, bool opens = true}) async {
  final opened = <Uri>[];
  tester.view.physicalSize = Size(width, 800) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        educationRepositoryProvider.overrideWithValue(repo),
        educationOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return opens;
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
    expect(opened, hasLength(1), reason: 'the pages themselves stay free');
  });

  testWidgets('tapping a card opens that page; the list is fetched again for fresh links', (tester) async {
    final repo = _Repo(List.of(_pages));
    final opened = await _pump(tester, repo);
    final before = repo.calls;
    await tester.tap(find.text('Therapy Comparison Chart'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://api.test/learn/therapy-comparison-chart?t=abc')]);
    expect(repo.calls, greaterThan(before));
  });

  testWidgets('a page that cannot open says so', (tester) async {
    await _pump(tester, _Repo(List.of(_pages)), opens: false);
    await tester.tap(find.text('Therapy Comparison Chart'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open the page. Please try again."), findsOneWidget);
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
