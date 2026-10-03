import 'package:flutter/material.dart';
import 'source_filter_widgets.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';

class SourceSelection {
  const SourceSelection(this.id);
  final String? id;
}

Future<SourceSelection?> showSourcePicker(
  BuildContext context, {
  required List<RegisteredBookSource> sources,
  required String? selectedId,
  bool allowAll = true,
}) => showModalBottomSheet<SourceSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => _SourcePicker(
    sources: sources,
    selectedId: selectedId,
    allowAll: allowAll,
  ),
);

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({
    required this.sources,
    required this.selectedId,
    required this.allowAll,
  });
  final bool allowAll;
  final List<RegisteredBookSource> sources;
  final String? selectedId;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  late String? _selected = widget.selectedId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.sources.where((source) {
      final text = '${source.name} ${source.apiBaseUrl.host}'.toLowerCase();
      return text.contains(_query);
    }).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .75,
        child: Column(
          children: [
            _header(),
            _search(),
            Expanded(child: _list(matches)),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
    child: Row(
      children: [
        TextButton(
          style: sourceTextActionStyle(context),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        Expanded(
          child: Text(
            '切换站点',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        TextButton(
          style: sourceTextActionStyle(context),
          key: const Key('sourcePickerConfirm'),
          onPressed: !widget.allowAll && _selected == null
              ? null
              : () => Navigator.pop(context, SourceSelection(_selected)),
          child: const Text('确定'),
        ),
      ],
    ),
  );

  Widget _search() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: TextField(
      key: const Key('sourcePickerQuery'),
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 32,
        ),
        hintText: '搜索站点名称或域名',
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _list(List<RegisteredBookSource> matches) => ListView.builder(
    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    itemCount: matches.length + (widget.allowAll ? 2 : 1),
    itemBuilder: (context, index) {
      if (widget.allowAll && index == 0) return _row(null, '全部站点', '跨站点搜索');
      if (index == (widget.allowAll ? 1 : 0)) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(matches.isEmpty ? '没有匹配的站点' : '可用站点 · ${matches.length}'),
        );
      }
      final source = matches[index - (widget.allowAll ? 2 : 1)];
      return _row(source.id, source.name, source.apiBaseUrl.host);
    },
  );

  Widget _row(String? id, String title, String subtitle) => ListTile(
    key: ValueKey('sourcePicker-${id ?? 'all'}'),
    selected: _selected == id,
    dense: true,
    visualDensity: VisualDensity.compact,
    minLeadingWidth: 20,
    horizontalTitleGap: 10,
    titleTextStyle: Theme.of(context).textTheme.bodySmall,
    subtitleTextStyle: Theme.of(context).textTheme.labelSmall,
    leading: const Icon(Icons.language_rounded, size: 18),
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: _selected == id ? const Icon(Icons.check_rounded) : null,
    onTap: () => setState(() => _selected = id),
  );
}
