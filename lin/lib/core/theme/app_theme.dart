import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Application theme — Linkd "moss & cream" design system.
///
/// Warm, human, not corporate. Three working ramps (moss/green, amber, warm
/// neutral) plus a red ramp reserved exclusively for destructive/error states.
///
/// Two layers:
///   1. Ramp constants ([green50]..[green900] etc.) are mode-independent hues.
///   2. [MossTokens] (a [ThemeExtension]) maps those hues to mode-dependent
///      semantic roles (page bg, card surface, text, borders, match tiers).
///      Always read surface/text/tier colors through `MossTokens.of(context)`
///      so dark mode resolves correctly — never hardcode literal colors inline.
class AppTheme {
  AppTheme._();

  // ----------------------------------------------------------- moss (green) ---
  static const Color green50 = Color(0xFFEAF3DE);
  static const Color green100 = Color(0xFFC0DD97);
  static const Color green200 = Color(0xFF97C459);
  static const Color green400 = Color(0xFF639922);
  static const Color green600 = Color(0xFF3B6D11);
  static const Color green800 = Color(0xFF27500A);
  static const Color green900 = Color(0xFF173404);

  // ------------------------------------------------------------------ amber ---
  static const Color amber50 = Color(0xFFFAEEDA);
  static const Color amber100 = Color(0xFFFAC775);
  static const Color amber200 = Color(0xFFEF9F27);
  static const Color amber400 = Color(0xFFBA7517);
  static const Color amber600 = Color(0xFF854F0B);
  static const Color amber800 = Color(0xFF633806);
  static const Color amber900 = Color(0xFF412402);

  // ---------------------------------------------------------------- neutral ---
  static const Color neutral50 = Color(0xFFF1EFE8);
  static const Color neutral100 = Color(0xFFD3D1C7);
  static const Color neutral200 = Color(0xFFB4B2A9);
  static const Color neutral400 = Color(0xFF888780);
  static const Color neutral600 = Color(0xFF5F5E5A);
  static const Color neutral800 = Color(0xFF444441);
  static const Color neutral900 = Color(0xFF2C2C2A);

  // --------------------------------------------- red (destructive / error) ---
  static const Color red50 = Color(0xFFFCEBEB);
  static const Color red400 = Color(0xFFE24B4A);
  static const Color red600 = Color(0xFFA32D2D);
  static const Color red800 = Color(0xFF791F1F);

  // ----------------------------------------------------------- light surfaces ---
  static const Color lightPageBackground = Color(0xFFF3F1E7);
  static const Color lightCardSurface = Color(0xFFFAFAF5);
  static const Color lightTextPrimary = neutral900;
  static const Color lightTextSecondary = neutral600;
  static const Color lightBorder = Color(0xFFE3E5D6);

  // ------------------------------------------------------------ dark surfaces ---
  static const Color darkPageBackground = Color(0xFF1C1B17);
  static const Color darkCardSurface = Color(0xFF26241F);
  static const Color darkCardSurfaceLow = Color(0xFF1E1C16);
  static const Color darkTextPrimary = Color(0xFFF0EDE2);
  static const Color darkTextSecondary = Color(0xFFA6A18E);
  static const Color darkBorder = Color(0xFF34312A);

  // --------------------------------------------------- legacy color aliases ---
  // Compile-safety net for any straggling references during the migration.
  // New code must read colors from MossTokens instead (these are light-only).
  static const Color primaryColor = green600;
  static const Color secondaryColor = green400;
  static const Color accentColor = green400;
  static const Color successColor = green400;
  static const Color warningColor = amber200;
  static const Color errorColor = red400;
  static const Color backgroundColor = lightPageBackground;
  static const Color surfaceColor = lightCardSurface;
  static const Color textPrimary = lightTextPrimary;
  static const Color textSecondary = lightTextSecondary;
  static const Color textHint = neutral400;
  static const Color borderColor = lightBorder;

  // ---------------------------------------------------------------- themes ---

  static ThemeData lightTheme() => _buildTheme(dark: false);
  static ThemeData darkTheme() => _buildTheme(dark: true);

  static ThemeData _buildTheme({required bool dark}) {
    final tokens = dark ? MossTokens.dark : MossTokens.light;
    final colorScheme = dark
        ? ColorScheme.dark(
            primary: green200,
            onPrimary: green900,
            secondary: amber200,
            surface: tokens.cardSurface,
            onSurface: tokens.textPrimary,
            error: red400,
          )
        : ColorScheme.light(
            primary: green600,
            onPrimary: Colors.white,
            secondary: amber200,
            surface: tokens.cardSurface,
            onSurface: tokens.textPrimary,
            error: red600,
          );

    final textTheme = buildTextTheme(tokens);

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: tokens.pageBackground,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.pageBackground,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      inputDecorationTheme: _inputTheme(tokens),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.cardSurface,
        elevation: 0,
        // Memory cards are deliberately near-square (2px); generic cards match.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      dividerColor: tokens.border,
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 0.5),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.cardSurface,
        selectedColor: green100,
        labelStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: tokens.border, width: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.cardSurface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: tokens.textSecondary,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  // ------------------------------------------------------------ typography ---

  /// Two weights only (400/500), sentence case enforced at call sites.
  /// Fraunces serif is reserved for editorial moments (display + headlineLarge);
  /// everything else uses Inter sans.
  static TextTheme buildTextTheme(MossTokens tokens) {
    final base = tokens.textPrimary;
    final muted = tokens.textSecondary;
    TextStyle serif(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        GoogleFonts.fraunces(fontSize: size, fontWeight: w, color: c ?? base);
    TextStyle sans(double size,
            {FontWeight w = FontWeight.w400, Color? c}) =>
        GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? base);

    return TextTheme(
      displayLarge: serif(32, w: FontWeight.w500),
      displayMedium: serif(26, w: FontWeight.w500),
      displaySmall: serif(22, w: FontWeight.w500),
      headlineLarge: serif(20, w: FontWeight.w500),
      headlineMedium: sans(18, w: FontWeight.w500),
      headlineSmall: sans(16, w: FontWeight.w500),
      titleLarge: sans(16, w: FontWeight.w500),
      titleMedium: sans(14, w: FontWeight.w500),
      titleSmall: sans(12, w: FontWeight.w500, c: muted),
      bodyLarge: sans(16),
      bodyMedium: sans(14),
      bodySmall: sans(12, c: muted),
      labelLarge: sans(14, w: FontWeight.w500),
      labelMedium: sans(12, w: FontWeight.w500),
      labelSmall: sans(11, c: muted),
    );
  }

  // -------------------------------------------------- underline-only inputs ---

  static InputDecorationTheme _inputTheme(MossTokens tokens) {
    return InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      hintStyle: GoogleFonts.inter(color: tokens.textSecondary, fontSize: 15),
      labelStyle: GoogleFonts.inter(color: tokens.textSecondary, fontSize: 15),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: tokens.border, width: 0.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: green400, width: 2),
      ),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: tokens.border, width: 0.5),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: red400, width: 2),
      ),
    );
  }
}

/// Mode-dependent semantic color roles. Read via `MossTokens.of(context)`.
@immutable
class MossTokens extends ThemeExtension<MossTokens> {
  final Color pageBackground;
  final Color cardSurface;

  /// Slightly darker than [cardSurface] — the folded-corner triangle detail.
  final Color cardFold;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  /// Color of the dotted "shared ground" rule on memory cards.
  final Color dottedRule;

  // Match / relationship / facet tiers. "low" is neutral gray — never red.
  final Color tierStrong; // moss
  final Color tierStrongSoft; // lighter moss (the "them" circle / outer rings)
  final Color tierModerate; // amber
  final Color tierModerateSoft;
  final Color tierLow; // neutral gray
  final Color tierLowSoft;

  /// Destructive / error.
  final Color danger;

  const MossTokens({
    required this.pageBackground,
    required this.cardSurface,
    required this.cardFold,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.dottedRule,
    required this.tierStrong,
    required this.tierStrongSoft,
    required this.tierModerate,
    required this.tierModerateSoft,
    required this.tierLow,
    required this.tierLowSoft,
    required this.danger,
  });

  static const MossTokens light = MossTokens(
    pageBackground: AppTheme.lightPageBackground,
    cardSurface: AppTheme.lightCardSurface,
    cardFold: AppTheme.neutral100,
    textPrimary: AppTheme.lightTextPrimary,
    textSecondary: AppTheme.lightTextSecondary,
    border: AppTheme.lightBorder,
    dottedRule: AppTheme.neutral200,
    tierStrong: AppTheme.green600,
    tierStrongSoft: AppTheme.green200,
    tierModerate: AppTheme.amber200,
    tierModerateSoft: AppTheme.amber100,
    tierLow: AppTheme.neutral400,
    tierLowSoft: AppTheme.neutral200,
    danger: AppTheme.red600,
  );

  static const MossTokens dark = MossTokens(
    pageBackground: AppTheme.darkPageBackground,
    cardSurface: AppTheme.darkCardSurface,
    cardFold: AppTheme.neutral800,
    textPrimary: AppTheme.darkTextPrimary,
    textSecondary: AppTheme.darkTextSecondary,
    border: AppTheme.darkBorder,
    dottedRule: AppTheme.neutral600,
    tierStrong: AppTheme.green200,
    tierStrongSoft: AppTheme.green400,
    tierModerate: AppTheme.amber200,
    tierModerateSoft: AppTheme.amber400,
    tierLow: AppTheme.neutral400,
    tierLowSoft: AppTheme.neutral600,
    danger: AppTheme.red400,
  );

  /// Convenience accessor. Falls back to [light] if the extension is missing.
  static MossTokens of(BuildContext context) =>
      Theme.of(context).extension<MossTokens>() ?? light;

  @override
  MossTokens copyWith({
    Color? pageBackground,
    Color? cardSurface,
    Color? cardFold,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? dottedRule,
    Color? tierStrong,
    Color? tierStrongSoft,
    Color? tierModerate,
    Color? tierModerateSoft,
    Color? tierLow,
    Color? tierLowSoft,
    Color? danger,
  }) {
    return MossTokens(
      pageBackground: pageBackground ?? this.pageBackground,
      cardSurface: cardSurface ?? this.cardSurface,
      cardFold: cardFold ?? this.cardFold,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      dottedRule: dottedRule ?? this.dottedRule,
      tierStrong: tierStrong ?? this.tierStrong,
      tierStrongSoft: tierStrongSoft ?? this.tierStrongSoft,
      tierModerate: tierModerate ?? this.tierModerate,
      tierModerateSoft: tierModerateSoft ?? this.tierModerateSoft,
      tierLow: tierLow ?? this.tierLow,
      tierLowSoft: tierLowSoft ?? this.tierLowSoft,
      danger: danger ?? this.danger,
    );
  }

  @override
  MossTokens lerp(ThemeExtension<MossTokens>? other, double t) {
    if (other is! MossTokens) return this;
    return MossTokens(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardFold: Color.lerp(cardFold, other.cardFold, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      dottedRule: Color.lerp(dottedRule, other.dottedRule, t)!,
      tierStrong: Color.lerp(tierStrong, other.tierStrong, t)!,
      tierStrongSoft: Color.lerp(tierStrongSoft, other.tierStrongSoft, t)!,
      tierModerate: Color.lerp(tierModerate, other.tierModerate, t)!,
      tierModerateSoft: Color.lerp(tierModerateSoft, other.tierModerateSoft, t)!,
      tierLow: Color.lerp(tierLow, other.tierLow, t)!,
      tierLowSoft: Color.lerp(tierLowSoft, other.tierLowSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Shared match/relationship/facet tiers and their thresholds, so every widget
/// (overlap circles, connection thread, facet ring) classifies consistently.
enum MatchTier { strong, moderate, low }

extension MatchTierX on MatchTier {
  /// From a 0.0–1.0 overlap score.
  static MatchTier fromScore(double score) {
    if (score >= 0.7) return MatchTier.strong;
    if (score >= 0.4) return MatchTier.moderate;
    return MatchTier.low;
  }

  /// From a 1–10 relationship strength.
  static MatchTier fromStrength(int strength) {
    if (strength >= 7) return MatchTier.strong;
    if (strength >= 4) return MatchTier.moderate;
    return MatchTier.low;
  }

  Color color(MossTokens t) => switch (this) {
        MatchTier.strong => t.tierStrong,
        MatchTier.moderate => t.tierModerate,
        MatchTier.low => t.tierLow,
      };

  Color soft(MossTokens t) => switch (this) {
        MatchTier.strong => t.tierStrongSoft,
        MatchTier.moderate => t.tierModerateSoft,
        MatchTier.low => t.tierLowSoft,
      };
}
