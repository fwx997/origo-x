import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/book.dart';
import '../../services/books/book_dao.dart';
import '../models/book_search_filter.dart';

/// Explicit links use stable shelf IDs, so renaming never disconnects editions.
/// Editions keep their own files, annotations and reading positions.
class BookSourceLinkService {
  BookSourceLinkService({BookDao? bookDao}) : _dao = bookDao ?? BookDao();
  final BookDao _dao;
  static const _key = 'book_source_links_v1';
  static Future<void>? _writes;

  static bool canUseLocalSource(Book book) =>
      !book.isOnline &&
      book.filePath.isNotEmpty &&
      const {
        'txt',
        'epub',
        'html',
        'htm',
        'xhtml',
        'md',
        'markdown',
        'fb2',
        'rtf',
        'docx',
        'mobi',
        'azw',
        'azw3',
      }.contains(book.format.toLowerCase());

  static bool sameIdentity(Book a, Book b) {
    final author = BookSearchFilter.normalizeAuthor(a.author);
    return author.isNotEmpty &&
        author == BookSearchFilter.normalizeAuthor(b.author) &&
        BookSearchFilter.normalize(a.title).isNotEmpty &&
        BookSearchFilter.normalize(a.title) ==
            BookSearchFilter.normalize(b.title);
  }

  Future<List<List<int>>> _links(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final json = jsonDecode(raw) as List;
    return json.map((edge) => (edge as List).cast<int>()).toList();
  }

  Future<void> link(int a, int b) {
    if (a == b) return Future.value();
    final previous = _writes;
    final next = previous == null
        ? _writeLink(a, b)
        : previous.catchError((Object _) {}).then((_) => _writeLink(a, b));
    _writes = next;
    return next.whenComplete(() {
      if (identical(_writes, next)) _writes = null;
    });
  }

  Future<void> _writeLink(int a, int b) async {
    final prefs = await SharedPreferences.getInstance();
    final links = await _links(prefs);
    if (!links.any((edge) => edge.contains(a) && edge.contains(b))) {
      links.add([a, b]);
    }
    await prefs.setString(_key, jsonEncode(links));
  }

  Future<List<Book>> candidates(Book anchor) async {
    final prefs = await SharedPreferences.getInstance();
    final links = await _links(prefs);
    final ids = <int>{if (anchor.id != null) anchor.id!};
    var changed = true;
    while (changed) {
      final before = ids.length;
      for (final edge in links) {
        if (edge.any(ids.contains)) ids.addAll(edge);
      }
      changed = before != ids.length;
    }
    final books = await _dao.getAllBooks();
    return books
        .where(
          (book) =>
              book.id != anchor.id &&
              (book.isOnline || canUseLocalSource(book)) &&
              (ids.contains(book.id) || sameIdentity(anchor, book)),
        )
        .toList();
  }

  Future<List<Book>> localBooks() async =>
      (await _dao.getAllBooks()).where(canUseLocalSource).toList();
}
