// SPDX-License-Identifier: Apache-2.0

/// Unified error type hierarchy.
sealed class AppException implements Exception {
  final String message;
  final String? detail;

  const AppException(this.message, {this.detail});

  @override
  String toString() => detail != null ? '$message: $detail' : message;
}

/// Database-related errors.
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.detail});
}

/// File system-related errors.
class FileSystemAppException extends AppException {
  const FileSystemAppException(super.message, {super.detail});
}

/// EXIF/metadata parsing errors.
class MetadataException extends AppException {
  const MetadataException(super.message, {super.detail});
}

/// Thumbnail generation errors.
class ThumbnailException extends AppException {
  const ThumbnailException(super.message, {super.detail});
}

/// Result type — unified success/failure return.
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

final class Failure<T> extends Result<T> {
  final AppException error;
  const Failure(this.error);
}

