import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const used = 12;
    const limit = AppConfig.dailyConsultLimit;

    return Scaffold(
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        gap: 16,
        children: [
          const PageHeading('Account'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Psychologist', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          Text('RCI · [registration number]', style: AppText.caption),
                        ],
                      ),
                    ),
                    StatusPill('Verified · L2', icon: Icons.check_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(child: Text('Consults in the last 24 hours', style: AppText.smallMuted)),
                    Text('$used / $limit', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    value: used / limit,
                    minHeight: 6,
                    color: AppColors.royalPurple,
                    backgroundColor: AppColors.lineSoft,
                  ),
                ),
              ],
            ),
          ),
          _LinkGroup(
            links: [
              ('How we protect client data', () {}),
              ('Crisis numbers', () => context.push('/safety')),
              ('Clinician Terms', () {}),
              ('Data Processing Agreement', () {}),
              ('Contact the clinical safety team', () {}),
              if (AppConfig.previewMode) ('Design preview: all screens', () => context.push('/gallery')),
            ],
          ),
          OutlinedButton(
            onPressed: () => context.go('/welcome'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.crisis,
              side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Sign out'),
          ),
          const Column(
            children: [
              BrandMark(size: 36),
              SizedBox(height: 4),
              Text('Version 1.0.0 (preview) · Knowledge base 2.1.1', style: AppText.caption),
            ],
          ),
        ],
      ),
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
