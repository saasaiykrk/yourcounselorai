import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Meaning-carrying tones. Brand pink is never a tone: it is not a status colour.
enum Tone {
  brand(AppColors.lavender, AppColors.royalPurple),
  check(AppColors.checkBg, AppColors.checkInk),
  crisis(AppColors.crisisBg, AppColors.crisis),
  neutral(AppColors.quiet, AppColors.quietInk);

  const Tone(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// A white card with a soft border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
    this.borderColor = AppColors.line,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: child,
    );
  }
}

/// Rounded square holding an icon, used at the top of state screens.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.tone = Tone.brand, this.size = 60});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.background, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: tone.foreground, size: size * 0.5),
    );
  }
}

/// Small rounded label such as "Passed", "Provisional" or "Missing".
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = Tone.brand, this.icon, this.uppercase = false});

  final String label;
  final Tone tone;
  final IconData? icon;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: tone.background, borderRadius: BorderRadius.circular(uppercase ? 6 : 999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: tone.foreground), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              uppercase ? label.toUpperCase() : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: uppercase ? 12 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: uppercase ? 0.6 : 0,
                color: tone.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted strip with an icon and a sentence.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.icon, required this.text, this.tone = Tone.brand});

  final IconData icon;
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: tone.background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, height: 1.45, color: tone.foreground)),
          ),
        ],
      ),
    );
  }
}
