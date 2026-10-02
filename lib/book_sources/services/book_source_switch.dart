import '../models/registered_book_source.dart';
import '../protocol/book_source_protocol.dart';
import 'book_source_client.dart';
import 'book_source_reading_progress.dart';

class BookSourceSwitchPlan {
  const BookSourceSwitchPlan(this.chapters, this.progress, this.content);
  final List<BookSourceChapter> chapters;
  final BookSourceReadingProgress progress;
  final BookSourceChapterContent content;
}

/// Prepare everything that can fail before replacing the current reading session.
Future<BookSourceSwitchPlan> prepareBookSourceSwitch({
  required BookSourceClient client,
  required RegisteredBookSource source,
  required BookSourceBook book,
  required String chapterTitle,
  required int chapterIndex,
  required double chapterProgress,
}) async {
  final chapters = [...await client.getChapters(source, book.id)]
    ..sort(compareBookSourceChapters);
  if (chapters.isEmpty) throw const BookSourceProtocolException('新书源没有返回目录');
  final title = _chapterName(chapterTitle);
  final matched = title.isEmpty
      ? -1
      : chapters.indexWhere((c) => _chapterName(c.title) == title);
  final index = matched >= 0
      ? matched
      : chapterIndex.clamp(0, chapters.length - 1);
  final content = await client.getChapterContent(
    source,
    bookId: book.id,
    chapterId: chapters[index].id,
  );
  if (content.content.trim().isEmpty) {
    throw const BookSourceProtocolException('新书源没有返回正文');
  }
  return BookSourceSwitchPlan(
    chapters,
    BookSourceReadingProgress(
      chapterId: chapters[index].id,
      chapterIndex: index,
      chapterProgress: chapterProgress.clamp(0, 1),
      updatedAt: DateTime.now().toUtc(),
    ),
    content,
  );
}

String _chapterName(String title) => title
    .replaceFirst(RegExp(r'^\s*第[\d零〇一二三四五六七八九十百千万两]+\s*[章回节话卷]\s*'), '')
    .replaceAll(RegExp(r'[\s\u3000:：、.。]'), '')
    .toLowerCase();
