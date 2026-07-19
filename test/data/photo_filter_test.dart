import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/data/models/photo_filter.dart';

void main() {
  group('PhotoFilter', () {
    test('空筛选器无活跃条件', () {
      const filter = PhotoFilter();
      expect(filter.hasActiveFilters, isFalse);
    });

    test('有筛选条件时 hasActiveFilters 为 true', () {
      const filter = PhotoFilter(minRating: 3);
      expect(filter.hasActiveFilters, isTrue);
    });

    test('copyWith 正确更新', () {
      const filter = PhotoFilter(minRating: 3);
      final updated = filter.copyWith(pickLabel: 1);
      expect(updated.minRating, 3);
      expect(updated.pickLabel, 1);
    });

    test('copyWith 清除条件', () {
      const filter = PhotoFilter(minRating: 3, pickLabel: 1);
      final updated = filter.copyWith(clearMinRating: true);
      expect(updated.minRating, isNull);
      expect(updated.pickLabel, 1);
    });

    test('相等性比较', () {
      const filter1 = PhotoFilter(minRating: 3, pickLabel: 1);
      const filter2 = PhotoFilter(minRating: 3, pickLabel: 1);
      const filter3 = PhotoFilter(minRating: 4, pickLabel: 1);

      expect(filter1 == filter2, isTrue);
      expect(filter1 == filter3, isFalse);
    });
  });
}