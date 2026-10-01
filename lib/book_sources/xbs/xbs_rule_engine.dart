import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../protocol/book_source_protocol.dart';
import 'xbs_javascript.dart';

class XbsRuleEngine {
  XbsRuleEngine(this.javascript, this.config, this.params);
  final XbsJavascript javascript;
  final Map<String, dynamic> config;
  final Map<String, dynamic> params;

  Future<Object?> evaluate(
    Object? input,
    Object? rule, {
    bool nodes = false,
    bool content = false,
  }) async {
    if (rule == null || rule == '') return nodes ? [input] : '';
    if (rule is! String) return rule;
    final scriptIndex = rule.indexOf('@js:');
    if (scriptIndex >= 0) {
      final selector = rule
          .substring(0, scriptIndex)
          .replaceFirst(RegExp(r'\|+$'), '');
      final selected = selector.isEmpty
          ? _serializable(input)
          : await evaluate(input, selector, nodes: nodes, content: content);
      return javascript.evaluate(
        rule.substring(scriptIndex + 4),
        config,
        params,
        _serializable(selected),
      );
    }
    for (final alternative in rule.split('||')) {
      final value = _select(input, alternative.trim(), nodes, content);
      if (value is List ? value.isNotEmpty : value != null && value != '') {
        return value;
      }
    }
    return nodes ? <Object?>[] : '';
  }

  Future<String> text(
    Object? input,
    Object? rule, {
    bool content = false,
  }) async {
    final result = await evaluate(input, rule, content: content);
    if (result is List) {
      return result.map((e) => '$e').join(content ? '\n' : '');
    }
    return result == null ? '' : '$result';
  }

  Object? _select(Object? input, String rule, bool nodes, bool content) {
    if (rule.isEmpty) return input;
    if ((rule.startsWith("'") && rule.endsWith("'")) ||
        (rule.startsWith('"') && rule.endsWith('"'))) {
      return rule.substring(1, rule.length - 1);
    }
    if (input is Map || input is List) return _json(input, rule, nodes);
    final node = input is Node ? input : html.parse('$input').documentElement!;
    if (!rule.startsWith('/') && !rule.startsWith('.')) {
      throw const BookSourceProtocolException('XBS：不支持此选择器语法');
    }
    final query = HtmlXPath.node(node).query(rule);
    if (nodes) return query.nodes.map((e) => e.node).toList();
    if (content && !rule.contains('/@') && !rule.endsWith('text()')) {
      return query.nodes
          .map((e) => e.node)
          .whereType<Element>()
          .map((e) => e.outerHtml)
          .join('\n');
    }
    final values = query.attrs.isNotEmpty
        ? query.attrs
        : query.nodes.map((node) => node.text);
    return values.whereType<String>().join(content ? '\n' : '');
  }

  Object? _json(Object? input, String rule, bool nodes) {
    var values = <Object?>[input];
    final path = rule
        .replaceFirst(RegExp(r'^\$[./]?'), '')
        .replaceAllMapped(RegExp(r'\[(\d+|\*)\]'), (m) => '/${m[1]}');
    for (final part in path.split(RegExp(r'[/.]')).where((e) => e.isNotEmpty)) {
      values = values.expand((value) => _jsonStep(value, part)).toList();
    }
    if (nodes) return values.expand((e) => e is List ? e : [e]).toList();
    return values.length == 1 ? values.first : values;
  }

  Iterable<Object?> _jsonStep(Object? value, String part) {
    if (value is Map) return value.containsKey(part) ? [value[part]] : [];
    if (value is! List) return [];
    if (part == '*') return value;
    final index = int.tryParse(part);
    if (index != null) {
      return index >= 0 && index < value.length ? [value[index]] : [];
    }
    return value.expand((item) => _jsonStep(item, part));
  }

  Object? _serializable(Object? value) {
    if (value is Element) return value.outerHtml;
    if (value is Node) return value.text;
    if (value is List) return value.map(_serializable).toList();
    return value;
  }

  static Object document(String body, Map<String, dynamic> config) =>
      config['responseFormatType'] == 'json' ? jsonDecode(body) : body;
}
