import 'package:xpath_selector/src/reg.dart';
import 'package:xpath_selector/src/selector.dart';

import 'model/base.dart';

/// parse xpath selector
List<List<Selector>> parseSelectGroup(String xpath) {
  final combine = _splitPath(xpath, '|');
  final selectorList = <List<Selector>>[];

  for (final groupPath in combine) {
    final path = groupPath.trim();
    final xpathItem = _splitPath(path, '/').where((part) => part.isNotEmpty);
    selectorList.add(xpathItem.map(_parseSelector).toList());
  }

  return selectorList;
}

// Delimiters inside predicates or quoted values belong to that step.
Iterable<String> _splitPath(String value, String delimiter) sync* {
  var start = 0;
  var depth = 0;
  String? quote;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '[') depth++;
    if (char == ']') depth--;
    if (char != delimiter || depth != 0) continue;
    if (delimiter == '/' && (i == start || value.substring(start, i) == '/')) {
      continue;
    }
    yield value.substring(start, i).trim();
    start = delimiter == '/' ? i : i + 1;
  }
  if (quote != null || depth != 0) {
    throw FormatException('Invalid XPath: $value');
  }
  yield value.substring(start).trim();
}

Selector _parseSelector(String input) {
  late String source;
  late SelectorType selectorType;
  if (input.startsWith('//')) {
    // descendant
    selectorType = SelectorType.descendant;
    source = input.substring(2).trim();
  } else if (input.startsWith('/')) {
    // self
    selectorType = SelectorType.self;
    source = input.substring(1).trim();
  } else if (input == '.' || input == '..') {
    selectorType = SelectorType.self;
    source = input;
  } else {
    throw FormatException("'$input' is not a valid xpath query string");
  }

  final simpleSelector = _parseSimpleSelector(selectorType, source);
  if (simpleSelector != null) return simpleSelector;

  // Axis
  AxesAxis? axis;
  late String withoutAxis;
  if (source.contains('::')) {
    final pattern = source.split('::');
    if (pattern.length > 2) throw UnsupportedError('Not support multiple axis');
    axis = SelectorAxes.createAxis(pattern.first.trim());
    withoutAxis = pattern.last.trim();
  } else {
    withoutAxis = source;
  }

  var nodeTest = withoutAxis;
  final predicates = predicateReg.allMatches(withoutAxis);
  for (final predicate in predicates) {
    nodeTest = nodeTest.replaceAll(predicate.group(0) ?? '', '');
  }
  final predicateList = predicates
      .map((e) => e.namedGroup('predicate'))
      .whereType<String>()
      .toList();

  nodeTest = nodeTest.trim();
  if (nodeTest == 'text()') {
    return Selector(
      selectorType: selectorType,
      function: 'text()',
      axes: SelectorAxes(
        nodeTest: '#text',
        axis: AxesAxis.child,
        predicate: predicateList,
      ),
    );
  }
  if (nodeTest == '.') {
    axis = AxesAxis.self;
    nodeTest = '*';
  } else if (nodeTest == '..') {
    axis = AxesAxis.parent;
    nodeTest = '*';
  }

  return Selector(
    selectorType: selectorType,
    axes: SelectorAxes(
      nodeTest: nodeTest,
      axis: axis,
      predicate: predicateList,
    ),
  );
}

Selector? _parseSimpleSelector(SelectorType selectorType, String source) {
  if (source == 'text()') {
    return Selector(
      selectorType: selectorType,
      function: 'text()',
      axes: SelectorAxes(
        nodeTest: '#text',
        axis: AxesAxis.child,
        predicate: [],
      ),
    );
  }
  // attr
  if (source.startsWith('@')) {
    return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(axis: AxesAxis.self, nodeTest: '*', predicate: []),
      attr: source.substring(1),
    );
  }

  // parents
  if (source == '..') {
    return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(axis: AxesAxis.parent, nodeTest: '*', predicate: []),
    );
  }

  // self
  if (source == '.') {
    return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(axis: AxesAxis.self, nodeTest: '*', predicate: []),
    );
  }

  // node()
  if (source == 'node()') {
    return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(
        nodeTest: 'node()',
        axis: AxesAxis.child,
        predicate: [],
      ),
    );
  }

  // text() string() .. xxx()
  final function = RegExp(r'^\w*\(\s*\)$').firstMatch(source);
  if (function != null) {
    return Selector(
      selectorType: selectorType,
      function: function.group(0),
      axes: SelectorAxes(nodeTest: '*', axis: AxesAxis.self, predicate: []),
    );
  }
  return null;
}

/// if last selector is @attr or function, add to result
List<String?> parseAttr({
  required List<Selector> selectorList,
  required List<XPathNode> elements,
}) {
  final result = <String?>[];

  if (selectorList.isNotEmpty) {
    final lastSelector = selectorList.last;
    for (final element in elements) {
      if (lastSelector.attr != null) {
        // @attr
        if (lastSelector.attr == '*') {
          result.addAll(element.attributes.values);
        } else {
          result.add(element.attributes[lastSelector.attr]);
        }
      } else if (lastSelector.function != null) {
        // function
        result.add(
          elementFunction(node: element, function: lastSelector.function!),
        );
      } else if (lastSelector.axes.axis == AxesAxis.attribute) {
        // attr
        if (lastSelector.axes.nodeTest == '*') {
          result.addAll(element.attributes.values);
        } else {
          result.add(element.attributes[lastSelector.axes.nodeTest]);
        }
      }
    }
  }
  return result;
}

/// if node-test is text() or other functions
String? elementFunction({required XPathNode node, required String function}) {
  if (function.startsWith('@')) {
    return node.attributes[function.substring(1)];
  } else {
    switch (function) {
      case '.':
      case 'text()':
      case 'string()':
        return node.text ?? '';
      case 'name()':
      case 'qualified()':
        return node.name?.qualified;
      case 'local-name()':
        return node.name?.localName;
      case 'namespace()':
      case 'prefix()':
        return node.name?.namespace;
      default:
        throw UnsupportedError('Unsupported function: $function');
    }
  }
}
