import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/billing_models.dart';
import '../../core/education/education_repository.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import 'education_reader_screen.dart';

/// The screen a card opens: the page inside the app, under the app's own bar. Tests override it
/// (a web view can't run in widget tests).
typedef PageView = Widget Function(EducationPage page, PrintOffer? offer);

final educationPageViewProvider = Provider<PageView>(
  (ref) =>
      (page, offer) => EducationReaderScreen(page: page, offer: offer),
);

/// The Knowledge tabs. Which page sits in which section is set on the server (`section`).
enum _Section {
  all('All'),
  basics('Basics'),
  therapies('Therapies'),
  practice('Practice'),
  others('Others'),
  handouts('Handouts');

  const _Section(this.label);

  final String label;
}

String _errorText(Object e) => switch (e) {
  NetworkProblem() => "Couldn't reach YourCounselor. Check your connection.",
  Unauthorized() => 'Please sign in again.',
  _ => 'Something went wrong. Please try again.',
};

/// Free teaching pages for every signed-in user: one card per page, titled with the page's own title.
/// Printing / saving as PDF comes with any plan (the server leaves the button out otherwise).
class EducationScreen extends ConsumerStatefulWidget {
  const EducationScreen({super.key});

  @override
  ConsumerState<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends ConsumerState<EducationScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: _Section.values.length, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  _Section get _section => _Section.values[_tabs.index];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _open(EducationPage p, PrintOffer? offer) async {
    if (p.url.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Preview build: pages open when connected to the server.')));
      return;
    }
    final view = ref.read(educationPageViewProvider);
    // Full screen, above the bottom bar, like the rest of the app's detail screens.
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => view(p, offer)));
    if (!mounted) return;
    // The signed links last a few hours; a fresh list means fresh links next time.
    ref.invalidate(educationPagesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(educationPagesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _Section.values) Tab(text: t.label)],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(educationPagesProvider);
          await ref.read(educationPagesProvider.future);
        },
        child: pages.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 40),
              Text(_errorText(e), style: AppText.bodyMuted, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                  onPressed: () => ref.invalidate(educationPagesProvider),
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
          data: (catalog) {
            final all = catalog.pages;
            final shown = _section == _Section.all
                ? all
                : [
                    for (final p in all)
                      if (p.section == _section.name) p,
                  ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (catalog.canPrint)
                  const Text(
                    'Free for every YourCounselor user. Each page has a Print / Save as PDF button.',
                    style: AppText.smallMuted,
                  )
                else
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Free to read for every YourCounselor user. Printing and saving as PDF come with a '
                        'subscription${catalog.printOffer == null ? '' : ', or buy a single page for '
                                  '${formatMoney(catalog.printOffer!.price, catalog.printOffer!.currency)} '
                                  '(${catalog.printOffer!.hours} hours)'}.',
                        style: AppText.smallMuted,
                      ),
                      TextButton(onPressed: () => context.push('/pricing'), child: const Text('See plans')),
                    ],
                  ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('Nothing here yet.', style: AppText.bodyMuted, textAlign: TextAlign.center),
                  ),
                for (final p in shown) _PageCard(page: p, onTap: () => _open(p, catalog.printOffer)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "3:05 pm" today, otherwise "17 Oct, 3:05 pm".
String _until(DateTime t) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final time = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
  final now = DateTime.now();
  return t.year == now.year && t.month == now.month && t.day == now.day ? time : '${t.day} ${m[t.month - 1]}, $time';
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.page, required this.onTap});

  final EducationPage page;
  final VoidCallback onTap;

  IconData get _icon => switch (page.kind) {
    'module' => Icons.menu_book_rounded,
    'handout' => Icons.picture_as_pdf_outlined,
    _ => Icons.table_chart_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: _icon, size: 44, tone: page.kind == 'handout' ? Tone.neutral : Tone.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(page.title, style: AppText.label.copyWith(fontSize: 16, height: 1.3)),
                      if (page.summary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(page.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusPill(page.kindLabel, tone: Tone.neutral),
                          if (page.printUntil != null)
                            StatusPill('Print until ${_until(page.printUntil!)}', icon: Icons.print_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Icon(Icons.chevron_right_rounded, size: 24, color: AppColors.royalPurple),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
