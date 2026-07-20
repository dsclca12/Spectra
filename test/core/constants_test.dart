import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/constants.dart';

void main() {
  group('FeatureFlags', () {
    test('aiMlEnabled defaults to false', () {
      expect(FeatureFlags.aiMlEnabled, isFalse);
    });

    test('superResolutionEnabled defaults to false', () {
      expect(FeatureFlags.superResolutionEnabled, isFalse);
    });
  });

  group('AppConstants misc', () {
    test('contains app name and version', () {
      expect(AppConstants.appName, 'Spectra');
      expect(AppConstants.appVersion, '0.1.0');
    });

    test('thumbnail sizes are positive', () {
      expect(AppConstants.thumbnailSmall, greaterThan(0));
      expect(AppConstants.thumbnailMedium, greaterThan(0));
      expect(AppConstants.previewMaxSize, greaterThan(0));
    });

    test('panel dimensions are consistent', () {
      expect(AppConstants.leftPanelMinWidth, lessThan(AppConstants.leftPanelDefaultWidth));
      expect(AppConstants.leftPanelDefaultWidth, lessThan(AppConstants.leftPanelMaxWidth));
      expect(AppConstants.rightPanelMinWidth, lessThan(AppConstants.rightPanelDefaultWidth));
      expect(AppConstants.rightPanelDefaultWidth, lessThan(AppConstants.rightPanelMaxWidth));
    });

    test('database file name is set', () {
      expect(AppConstants.databaseFileName, 'spectra.db');
    });

    test('search debounce is 300ms', () {
      expect(AppConstants.searchDebounce, const Duration(milliseconds: 300));
    });

    test('default page size is 200', () {
      expect(AppConstants.defaultPageSize, 200);
    });
  });
}
