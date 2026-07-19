import '../database/app_database.dart';

/// A tag tree node — used to build a hierarchical tag tree.
class TagNode {
  final Tag tag;
  final List<TagNode> children;
  final int photoCount;

  const TagNode({
    required this.tag,
    required this.children,
    this.photoCount = 0,
  });

  /// Whether this node has child tags.
  bool get hasChildren => children.isNotEmpty;

  /// Create a copy with optional field overrides.
  TagNode copyWith({
    Tag? tag,
    List<TagNode>? children,
    int? photoCount,
  }) {
    return TagNode(
      tag: tag ?? this.tag,
      children: children ?? this.children,
      photoCount: photoCount ?? this.photoCount,
    );
  }
}