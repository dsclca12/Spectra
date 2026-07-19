/// Rating values (0-5).
class Rating {
  Rating._();

  static const int none = 0;
  static const int one = 1;
  static const int two = 2;
  static const int three = 3;
  static const int four = 4;
  static const int five = 5;

  static bool isValid(int value) => value >= 0 && value <= 5;
}

/// Pick label flags.
class PickLabel {
  PickLabel._();

  static const int none = 0;
  static const int pick = 1;
  static const int reject = 2;

  static bool isValid(int value) => value >= 0 && value <= 2;
}

/// Color labels.
class ColorLabel {
  ColorLabel._();

  static const int none = 0;
  static const int red = 1;
  static const int yellow = 2;
  static const int green = 3;
  static const int blue = 4;
  static const int purple = 5;
  static const int gray = 6;

  static bool isValid(int value) => value >= 0 && value <= 6;
}

/// Thumbnail generation status.
class ThumbnailStatus {
  ThumbnailStatus._();

  static const int notGenerated = 0;
  static const int generating = 1;
  static const int generated = 2;
  static const int failed = 3;
}

/// Sync status flags.
class SyncStatus {
  SyncStatus._();

  static const int normal = 0;
  static const int fileMissing = 1;
  static const int modified = 2;
}