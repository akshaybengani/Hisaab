import 'package:flutter/material.dart';

/// The single source of truth for colour in Hisaab, taken from the app icon.
/// No widget carries a literal colour; re-skinning happens here [per std-27].
abstract final class AppColors {
  static const Color primary = Color(0xFF333196);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFFB9BAF7);
}

/// Material 3 light and dark schemes seeded from the icon's indigo, so the
/// whole app stays tonally consistent without hand-picking shades.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
