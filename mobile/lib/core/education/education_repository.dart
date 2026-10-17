import '../api/api_client.dart';

/// One page of the free Education module, as the server lists it.
class EducationPage {
  const EducationPage({
    required this.slug,
    required this.title,
    required this.kind,
    required this.url,
    this.summary = '',
  });

  factory EducationPage.fromJson(Map<String, dynamic> j) => EducationPage(
    slug: j['slug'] as String? ?? '',
    title: j['title'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    kind: j['kind'] as String? ?? 'reference',
    url: j['url'] as String? ?? '',
  );

  final String slug;

  /// The page's own title.
  final String title;
  final String summary;

  /// module · reference · handout
  final String kind;

  /// A signed link to the page, valid for a few hours; fetched fresh each time the list loads.
  final String url;

  String get kindLabel => switch (kind) {
    'module' => 'Module',
    'handout' => 'Handout · PDF',
    _ => 'Reference',
  };
}

/// The cards, and whether this clinician may print them (any plan in effect).
class EducationCatalog {
  const EducationCatalog({required this.pages, this.canPrint = false});

  factory EducationCatalog.fromJson(Map<String, dynamic> j) => EducationCatalog(
    pages: [for (final p in (j['pages'] as List? ?? const [])) EducationPage.fromJson(p as Map<String, dynamic>)],
    canPrint: j['can_print'] == true,
  );

  final List<EducationPage> pages;

  /// The pages show "Print / Save as PDF" only with a plan; the server decides, this only explains it.
  final bool canPrint;
}

abstract interface class EducationRepository {
  Future<EducationCatalog> pages();
}

class ApiEducationRepository implements EducationRepository {
  ApiEducationRepository(this._api);

  final ApiClient _api;

  @override
  Future<EducationCatalog> pages() => _api.education();
}

/// Offline preview: the real titles, no links (nothing to open without the server).
class PreviewEducationRepository implements EducationRepository {
  static const _pages = [
    (
      'foundations',
      'Foundations for Counsellors and Psychologists',
      'module',
      'A practical training guide to safe, collaborative and accountable practice.',
    ),
    (
      'the-core-eight-practical-guide',
      'The Core Eight',
      'reference',
      'A practical perspective on learning and combining therapy approaches.',
    ),
    (
      'therapy-comparison-chart',
      'Therapy Comparison Chart',
      'reference',
      'A side-by-side comparison of eight therapy approaches.',
    ),
    (
      'adult-psychotherapy-protocol-matrix-and-glossary',
      'Adult Psychotherapy Clinical Protocol Matrix and Therapy Glossary',
      'reference',
      '',
    ),
    (
      'acceptance-commitment-therapy',
      'Acceptance and Commitment Therapy (ACT)',
      'module',
      'A professional practice module on ACT’s psychological flexibility model.',
    ),
    (
      'cbt',
      'Cognitive Behavioural Therapy (CBT)',
      'module',
      'A structured, time-limited approach that helps clients notice, test and loosen unhelpful thoughts.',
    ),
    (
      'case-history-and-mse-practice-handout',
      'Case History and MSE Practice Handout',
      'handout',
      'Printable practice handout (PDF).',
    ),
  ];

  @override
  Future<EducationCatalog> pages() async => EducationCatalog(
    pages: [
      for (final (slug, title, kind, summary) in _pages)
        EducationPage(slug: slug, title: title, kind: kind, summary: summary, url: ''),
    ],
    canPrint: true,
  );
}
