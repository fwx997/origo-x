import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_download_cancellation.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/book_sources/services/source_task_pool.dart';
import 'package:xxread/book_sources/xbs/xbs_runtime.dart';
import 'package:xxread/book_sources/xbs/xbs_source.dart';
import 'package:xxread/l10n/app_localizations.dart';
import 'package:xxread/pages/book_sources/book_sources_page.dart';
import 'package:xxread/pages/book_sources/source_search_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('bottom retry recovers first-page and later-page failures', (
    tester,
  ) async {
    final calls = <String, int>{};
    final client = _Client()
      ..searchResult = (source, query, page) async {
        final key = '${source.name}:$page';
        calls.update(key, (count) => count + 1, ifAbsent: () => 1);
        if (key == 'A:1') return _page([_book('a1', 'First page')], more: true);
        if (calls[key] == 1) throw StateError('Temporary failure');
        return _page([_book(key, '${source.name} recovered')]);
      };
    await _searchPage(tester, client, [_source('A'), _source('B')]);
    await _search(tester, 'book');
    if (!calls.containsKey('A:2')) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
    }
    expect(calls, {'A:1': 1, 'B:1': 1, 'A:2': 1});
    await tester.ensureVisible(
      find.byKey(const Key('bookSourceLoadMoreButton')),
    );
    await tester.tap(find.byKey(const Key('bookSourceLoadMoreButton')));
    await tester.pumpAndSettle();
    expect(calls, {'A:1': 1, 'B:1': 2, 'A:2': 2});
    expect(find.text('First page'), findsOneWidget);
    expect(find.text('A recovered'), findsOneWidget);
    expect(find.text('B recovered'), findsOneWidget);
    expect(find.byKey(const Key('bookSourceSearchFailures')), findsNothing);
  });

  testWidgets('all failures expose reasons and allow retrying one source', (
    tester,
  ) async {
    final calls = <String, int>{};
    final client = _Client()
      ..searchResult = (source, query, page) async {
        calls.update(source.name, (count) => count + 1, ifAbsent: () => 1);
        if (source.name == 'A' || calls[source.name] == 1) {
          throw StateError('Connection timed out');
        }
        return _page([_book('found', 'Recovered book')]);
      };
    await _searchPage(tester, client, [_source('A'), _source('B')]);
    await _search(tester, 'book');
    await tester.tap(find.byKey(const Key('bookSourceSearchFailures')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection timed out'), findsNWidgets(2));
    await tester.tap(find.byKey(Key('retrySearchSource-${_source('B').id}')));
    await tester.pumpAndSettle();
    expect(calls, {'A': 1, 'B': 2});
    expect(find.text('Recovered book'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bookSourceRetryFailed')));
    await tester.pumpAndSettle();
    expect(calls, {'A': 2, 'B': 2});
    expect(find.text('Recovered book'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bookSourceSearchFailures')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection timed out'), findsOneWidget);
  });

  testWidgets('a failed source does not block loading other sources pages', (
    tester,
  ) async {
    final pages = <int>[];
    var failures = 0;
    final client = _Client()
      ..searchResult = (source, query, page) async {
        if (source.name == 'B') {
          failures++;
          throw StateError('Unavailable');
        }
        pages.add(page);
        return _page([_book('$page', 'Page $page')], more: page < 3);
      };
    await _searchPage(tester, client, [_source('A'), _source('B')]);
    await _search(tester, 'book');
    expect(pages, [1, 2]);
    expect(failures, 1);
    await tester.ensureVisible(
      find.byKey(const Key('bookSourceLoadMoreButton')),
    );
    await tester.tap(find.byKey(const Key('bookSourceLoadMoreButton')));
    await tester.pumpAndSettle();
    expect(pages, [1, 2, 3]);
    expect(failures, 2);
    expect(find.text('Page 3'), findsOneWidget);
  });

  testWidgets('a new query cancels a retry and discards its late response', (
    tester,
  ) async {
    final retry = Completer<BookSourceSearchPage>();
    BookDownloadCancellation? retryToken;
    var calls = 0;
    final client = _Client()
      ..searchResult = (source, query, page) {
        if (query == 'new') {
          return Future.value(_page([_book('new', 'New book')]));
        }
        if (++calls == 1) return Future.error(StateError('Temporary failure'));
        retryToken = SourceTaskContext.cancellation;
        return retry.future;
      };
    await _searchPage(tester, client, [_source('A')]);
    await _search(tester, 'old');
    await tester.tap(find.byKey(const Key('bookSourceRetryFailed')));
    await tester.pump();
    await _search(tester, 'new');
    expect(retryToken?.isCancelled, isTrue);
    retry.complete(_page([_book('old', 'Stale book')]));
    await tester.pumpAndSettle();
    expect(find.text('New book'), findsOneWidget);
    expect(find.text('Stale book'), findsNothing);
    expect(find.byKey(const Key('bookSourceSearchFailures')), findsNothing);
  });

  testWidgets('filtered-out first page can still load a matching second page', (
    tester,
  ) async {
    final second = Completer<BookSourceSearchPage>();
    final pages = <int>[];
    final client = _Client()
      ..searchResult = (source, query, page) {
        pages.add(page);
        return page == 1
            ? Future.value(_page([_book('1', 'Unrelated')], more: true))
            : second.future;
      };
    await _searchPage(tester, client, [_source('A')]);
    await tester.tap(find.text('精确匹配').last);
    await tester.pumpAndSettle();
    await _search(tester, 'Wanted', settle: false);
    await tester.pump(const Duration(milliseconds: 50));
    if (pages.length == 1) {
      await tester.tap(find.byKey(const Key('bookSourceLoadMoreButton')));
      await tester.pump();
    }
    expect(pages, [1, 2]);
    second.complete(_page([_book('2', 'Wanted')]));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Wanted'),
      findsOneWidget,
    );
    expect(find.text('Unrelated'), findsNothing);
  });

  testWidgets('a site that repeats the same page stops automatic pagination', (
    tester,
  ) async {
    final pages = <int>[];
    final client = _Client()
      ..searchResult = (source, query, page) async {
        pages.add(page);
        return _page([_book('same', 'Same book')], more: true);
      };
    await _searchPage(tester, client, [_source('A')]);
    await _search(tester, 'Same');
    expect(pages, [1, 2]);
    expect(find.text('Same book'), findsOneWidget);
    expect(find.byKey(const Key('bookSourceLoadMoreButton')), findsNothing);
  });

  testWidgets('submitting an empty query cancels an active search', (
    tester,
  ) async {
    final response = Completer<BookSourceSearchPage>();
    final client = _Client()
      ..searchResult = (source, query, page) => response.future;
    await _searchPage(tester, client, [_source('A')]);
    await _search(tester, 'first', settle: false);
    await _search(tester, '');
    response.complete(_page([_book('late', 'Stale result')]));
    await tester.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    expect(find.byKey(const Key('bookSourceStopSearch')), findsNothing);
  });

  testWidgets('retrying failed discovery retains successful sources', (
    tester,
  ) async {
    final calls = <String, int>{};
    final client = _Client()
      ..discoverResult = (source) async {
        calls.update(source.name, (n) => n + 1, ifAbsent: () => 1);
        if (source.name == 'B' && calls['B'] == 1) {
          throw StateError('Temporary failure');
        }
        return _discovery('${source.name} ready');
      };
    await _discoverPage(tester, client, [_source('A'), _source('B')]);
    expect(find.text('A ready'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, {'A': 1, 'B': 2});
    expect(find.text('A ready'), findsOneWidget);
    expect(find.text('B ready'), findsOneWidget);
  });

  testWidgets(
    'category page failure retries the same page without losing earlier books',
    (tester) async {
      final pages = <int>[];
      final client = _Client()
        ..browseResult = (source, category, page) async {
          pages.add(page);
          if (pages.length == 2) throw StateError('Page timed out');
          return _page([
            _book('$page', 'Category page $page'),
          ], more: page == 1);
        };
      await _discoverPage(tester, client, [_source('A')]);
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('bookSourceCategoryLoadMore')),
      );
      await tester.tap(find.byKey(const Key('bookSourceCategoryLoadMore')));
      await tester.pumpAndSettle();
      expect(find.text('Category page 1'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(pages, [1, 2, 2]);
      expect(find.text('Category page 1'), findsOneWidget);
      expect(find.text('Category page 2'), findsOneWidget);
    },
  );

  testWidgets('author keyword is sent and only matching authors are shown', (
    tester,
  ) async {
    final client = _Client()
      ..searchResult = (source, query, page) async => _page([
        _book('a', '剑来', author: '烽火戏诸侯'),
        _book('b', '烽火戏诸侯', author: '其他作者'),
      ]);
    await _searchPage(tester, client, [_source('A')]);
    await tester.tap(find.text('作者').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('精确匹配').last);
    await tester.pumpAndSettle();
    await _search(tester, '烽火戏诸侯');
    expect(client.queries.single, '烽火戏诸侯');
    expect(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '剑来'),
      findsOneWidget,
    );
    expect(find.textContaining('其他作者'), findsNothing);
  });

  testWidgets('same work is grouped and every source remains selectable', (
    tester,
  ) async {
    final client = _Client()
      ..searchResult = (source, query, page) async => _page([
        _book(source.id, '剑来', author: source.name == 'C' ? '其他作者' : '烽火戏诸侯'),
      ]);
    await _searchPage(tester, client, [
      _source('A'),
      _source('B'),
      _source('C'),
    ]);
    await _search(tester, '剑来');
    expect(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '剑来'),
      findsNWidgets(2),
    );
    await tester.tap(find.text('2 个来源'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B'), findsWidgets);
    await tester.tap(find.widgetWithText(ListTile, 'B'));
    await tester.pumpAndSettle();
    expect(client.detailSources.last, _source('B').id);
  });

  testWidgets(
    'search runs at most twelve sources concurrently and publishes early results',
    (tester) async {
      final responses = List.generate(
        15,
        (_) => Completer<BookSourceSearchPage>(),
      );
      var active = 0;
      var peak = 0;
      final started = <int>[];
      final client = _Client()
        ..searchResult = (source, query, page) async {
          final index = int.parse(source.name);
          started.add(index);
          active++;
          if (active > peak) peak = active;
          final result = await responses[index].future;
          active--;
          return result;
        };
      await _searchPage(
        tester,
        client,
        List.generate(15, (i) => _source('$i')),
      );
      await _search(tester, '书', settle: false);
      expect(started, hasLength(12));
      responses.first.complete(_page([_book('fast', '已返回的书')]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('已返回的书'), findsOneWidget);
      expect(started, hasLength(13));
      expect(peak, 12);
      await tester.tap(find.byKey(const Key('bookSourceStopSearch')));
      for (var i = 1; i < responses.length; i++) {
        responses[i].complete(_page([_book('$i', '过期结果')]));
      }
      await tester.pumpAndSettle();
      expect(started, hasLength(13));
      expect(find.text('过期结果'), findsNothing);
    },
  );

  testWidgets(
    'discovered book opens cross-source lookup with title and author identity',
    (tester) async {
      final client = _Client()
        ..searchResult = (source, query, page) async => _page([
          _book('found', '剑来', author: source.name == 'C' ? '其他作者' : '烽火戏诸侯'),
        ]);
      await _discoverPage(tester, client, [
        _source('A'),
        _source('B'),
        _source('C'),
      ]);
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) => widget is Text && widget.data == '剑来',
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bookSourceFindOtherSources')));
      await tester.pumpAndSettle();
      expect(find.byType(SourceSearchPage), findsOneWidget);
      expect(client.queries, ['剑来', '剑来', '剑来']);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == '剑来',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('其他作者'), findsNothing);
      expect(find.text('2 个来源'), findsNothing);
    },
  );

  testWidgets(
    'fast discovery remains visible while another source is pending',
    (tester) async {
      final slow = Completer<BookSourceDiscoveryPage>();
      final client = _Client()
        ..discoverResult = (source) =>
            source.name == 'B' ? slow.future : Future.value(_discovery('快源书籍'));
      await _discoverPage(tester, client, [
        _source('A'),
        _source('B'),
      ], settle: false);
      expect(find.text('快源书籍'), findsOneWidget);
      await _pickSource(tester, 'bookSourceDiscoverSwitch', _source('B').id);
      await tester.pump();
      expect(find.text('快源书籍'), findsNothing);
      slow.complete(_discovery('慢源书籍'));
      await tester.pumpAndSettle();
      expect(find.text('慢源书籍'), findsOneWidget);
    },
  );

  testWidgets(
    'category filters reset paging, preserve all choices and discard old results',
    (tester) async {
      final old = Completer<BookSourceSearchPage>();
      BookDownloadCancellation? oldToken;
      final requests = <List<dynamic>>[];
      final client = _Client()
        ..browseResult = (source, category, page) {
          final token = jsonDecode(category!) as List;
          requests.add([...token, page]);
          if ((token[2] as Map)['class'] == '0') {
            oldToken = SourceTaskContext.cancellation;
            return old.future;
          }
          return Future.value(
            _page([_book('$page', '玄幻第$page页')], more: page == 1),
          );
        };
      await _discoverPage(tester, client, [_source('A')]);
      await tester.tap(find.text('Categories'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('玄幻').last);
      await tester.pumpAndSettle();
      expect(oldToken?.isCancelled, isTrue);
      expect(requests.last[2], {'type': 'finish', 'class': '3'});
      expect(requests.last.last, 1);
      expect(find.text('玄幻第1页'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('bookSourceCategoryLoadMore')),
      );
      await tester.tap(find.byKey(const Key('bookSourceCategoryLoadMore')));
      await tester.pumpAndSettle();
      expect(requests.last.last, 2);
      expect(find.text('玄幻第2页'), findsOneWidget);
      old.complete(_page([_book('old', '旧分类的书')]));
      await tester.pumpAndSettle();
      expect(find.text('旧分类的书'), findsNothing);
    },
  );

  testWidgets(
    'switching source cancels old category browse and retries failures',
    (tester) async {
      final old = Completer<BookSourceSearchPage>();
      BookDownloadCancellation? oldToken;
      var retries = 0;
      final client = _Client()
        ..browseResult = (source, category, page) async {
          if (source.name == 'A') {
            oldToken = SourceTaskContext.cancellation;
            return old.future;
          }
          if (retries++ == 0) throw StateError('temporarily unavailable');
          return _page([_book('b', 'B分类的书')]);
        };
      await _discoverPage(tester, client, [_source('A'), _source('B')]);
      await tester.tap(find.text('Categories'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _pickSource(tester, 'bookSourceDiscoverSwitch', _source('B').id);
      await tester.pumpAndSettle();
      expect(oldToken?.isCancelled, isTrue);
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('B分类的书'), findsOneWidget);
      old.complete(_page([_book('a', 'A过期的书')]));
      await tester.pumpAndSettle();
      expect(find.text('A过期的书'), findsNothing);
    },
  );
}

RegisteredBookSource _source(String name) => XbsSource(name, {
  'sourceName': name,
  'sourceUrl': 'https://s${Uri.encodeComponent(name)}.test/',
  'enable': 1,
  'searchBook': {'requestInfo': '/search?q=%@keyWord'},
  'bookWorld': {
    '榜单': {
      'requestInfo': '/rank?page=%@pageIndex',
      'moreKeys': {
        'requestFilters':
            'type\n完本榜::finish\n字数榜::word_number\nclass\n全部::0\n玄幻::3',
      },
    },
  },
}).toRegisteredSource();

BookSourceBook _book(String id, String title, {String author = '烽火戏诸侯'}) =>
    BookSourceBook(
      id: id,
      title: title,
      author: author,
      description: '',
      categories: const [],
    );

BookSourceSearchPage _page(List<BookSourceBook> books, {bool more = false}) =>
    BookSourceSearchPage(items: books, page: 1, pageSize: 20, hasMore: more);

BookSourceDiscoveryPage _discovery(String title) => BookSourceDiscoveryPage(
  sections: [
    BookSourceDiscoverySection(
      id: 'picks',
      title: '推荐书籍',
      items: [_book('found', title)],
    ),
  ],
);

Widget _app(Widget page) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: page),
);

Future<void> _searchPage(
  WidgetTester tester,
  _Client client,
  List<RegisteredBookSource> sources,
) async {
  addTearDown(client.close);
  await tester.pumpWidget(
    _app(
      SourceSearchPage(
        sources: sources,
        client: client,
        shelfService: BookSourceShelfService(client: client),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(
  WidgetTester tester,
  String query, {
  bool settle = true,
}) async {
  await tester.enterText(
    find.byKey(const Key('bookSourceQueryControl')),
    query,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<void> _discoverPage(
  WidgetTester tester,
  _Client client,
  List<RegisteredBookSource> sources, {
  bool settle = true,
}) async {
  addTearDown(client.close);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1100);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'open_reading_book_sources_v1': jsonEncode(
      sources.map((s) => s.toJson()).toList(),
    ),
  });
  await tester.pumpWidget(_app(BookSourcesPage(client: client)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  if (settle) await tester.pumpAndSettle();
}

class _Client extends BookSourceClient {
  Future<BookSourceSearchPage> Function(RegisteredBookSource, String, int)?
  searchResult;
  Future<BookSourceSearchPage> Function(RegisteredBookSource, String?, int)?
  browseResult;
  Future<BookSourceDiscoveryPage> Function(RegisteredBookSource)?
  discoverResult;
  final queries = <String>[];
  final detailSources = <String>[];

  @override
  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) {
    queries.add(query);
    return searchResult?.call(source, query, page) ?? Future.value(_page([]));
  }

  @override
  Future<BookSourceBook> getBook(RegisteredBookSource source, String id) async {
    detailSources.add(source.id);
    return _book(id, '剑来');
  }

  @override
  Future<BookSourceDiscoveryPage> getDiscovery(RegisteredBookSource source) =>
      discoverResult?.call(source) ?? Future.value(_discovery('剑来'));

  @override
  Future<List<BookSourceCategory>> getCategories(
    RegisteredBookSource source,
  ) async {
    final runtime = XbsRuntime();
    try {
      return await runtime.getCategories(source);
    } finally {
      runtime.close();
    }
  }

  @override
  Future<BookSourceSearchPage> browse(
    RegisteredBookSource source, {
    String? category,
    String sort = 'latest',
    int page = 1,
    int pageSize = 20,
  }) => browseResult?.call(source, category, page) ?? Future.value(_page([]));
}

Future<void> _pickSource(
  WidgetTester tester,
  String entryKey,
  String id,
) async {
  await tester.tap(find.byKey(Key(entryKey)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.byKey(Key('sourcePicker-$id')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('sourcePickerConfirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}
