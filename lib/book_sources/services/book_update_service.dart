import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/registered_book_source.dart';
import '../protocol/book_source_protocol.dart';
import '../../services/books/book_dao.dart';
import '../../services/library/library_event_bus_service.dart';
import 'book_source_client.dart';
import 'book_source_shelf_service.dart';

class BookUpdateSnapshot {
  const BookUpdateSnapshot({
    required this.count,
    required this.latestChapter,
    required this.checkedAt,
    this.updatedAt,
    this.added = 0,
  });
  final int count;
  final String latestChapter;
  final DateTime checkedAt;
  final DateTime? updatedAt;
  final int added;

  Map<String, dynamic> toJson() => {
    'count': count,
    'latest': latestChapter,
    'checked': checkedAt.toIso8601String(),
    'updated': updatedAt?.toIso8601String(),
    'added': added,
  };

  factory BookUpdateSnapshot.fromJson(Map<String, dynamic> json) =>
      BookUpdateSnapshot(
        count: json['count'] as int,
        latestChapter: json['latest'] as String,
        checkedAt: DateTime.parse(json['checked'] as String),
        updatedAt: DateTime.tryParse(json['updated'] as String? ?? ''),
        added: json['added'] as int? ?? 0,
      );
}

class BookUpdateResult {
  const BookUpdateResult(this.snapshot, this.chapters);
  final BookUpdateSnapshot snapshot;
  final List<BookSourceChapter> chapters;
}

class BookUpdateService {
  BookUpdateService({BookSourceClient? client, BookDao? bookDao})
    : _client = client ?? BookSourceClient(),
      _dao = bookDao ?? BookDao();
  final BookSourceClient _client;
  final BookDao _dao;

  String _key(RegisteredBookSource source, BookSourceBook book) =>
      'book_update:${Uri.encodeComponent(source.id)}:${Uri.encodeComponent(book.id)}';

  Future<BookUpdateSnapshot?> load(
    RegisteredBookSource source,
    BookSourceBook book,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(source, book));
    if (raw == null) return null;
    try {
      return BookUpdateSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<BookUpdateResult> check(
    RegisteredBookSource source,
    BookSourceBook book, {
    int knownCount = 0,
  }) async {
    final previous = await load(source, book);
    final chapters = [...await _client.getChaptersFresh(source, book.id)]
      ..sort(compareBookSourceChapters);
    if (chapters.isEmpty)
      throw const BookSourceProtocolException('书源返回空目录，保留原目录');
    final baseline = previous?.count ?? knownCount;
    final snapshot = BookUpdateSnapshot(
      count: chapters.length,
      latestChapter: chapters.last.title,
      checkedAt: DateTime.now().toUtc(),
      updatedAt: chapters.last.updatedAt ?? book.updatedAt,
      added: baseline > 0
          ? (chapters.length - baseline).clamp(0, chapters.length)
          : 0,
    );
    final shelf = await _dao.getBookBySource(
      sourceId: source.id,
      sourceBookId: book.id,
    );
    if (shelf != null) {
      final metadata =
          jsonDecode(shelf.sourceBookJson!) as Map<String, dynamic>;
      metadata['latestChapter'] = snapshot.latestChapter;
      if (snapshot.updatedAt != null)
        metadata['updatedAt'] = snapshot.updatedAt!.toIso8601String();
      await _dao.updateSourceCatalog(
        shelf.id!,
        jsonEncode(metadata),
        chapters.length * BookSourceShelfService.unitsPerChapter,
      );
      LibraryEventBus().notifyLibraryChanged();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(source, book), jsonEncode(snapshot.toJson()));
    return BookUpdateResult(snapshot, chapters);
  }
}
