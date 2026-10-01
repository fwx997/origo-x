import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/registered_book_source.dart';

class XbsSource {
  const XbsSource(this.alias, this.config);

  final String alias;
  final Map<String, dynamic> config;
  String get name => config['sourceName'] as String? ?? alias;
  String get type => config['sourceType'] as String? ?? 'text';
  Uri get baseUri => Uri.parse(config['sourceUrl'] as String);
  String get id =>
      'xbs.${sha256.convert(utf8.encode('$alias\n${baseUri.origin}')).toString().substring(0, 24)}';

  Map<String, dynamic> action(String name) {
    final own = stringMap(config[name]);
    final inherited = stringMap(config[own['validConfig']]);
    return {...inherited, ...own};
  }

  Set<String> get capabilities => {
    if (action('searchBook')['requestInfo'] != null) 'search',
    'detail',
    'catalog',
    'content',
    if (stringMap(config['bookWorld']).isNotEmpty) ...{
      'discover',
      'categories',
      'browse',
    },
  };

  RegisteredBookSource toRegisteredSource() => RegisteredBookSource(
    id: id,
    name: name,
    description: '香色闺阁原始规则 · 未检测',
    manifestUrl: baseUri,
    apiBaseUrl: baseUri,
    websiteUrl: baseUri,
    protocolVersion: 'xbs-1',
    languages: const ['zh'],
    capabilities: capabilities,
    enabled: config['enable'] != false && config['enable'] != 0,
    addedAt: DateTime.now(),
    sourceProtocol: BookSourceProtocolKind.xbs,
    sourceConfig: {'alias': alias, 'config': config},
  );

  static XbsSource fromRegistered(RegisteredBookSource source) {
    final raw = source.sourceConfig!;
    return XbsSource(raw['alias'] as String, stringMap(raw['config']));
  }
}

Map<String, dynamic> stringMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : <String, dynamic>{};

class XbsImportResult {
  const XbsImportResult(this.sources, this.errors);
  final List<XbsSource> sources;
  final List<String> errors;
}

class XbsSourceFile {
  static const maxBytes = 64 * 1024 * 1024;
  static const maxSources = 10000;

  static XbsImportResult parse(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const FormatException('书源文件超过 64 MiB');
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes).replaceFirst('\ufeff', ''));
    } on FormatException {
      decoded = jsonDecode(utf8.decode(decode(bytes)));
    }
    return fromJson(decoded);
  }

  static bool recognizes(Object? value) {
    if (value is Map && value.containsKey('sourceName')) return true;
    final values = value is Map
        ? value.values
        : value is List
        ? value
        : const [];
    return values.any((item) => item is Map && item.containsKey('sourceName'));
  }

  static XbsImportResult fromJson(Object? value) {
    final Map<String, dynamic> entries;
    if (value is Map && value.containsKey('sourceName')) {
      entries = {'${value['sourceName']}': value};
    } else if (value is Map) {
      entries = stringMap(value);
    } else if (value is List) {
      entries = {for (var i = 0; i < value.length; i++) '$i': value[i]};
    } else {
      throw const FormatException('不是香色书源集合');
    }
    if (entries.length > maxSources) {
      throw const FormatException('书源数量超过 10000');
    }
    final sources = <XbsSource>[];
    final errors = <String>[];
    for (final entry in entries.entries) {
      final config = stringMap(entry.value);
      final uri = Uri.tryParse(config['sourceUrl']?.toString() ?? '');
      if (config['sourceName'] is! String ||
          uri == null ||
          !uri.hasAuthority ||
          !['http', 'https'].contains(uri.scheme)) {
        errors.add('${entry.key}：名称或站点地址无效');
        continue;
      }
      final alias = value is List ? config['sourceName'] as String : entry.key;
      sources.add(XbsSource(alias, config));
    }
    if (sources.isEmpty) throw const FormatException('文件中没有有效香色书源');
    return XbsImportResult(sources, errors);
  }

  // XBS uses XXTEA with a little-endian length word. This is a file-format
  // constant, not an account password or encryption credential.
  static Uint8List decode(Uint8List input) {
    if (input.length < 8 || input.length % 4 != 0 || input.length > maxBytes) {
      throw const FormatException('无效的 XBS 文件长度');
    }
    final data = ByteData.sublistView(input);
    final words = List<int>.generate(
      input.length ~/ 4,
      (i) => data.getUint32(i * 4, Endian.little),
    );
    final keyBytes = Uint8List.fromList([
      0xe5,
      0x87,
      0xbc,
      0xe8,
      0xa4,
      0x86,
      0xe6,
      0xbb,
      0xbf,
      0xe9,
      0x87,
      0x91,
      0xe6,
      0xba,
      0xa1,
      0xe5,
    ]);
    final keyData = ByteData.sublistView(keyBytes);
    final key = List<int>.generate(
      4,
      (i) => keyData.getUint32(i * 4, Endian.little),
    );
    const mask = 0xffffffff, delta = 0x9e3779b9;
    var sum = ((6 + 52 ~/ words.length) * delta) & mask;
    var y = words[0];
    while (sum != 0) {
      final e = (sum >> 2) & 3;
      for (var p = words.length - 1; p >= 0; p--) {
        final z = words[p == 0 ? words.length - 1 : p - 1];
        final mx =
            ((((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^
                ((sum ^ y) + (key[(p & 3) ^ e] ^ z))) &
            mask;
        y = words[p] = (words[p] - mx) & mask;
      }
      sum = (sum - delta) & mask;
    }
    final length = words.last;
    final capacity = input.length - 4;
    if (length > capacity || capacity - length > 3) {
      throw const FormatException('XBS 解码失败');
    }
    final output = ByteData(capacity);
    for (var i = 0; i < words.length - 1; i++) {
      output.setUint32(i * 4, words[i], Endian.little);
    }
    return output.buffer.asUint8List(0, length);
  }
}
