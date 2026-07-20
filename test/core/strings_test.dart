import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/strings.dart';

void main() {
  group('AppStrings', () {
    test('app name and version are set', () {
      expect(AppStrings.appName, 'Spectra');
      expect(AppStrings.appVersion, '0.1.0');
    });

    test('menu strings are defined', () {
      expect(AppStrings.menuFile, 'File');
      expect(AppStrings.menuEdit, 'Edit');
      expect(AppStrings.menuView, 'View');
    });
  });
}
