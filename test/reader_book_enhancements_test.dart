import 'package:xxread/pages/reader/source_book_settings_page.dart';
import 'package:xxread/pages/book_sources/shelf_source_picker.dart';
import 'package:xxread/pages/book_sources/shelf_source_navigation.dart';
import 'package:xxread/pages/reader/native_reader_page.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/l10n/app_localizations.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_download_cancellation.dart';
import 'package:xxread/book_sources/services/book_source_chapter_cache.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_link_service.dart';
import 'package:xxread/book_sources/services/book_update_service.dart';
import 'package:xxread/models/book.dart';
import 'package:xxread/services/books/book_dao.dart';
import 'package:xxread/services/books/book_rename_service.dart';
import 'package:xxread/utils/reader_themes.dart';
import 'package:xxread/widgets/book_update_card.dart';
import 'package:xxread/widgets/reader_control_chrome.dart';
import 'package:xxread/widgets/reader_toolbar_preferences.dart';

final source = RegisteredBookSource(
  id: 'enhancement-test',
  name: '测试书源',
  description: '',
  manifestUrl: Uri.parse('https://example.com/manifest'),
  apiBaseUrl: Uri.parse('https://example.com/api'),
  protocolVersion: '1.0',
  languages: const ['zh'],
  capabilities: const {'search', 'detail', 'catalog', 'content'},
  enabled: true,
  addedAt: DateTime.utc(2026),
);
const sourceBook = BookSourceBook(
  id: 'book',
  title: '春日来信',
  author: '作者甲',
  description: '',
  categories: [],
);

Book shelfBook(int id, {String title = '春日来信', String author = '作者甲'}) => Book(
  id: id,
  title: title,
  author: author,
  filePath: '/books/$id.txt',
  format: 'txt',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookSourceChapterCache.clearMemory();
    ReaderToolbarStore.state.value = const ReaderToolbarPreferences();
  });

  testWidgets(
    'an imported book can be linked explicitly and selected as a local source',
    (tester) async {
      final anchor = shelfBook(1).copyWith(storageType: 'online');
      final local = shelfBook(2, title: '手工导入的版本', author: '未知');
      final dao = _Dao([anchor, local]);
      final client = _Client(const BookSourceChapterCache());
      addTearDown(client.close);
      SharedPreferences.setMockInitialValues({
        'open_reading_book_sources_v1': jsonEncode([source.toJson()]),
      });
      ShelfSourceChoice? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showShelfSourcePicker(
                    context,
                    anchor: anchor,
                    client: client,
                    shelfService: BookSourceShelfService(),
                    linkService: BookSourceLinkService(bookDao: dao),
                  );
                },
                child: const Text('选择来源'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择来源'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关联本地书'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(local.title));
      await tester.pumpAndSettle();
      expect(find.text('1 个来源'), findsOneWidget);
      await tester.tap(find.text('本地及已关联来源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(local.title));
      await tester.pumpAndSettle();
      expect(selected?.local?.id, local.id);
      expect(
        (await BookSourceLinkService(
          bookDao: dao,
        ).candidates(anchor)).single.id,
        local.id,
      );
    },
  );

  test(
    'switching to a linked local edition retains its file and reading position',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'linked-edition-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/local.txt');
      await file.writeAsString('第一章 正文');
      final local = shelfBook(
        2,
      ).copyWith(filePath: file.path, currentPage: 3, totalPages: 10);
      final client = _Client(const BookSourceChapterCache());
      addTearDown(client.close);
      final result = await prepareShelfSourceChoice(
        anchor: shelfBook(1).copyWith(storageType: 'online'),
        choice: ShelfSourceChoice.local(local),
        client: client,
        shelfService: BookSourceShelfService(),
        bookDao: _Dao([local]),
      );
      expect(result.reader, isA<NativeReaderPage>());
      expect(result.book.currentPage, 3);
      expect(result.book.filePath, file.path);
      expect(await file.readAsString(), '第一章 正文');
    },
  );

  test(
    'same-work suggestions require a known matching author; explicit links survive renames',
    () async {
      final dao = _Dao([
        shelfBook(1),
        shelfBook(2),
        shelfBook(3, author: '作者乙'),
        shelfBook(4, author: '未知'),
      ]);
      final links = BookSourceLinkService(bookDao: dao);
      expect((await links.candidates(dao.books.first)).map((b) => b.id), [2]);
      await links.link(1, 2);
      dao.books[1] = dao.books[1].copyWith(title: '手工重命名', author: '笔名');
      expect(
        (await BookSourceLinkService(
          bookDao: dao,
        ).candidates(dao.books.first)).map((b) => b.id),
        [2],
      );
      await links.link(2, 3);
      expect((await links.candidates(dao.books.first)).map((b) => b.id), [
        2,
        3,
      ]);
    },
  );

  test(
    'editing only the author keeps the local file and source identity',
    () async {
      final directory = await Directory.systemTemp.createTemp('book-author-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/original.txt');
      await file.writeAsString('正文');
      final book = shelfBook(1).copyWith(
        filePath: file.path,
        sourceId: source.id,
        sourceBookId: sourceBook.id,
        sourceBookJson: jsonEncode(sourceBook.toJson()),
      );
      final dao = _Dao([book]);
      final updated = await BookRenameService(
        bookDao: dao,
      ).rename(book, book.title, newAuthor: '新作者');
      expect(updated.author, '新作者');
      expect(updated.filePath, file.path);
      expect(await file.readAsString(), '正文');
      expect(jsonDecode(updated.sourceBookJson!)['author'], '新作者');
      expect(updated.sourceBookId, sourceBook.id);
    },
  );

  test(
    'update checks replace fresh catalog cache and failures preserve the last successful check',
    () async {
      final directory = await Directory.systemTemp.createTemp('book-update-');
      addTearDown(() => directory.delete(recursive: true));
      final cache = BookSourceChapterCache(cacheDirectory: directory);
      final client = _Client(cache);
      addTearDown(client.close);
      await cache.getChapterCatalogOrLoad(
        sourceId: source.id,
        sourceRevision: source.apiBaseUrl.toString(),
        bookId: sourceBook.id,
        loader: () async => [
          const BookSourceChapter(id: 'old', title: '旧目录', order: 0),
        ],
      );
      final service = BookUpdateService(client: client, bookDao: _Dao([]));
      final result = await service.check(source, sourceBook, knownCount: 2);
      expect(client.freshCalls, 1);
      expect(result.snapshot.count, 3);
      expect(result.snapshot.added, 1);
      expect(
        (await client.getChapters(source, sourceBook.id)).last.title,
        '第三章 新的旅程',
      );
      client.fail = true;
      await expectLater(service.check(source, sourceBook), throwsStateError);
      expect(
        (await service.load(source, sourceBook))!.checkedAt,
        result.snapshot.checkedAt,
      );
      expect((await client.getChapters(source, sourceBook.id)).length, 3);
    },
  );

  testWidgets(
    'toolbar visibility and order persist while top settings stays reachable',
    (tester) async {
      var openedSettings = 0;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _chrome(() => openedSettings++))),
      );
      await tester.pumpAndSettle();
      await ReaderToolbarStore.save(
        const ReaderToolbarPreferences(
          labels: true,
          order: [
            ReaderToolbarAction.settings,
            ReaderToolbarAction.catalog,
            ReaderToolbarAction.ai,
            ReaderToolbarAction.aloud,
          ],
          hidden: {ReaderToolbarAction.ai, ReaderToolbarAction.aloud},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('阅读设置')).dx,
        lessThan(tester.getTopLeft(find.text('目录')).dx),
      );
      await ReaderToolbarStore.save(
        ReaderToolbarStore.state.value.copyWith(enabled: false),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-bottom-bar')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reader-book-settings')));
      expect(openedSettings, 1);
      await ReaderToolbarStore.load();
      expect(ReaderToolbarStore.state.value.enabled, isFalse);
      expect(
        ReaderToolbarStore.state.value.order.first,
        ReaderToolbarAction.settings,
      );
    },
  );

  testWidgets(
    'book update card reports new chapters and remains usable in both themes',
    (tester) async {
      if (Platform.environment['READER_CAPTURE_FONT'] case final path?) {
        await tester.runAsync(() async {
          final loader = FontLoader('CaptureFont')
            ..addFont(
              File(
                path,
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
          if (Platform.environment['READER_CAPTURE_ICONS'] case final icons?) {
            final iconLoader = FontLoader('MaterialIcons')
              ..addFont(
                File(
                  icons,
                ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
              );
            await iconLoader.load();
          }
        });
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = _Client(const BookSourceChapterCache());
      addTearDown(client.close);
      final service = BookUpdateService(client: client, bookDao: _Dao([]));
      for (final brightness in Brightness.values) {
        final repaint = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'CaptureFont'),
            home: RepaintBoundary(
              key: repaint,
              child: Scaffold(
                appBar: AppBar(title: const Text('书籍信息')),
                body: SingleChildScrollView(
                  child: BookUpdateCard(
                    key: ValueKey(brightness),
                    source: source,
                    book: sourceBook,
                    knownCount: 2,
                    service: service,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
        expect(find.text('最新章节：第三章 新的旅程'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, repaint, 'book-update-${brightness.name}');
        final settingsRepaint = GlobalKey();
        await ReaderToolbarStore.save(
          const ReaderToolbarPreferences(labels: true),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'CaptureFont'),
            home: RepaintBoundary(
              key: settingsRepaint,
              child: const ReaderToolbarSettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          settingsRepaint,
          'reader-toolbar-${brightness.name}',
        );
        final bookSettingsRepaint = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'CaptureFont'),
            home: RepaintBoundary(
              key: bookSettingsRepaint,
              child: SourceBookSettingsPage(
                source: source,
                book: sourceBook,
                chapterCount: 3,
                latestChapter: '第三章 新的旅程',
                updateService: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('检查更新'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          bookSettingsRepaint,
          'book-settings-${brightness.name}',
        );
      }
    },
  );
}

Widget _chrome(VoidCallback onSettings) => ReaderChromeOverlay(
  palette: ReaderThemes.day,
  visible: true,
  title: '阅读测试',
  statusBottom: 8,
  statusBuilder: (_, _, _) => const SizedBox.shrink(),
  onBack: () {},
  onBookmark: () {},
  onTableOfContents: () {},
  onSettings: onSettings,
  backTooltip: '返回',
  bookmarkTooltip: '加入书架',
  tableOfContentsTooltip: '目录',
  settingsTooltip: '设置',
  bookmarked: false,
  addToShelf: true,
  bottomKey: const ValueKey('test-bottom-bar'),
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!Platform.environment.containsKey('READER_CAPTURE_UI')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/reader-enhancements-ui');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Dao extends BookDao {
  _Dao(this.books);
  final List<Book> books;
  @override
  Future<List<Book>> getAllBooks() async => books;
  @override
  Future<Book?> getBookById(int id) async =>
      books.where((b) => b.id == id).firstOrNull;
  @override
  Future<void> updateBook(Book book) async {
    books[books.indexWhere((b) => b.id == book.id)] = book;
  }

  @override
  Future<Book?> getBookBySource({
    required String sourceId,
    required String sourceBookId,
  }) async => null;
}

class _Client extends BookSourceClient {
  _Client(BookSourceChapterCache cache) : super(chapterCache: cache);
  @override
  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async => const BookSourceSearchPage(
    items: [],
    page: 1,
    pageSize: 20,
    hasMore: false,
  );
  int freshCalls = 0;
  bool fail = false;
  @override
  Future<List<BookSourceChapter>> getChaptersForDownload(
    RegisteredBookSource source,
    String bookId, {
    BookDownloadCancellation? cancellation,
  }) async {
    freshCalls++;
    if (fail) throw StateError('网络断开');
    return const [
      BookSourceChapter(id: '1', title: '第一章', order: 0),
      BookSourceChapter(id: '2', title: '第二章', order: 1),
      BookSourceChapter(id: '3', title: '第三章 新的旅程', order: 2),
    ];
  }
}
