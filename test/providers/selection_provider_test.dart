import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/providers/selection_provider.dart';

void main() {
  group('SelectionNotifier', () {
    test('初始状态无选择', () {
      final notifier = SelectionNotifier();
      expect(notifier.state.hasSelection, isFalse);
      expect(notifier.state.count, 0);
    });

    test('单选', () {
      final notifier = SelectionNotifier();
      notifier.select(1);
      expect(notifier.state.isSelected(1), isTrue);
      expect(notifier.state.count, 1);
    });

    test('切换选中', () {
      final notifier = SelectionNotifier();
      notifier.select(1);
      notifier.toggle(2);
      expect(notifier.state.isSelected(1), isTrue);
      expect(notifier.state.isSelected(2), isTrue);
      expect(notifier.state.count, 2);

      notifier.toggle(1);
      expect(notifier.state.isSelected(1), isFalse);
      expect(notifier.state.count, 1);
    });

    test('全选', () {
      final notifier = SelectionNotifier();
      notifier.selectAll([1, 2, 3, 4, 5]);
      expect(notifier.state.count, 5);
    });

    test('清除选择', () {
      final notifier = SelectionNotifier();
      notifier.select(1);
      notifier.select(2);
      notifier.clear();
      expect(notifier.state.hasSelection, isFalse);
    });

    test('范围选择', () {
      final notifier = SelectionNotifier();
      notifier.select(1);
      notifier.selectRange(3, [1, 2, 3, 4, 5]);
      expect(notifier.state.isSelected(1), isTrue);
      expect(notifier.state.isSelected(2), isTrue);
      expect(notifier.state.isSelected(3), isTrue);
      expect(notifier.state.isSelected(4), isFalse);
    });
  });
}