import 'dart:convert';
import 'dart:typed_data';
import 'package:html/parser.dart' as html;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/book_sources/legado/legado_request.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/services/book_source_import_analyzer.dart';
import 'package:xxread/book_sources/services/book_source_registry.dart';
import 'package:xxread/book_sources/xbs/xbs_javascript.dart';
import 'package:xxread/book_sources/xbs/xbs_rule_engine.dart';
import 'package:xxread/book_sources/xbs/xbs_runtime.dart';
import 'package:xxread/book_sources/xbs/xbs_source.dart';

Map<String, dynamic> fixture() => {
  'sourceName': 'Fixture',
  'sourceUrl': 'https://books.test/',
  'enable': 1,
  'unknownField': {'retained': true},
  'searchBook': {
    'requestInfo': '/search?q=%@keyWord&page=%@pageIndex',
    'list': '//li',
    'bookName': '//a',
    'detailUrl': '//a/@href',
    'author': '//span',
    'cover': '//img/@src',
  },
  'bookDetail': {
    'bookName': '//h1',
    'desc': '//p',
    'chapterListUrl': '//a/@href',
  },
  'chapterList': {
    'list': '//li',
    'title': '//a',
    'url': '//a/@href',
    'nextPageUrl': '//a[@rel="next"]/@href',
  },
  'chapterContent': {'content': '//article/p'},
  'bookWorld': {
    '榜单': {
      'requestInfo': '/rank?kind=%@filter',
      'list': '//li',
      'bookName': '//a',
      'detailUrl': '//a/@href',
      'moreKeys': {
        'requestFilters': {'最新': 'new', '热门': 'hot'},
      },
    },
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'source skipCount and maxPage bound catalogs and content pages',
    () async {
      final config = fixture();
      config['chapterList'] = Map<String, dynamic>.from(
        config['chapterList'] as Map,
      );
      config['chapterContent'] = Map<String, dynamic>.from(
        config['chapterContent'] as Map,
      );
      (config['chapterList'] as Map)['moreKeys'] = {'skipCount': 1};
      final transport = _FixtureTransport();
      final runtime = XbsRuntime(
        transport: transport,
        javascript: _NoJavascript.new,
      );
      var source = XbsSource('limits', config).toRegisteredSource();
      final chapters = await runtime.getChapters(
        source,
        'https://books.test/catalog/2',
      );
      expect(chapters.single.title, 'Chapter Two');
      (config['chapterList'] as Map)['moreKeys'] = {'maxPage': 1};
      (config['chapterContent'] as Map)['moreKeys'] = {'maxPage': 1};
      (config['chapterContent'] as Map)['nextPageUrl'] =
          '"https://books.test/chapter/2"';
      source = XbsSource('limits', config).toRegisteredSource();
      final limited = await runtime.getChapters(
        source,
        'https://books.test/catalog/1',
      );
      expect(limited.length, 1);
      final content = await runtime.getChapterContent(
        source,
        bookId: '1',
        chapterId: limited.single.id,
      );
      expect(content.content, contains('First paragraph'));
      expect(
        transport.requests.where((r) => r.url.path == '/chapter/2'),
        isEmpty,
      );
      expect(
        transport.requests.where((r) => r.url.path == '/catalog/2').length,
        1,
      );
    },
  );

  test(
    'legacy replacement chains remove labels without breaking XPath unions',
    () async {
      final engine = XbsRuleEngine(_NoJavascript(), {}, {});
      expect(
        await engine.text('<p>《书名》</p>', '//p||@replace:《||@replace:》'),
        '书名',
      );
      expect(
        await engine.text('<p>[分类]</p>', '//p|@replace:[|@replace:]'),
        '分类',
      );
      expect(
        await engine.text('<p>首<b>嵌套</b>尾</p>', '//p/text()[2]', content: true),
        '尾',
      );
    },
  );

  test(
    'XPath item fields include the detached item root and legacy attributes',
    () async {
      final engine = XbsRuleEngine(_NoJavascript(), {}, {});
      final item = html
          .parseFragment('<a href="/chapter/1"><dd>Chapter one</dd></a>')
          .children
          .single;
      expect(await engine.text(item, '//a/@href'), '/chapter/1');
      expect(await engine.text(item, '/@href'), '/chapter/1');
      expect(await engine.text(item, '//dd/text()'), 'Chapter one');
      expect(
        await engine.text(
          '<div class="image"><img src="/cover.jpg"></div>',
          '//div[@*=image]/img/@src',
        ),
        '/cover.jpg',
      );
    },
  );

  test(
    'all 185 original rules survive import, reload, and repeat import',
    () async {
      final raw = {for (var i = 0; i < 185; i++) 'alias$i': fixture()};
      raw['media'] = {...fixture(), 'sourceType': 'comic'};
      final analysis = BookSourceImportAnalyzer().analyzeBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(raw))),
      );
      expect(analysis.kind, BookSourceImportKind.xbs);
      expect(analysis.sources, hasLength(185));
      expect(analysis.excludedMedia, 1);
      final registry = BookSourceRegistry();
      await registry.upsertAll(analysis.sources);
      final source = analysis.sources.first;
      await registry.setEnabled(source.id, false);
      await registry.upsertAll(analysis.sources);
      final saved = await registry.load();
      expect(saved, hasLength(185));
      expect(saved.firstWhere((s) => s.id == source.id).enabled, isFalse);
      expect(await registry.loadRunnable(), hasLength(185));
      final restored = RegisteredBookSource.fromJson(source.toJson());
      expect(XbsSource.fromRegistered(restored).config, fixture());
    },
  );

  test(
    'HTML source connects search, detail, paged catalog, content and discovery',
    () async {
      final transport = _FixtureTransport();
      final runtime = XbsRuntime(
        transport: transport,
        javascript: _NoJavascript.new,
      );
      final source = XbsSource('fixture', fixture()).toRegisteredSource();
      final search = await runtime.search(source, '剑 来');
      expect(transport.requests.first.url.queryParameters['q'], '剑 来');
      expect(search.items.single.title, 'Example Book');
      expect(search.items.single.author, 'Author');
      expect(
        search.items.single.coverUrl,
        Uri.parse('https://books.test/covers/1.jpg'),
      );
      expect(search.hasMore, isTrue);
      final book = await runtime.getBook(source, search.items.single.id);
      expect(book.id, 'https://books.test/book/1');
      expect(book.author, 'Author');
      expect(book.coverUrl, search.items.single.coverUrl);
      final chapters = await runtime.getChapters(source, book.id);
      expect(chapters.map((c) => c.title), ['Chapter One', 'Chapter Two']);
      final content = await runtime.getChapterContent(
        source,
        bookId: book.id,
        chapterId: chapters.first.id,
      );
      expect(content.content, contains('<p>First paragraph</p>'));
      expect(content.content, contains('<p>Second paragraph</p>'));
      final categories = await runtime.getCategories(source);
      expect(categories.map((c) => c.name), ['榜单 · 最新', '榜单 · 热门']);
      final browse = await runtime.browse(source, category: categories.last.id);
      expect(transport.requests.last.url.queryParameters['kind'], 'hot');
      expect(browse.items.single.title, 'Example Book');
    },
  );

  test('optional covers ignore invalid schemes and malformed URLs', () async {
    for (final cover in [
      'data:image/png;base64,AAAA',
      'https://[broken',
      '   ',
    ]) {
      final config = fixture();
      (config['searchBook'] as Map)['cover'] = "'$cover'";
      final runtime = XbsRuntime(
        transport: _FixtureTransport(),
        javascript: _NoJavascript.new,
      );
      addTearDown(runtime.close);
      final page = await runtime.search(
        XbsSource('invalid-cover', config).toRegisteredSource(),
        'Book',
      );
      expect(page.items.single.title, 'Example Book');
      expect(page.items.single.coverUrl, isNull);
    }
  });

  test(
    'cover selection takes the first value while text fields keep all matches',
    () async {
      final engine = XbsRuleEngine(_NoJavascript(), {}, {});
      const html = '<img src=" "><img src="/cover.jpg"><img src="/avatar.png">';
      expect(await engine.text(html, '//img/@src', first: true), '/cover.jpg');
      expect(await engine.text(html, '//img/@src'), ' /cover.jpg/avatar.png');
      expect(
        await engine.text(
          {
            'covers': ['', '/cover.jpg', '/avatar.png'],
          },
          'covers',
          first: true,
        ),
        '/cover.jpg',
      );
    },
  );

  test('JSON paths retain arrays, numbers, and indexed values', () async {
    final engine = XbsRuleEngine(_NoJavascript(), {}, {});
    final data = {
      'data': {
        'items': [
          {'id': 17},
          {'id': 19},
        ],
      },
    };
    expect(
      await engine.evaluate(data, 'data/items', nodes: true),
      hasLength(2),
    );
    expect(await engine.text(data, 'data/items[1]/id'), '19');
    expect(await engine.evaluate(data, 'data/items/*/id'), [17, 19]);
  });

  test(
    'POST bodies honor JSON media types and preserve raw and form data',
    () async {
      final cases = [
        (
          'Application/JSON; charset=utf-8',
          <String, Object?>{
            'items': [
              1,
              {'name': '中文'},
            ],
            'enabled': true,
          },
        ),
        (
          'application/vendor+json',
          <Object?>[
            1,
            {'name': '中文'},
          ],
        ),
        ('application/json', '{"literal":"%@keyWord"}'),
        (
          'application/x-www-form-urlencoded',
          <String, Object?>{'q': '中 文', 'page': 2},
        ),
      ];
      for (final (contentType, parameters) in cases) {
        final config = fixture();
        config['searchBook'] = <String, dynamic>{
          ...config['searchBook'] as Map,
          'requestInfo': {
            'url': '/search',
            'POST': true,
            'httpParams': parameters,
            'httpHeaders': {'content-type': contentType},
          },
        };
        final transport = _FixtureTransport();
        final runtime = XbsRuntime(
          transport: transport,
          javascript: _NoJavascript.new,
        );
        await runtime.search(
          XbsSource('post', config).toRegisteredSource(),
          'query',
        );
        final body = transport.requests.single.body!;
        if (parameters is String) {
          expect(body, parameters);
        } else if (contentType == 'application/x-www-form-urlencoded') {
          expect(Uri.splitQueryString(body), {'q': '中 文', 'page': '2'});
        } else {
          expect(jsonDecode(body), parameters);
        }
      }
    },
  );

  test(
    'uses the original Apple charset identifiers without double encoding',
    () async {
      final config = fixture();
      final rules = Map<String, dynamic>.from(config['searchBook'] as Map);
      config['searchBook'] = rules;
      rules['requestParamsEncode'] = 2147485234;
      rules['responseEncode'] = 2147485232;
      final transport = _FixtureTransport();
      final runtime = XbsRuntime(
        transport: transport,
        javascript: _NoJavascript.new,
      );
      await runtime.search(
        XbsSource('encoded', config).toRegisteredSource(),
        '中文',
      );
      expect(transport.requests.single.url.query, contains('q=%D6%D0%CE%C4'));
      expect(transport.requests.single.charset, 'gb18030');
      expect(transport.requests.single.responseCharset, 'gbk');
    },
  );
}

class _NoJavascript implements XbsJavascript {
  @override
  Future<Object?> evaluate(
    String code,
    Map<String, dynamic> config,
    Map<String, dynamic> params,
    Object? result,
  ) async => throw StateError('This fixture must run without JavaScript');
  @override
  Future<void> close() async {}
}

class _FixtureTransport implements LegadoTransport {
  final requests = <LegadoRequestTemplate>[];
  @override
  Future<LegadoResponse> send(LegadoRequestTemplate request) async {
    requests.add(request);
    final body = switch (request.url.path) {
      '/search' || '/rank' =>
        '<ul><li><a href="/book/1">Example Book</a><span>Author</span>'
            '<img src=" /covers/1.jpg "><img src="//cdn.books.test/avatar.png"></li></ul>',
      '/book/1' =>
        '<h1>Example Book</h1><p>Description</p><a href="/catalog/1">Catalog</a>',
      '/catalog/1' =>
        '<a rel="next" href="/catalog/2">Next</a><ul><li><a href="/chapter/1">Chapter One</a></li></ul><a rel="next" href="/catalog/2">Next</a>',
      '/catalog/2' =>
        '<ul><li><a href="/chapter/1">Chapter One</a></li><li><a href="/chapter/2">Chapter Two</a></li></ul>',
      '/chapter/1' =>
        '<article><p>First paragraph</p><p>Second paragraph</p></article>',
      _ => throw StateError('Unexpected request: ${request.url.path}'),
    };
    return LegadoResponse(body: body, finalUri: request.url);
  }
}
