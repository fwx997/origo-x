import 'dart:convert';

import '../protocol/book_source_protocol.dart';

/// Original XBS supports a label/value map, named groups with `label::value`
/// lines, and key/items arrays. Preserve values verbatim for request scripts.
class XbsDiscovery {
  static List<BookSourceFilterGroup> filterGroups(Object? raw) {
    if (raw is List) return _arrayGroups(raw);
    if (raw is! String) return const [];
    final groups = <BookSourceFilterGroup>[];
    var name = 'filter';
    var options = <BookSourceFilterOption>[];
    void flush() {
      if (options.isEmpty) return;
      final seen = <String>{};
      groups.add(
        BookSourceFilterGroup(
          id: name,
          name: _groupName(name),
          options: options.where((option) => seen.add(option.value)).toList(),
        ),
      );
      options = [];
    }

    for (final text in const LineSplitter().convert(raw)) {
      final line = text.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf('::');
      if (separator < 0) {
        flush();
        name = line;
        continue;
      }
      options.add(
        BookSourceFilterOption(
          name: line.substring(0, separator),
          value: line.substring(separator + 2),
        ),
      );
    }
    flush();
    return groups;
  }

  static List<BookSourceFilterGroup> _arrayGroups(List<dynamic> raw) {
    final groups = <BookSourceFilterGroup>[];
    for (final entry in raw.whereType<Map>()) {
      final key = '${entry['key'] ?? ''}';
      final items = entry['items'];
      if (key.isEmpty || items is! List) continue;
      final seen = <String>{};
      final options = items
          .whereType<Map>()
          .map(
            (item) => BookSourceFilterOption(
              name: '${item['title'] ?? item['value'] ?? ''}',
              value: '${item['value'] ?? ''}',
              requestValue: item['value'],
            ),
          )
          .where((option) => seen.add(option.value))
          .toList(growable: false);
      if (options.isEmpty) continue;
      groups.add(
        BookSourceFilterGroup(
          id: key,
          name: '${entry['title'] ?? _groupName(key)}',
          options: options,
        ),
      );
    }
    return groups;
  }

  static String _groupName(String key) =>
      const {
        'type': '类型',
        'class': '分类',
        'sort': '排序',
        'status': '状态',
        'filter': '分类',
        'date_type': '时间',
        'tags': '标签',
      }[key] ??
      (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key) ? '筛选' : key);

  static String withFilters(String category, Map<String, String> filters) {
    final decoded = jsonDecode(category) as List;
    return jsonEncode([decoded[0], decoded[1], filters]);
  }
}
