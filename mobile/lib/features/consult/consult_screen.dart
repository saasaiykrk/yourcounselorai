import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/content/safety_content.dart';
import '../../core/demo/preview_data.dart';
import '../../core/providers.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../consultation/consultation_controller.dart';
import '../consultation/open_consultations.dart';
import 'check_sheet.dart';
import 'consult_controller.dart';

class ConsultScreen extends ConsumerStatefulWidget {
  const ConsultScreen({super.key});

  @override
  ConsumerState<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends ConsumerState<ConsultScreen> {
  // Case text lives only in memory and is never written to disk.
  final _text = TextEditingController(text: AppConfig.previewMode ? kSampleCase : '');
  ConsultMode _mode = ConsultMode.auto;

  /// Guided consultation (questions, then the fixed report) or a direct consult.
  /// Null until the clinician picks: guided is the default when the server offers it.
  bool? _guidedChoice;

  bool get _canSend => _text.text.trim().length >= AppConfig.minCaseLength;

  Future<void> _check(bool guided) => guided
      ? showCheckSheet(context, text: _text.text, onSend: _startGuided)
      : showCheckSheet(context, text: _text.text, mode: _mode);

  Future<void> _startGuided(String text, Map<String, int> counts) async {
    final router = GoRouter.of(context);
    router.push('/consultation');
    final ok = await ref.read(consultationControllerProvider.notifier).start(text: text, redactionCounts: counts);
    if (ok && mounted) setState(_text.clear);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The draft stays in memory (never on disk) until a reply is delivered, so a
    // failed send can be retried; then it is wiped (SPEC-week1 §3.1).
    ref.listen(consultControllerProvider, (_, next) {
      if (next is ConsultReplied && next.reply.delivered) setState(_text.clear);
    });
    final offered = ref.watch(meProvider).value?.guidedConsultation ?? false;
    final guided = offered && (_guidedChoice ?? true);
    return ProtectedScreen(
      child: Scaffold(
        body: PageBody(
          gap: 16,
          actions: [
            FilledButton.icon(
              onPressed: _canSend ? () => _check(guided) : null,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(guided ? 'Check & start' : 'Check & send'),
            ),
          ],
          children: [
            const _Header(),
            if (AppConfig.previewMode)
              const NoticeBanner(
                icon: Icons.visibility_outlined,
                tone: Tone.neutral,
                text: 'Preview build: sample case, not connected to the server.',
              ),
            if (offered)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Guided'), icon: Icon(Icons.forum_outlined)),
                  ButtonSegment(value: false, label: Text('Direct'), icon: Icon(Icons.bolt_outlined)),
                ],
                selected: {guided},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _guidedChoice = v.first),
              ),
            PageHeading(
              guided ? 'Guided consultation' : 'New consult',
              message: guided
                  ? "Describe the case. We'll ask only what the report needs, then write your consultation report. "
                        'Leave out names, contact details and ID numbers.'
                  : 'Describe the case. Leave out names, contact details and ID numbers.',
            ),
            _CaseField(controller: _text, onChanged: () => setState(() {})),
            if (guided) const OpenConsultations(),
            if (!guided)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What do you need?', style: AppText.label),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: ConsultMode.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final mode = ConsultMode.values[i];
                        return _ModeChip(
                          label: mode.label,
                          selected: mode == _mode,
                          onTap: () => setState(() => _mode = mode),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(_mode.hint, style: AppText.smallMuted),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

const _roleLabels = {'counsellor_trainee': 'Trainee', 'psychologist': 'Psychologist', 'psychiatrist': 'Psychiatrist'};

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The level shown is the server-verified one; the app never decides it.
    // Only the level fits beside the wordmark on narrow phones; the role is on Account.
    final me = ref.watch(meProvider).value;
    final level = me?.level;
    final role = me?.role == null ? null : _roleLabels[me!.role] ?? me.role!;
    // Keep the header one line high even with very large system text.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const BrandMark(size: 30),
            const SizedBox(width: 8),
            // The wordmark never wraps; it shrinks a little if the row is tight.
            const Expanded(
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: BrandWordmark()),
            ),
            if (level != null) ...[
              const SizedBox(width: 8),
              Semantics(
                label: 'Verified ${role ?? 'clinician'}, level $level',
                excludeSemantics: true,
                child: StatusPill(level, icon: Icons.verified_user_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaseField extends StatelessWidget {
  const _CaseField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.royalPurple, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Case description',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
            ),
          ),
          TextField(
            controller: controller,
            minLines: 7,
            maxLines: 12,
            maxLength: AppConfig.maxCaseLength,
            keyboardType: TextInputType.multiline,
            // No autocorrect learning or suggestions on clinical text.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            style: AppText.body,
            decoration: const InputDecoration(
              hintText: 'e.g. 34F, panic attacks for 3 months, PHQ-9 8, GAD-7 14. Risk asked, denies.',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            ),
            onChanged: (_) => onChanged(),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                const Expanded(child: Text('Never stored on this phone', style: AppText.caption)),
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (_, value, _) => Text('${value.text.length} / 12,000', style: AppText.caption),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.royalPurple : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? AppColors.royalPurple : AppColors.inputBorder, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
