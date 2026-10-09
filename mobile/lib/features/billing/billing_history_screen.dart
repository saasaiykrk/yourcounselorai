import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/billing_models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';

final _ordersProvider = FutureProvider.autoDispose<List<BillingOrder>>(
  (ref) => ref.watch(billingRepositoryProvider).orders(),
);
final _ledgerProvider = FutureProvider.autoDispose<List<LedgerEntry>>(
  (ref) => ref.watch(billingRepositoryProvider).ledger(),
);

String _when(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _planName(String plan, String? type) => switch (plan) {
  'per_report' => '${reportTypeLabel(type)} (single)',
  'sub_30' => 'Monthly · 30 reports',
  'sub_50' => 'Monthly · 50 reports',
  'byok' => 'Own-key access fee',
  _ => plan,
};

/// Payments and credit movements, newest first.
class BillingHistoryScreen extends ConsumerWidget {
  const BillingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(_ordersProvider);
    final ledger = ref.watch(_ledgerProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Payments'),
              Tab(text: 'Credits'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            orders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _retry(() => ref.invalidate(_ordersProvider)),
              data: (list) => list.isEmpty
                  ? const _Empty('No payments yet.')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _OrderTile(list[i]),
                    ),
            ),
            ledger.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _retry(() => ref.invalidate(_ledgerProvider)),
              data: (list) {
                // "Held" and its matching "used"/"returned" are one event to a clinician.
                final shown = list.where((l) => l.kind != 'reserve').toList();
                return shown.isEmpty
                    ? const _Empty('No credit changes yet.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final l = shown[i];
                          final amount = l.kind == 'release'
                              ? '+${l.amount}'
                              : (l.amount > 0 ? '+${l.amount}' : '${l.amount}');
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l.label),
                            subtitle: Text(
                              [
                                _when(l.createdAt),
                                if (l.reportType != null) reportTypeLabel(l.reportType),
                                if (l.kind == 'adjust' && l.reason != null) l.reason!,
                              ].join(' · '),
                            ),
                            trailing: Text(amount, style: AppText.label),
                          );
                        },
                      );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _retry(VoidCallback onRetry) => Center(
    child: TextButton(onPressed: onRetry, child: const Text("Couldn't load. Try again")),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, style: AppText.bodyMuted),
    ),
  );
}

class _OrderTile extends StatelessWidget {
  const _OrderTile(this.o);

  final BillingOrder o;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (o.status) {
      'paid' => ('Paid', Tone.brand),
      'pending' => ('Being confirmed', Tone.check),
      'failed' => ('Failed', Tone.crisis),
      'cancelled' => ('Cancelled', Tone.neutral),
      _ => ('Not completed', Tone.neutral),
    };
    final refund = switch (o.refundStatus) {
      'refunded' => 'Refunded ${formatMoney(o.refundedAmount, o.currency)}',
      'partial' => 'Partly refunded ${formatMoney(o.refundedAmount, o.currency)}',
      'pending' => 'Refund in progress',
      'failed' => 'Refund failed — contact us',
      _ => null,
    };
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_planName(o.plan, o.reportType), style: AppText.label),
                const SizedBox(height: 2),
                Text(
                  [
                    _when(o.paidAt ?? o.createdAt),
                    ?refund,
                    if (o.status == 'failed' && o.failureReason != null) o.failureReason!,
                  ].join(' · '),
                  style: AppText.smallMuted,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(o.amount, o.currency), style: AppText.label),
              const SizedBox(height: 4),
              StatusPill(label, tone: tone),
            ],
          ),
        ],
      ),
    );
  }
}
