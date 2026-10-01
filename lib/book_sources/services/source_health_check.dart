import '../models/registered_book_source.dart';
import 'book_download_cancellation.dart';
import 'book_source_client.dart';
import 'source_task_pool.dart';

enum SourceHealthStage { search, detail, catalog, content }

class SourceHealthResult {
  const SourceHealthResult(
    this.sourceId,
    this.stage,
    this.message,
    this.elapsed, {
    this.succeeded = false,
  });
  final String sourceId;
  final SourceHealthStage stage;
  final String message;
  final Duration elapsed;
  final bool succeeded;
  String get label => '$message · ${elapsed.inMilliseconds} ms';
}

/// Diagnostics never remove a source or change its enabled state.
class SourceHealthCheck {
  SourceHealthCheck(this.client);
  final BookSourceClient client;

  Future<void> run(
    Iterable<RegisteredBookSource> sources,
    String query, {
    required BookDownloadCancellation cancellation,
    required void Function(SourceHealthResult) onResult,
    bool fullChain = false,
  }) async {
    if (query.trim().isEmpty) throw const FormatException('请输入用于检测的书名');
    final pool = SourceTaskPool(limit: 8);
    await Future.wait(
      sources.map(
        (source) => pool
            .run(
              source.apiBaseUrl.host,
              () => SourceTaskContext.run(cancellation, () async {
                final result = await _check(source, query, fullChain);
                if (!cancellation.isCancelled) onResult(result);
              }),
              cancellation: cancellation,
            )
            .onError((_, _) {}),
      ),
    );
  }

  Future<SourceHealthResult> _check(
    RegisteredBookSource source,
    String query,
    bool fullChain,
  ) async {
    final timer = Stopwatch()..start();
    var stage = SourceHealthStage.search;
    try {
      final page = await client.search(source, query);
      if (page.items.isEmpty) {
        return SourceHealthResult(source.id, stage, '搜索无结果', timer.elapsed);
      }
      if (!fullChain) {
        return SourceHealthResult(
          source.id,
          stage,
          '可搜索',
          timer.elapsed,
          succeeded: true,
        );
      }
      stage = SourceHealthStage.detail;
      final book = await client.getBook(source, page.items.first.id);
      stage = SourceHealthStage.catalog;
      final chapters = await client.getChapters(source, book.id);
      if (chapters.isEmpty) {
        return SourceHealthResult(source.id, stage, '目录为空', timer.elapsed);
      }
      stage = SourceHealthStage.content;
      final content = await client.getChapterContent(
        source,
        bookId: book.id,
        chapterId: chapters.first.id,
      );
      if (content.content.trim().isEmpty) {
        return SourceHealthResult(source.id, stage, '正文为空', timer.elapsed);
      }
      return SourceHealthResult(
        source.id,
        stage,
        '阅读链已返回内容（需抽查正文）',
        timer.elapsed,
        succeeded: true,
      );
    } catch (_) {
      SourceTaskContext.cancellation?.throwIfCancelled();
      // Avoid surfacing request URLs, embedded credentials or script bodies.
      return SourceHealthResult(
        source.id,
        stage,
        '${stage.name} 阶段失败',
        timer.elapsed,
      );
    }
  }
}
