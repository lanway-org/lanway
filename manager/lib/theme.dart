import 'package:flutter/material.dart';

/// Lanway Manager palette — dark surfaces, sky-blue accent, white buttons.
/// Uses the platform's built-in font (no network font fetch).
class LanwayColors {
  static const accent = Color(0xFF38BDF8); // sky blue
  static const primary = Color(0xFF0EA5E9); // deeper sky blue
  static const navy = Color(0xFF0A1628); // dark background
  static const navy2 = Color(0xFF0D1D33);
  static const mint = Color(0xFFE6EEF7); // light text on dark
  static const surface = Color(0xFF11213A);
  static const danger = Color(0xFFE24B4A);
  static const amber = Color(0xFFEF9F27);
}

ThemeData buildLanwayTheme() {
  const scheme = ColorScheme.dark(
    primary: LanwayColors.accent,
    onPrimary: LanwayColors.navy,
    secondary: LanwayColors.primary,
    surface: LanwayColors.navy2,
    onSurface: LanwayColors.mint,
    error: LanwayColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LanwayColors.navy,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: LanwayColors.navy,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      color: LanwayColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LanwayColors.navy2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LanwayColors.accent, width: 1.5),
      ),
    ),
    // Solid blue buttons, white text, rectangular and tall.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x330284C7),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: LanwayColors.surface,
      contentTextStyle: TextStyle(color: LanwayColors.mint),
    ),
  );
}
