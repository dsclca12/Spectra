import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/edit_params.dart';
import '../../providers/edit_provider.dart';

/// 历史面板 — 显示操作历史，可回退到任意历史节点
///
/// 实时特性：
/// - 编辑后立即显示[内存级历史]条目（带"待保存"标签），无需等待 DB 写入
/// - DB 持久化完成后自动合并，移除"待保存"标签
class HistoryPanel extends ConsumerWidget {
  final int photoId;

  const HistoryPanel({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(editSessionProvider(photoId));
    final hasAny = session.history.isNotEmpty || session.localHistory.isNotEmpty;
    final theme = Theme.of(context);

    if (!hasAny) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 40, color: theme.colorScheme.secondary),
              const SizedBox(height: 12),
              Text('还没有编辑历史',
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.secondary)),
              const SizedBox(height: 4),
              Text('编辑操作会自动记录到历史中',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.secondary)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 历史列表
        // Material 为 ListTile 提供 ink splash 容器，
        // 避免 "ListTile background color or ink splashes may be invisible" 警告
        Expanded(
          child: Material(
            color: theme.canvasColor,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _totalItemCount(session),
              itemBuilder: (context, index) {
                // 第 0 项是"当前"状态
                if (index == 0) {
                  return _CurrentStateTile(
                    params: session.params,
                    isDirty: session.isDirty,
                    isPreviewing: session.previewHistoryId != null,
                    onTap: () {
                      ref
                          .read(editSessionProvider(photoId).notifier)
                          .clearPreview();
                    },
                  );
                }
                // 初始状态在最后一项（DB 历史 + 本地历史 + 1（当前状态）后的最后一项）
                final dbCount = session.history.length;
                final localCount = session.localHistory.length;
                final lastIndex = dbCount + localCount + 1; // +1 for current state
                if (index == lastIndex) {
                  return _InitialStateTile(
                    photoId: photoId,
                    isPreviewing: session.previewHistoryId == 0,
                  );
                }
                // 本地历史条目（在 DB 历史之前，最新的在最前面）
                if (index <= localCount) {
                  final entry = session.localHistory[localCount - index];
                  return _LocalHistoryTile(
                    entry: entry,
                    photoId: photoId,
                  );
                }
                // DB 持久化历史记录
                final dbIndex = index - localCount - 1;
                final entry = session.history[dbIndex];
                return _HistoryTile(
                  entry: entry,
                  photoId: photoId,
                  isPreviewing: session.previewHistoryId == entry.id,
                );
              },
            ),
          ),
        ),
        // 清空历史按钮
        if (session.history.isNotEmpty || session.localHistory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => _showClearConfirm(context, ref),
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('清空历史'),
            ),
          ),
      ],
    );
  }

  /// 计算总条目数：当前状态 + 本地历史 + DB 历史 + 初始状态
  int _totalItemCount(EditSessionState session) {
    return 1 + session.localHistory.length + session.history.length + 1;
  }

  void _showClearConfirm(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有编辑历史吗？快照不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(editSessionProvider(photoId).notifier).clearHistory();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

/// 当前状态条目
class _CurrentStateTile extends StatelessWidget {
  final EditParams params;
  final bool isDirty;
  final bool isPreviewing;
  final VoidCallback? onTap;

  const _CurrentStateTile({
    required this.params,
    required this.isDirty,
    this.isPreviewing = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 预览中时降低不透明度，提示当前状态不是正在显示的状态
    final opacity = isPreviewing ? 0.5 : 1.0;

    // Material(type: MaterialType.transparency) 在容器内为 ListTile 提供
    // ink splash 表面，避免 DecoratedBox 隔断后 "ListTile background color
    // or ink splashes may be invisible" 警告。
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
          title: Text(
            isDirty ? '当前编辑（未保存）' : '当前编辑',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary.withValues(alpha: opacity),
            ),
          ),
          subtitle: Text(
            _describeParams(params),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.secondary.withValues(alpha: opacity),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// 初始状态条目 — 代表原始未编辑的照片状态（默认参数）
class _InitialStateTile extends ConsumerWidget {
  final int photoId;
  final bool isPreviewing;

  const _InitialStateTile({
    required this.photoId,
    this.isPreviewing = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final bgColor = isPreviewing
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : null;
    final leadingIcon = isPreviewing
        ? Icon(Icons.visibility, size: 16, color: theme.colorScheme.primary)
        : Icon(Icons.photo_outlined, size: 16, color: theme.colorScheme.secondary);
    final titleColor = isPreviewing ? theme.colorScheme.primary : null;

    return Container(
      decoration: bgColor != null
          ? BoxDecoration(
              color: bgColor,
              border: Border(
                left:
                    BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            )
          : null,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          leading: leadingIcon,
          title: Text(
            '初始',
            style: TextStyle(fontSize: 13, color: titleColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '原始照片 · 无调整',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 点击 — 预览初始状态
          onTap: () {
            ref
                .read(editSessionProvider(photoId).notifier)
                .previewHistory(0);
          },
          // 长按 — 恢复到初始状态
          onLongPress: () {
            _showRestoreConfirm(context, ref);
          },
          trailing: isPreviewing
              ? TextButton.icon(
                  onPressed: () {
                    ref
                        .read(editSessionProvider(photoId).notifier)
                        .restoreHistory(0);
                  },
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('恢复'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _showRestoreConfirm(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复到初始状态'),
        content: const Text('将编辑参数重置为默认值（原始照片状态）。'
            '当前编辑将被推入撤销栈，可通过撤销恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref
                  .read(editSessionProvider(photoId).notifier)
                  .restoreHistory(0);
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }
}

/// 历史记录条目
class _HistoryTile extends ConsumerWidget {
  final EditHistoryData entry;
  final int photoId;
  final bool isPreviewing;

  const _HistoryTile({
    required this.entry,
    required this.photoId,
    this.isPreviewing = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = EditParams.fromJson(
      jsonDecode(entry.paramsJson) as Map<String, dynamic>,
    );

    // 预览中的条目高亮显示
    final bgColor = isPreviewing
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : null;
    final leadingIcon = isPreviewing
        ? Icon(Icons.visibility, size: 16, color: theme.colorScheme.primary)
        : Icon(Icons.history, size: 16, color: theme.colorScheme.secondary);
    final titleColor = isPreviewing ? theme.colorScheme.primary : null;

    return Container(
      decoration: bgColor != null
          ? BoxDecoration(
              color: bgColor,
              border: Border(
                left: BorderSide(
                    color: theme.colorScheme.primary, width: 3),
              ),
            )
          : null,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          leading: leadingIcon,
          title: Text(
            entry.actionLabel ?? '编辑操作',
            style: TextStyle(fontSize: 13, color: titleColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_formatDate(entry.createdAt)} · ${_describeParams(params)}',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 点击 — 预览该历史节点（不修改实际编辑状态）
          onTap: () {
            ref
                .read(editSessionProvider(photoId).notifier)
                .previewHistory(entry.id);
          },
          // 长按 — 恢复到该历史节点（提交为当前编辑）
          onLongPress: () {
            _showRestoreConfirm(context, ref, entry);
          },
          trailing: isPreviewing
              ? TextButton.icon(
                  onPressed: () {
                    ref
                        .read(editSessionProvider(photoId).notifier)
                        .restoreHistory(entry.id);
                  },
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('恢复'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _showRestoreConfirm(
      BuildContext context, WidgetRef ref, EditHistoryData entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复到此历史节点'),
        content: Text('将编辑参数恢复到「${entry.actionLabel ?? '编辑操作'}」时的状态。'
            '当前编辑将被推入撤销栈，可通过撤销恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref
                  .read(editSessionProvider(photoId).notifier)
                  .restoreHistory(entry.id);
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 内存级历史条目 — 尚未持久化到数据库的编辑操作。
///
/// 显示在 DB 历史之上，带「待保存」小标签提示用户。
/// 持久化完成后会自动合并到 DB 历史，此条目消失。
class _LocalHistoryTile extends ConsumerWidget {
  final EditLocalHistoryEntry entry;
  final int photoId;

  const _LocalHistoryTile({
    required this.entry,
    required this.photoId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = EditParams.fromJson(
      jsonDecode(entry.paramsJson) as Map<String, dynamic>,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.orange.withValues(alpha: 0.6), width: 2),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          leading: Stack(
            children: [
              Icon(Icons.history, size: 16, color: Colors.orange.shade700),
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  entry.actionLabel ?? '编辑中…',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: const Text(
                  '待保存',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            '${_formatLocalDate(entry.createdAt)} · ${_describeParams(params)}',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 点击暂不提供预览（本地条目不参与预览/恢复，
          // 等持久化后自动合并到 DB 历史即可操作）
          enabled: false,
        ),
      ),
    );
  }

  String _formatLocalDate(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

/// 描述编辑参数（简短摘要）
String _describeParams(EditParams p) {
  final parts = <String>[];
  if (p.exposure != 0)
    parts
        .add('曝光 ${p.exposure > 0 ? '+' : ''}${p.exposure.toStringAsFixed(1)}');
  if (p.contrast != 0)
    parts.add('对比度 ${p.contrast > 0 ? '+' : ''}${p.contrast.round()}');
  if (p.highlights != 0)
    parts.add('高光 ${p.highlights > 0 ? '+' : ''}${p.highlights.round()}');
  if (p.shadows != 0)
    parts.add('阴影 ${p.shadows > 0 ? '+' : ''}${p.shadows.round()}');
  if (p.temperature != 0)
    parts.add(
        '色温 ${p.temperature > 0 ? '暖' : '冷'}${p.temperature.abs().round()}');
  if (p.saturation != 0)
    parts.add('饱和度 ${p.saturation > 0 ? '+' : ''}${p.saturation.round()}');
  if (p.vibrance != 0)
    parts.add('自然饱和度 ${p.vibrance > 0 ? '+' : ''}${p.vibrance.round()}');
  if (p.rotation != 0) parts.add('旋转 ${p.rotation}°');
  if (p.cropWidth < 1.0 || p.cropHeight < 1.0) parts.add('裁剪');
  if (parts.isEmpty) return '无调整';
  return parts.take(3).join(' · ');
}
