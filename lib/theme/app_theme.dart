import 'package:flutter/material.dart';

/// Shared Material 3 styling for Atlas's VS Code-inspired dark workspace.
abstract final class AppTheme {
  static const _background = Color(0xFF181818);
  static const _surface = Color(0xFF1F1F1F);
  static const _panel = Color(0xFF252526);
  static const _border = Color(0xFF3C3C3C);
  static const _accent = Color(0xFF3794FF);

  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: _accent,
      onPrimary: Colors.white,
      surface: _surface,
      onSurface: Color(0xFFCCCCCC),
      outline: _border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _background,
      dividerColor: _border,
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Color(0xFFCCCCCC)),
        bodySmall: TextStyle(color: Color(0xFF9D9D9D)),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFCCCCCC)),
      appBarTheme: const AppBarTheme(
        backgroundColor: _panel,
        foregroundColor: Color(0xFFCCCCCC),
        elevation: 0,
      ),
    );
  }
}
