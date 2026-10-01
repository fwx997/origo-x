import 'package:flutter/material.dart';

class SourceCheckOptions {
  const SourceCheckOptions(this.query, this.fullChain);
  final String query;
  final bool fullChain;
}

class SourceCheckDialog extends StatefulWidget {
  const SourceCheckDialog({super.key});
  @override
  State<SourceCheckDialog> createState() => _SourceCheckDialogState();
}

class _SourceCheckDialogState extends State<SourceCheckDialog> {
  final _query = TextEditingController();
  bool _fullChain = false;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('批量检测书源'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(labelText: '用于检测的书名'),
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('检测到正文'),
          subtitle: const Text('搜索、详情、目录和首章；不自动删除失败书源'),
          value: _fullChain,
          onChanged: (v) => setState(() => _fullChain = v),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _query.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                SourceCheckOptions(_query.text.trim(), _fullChain),
              ),
        child: const Text('开始'),
      ),
    ],
  );
}
