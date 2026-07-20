import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';

/// 元数据展示组件 — 显示 EXIF 信息
class MetadataView extends StatelessWidget {
  final Photo photo;

  const MetadataView({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    final exifEntries = _buildExifEntries();
    if (exifEntries.isEmpty) {
      return Text(
        '无 EXIF 数据',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.secondary,
        ),
      );
    }

    return Column(
      children: exifEntries.map((entry) => _MetadataRow(
        label: entry.label,
        value: entry.value,
      )).toList(),
    );
  }

  List<_ExifEntry> _buildExifEntries() {
    final entries = <_ExifEntry>[];

    if (photo.cameraMake != null || photo.cameraModel != null) {
      final camera = [
        photo.cameraMake ?? '',
        photo.cameraModel ?? '',
      ].where((s) => s.isNotEmpty).join(' ');
      entries.add(_ExifEntry('相机', camera));
    }

    if (photo.lensModel != null) {
      entries.add(_ExifEntry('镜头', photo.lensModel!));
    }

    if (photo.focalLength != null) {
      var focal = '${photo.focalLength!.toStringAsFixed(0)}mm';
      if (photo.focalLength35mm != null) {
        focal += ' (35mm: ${photo.focalLength35mm!.toStringAsFixed(0)}mm)';
      }
      entries.add(_ExifEntry('焦距', focal));
    }

    if (photo.aperture != null) {
      entries.add(_ExifEntry('光圈', 'f/${photo.aperture!.toStringAsFixed(1)}'));
    }

    if (photo.shutterSpeed != null) {
      entries.add(_ExifEntry('快门', photo.shutterSpeed!));
    }

    if (photo.iso != null) {
      entries.add(_ExifEntry('ISO', photo.iso!.toStringAsFixed(0)));
    }

    if (photo.exposureBias != null) {
      entries.add(_ExifEntry('曝光补偿', '${photo.exposureBias!.toStringAsFixed(1)} EV'));
    }

    if (photo.meteringMode != null) {
      entries.add(_ExifEntry('测光', photo.meteringMode!));
    }

    if (photo.whiteBalance != null) {
      entries.add(_ExifEntry('白平衡', photo.whiteBalance!));
    }

    if (photo.flash != null) {
      entries.add(_ExifEntry('闪光灯', photo.flash!));
    }

    if (photo.dateTaken != null) {
      entries.add(_ExifEntry('拍摄时间', _formatDateTime(photo.dateTaken!)));
    }

    return entries;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _ExifEntry {
  final String label;
  final String value;

  const _ExifEntry(this.label, this.value);
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Consolas',
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}