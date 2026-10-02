import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../../utils/fast_gbk_decoder.dart';

import '../legado/legado_request.dart';
import '../models/registered_book_source.dart';
import '../protocol/book_source_protocol.dart';
import '../services/source_task_pool.dart';
import 'xbs_javascript.dart';
import 'xbs_rule_engine.dart';
import 'xbs_source.dart';
import 'xbs_discovery.dart';

/// Executes original XBS actions. No conversion to Legado is involved.
class XbsRuntime {
  XbsRuntime({LegadoTransport? transport, XbsJavascript Function()? javascript})
    : _transport = transport ?? LegadoHttpTransport(),
      _javascript = javascript ?? XbsQuickJs.new;

  final LegadoTransport _transport;
  final XbsJavascript Function() _javascript;
  final Map<String, BookSourceBook> _books = {};
  final Map<String, String> _catalogs = {};

  void close({bool force = true}) {
    if (_transport case final LegadoHttpTransport transport) {
      transport.close(force: force);
    }
  }

  Future<T> _action<T>(
    RegisteredBookSource registered,
    String name,
    Object? input,
    Map<String, dynamic> params,
    Future<T> Function(_XbsPage) parse, {
    Map<String, dynamic>? override,
  }) async {
    SourceTaskContext.cancellation?.throwIfCancelled();
    final source = XbsSource.fromRegistered(registered);
    final rules = override ?? source.action(name);
    final config = <String, dynamic>{
      ...rules,
      'host': rules['host'] ?? source.baseUri.toString(),
      'httpHeaders': {
        ...stringMap(source.config['httpHeaders']),
        ...stringMap(rules['httpHeaders']),
      },
    };
    final js = _javascript();
    try {
      final engine = XbsRuleEngine(js, config, params);
      final request = await _request(engine, input);
      final response = await _transport.send(request);
      params['responseUrl'] = response.finalUri.toString();
      SourceTaskContext.cancellation?.throwIfCancelled();
      Object? document = XbsRuleEngine.document(response.body, config);
      final parser = config['JSParser'];
      if (parser is String && parser.trim().isNotEmpty) {
        document = await js.evaluate(
          '$parser\n'
          'if(typeof functionName === "function") '
          'return functionName(config,params,result);',
          config,
          params,
          response.body,
        );
      }
      return await parse(
        _XbsPage(
          engine,
          document,
          response.finalUri,
          scripted: parser is String && parser.trim().isNotEmpty,
        ),
      );
    } finally {
      await js.close();
    }
  }

  Future<LegadoRequestTemplate> _request(
    XbsRuleEngine engine,
    Object? input,
  ) async {
    final config = engine.config;
    Object? value = config['requestInfo'];
    if (value == null || value == '') value = input;
    if (value is String && value.trimLeft().startsWith('@js:')) {
      value = await engine.javascript.evaluate(
        value.trimLeft().substring(4),
        config,
        engine.params,
        input,
      );
    }
    final request = value is Map ? stringMap(value) : {'url': '$value'};
    if (request.entries.any(
      (e) =>
          e.key.toLowerCase().startsWith('webview') &&
          e.value != null &&
          e.value != false &&
          e.value != '',
    )) {
      throw const BookSourceProtocolException(
        'XBS：此请求需要浏览器执行',
        code: 'xbs_browser_required',
      );
    }
    final requestCharset = _charset(config['requestParamsEncode']);
    final base = Uri.parse('${config['host']}');
    var uri = base.resolve(
      _template(
        '${request['url'] ?? input ?? ''}',
        engine.params,
        input,
        charset: requestCharset,
      ),
    );
    final parameters = stringMap(request['httpParams']);
    final form = parameters.entries
        .map(
          (e) =>
              '${_encodeParameter(e.key, requestCharset)}='
              '${_encodeParameter(_template('${e.value}', engine.params, input, encodeKeyword: false), requestCharset)}',
        )
        .join('&');
    final post = request['POST'] == true || request['POST'] == 1;
    if (!post && form.isNotEmpty) {
      uri = uri.replace(query: [if (uri.hasQuery) uri.query, form].join('&'));
    }
    if (!uri.hasAuthority || !['http', 'https'].contains(uri.scheme)) {
      throw const BookSourceProtocolException('XBS：请求地址无效');
    }
    final headers = {
      ...stringMap(config['httpHeaders']),
      ...stringMap(request['httpHeaders']),
    };
    return LegadoRequestTemplate(
      url: uri,
      method: post ? LegadoRequestMethod.post : LegadoRequestMethod.get,
      headers: {
        for (final e in headers.entries) e.key: '${e.value}',
        if (post && !headers.keys.any((k) => k.toLowerCase() == 'content-type'))
          'Content-Type': 'application/x-www-form-urlencoded',
      },
      charset: requestCharset,
      responseCharset: _charset(config['responseEncode']),
      body: post
          ? (request['httpParams'] is String
                ? '${request['httpParams']}'
                : form)
          : null,
    );
  }

  String _charset(Object? value) => switch ('$value'.toLowerCase()) {
    'gbk' || 'gb2312' || '2147485232' || '2147485233' => 'gbk',
    'gb18030' || '2147485234' => 'gb18030',
    _ => 'utf-8',
  };

  String _encodeParameter(String value, String charset) {
    final bytes = charset == 'utf-8'
        ? utf8.encode(value)
        : encodeGbkFast(value);
    return bytes.map((b) {
      if (b == 32) return '+';
      if (b >= 65 && b <= 90 ||
          b >= 97 && b <= 122 ||
          b >= 48 && b <= 57 ||
          [45, 46, 95, 126].contains(b)) {
        return String.fromCharCode(b);
      }
      return '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }).join();
  }

  String _template(
    String text,
    Map<String, dynamic> params,
    Object? input, {
    String charset = 'utf-8',
    bool encodeKeyword = true,
  }) => text.replaceAllMapped(RegExp(r'%@(\w+)'), (m) {
    final key = m[1]!;
    final value = key == 'result' ? input : params[key];
    if (value == null) throw BookSourceProtocolException('XBS：缺少请求参数 $key');
    return key == 'keyWord' && encodeKeyword
        ? _encodeParameter('$value', charset)
        : '$value';
  });

  Map<String, dynamic> _params({
    String query = '',
    int page = 1,
    int size = 20,
  }) => {
    'keyWord': query,
    'pageIndex': page,
    'pageSize': size,
    'offset': (page - 1) * size,
    'filter': '',
    'filters': <String, dynamic>{},
  };

  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) => _action(
    source,
    'searchBook',
    '',
    _params(query: query, page: page, size: pageSize),
    (result) => _bookPage(source, result, page, pageSize),
  );

  Future<BookSourceSearchPage> _bookPage(
    RegisteredBookSource source,
    _XbsPage result,
    int page,
    int size,
  ) async {
    final books = <BookSourceBook>[];
    final seen = <String>{};
    for (final item in await result.items()) {
      SourceTaskContext.cancellation?.throwIfCancelled();
      final title = await result.field(item, 'bookName');
      final rawId = await result.field(item, 'detailUrl');
      if (title.isEmpty || rawId.isEmpty) continue;
      final id = _identity(rawId, result.uri);
      if (!seen.add(id)) continue;
      final book = await _book(result, item, id, title);
      books.add(book);
      _books['${source.id}\n$id'] = book;
      if (books.length >= 500) break;
    }
    if (_books.length > 3000) _books.remove(_books.keys.first);
    final request = '${result.engine.config['requestInfo']}';
    final pagination =
        request.contains('pageIndex') || request.contains('offset');
    return BookSourceSearchPage(
      items: books,
      page: page,
      pageSize: size,
      hasMore: pagination && books.isNotEmpty,
    );
  }

  Future<BookSourceBook> _book(
    _XbsPage page,
    Object? item,
    String id,
    String title, {
    BookSourceBook? fallback,
  }) async {
    final cover = await page.field(item, 'cover', first: true);
    final author = await page.field(item, 'author');
    final description = await page.field(item, 'desc');
    final latest = await page.field(item, 'lastChapterTitle');
    return BookSourceBook(
      id: id,
      title: title,
      author: author.isEmpty ? fallback?.author ?? '' : author,
      description: description.isEmpty
          ? fallback?.description ?? ''
          : description,
      coverUrl: _coverUri(cover, page.uri) ?? fallback?.coverUrl,
      latestChapter: latest.isEmpty ? fallback?.latestChapter : latest,
      categories: [
        await page.field(item, 'cat'),
      ].where((s) => s.isNotEmpty).toList(),
    );
  }

  Uri? _coverUri(String value, Uri base) {
    if (value.trim().isEmpty) return null;
    try {
      final uri = base.resolve(value.trim());
      return uri.host.isNotEmpty && ['http', 'https'].contains(uri.scheme)
          ? uri
          : null;
    } on FormatException {
      return null;
    }
  }

  String _identity(String value, Uri base) =>
      RegExp(r'^\d+$').hasMatch(value) ? value : base.resolve(value).toString();

  Future<BookSourceBook> getBook(RegisteredBookSource source, String bookId) =>
      _action(source, 'bookDetail', bookId, _params(), (page) async {
        final previous = _books['${source.id}\n$bookId'];
        var title = await page.field(page.document, 'bookName');
        if (title.isEmpty) title = previous?.title ?? '';
        if (title.isEmpty && page.document is String) {
          title =
              html
                  .parse(page.document as String)
                  .querySelector('h1')
                  ?.text
                  .trim() ??
              '';
        }
        if (title.isEmpty) {
          throw const BookSourceProtocolException('XBS：详情未返回书名');
        }
        final catalog = await page.field(page.document, 'chapterListUrl');
        if (catalog.isNotEmpty) {
          _catalogs['${source.id}\n$bookId'] = _identity(catalog, page.uri);
        }
        return _book(page, page.document, bookId, title, fallback: previous);
      });

  Future<List<BookSourceChapter>> getChapters(
    RegisteredBookSource source,
    String bookId,
  ) async {
    var url = _catalogs['${source.id}\n$bookId'] ?? bookId;
    final chapters = <BookSourceChapter>[];
    final seenPages = <String>{};
    final seen = <String>{};
    for (var hop = 1; hop <= 100 && seenPages.add(url); hop++) {
      final next = await _action(
        source,
        'chapterList',
        url,
        _params(page: hop),
        (page) async {
          for (final item in await page.items()) {
            final title = await page.field(item, 'title');
            final raw = await page.field(item, 'url');
            if (title.isEmpty || raw.isEmpty) continue;
            final id = _identity(raw, page.uri);
            if (seen.add(id)) {
              chapters.add(
                BookSourceChapter(id: id, title: title, order: chapters.length),
              );
            }
            if (chapters.length > 30000) {
              throw const BookSourceProtocolException('XBS：目录超过 30000 章');
            }
          }
          return page.nextUrl();
        },
      );
      if (next.isEmpty) break;
      url = next;
    }
    if (chapters.isEmpty) {
      throw const BookSourceProtocolException('XBS：没有解析到章节目录');
    }
    return chapters;
  }

  Future<BookSourceChapterContent> getChapterContent(
    RegisteredBookSource source, {
    required String bookId,
    required String chapterId,
  }) async {
    var url = chapterId;
    final seen = <String>{};
    final parts = <String>[];
    for (var hop = 1; hop <= 20 && seen.add(url); hop++) {
      final next = await _action(
        source,
        'chapterContent',
        url,
        _params(page: hop),
        (page) async {
          final content = await page.field(
            page.document,
            'content',
            content: true,
          );
          if (content.trim().isEmpty) {
            throw const BookSourceProtocolException('XBS：正文为空');
          }
          parts.add(content);
          return page.nextUrl();
        },
      );
      if (next.isEmpty) break;
      url = next;
    }
    return BookSourceChapterContent(
      bookId: bookId,
      chapterId: chapterId,
      title: '',
      content: parts.join('\n'),
      contentType: 'text/html',
    );
  }

  Future<List<BookSourceCategory>> getCategories(
    RegisteredBookSource source,
  ) async {
    final world = stringMap(
      XbsSource.fromRegistered(source).config['bookWorld'],
    );
    final categories = <BookSourceCategory>[];
    for (final entry in world.entries) {
      final rule = stringMap(entry.value);
      if (rule['requestInfo'] == null) continue;
      final rawFilters = stringMap(rule['moreKeys'])['requestFilters'];
      final filters = stringMap(rawFilters);
      if (filters.isEmpty) {
        categories.add(
          BookSourceCategory(
            id: jsonEncode([entry.key, '']),
            name: entry.key,
            filterGroups: XbsDiscovery.filterGroups(rawFilters),
          ),
        );
        continue;
      }
      for (final filter in filters.entries) {
        categories.add(
          BookSourceCategory(
            id: jsonEncode([entry.key, filter.value]),
            name: '${entry.key} · ${filter.key}',
          ),
        );
      }
    }
    return categories;
  }

  Future<BookSourceSearchPage> browse(
    RegisteredBookSource source, {
    String? category,
    int page = 1,
    int pageSize = 20,
  }) async {
    final categories = await getCategories(source);
    if (categories.isEmpty) {
      return BookSourceSearchPage(
        items: const [],
        page: page,
        pageSize: pageSize,
        hasMore: false,
      );
    }
    final selected = jsonDecode(category ?? categories.first.id) as List;
    final rule = stringMap(
      stringMap(
        XbsSource.fromRegistered(source).config['bookWorld'],
      )[selected.first],
    );
    final params = _params(page: page, size: pageSize)
      ..['filter'] = selected[1];
    final groups = XbsDiscovery.filterGroups(
      stringMap(rule['moreKeys'])['requestFilters'],
    );
    final choices = selected.length > 2
        ? stringMap(selected[2])
        : const <String, dynamic>{};
    params['filters'] = {
      for (final group in groups)
        group.id: group.options
            .firstWhere(
              (option) => option.value == '${choices[group.id]}',
              orElse: () => group.options.first,
            )
            .parameterValue,
    };
    if ((params['filters'] as Map).containsKey('filter')) {
      params['filter'] = params['filters']['filter'];
    }
    return _action(
      source,
      'bookWorld',
      '',
      params,
      (result) => _bookPage(source, result, page, pageSize),
      override: rule,
    );
  }

  Future<BookSourceDiscoveryPage> getDiscovery(
    RegisteredBookSource source,
  ) async {
    final categories = await getCategories(source);
    if (categories.isEmpty) return const BookSourceDiscoveryPage(sections: []);
    final category = categories.first;
    final books = await browse(source, category: category.id);
    return BookSourceDiscoveryPage(
      sections: [
        BookSourceDiscoverySection(
          id: category.id,
          title: category.name,
          items: books.items,
        ),
      ],
    );
  }
}

class _XbsPage {
  const _XbsPage(
    this.engine,
    this.document,
    this.uri, {
    required this.scripted,
  });
  final XbsRuleEngine engine;
  final Object? document;
  final Uri uri;
  final bool scripted;

  Future<List<Object?>> items() async {
    final result = scripted
        ? document
        : await engine.evaluate(document, engine.config['list'], nodes: true);
    if (result is List) return result;
    if (result is Map && result['list'] is List) {
      return List<Object?>.from(result['list']);
    }
    return result == null ? [] : [result];
  }

  Future<String> field(
    Object? item,
    String name, {
    bool content = false,
    bool first = false,
  }) async {
    if (scripted && item is Map) {
      final value = item[name];
      if (first && value is List) {
        return value
                .where((entry) => entry != null && '$entry'.trim().isNotEmpty)
                .firstOrNull
                ?.toString() ??
            '';
      }
      return '${value ?? ''}';
    }
    return engine.text(
      item,
      engine.config[name],
      content: content,
      first: first,
    );
  }

  Future<String> nextUrl() async {
    final next = await field(document, 'nextPageUrl');
    return next.isEmpty ? '' : uri.resolve(next).toString();
  }
}
