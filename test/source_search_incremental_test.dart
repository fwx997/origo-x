import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/l10n/app_localizations.dart';
import 'package:xxread/pages/book_sources/source_search_page.dart';

void main() {
  testWidgets('matching books stay visible above unrelated site results', (
    tester,
  ) async {
    final client = _RankingClient();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourceSearchPage(
          sources: [_source('fast'), _source('slow')],
          client: client,
          shelfService: BookSourceShelfService(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('bookSourceQueryControl')),
      'Wanted',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Wanted sequel'), findsOneWidget);
    client.slow.complete(_rankingPage(['Wanted']));
    await tester.pumpAndSettle();
    final exactTitle = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == 'Wanted',
    );
    expect(exactTitle, findsOneWidget);
    expect(
      tester.getTopLeft(exactTitle).dy,
      lessThan(tester.getTopLeft(find.text('Wanted sequel')).dy),
    );
    // The default unfiltered mode still retains the site's other results.
    expect(find.text('Unrelated 0'), findsOneWidget);
  });

  testWidgets(
    'a slow source does not hide fast results and stop preserves them',
    (tester) async {
      final client = _DelayedClient();
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourceSearchPage(
            sources: [_source('fast'), _source('slow')],
            client: client,
            shelfService: BookSourceShelfService(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('bookSourceQueryControl')),
        'query',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Fast result'), findsOneWidget);
      expect(find.byKey(const Key('bookSourceStopSearch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bookSourceStopSearch')));
      await tester.pumpAndSettle();
      client.slow.complete(
        const BookSourceSearchPage(
          items: [
            BookSourceBook(
              id: 'late',
              title: 'Late result',
              author: '',
              description: '',
              categories: [],
            ),
          ],
          page: 1,
          pageSize: 20,
          hasMore: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fast result'), findsOneWidget);
      expect(find.text('Late result'), findsNothing);
    },
  );
}

RegisteredBookSource _source(String id) => RegisteredBookSource(
  id: id,
  name: id,
  description: '',
  manifestUrl: Uri.parse('https://$id.test/source.json'),
  apiBaseUrl: Uri.parse('https://$id.test/'),
  protocolVersion: '1.0',
  languages: const ['en'],
  capabilities: const {'search'},
  enabled: true,
  addedAt: DateTime.utc(2026),
);

class _DelayedClient extends BookSourceClient {
  final slow = Completer<BookSourceSearchPage>();
  @override
  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (source.id == 'slow') return slow.future;
    return const BookSourceSearchPage(
      items: [
        BookSourceBook(
          id: 'fast',
          title: 'Fast result',
          author: '',
          description: '',
          categories: [],
        ),
      ],
      page: 1,
      pageSize: 20,
      hasMore: false,
    );
  }
}

BookSourceSearchPage _rankingPage(List<String> titles) => BookSourceSearchPage(
  items: titles
      .map(
        (title) => BookSourceBook(
          id: title,
          title: title,
          author: '',
          description: '',
          categories: const [],
        ),
      )
      .toList(),
  page: 1,
  pageSize: 20,
  hasMore: false,
);

class _RankingClient extends BookSourceClient {
  final slow = Completer<BookSourceSearchPage>();

  @override
  Future<BookSourceSearchPage> search(
    RegisteredBookSource source,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (source.id == 'slow') return slow.future;
    return _rankingPage([
      ...List.generate(40, (i) => 'Unrelated $i'),
      'Wanted sequel',
    ]);
  }
}
