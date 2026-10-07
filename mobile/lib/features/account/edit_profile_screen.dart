import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/content/safety_content.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

/// Account → Edit profile. Name, gender and age change straight away. A changed role or
/// registration number goes back to the verification team (after a warning): the level is
/// only ever set by an admin who has checked the register.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: me.when(
        data: (m) => _EditForm(me: m),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(onPressed: () => ref.invalidate(meProvider), child: const Text("Couldn't load. Retry")),
        ),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.me});

  final Me me;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final _name = TextEditingController(text: widget.me.fullName ?? '');
  late final _age = TextEditingController(text: widget.me.age?.toString() ?? '');
  late final _registration = TextEditingController(text: widget.me.registrationNumber ?? '');
  late String? _gender = widget.me.gender;
  late ClinicianRole _role = ClinicianRole.values.firstWhere(
    (r) => r.apiValue == widget.me.role,
    orElse: () => ClinicianRole.psychologist,
  );
  bool _busy = false;
  String? _error;

  int? get _ageValue {
    final a = int.tryParse(_age.text.trim());
    return a != null && a >= 18 && a <= 100 ? a : null;
  }

  String? get _registrationValue => _role.needsRegistration ? _registration.text.trim() : null;

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _gender != null &&
      _ageValue != null &&
      (!_role.needsRegistration || _registration.text.trim().isNotEmpty);

  /// Role or registration differ from what was verified.
  bool get _professionalChange =>
      _role.apiValue != widget.me.role ||
      _role.registrationBody != (widget.me.registrationBody ?? 'none') ||
      (_registrationValue ?? '') != (widget.me.registrationNumber ?? '');

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _registration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_professionalChange && widget.me.verificationStatus != 'none') {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Send for verification again?'),
          content: const Text(
            'You changed your role or registration. Our team checks it on the official register again '
            'before you can consult. Until then your level is removed and consults are paused.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send for verification')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(profileRepositoryProvider)
          .edit(
            ProfileEdit(
              fullName: _name.text.trim(),
              gender: _gender!,
              age: _ageValue!,
              role: _role.apiValue,
              registrationBody: _role.registrationBody,
              registrationNumber: _registrationValue,
            ),
          );
      ref.invalidate(meProvider);
      if (!mounted) return;
      if (result.reverify) {
        context.go('/pending');
      } else {
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Profile saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is NetworkProblem
              ? "Couldn't reach Your Counselor. Check your connection and try again."
              : "Couldn't save your profile. Please try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      actions: [
        FilledButton(onPressed: _valid && !_busy ? _save : null, child: Text(_busy ? 'Saving…' : 'Save changes')),
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Full name', style: AppText.label),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('profile-name'),
              controller: _name,
              maxLength: 100,
              autocorrect: false,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'As on your registration', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('Gender', style: AppText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in kGenders.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _gender == e.key,
                    onSelected: (_) => setState(() => _gender = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Age', style: AppText.label),
            const SizedBox(height: 8),
            SizedBox(
              width: 140,
              child: TextField(
                key: const ValueKey('profile-age'),
                controller: _age,
                maxLength: 3,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'Years',
                  counterText: '',
                  errorText: _age.text.isNotEmpty && _ageValue == null ? '18 to 100' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Only our verification team sees these. They are never sent to the AI.', style: AppText.caption),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('I am a', style: AppText.label),
            const SizedBox(height: 8),
            for (final role in ClinicianRole.values) ...[
              ChoiceCard(
                title: role.label,
                subtitle: role.detail,
                selected: _role == role,
                onTap: () => setState(() => _role = role),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
        if (_role.needsRegistration)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${_role.registrationBody} registration number', style: AppText.label),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('profile-registration'),
                controller: _registration,
                maxLength: 40,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'As shown on the register', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        if (_professionalChange && widget.me.verificationStatus != 'none')
          const NoticeBanner(
            icon: Icons.verified_user_outlined,
            text: 'A changed role or registration is checked again before you can consult.',
            tone: Tone.check,
          ),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.crisis)),
      ],
    );
  }
}
