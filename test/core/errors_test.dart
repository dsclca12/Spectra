import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/errors.dart';

void main() {
  group('AppException', () {
    test('DatabaseException 带有消息和详情', () {
      final e = DatabaseException('连接失败', detail: '超时');
      expect(e.message, '连接失败');
      expect(e.detail, '超时');
      expect(e.toString(), '连接失败: 超时');
    });

    test('FileSystemAppException 格式化正确', () {
      final e = FileSystemAppException('文件未找到');
      expect(e.toString(), '文件未找到');
    });

    test('MetadataException 带详情构造', () {
      final e = MetadataException('EXIF 解析失败', detail: 'unsupported format');
      expect(e.detail, 'unsupported format');
    });

    test('ThumbnailException 可抛出', () {
      expect(
        () => throw ThumbnailException('生成失败'),
        throwsA(isA<ThumbnailException>()),
      );
    });
  });

  group('Result', () {
    test('Success 保存数据', () {
      final result = Success(42);
      expect(result.data, 42);
    });

    test('Failure 保存错误', () {
      final result = Failure<String>(DatabaseException('出错啦'));
      expect(result.error, isA<DatabaseException>());
      expect(result.error.message, '出错啦');
    });

    test('Result 可以模式匹配', () {
      Result<int> result = Success(1);
      switch (result) {
        case Success(:final data):
          expect(data, 1);
        case Failure():
          fail('不应是 Failure');
      }
    });

    test('Failure toString 委托给 error', () {
      final result = Failure<String>(MetadataException('bad format'));
      expect(result.error.toString(), 'bad format');
    });
  });
}
