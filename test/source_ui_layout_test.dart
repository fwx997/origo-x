import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/book_sources/xbs/xbs_source.dart';
import 'package:xxread/book_sources/xbs/xbs_runtime.dart';
import 'package:xxread/l10n/app_localizations.dart';
import 'package:xxread/pages/book_sources/book_sources_page.dart';
import 'package:xxread/pages/book_sources/source_search_page.dart';
import 'package:xxread/pages/home/home_mobile_chrome.dart';
import 'package:xxread/utils/app_themes.dart';
import 'package:xxread/utils/ui_style.dart';

const _previewFont = String.fromEnvironment('XBS_PREVIEW_FONT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_previewFont.isEmpty) return;
    final bytes = ByteData.sublistView(File(_previewFont).readAsBytesSync());
    await (FontLoader('PreviewCJK')..addFont(Future.value(bytes))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final scenario in [
    (name: 'light', width: 390.0, scale: 1.0, dark: false, glass: false),
    (name: 'dark', width: 390.0, scale: 1.0, dark: true, glass: false),
    (name: 'narrow', width: 320.0, scale: 1.25, dark: false, glass: false),
    (name: 'large-text', width: 390.0, scale: 1.6, dark: true, glass: true),
  ]) {
    for (final search in [true, false]) {
      final name = '${search ? 'search' : 'discovery'}-${scenario.name}';
      testWidgets('$name keeps controls readable without overflow', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scenario.width, 844);
        addTearDown(tester.view.reset);
        final sources = ['知行书屋', '云海阅读', '远山书库'].map(_source).toList();
        SharedPreferences.setMockInitialValues({
          'open_reading_book_sources_v1': jsonEncode(
            sources.map((s) => s.toJson()).toList(),
          ),
        });
        final client = _PreviewClient();
        addTearDown(client.close);
        final colors = AppThemes.fromAccentColor(AppThemes.defaultAccentColor);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: scenario.dark
                    ? colors.darkColorScheme
                    : colors.lightColorScheme,
                fontFamily: _previewFont.isEmpty ? null : 'PreviewCJK',
                extensions: [
                  UiStyleThemeExtension(
                    style: scenario.glass
                        ? AppUiStyle.glass
                        : AppUiStyle.material3,
                  ),
                ],
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: child!,
              ),
              home: search
                  ? Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          key: const Key('previewOpenSearch'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SourceSearchPage(
                                sources: sources,
                                client: client,
                                shelfService: BookSourceShelfService(
                                  client: client,
                                ),
                              ),
                            ),
                          ),
                          child: const Text('找书'),
                        ),
                      ),
                    )
                  : Scaffold(
                      appBar: AppBar(title: const Text('发现')),
                      body: HomeMobileChromeScope(
                        metrics: const HomeMobileChromeMetrics(
                          systemTopInset: 0,
                          systemBottomInset: 0,
                          topBarContentHeight: 0,
                          floatingNavHeight: 0,
                        ),
                        child: BookSourcesPage(client: client),
                      ),
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (search) {
          await tester.tap(find.byKey(const Key('previewOpenSearch')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('bookSourceQueryControl')),
            '长夜',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
        } else {
          await tester.tap(find.text('分类'));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (_previewFont.isNotEmpty) await _savePreview(tester, key, name);
      });
    }
  }
}

Future<void> _savePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('.dart_tool/ui-previews/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

RegisteredBookSource _source(String name) => XbsSource(name, {
  'sourceName': name,
  'sourceUrl': 'https://preview.test/',
  'searchBook': {'requestInfo': '/search?q=%@keyWord'},
  'bookWorld': {
    '精选小说': {
      'requestInfo': '/rank?p=%@pageIndex',
      'moreKeys': {
        'requestFilters':
            'class\n全部分类::0\n玄幻奇幻::1\n都市言情::2\n'
            'sort\n人气排行::0\n最新上架::1\n'
            'status\n全部状态::0\n连载::1\n完本::2\n'
            'date_type\n全部时间::0\n本月::1',
      },
    },
  },
}).toRegisteredSource();

BookSourceBook _book(String id, String title, String author) => BookSourceBook(
  id: id,
  title: title,
  author: author,
  description: '穿过群山与旧城，在漫长的旅途中寻找答案。',
  categories: const [],
);

List<BookSourceBook> get _books => [
  _book('1', '长夜行', '林间风'),
  _book('2', '长夜里的旅人与星河：从远山出发', '顾南'),
  _book('3', '长夜见青山', '云白'),
];

class _PreviewClient extends BookSourceClient {
  @override
  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async => BookSourceSearchPage(
    items: source.name == '知行书屋' ? _books : [_books.first],
    page: page,
    pageSize: pageSize,
    hasMore: false,
  );

  @override
  Future<BookSourceDiscoveryPage> getDiscovery(
    RegisteredBookSource source,
  ) async => const BookSourceDiscoveryPage(sections: []);

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
  }) async => BookSourceSearchPage(
    items: _books,
    page: page,
    pageSize: pageSize,
    hasMore: false,
  );
}
