// 文件说明：发现页与搜索页共享的书源书籍展示组件与操作流程。
// 技术要点：Flutter UI、底部弹窗、书架服务调用。

import 'dart:async';

import 'package:flutter/material.dart';
import 'source_filter_widgets.dart';
import 'package:provider/provider.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/pages/reader/book_source_reader_page.dart';
import 'package:xxread/services/library/download_task_controller.dart';
import 'package:xxread/utils/book_open_transition.dart';
import 'package:xxread/utils/localization_extension.dart';
import 'package:xxread/utils/page_transitions.dart';
import 'package:xxread/utils/page_style_helper.dart';
import 'package:xxread/utils/ui_style.dart';
import 'package:xxread/widgets/generated_book_cover.dart';
import 'package:xxread/widgets/side_toast.dart';
import 'package:xxread/widgets/source_cover_image.dart';

/// 一本来自具体书源的书。
class SourcedBook {
  final RegisteredBookSource source;
  final BookSourceBook book;

  const SourcedBook({required this.source, required this.book});
}

BoxDecoration bookSourcePanelDecoration(
  BuildContext context, {
  double radius = 16,
  bool stronger = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final palette = PageStyleHelper.palette(context);
  final isMaterial3Style =
      Theme.of(context).extension<UiStyleThemeExtension>()?.isMaterial3Style ??
      false;
  return BoxDecoration(
    color: isMaterial3Style
        ? (stronger ? scheme.surfaceContainer : scheme.surfaceContainerLow)
        : (stronger ? palette.cardStrong : palette.card),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: scheme.outline.withValues(alpha: isMaterial3Style ? 0.22 : 0.12),
      width: 0.8,
    ),
  );
}

/// 竖版书籍卡片（封面 + 标题 + 作者），用于发现页横向书架。
class SourcedBookCard extends StatelessWidget {
  final SourcedBook result;
  final VoidCallback onTap;

  const SourcedBookCard({super.key, required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 132,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: result.book.coverUrl == null
                        ? GeneratedBookCover(
                            title: result.book.title,
                            author: result.book.author,
                          )
                        : SourceCoverImage(
                            url: result.book.coverUrl!,
                            fit: BoxFit.cover,
                            cacheWidth:
                                (132 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                            fallback: GeneratedBookCover(
                              title: result.book.title,
                              author: result.book.author,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  result.book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  result.book.author.isEmpty
                      ? result.source.name
                      : result.book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 横版书籍行（封面 + 标题 + 作者/来源 + 简介），用于搜索结果和分类列表。
class SourcedBookListTile extends StatelessWidget {
  final SourcedBook result;
  final VoidCallback onTap;
  final Widget? footer;

  const SourcedBookListTile({
    super.key,
    required this.result,
    required this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final book = result.book;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookCoverThumb(book: book),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      book.author,
                      ...book.categories,
                      if (book.status?.isNotEmpty ?? false) book.status!,
                      result.source.name,
                    ].where((item) => item.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (book.description.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      book.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (book.latestChapter?.isNotEmpty ?? false)
                    Text(
                      book.latestChapter!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  if (footer != null) ...[const SizedBox(height: 4), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCoverThumb extends StatelessWidget {
  final BookSourceBook book;
  final double width;
  final double height;

  const _BookCoverThumb({
    required this.book,
    this.width = 54,
    this.height = 76,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(
      width: width,
      height: height,
      child: GeneratedBookCover(title: book.title, author: book.author),
    );
    if (book.coverUrl == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SourceCoverImage(
        url: book.coverUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        fallback: fallback,
      ),
    );
  }
}

/// 书籍详情弹窗与加入书架/下载/阅读的完整流程。
///
/// 发现页与搜索页共用，弹窗只展示面向读者的信息。
class SourcedBookActions {
  final BuildContext context;
  final BookSourceClient client;
  final BookSourceShelfService shelfService;
  final void Function(SourcedBook book)? onFindSources;

  const SourcedBookActions({
    required this.context,
    required this.client,
    required this.shelfService,
    this.onFindSources,
  });

  void showBookDetails(SourcedBook result) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (pageContext) => Scaffold(
            key: const Key('bookSourceDetailsPage'),
            appBar: AppBar(
              backgroundColor: PageStyleHelper.palette(
                pageContext,
              ).backgroundStart,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 56,
              title: Text(
                result.source.name,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: PageStyleHelper.backgroundGradient(pageContext),
              ),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _detailsLoader(result),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsLoader(SourcedBook result) => _SourcedBookDetailsLoader(
    result: result,
    client: client,
    shelfService: shelfService,
    onFindSources: onFindSources,
    onRead: (book) =>
        _openReader(SourcedBook(source: result.source, book: book)),
    onDownloadContinuesInBackground: () {
      if (context.mounted) {
        showSideToast(context, context.l10n.downloadRunningInBackground);
      }
    },
  );

  Future<void> _openReader(SourcedBook result) async {
    if (!context.mounted) return;
    final route = BookOpenTransition.createRoute<void>(
      BookSourceReaderPage(
        source: result.source,
        book: result.book,
        client: client,
        shelfService: shelfService,
      ),
      origin: ReaderPageTransitionOrigin.discoverSheet,
      waitForReaderReady: true,
    );
    await BookOpenTransition.push<void>(context, route);
  }
}

class _SourcedBookDetailsLoader extends StatefulWidget {
  const _SourcedBookDetailsLoader({
    required this.result,
    required this.client,
    required this.shelfService,
    required this.onRead,
    required this.onDownloadContinuesInBackground,
    this.onFindSources,
  });

  final SourcedBook result;
  final BookSourceClient client;
  final BookSourceShelfService shelfService;
  final Future<void> Function(BookSourceBook book) onRead;
  final VoidCallback onDownloadContinuesInBackground;
  final void Function(SourcedBook book)? onFindSources;

  @override
  State<_SourcedBookDetailsLoader> createState() =>
      _SourcedBookDetailsLoaderState();
}

class _SourcedBookDetailsLoaderState extends State<_SourcedBookDetailsLoader> {
  late BookSourceBook _book = widget.result.book;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    try {
      final book = await widget.client.getBook(
        widget.result.source,
        widget.result.book.id,
      );
      if (mounted) setState(() => _book = book);
    } catch (_) {
      // Search/discovery summaries remain usable when detail is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = SourcedBook(source: widget.result.source, book: _book);
    return _SourcedBookDetailsSheet(
      key: ValueKey(_book.id),
      result: result,
      shelfService: widget.shelfService,
      onFindSources: widget.onFindSources == null
          ? null
          : () => widget.onFindSources!(result),
      onRead: () => widget.onRead(result.book),
      onDownloadContinuesInBackground: widget.onDownloadContinuesInBackground,
    );
  }
}

enum _BookDetailsSheetStep {
  details,
  shelfOptions,
  openingReader,
  submitting,
  added,
  alreadyAdded,
  addFailed,
  downloading,
}

class _SourcedBookDetailsSheet extends StatefulWidget {
  const _SourcedBookDetailsSheet({
    super.key,
    required this.result,
    required this.shelfService,
    required this.onRead,
    required this.onDownloadContinuesInBackground,
    this.onFindSources,
  });

  final SourcedBook result;
  final BookSourceShelfService shelfService;
  final Future<void> Function() onRead;
  final VoidCallback onDownloadContinuesInBackground;
  final VoidCallback? onFindSources;

  @override
  State<_SourcedBookDetailsSheet> createState() =>
      _SourcedBookDetailsSheetState();
}

class _SourcedBookDetailsSheetState extends State<_SourcedBookDetailsSheet> {
  _BookDetailsSheetStep _step = _BookDetailsSheetStep.details;
  Object? _addError;
  DownloadTaskController? _downloadController;
  String? _downloadTaskId;
  bool _closingScheduled = false;
  bool _closing = false;

  BookSourceBook get _book => widget.result.book;

  @override
  void dispose() {
    _downloadController?.removeListener(_handleDownloadUpdate);
    super.dispose();
  }

  Future<void> _openReader() async {
    if (_step != _BookDetailsSheetStep.details) return;
    setState(() => _step = _BookDetailsSheetStep.openingReader);
    _closing = true;
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await widget.onRead();
  }

  Future<void> _addOnline() async {
    if (_step == _BookDetailsSheetStep.submitting) return;
    setState(() {
      _step = _BookDetailsSheetStep.submitting;
      _addError = null;
    });
    try {
      final existing = await widget.shelfService.findShelfBook(
        sourceId: widget.result.source.id,
        sourceBookId: _book.id,
      );
      if (existing == null || !existing.isOnline) {
        await widget.shelfService.addOnline(
          source: widget.result.source,
          book: _book,
        );
      }
      if (!mounted) return;
      setState(() {
        _step = existing == null || !existing.isOnline
            ? _BookDetailsSheetStep.added
            : _BookDetailsSheetStep.alreadyAdded;
      });
      _scheduleClose();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _addError = error;
        _step = _BookDetailsSheetStep.addFailed;
      });
    }
  }

  void _startDownload() {
    final controller = context.read<DownloadTaskController>();
    _downloadController?.removeListener(_handleDownloadUpdate);
    final taskId = controller.enqueueBookDownload(
      source: widget.result.source,
      book: _book,
      shelfService: widget.shelfService,
    );
    _downloadController = controller..addListener(_handleDownloadUpdate);
    setState(() {
      _downloadTaskId = taskId;
      _step = _BookDetailsSheetStep.downloading;
    });
  }

  void _handleDownloadUpdate() {
    if (!mounted) return;
    final task = _downloadController?.taskById(_downloadTaskId ?? '');
    setState(() {});
    if (!_closing && task?.state == DownloadTaskState.completed) {
      _scheduleClose();
    }
  }

  void _scheduleClose() {
    if (_closingScheduled) return;
    _closingScheduled = true;
    _closing = true;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 550), () {
        if (mounted) Navigator.of(context).pop();
      }),
    );
  }

  void _continueDownloadInBackground() {
    _closing = true;
    Navigator.of(context).pop();
    widget.onDownloadContinuesInBackground();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final authorAndSource = [
      _book.author,
      widget.result.source.name,
    ].where((item) => item.isNotEmpty).join(' · ');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBookHeader(context, authorAndSource),
            const SizedBox(height: 20),
            Expanded(
              child: AnimatedSize(
                key: const Key('bookSourceSheetAnimatedSize'),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                reverseDuration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  reverseDuration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) =>
                      currentChild ?? const SizedBox.shrink(),
                  transitionBuilder: (child, animation) {
                    final position = Tween<Offset>(
                      begin: reduceMotion
                          ? Offset.zero
                          : const Offset(0, 0.035),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: position, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStep(context, reduceMotion),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookHeader(BuildContext context, String authorAndSource) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _BookCoverThumb(book: _book, width: 64, height: 90),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _book.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              authorAndSource,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (_book.categories.isNotEmpty ||
                (_book.status?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    ..._book.categories,
                    if (_book.status != null) _book.status!,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _buildStep(BuildContext context, bool reduceMotion) {
    return switch (_step) {
      _BookDetailsSheetStep.details => _buildDetails(context),
      _BookDetailsSheetStep.shelfOptions => _buildShelfOptions(context),
      _BookDetailsSheetStep.openingReader => _buildSubmitting(
        context,
        key: const Key('bookSourceReaderOpening'),
        message: context.l10n.reading,
      ),
      _BookDetailsSheetStep.submitting => _buildSubmitting(
        context,
        key: const Key('bookSourceActionSubmitting'),
        message: context.l10n.bookSourceAddToShelf,
      ),
      _BookDetailsSheetStep.added => _ShelfCompletionView(
        book: _book,
        reduceMotion: reduceMotion,
        message: context.l10n.bookSourceAddedOnline,
      ),
      _BookDetailsSheetStep.alreadyAdded => _ShelfCompletionView(
        book: _book,
        reduceMotion: true,
        alreadyAdded: true,
        message: context.l10n.bookSourceAlreadyOnShelf,
      ),
      _BookDetailsSheetStep.addFailed => _buildAddFailed(context),
      _BookDetailsSheetStep.downloading => _buildDownload(context),
    };
  }

  Widget _buildDetails(BuildContext context) {
    return Column(
      key: const Key('bookSourceDetailsContent'),
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const Key('bookSourceDetailsScroll'),
            child: _buildDescription(context),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 13),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  key: const Key('bookSourceAddToShelfButton'),
                  onPressed: () => setState(
                    () => _step = _BookDetailsSheetStep.shelfOptions,
                  ),
                  icon: const Icon(Icons.add_to_photos_outlined),
                  label: Text(context.l10n.bookSourceAddToShelf),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 42,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 13),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  key: const Key('bookSourceReadButton'),
                  onPressed: _openReader,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(context.l10n.reading),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('简介', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        _book.description.isEmpty ? '暂无简介' : _book.description,
        style: const TextStyle(height: 1.6),
      ),
      const SizedBox(height: 24),
      Text('站点', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('当前使用：${widget.result.source.name}'),
      if (widget.onFindSources != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: sourceTextActionStyle(context),
            key: const Key('bookSourceFindOtherSources'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onFindSources!();
            },
            child: const Text('查找其他书源'),
          ),
        ),
      if (_book.latestChapter?.isNotEmpty ?? false) ...[
        const SizedBox(height: 16),
        Text('最新章节', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_book.latestChapter!),
      ],
    ],
  );

  Widget _buildShelfOptions(BuildContext context) {
    return Column(
      key: const Key('bookSourceShelfOptions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const Key('bookSourceAddOnlineOption'),
          leading: const Icon(Icons.cloud_outlined),
          title: Text(context.l10n.bookSourceAddOnline),
          subtitle: Text(context.l10n.bookSourceAddOnlineHint),
          onTap: _addOnline,
        ),
        ListTile(
          key: const Key('bookSourceDownloadLocalOption'),
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text(context.l10n.bookSourceDownloadLocal),
          subtitle: Text(context.l10n.bookSourceDownloadLocalHint),
          onTap: _startDownload,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _step = _BookDetailsSheetStep.details),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(context.l10n.back),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitting(
    BuildContext context, {
    required Key key,
    required String message,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }

  Widget _buildAddFailed(BuildContext context) {
    return Padding(
      key: const Key('bookSourceAddFailed'),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 38,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            '$_addError',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                style: sourceTextActionStyle(context),
                onPressed: () =>
                    setState(() => _step = _BookDetailsSheetStep.shelfOptions),
                child: Text(context.l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('bookSourceAddRetryButton'),
                onPressed: _addOnline,
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownload(BuildContext context) {
    final task = _downloadController?.taskById(_downloadTaskId ?? '');
    final state = task?.state;
    final status = switch (state) {
      DownloadTaskState.queued => context.l10n.downloadTaskQueued,
      DownloadTaskState.downloading => context.l10n.downloadTaskDownloading,
      DownloadTaskState.completed => context.l10n.bookSourceDownloadComplete,
      DownloadTaskState.failed => context.l10n.bookSourceDownloadFailed(
        '${task?.error ?? ''}',
      ),
      DownloadTaskState.cancelled => context.l10n.downloadTaskCancelled,
      null => context.l10n.downloadTaskFailed,
    };
    final active =
        state == DownloadTaskState.queued ||
        state == DownloadTaskState.downloading;

    return Padding(
      key: const Key('bookSourceDownloadInline'),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state == DownloadTaskState.completed)
            const Icon(Icons.check_circle_rounded, size: 42)
          else
            LinearProgressIndicator(
              value: state == DownloadTaskState.failed ? 0 : task?.progress,
            ),
          const SizedBox(height: 14),
          Text(status, textAlign: TextAlign.center),
          if (task != null && task.total > 0) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.bookSourceDownloadProgress(
                task.completed,
                task.total,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          if (active)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: sourceTextActionStyle(context),
                    onPressed: () =>
                        _downloadController?.cancelTask(_downloadTaskId ?? ''),
                    child: Text(context.l10n.downloadTaskCancel),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    key: const Key('bookSourceDownloadBackgroundButton'),
                    onPressed: _continueDownloadInBackground,
                    child: Text(context.l10n.downloadContinueInBackground),
                  ),
                ),
              ],
            )
          else if (state == DownloadTaskState.failed)
            FilledButton(
              onPressed: _startDownload,
              child: Text(context.l10n.retry),
            )
          else if (state == DownloadTaskState.cancelled)
            TextButton(
              style: sourceTextActionStyle(context),
              onPressed: () =>
                  setState(() => _step = _BookDetailsSheetStep.shelfOptions),
              child: Text(context.l10n.back),
            ),
        ],
      ),
    );
  }
}

class _ShelfCompletionView extends StatelessWidget {
  const _ShelfCompletionView({
    required this.book,
    required this.reduceMotion,
    required this.message,
    this.alreadyAdded = false,
  });

  final BookSourceBook book;
  final bool reduceMotion;
  final String message;
  final bool alreadyAdded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key(
        alreadyAdded
            ? 'bookSourceAlreadyAddedCompletion'
            : 'bookSourceAddedCompletion',
      ),
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alreadyAdded)
            Icon(
              Icons.info_outline_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            )
          else
            _BookDropsOntoShelf(book: book, animate: !reduceMotion),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BookDropsOntoShelf extends StatelessWidget {
  const _BookDropsOntoShelf({required this.book, required this.animate});

  final BookSourceBook book;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: const Key('bookSourceShelfDropAnimation'),
      tween: Tween(begin: 0, end: 1),
      duration: animate ? const Duration(milliseconds: 320) : Duration.zero,
      curve: Curves.easeOutBack,
      builder: (context, value, child) => SizedBox(
        width: 86,
        height: 92,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 0,
              child: Transform.translate(
                offset: Offset(0, value * 11),
                child: child,
              ),
            ),
            Positioned(
              left: 4,
              right: 4,
              bottom: 3,
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withValues(alpha: 0.18),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      child: _BookCoverThumb(book: book),
    );
  }
}
