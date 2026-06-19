import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Application theme configuration — Linkd premium design system.
///
/// Identity: deep navy primary + electric-violet accent, with coral reserved
/// for urgent CTAs. Typography pairs Sora (display/headline) with DM Sans
/// (body/UI). All legacy color names are preserved so existing screens keep
/// compiling while picking up the refreshed palette.
class AppTheme {
  // Primary identity — deep navy, intelligence and depth.
  static const Color primaryColor = Color(0xFF1B1F3B);
  static const Color primaryLight = Color(0xFF2D3561);

  // Accent — electric violet for interactive elements.
  static const Color accentColor = Color(0xFF6C63FF);
  static const Color accentWarm = Color(0xFFFF6B6B); // coral, urgency / CTAs

  // Secondary kept for backwards-compatibility (mapped to the success teal).
  static const Color secondaryColor = Color(0xFF00C896);

  // Semantic.
  static const Color successColor = Color(0xFF00C896);
  static const Color warningColor = Color(0xFFFFB547);
  static const Color errorColor = Color(0xFFFF4757);

  // Surface.
  static const Color backgroundColor = Color(0xFFF7F8FC);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF0F2FF);

  // Text.
  static const Color textPrimary = Color(0xFF1B1F3B);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFFB0B7C3);

  // Lines.
  static const Color borderColor = Color(0xFFE8EAF0);
  static const Color dividerColor = Color(0xFFEDEFF5);

  // Dark mode.
  static const Color backgroundDark = Color(0xFF0F1117);
  static const Color surfaceDark = Color(0xFF1A1D2E);
  static const Color surfaceElevatedDark = Color(0xFF252840);

  // ---------------------------------------------------------------- themes ---

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
        surface: surfaceColor,
        error: errorColor,
      ),
      textTheme: buildTextTheme(dark: false),
      inputDecorationTheme: _inputTheme(dark: false),
      elevatedButtonTheme: _buttonTheme,
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderColor),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      chipTheme: _chipTheme(dark: false),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: primaryColor,
        selectedItemColor: accentColor,
        unselectedItemColor: Color(0xFF8A90A6),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerColor: dividerColor,
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: accentColor,
        secondary: accentColor,
        surface: surfaceDark,
        error: errorColor,
      ),
      textTheme: buildTextTheme(dark: true),
      inputDecorationTheme: _inputTheme(dark: true),
      elevatedButtonTheme: _buttonTheme,
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surfaceElevatedDark),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      chipTheme: _chipTheme(dark: true),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: accentColor,
        unselectedItemColor: Color(0xFF8A90A6),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerColor: surfaceElevatedDark,
    );
  }

  // ------------------------------------------------------------ typography ---

  static TextTheme buildTextTheme({required bool dark}) {
    final base = dark ? Colors.white : textPrimary;
    final muted = dark ? const Color(0xFFAAB0C0) : textSecondary;
    return TextTheme(
      displayLarge:
          GoogleFonts.sora(fontSize: 32, fontWeight: FontWeight.w700, color: base),
      displayMedium:
          GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.w700, color: base),
      displaySmall:
          GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700, color: base),
      headlineLarge:
          GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w600, color: base),
      headlineMedium:
          GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600, color: base),
      headlineSmall:
          GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600, color: base),
      titleLarge:
          GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w600, color: base),
      titleMedium:
          GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w500, color: base),
      titleSmall:
          GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
      bodyLarge: GoogleFonts.dmSans(fontSize: 16, color: base),
      bodyMedium: GoogleFonts.dmSans(fontSize: 14, color: base),
      bodySmall: GoogleFonts.dmSans(fontSize: 12, color: muted),
      labelLarge: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  // ------------------------------------------------------- component themes ---

  static final ElevatedButtonThemeData _buttonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      elevation: 0,
      textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  static InputDecorationTheme _inputTheme({required bool dark}) {
    final fill = dark ? surfaceElevatedDark : surfaceColor;
    final border = dark ? surfaceElevatedDark : borderColor;
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: GoogleFonts.dmSans(color: textHint, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorColor),
      ),
    );
  }

  static ChipThemeData _chipTheme({required bool dark}) {
    return ChipThemeData(
      backgroundColor: dark ? surfaceElevatedDark : surfaceElevated,
      selectedColor: accentColor,
      labelStyle: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: dark ? Colors.white : textPrimary,
      ),
      secondaryLabelStyle: GoogleFonts.dmSans(fontSize: 13, color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }
}
