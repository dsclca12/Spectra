// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Spectra theme configuration — dark-mode first, Fluent Design style.
class AppTheme {
  AppTheme._();

  // ─── Dark theme colors ───
  static const Color _darkBgPanel = Color(0xFF1E1E1E);
  static const Color _darkBgContent = Color(0xFF252526);
  static const Color _darkBgHover = Color(0xFF2D2D30);
  static const Color _darkBgPressed = Color(0xFF38383C);
  static const Color _darkFgPrimary = Color(0xFFCCCCCC);
  static const Color _darkFgSecondary = Color(0xFF969696);
  static const Color _darkFgDisabled = Color(0xFF5A5A5A);
  static const Color _accent = Color(0xFF0078D4);
  static const Color _accentHover = Color(0xFF1A8AE0);
  static const Color _accentPressed = Color(0xFF0069C0);
  static const Color _rejectRed = Color(0xFFE81123);

  // Color label colors
  static const Color colorLabelRed = Color(0xFFE81123);
  static const Color colorLabelYellow = Color(0xFFFFB900);
  static const Color colorLabelGreen = Color(0xFF10893E);
  static const Color colorLabelBlue = Color(0xFF0078D4);
  static const Color colorLabelPurple = Color(0xFF8661C5);
  static const Color colorLabelGray = Color(0xFF69797E);

  // ─── Shared component builders ───

  /// Hover/pressed/focused overlay colors used by buttons, list tiles, menu items.
  static WidgetStateProperty<Color> _interactiveOverlay(
    Color hover,
    Color pressed,
    Color focused,
  ) {
    return WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.pressed)) return pressed;
      if (states.contains(WidgetState.focused)) return focused;
      if (states.contains(WidgetState.hovered)) return hover;
      return Colors.transparent;
    });
  }

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
      onPrimary: Colors.white,
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
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBgPanel,
        foregroundColor: _darkFgPrimary,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
      ),
      iconTheme: const IconThemeData(color: _darkFgPrimary, size: 18),
      listTileTheme: ListTileThemeData(
        textColor: _darkFgPrimary,
        iconColor: _darkFgSecondary,
        selectedColor: _accent,
        selectedTileColor: _accent.withValues(alpha: 0.25),
        minVerticalPadding: 6,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      splashColor: _accent.withValues(alpha: 0.18),
      highlightColor: Colors.transparent,
      hoverColor: _darkBgHover,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return _darkFgSecondary;
          }
          return _darkFgDisabled;
        }),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        thickness: WidgetStateProperty.all(10),
        radius: const Radius.circular(5),
        crossAxisMargin: 2,
        mainAxisMargin: 2,
        minThumbLength: 40,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkBgHover,
        hoverColor: _darkBgPressed,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: _accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: _darkFgSecondary),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF2B2B2D),
        textStyle: const TextStyle(color: _darkFgPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: _darkFgDisabled.withValues(alpha: 0.5)),
        ),
        elevation: 8,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _darkBgPressed,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _darkFgDisabled.withValues(alpha: 0.4)),
        ),
        textStyle: const TextStyle(color: _darkFgPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
        showDuration: const Duration(milliseconds: 1500),
      ),
      // ─── Button themes — Fluent-style hover/press feedback ───
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return _darkBgHover;
            if (states.contains(WidgetState.pressed)) return _accentPressed;
            if (states.contains(WidgetState.hovered)) return _accentHover;
            return _accent;
          }),
          foregroundColor:
              WidgetStateProperty.all(Colors.white),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(0),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return _accentPressed;
            if (states.contains(WidgetState.hovered)) return _accentHover;
            return _accent;
          }),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(0),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return _darkFgDisabled;
            if (states.contains(WidgetState.hovered)) return _accentHover;
            return _accent;
          }),
          overlayColor: _interactiveOverlay(
            _darkBgHover,
            _darkBgPressed,
            _accent.withValues(alpha: 0.15),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return _darkFgDisabled;
            if (states.contains(WidgetState.hovered)) return _accentHover;
            return _darkFgPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return _darkBgHover;
            return Colors.transparent;
          }),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          side: WidgetStateProperty.all(
            BorderSide(color: _darkFgDisabled.withValues(alpha: 0.6)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return _darkFgDisabled;
            if (states.contains(WidgetState.selected)) return _accent;
            if (states.contains(WidgetState.hovered)) return _darkFgPrimary;
            return _darkFgSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _accent.withValues(alpha: 0.18);
            }
            if (states.contains(WidgetState.hovered)) return _darkBgHover;
            return Colors.transparent;
          }),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          padding: WidgetStateProperty.all(const EdgeInsets.all(6)),
          minimumSize: WidgetStateProperty.all(const Size(30, 30)),
        ),
      ),
      // ─── Card / container theme ───
      cardTheme: CardThemeData(
        color: _darkBgPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: _darkFgDisabled.withValues(alpha: 0.3)),
        ),
        margin: EdgeInsets.zero,
      ),
      // ─── Chip theme ───
      chipTheme: ChipThemeData(
        backgroundColor: _darkBgHover,
        selectedColor: _accent.withValues(alpha: 0.25),
        disabledColor: _darkBgPanel,
        labelStyle: const TextStyle(fontSize: 12, color: _darkFgPrimary),
        secondaryLabelStyle:
            const TextStyle(fontSize: 11, color: _darkFgSecondary),
        side: BorderSide(
          color: _darkFgDisabled.withValues(alpha: 0.4),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      // ─── Dialog theme ───
      dialogTheme: DialogThemeData(
        backgroundColor: _darkBgPanel,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _darkFgDisabled.withValues(alpha: 0.4)),
        ),
        titleTextStyle: const TextStyle(
          color: _darkFgPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: _darkFgPrimary,
          fontSize: 13,
        ),
      ),
      // ─── Progress indicators ───
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: _darkBgHover,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
      // ─── Divider ───
      dividerTheme: DividerThemeData(
        color: _darkFgDisabled.withValues(alpha: 0.4),
        thickness: 0.5,
        space: 0,
      ),
      // ─── SnackBar ───
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkBgPressed,
        contentTextStyle: const TextStyle(color: _darkFgPrimary, fontSize: 13),
        actionTextColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 6,
      ),
      // ─── Switch ───
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return _darkFgDisabled;
          if (states.contains(WidgetState.selected)) return Colors.white;
          return _darkFgPrimary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return _darkBgPressed;
        }),
        trackOutlineColor: WidgetStateProperty.all(_darkFgDisabled),
        splashRadius: 0,
      ),
      // ─── Slider ───
      sliderTheme: SliderThemeData(
        activeTrackColor: _accent,
        inactiveTrackColor: _darkBgPressed,
        thumbColor: _accent,
        overlayColor: _accent.withValues(alpha: 0.2),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        tickMarkShape: const RoundSliderTickMarkShape(),
      ),
      // ─── Typography ───
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
        displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
        headlineLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      // ─── Page transitions ───
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.windows: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.macOS: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.linux: _FadeUpPageTransitionsBuilder(),
      }),
    );
  }

  /// Light theme.
  static ThemeData light() {
    const Color bgPanel = Color(0xFFF3F3F3);
    const Color bgContent = Color(0xFFFFFFFF);
    const Color bgHover = Color(0xFFE6E6E6);
    const Color fgPrimary = Color(0xFF1E1E1E);
    const Color fgSecondary = Color(0xFF616161);
    const Color fgDisabled = Color(0xFFBDBDBD);

    final colorScheme = const ColorScheme.light(
      primary: _accent,
      onPrimary: Colors.white,
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
      dividerColor: fgDisabled,
      fontFamily: 'Segoe UI',
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgPanel,
        foregroundColor: fgPrimary,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
      ),
      iconTheme: const IconThemeData(color: fgPrimary, size: 18),
      listTileTheme: const ListTileThemeData(
        textColor: fgPrimary,
        iconColor: fgSecondary,
        selectedColor: _accent,
        selectedTileColor: Color(0xFFE0E0E0),
        minVerticalPadding: 6,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      splashColor: _accent.withValues(alpha: 0.18),
      highlightColor: Colors.transparent,
      hoverColor: bgHover,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return fgSecondary;
          }
          return fgDisabled;
        }),
        thickness: WidgetStateProperty.all(10),
        radius: const Radius.circular(5),
        crossAxisMargin: 2,
        mainAxisMargin: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgHover,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: fgSecondary),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        textStyle: const TextStyle(color: fgPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: fgDisabled),
        ),
        elevation: 8,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: bgPanel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: fgDisabled),
        ),
        textStyle: const TextStyle(color: fgPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return bgHover;
            if (states.contains(WidgetState.pressed)) return _accentPressed;
            if (states.contains(WidgetState.hovered)) return _accentHover;
            return _accent;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(0),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(_accent),
          overlayColor: WidgetStateProperty.all(bgHover),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: fgDisabled,
        thickness: 0.5,
        space: 0,
      ),
      cardTheme: CardThemeData(
        color: bgContent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: fgDisabled),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgContent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: fgDisabled),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: bgHover,
        linearMinHeight: 4,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.windows: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.macOS: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.linux: _FadeUpPageTransitionsBuilder(),
      }),
    );
  }
}

/// Fluent-style page transition — subtle fade + slight upward slide.
/// Feels native on Windows desktop (no Material bounce/scale).
class _FadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.easeOutCubic;
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.015),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: curve));
    final fade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: animation, curve: curve));
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: offset, child: child),
    );
  }
}