import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../consult/consult_controller.dart';
import '../consultation/consultation_controller.dart';

/// Account → Delete account. Says what goes and what stays, asks the clinician to type DELETE,
/// then deletes the account on the server and signs out.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _typed => _confirm.text.trim() == 'DELETE';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(deleteAccountProvider)();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = switch (e) {
            BillingRefused(:final message) => message,
            NetworkProblem() => "Couldn't reach Your Counselor. Check your connection and try again.",
            _ => "Couldn't delete your account. Please try again.",
          };
        });
      }
      return;
    }
    // The account is gone on the server: wipe what is in memory and sign out on this phone.
    ref.read(consultControllerProvider.notifier).clear();
    ref.read(consultationControllerProvider.notifier).clear();
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // The sign-in no longer exists on the server; the local session is cleared either way.
    }
    ref.invalidate(meProvider);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.go('/welcome');
    messenger.showSnackBar(const SnackBar(content: Text('Your account has been deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        actions: [
          FilledButton(
            key: const ValueKey('delete-account'),
            onPressed: _typed && !_busy ? _delete : null,
            style: FilledButton.styleFrom(backgroundColor: AppColors.crisis),
            child: Text(_busy ? 'Deleting…' : 'Delete my account'),
          ),
        ],
        children: [
          const NoticeBanner(
            icon: Icons.warning_amber_rounded,
            tone: Tone.check,
            text: "Deleting your account can't be undone. You will be signed out straight away.",
          ),
          const _Section('What is deleted', [
            'Your sign-in and email address.',
            'Your name, gender, age, registration number and verification level.',
            'Your own AI key, if you added one.',
            "Your booking page, working hours, time off and appointments, including your clients' names "
                'and emails.',
            'Your consult history and any running plan or credits.',
          ]),
          const _Section('What is kept', [
            'Payment records (plan, amount, date), for as long as tax law requires.',
            'The de-identified consult text and safety-review records, for the 12-month beta retention period '
                '(longer only while a safety report is open). They no longer carry your name or email.',
          ]),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Type DELETE to confirm', style: AppText.label),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('delete-confirm'),
                controller: _confirm,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'DELETE'),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(icon: Icons.error_outline_rounded, tone: Tone.check, text: _error!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.items);

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: AppText.smallMuted),
                  Expanded(child: Text(item, style: const TextStyle(fontSize: 14, height: 1.45))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
