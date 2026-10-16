import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/education/education_repository.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';

/// Opens a page in the phone's in-app browser (Chrome Custom Tab / Safari view), where the page's own
/// "Print / Save as PDF" button works. Tests override it.
typedef PageOpener = Future<bool> Function(Uri url);

final educationOpenerProvider = Provider<PageOpener>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.inAppBrowserView),
);

enum _Filter {
  all('All'),
  module('Modules'),
  reference('Reference'),
  handout('Handouts');

  const _Filter(this.label);

  final String label;
}

String _errorText(Object e) => switch (e) {
  NetworkProblem() => "Couldn't reach YourCounselor. Check your connection.",
  Unauthorized() => 'Please sign in again.',
  _ => 'Something went wrong. Please try again.',
};

/// Free teaching pages for every signed-in user: one card per page, titled with the page's own title.
class EducationScreen extends ConsumerStatefulWidget {
  const EducationScreen({super.key});

  @override
  ConsumerState<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends ConsumerState<EducationScreen> {
  _Filter _filter = _Filter.all;
  String? _opening;

  Future<void> _open(EducationPage p) async {
    if (_opening != null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (p.url.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Preview build: pages open when connected to the server.')));
      return;
    }
    setState(() => _opening = p.slug);
    var ok = false;
    try {
      ok = await ref.read(educationOpenerProvider)(Uri.parse(p.url));
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _opening = null);
    // The signed links last a few hours; a fresh list means fresh links next time.
    ref.invalidate(educationPagesProvider);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text("Couldn't open the page. Please try again.")));
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(educationPagesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Education')),
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
          data: (all) {
            final kinds = {for (final p in all) p.kind};
            final filters = [
              _Filter.all,
              for (final f in _Filter.values.skip(1))
                if (kinds.contains(f.name)) f,
            ];
            final shown = _filter == _Filter.all
                ? all
                : [
                    for (final p in all)
                      if (p.kind == _filter.name) p,
                  ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                const Text(
                  'Free for every YourCounselor user. Pages open in your browser; each has a '
                  'Print / Save as PDF button.',
                  style: AppText.smallMuted,
                ),
                const SizedBox(height: 12),
                if (filters.length > 2)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final f in filters)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('Nothing here yet.', style: AppText.bodyMuted, textAlign: TextAlign.center),
                  ),
                for (final p in shown) _PageCard(page: p, opening: _opening == p.slug, onTap: () => _open(p)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.page, required this.onTap, this.opening = false});

  final EducationPage page;
  final VoidCallback onTap;
  final bool opening;

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
                      StatusPill(page.kindLabel, tone: Tone.neutral),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: opening
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.open_in_new_rounded, size: 20, color: AppColors.royalPurple),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
