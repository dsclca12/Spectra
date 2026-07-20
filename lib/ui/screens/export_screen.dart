import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/database/app_database.dart';
import '../../data/models/photo_filter.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';

/// 导出对话框 — 按筛选条件或选中照片导出到目标文件夹
class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key});

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  /// 导出范围
  _ExportScope _scope = _ExportScope.filtered;

  /// 是否保留目录结构
  bool _preserveStructure = false;

  /// 导出状态
  _ExportStatus _status = _ExportStatus.idle;

  /// 进度信息
  int _exported = 0;
  int _total = 0;
  String _currentFile = '';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final selection = ref.watch(selectionProvider);

    return AlertDialog(
      title: const Text('导出照片'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_status == _ExportStatus.idle) ...[
              // 导出范围选择
              const Text('导出范围', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              RadioListTile<_ExportScope>(
                title: Text(_filterDescription(filter)),
                value: _ExportScope.filtered,
                groupValue: _scope,
                dense: true,
                onChanged: (v) => setState(() => _scope = v!),
              ),
              if (selection.hasSelection)
                RadioListTile<_ExportScope>(
                  title: Text('选中的 ${selection.count} 张照片'),
                  value: _ExportScope.selected,
                  groupValue: _scope,
                  dense: true,
                  onChanged: (v) => setState(() => _scope = v!),
                ),
              RadioListTile<_ExportScope>(
                title: const Text('所有照片'),
                value: _ExportScope.all,
                groupValue: _scope,
                dense: true,
                onChanged: (v) => setState(() => _scope = v!),
              ),

              const SizedBox(height: 16),

              // 目录结构选项
              CheckboxListTile(
                title: const Text('保留原始目录结构'),
                subtitle: const Text('不勾选则所有文件平铺在同一目录'),
                value: _preserveStructure,
                dense: true,
                onChanged: (v) => setState(() => _preserveStructure = v ?? false),
              ),

              const SizedBox(height: 16),

              // 当前筛选条件摘要
              if (filter.hasActiveFilters) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前筛选条件:',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._buildFilterSummary(filter),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ] else if (_status == _ExportStatus.exporting) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Text('正在导出: $_exported / $_total'),
              if (_currentFile.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _currentFile,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ] else if (_status == _ExportStatus.completed) ...[
              const Icon(Icons.check_circle, size: 48, color: Colors.green),
              const SizedBox(height: 16),
              Text('导出完成: $_exported 张'),
              if (_exported < _total)
                Text('跳过: ${_total - _exported} 张（源文件不存在）'),
            ] else if (_status == _ExportStatus.error) ...[
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('导出失败: $_error'),
            ],
          ],
        ),
      ),
      actions: [
        if (_status == _ExportStatus.idle) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton.icon(
            onPressed: _startExport,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('选择目标文件夹并导出'),
          ),
        ],
        if (_status == _ExportStatus.completed ||
            _status == _ExportStatus.error)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
      ],
    );
  }

  /// 筛选条件描述
  String _filterDescription(PhotoFilter filter) {
    final parts = <String>[];
    if (filter.minRating != null) {
      if (filter.minRating == 0 && filter.maxRating == 0) {
        parts.add('未评分');
      } else {
        parts.add('≥${filter.minRating}星');
      }
    }
    if (filter.pickLabel != null) {
      parts.add(switch (filter.pickLabel) {
        1 => 'Pick',
        2 => 'Reject',
        _ => '旗标',
      });
    }
    if (filter.colorLabels != null && filter.colorLabels!.isNotEmpty) {
      parts.add('色标(${filter.colorLabels!.length})');
    }
    if (filter.dateFrom != null || filter.dateTo != null) {
      parts.add('日期范围');
    }
    if (filter.cameraModel != null && filter.cameraModel!.isNotEmpty) {
      parts.add(filter.cameraModel!);
    }
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      parts.add('搜索"${filter.searchQuery}"');
    }
    if (parts.isEmpty) return '当前筛选的照片';
    return '当前筛选 (${parts.join(', ')})';
  }

  /// 构建筛选条件摘要
  List<Widget> _buildFilterSummary(PhotoFilter filter) {
    final widgets = <Widget>[];
    if (filter.minRating != null) {
      if (filter.minRating == 0 && filter.maxRating == 0) {
        widgets.add(_filterChip('未评分'));
      } else {
        widgets.add(_filterChip('星级 ≥ ${filter.minRating}'));
      }
    }
    if (filter.pickLabel != null) {
      widgets.add(_filterChip(switch (filter.pickLabel) {
        1 => '🚩 Pick',
        2 => '✗ Reject',
        _ => '旗标',
      }));
    }
    if (filter.colorLabels != null) {
      for (final c in filter.colorLabels!) {
        final name = switch (c) {
          1 => '红',
          2 => '黄',
          3 => '绿',
          4 => '蓝',
          5 => '紫',
          6 => '灰',
          _ => '色标$c',
        };
        widgets.add(_filterChip('🏷️ $name'));
      }
    }
    if (filter.dateFrom != null || filter.dateTo != null) {
      widgets.add(_filterChip('📅 日期范围'));
    }
    if (filter.cameraModel != null && filter.cameraModel!.isNotEmpty) {
      widgets.add(_filterChip('📷 ${filter.cameraModel}'));
    }
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      widgets.add(_filterChip('🔍 "${filter.searchQuery}"'));
    }
    return widgets;
  }

  Widget _filterChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  /// 开始导出
  Future<void> _startExport() async {
    // 选择目标文件夹
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目标文件夹',
    );
    if (result == null) return;

    final targetDir = result;

    setState(() {
      _status = _ExportStatus.exporting;
      _exported = 0;
      _total = 0;
      _currentFile = '';
      _error = null;
    });

    try {
      final catalogService = ref.read(catalogServiceProvider);
      final exportService = ref.read(exportServiceProvider);
      final filter = ref.read(filterProvider);
      final folderId = ref.read(currentFolderProvider);
      final selection = ref.read(selectionProvider);

      // 获取要导出的照片列表
      List<Photo> photos;

      switch (_scope) {
        case _ExportScope.selected:
          if (!selection.hasSelection) {
            setState(() {
              _status = _ExportStatus.error;
              _error = '没有选中的照片';
            });
            return;
          }
          photos = await catalogService.getPhotosByIds(
            selection.selectedIds.toList(),
          );
        case _ExportScope.all:
          photos = await catalogService.queryAllPhotos(
            folderId: null,
            filter: const PhotoFilter(),
          );
        case _ExportScope.filtered:
          photos = await catalogService.queryAllPhotos(
            folderId: folderId,
            filter: filter,
          );
      }

      if (photos.isEmpty) {
        setState(() {
          _status = _ExportStatus.error;
          _error = '没有符合条件的照片可导出';
        });
        return;
      }

      final photoPaths = photos.map((p) => p.path).toList();

      // 确定公共根路径（用于保留目录结构）
      String? commonRootPath;
      if (_preserveStructure && photos.isNotEmpty) {
        // 取所有照片路径的公共前缀目录
        commonRootPath = _findCommonRoot(photoPaths);
      }

      final exported = await exportService.exportPhotos(
        photoPaths: photoPaths,
        targetDir: targetDir,
        preserveStructure: _preserveStructure,
        commonRootPath: commonRootPath,
        onProgress: (exported, total, currentFile) {
          if (mounted) {
            setState(() {
              _exported = exported;
              _total = total;
              _currentFile = currentFile;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _exported = exported;
          _total = photoPaths.length;
          _status = _ExportStatus.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _ExportStatus.error;
          _error = e.toString();
        });
      }
    }
  }

  /// 找出一组文件路径的公共父目录
  String? _findCommonRoot(List<String> paths) {
    if (paths.isEmpty) return null;
    if (paths.length == 1) return p.dirname(paths.first);

    String common = p.dirname(paths.first);
    for (final path in paths.skip(1)) {
      final dir = p.dirname(path);
      while (!dir.startsWith(common) && common.isNotEmpty) {
        final parent = p.dirname(common);
        if (parent == common) break;
        common = parent;
      }
    }
    return common;
  }
}

/// 导出范围
enum _ExportScope { filtered, selected, all }

/// 导出状态
enum _ExportStatus { idle, exporting, completed, error }