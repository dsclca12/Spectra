import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 色标选择器组件
class ColorLabelSelector extends StatelessWidget {
  final int colorLabel;
  final ValueChanged<int> onChanged;

  const ColorLabelSelector({
    super.key,
    required this.colorLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      (0, '无', Colors.transparent),
      (1, '红', AppTheme.colorLabelRed),
      (2, '黄', AppTheme.colorLabelYellow),
      (3, '绿', AppTheme.colorLabelGreen),
      (4, '蓝', AppTheme.colorLabelBlue),
      (5, '紫', AppTheme.colorLabelPurple),
      (6, '灰', AppTheme.colorLabelGray),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: colors.map((c) {
        final ($label, $name, $color) = (c.$1, c.$2, c.$3);
        final isSelected = colorLabel == $label;
        return GestureDetector(
          onTap: () => onChanged(isSelected ? 0 : $label),
          child: Tooltip(
            message: $name,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: $color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: $label == 0
                  ? Icon(Icons.close, size: 18,
                      color: Theme.of(context).colorScheme.secondary)
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 色标条 — 显示在缩略图底部
class ColorLabelBar extends StatelessWidget {
  final int colorLabel;
  final double height;

  const ColorLabelBar({
    super.key,
    required this.colorLabel,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (colorLabel == 0) return const SizedBox.shrink();

    final color = AppTheme.colorLabelColor(colorLabel);
    if (color == null) return const SizedBox.shrink();

    return Container(
      height: height,
      color: color,
    );
  }
}