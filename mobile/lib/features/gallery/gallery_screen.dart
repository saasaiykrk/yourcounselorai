import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/safety_content.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../consult/check_sheet.dart';
import '../consult/report_sheet.dart';

/// Preview builds only: jump to any screen for design review.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  static const routes = <(String, String, String)>[
    ('Onboarding', '00 · Splash', '/'),
    ('Onboarding', '01 · Welcome', '/welcome'),
    ('Onboarding', '02 · Sign in', '/sign-in'),
    ('Onboarding', '03 · Email code', '/code'),
    ('Onboarding', '04 · Professional details', '/details'),
    ('Onboarding', '05 · Verification pending', '/pending'),
    ('Consult', '06 · New consult', '/consult'),
    ('Consult', '08 · Drafting', '/drafting'),
    ('Consult', '09 · Reply', '/reply'),
    ('Safety & errors', '11 · Risk detected', '/safety'),
    ('Safety & errors', '12 · Reply held back', '/held-back'),
    ('Safety & errors', '13 · Identifier found', '/identifiers'),
    ('Safety & errors', '14 · Daily limit', '/limit'),
    ('Safety & errors', '15 · Connection problem', '/offline'),
    ('Account', '16 · Account', '/account'),
    ('History', '17 · History', '/history'),
  ];

  @override
  Widget build(BuildContext context) {
    String? group;
    final tiles = <Widget>[];
    for (final (g, label, path) in routes) {
      if (g != group) {
        group = g;
        tiles.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
            child: Text(g.toUpperCase(), style: AppText.overline),
          ),
        );
      }
      tiles.add(
        ListTile(
          title: Text(label),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(path),
        ),
      );
      if (path == '/consult') {
        tiles.add(
          ListTile(
            title: const Text('07 · Check before sending (panel)'),
            trailing: const Icon(Icons.expand_less_rounded),
            onTap: () => showCheckSheet(context, text: '', mode: ConsultMode.auto),
          ),
        );
      }
      if (path == '/reply') {
        tiles.add(
          ListTile(
            title: const Text('10 · Report a problem (panel)'),
            trailing: const Icon(Icons.expand_less_rounded),
            onTap: () => showReportSheet(context),
          ),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Design preview',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.deepPurple),
        ),
      ),
      body: ListView(children: tiles),
    );
  }
}
