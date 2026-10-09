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

/// Plans & credits. Every plan, price and feature shown here comes from the server (the admin's
/// pricing); nothing is hardcoded. A purchase counts only once the server has confirmed it.
class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  String? _busy; // which button is working: "<plan>:<type>"

  Future<void> _buy(PlanOffer plan, {String? reportType}) async {
    if (_busy != null) return;
    setState(() => _busy = '${plan.id}:${reportType ?? ''}');
    final flow = PurchaseFlow(ref.read(billingRepositoryProvider), ref.read(paymentGatewayProvider));
    final outcome = await flow.buy(plan: plan.id, reportType: reportType);
    if (!mounted) return;
    setState(() => _busy = null);
    ref.invalidate(billingStatusProvider);
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case PurchaseDone():
        messenger.showSnackBar(const SnackBar(content: Text('Payment received. Your plan is ready to use.')));
      case PurchaseCancelled():
        messenger.showSnackBar(const SnackBar(content: Text('Payment cancelled. Nothing was charged.')));
      case PurchasePending():
        await _tell(
          'Waiting for the bank',
          'Your payment is still being confirmed. Your credits appear here as soon as Razorpay confirms it. '
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (!p.enabled) ...[
          const PageHeading(
            'Reports are free right now',
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
          const SizedBox(height: 22),
          const Text('Plans', style: AppText.sectionTitle),
          const SizedBox(height: 10),
          for (final plan in p.plans) ...[
            _PlanCard(
              plan: plan,
              currency: p.currency,
              status: s,
              canPay: p.paymentsAvailable,
              busy: _busy,
              onBuy: (type) => _buy(plan, reportType: type),
            ),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 4),
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

/// The clinician's credits and current plan.
class CreditsCard extends StatelessWidget {
  const CreditsCard({super.key, required this.status});

  final BillingStatus status;

  @override
  Widget build(BuildContext context) {
    final sub = status.activeSubscription;
    final key = status.ownKey;
    return AppCard(
      color: AppColors.lavender,
      borderColor: AppColors.lavender,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your credits', style: AppText.label),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Count(label: 'Guided reports', value: status.guidedCredits),
              ),
              Expanded(
                child: _Count(label: 'Direct reports', value: status.directCredits),
              ),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 12),
            Text(
              '${sub.remaining} of ${sub.creditsTotal} plan reports left · ends ${_day(sub.expiresAt)}',
              style: AppText.smallMuted,
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.currency,
    required this.status,
    required this.canPay,
    required this.busy,
    required this.onBuy,
  });

  final PlanOffer plan;
  final String currency;
  final BillingStatus? status;
  final bool canPay;
  final String? busy;
  final void Function(String? reportType) onBuy;

  Widget _button(String label, String? type, {bool primary = true}) {
    final working = busy == '${plan.id}:${type ?? ''}';
    final child = working
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
        : Text(label);
    final onPressed = busy == null && canPay ? () => onBuy(type) : null;
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final current = status?.activeSubscription?.plan == plan.id;
    final (headline, detail) = switch (plan.kind) {
      'per_report' => (
        'From ${formatMoney(plan.prices.values.fold<int>(1 << 30, (a, b) => a < b ? a : b), currency)}',
        'per report',
      ),
      'subscription' => (formatMoney(plan.price ?? 0, currency), '${plan.reports} reports · ${plan.durationDays} days'),
      _ => (
        (plan.fee ?? 0) == 0 ? 'No platform fee' : formatMoney(plan.fee!, currency),
        (plan.fee ?? 0) == 0
            ? 'Anthropic bills you directly'
            : 'for ${plan.feeDays} days · Anthropic bills you directly',
      ),
    };
    return AppCard(
      borderColor: current ? AppColors.royalPurple : AppColors.line,
      borderWidth: current ? 1.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: AppText.sectionTitle)),
              if (current) const StatusPill('Your plan', icon: Icons.check_rounded),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: headline,
                  style: AppText.screenTitle.copyWith(fontSize: 24, color: AppColors.deepPurple),
                ),
                TextSpan(text: '  $detail', style: AppText.smallMuted),
              ],
            ),
          ),
          if (plan.description.isNotEmpty) ...[const SizedBox(height: 6), Text(plan.description, style: AppText.small)],
          for (final f in plan.features)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.doneInk),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: AppText.small)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (plan.kind == 'per_report')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const ['guided', 'direct'])
                  if (plan.prices[t] != null)
                    _button('${reportTypeLabel(t)} · ${formatMoney(plan.prices[t]!, currency)}', t),
              ],
            )
          else if (plan.kind == 'subscription')
            _button(
              current
                  ? 'Renew for ${formatMoney(plan.price ?? 0, currency)}'
                  : 'Buy for ${formatMoney(plan.price ?? 0, currency)}',
              null,
            )
          else
            OutlinedButton(
              onPressed: () => GoRouter.of(context).push('/pricing/own-key'),
              child: Text(status?.ownKey.connected == true ? 'Manage my key' : 'Set up my key'),
            ),
        ],
      ),
    );
  }
}

/// A one-line summary on the consult screen: credits left, or that the clinician's own key is in use.
class CreditsStrip extends ConsumerWidget {
  const CreditsStrip({super.key, required this.reportType});

  final String reportType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(billingStatusProvider).value;
    if (s == null || !s.enabled) return const SizedBox.shrink();
    final ownKey = ref.watch(useOwnKeyProvider) && s.ownKey.usable;
    final left = reportType == 'guided' ? s.guidedCredits : s.directCredits;
    final text = ownKey
        ? 'Writing with your own Anthropic key (…${s.ownKey.last4})'
        : left == 0
        ? 'No ${reportType == 'guided' ? 'guided' : 'direct'} report credits left'
        : '$left ${reportType == 'guided' ? 'guided' : 'direct'} report credit${left == 1 ? '' : 's'} left';
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
      PaymentRequired(:final message, :final plan) => StatusPage(
        icon: Icons.confirmation_number_outlined,
        tone: Tone.brand,
        title: plan == 'byok' ? 'Access fee needed' : 'No report credits left',
        message: message,
        actions: [
          FilledButton(onPressed: () => context.pushReplacement('/pricing'), child: const Text('See plans')),
          if (plan != 'byok' && ownKey?.usable == true)
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
