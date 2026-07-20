import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/tag_node.dart';
import '../../providers/providers.dart';
import '../../providers/tag_provider.dart';

/// 标签管理器对话框
class TagManagerDialog extends ConsumerWidget {
  const TagManagerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagTreeAsync = ref.watch(tagTreeProvider);

    return AlertDialog(
      title: const Text('标签管理'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            // 搜索/新建栏
            _TagSearchBar(),
            const Divider(),
            // 标签树
            Expanded(
              child: tagTreeAsync.when(
                data: (tree) => _TagTreeView(tree: tree),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 标签搜索栏
class _TagSearchBar extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TagSearchBar> createState() => _TagSearchBarState();
}

class _TagSearchBarState extends ConsumerState<_TagSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: '搜索或输入新标签名...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: (value) async {
              if (value.isNotEmpty) {
                await ref.read(tagSearchProvider(value).future);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () async {
            final name = _controller.text.trim();
            if (name.isNotEmpty) {
              await ref.read(tagServiceProvider).createTag(name);
              ref.invalidate(tagTreeProvider);
              ref.invalidate(allTagsProvider);
              _controller.clear();
            }
          },
          child: const Text('新建'),
        ),
      ],
    );
  }
}

/// 标签树视图
class _TagTreeView extends ConsumerWidget {
  final List<TagNode> tree;

  const _TagTreeView({required this.tree});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tree.isEmpty) {
      return Center(
        child: Text(
          '还没有标签',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: tree.length,
      itemBuilder: (context, index) => _TagNodeTile(node: tree[index]),
    );
  }
}

/// 标签节点
class _TagNodeTile extends ConsumerWidget {
  final TagNode node;

  const _TagNodeTile({required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 8),
      title: Row(
        children: [
          Text(node.tag.name, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Text(
            '${node.photoCount}',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 16),
        onPressed: () async {
          await ref.read(tagServiceProvider).deleteTag(node.tag.id);
          ref.invalidate(tagTreeProvider);
          ref.invalidate(allTagsProvider);
        },
      ),
      children: node.children
          .map((child) => Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _TagNodeTile(node: child),
              ))
          .toList(),
    );
  }
}