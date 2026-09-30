import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The "C-Y" mark from the logo.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// The full logo with wordmark and tagline. Light backgrounds only.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 280});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo_full.png',
      width: width,
      fit: BoxFit.contain,
      semanticLabel: 'Your Counselor: where counseling meets technology',
    );
  }
}

/// "Your" in brand pink, "Counselor" in deep purple, as in the logo.
/// Pink is only used at this large, heavy size, where it meets contrast rules.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 21});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: 'Nunito', fontSize: fontSize, fontWeight: FontWeight.w900, letterSpacing: -0.2);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Your ',
            style: base.copyWith(color: AppColors.brandPink),
          ),
          TextSpan(
            text: 'Counselor',
            style: base.copyWith(color: AppColors.deepPurple),
          ),
        ],
      ),
      semanticsLabel: 'Your Counselor',
    );
  }
}
