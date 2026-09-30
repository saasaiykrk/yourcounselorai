import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/content/safety_content.dart';
import '../../core/demo/preview_data.dart';
import '../../core/deid/cleaner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import 'consult_controller.dart';

/// Waiting state while the server drafts and safety-checks the reply.
/// Nothing reaches the clinician until the inspector has passed it, so this
/// screen shows progress, never streamed text. When the consult finishes it
/// replaces itself with the reply, the safety pathway, or the right error.
class DraftingScreen extends ConsumerStatefulWidget {
  const DraftingScreen({super.key});

  @override
  ConsumerState<DraftingScreen> createState() => _DraftingScreenState();
}

class _DraftingScreenState extends ConsumerState<DraftingScreen> {
  static const _labels = [
    'Sent securely, identifiers checked again',
    'Drafting with the clinical knowledge base',
    'Safety checks on the draft',
    'Ready for your review',
  ];

  Timer? _ticker;
  int _elapsed = 0;
  int _current = 1;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed++));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(consultControllerProvider);
      if (state is ConsultIdle && AppConfig.previewMode) {
        // Opened directly (design preview): run the sample case.
        final sample = clean(kSampleCase);
        ref
            .read(consultControllerProvider.notifier)
            .send(text: sample.text, mode: ConsultMode.fullPlan, redactionCounts: sample.counts);
      } else {
        _maybeFinish(state);
      }
    });
  }

  void _maybeFinish(ConsultState state) {
    if (_left || state is ConsultSending || state is ConsultIdle) return;
    _left = true;
    _ticker?.cancel();
    setState(() => _current = _labels.length);
    final (route, extra) = routeForOutcome(state);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (route == '/sign-in' || route == '/pending') {
        context.go(route);
      } else {
        context.pushReplacement(route, extra: extra);
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
    ref.listen(consultControllerProvider, (_, next) => _maybeFinish(next));
    final state = ref.watch(consultControllerProvider);
    final modeLabel = state is ConsultSending ? state.mode.label : 'Consult';
    final clock = '${_elapsed ~/ 60}:${(_elapsed % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          modeLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.muted),
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
            message: "A full plan can take 1–2 minutes. You'll only see it after it passes the safety checks.",
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
