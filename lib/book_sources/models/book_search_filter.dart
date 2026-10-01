import '../protocol/book_source_protocol.dart';

enum BookSearchField { any, title, author }

enum BookSearchMatch { all, exact, contains }

/// Search sites accept keywords; these options filter their returned metadata.
/// Keep unknown authors separate instead of merging different works by title.
class BookSearchFilter {
  final String query;
  final BookSearchField field;
  final BookSearchMatch match;
  final BookSourceBook? reference;

  const BookSearchFilter({
    required this.query,
    this.field = BookSearchField.any,
    this.match = BookSearchMatch.all,
    this.reference,
  });

  bool accepts(BookSourceBook book) {
    final target = reference;
    if (target != null) return sameWork(target, book);
    if (match == BookSearchMatch.all) return true;
    final needle = field == BookSearchField.author
        ? normalizeAuthor(query)
        : normalize(query);
    if (needle.isEmpty) return false;
    final fields = switch (field) {
      BookSearchField.any => [book.title, normalizeAuthor(book.author)],
      BookSearchField.title => [book.title],
      BookSearchField.author => [normalizeAuthor(book.author)],
    };
    return fields
        .map(normalize)
        .any(
          (text) => match == BookSearchMatch.exact
              ? text == needle
              : text.contains(needle),
        );
  }

  static bool sameWork(BookSourceBook left, BookSourceBook right) {
    final title = normalize(left.title);
    if (title.isEmpty || title != normalize(right.title)) return false;
    final author = normalizeAuthor(left.author);
    final candidate = normalizeAuthor(right.author);
    // Missing authors remain visible as candidates, clearly marked by the UI.
    return author.isEmpty || candidate.isEmpty || author == candidate;
  }

  static String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s\u3000《》「」『』]'), '');

  static String normalizeAuthor(String value) {
    final result = normalize(
      value.replaceFirst(RegExp(r'^\s*作者\s*[:：]\s*'), ''),
    );
    return const {'未知', '佚名', '未知作者', 'unknown'}.contains(result) ? '' : result;
  }

  static String workKey(BookSourceBook book, String sourceId) {
    final title = normalize(book.title);
    final author = normalizeAuthor(book.author);
    if (title.isEmpty || author.isEmpty) return '$sourceId\n${book.id}';
    return '$title\n$author';
  }
}
