import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content/legal_content.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/safety_widgets.dart';
import '../../core/widgets/surfaces.dart';

/// Account → privacy, Clinician Terms and Data Processing Agreement.
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key, required this.doc});

  final InfoDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        gap: 14,
        children: [
          if (doc.draft)
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill('Beta draft', tone: Tone.check, icon: Icons.edit_note_rounded, uppercase: true),
            ),
          PageHeading(doc.title, message: doc.intro),
          if (doc.draft) const Text(kDraftNotice, style: AppText.smallMuted),
          for (final s in doc.sections)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(s.heading, style: AppText.sectionTitle)),
                  const SizedBox(height: 8),
                  for (final p in s.points) _Point(p),
                ],
              ),
            ),
          if (identical(doc, kTermsDoc)) const DisclaimerBlock(),
          TextButton.icon(
            onPressed: () => contactSafetyTeam(context),
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Questions? Contact the clinical safety team'),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8, right: 10),
            child: Icon(Icons.circle, size: 6, color: AppColors.royalPurple),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.5))),
        ],
      ),
    );
  }
}

/// Opens the mail app addressed to the safety team. If there is no mail app,
/// shows the address with a copy button. Nothing about a case is pre-filled.
Future<void> contactSafetyTeam(BuildContext context) async {
  final uri = Uri(
    scheme: 'mailto',
    path: kSafetyEmail,
    query:
        'subject=${Uri.encodeComponent('Your Counselor: clinical safety')}'
        '&body=${Uri.encodeComponent('(Please do not include client names or other identifiers.)\n\n')}',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Contact the clinical safety team'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email us at:'),
          SizedBox(height: 6),
          SelectableText(kSafetyEmail, style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 12),
          Text('Never include client names or other identifiers in an email.', style: AppText.smallMuted),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: kSafetyEmail));
            Navigator.of(ctx).pop();
          },
          child: const Text('Copy address'),
        ),
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
      ],
    ),
  );
}
