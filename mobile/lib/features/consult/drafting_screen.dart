import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';

/// Waiting state while the server drafts and safety-checks the reply.
/// Nothing is shown to the clinician until the inspector has passed it,
/// so this screen shows progress rather than streamed text.
class DraftingScreen extends StatefulWidget {
  const DraftingScreen({super.key, this.autoAdvance = true});

  /// Preview only: walk through the steps and open the sample reply.
  final bool autoAdvance;

  @override
  State<DraftingScreen> createState() => _DraftingScreenState();
}

class _DraftingScreenState extends State<DraftingScreen> {
  static const _labels = [
    'Identifiers checked again on our server',
    'Drafting with the clinical knowledge base',
    'Safety checks on the draft',
    'Ready for your review',
  ];

  Timer? _ticker;
  int _elapsed = 0;
  int _current = 1;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed++;
        if (widget.autoAdvance && _elapsed == 3) _current = 2;
        if (widget.autoAdvance && _elapsed == 5) _current = 3;
      });
      if (widget.autoAdvance && _elapsed == 6) {
        _ticker?.cancel();
        context.pushReplacement('/reply');
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = '${_elapsed ~/ 60}:${(_elapsed % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Full plan',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.muted),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(clock, style: AppText.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ],
      ),
      body: PageBody(
        actions: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: AppColors.muted),
              SizedBox(width: 6),
              Flexible(child: Text("Keep the app open until it's ready.", style: AppText.caption)),
            ],
          ),
        ],
        children: [
          const PageHeading(
            'Drafting your work-up',
            message: "Full plans take 1–2 minutes. You'll only see it after it passes the safety checks.",
          ),
          Semantics(
            label: 'Step ${_current + 1} of ${_labels.length}',
            child: Row(
              children: [
                for (var i = 0; i < _labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= _current ? AppColors.royalPurple : AppColors.line,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          StepList(
            steps: [
              for (var i = 0; i < _labels.length; i++)
                StepItem(
                  _labels[i],
                  i < _current ? StepStatus.done : (i == _current ? StepStatus.active : StepStatus.pending),
                ),
            ],
          ),
          const _ReplySkeleton(),
        ],
      ),
    );
  }
}

class _ReplySkeleton extends StatelessWidget {
  const _ReplySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, {double height = 10, Color color = AppColors.lineSoft}) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      ),
    );
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            bar(0.6, height: 14, color: AppColors.lavender),
            const SizedBox(height: 10),
            bar(1),
            const SizedBox(height: 10),
            bar(0.92),
            const SizedBox(height: 10),
            bar(0.78),
            const SizedBox(height: 18),
            bar(0.45, height: 14, color: AppColors.lavender),
            const SizedBox(height: 10),
            bar(0.96),
            const SizedBox(height: 10),
            bar(0.7),
          ],
        ),
      ),
    );
  }
}
