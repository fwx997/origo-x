import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/book_sources/legado/legado_request.dart';
import 'package:xxread/book_sources/xbs/xbs_runtime.dart';
import 'package:xxread/book_sources/xbs/xbs_source.dart';

// Original Songhe action rules, with a fixture GUID; all responses are synthetic.
// Run with XBS_NATIVE_TEST=true and FJS on PATH. No network requests are made.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'Songhe original scripts',
    () {
      test(
        'queryInfo supplies book metadata and the current chapter title',
        () async {
          final original = _source();
          (original.config['chapterContent'] as Map)['requestInfo'] = '''@js:
          return {url: '/be-api/content/ads-read', POST: true,
            httpHeaders: {'Content-Type': 'application/json'},
            httpParams: params.queryInfo};
        ''';
          final source = original.toRegisteredSource();
          final transport = _SongheTransport();
          final runtime = XbsRuntime(transport: transport);
          addTearDown(runtime.close);
          final book = (await runtime.search(source, 'Fixture')).items.single;
          final chapters = await runtime.getChapters(source, book.id);
          await runtime.getChapterContent(
            source,
            bookId: book.id,
            chapterId: chapters.last.id,
          );
          expect(jsonDecode(transport.requests.last.body!), {
            'bookId': book.id,
            'detailUrl': book.id,
            'bookName': book.title,
            'url': chapters.last.id,
            'id': chapters.last.id,
            'title': 'Chapter two',
          });
        },
      );
      test('connect search, detail, catalog and JSON chapter POST', () async {
        final source = _source();
        final transport = _SongheTransport();
        final runtime = XbsRuntime(transport: transport);
        addTearDown(runtime.close);
        final books = await runtime.search(
          source.toRegisteredSource(),
          'Fixture',
        );
        expect(books.items.single.id, '1131822340');
        expect(books.items.single.title, 'Fixture book');
        final book = await runtime.getBook(
          source.toRegisteredSource(),
          books.items.single.id,
        );
        expect(book.author, 'Fixture author');
        expect(transport.requests, hasLength(1));
        final chapters = await runtime.getChapters(
          source.toRegisteredSource(),
          book.id,
        );
        expect(chapters.map((c) => c.id), ['1131822340_1', '1131822340_2']);
        expect(transport.requests.last.url.queryParameters['bookId'], book.id);
        // Resume in a new runtime, as after restarting the app: IDs must suffice.
        final resumed = XbsRuntime(transport: transport);
        addTearDown(resumed.close);
        final content = await resumed.getChapterContent(
          source.toRegisteredSource(),
          bookId: book.id,
          chapterId: chapters.last.id,
        );
        expect(content.content, 'Fixture paragraph.');
        final request = transport.requests.last;
        expect(request.method, LegadoRequestMethod.post);
        expect(
          request.url.toString(),
          'https://novel.html5.qq.com/be-api/content/ads-read',
        );
        expect(jsonDecode(request.body!), {
          'Scene': 'chapter',
          'ContentAnchorBatch': [
            {
              'BookID': book.id,
              'ChapterSeqNo': ['2'],
            },
          ],
        });
      });

      test(
        'discovery preserves the API identifier used by catalog scripts',
        () async {
          final source = _source().toRegisteredSource();
          final runtime = XbsRuntime(transport: _SongheTransport());
          addTearDown(runtime.close);
          final books = await runtime.browse(source);
          expect(books.items.single.id, '1131822340');
          final chapters = await runtime.getChapters(
            source,
            books.items.single.id,
          );
          final content = await runtime.getChapterContent(
            source,
            bookId: books.items.single.id,
            chapterId: chapters.first.id,
          );
          expect(content.content, 'Fixture paragraph.');
        },
      );
    },
    skip: !const bool.fromEnvironment('XBS_NATIVE_TEST'),
  );
}

XbsSource _source() => XbsSource(
  'x-松鹤阅读',
  jsonDecode(File('test/fixtures/xbs_songhe.json').readAsStringSync())
      as Map<String, dynamic>,
);

class _SongheTransport implements LegadoTransport {
  final requests = <LegadoRequestTemplate>[];
  @override
  Future<LegadoResponse> send(LegadoRequestTemplate request) async {
    requests.add(request);
    final Object body = switch (request.url.path) {
      '/ajax/real/search_result' => {
        'data': {
          'state': [
            {
              'dataID': 100,
              'items': [
                {'title': 'Not a book'},
              ],
            },
            {
              'dataID': 360,
              'items': [
                {
                  'docId': '90000001_1131822340',
                  'title': 'Fixture book',
                  'author': 'Fixture author',
                  'abstract': 'Fixture description',
                  'cover_url': 'https://books.test/cover.jpg',
                  'tag_views': 'Fiction',
                },
              ],
            },
          ],
        },
      },
      '/qbread/api/rank/list' => {
        'rows': [
          {
            'resourceID': '1131822340',
            'resourceName': 'Fixture book',
            'author': 'Fixture author',
            'summary': 'Fixture description',
            'picurl': 'https://books.test/cover.jpg',
            'subject': 'Fiction',
          },
        ],
      },
      '/qbread/api/book/all-chapter' => {
        'rows': [
          {'serialID': 1, 'serialName': 'Chapter one'},
          {'serialID': 2, 'serialName': 'Chapter two'},
        ],
      },
      '/be-api/content/ads-read' => {
        'data': {
          'Content': [
            {
              'Content': ['Fixture paragraph.'],
            },
          ],
        },
      },
      _ => throw StateError('Unexpected request: ${request.url}'),
    };
    return LegadoResponse(body: jsonEncode(body), finalUri: request.url);
  }
}
