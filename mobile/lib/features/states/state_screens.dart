import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/config.dart';
import '../../core/demo/preview_data.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/safety_widgets.dart';
import '../../core/widgets/surfaces.dart';
import '../consult/consult_controller.dart';
import '../consult/reply_markdown.dart';
import '../consult/reply_sections.dart';
import '../consult/report_sheet.dart';

/// Gate 1/2: risk indicators in the case. The reply is the safety pathway,
/// not a plan; the clinician confirms safety before continuing.
class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(consultControllerProvider);
    final reply = state is ConsultReplied && state.reply.meta.isSafetyGate ? state.reply : null;
    // From Account → Crisis numbers there is no reply: show the numbers only.
    final markdown = reply?.text ?? (AppConfig.previewMode && state is! ConsultIdle ? kPreviewSafetyMarkdown : null);
    final parsed = markdown == null ? null : parseReply(markdown);

    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(),
        body: PageBody(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          gap: 14,
          actions: [
            if (reply != null) ...[
              OutlinedButton(onPressed: () => context.go('/consult'), child: const Text('Safety is managed: continue')),
              TextButton(onPressed: () => showReportSheet(context), child: const Text('Report a problem')),
            ],
          ],
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill('Safety first', tone: Tone.crisis, icon: Icons.warning_amber_rounded, uppercase: true),
            ),
            PageHeading(
              markdown == null ? 'Crisis numbers' : 'Your notes suggest possible risk',
              message: markdown == null
                  ? 'For any immediate risk to a client. Tap a number to call.'
                  : "The treatment plan is paused until your client's safety is addressed.",
            ),
            if (parsed != null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parsed.intro.isNotEmpty) ReplyMarkdown(parsed.intro),
                    for (final s in parsed.sections) ...[
                      Text(s.heading, style: AppText.sectionTitle.copyWith(fontSize: 18, color: AppColors.crisis)),
                      const SizedBox(height: 8),
                      ReplyMarkdown(s.body),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            const CrisisNumbersCard(),
            if (parsed != null) const DisclaimerBlock(compact: true),
          ],
        ),
      ),
    );
  }
}

/// The inspector blocked the reply twice; the safe fallback is shown instead.
/// The draft is still on the consult screen, so the clinician can rephrase.
class HeldBackScreen extends StatelessWidget {
  const HeldBackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusPage(
      icon: Icons.shield_outlined,
      tone: Tone.check,
      title: 'We held this reply back',
      message: "It did not pass the app's clinical safety checks, even after one retry. It has been logged for review.",
      actions: [FilledButton(onPressed: () => context.go('/consult'), child: const Text('Rephrase and try again'))],
      children: const [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What you can do', style: AppText.label),
              SizedBox(height: 6),
              Text('Try again, or rephrase: add the duration, risk status and any scores.', style: AppText.small),
            ],
          ),
        ),
        CrisisNumbersCard(),
        DisclaimerBlock(compact: true),
      ],
    );
  }
}

/// Server-side cleaner found an identifier the phone missed (HTTP 422).
class IdentifiersScreen extends StatelessWidget {
  const IdentifiersScreen({super.key, this.types = const ['ID']});

  /// Tag types from the server, e.g. ["PHONE"]. Never the values.
  final List<String> types;

  @override
  Widget build(BuildContext context) {
    return StatusPage(
      icon: Icons.search_rounded,
      tone: Tone.check,
      title: 'Something still looks like an identifier',
      message: 'Our server double-checks every message. Please edit your text and send again.',
      actions: [FilledButton(onPressed: () => context.go('/consult'), child: const Text('Edit text'))],
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Found', style: AppText.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in types.toSet()) StatusPill(describeIdentifierType(t), tone: Tone.check)],
              ),
              if (types.contains('ID')) ...[
                const SizedBox(height: 10),
                const Text(
                  'Long runs of digits (7 or more) count as ID numbers. Write scores and dates in shorter forms.',
                  style: AppText.smallMuted,
                ),
              ],
            ],
          ),
        ),
        const NoticeBanner(
          icon: Icons.verified_user_outlined,
          text: 'Nothing was sent to the AI, and nothing was stored.',
        ),
      ],
    );
  }
}

/// Daily consult limit reached (HTTP 429). The backend counts a rolling 24 hours.
class LimitScreen extends StatelessWidget {
  const LimitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const limit = AppConfig.dailyConsultLimit;
    return StatusPage(
      icon: Icons.update_rounded,
      tone: Tone.brand,
      title: "You've reached today's limit",
      message: 'During the beta, each clinician can run $limit consults in any 24 hours.',
      actions: [OutlinedButton(onPressed: () => context.go('/consult'), child: const Text('OK'))],
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Expanded(child: Text('Used', style: AppText.label)),
                  Text('$limit / $limit', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  value: 1,
                  minHeight: 8,
                  color: AppColors.royalPurple,
                  backgroundColor: AppColors.lineSoft,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your next consult frees up once your earliest one today is 24 hours old.',
                style: AppText.smallMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Network failure, timeout or server error. The draft is still in memory on
/// the consult screen (never on disk).
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (error) {
      NetworkProblem(timedOut: true) => (
        'This is taking too long',
        "The reply didn't arrive in time. Your text is still on the consult screen; please try again.",
      ),
      ServerProblem() || NotFound() => (
        'Something went wrong on our side',
        'Your text is still on the consult screen. Please try again in a moment.',
      ),
      _ => (
        "Couldn't reach Your Counselor",
        "Check your connection and try again. Your text is still on the consult screen and hasn't been sent.",
      ),
    };
    return StatusPage(
      icon: error is NetworkProblem || error == null ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
      tone: Tone.neutral,
      title: title,
      message: message,
      actions: [FilledButton(onPressed: () => context.go('/consult'), child: const Text('Back to my text'))],
      children: const [
        NoticeBanner(
          icon: Icons.info_outline_rounded,
          tone: Tone.check,
          text: 'For privacy, case text is never saved. Closing the app will clear it.',
        ),
      ],
    );
  }
}
