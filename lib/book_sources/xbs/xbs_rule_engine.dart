import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../protocol/book_source_protocol.dart';
import 'xbs_javascript.dart';
import 'xbs_json_path.dart';

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
    bool first = false,
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
          : await evaluate(
              input,
              selector,
              nodes: nodes,
              content: content,
              first: first,
            );
      return javascript.evaluate(
        rule.substring(scriptIndex + 4),
        config,
        params,
        _serializable(selected),
      );
    }
    final replacements = rule.split(RegExp(r'\|{1,2}\s*@replace:'));
    if (replacements.length > 1) {
      var value = await text(
        input,
        replacements.first,
        content: content,
        first: first,
      );
      for (final replacement in replacements.skip(1)) {
        value = value.replaceAll(replacement.trim(), '');
      }
      return value;
    }
    for (final alternative in rule.split('||')) {
      final value = _select(input, alternative.trim(), nodes, content, first);
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
    bool first = false,
  }) async {
    final result = await evaluate(input, rule, content: content, first: first);
    if (result is List) {
      if (first) {
        return result
                .where((value) => value != null && '$value'.trim().isNotEmpty)
                .firstOrNull
                ?.toString() ??
            '';
      }
      return result.map((e) => '$e').join(content ? '\n' : '');
    }
    return result == null ? '' : '$result';
  }

  Object? _select(
    Object? input,
    String rule,
    bool nodes,
    bool content,
    bool first,
  ) {
    if (rule.isEmpty) return input;
    if ((rule.startsWith("'") && rule.endsWith("'")) ||
        (rule.startsWith('"') && rule.endsWith('"'))) {
      return rule.substring(1, rule.length - 1);
    }
    if (input is Map || input is List) {
      final value = XbsJsonPath.select(input, rule, nodes: nodes);
      if (first && !nodes && value is List) {
        return value
                .where((entry) => entry != null && '$entry'.trim().isNotEmpty)
                .firstOrNull ??
            '';
      }
      return value;
    }
    final node = input is Element && rule.startsWith('//')
        ? (DocumentFragment()..nodes.add(input.clone(true)))
        : input is Node
        ? input
        : html.parse('$input').documentElement!;
    if (!rule.startsWith('/') && !rule.startsWith('.')) {
      throw const BookSourceProtocolException('XBS：不支持此选择器语法');
    }
    // Legacy XBS rules sometimes omit quotes in wildcard attribute values.
    final xpath = rule.replaceAllMapped(
      RegExp(r'\[@\*\s*(=|!=)\s*([A-Za-z_][\w-]*)\s*\]'),
      (match) => '[@*${match[1]}"${match[2]}"]',
    );
    final query = HtmlXPath.node(node).query(xpath);
    if (nodes) return query.nodes.map((e) => e.node).toList();
    if (content && !rule.contains('/@') && !rule.contains('/text()')) {
      return query.nodes
          .map((e) => e.node)
          .whereType<Element>()
          .map((e) => e.outerHtml)
          .join('\n');
    }
    final values = query.attrs.isNotEmpty
        ? query.attrs
        : query.nodes.map((node) => node.text);
    final strings = values.whereType<String>();
    if (first) {
      return strings.where((value) => value.trim().isNotEmpty).firstOrNull ??
          '';
    }
    return strings.join(content ? '\n' : '');
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
