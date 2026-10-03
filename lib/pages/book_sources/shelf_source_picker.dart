import 'dart:convert';
import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../../book_sources/models/registered_book_source.dart';
import '../../book_sources/protocol/book_source_protocol.dart';
import '../../book_sources/services/book_source_client.dart';
import '../../book_sources/services/book_source_link_service.dart';
import '../../book_sources/services/book_source_registry.dart';
import '../../book_sources/services/book_source_shelf_service.dart';
import 'source_search_page.dart';
import 'widgets/sourced_book_widgets.dart';

class ShelfSourceChoice {
  const ShelfSourceChoice.online(this.online) : local = null;
  const ShelfSourceChoice.local(this.local) : online = null;
  final SourcedBook? online;
  final Book? local;
}

Future<ShelfSourceChoice?> showShelfSourcePicker(
  BuildContext context, {
  required Book anchor,
  required BookSourceClient client,
  required BookSourceShelfService shelfService,
  SourcedBook? reference,
  BookSourceLinkService? linkService,
}) async {
  final sources = await BookSourceRegistry().load();
  if (!context.mounted) return null;
  return Navigator.of(context).push<ShelfSourceChoice>(
    MaterialPageRoute(
      builder: (_) => _ShelfSourcePicker(
        anchor: anchor,
        client: client,
        shelfService: shelfService,
        sources: sources,
        reference: reference,
        linkService: linkService,
      ),
    ),
  );
}

class _ShelfSourcePicker extends StatefulWidget {
  const _ShelfSourcePicker({
    required this.anchor,
    required this.client,
    required this.shelfService,
    required this.sources,
    this.reference,
    this.linkService,
  });
  final Book anchor;
  final BookSourceClient client;
  final BookSourceShelfService shelfService;
  final List<RegisteredBookSource> sources;
  final SourcedBook? reference;
  final BookSourceLinkService? linkService;

  @override
  State<_ShelfSourcePicker> createState() => _ShelfSourcePickerState();
}

class _ShelfSourcePickerState extends State<_ShelfSourcePicker> {
  late final _links = widget.linkService ?? BookSourceLinkService();
  List<Book> _candidates = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final candidates = await _links.candidates(widget.anchor);
      if (mounted)
        setState(() {
          _candidates = candidates;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = '本地来源加载失败，可继续搜索在线来源');
    }
  }

  SourcedBook? _reference() {
    if (widget.reference != null) return widget.reference;
    final anchor = widget.anchor;
    final source = anchor.sourceJson == null
        ? widget.sources.firstOrNull
        : RegisteredBookSource.fromJson(
            jsonDecode(anchor.sourceJson!) as Map<String, dynamic>,
          );
    if (source == null) return null;
    return SourcedBook(
      source: source,
      book: BookSourceBook(
        id: anchor.sourceBookId ?? 'local',
        title: anchor.title,
        author: anchor.author,
        description: '',
        categories: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SourceSearchPage(
    sources: widget.sources,
    client: widget.client,
    shelfService: widget.shelfService,
    initialBook: _reference(),
    additionalSources: _localSources(),
    onBookSelected: (book) =>
        Navigator.of(context).pop(ShelfSourceChoice.online(book)),
  );

  Widget _localSources() => Card(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.folder_copy_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('本地及已关联来源'),
                subtitle: Text('${_candidates.length} 个来源'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _candidates.isEmpty ? null : _chooseCandidate,
              ),
            ),
            IconButton(
              tooltip: '关联本地书',
              onPressed: _linkLocal,
              icon: const Icon(Icons.add_link_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ),
  );

  Future<Book?> _choose(List<Book> books, String title) =>
      showModalBottomSheet<Book>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: _candidateList(context, books, title),
          ),
        ),
      );

  Widget _candidateList(BuildContext context, List<Book> books, String title) =>
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (books.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('请先导入本地书籍')),
          Expanded(
            child: ListView.builder(
              itemCount: books.length,
              itemBuilder: (context, index) =>
                  _candidateTile(context, books[index]),
            ),
          ),
        ],
      );

  Widget _candidateTile(BuildContext context, Book book) => ListTile(
    leading: Icon(book.isOnline ? Icons.cloud_outlined : Icons.folder_outlined),
    title: Text(book.title),
    subtitle: Text(
      '${book.author} · ${book.isOnline ? '在线来源' : '本地 ${book.format.toUpperCase()}'}',
    ),
    onTap: () => Navigator.of(context).pop(book),
  );

  Future<void> _chooseCandidate() async {
    final selected = await _choose(_candidates, '选择来源');
    if (selected == null || !mounted) return;
    if (widget.anchor.id != null && selected.id != null) {
      await _links.link(widget.anchor.id!, selected.id!);
    }
    if (!mounted) return;
    final choice = selected.isOnline
        ? ShelfSourceChoice.online(
            SourcedBook(
              source: widget.shelfService.sourceFrom(selected),
              book: widget.shelfService.sourceBookFrom(selected),
            ),
          )
        : ShelfSourceChoice.local(selected);
    Navigator.of(context).pop(choice);
  }

  Future<void> _linkLocal() async {
    try {
      final books = (await _links.localBooks())
          .where((b) => b.id != widget.anchor.id)
          .toList();
      if (!mounted) return;
      final selected = await _choose(books, '选择要关联的本地书（书名和作者可以不同）');
      if (selected?.id == null || !mounted) return;
      if (widget.anchor.id == null) {
        setState(() => _error = '请先将当前在线书加入书架，再保存来源关联');
        return;
      }
      await _links.link(widget.anchor.id!, selected!.id!);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '关联失败：$error');
    }
  }
}
