import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_models.dart';
import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../consult/consult_controller.dart';
import '../consultation/consultation_controller.dart';
import 'info_screen.dart';

const _roles = {
  'counsellor_trainee': 'Counsellor or trainee',
  'psychologist': 'Psychologist',
  'psychiatrist': 'Psychiatrist',
};

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Wipe the in-memory consult and reply before leaving.
    ref.read(consultControllerProvider.notifier).clear();
    ref.read(consultationControllerProvider.notifier).clear();
    await ref.read(authServiceProvider).signOut();
    ref.invalidate(meProvider);
    if (context.mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        gap: 16,
        children: [
          const PageHeading('Account'),
          AppCard(
            child: me.when(
              data: (m) => _Profile(me: m),
              loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
              error: (_, _) => Row(
                children: [
                  const Expanded(child: Text("Couldn't load your profile.", style: AppText.smallMuted)),
                  TextButton(onPressed: () => ref.invalidate(meProvider), child: const Text('Retry')),
                ],
              ),
            ),
          ),
          _LinkGroup(
            links: [
              if (me.value != null && !me.value!.needsProfile) ('Edit profile', () => context.push('/account/profile')),
              if (me.value?.isAdmin == true) ('Admin: registrations and reports', () => context.push('/admin')),
              ('How we protect client data', () => context.push('/privacy')),
              ('Crisis numbers', () => context.push('/safety')),
              ('Clinician Terms', () => context.push('/terms')),
              ('Data Processing Agreement', () => context.push('/dpa')),
              ('Contact the clinical safety team', () => contactSafetyTeam(context)),
              if (AppConfig.previewMode) ('Design preview: all screens', () => context.push('/gallery')),
            ],
          ),
          OutlinedButton(
            onPressed: () => _signOut(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.crisis,
              side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Sign out'),
          ),
          Column(
            children: [
              const BrandMark(size: 36),
              const SizedBox(height: 4),
              Text('Version 1.0.0 · ${AppConfig.mode.name} build', style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context) {
    final role = _roles[me.role] ?? 'Clinician';
    final status = me.isVerified ? 'Verified · ${me.level}' : (me.isRejected ? 'Not verified' : 'Being checked');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.fullName ?? role, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (me.fullName != null) Text(role, style: AppText.smallMuted),
              if (me.registrationBody != null && me.registrationBody != 'none')
                Text('${me.registrationBody} registration', style: AppText.caption),
            ],
          ),
        ),
        StatusPill(
          status,
          icon: me.isVerified ? Icons.check_rounded : Icons.schedule_rounded,
          tone: me.isVerified ? Tone.brand : Tone.check,
        ),
      ],
    );
  }
}

class _LinkGroup extends StatelessWidget {
  const _LinkGroup({required this.links});

  final List<(String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (final (i, (label, onTap)) in links.indexed) ...[
            if (i > 0) const Divider(),
            ListTile(
              minTileHeight: 52,
              title: Text(label, style: const TextStyle(fontSize: 15)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: onTap,
            ),
          ],
        ],
      ),
    );
  }
}
