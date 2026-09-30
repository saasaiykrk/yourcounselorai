import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'surfaces.dart';

/// Standard page: scrollable content with actions pinned to the bottom.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
    this.gap = 18,
  });

  final List<Widget> children;
  final List<Widget> actions;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: padding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(children, gap)),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(actions, 8)),
            ),
        ],
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> items, double gap) => [
    for (final (i, w) in items.indexed) ...[if (i > 0) SizedBox(height: gap), w],
  ];
}

/// Title plus supporting sentence.
class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.message, this.hero = false});

  final String title;
  final String? message;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: hero ? AppText.heroTitle : AppText.screenTitle)),
        if (message != null) ...[const SizedBox(height: 8), Text(message!, style: AppText.bodyMuted)],
      ],
    );
  }
}

/// Layout for the single-message screens: pending, held back, errors.
class StatusPage extends StatelessWidget {
  const StatusPage({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    this.children = const [],
    this.actions = const [],
  });

  final IconData icon;
  final Tone tone;
  final String title;
  final String message;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(22, 56, 22, 0),
        actions: actions,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconTile(icon: icon, tone: tone),
          ),
          PageHeading(title, message: message),
          ...children,
        ],
      ),
    );
  }
}

/// Selectable card that behaves like a radio button.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.title, required this.selected, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.lavender : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.royalPurple : AppColors.line, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.royalPurple : AppColors.muted,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        if (subtitle != null) Text(subtitle!, style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum StepStatus { done, active, pending }

class StepItem {
  const StepItem(this.label, this.state, {this.detail});

  final String label;
  final String? detail;
  final StepStatus state;
}

/// Vertical checklist used for drafting progress and verification status.
class StepList extends StatelessWidget {
  const StepList({super.key, required this.steps, this.activeColor = AppColors.royalPurple});

  final List<StepItem> steps;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, step) in steps.indexed) ...[
            if (i > 0) const Divider(),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Row(
                children: [
                  _marker(step.state),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          step.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: step.state == StepStatus.pending ? FontWeight.w400 : FontWeight.w700,
                            color: step.state == StepStatus.pending ? AppColors.muted : AppColors.ink,
                          ),
                        ),
                        if (step.detail != null) Text(step.detail!, style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _marker(StepStatus state) {
    switch (state) {
      case StepStatus.done:
        return Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(color: AppColors.royalPurple, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        );
      case StepStatus.active:
        return Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: activeColor, width: 2.5),
          ),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle),
          ),
        );
      case StepStatus.pending:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.pendingRing, width: 2),
          ),
        );
    }
  }
}
