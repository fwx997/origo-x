import 'package:flutter/material.dart';

import '../book_sources/models/registered_book_source.dart';
import '../book_sources/protocol/book_source_protocol.dart';
import '../book_sources/services/book_update_service.dart';
import '../book_sources/services/book_source_link_service.dart';
import '../book_sources/services/book_source_shelf_service.dart';
import '../models/book.dart';

class ShelfBookUpdateCard extends StatefulWidget {
  const ShelfBookUpdateCard({
    super.key,
    required this.book,
    this.autoCheck = false,
  });
  final Book book;
  final bool autoCheck;

  @override
  State<ShelfBookUpdateCard> createState() => _ShelfBookUpdateCardState();
}

class _ShelfBookUpdateCardState extends State<ShelfBookUpdateCard> {
  late final Future<Book?> _target = _resolve();

  Future<Book?> _resolve() async {
    if (widget.book.sourceJson != null && widget.book.sourceBookJson != null)
      return widget.book;
    final candidates = await BookSourceLinkService().candidates(widget.book);
    return candidates.where((book) => book.isOnline).firstOrNull;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Book?>(
    future: _target,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const LinearProgressIndicator();
      final book = snapshot.data;
      if (book == null)
        return Text(
          snapshot.hasError ? '无法读取关联来源，请稍后重试' : '本地书暂无在线来源，可通过“换源”关联后检查更新',
        );
      final shelf = BookSourceShelfService();
      final source = shelf.sourceFrom(book);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '检查来源：${source.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          BookUpdateCard(
            source: source,
            book: shelf.sourceBookFrom(book),
            autoCheck: widget.autoCheck,
            knownCount: book.isOnline
                ? book.totalPages ~/ BookSourceShelfService.unitsPerChapter
                : 0,
            latestChapter: shelf.sourceBookFrom(book).latestChapter ?? '',
          ),
        ],
      );
    },
  );
}

class BookUpdateCard extends StatefulWidget {
  const BookUpdateCard({
    super.key,
    required this.source,
    required this.book,
    this.knownCount = 0,
    this.latestChapter = '',
    this.service,
    this.onUpdated,
    this.autoCheck = false,
  });
  final RegisteredBookSource source;
  final BookSourceBook book;
  final int knownCount;
  final String latestChapter;
  final BookUpdateService? service;
  final ValueChanged<BookUpdateResult>? onUpdated;
  final bool autoCheck;

  @override
  State<BookUpdateCard> createState() => _BookUpdateCardState();
}

class _BookUpdateCardState extends State<BookUpdateCard> {
  late final _service = widget.service ?? BookUpdateService();
  BookUpdateSnapshot? _snapshot;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.autoCheck) _check();
  }

  Future<void> _load() async {
    final snapshot = await _service.load(widget.source, widget.book);
    if (mounted && !_busy && _snapshot == null)
      setState(() => _snapshot = snapshot);
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.check(
        widget.source,
        widget.book,
        knownCount: widget.knownCount,
      );
      if (!mounted) return;
      setState(() => _snapshot = result.snapshot);
      widget.onUpdated?.call(result);
    } catch (error) {
      if (mounted) setState(() => _error = '检查失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(padding: const EdgeInsets.all(20), child: _content(context)),
  );

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final latest = snapshot?.latestChapter ?? widget.latestChapter;
    final count = snapshot?.count ?? widget.knownCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, count),
        const SizedBox(height: 20),
        Text(
          snapshot == null
              ? '尚未检查更新'
              : snapshot.added > 0
              ? '发现 ${snapshot.added} 个新章节'
              : '目录已是最新',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (latest.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '最新章节：$latest',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
        const SizedBox(height: 16),
        _metadata(
          context,
          Icons.schedule_rounded,
          snapshot?.updatedAt == null
              ? '更新时间暂无记录'
              : '更新于 ${_time(snapshot!.updatedAt!)}',
        ),
        if (snapshot != null) ...[
          const SizedBox(height: 6),
          _metadata(
            context,
            Icons.history_rounded,
            '上次检查于 ${_time(snapshot.checkedAt)}',
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: _busy ? null : _check,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
            label: Text(_busy ? '正在检查…' : '检查更新'),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.update_rounded,
            color: theme.colorScheme.onPrimaryContainer,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '书籍更新',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (count > 0)
          Text(
            '共 $count 章',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _metadata(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
