import '../api/api_client.dart';

/// One page of the free Education module, as the server lists it.
class EducationPage {
  const EducationPage({
    required this.slug,
    required this.title,
    required this.kind,
    required this.url,
    this.summary = '',
    this.canPrint = false,
    this.printUntil,
    String? section,
  }) : section = section ?? (kind == 'handout' ? 'handouts' : 'others');

  factory EducationPage.fromJson(Map<String, dynamic> j) => EducationPage(
    slug: j['slug'] as String? ?? '',
    title: j['title'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    kind: j['kind'] as String? ?? 'reference',
    url: j['url'] as String? ?? '',
    section: j['section'] as String?,
    canPrint: j['can_print'] == true,
    printUntil: DateTime.tryParse(j['print_until'] as String? ?? '')?.toLocal(),
  );

  final String slug;

  /// The page's own title.
  final String title;
  final String summary;

  /// module · reference · handout
  final String kind;

  /// The Knowledge tab it sits under: basics · therapies · practice · others · handouts (set by the server).
  final String section;

  /// A signed link to the page, valid for a few hours; fetched fresh each time the list loads.
  final String url;

  /// This clinician may print / save this page as a PDF (the server decides; the page enforces it).
  final bool canPrint;

  /// When a single print bought for this page ends (null: none, or a subscription covers it).
  final DateTime? printUntil;

  String get kindLabel => switch (kind) {
    'module' => 'Module',
    'handout' => 'Handout · PDF',
    _ => 'Reference',
  };
}

/// A single print for sale: one page, printed or saved as often as needed for [hours].
class PrintOffer {
  const PrintOffer({required this.price, this.currency = 'INR', this.hours = 24, this.name = 'Print one page'});

  static PrintOffer? fromJson(Object? j) => j is Map<String, dynamic>
      ? PrintOffer(
          price: (j['price'] as num?)?.toInt() ?? 0,
          currency: j['currency'] as String? ?? 'INR',
          hours: (j['hours'] as num?)?.toInt() ?? 24,
          name: j['name'] as String? ?? 'Print one page',
        )
      : null;

  final int price; // paise
  final String currency;
  final int hours;
  final String name;
}

/// The cards, and what this clinician may print.
class EducationCatalog {
  const EducationCatalog({required this.pages, this.canPrint = false, this.printOffer});

  factory EducationCatalog.fromJson(Map<String, dynamic> j) => EducationCatalog(
    pages: [for (final p in (j['pages'] as List? ?? const [])) EducationPage.fromJson(p as Map<String, dynamic>)],
    canPrint: j['can_print'] == true,
    printOffer: PrintOffer.fromJson(j['print_offer']),
  );

  final List<EducationPage> pages;

  /// Every page prints: pricing is off, or a running subscription. The server decides; this explains it.
  final bool canPrint;

  /// A single print for sale (null: printing comes only with a subscription right now).
  final PrintOffer? printOffer;
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

  static const _sections = {
    'foundations': 'basics',
    'the-core-eight-practical-guide': 'basics',
    'therapy-comparison-chart': 'practice',
    'adult-psychotherapy-protocol-matrix-and-glossary': 'practice',
    'acceptance-commitment-therapy': 'therapies',
    'cbt': 'therapies',
  };

  @override
  Future<EducationCatalog> pages() async => EducationCatalog(
    pages: [
      for (final (slug, title, kind, summary) in _pages)
        EducationPage(
          slug: slug,
          title: title,
          kind: kind,
          summary: summary,
          url: '',
          canPrint: true,
          section: _sections[slug],
        ),
    ],
    canPrint: true,
  );
}
