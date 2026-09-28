import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/safety_widgets.dart';
import '../../core/widgets/surfaces.dart';

/// Gate 1: risk indicators in the case. The plan is replaced by the crisis
/// pathway, and the clinician confirms safety before continuing.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        gap: 14,
        actions: [
          OutlinedButton(onPressed: () => context.go('/consult'), child: const Text('Safety is managed: continue')),
        ],
        children: const [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill('Safety first', tone: Tone.crisis, icon: Icons.warning_amber_rounded, uppercase: true),
          ),
          PageHeading(
            'Your notes suggest possible risk',
            message: "The treatment plan is paused until your client's safety is addressed.",
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Immediate steps', style: AppText.label),
                SizedBox(height: 8),
                Text('[Safety steps from the reply appear here.]', style: AppText.small),
              ],
            ),
          ),
          CrisisNumbersCard(),
        ],
      ),
    );
  }
}

/// The inspector blocked the reply twice; the safe fallback is shown instead.
class HeldBackScreen extends StatelessWidget {
  const HeldBackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusPage(
      icon: Icons.shield_outlined,
      tone: Tone.check,
      title: 'We held this reply back',
      message: "It did not pass the app's clinical safety checks, even after one retry. It has been logged for review.",
      actions: [FilledButton(onPressed: () => context.go('/consult'), child: const Text('Try again'))],
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
  const IdentifiersScreen({super.key, this.types = const ['ID number']});

  final List<String> types;

  @override
  Widget build(BuildContext context) {
    return StatusPage(
      icon: Icons.search_rounded,
      tone: Tone.check,
      title: 'One thing still looks like an identifier',
      message: 'Our server double-checks every message. Please edit and send again.',
      actions: [FilledButton(onPressed: () => context.go('/consult'), child: const Text('Edit text'))],
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Found', style: AppText.label),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in types) StatusPill(t, tone: Tone.check)]),
              const SizedBox(height: 10),
              const Text(
                'Long runs of digits (7 or more) count as ID numbers. Write scores and dates in shorter forms.',
                style: AppText.smallMuted,
              ),
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

/// Network failure or timeout. The case text is still in memory, never on disk.
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusPage(
      icon: Icons.wifi_off_rounded,
      tone: Tone.neutral,
      title: "Couldn't reach Your Counselor",
      message: "Check your connection and try again. Your text is still on screen and hasn't been sent.",
      actions: [
        FilledButton(onPressed: () => context.go('/consult'), child: const Text('Try again')),
        TextButton(onPressed: () => context.go('/consult'), child: const Text('Back to my text')),
      ],
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
