import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/billing_models.dart';
import '../../core/billing/purchase.dart';
import '../../core/education/education_repository.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';

enum _Choice { buy, plans }

/// A locked "Print / Save as PDF": printing comes with a subscription; or, when the admin sells
/// it, a single print of this page. Returns true once the SERVER has confirmed the payment
/// (the page must then be loaded again, so the server unlocks it).
Future<bool> unlockPrinting(BuildContext context, WidgetRef ref, EducationPage page, PrintOffer? offer) async {
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => PrintOfferSheet(offer: offer),
  );
  if (!context.mounted || choice == null) return false;
  if (choice == _Choice.plans) {
    context.push('/pricing');
    return false;
  }
  final flow = PurchaseFlow(ref.read(billingRepositoryProvider), ref.read(paymentGatewayProvider));
  final outcome = await flow.buy(plan: 'print', item: page.slug);
  ref.invalidate(educationPagesProvider);
  ref.invalidate(billingStatusProvider);
  if (!context.mounted) return outcome is PurchaseDone;
  final hours = offer?.hours ?? 24;
  final messenger = ScaffoldMessenger.of(context);
  switch (outcome) {
    case PurchaseDone():
      messenger.showSnackBar(
        SnackBar(content: Text("Payment received. You can print this module's handouts for $hours hours.")),
      );
    case PurchaseCancelled():
      messenger.showSnackBar(const SnackBar(content: Text('Payment cancelled. Nothing was charged.')));
    case PurchasePending():
      await _tell(
        context,
        'Waiting for the bank',
        'Your payment is still being confirmed. Open the page again in a few minutes to print it. '
            "You won't be charged twice.",
      );
    case PurchaseFailed(:final message):
      await _tell(context, 'Payment not completed', message);
  }
  return outcome is PurchaseDone;
}

Future<void> _tell(BuildContext context, String title, String message) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
  ),
);

/// What unlocks printing: any subscription, or (when on sale) a single print of this page.
class PrintOfferSheet extends StatelessWidget {
  const PrintOfferSheet({super.key, this.offer});

  final PrintOffer? offer;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                IconTile(icon: Icons.print_outlined, size: 44),
                SizedBox(width: 12),
                Expanded(child: Text('Print / Save as PDF', style: AppText.sheetTitle)),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Included with every subscription, for every page.', style: AppText.bodyMuted),
            if (o != null) ...[
              const SizedBox(height: 18),
              Text('Just this module', style: AppText.label.copyWith(fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                'Print or save its handouts and worksheets as PDF, as often as you need, for ${o.hours} hours.',
                style: AppText.smallMuted,
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, _Choice.buy),
                child: Text('Buy for ${formatMoney(o.price, o.currency)}'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(context, _Choice.plans),
              child: const Text('See subscriptions'),
            ),
          ],
        ),
      ),
    );
  }
}
