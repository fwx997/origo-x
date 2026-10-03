import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../../services/books/book_dao.dart';
import '../../book_sources/services/book_source_client.dart';
import '../../book_sources/services/book_source_link_service.dart';
import '../../book_sources/services/book_source_shelf_service.dart';
import '../../book_sources/services/book_source_switch.dart';
import '../../book_sources/services/book_source_reading_progress.dart';
import '../reader/book_source_reader_page.dart';
import '../reader/native_reader_page.dart';
import 'shelf_source_picker.dart';

class PreparedShelfSource {
  const PreparedShelfSource(this.book, this.reader);
  final Book book;
  final Widget reader;
}

Future<PreparedShelfSource> prepareShelfSourceChoice({
  required Book anchor,
  required ShelfSourceChoice choice,
  required BookSourceClient client,
  required BookSourceShelfService shelfService,
  String chapterTitle = '',
  int? chapterIndex,
  double? chapterProgress,
  BookDao? bookDao,
}) async {
  final dao = bookDao ?? BookDao();
  final local = choice.local;
  if (local != null) {
    if (!BookSourceLinkService.canUseLocalSource(local)) {
      throw StateError('请选择 TXT、EPUB 等文字书籍作为本地来源');
    }
    final full = local.id == null ? local : await dao.getBookById(local.id!);
    if (full == null || (!kIsWeb && !await File(full.filePath).exists())) {
      throw StateError('本地书文件不存在，请重新导入');
    }
    if (anchor.id != null && full.id != null)
      await BookSourceLinkService().link(anchor.id!, full.id!);
    return PreparedShelfSource(full, NativeReaderPage(book: full));
  }
  final online = choice.online!;
  final index =
      chapterIndex ??
      (anchor.isOnline
          ? anchor.currentPage ~/ BookSourceShelfService.unitsPerChapter
          : anchor.currentPage);
  final fraction =
      chapterProgress ??
      (anchor.isOnline
          ? (anchor.currentPage % BookSourceShelfService.unitsPerChapter) /
                BookSourceShelfService.unitsPerChapter
          : anchor.toCanonicalLocator()?.progression ?? 0);
  final plan = await prepareBookSourceSwitch(
    client: client,
    source: online.source,
    book: online.book,
    chapterTitle: chapterTitle,
    chapterIndex: index,
    chapterProgress: fraction,
  );
  Book target;
  if (anchor.isOnline && anchor.id != null) {
    await shelfService.replaceOnlineSource(
      shelfBookId: anchor.id!,
      source: online.source,
      book: online.book,
      chapterIndex: plan.progress.chapterIndex,
      chapterCount: plan.chapters.length,
      chapterProgress: plan.progress.chapterProgress,
    );
    target = (await dao.getBookById(anchor.id!))!;
  } else {
    target = await shelfService.addOnline(
      source: online.source,
      book: online.book,
    );
    if (anchor.id != null && target.id != null)
      await BookSourceLinkService().link(anchor.id!, target.id!);
    await shelfService.updateShelfProgress(
      shelfBookId: target.id!,
      chapterIndex: plan.progress.chapterIndex,
      chapterCount: plan.chapters.length,
      chapterProgress: plan.progress.chapterProgress,
    );
  }
  await const BookSourceReadingProgressStore().save(
    sourceId: online.source.id,
    bookId: online.book.id,
    progress: plan.progress,
  );
  return PreparedShelfSource(
    target,
    BookSourceReaderPage(
      source: online.source,
      book: online.book,
      client: client,
      shelfService: shelfService,
      initialSwitch: plan,
    ),
  );
}
