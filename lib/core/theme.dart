// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Spectra theme configuration — dark-mode first, Fluent Design style.
class AppTheme {
  AppTheme._();

  // ─── Dark theme colors ───
  static const Color _darkBgPanel = Color(0xFF1E1E1E);
  static const Color _darkBgContent = Color(0xFF252526);
  static const Color _darkBgHover = Color(0xFF2D2D30);
  static const Color _darkFgPrimary = Color(0xFFCCCCCC);
  static const Color _darkFgSecondary = Color(0xFF969696);
  static const Color _darkFgDisabled = Color(0xFF5A5A5A);
  static const Color _accent = Color(0xFF0078D4);
  static const Color _rejectRed = Color(0xFFE81123);

  // Color label colors
  static const Color colorLabelRed = Color(0xFFE81123);
  static const Color colorLabelYellow = Color(0xFFFFB900);
  static const Color colorLabelGreen = Color(0xFF10893E);
  static const Color colorLabelBlue = Color(0xFF0078D4);
  static const Color colorLabelPurple = Color(0xFF8661C5);
  static const Color colorLabelGray = Color(0xFF69797E);

  /// Get the color for a given color label value.
  static Color? colorLabelColor(int label) {
    return switch (label) {
      1 => colorLabelRed,
      2 => colorLabelYellow,
      3 => colorLabelGreen,
      4 => colorLabelBlue,
      5 => colorLabelPurple,
      6 => colorLabelGray,
      _ => null,
    };
  }

  /// Dark theme.
  static ThemeData dark() {
    final colorScheme = const ColorScheme.dark(
      primary: _accent,
      surface: _darkBgPanel,
      onSurface: _darkFgPrimary,
      secondary: _darkFgSecondary,
      error: _rejectRed,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _darkBgContent,
      canvasColor: _darkBgPanel,
      dividerColor: _darkFgDisabled,
      fontFamily: 'Segoe UI',
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBgPanel,
        foregroundColor: _darkFgPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      iconTheme: const IconThemeData(color: _darkFgPrimary, size: 18),
      listTileTheme: ListTileThemeData(
        textColor: _darkFgPrimary,
        iconColor: _darkFgSecondary,
        selectedColor: _accent,
        selectedTileColor: _accent.withValues(alpha: 0.25),
      ),
      splashColor: _accent.withValues(alpha: 0.30),
      highlightColor: _accent.withValues(alpha: 0.18),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(_darkFgDisabled),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkBgHover,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: _darkFgSecondary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: _darkBgPanel,
        textStyle: const TextStyle(color: _darkFgPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _darkBgHover,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: _darkFgPrimary, fontSize: 12),
      ),
    );
  }

  /// Light theme.
  static ThemeData light() {
    const Color bgPanel = Color(0xFFF3F3F3);
    const Color bgContent = Color(0xFFFFFFFF);
    const Color fgPrimary = Color(0xFF1E1E1E);
    const Color fgSecondary = Color(0xFF616161);

    final colorScheme = const ColorScheme.light(
      primary: _accent,
      surface: bgPanel,
      onSurface: fgPrimary,
      secondary: fgSecondary,
      error: _rejectRed,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgContent,
      canvasColor: bgPanel,
      fontFamily: 'Segoe UI',
      appBarTheme: const AppBarTheme(
        backgroundColor: bgPanel,
        foregroundColor: fgPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      iconTheme: const IconThemeData(color: fgPrimary, size: 18),
      listTileTheme: const ListTileThemeData(
        textColor: fgPrimary,
        iconColor: fgSecondary,
        selectedColor: _accent,
        selectedTileColor: Color(0xFFE0E0E0),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.grey[400]),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
    );
  }
}