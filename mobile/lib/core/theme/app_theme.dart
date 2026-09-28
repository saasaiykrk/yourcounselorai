import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Headings use Nunito (rounded, like the wordmark); body text uses Nunito Sans.
abstract final class AppText {
  static const _display = 'Nunito';

  static const screenTitle = TextStyle(
    fontFamily: _display,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.12,
    letterSpacing: -0.4,
    color: AppColors.deepPurple,
  );

  static const heroTitle = TextStyle(
    fontFamily: _display,
    fontSize: 30,
    fontWeight: FontWeight.w900,
    height: 1.12,
    letterSpacing: -0.4,
    color: AppColors.deepPurple,
  );

  static const sheetTitle = TextStyle(
    fontFamily: _display,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: AppColors.deepPurple,
  );

  static const sectionTitle = TextStyle(
    fontFamily: _display,
    fontSize: 21,
    fontWeight: FontWeight.w800,
    color: AppColors.deepPurple,
  );

  static const body = TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink);
  static const bodyMuted = TextStyle(fontSize: 16, height: 1.5, color: AppColors.muted);
  static const small = TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink);
  static const smallMuted = TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted);
  static const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const caption = TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted);
  static const overline = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: AppColors.muted,
  );
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.royalPurple,
    onPrimary: Colors.white,
    primaryContainer: AppColors.lavender,
    onPrimaryContainer: AppColors.deepPurple,
    secondary: AppColors.brandPink,
    onSecondary: Colors.white,
    tertiary: AppColors.deepPurple,
    onTertiary: Colors.white,
    error: AppColors.crisis,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.inputBorder,
    outlineVariant: AppColors.line,
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const buttonText = TextStyle(fontFamily: 'NunitoSans', fontSize: 17, fontWeight: FontWeight.w700);

  OutlineInputBorder border(Color color, [double width = 1.5]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'NunitoSans',
    textTheme: const TextTheme(
      bodyLarge: AppText.body,
      bodyMedium: AppText.small,
      titleLarge: AppText.sectionTitle,
      headlineMedium: AppText.screenTitle,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: buttonShape,
        textStyle: buttonText,
        backgroundColor: AppColors.royalPurple,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.disabledBg,
        disabledForegroundColor: AppColors.disabledInk,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: buttonShape,
        textStyle: buttonText,
        foregroundColor: AppColors.royalPurple,
        side: const BorderSide(color: AppColors.royalPurple, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: AppColors.royalPurple,
        textStyle: const TextStyle(fontFamily: 'NunitoSans', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: AppColors.muted),
      border: border(AppColors.inputBorder),
      enabledBorder: border(AppColors.inputBorder),
      focusedBorder: border(AppColors.royalPurple, 2),
      errorBorder: border(AppColors.crisis),
      focusedErrorBorder: border(AppColors.crisis, 2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.royalPurple : Colors.transparent,
      ),
      side: const BorderSide(color: AppColors.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.background,
      modalBarrierColor: Color(0x996E6479),
      showDragHandle: true,
      dragHandleColor: AppColors.pendingRing,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.lavender,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? AppColors.royalPurple : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) =>
            IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.royalPurple : AppColors.muted),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: AppColors.ink),
    dividerTheme: const DividerThemeData(color: AppColors.lineSoft, space: 1, thickness: 1),
  );
}
