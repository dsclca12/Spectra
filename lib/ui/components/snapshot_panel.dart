import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/edit_params.dart';
import '../../providers/edit_provider.dart';

/// 快照面板 — 显示、创建、恢复、删除、重命名编辑快照
class SnapshotPanel extends ConsumerWidget {
  final int photoId;

  const SnapshotPanel({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(editSessionProvider(photoId));
    final snapshots = session.snapshots;
    final theme = Theme.of(context);

    if (snapshots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined,
                  size: 40, color: theme.colorScheme.secondary),
              const SizedBox(height: 12),
              Text('还没有快照',
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.secondary)),
              const SizedBox(height: 4),
              Text('创建快照以保存当前编辑状态',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.secondary)),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _showCreateDialog(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('创建快照'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 快照列表
        // Material 为 ListTile 提供 ink splash 容器，
        // 避免 "ListTile background color or ink splashes may be invisible" 警告
        Expanded(
          child: Material(
            color: theme.canvasColor,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: snapshots.length,
              itemBuilder: (context, index) {
                final snapshot = snapshots[index];
                return _SnapshotTile(
                  snapshot: snapshot,
                  photoId: photoId,
                );
              },
            ),
          ),
        ),
        // 创建快照按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.tonalIcon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('创建快照'),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建快照'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '快照名称',
            hintText: '如：暖色调、黑白风格…',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop();
              ref
                  .read(editSessionProvider(photoId).notifier)
                  .createSnapshot(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop();
                ref
                    .read(editSessionProvider(photoId).notifier)
                    .createSnapshot(name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 单个快照条目
class _SnapshotTile extends ConsumerWidget {
  final EditSnapshot snapshot;
  final int photoId;

  const _SnapshotTile({required this.snapshot, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Params loaded; kept for future thumbnail preview
    final _ = EditParams.fromJson(
      jsonDecode(snapshot.paramsJson) as Map<String, dynamic>,
    );

    return ListTile(
      dense: true,
      leading: Icon(
        snapshot.isAuto ? Icons.history : Icons.camera_alt,
        size: 18,
        color: theme.colorScheme.secondary,
      ),
      title: Text(
        snapshot.name,
        style: const TextStyle(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatDate(snapshot.createdAt),
        style: TextStyle(fontSize: 11, color: theme.colorScheme.secondary),
      ),
      trailing: PopupMenuButton<String>(
        icon:
            Icon(Icons.more_vert, size: 18, color: theme.colorScheme.secondary),
        tooltip: '操作',
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'restore', child: Text('恢复到此快照')),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
        onSelected: (action) {
          switch (action) {
            case 'restore':
              ref
                  .read(editSessionProvider(photoId).notifier)
                  .restoreSnapshot(snapshot.id);
            case 'rename':
              _showRenameDialog(context, ref);
            case 'delete':
              _showDeleteConfirm(context, ref);
          }
        },
      ),
      onTap: () {
        ref
            .read(editSessionProvider(photoId).notifier)
            .restoreSnapshot(snapshot.id);
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: snapshot.name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名快照'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '快照名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop();
                ref
                    .read(editSessionProvider(photoId).notifier)
                    .renameSnapshot(snapshot.id, name);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除快照'),
        content: Text('确定要删除快照「${snapshot.name}」吗？'),
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
                  .deleteSnapshot(snapshot.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
