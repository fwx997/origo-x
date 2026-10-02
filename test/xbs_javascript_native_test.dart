import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_download_cancellation.dart';
import 'package:xxread/book_sources/services/source_task_pool.dart';
import 'package:xxread/book_sources/xbs/xbs_javascript.dart';
import 'package:xxread/book_sources/xbs/xbs_runtime.dart';
import 'package:xxread/book_sources/xbs/xbs_rule_engine.dart';
import 'package:xxread/book_sources/xbs/xbs_source.dart';
import 'package:xxread/book_sources/xbs/xbs_discovery.dart';
import 'package:xxread/book_sources/legado/legado_request.dart';

/// Opt in with --dart-define=XBS_NATIVE_TEST=true and the FJS native library
/// built/available to the test process. No mock engine is used in this suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('native XBS JavaScript', () {
    test(
      'compound JSON chapter identifiers reach the next request unchanged',
      () async {
        final transport = _ScriptTransport();
        final runtime = XbsRuntime(transport: transport);
        addTearDown(runtime.close);
        final source = XbsSource('compound', {
          'sourceUrl': 'https://books.test/',
          'chapterList': {
            'JSParser':
                'function functionName(config,params,result){return {list:[{title:"Chapter",url:JSON.stringify({book:"42",chapter:"7"})}]};}',
          },
          'chapterContent': {
            'requestInfo':
                '@js:const id=JSON.parse(result);return {url:config.host+"read/"+id.book+"/"+id.chapter};',
            'JSParser':
                'function functionName(config,params,result){return {content:"chapter text"};}',
          },
        }).toRegisteredSource();
        final chapters = await runtime.getChapters(source, '42');
        expect(jsonDecode(chapters.single.id), {'book': '42', 'chapter': '7'});
        await runtime.getChapterContent(
          source,
          bookId: '42',
          chapterId: chapters.single.id,
        );
        expect(
          transport.request.url.toString(),
          'https://books.test/read/42/7',
        );
      },
    );
    test(
      'request overrides pass decoded JSON and retain source-scoped cache',
      () async {
        final transport = _ScriptTransport();
        final runtime = XbsRuntime(transport: transport);
        addTearDown(runtime.close);
        final config = <String, dynamic>{
          'sourceUrl': 'https://books.test/',
          'searchBook': {
            'requestInfo':
                '@js:if(params.pageIndex===1)params.nativeTool.setCache("page",7);'
                'return {url:config.host+"search",responseFormatType:"json",'
                'requestParamsEncode:"2147485232",responseEncode:"2147485232",'
                'httpParams:{page:params.nativeTool.getCache("page") || 0}};',
            'JSParser':
                'function functionName(config,params,result) {'
                'return result.items.map(b=>({bookName:b.name,detailUrl:b.id}));}',
          },
        };
        final first = XbsSource('first', config).toRegisteredSource();
        final other = XbsSource('other', {
          ...config,
          'sourceUrl': 'https://other.test/',
        }).toRegisteredSource();
        expect((await runtime.search(first, '书')).items.single.title, 'Book');
        expect(transport.request.responseCharset, 'gbk');
        expect(transport.request.charset, 'gbk');
        await runtime.search(first, '书', page: 2);
        expect(transport.request.url.queryParameters['page'], '7');
        await runtime.search(other, '书', page: 2);
        expect(transport.request.url.queryParameters['page'], '0');
      },
    );
    test(
      'native helpers parse malformed HTML, hash and decode Unicode',
      () async {
        final js = XbsQuickJs();
        addTearDown(js.close);
        final value =
            await js.evaluate(
                  '''
        console.log('ignored');
        const tool = params.nativeTool;
        tool.logWithKey('ignored', 'key');
        const doc = tool.XPathParserWithSource('<ul><li><a href="/1">一</a><li><a href="/2">二</a></ul>');
        const rows = doc.queryWithXPath('//li');
        return {
          links: rows.map(row => row.queryWithXPath('//a/@href')[0].content()),
          root: rows[0].queryWithXPath('//li')[0].content(),
          hash: tool.md5Encode('abc'),
          text: tool.base64Decode(tool.base64Encode('中文😀')),
          html: rows[0].raw(),
          noIo: typeof tool.readTxtFile
        };
      ''',
                  {},
                  {},
                  null,
                )
                as Map;
        expect(value['links'], ['/1', '/2']);
        expect(value['root'], '一');
        expect(value['hash'], '900150983cd24fb0d6963f7d28e17f72');
        expect(value['text'], '中文😀');
        expect(value['html'], contains('<a href="/1">一</a>'));
        expect(value['noIo'], 'undefined');
      },
    );

    test(
      'script cache survives actions and isolates source instances',
      () async {
        final cache = <String, Object?>{};
        final first = XbsQuickJs(cache: cache);
        await first.evaluate(
          'params.nativeTool.setCache("tag", {page:2}); return null;',
          {},
          {},
          null,
        );
        await first.close();
        final next = XbsQuickJs(cache: cache);
        final other = XbsQuickJs();
        addTearDown(next.close);
        addTearDown(other.close);
        expect(
          await next.evaluate(
            'return params.nativeTool.getCache("tag");',
            {},
            {},
            null,
          ),
          {'page': 2},
        );
        expect(
          await other.evaluate(
            'return params.nativeTool.getCache("tag");',
            {},
            {},
            null,
          ),
          isNull,
        );
        await next.evaluate(
          'for(let i=0;i<150;i++)params.nativeTool.setCache("k"+i,i);',
          {},
          {},
          null,
        );
        expect(cache.length, 128);
      },
    );

    test('cover postprocessing receives one image URL', () async {
      final js = XbsQuickJs();
      addTearDown(js.close);
      final engine = XbsRuleEngine(js, {}, {});
      final cover = await engine.text(
        '<img src="/cover.jpg"><img src="/avatar.png">',
        '//img/@src||@js:return "https://cdn.books.test" + result;',
        first: true,
      );
      expect(cover, 'https://cdn.books.test/cover.jpg');
      expect(
        await engine.text(
          {
            'covers': ['/cover.jpg', '/avatar.png'],
          },
          'covers||@js:return "https://cdn.books.test" + result;',
          first: true,
        ),
        'https://cdn.books.test/cover.jpg',
      );
    });
    test(
      'array filters preserve numeric values and the legacy filter alias',
      () async {
        final transport = _ScriptTransport();
        final runtime = XbsRuntime(transport: transport);
        addTearDown(runtime.close);
        final source = XbsSource('array', {
          'sourceName': 'Array filters',
          'sourceUrl': 'https://books.test/',
          'bookWorld': {
            '榜单': {
              'moreKeys': {
                'requestFilters': [
                  {
                    'key': 'filter',
                    'items': [
                      {'title': '全部', 'value': 0},
                      {'title': '玄幻', 'value': 3},
                    ],
                  },
                ],
              },
              'requestInfo':
                  '@js:return {url:config.host+"rank",httpParams:{'
                  'value:params.filter,nested:params.filters.filter,type:typeof params.filter}};',
              'JSParser':
                  'function functionName(config,params,result) {return [];}',
            },
          },
        }).toRegisteredSource();
        final category = (await runtime.getCategories(source)).single;
        await runtime.browse(
          source,
          category: XbsDiscovery.withFilters(category.id, {'filter': '3'}),
        );
        expect(transport.request.url.queryParameters, {
          'value': '3',
          'nested': '3',
          'type': 'number',
        });
      },
    );
    test(
      'discovery scripts receive original grouped filters and page index',
      () async {
        final transport = _ScriptTransport();
        final runtime = XbsRuntime(transport: transport);
        addTearDown(runtime.close);
        final source = XbsSource('grouped', {
          'sourceName': 'Grouped discovery',
          'sourceUrl': 'https://books.test/',
          'bookWorld': {
            '榜单': {
              'moreKeys': {
                'requestFilters':
                    'type\n完本榜::finish\n字数榜::word_number\nclass\n全部::0\n玄幻::3',
              },
              'requestInfo':
                  '@js:return {url:config.host+"rank",httpParams:{'
                  'type:params.filters.type,category:params.filters.class,page:params.pageIndex}};',
              'JSParser':
                  'function functionName(config,params,result) {'
                  'return JSON.parse(result).items.map(b => ({bookName:b.name,detailUrl:b.id}));}',
            },
          },
        }).toRegisteredSource();
        final categories = await runtime.getCategories(source);
        await runtime.browse(source);
        expect(transport.request.url.queryParameters, {
          'type': 'finish',
          'category': '0',
          'page': '1',
        });
        final result = await runtime.browse(
          source,
          page: 2,
          category: XbsDiscovery.withFilters(categories.single.id, {
            'type': 'word_number',
            'class': '3',
          }),
        );
        expect(transport.request.url.queryParameters, {
          'type': 'word_number',
          'category': '3',
          'page': '2',
        });
        expect(result.items.single.title, 'Book');
        expect(result.hasMore, isTrue);
      },
    );
    test('runs dynamic POST requests and a complete JSParser', () async {
      final transport = _ScriptTransport();
      final runtime = XbsRuntime(transport: transport);
      final source = XbsSource('native', {
        'sourceName': 'Native fixture',
        'sourceUrl': 'https://books.test/',
        'searchBook': {
          'requestInfo':
              '@js:return {url: config.host + "search", POST: true, '
              'httpParams: {q: params.keyWord, page: params.pageIndex}};',
          'JSParser':
              'function functionName(config,params,result) {'
              'return JSON.parse(result).items.map(b => ({bookName:b.name,detailUrl:b.id,cover:["/cover.jpg","/avatar.png"]}));}',
        },
      }).toRegisteredSource();
      final result = await runtime.search(source, '中 文');
      expect(result.items.single.id, '42');
      expect(result.items.single.title, 'Book');
      expect(
        result.items.single.coverUrl,
        Uri.parse('https://books.test/cover.jpg'),
      );
      expect(transport.request.method, LegadoRequestMethod.post);
      expect(Uri.splitQueryString(transport.request.body!), {
        'q': '中 文',
        'page': '1',
      });
    });
    test('preserves structured results and treats arguments as data', () async {
      final js = XbsQuickJs();
      addTearDown(js.close);
      final result = await js.evaluate(
        'return {url: config.host + params.keyWord, items: [result, 7]};',
        {'host': 'https://example.test/'},
        {'keyWord': '";throw 1;//'},
        'text',
      );
      expect(result, {
        'url': 'https://example.test/";throw 1;//',
        'items': ['text', 7],
      });
    });

    test(
      'terminates an infinite loop and can evaluate again',
      () async {
        final js = XbsQuickJs();
        addTearDown(js.close);
        final timer = Stopwatch()..start();
        await expectLater(
          js.evaluate('while(true){}', {}, {}, null),
          throwsA(isA<BookSourceProtocolException>()),
        );
        expect(timer.elapsed, lessThan(const Duration(seconds: 5)));
        expect(await js.evaluate('return 42;', {}, {}, null), 42);
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );

    test(
      'cancels an in-flight native loop',
      () async {
        final js = XbsQuickJs();
        addTearDown(js.close);
        await js.evaluate('return 1;', {}, {}, null);
        final token = BookDownloadCancellation();
        final execution = SourceTaskContext.run(
          token,
          () => js.evaluate('while(true){}', {}, {}, null),
        );
        final check = expectLater(
          execution,
          throwsA(isA<BookDownloadCancelledException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final timer = Stopwatch()..start();
        token.cancel();
        await check;
        expect(timer.elapsed, lessThan(const Duration(seconds: 1)));
      },
      timeout: const Timeout(Duration(seconds: 8)),
    );
  }, skip: !const bool.fromEnvironment('XBS_NATIVE_TEST'));
}

class _ScriptTransport implements LegadoTransport {
  late LegadoRequestTemplate request;
  @override
  Future<LegadoResponse> send(LegadoRequestTemplate value) async {
    request = value;
    return LegadoResponse(
      body: '{"items":[{"id":"42","name":"Book"}]}',
      finalUri: value.url,
    );
  }
}
