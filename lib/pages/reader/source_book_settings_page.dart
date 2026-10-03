import 'package:flutter/material.dart';

import '../../book_sources/models/registered_book_source.dart';
import '../../book_sources/protocol/book_source_protocol.dart';
import '../../widgets/source_cover_image.dart';
import '../../widgets/book_update_card.dart';
import '../../book_sources/services/book_update_service.dart';

enum SourceBookSettingAction { changeSource, readingSettings }

class SourceBookSettingsPage extends StatefulWidget {
  const SourceBookSettingsPage({
    super.key,
    required this.source,
    required this.book,
    required this.chapterCount,
    required this.latestChapter,
    this.updateService,
    this.onUpdated,
  });
  final RegisteredBookSource source;
  final BookSourceBook book;
  final int chapterCount;
  final String latestChapter;
  final BookUpdateService? updateService;
  final ValueChanged<BookUpdateResult>? onUpdated;

  @override
  State<SourceBookSettingsPage> createState() => _SourceBookSettingsPageState();
}

class _SourceBookSettingsPageState extends State<SourceBookSettingsPage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('书籍设置'), centerTitle: true),
    body: _content(context),
  );

  Widget _content(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _bookCard(context),
      const SizedBox(height: 16),
      _descriptionCard(),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text('书籍功能', style: TextStyle(fontSize: 18)),
      ),
      Row(
        children: [
          Expanded(
            child: _action(
              context,
              '换源',
              Icons.swap_horiz_rounded,
              SourceBookSettingAction.changeSource,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _action(
              context,
              '阅读设置',
              Icons.tune_rounded,
              SourceBookSettingAction.readingSettings,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      BookUpdateCard(
        source: widget.source,
        book: widget.book,
        knownCount: widget.chapterCount,
        latestChapter: widget.latestChapter,
        service: widget.updateService,
        onUpdated: widget.onUpdated,
      ),
    ],
  );

  Widget _card(List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );

  Widget _descriptionCard() => _card([
    const Text(
      '内容简介',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    Text(
      widget.book.description.isEmpty ? '暂无简介' : widget.book.description,
      maxLines: _expanded ? null : 5,
      overflow: _expanded ? null : TextOverflow.ellipsis,
      style: const TextStyle(height: 1.7),
    ),
    if (widget.book.description.length > 100)
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(_expanded ? '收起' : '展开'),
        ),
      ),
  ]);

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    SourceBookSettingAction action,
  ) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('source-book-${action.name}'),
      onTap: () => Navigator.of(context).pop(action),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _actionContent(context, label, icon),
      ),
    ),
  );

  Widget _actionContent(BuildContext context, String label, IconData icon) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 18),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );

  Widget _bookCard(BuildContext context) {
    const fallback = SizedBox(
      width: 76,
      height: 108,
      child: Icon(Icons.menu_book, size: 40),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.book.coverUrl == null
                  ? fallback
                  : SourceCoverImage(
                      url: widget.book.coverUrl!,
                      fallback: fallback,
                      width: 76,
                      height: 108,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _bookMetadata(context)),
          ],
        ),
      ),
    );
  }

  Widget _bookMetadata(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.book.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(widget.book.author),
      const SizedBox(height: 12),
      Text(
        widget.source.name,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    ],
  );
}
