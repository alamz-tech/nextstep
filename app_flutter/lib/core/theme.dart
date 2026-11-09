import 'package:flutter/material.dart';

/// Colours and type from the Claude Design tokens (content/tokens.json).
class NsColors {
  const NsColors({required this.bg, required this.surface, required this.chatBg, required this.text, required this.text2,
      required this.line, required this.primary, required this.onPrimary, required this.primaryTint, required this.accent,
      required this.onAccent, required this.highlight, required this.onHighlight, required this.support,
      required this.onSupport, required this.supportTint, required this.success});
  final Color bg, surface, chatBg, text, text2, line, primary, onPrimary, primaryTint, accent, onAccent, highlight,
      onHighlight, support, onSupport, supportTint, success;

  static const light = NsColors(bg: Color(0xFFFAF8F4), surface: Color(0xFFFFFFFF), chatBg: Color(0xFFEEEAE3),
      text: Color(0xFF1B1F23), text2: Color(0xFF4A5560), line: Color(0xFFE3DFD7), primary: Color(0xFF0F5C5A),
      onPrimary: Color(0xFFFFFFFF), primaryTint: Color(0xFFDCEFEC), accent: Color(0xFFC2462E), onAccent: Color(0xFFFFFFFF),
      highlight: Color(0xFFF6C453), onHighlight: Color(0xFF1B1F23), support: Color(0xFF2F5DA8), onSupport: Color(0xFFFFFFFF),
      supportTint: Color(0xFFE3EAF6), success: Color(0xFF2E7D4F));
  static const dark = NsColors(bg: Color(0xFF0E1517), surface: Color(0xFF172225), chatBg: Color(0xFF121C1F),
      text: Color(0xFFEEF2F1), text2: Color(0xFFA9B7B5), line: Color(0xFF2A3A3E), primary: Color(0xFF5CC8BE),
      onPrimary: Color(0xFF0E1517), primaryTint: Color(0xFF1F3B3A), accent: Color(0xFFFF8A70), onAccent: Color(0xFF0E1517),
      highlight: Color(0xFFF6C453), onHighlight: Color(0xFF0E1517), support: Color(0xFF8FB0EA), onSupport: Color(0xFF0E1517),
      supportTint: Color(0xFF1F2D45), success: Color(0xFF6CC79A));

  static NsColors of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

const kBody = 'Atkinson';
const kDisplay = 'Bricolage';

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? NsColors.dark : NsColors.light;
  final scheme = ColorScheme(
    brightness: b, primary: c.primary, onPrimary: c.onPrimary, secondary: c.accent, onSecondary: c.onAccent,
    tertiary: c.support, onTertiary: c.onSupport, error: c.accent, onError: c.onAccent, surface: c.surface,
    onSurface: c.text, primaryContainer: c.primaryTint, onPrimaryContainer: c.text, outline: c.line,
    surfaceContainerHighest: c.chatBg, onSurfaceVariant: c.text2,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: kBody, scaffoldBackgroundColor: c.bg);
  TextStyle d(double s, double h, FontWeight w) => TextStyle(fontFamily: kDisplay, fontSize: s, height: h / s, fontWeight: w, color: c.text);
  TextStyle bd(double s, double h, [FontWeight w = FontWeight.w400]) => TextStyle(fontFamily: kBody, fontSize: s, height: h / s, fontWeight: w, color: c.text);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: d(48, 56, FontWeight.w800), headlineMedium: d(32, 40, FontWeight.w700), headlineSmall: d(24, 32, FontWeight.w700),
      titleLarge: bd(20, 28, FontWeight.w700), titleMedium: bd(18, 26, FontWeight.w700), bodyLarge: bd(18, 28),
      bodyMedium: bd(16, 24), bodySmall: bd(14, 20).copyWith(color: c.text2), labelLarge: bd(16, 20, FontWeight.w700),
      labelSmall: bd(12, 16, FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(backgroundColor: c.surface, foregroundColor: c.text, elevation: 0, scrolledUnderElevation: 0,
        titleTextStyle: d(20, 26, FontWeight.w700), shape: Border(bottom: BorderSide(color: c.line))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48),
        shape: const StadiumBorder(), textStyle: const TextStyle(fontFamily: kBody, fontWeight: FontWeight.w700, fontSize: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48),
        shape: const StadiumBorder(), side: BorderSide(color: c.primary, width: 2), foregroundColor: c.primary,
        textStyle: const TextStyle(fontFamily: kBody, fontWeight: FontWeight.w700, fontSize: 16))),
    cardTheme: CardThemeData(color: c.surface, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.line))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: c.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.line, width: 2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.line, width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.primary, width: 2))),
    dividerTheme: DividerThemeData(color: c.line),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
