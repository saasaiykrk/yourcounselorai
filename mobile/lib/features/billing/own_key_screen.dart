import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/providers.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

/// "Use My Anthropic API Key". The key is typed here, sent once to the server over HTTPS, checked
/// with Anthropic, and stored encrypted there. The phone never stores it, and only its last 4
/// characters are ever shown again. Screenshots are blocked on this screen.
class OwnKeyScreen extends ConsumerStatefulWidget {
  const OwnKeyScreen({super.key});

  @override
  ConsumerState<OwnKeyScreen> createState() => _OwnKeyScreenState();
}

class _OwnKeyScreenState extends ConsumerState<OwnKeyScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  bool _replacing = false;
  String? _error;

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on BillingRefused catch (e) {
      _error = e.message;
    } on NetworkProblem {
      _error = "Couldn't reach Your Counselor. Check your connection and try again.";
    } on ApiException {
      _error = 'Something went wrong. Try again.';
    } finally {
      ref.invalidate(billingStatusProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final key = _key.text.trim();
    if (!key.startsWith('sk-ant-') || key.length < 40) {
      throw const BillingRefused(
        code: 'format',
        message: 'That does not look like an Anthropic API key (it starts with sk-ant-).',
      );
    }
    final r = await ref.read(billingRepositoryProvider).saveOwnKey(key);
    _key.clear();
    _replacing = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Key checked and saved (…${r.last4}).')));
    }
  });

  Future<void> _check() => _run(() async {
    final r = await ref.read(billingRepositoryProvider).checkOwnKey();
    if (r.status != 'valid' || r.message != null) {
      _error = r.message ?? 'Anthropic did not accept this key.';
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your key works.')));
    }
  });

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove your key?'),
        content: const Text('It is deleted from our server. AI-Guided reports then need report credits.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(billingRepositoryProvider).removeOwnKey();
      ref.read(useOwnKeyProvider.notifier).set(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(billingStatusProvider);
    final plan = ref.watch(billingPlansProvider).value?.plans.where((p) => p.id == 'byok_scale').firstOrNull;
    final use = ref.watch(useOwnKeyProvider);
    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Your Anthropic API key')),
        body: status.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(onPressed: () => ref.invalidate(billingStatusProvider), child: const Text('Try again')),
          ),
          data: (s) {
            final k = s.ownKey;
            if (!k.available) {
              return const PageBody(
                children: [
                  PageHeading('Not available', message: 'Using your own Anthropic key is not offered right now.'),
                ],
              );
            }
            final showForm = !k.connected || _replacing;
            final instructions = plan?.instructions.isNotEmpty == true ? plan!.instructions : k.instructions;
            return PageBody(
              gap: 14,
              children: [
                const PageHeading(
                  'Your Anthropic API key',
                  message:
                      'AI-Guided reports are written with your key, and Anthropic bills you for that use directly.',
                ),
                if (instructions.isNotEmpty) Text(instructions, style: AppText.small),
                _Facts(included: k.included, planName: plan?.name ?? 'BYOK Scale'),
                if (!k.included)
                  FilledButton(
                    onPressed: () => context.push('/pricing'),
                    child: Text('Choose ${plan?.name ?? 'BYOK Scale'} to use your key'),
                  ),
                if (k.connected)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Key ending …${k.last4}', style: AppText.label)),
                            StatusPill(
                              k.status == 'valid' ? 'Working' : 'Not working',
                              tone: k.status == 'valid' ? Tone.brand : Tone.check,
                            ),
                          ],
                        ),
                        if (k.status != 'valid' && k.lastError != null) ...[
                          const SizedBox(height: 6),
                          Text(_reason(k.lastError!), style: AppText.smallMuted),
                        ],
                        const SizedBox(height: 6),
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: use && k.usable,
                            onChanged: k.usable ? (v) => ref.read(useOwnKeyProvider.notifier).set(v) : null,
                            title: const Text('Write my AI-Guided reports with this key'),
                            subtitle: const Text('If it fails, nothing is written with the platform key instead.'),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(onPressed: _busy ? null : _check, child: const Text('Check again')),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _replacing = true),
                              child: const Text('Replace key'),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _remove,
                              style: TextButton.styleFrom(foregroundColor: AppColors.crisis),
                              child: const Text('Remove key'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (showForm) ...[
                  TextField(
                    controller: _key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const <String>[],
                    decoration: const InputDecoration(labelText: 'Anthropic API key', hintText: 'sk-ant-…'),
                    onSubmitted: (_) => _save(),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('Check and save'),
                  ),
                ],
                if (_error != null) NoticeBanner(icon: Icons.error_outline_rounded, tone: Tone.check, text: _error!),
                const NoticeBanner(
                  icon: Icons.lock_outline_rounded,
                  text:
                      'Your key is checked with Anthropic, stored encrypted on our server and never shown again — only '
                      'its last 4 characters. It is never stored on this phone. Case text is still cleaned of '
                      'identifiers before anything is sent.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _reason(String code) => switch (code) {
    'invalid_key' => 'Anthropic did not accept this key.',
    'no_access' => 'This key cannot use the model the app needs.',
    _ => 'The last check failed.',
  };
}

class _Facts extends StatelessWidget {
  const _Facts({required this.included, required this.planName});

  final bool included;
  final String planName;

  @override
  Widget build(BuildContext context) {
    final lines = [
      included
          ? 'Your plan, $planName, includes reports with your own key.'
          : 'Using your own key is part of $planName.',
      'AI-Guided reports with your key are unlimited and use no report credits.',
      'Quick consults are bought per report.',
    ];
    return AppCard(
      color: AppColors.lavender,
      borderColor: AppColors.lavender,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $l', style: AppText.small),
            ),
        ],
      ),
    );
  }
}
