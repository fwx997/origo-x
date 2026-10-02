import 'dart:convert';

import '../protocol/book_source_protocol.dart';

/// The JSONPath subset used by XBS DOM rules. Filters never execute code.
class XbsJsonPath {
  static final _token = RegExp(
    r'''\[(?:\?\([^\]]*\)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\d+|\*)\]|[\w$*-]+''',
  );
  static final _predicate = RegExp(
    r'''^\?\(@\.([\w.]+)\s*(?:(==|!=)\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|-?\d+(?:\.\d+)?|true|false|null))?\s*\)$''',
  );

  static Object? select(Object? input, String path, {bool nodes = false}) {
    var values = <Object?>[input];
    var offset = path.startsWith(r'$') ? 1 : 0;
    while (offset < path.length) {
      final recursive = path.startsWith('..', offset);
      if (recursive) {
        offset += 2;
      } else if (path[offset] == '.' || path[offset] == '/') {
        offset++;
      }
      final match = _token.matchAsPrefix(path, offset);
      if (match == null) _unsupported();
      final step = _Step(match[0]!);
      values = values
          .expand(
            (value) => recursive
                ? _descendants(
                    value,
                  ).expand((node) => step.select(node, recursive: true))
                : step.select(value),
          )
          .toList();
      offset = match.end;
    }
    if (nodes) {
      return values.expand((value) => value is List ? value : [value]).toList();
    }
    return values.length == 1 ? values.first : values;
  }

  static Iterable<Object?> _descendants(Object? value) sync* {
    yield value;
    final children = value is Map
        ? value.values
        : value is List
        ? value
        : const [];
    for (final child in children) {
      yield* _descendants(child);
    }
  }

  static Never _unsupported() =>
      throw const BookSourceProtocolException('XBS：不支持此 JSON 路径语法');
}

class _Step {
  _Step(String token) {
    key = token.startsWith('[') ? token.substring(1, token.length - 1) : token;
    if (key.startsWith('?')) {
      predicate = XbsJsonPath._predicate.firstMatch(key);
      if (predicate == null) XbsJsonPath._unsupported();
      expected = predicate![2] == null ? null : _literal(predicate![3]!);
    } else if (key.startsWith('"') || key.startsWith("'")) {
      key = _literal(key) as String;
      quoted = true;
    }
  }

  late final Object? expected;
  late String key;
  RegExpMatch? predicate;
  bool quoted = false;

  static Object? _literal(String value) => value.startsWith("'")
      ? value
            .substring(1, value.length - 1)
            .replaceAll(r"\'", "'")
            .replaceAll(r'\\', r'\')
      : jsonDecode(value);

  Iterable<Object?> select(Object? value, {bool recursive = false}) {
    if (predicate != null) return _children(value).where(_matches);
    if (key == '*' && !quoted) return _children(value);
    if (value is Map) return value.containsKey(key) ? [value[key]] : [];
    if (value is! List) return [];
    final index = quoted ? null : int.tryParse(key);
    if (index != null) return index < value.length ? [value[index]] : [];
    // Recursive traversal visits the elements itself; do not emit them twice.
    return recursive ? [] : value.expand((item) => select(item));
  }

  Iterable<Object?> _children(Object? value) => value is Map
      ? value.values
      : value is List
      ? value
      : const [];

  bool _matches(Object? value) {
    Object? selected = value;
    for (final part in predicate![1]!.split('.')) {
      if (selected is! Map || !selected.containsKey(part)) return false;
      selected = selected[part];
    }
    return switch (predicate![2]) {
      '==' => selected == expected,
      '!=' => selected != expected,
      _ => true,
    };
  }
}
