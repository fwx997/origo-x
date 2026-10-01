import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/book_sources/models/book_search_filter.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/xbs/xbs_discovery.dart';

BookSourceBook book(String title, String author) => BookSourceBook(
  id: title,
  title: title,
  author: author,
  description: '',
  categories: const [],
);

void main() {
  test('original array filters retain key/items/title/value semantics', () {
    final groups = XbsDiscovery.filterGroups([
      {
        'key': 'filter',
        'items': [
          {'title': '纯爱', 'value': 'chunai'},
          {'title': '言情', 'value': 'yanqing'},
        ],
      },
      {
        'key': 'sort',
        'items': [
          {'title': '原创', 'value': '2'},
          {'title': '衍生和轻小说', 'value': '3'},
        ],
      },
    ]);
    expect(groups.map((g) => g.id), ['filter', 'sort']);
    expect(groups.first.options.map((o) => o.value), ['chunai', 'yanqing']);
    expect(groups.last.options.last.name, '衍生和轻小说');
  });
  test('exact and substring filters distinguish title and author', () {
    const exact = BookSearchFilter(
      query: '剑来',
      field: BookSearchField.title,
      match: BookSearchMatch.exact,
    );
    expect(exact.accepts(book('《剑 来》', '烽火戏诸侯')), isTrue);
    expect(exact.accepts(book('剑来续集', '烽火戏诸侯')), isFalse);
    expect(exact.accepts(book('别的书', '剑来')), isFalse);
    const fuzzy = BookSearchFilter(
      query: '剑来',
      field: BookSearchField.title,
      match: BookSearchMatch.contains,
    );
    expect(fuzzy.accepts(book('剑来续集', '烽火戏诸侯')), isTrue);
    const author = BookSearchFilter(
      query: '烽火戏诸侯',
      field: BookSearchField.author,
      match: BookSearchMatch.exact,
    );
    expect(author.accepts(book('剑来', '作者：烽火戏诸侯')), isTrue);
    expect(author.accepts(book('烽火戏诸侯', '其他作者')), isFalse);
    expect(
      const BookSearchFilter(
        query: 'test',
        match: BookSearchMatch.exact,
      ).accepts(book('TEST', 'A')),
      isTrue,
    );
  });

  test('same title different authors are never grouped into the same work', () {
    final original = book('剑来', '烽火戏诸侯');
    final same = book('《剑来》', '作者：烽火戏诸侯');
    final different = book('剑来', '其他作者');
    expect(BookSearchFilter.sameWork(original, same), isTrue);
    expect(BookSearchFilter.sameWork(original, different), isFalse);
    expect(
      BookSearchFilter.workKey(original, 'a'),
      BookSearchFilter.workKey(same, 'b'),
    );
    expect(
      BookSearchFilter.workKey(original, 'a'),
      isNot(BookSearchFilter.workKey(different, 'b')),
    );
    final unknown = book('剑来', '未知');
    expect(
      BookSearchFilter.workKey(unknown, 'a'),
      isNot(BookSearchFilter.workKey(unknown, 'b')),
    );
  });

  test('original named filter groups preserve their keys and values', () {
    final groups = XbsDiscovery.filterGroups(
      'type\r\n完本榜::finish\r\n字数榜::word_number\r\n新书榜::new_book\r\n'
      'class\r\n全部::0\r\n玄幻::3\r\n同值::3\r\n路径::https://test/a::b',
    );
    expect(groups.map((g) => g.id), ['type', 'class']);
    expect(groups.first.options.map((v) => v.value), [
      'finish',
      'word_number',
      'new_book',
    ]);
    expect(groups.last.options.map((v) => v.value), [
      '0',
      '3',
      'https://test/a::b',
    ]);
  });
}
