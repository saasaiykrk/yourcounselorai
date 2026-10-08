import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../history/history_screen.dart' show historyWhen;
import 'consultation_controller.dart';

/// "Continue where you left off": unfinished guided consultations, read from the server.
/// Shows nothing when there are none (or the list can't be loaded).
class OpenConsultations extends ConsumerWidget {
  const OpenConsultations({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openConsultationsProvider).value ?? const <ConsultationSummary>[];
    if (open.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Continue a consultation', style: AppText.label),
        const SizedBox(height: 8),
        for (final c in open.take(3)) ...[
          _OpenCard(
            summary: c,
            onTap: () {
              ref.read(consultationControllerProvider.notifier).resume(c.id);
              context.push('/consultation');
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _OpenCard extends StatelessWidget {
  const _OpenCard({required this.summary, required this.onTap});

  final ConsultationSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = switch (summary.stage) {
      ConsultationStage.snapshot => 'Case Snapshot to complete',
      ConsultationStage.ready => 'Ready for the report',
      ConsultationStage.safetyStop => 'Waiting for your safety check',
      _ => 'Question ${summary.questionsAsked}',
    };
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.forum_outlined, color: AppColors.royalPurple, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.caseSummary.isEmpty ? 'Guided consultation' : summary.caseSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [status, if (summary.updatedAt != null) historyWhen(summary.updatedAt!)].join(' · '),
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
