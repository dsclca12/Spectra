import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/theme.dart';

void main() {
  group('AppTheme', () {
    test('暗色主题已创建', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
    });

    test('主题色不为 null', () {
      final theme = AppTheme.dark();
      expect(theme.colorScheme.primary, isNotNull);
      expect(theme.colorScheme.surface, isNotNull);
      expect(theme.colorScheme.onSurface, isNotNull);
    });

    test('colorLabel 颜色已定义', () {
      expect(AppTheme.colorLabelRed, const Color(0xFFE81123));
      expect(AppTheme.colorLabelYellow, const Color(0xFFFFB900));
      expect(AppTheme.colorLabelGreen, const Color(0xFF10893E));
      expect(AppTheme.colorLabelBlue, const Color(0xFF0078D4));
    });
  });
}
