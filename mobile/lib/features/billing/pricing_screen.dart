import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/billing_models.dart';
import '../../core/billing/purchase.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

String _day(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Plans & credits. Every plan, price and table cell shown here comes from the server (the admin's
/// pricing); nothing is hardcoded. A purchase counts only once the server has confirmed it.
class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  String? _busy; // which button is working: "<plan>:<type or period>"
  String _period = 'year';

  Future<void> _buy(String plan, {String? reportType, String? period}) async {
    if (_busy != null) return;
    setState(() => _busy = '$plan:${reportType ?? period ?? ''}');
    final flow = PurchaseFlow(ref.read(billingRepositoryProvider), ref.read(paymentGatewayProvider));
    final outcome = await flow.buy(plan: plan, reportType: reportType, period: period);
    if (!mounted) return;
    setState(() => _busy = null);
    ref.invalidate(billingStatusProvider);
    ref.invalidate(meProvider);
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case PurchaseDone():
        messenger.showSnackBar(const SnackBar(content: Text('Payment received. Your plan is ready to use.')));
      case PurchaseCancelled():
        messenger.showSnackBar(const SnackBar(content: Text('Payment cancelled. Nothing was charged.')));
      case PurchasePending():
        await _tell(
          'Waiting for the bank',
          'Your payment is still being confirmed. Your plan appears here as soon as Razorpay confirms it. '
              "You won't be charged twice.",
        );
      case PurchaseFailed(:final message):
        await _tell('Payment not completed', message);
    }
  }

  Future<void> _tell(String title, String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(billingPlansProvider);
    final status = ref.watch(billingStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & credits')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(billingPlansProvider);
          ref.invalidate(billingStatusProvider);
          await ref.read(billingPlansProvider.future);
        },
        child: plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _LoadError(onRetry: () => ref.invalidate(billingPlansProvider)),
          data: (p) => _body(p, status.value),
        ),
      ),
    );
  }

  Widget _body(BillingPlans p, BillingStatus? s) {
    final tiers = p.tiers;
    final periods = {for (final t in tiers) ...t.periods};
    final period = periods.contains(_period) || periods.isEmpty ? _period : periods.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (!p.enabled) ...[
          const PageHeading(
            'Everything is free right now',
            message: 'There is nothing to buy. Plans appear here if that changes.',
          ),
        ] else ...[
          if (s != null) CreditsCard(status: s),
          for (final n in s?.notices ?? const <BillingNotice>[]) ...[
            const SizedBox(height: 10),
            NoticeBanner(icon: Icons.info_outline_rounded, tone: Tone.check, text: n.message),
          ],
          if (!p.paymentsAvailable) ...[
            const SizedBox(height: 10),
            const NoticeBanner(
              icon: Icons.schedule_rounded,
              tone: Tone.neutral,
              text: 'Payments are not available right now. Please try again later.',
            ),
          ],
          if (tiers.isNotEmpty) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(child: Text('Plans', style: AppText.sectionTitle)),
                if (periods.length > 1)
                  SegmentedButton<String>(
                    key: const ValueKey('period'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'year', label: Text('Yearly')),
                      ButtonSegment(value: 'month', label: Text('Monthly')),
                    ],
                    selected: {period},
                    onSelectionChanged: (v) => setState(() => _period = v.first),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Prices in ₹. Paid in advance; renew any time.', style: AppText.caption),
            const SizedBox(height: 12),
            for (final plan in tiers) ...[
              TierCard(
                plan: plan,
                period: plan.periods.contains(period) ? period : plan.periods.firstOrNull ?? period,
                rows: p.rows,
                currency: p.currency,
                status: s,
                canPay: p.paymentsAvailable,
                busy: _busy,
                onBuy: (per) => _buy(plan.id, period: per),
                onExtra: () => _buy('scale_extra'),
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (p.perReport case final per?) ...[
            const SizedBox(height: 10),
            _PerReportCard(
              plan: per,
              currency: p.currency,
              canPay: p.paymentsAvailable,
              busy: _busy,
              onBuy: (type) => _buy(per.id, reportType: type),
            ),
          ],
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.push('/pricing/history'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Payment and credit history'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Payments are handled by Razorpay. Prices include any applicable taxes. '
          'A report is charged only when it is delivered; a report held back by the safety check costs nothing.',
          style: AppText.caption,
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text("Couldn't load the plans. Check your connection.", style: AppText.bodyMuted),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}

String _periodWord(String? p) => switch (p) {
  'year' => 'yearly',
  'month' => 'monthly',
  'trial' => 'free months',
  'admin' => 'given by the team',
  _ => '',
};

/// The clinician's plan now, this month's Scale reports, and credits bought on their own.
class CreditsCard extends StatelessWidget {
  const CreditsCard({super.key, required this.status});

  final BillingStatus status;

  @override
  Widget build(BuildContext context) {
    final plan = status.plan;
    final key = status.ownKey;
    final scale = status.scale;
    return AppCard(
      color: AppColors.lavender,
      borderColor: AppColors.lavender,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your plan', style: AppText.label),
          const SizedBox(height: 6),
          Text(
            plan == null ? 'No plan yet' : plan.name,
            style: AppText.screenTitle.copyWith(fontSize: 22, color: AppColors.deepPurple),
          ),
          if (plan != null)
            Text(
              plan.trial
                  ? 'Free until ${_day(plan.expiresAt)}'
                  : '${_periodWord(plan.period)} · until ${_day(plan.expiresAt)}'.trim(),
              style: AppText.smallMuted,
            ),
          if (scale != null) ...[
            const SizedBox(height: 10),
            Text(
              '${scale.guidedLeft} of ${scale.perMonth} AI-Guided reports left this month'
              '${scale.resetsAt == null ? '' : ' · new ones on ${_day(scale.resetsAt)}'}',
              style: AppText.small,
            ),
          ],
          if (status.guidedCredits - (scale?.guidedLeft ?? 0) > 0 || status.directCredits > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Count(label: 'Guided reports', value: status.guidedCredits - (scale?.guidedLeft ?? 0)),
                ),
                Expanded(
                  child: _Count(label: 'Quick reports', value: status.directCredits),
                ),
              ],
            ),
          ],
          if (key.connected) ...[
            const SizedBox(height: 6),
            Text(
              key.status == 'valid'
                  ? 'Your Anthropic key (…${key.last4}) is connected.'
                  : 'Your Anthropic key (…${key.last4}) needs attention.',
              style: AppText.smallMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value left',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: AppText.screenTitle.copyWith(color: AppColors.deepPurple)),
        Text(label, style: AppText.smallMuted),
      ],
    ),
  );
}

/// One plan: badge, price for the chosen period (old price struck through, the other period
/// below), what it includes row by row, and its button.
class TierCard extends StatelessWidget {
  const TierCard({
    super.key,
    required this.plan,
    required this.period,
    required this.rows,
    required this.currency,
    required this.status,
    required this.canPay,
    required this.busy,
    required this.onBuy,
    required this.onExtra,
  });

  final PlanOffer plan;
  final String period;
  final List<PlanRow> rows;
  final String currency;
  final BillingStatus? status;
  final bool canPay;
  final String? busy;
  final void Function(String period) onBuy;
  final VoidCallback onExtra;

  @override
  Widget build(BuildContext context) {
    final current = status?.plan?.id == plan.id;
    final trial = current && status!.plan!.trial;
    final other = period == 'year' ? 'month' : 'year';
    final price = plan.price(period), was = plan.was(period);
    final working = busy == '${plan.id}:$period';
    final freeFirst = plan.trialDays > 0;
    final months = (plan.trialDays / 30).round();
    final freeWords = months >= 1 ? '$months month${months == 1 ? '' : 's'}' : '${plan.trialDays} days';
    final highlight = plan.id == 'scale';
    return AppCard(
      key: ValueKey('tier-${plan.id}'),
      color: highlight ? AppColors.lavender : AppColors.surface,
      borderColor: current ? AppColors.royalPurple : AppColors.line,
      borderWidth: current ? 1.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (plan.badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.berry, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    plan.badge,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              const Spacer(),
              if (current) StatusPill(trial ? 'Free now' : 'Your plan', icon: Icons.check_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.name, style: AppText.sectionTitle.copyWith(color: AppColors.deepPurple)),
          const SizedBox(height: 4),
          if (freeFirst) ...[
            Text('Free', style: AppText.screenTitle.copyWith(fontSize: 28, color: AppColors.deepPurple)),
            Text(
              'for $freeWords, then ${formatMoney(plan.priceMonth, currency)}/month or '
              '${formatMoney(plan.priceYear, currency)}/year',
              style: AppText.smallMuted,
            ),
          ] else ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatMoney(price, currency),
                    style: AppText.screenTitle.copyWith(fontSize: 28, color: AppColors.deepPurple),
                  ),
                  TextSpan(text: '/$period', style: AppText.smallMuted),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                style: AppText.smallMuted,
                children: [
                  if (was > 0)
                    TextSpan(
                      text: formatMoney(was, currency),
                      style: const TextStyle(decoration: TextDecoration.lineThrough),
                    ),
                  if (was > 0 && plan.periods.contains(other)) const TextSpan(text: ' · '),
                  if (plan.periods.contains(other))
                    TextSpan(text: 'or ${formatMoney(plan.price(other), currency)}/$other'),
                ],
              ),
            ),
          ],
          if (plan.description.isNotEmpty) ...[const SizedBox(height: 6), Text(plan.description, style: AppText.small)],
          const SizedBox(height: 10),
          for (final r in rows) _Row(label: r.label, value: plan.table[r.key]),
          for (final f in plan.features)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $f', style: AppText.small),
            ),
          const SizedBox(height: 14),
          FilledButton(
            key: ValueKey('choose-${plan.id}'),
            onPressed: busy == null && canPay ? () => onBuy(period) : null,
            child: working
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(
                    current && !trial
                        ? 'Renew ${plan.name}'
                        : trial
                        ? 'Keep ${plan.name} after the free months'
                        : freeFirst
                        ? 'Choose ${plan.name} · ${formatMoney(price, currency)}/$period'
                        : 'Choose ${plan.name}',
                  ),
          ),
          if (plan.id == 'scale' && current) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('buy-extra'),
              onPressed: busy == null && canPay ? onExtra : null,
              child: Text('Buy an extra AI-Guided report · ${formatMoney(plan.extraPrice, currency)}'),
            ),
          ],
          if (plan.id == 'byok_scale' && (status?.ownKey.included ?? false)) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => GoRouter.of(context).push('/pricing/own-key'),
              child: Text(status?.ownKey.connected == true ? 'Manage my key' : 'Set up my key'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          value == null ? Icons.remove_rounded : Icons.check_circle_rounded,
          size: 18,
          color: value == null ? AppColors.muted : AppColors.doneInk,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label, style: AppText.small),
                if (value != null && value != 'Included')
                  TextSpan(
                    text: ' · $value',
                    style: AppText.small.copyWith(color: AppColors.doneInk, fontWeight: FontWeight.w700),
                  ),
                if (value == null) const TextSpan(text: ' · Not included', style: AppText.smallMuted),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _PerReportCard extends StatelessWidget {
  const _PerReportCard({
    required this.plan,
    required this.currency,
    required this.canPay,
    required this.busy,
    required this.onBuy,
  });

  final PlanOffer plan;
  final String currency;
  final bool canPay;
  final String? busy;
  final void Function(String reportType) onBuy;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(plan.name, style: AppText.sectionTitle),
        if (plan.description.isNotEmpty) ...[const SizedBox(height: 6), Text(plan.description, style: AppText.small)],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (t, label) in const [('guided', 'AI-Guided report'), ('direct', 'Quick consult')])
              if (plan.prices[t] != null)
                OutlinedButton(
                  onPressed: busy == null && canPay ? () => onBuy(t) : null,
                  child: busy == '${plan.id}:$t'
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : Text('$label · ${formatMoney(plan.prices[t]!, currency)}'),
                ),
          ],
        ),
      ],
    ),
  );
}

/// A one-line summary on the consult screen: credits left, or that the clinician's own key is in use.
class CreditsStrip extends ConsumerWidget {
  const CreditsStrip({super.key, required this.reportType});

  final String reportType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(billingStatusProvider).value;
    if (s == null || !s.enabled) return const SizedBox.shrink();
    final ownKey = reportType == 'guided' && ref.watch(useOwnKeyProvider) && s.ownKey.usable;
    final left = reportType == 'guided' ? s.guidedCredits : s.directCredits;
    final text = ownKey
        ? 'Writing with your own Anthropic key (…${s.ownKey.last4})'
        : left == 0
        ? 'No ${reportType == 'guided' ? 'AI-Guided' : 'quick consult'} report credits left'
        : '$left ${reportType == 'guided' ? 'AI-Guided' : 'quick consult'} report credit${left == 1 ? '' : 's'} left';
    return Semantics(
      button: true,
      label: '$text. Open plans and credits.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/pricing'),
        child: NoticeBanner(
          icon: ownKey ? Icons.key_rounded : Icons.confirmation_number_outlined,
          tone: left == 0 && !ownKey ? Tone.check : Tone.brand,
          text: '$text · Plans & credits ›',
        ),
      ),
    );
  }
}

/// A direct consult was refused before anything was written: no credit, or the clinician's own key
/// failed. The case text is still on the consult screen.
class NoCreditScreen extends ConsumerWidget {
  const NoCreditScreen({super.key, required this.error});

  final ApiException? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownKey = ref.watch(billingStatusProvider).value?.ownKey;
    return switch (error) {
      OwnKeyFailed(:final message, :final retry) => StatusPage(
        icon: Icons.key_off_rounded,
        tone: Tone.check,
        title: "Your Anthropic key couldn't be used",
        message: message,
        actions: [
          FilledButton(
            onPressed: () => context.pushReplacement('/pricing/own-key'),
            child: const Text('Manage my key'),
          ),
          OutlinedButton(
            onPressed: () {
              ref.read(useOwnKeyProvider.notifier).set(false);
              context.go('/consult');
            },
            child: const Text('Write without my key'),
          ),
          TextButton(
            onPressed: () => context.go('/consult'),
            child: Text(retry ? 'Back to my case (try again later)' : 'Back to my case'),
          ),
        ],
        children: const [
          NoticeBanner(
            icon: Icons.shield_outlined,
            text: "Nothing was written and nothing was charged. We never switch to the platform's key without asking you.",
          ),
        ],
      ),
      PlanRequired(:final message) => StatusPage(
        icon: Icons.lock_outline_rounded,
        tone: Tone.brand,
        title: 'Not in your plan',
        message: message,
        actions: [
          FilledButton(onPressed: () => context.pushReplacement('/pricing'), child: const Text('See plans')),
          TextButton(onPressed: () => context.go('/consult'), child: const Text('Back to my case')),
        ],
      ),
      PaymentRequired(:final message, :final reportType) => StatusPage(
        icon: Icons.confirmation_number_outlined,
        tone: Tone.brand,
        title: 'No report credits left',
        message: message,
        actions: [
          FilledButton(onPressed: () => context.pushReplacement('/pricing'), child: const Text('See plans')),
          if (reportType == 'guided' && ownKey?.usable == true)
            OutlinedButton(
              onPressed: () {
                ref.read(useOwnKeyProvider.notifier).set(true);
                context.go('/consult');
              },
              child: const Text('Use my own Anthropic key'),
            ),
          TextButton(onPressed: () => context.go('/consult'), child: const Text('Back to my case')),
        ],
        children: const [
          NoticeBanner(
            icon: Icons.edit_note_rounded,
            text: 'Your case is still on the consult screen. Nothing was charged.',
          ),
        ],
      ),
      _ => StatusPage(
        icon: Icons.error_outline_rounded,
        tone: Tone.check,
        title: "Couldn't write the report",
        message: error is BillingRefused ? (error as BillingRefused).message : 'Please try again.',
        actions: [OutlinedButton(onPressed: () => context.go('/consult'), child: const Text('Back to my case'))],
      ),
    };
  }
}
