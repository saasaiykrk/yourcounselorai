import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../content/safety_content.dart';
import '../theme/app_colors.dart';

/// The v2.1 disclaimer, shown verbatim at the end of every reply.
class DisclaimerBlock extends StatelessWidget {
  const DisclaimerBlock({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      kDisclaimer,
      style: TextStyle(
        fontSize: compact ? 12.5 : 13.5,
        height: 1.55,
        fontWeight: FontWeight.w600,
        color: compact ? AppColors.muted : AppColors.quietInk,
      ),
    );
    if (compact) return text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.quiet, borderRadius: BorderRadius.circular(18)),
      child: text,
    );
  }
}

/// Tap-to-call crisis numbers, straight from the crisis register.
class CrisisNumbersCard extends StatelessWidget {
  const CrisisNumbersCard({super.key, this.title = 'If there is any immediate risk to your client'});

  final String title;

  Future<void> _call(BuildContext context, CrisisLine line) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: line.dialString));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open the dialler. Call ${line.number} directly.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.crisis, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.crisis),
          ),
          const SizedBox(height: 4),
          for (final (i, line) in kCrisisLines.indexed) ...[
            if (i > 0) const Divider(),
            Semantics(
              button: true,
              label: 'Call ${line.service}, ${line.number}',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => _call(context, line),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(line.service, style: const TextStyle(fontSize: 15, color: AppColors.ink)),
                      ),
                      Text(
                        line.number,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.crisis),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.call_rounded, size: 18, color: AppColors.crisis),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(kCrisisVerifiedNote, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}
