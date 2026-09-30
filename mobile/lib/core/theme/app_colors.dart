import 'package:flutter/material.dart';

/// Brand and UI colours for Your Counselor.
///
/// Brand values were measured from the approved logo. Safety colours are
/// deliberately kept away from the brand pink so a crisis state is never
/// mistaken for decoration.
abstract final class AppColors {
  // Brand (from the logo)
  static const deepPurple = Color(0xFF3F0079); // "Counselor" wordmark: headings
  static const royalPurple = Color(0xFF6A11BA); // the "C": actions, links, selection
  static const violet = Color(0xFF8C0FD0); // logo highlight only
  static const orchid = Color(0xFFC73EE7); // logo shine only
  static const brandPink = Color(0xFFE83C7D); // "Your": large text and graphics only
  static const berry = Color(0xFFC31B6A); // pink for small text (passes 4.5:1)
  static const taglineGrey = Color(0xFF545454);

  // Surfaces and text
  static const background = Color(0xFFFAF7FD);
  static const surface = Color(0xFFFFFFFF);
  static const lavender = Color(0xFFF1E7FB);
  static const pinkTint = Color(0xFFFCE6EF);
  static const line = Color(0xFFE6DDF0);
  static const lineSoft = Color(0xFFEFE8F6);
  static const inputBorder = Color(0xFFD9CCE8);
  static const pendingRing = Color(0xFFD3C4E6);
  static const ink = Color(0xFF1E1030);
  static const inkSoft = Color(0xFF3B2A55);
  static const muted = Color(0xFF5A5068);
  static const quiet = Color(0xFFF1ECF7);
  static const quietInk = Color(0xFF2E2240);
  static const scrim = Color(0xFF6E6479);
  static const disabledBg = Color(0xFFE3DCEC);
  static const disabledInk = Color(0xFF5E5670);

  // "Please check" / provisional
  static const checkInk = Color(0xFF7F440A);
  static const checkBg = Color(0xFFFAEBD8);
  static const checkBorder = Color(0xFFC98A48);
  static const checkDot = Color(0xFFB8661C);

  // Risk and crisis only
  static const crisis = Color(0xFF8E2A2A);
  static const crisisBg = Color(0xFFF7E2DF);
}
