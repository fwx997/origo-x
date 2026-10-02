import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_reading_progress.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/book_sources/services/book_source_switch.dart';
import 'package:xxread/core/reader/reader_text_appearance.dart';
import 'package:xxread/core/reader/reader_settings.dart';
import 'package:xxread/l10n/app_localizations.dart';
import 'package:xxread/models/book.dart';
import 'package:xxread/pages/reader/book_source_reader_page.dart';
import 'package:xxread/pages/reader/source_book_settings_page.dart';
import 'package:xxread/pages/book_sources/source_search_page.dart';
import 'package:xxread/utils/reader_themes.dart';
import 'package:xxread/widgets/reader_control_chrome.dart';
import 'package:xxread/widgets/reader_annotated_text_page.dart';
import 'package:xxread/widgets/reader_settings_controls.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'chapter titles align across numbering changes and shifted catalogs',
    () async {
      final client = _Client();
      addTearDown(client.close);
      final plan = await prepareBookSourceSwitch(
        client: client,
        source: _source('B'),
        book: _book('B'),
        chapterTitle: '第2章 重逢',
        chapterIndex: 1,
        chapterProgress: 0.4,
      );
      expect(plan.progress.chapterIndex, 2);
      expect(plan.progress.chapterId, 'B-2');
      expect(plan.progress.chapterProgress, 0.4);
      expect(plan.content.chapterId, 'B-2');
      client.failContent = true;
      await expectLater(
        prepareBookSourceSwitch(
          client: client,
          source: _source('B'),
          book: _book('B'),
          chapterTitle: 'missing',
          chapterIndex: 99,
          chapterProgress: 0,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'brightness changes only glyph opacity and night reduction is optional',
    () {
      expect(
        readerBodyTextColor(ReaderThemes.day, 0.5, true).a,
        closeTo(0.5, 0.01),
      );
      expect(
        readerBodyTextColor(ReaderThemes.night, 1, true).a,
        closeTo(0.7, 0.01),
      );
      expect(
        readerBodyTextColor(ReaderThemes.night, 1, false),
        ReaderThemes.night.text,
      );
    },
  );

  testWidgets(
    'reader more menu switches sources and remains available afterward',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      SharedPreferences.setMockInitialValues({
        'open_reading_book_sources_v1': jsonEncode([
          _source('A').toJson(),
          _source('B').toJson(),
          _source('C').toJson(),
        ]),
      });
      const progressStore = BookSourceReadingProgressStore();
      await progressStore.save(
        sourceId: 'A',
        bookId: 'book-A',
        progress: BookSourceReadingProgress(
          chapterId: 'A-1',
          chapterIndex: 1,
          chapterProgress: 0.4,
          updatedAt: DateTime.now(),
        ),
      );
      final client = _Client();
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.system,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BookSourceReaderPage(
            source: _source('A'),
            book: _book('A'),
            client: client,
            shelfService: _Shelf(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2/2章'), findsOneWidget);
      client.failContent = true;
      await _switchTo(tester, 'B');
      expect(_currentSource(tester), 'A');
      expect(
        tester
            .widget<ReaderChromeOverlay>(find.byType(ReaderChromeOverlay))
            .chapterProgressLabel,
        '2/2章',
      );
      expect(find.textContaining('换源失败'), findsOneWidget);
      expect(await progressStore.load(sourceId: 'B', bookId: 'book-B'), isNull);
      client.failContent = false;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _switchTo(tester, 'B');
      expect(
        tester
            .widget<BookSourceReaderPage>(find.byType(BookSourceReaderPage))
            .source
            .id,
        'B',
      );
      expect(client.catalogCalls['B'], 2); // One failed attempt, one handoff.
      expect(find.text('3/3章'), findsOneWidget);
      final saved = await progressStore.load(sourceId: 'B', bookId: 'book-B');
      expect(saved?.chapterId, 'B-2');
      await _switchTo(tester, 'A');
      expect(_currentSource(tester), 'A');
      expect(client.catalogCalls['A'], 2); // Initial load plus return to A.
      expect(find.text('2/2章'), findsOneWidget);
      await _openBookSettings(tester);
      await tester.tap(
        find.byKey(const ValueKey('source-book-readingSettings')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsSheet), findsOneWidget);
      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      for (final entry in {
        'reader-text-brightness': 0.5,
        'reader-font-weight': 700.0,
      }.entries) {
        final control = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(
          find.descendant(of: control, matching: find.byType(Slider)),
        );
        slider.onChanged!(entry.value);
        slider.onChangeEnd!(entry.value);
        await tester.pumpAndSettle();
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(ReaderSettingsStore.textBrightnessKey), 0.5);
      expect(prefs.getInt(ReaderSettingsStore.fontWeightKey), 700);
      final bodies = tester.widgetList<ReaderAnnotatedTextPage>(
        find.byType(ReaderAnnotatedTextPage, skipOffstage: false),
      );
      expect(bodies, isNotEmpty);
      for (final body in bodies) {
        expect(body.bodyStyle.fontWeight, FontWeight.w700);
        expect(body.bodyStyle.color?.a, closeTo(0.5, 0.01));
      }
      await tester.ensureVisible(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      final progressToggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('reader-chapter-progress-toggle')),
      );
      progressToggle.onChanged!(false);
      await tester.pump();
      Navigator.of(tester.element(find.byType(ReaderSettingsSheet))).pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderChromeOverlay>(find.byType(ReaderChromeOverlay))
            .chapterProgressLabel,
        isNull,
      );
      expect(prefs.getBool(ReaderSettingsStore.chapterProgressKey), false);
    },
  );
}

String _currentSource(WidgetTester tester) => tester
    .widget<BookSourceReaderPage>(find.byType(BookSourceReaderPage))
    .source
    .id;

Future<void> _openBookSettings(WidgetTester tester) async {
  final chrome = tester.widget<ReaderChromeOverlay>(
    find.byType(ReaderChromeOverlay),
  );
  if (!chrome.visible) {
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('reader-book-settings')));
  await tester.pumpAndSettle();
  expect(find.byType(SourceBookSettingsPage), findsOneWidget);
  expect(
    Theme.of(tester.element(find.text('书籍设置'))).brightness,
    tester.platformDispatcher.platformBrightness,
  );
}

Future<void> _switchTo(WidgetTester tester, String id) async {
  await _openBookSettings(tester);
  await tester.tap(find.byKey(const ValueKey('source-book-changeSource')));
  await tester.pumpAndSettle();
  expect(
    Theme.of(tester.element(find.byType(SourceSearchPage))).brightness,
    tester.platformDispatcher.platformBrightness,
  );
  final title = find.byWidgetPredicate(
    (w) => w is Text && w.data == 'Test book',
  );
  await tester.tap(title.last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Source $id'),
    ),
  );
  await tester.pumpAndSettle();
}

RegisteredBookSource _source(String id) => RegisteredBookSource(
  id: id,
  name: 'Source $id',
  description: '',
  manifestUrl: Uri.parse('https://$id.test/source.json'),
  apiBaseUrl: Uri.parse('https://$id.test/'),
  protocolVersion: '1.0',
  languages: const ['zh'],
  capabilities: const {'search', 'catalog', 'content'},
  enabled: true,
  addedAt: DateTime.utc(2026),
);

BookSourceBook _book(String id) => BookSourceBook(
  id: 'book-$id',
  title: 'Test book',
  author: 'Author',
  description: 'A book description.',
  categories: const [],
);

class _Shelf extends BookSourceShelfService {
  _Shelf({required super.client});
  @override
  Future<Book?> findShelfBook({
    required String sourceId,
    required String sourceBookId,
  }) async => null;
}

class _Client extends BookSourceClient {
  bool failContent = false;
  final catalogCalls = <String, int>{};
  @override
  Future<List<BookSourceChapter>> getChapters(
    RegisteredBookSource source,
    String bookId,
  ) async {
    catalogCalls.update(source.id, (n) => n + 1, ifAbsent: () => 1);
    final titles = source.id == 'A'
        ? ['第1章 初见', '第2章 重逢']
        : ['序章', '第一章 初见', '第二章 重逢'];
    return List.generate(
      titles.length,
      (i) =>
          BookSourceChapter(id: '${source.id}-$i', title: titles[i], order: i),
    );
  }

  @override
  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async => BookSourceSearchPage(
    items: [_book(source.id)],
    page: 1,
    pageSize: 20,
    hasMore: false,
  );
  @override
  Future<BookSourceChapterContent> getChapterContent(
    RegisteredBookSource source, {
    required String bookId,
    required String chapterId,
  }) async {
    if (failContent) throw StateError('Unavailable content');
    return BookSourceChapterContent(
      bookId: bookId,
      chapterId: chapterId,
      title: 'Chapter',
      content: List.filled(100, '这是阅读测试正文，切换书源后应保留阅读位置。').join('\n'),
      contentType: 'text/plain',
    );
  }
}
