// 文件说明：跨书源聚合搜索页，由发现页右上角搜索按钮进入。
// 技术要点：Flutter UI、并发书源请求、按源分页加载更多。

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/models/book_search_filter.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_download_cancellation.dart';
import 'package:xxread/book_sources/services/source_task_pool.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/utils/localization_extension.dart';
import 'package:xxread/utils/page_style_helper.dart';

import 'widgets/sourced_book_widgets.dart';
import 'widgets/source_filter_widgets.dart';
import 'widgets/source_picker.dart';

/// 跨已启用书源的聚合搜索页。
///
/// 搜索范围与分页状态都在本页内维护；发现页只负责展示书籍。
class SourceSearchPage extends StatefulWidget {
  final List<RegisteredBookSource> sources;
  final BookSourceClient client;
  final BookSourceShelfService shelfService;
  final SourcedBook? initialBook;
  final String? initialSourceId;

  const SourceSearchPage({
    super.key,
    required this.sources,
    required this.client,
    required this.shelfService,
    this.initialBook,
    this.initialSourceId,
  });

  /// 解析实际参与搜索的书源集合；发现页与测试也复用这份规则。
  static List<RegisteredBookSource> searchTargets(
    Iterable<RegisteredBookSource> sources,
    String? selectedSourceId,
  ) {
    final enabled = sources.where((source) => source.enabled);
    if (selectedSourceId == null) return enabled.toList(growable: false);
    return enabled
        .where((source) => source.id == selectedSourceId)
        .toList(growable: false);
  }

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final SourcedBookActions _actions = SourcedBookActions(
    context: context,
    client: widget.client,
    shelfService: widget.shelfService,
    onFindSources: _findSources,
  );

  String? _selectedSourceId;
  static const _historyKey = 'source_search_history_v1';
  List<String> _history = const [];
  Future<void> _historyWrites = Future<void>.value();
  bool _historyEdited = false;
  List<SourcedBook> _results = const [];
  BookSearchField _field = BookSearchField.any;
  BookSearchMatch _match = BookSearchMatch.all;
  SourcedBook? _reference;
  Map<String, _SearchPageState> _pageStates = const {};
  bool _searching = false;
  bool _hasSearched = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  int _failedSourceCount = 0;
  String _activeQuery = '';
  int _searchGeneration = 0;
  BookDownloadCancellation _cancellation = BookDownloadCancellation();
  SourceTaskPool _searchPool = SourceTaskPool(perHost: 12);
  int _completedSources = 0;
  int _totalSources = 0;

  bool get _hasMore => _pageStates.values.any((state) => state.hasMore);

  @override
  void initState() {
    super.initState();
    _reference = widget.initialBook;
    _selectedSourceId =
        widget.sources.any(
          (source) => source.enabled && source.id == widget.initialSourceId,
        )
        ? widget.initialSourceId
        : null;
    unawaited(_loadHistory());
    _queryController.text = _reference?.book.title ?? '';
    _scrollController.addListener(_handleScroll);
    // 进入搜索页直接聚焦输入框，用户可立即输入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reference != null) {
        unawaited(_search());
      } else {
        _queryFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _cancellation.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_loadMoreFailed ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 600) {
      return;
    }
    unawaited(_loadMore());
  }

  List<RegisteredBookSource> get _targets =>
      SourceSearchPage.searchTargets(widget.sources, _selectedSourceId);

  Future<void> _search() async {
    final query = _queryController.text.trim();
    final targetSources = _targets;
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    if (targetSources.isEmpty) {
      _cancellation.cancel();
      _searchGeneration++;
      if (_searching && mounted) setState(() => _searching = false);
      return;
    }
    _rememberQuery(query);
    final generation = ++_searchGeneration;
    _cancellation.cancel();
    final cancellation = _cancellation = BookDownloadCancellation();
    // Network requests still share the application-wide per-host budget.
    // A cancelled query must not keep the next query behind its parsing work.
    final pool = _searchPool = SourceTaskPool(perHost: 12);

    FocusScope.of(context).unfocus();
    setState(() {
      if (BookSearchFilter.normalize(query) !=
          BookSearchFilter.normalize(_reference?.book.title ?? '')) {
        _reference = null;
      }
      _searching = true;
      _hasSearched = true;
      _failedSourceCount = 0;
      _completedSources = 0;
      _totalSources = targetSources.length;
      _activeQuery = query;
      _results = const [];
      _pageStates = const {};
      _loadingMore = false;
      _loadMoreFailed = false;
    });

    await Future.wait(
      targetSources.map(
        (source) => _scheduleSearch(
          pool,
          cancellation,
          source,
          query,
          1,
          generation,
          initial: true,
        ),
      ),
    );

    if (!mounted || generation != _searchGeneration) return;
    setState(() => _searching = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  Future<void> _loadMore() async {
    if (_searching || _loadingMore || !_hasSearched || _activeQuery.isEmpty) {
      return;
    }
    final targets = _pageStates.values
        .where((state) => state.hasMore)
        .toList(growable: false);
    if (targets.isEmpty) return;

    final query = _activeQuery;
    final generation = _searchGeneration;
    if (_cancellation.isCancelled) _cancellation = BookDownloadCancellation();
    final cancellation = _cancellation;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });

    await Future.wait(
      targets.map(
        (state) => _scheduleSearch(
          _searchPool,
          cancellation,
          state.source,
          query,
          state.page + 1,
          generation,
          initial: false,
        ),
      ),
    );

    if (!mounted || generation != _searchGeneration || query != _activeQuery) {
      return;
    }
    setState(() => _loadingMore = false);
  }

  Future<void> _scheduleSearch(
    SourceTaskPool pool,
    BookDownloadCancellation cancellation,
    RegisteredBookSource source,
    String query,
    int page,
    int generation, {
    required bool initial,
  }) => pool
      .run(source.apiBaseUrl.host, () async {
        final batch = await _fetchBatch(source, query, page, cancellation);
        _acceptBatch(batch, generation, initial: initial);
      }, cancellation: cancellation)
      .onError((_, _) {});

  Future<_SearchBatch> _fetchBatch(
    RegisteredBookSource source,
    String query,
    int pageNumber,
    BookDownloadCancellation cancellation,
  ) async {
    try {
      final page = await SourceTaskContext.run(
        cancellation,
        () => widget.client.search(source, query, page: pageNumber),
      );
      return _SearchBatch(
        source: source,
        items: page.items
            .map((book) => SourcedBook(source: source, book: book))
            .toList(),
        page: pageNumber,
        hasMore: page.hasMore && page.items.isNotEmpty,
      );
    } catch (_) {
      return _SearchBatch(source: source, items: const [], failed: true);
    }
  }

  void _acceptBatch(
    _SearchBatch batch,
    int generation, {
    required bool initial,
  }) {
    if (!mounted ||
        generation != _searchGeneration ||
        _cancellation.isCancelled) {
      return;
    }
    setState(() {
      if (initial) _completedSources++;
      if (batch.failed) {
        if (initial) _failedSourceCount++;
        if (!initial) _loadMoreFailed = true;
        return;
      }
      final seen = _results
          .map((item) => '${item.source.id}\n${item.book.id}')
          .toSet();
      final added = batch.items
          .where((item) => seen.add('${item.source.id}\n${item.book.id}'))
          .toList(growable: false);
      _results = [..._results, ...added];
      _pageStates = {
        ..._pageStates,
        batch.source.id: _SearchPageState(
          source: batch.source,
          page: batch.page,
          hasMore: batch.hasMore && added.isNotEmpty,
        ),
      };
    });
  }

  void _stopSearch() {
    _cancellation.cancel();
    _searchGeneration++;
    setState(() {
      _searching = false;
      _loadingMore = false;
    });
  }

  void _clearSearch() {
    _cancellation.cancel();
    _searchGeneration++;
    _queryController.clear();
    setState(() {
      _reference = null;
      _results = const [];
      _pageStates = const {};
      _hasSearched = false;
      _failedSourceCount = 0;
      _activeQuery = '';
      _searching = false;
      _loadingMore = false;
      _loadMoreFailed = false;
    });
    _queryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final enabledSources = widget.sources
        .where((source) => source.enabled)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PageStyleHelper.palette(context).backgroundStart,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight:
            60 + (MediaQuery.textScalerOf(context).scale(15) - 15) * 1.5,
        leadingWidth: 48,
        titleSpacing: 0,
        title: _buildQueryField(enabledSources),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: PageStyleHelper.backgroundGradient(context),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (enabledSources.isNotEmpty) _buildScopeChips(enabledSources),
              _buildSearchOptions(),
              if (_searching || _loadingMore)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SourceLoadingStatus(
                    label: _searching
                        ? '已搜索 $_completedSources / $_totalSources 个书源'
                        : '正在加载更多结果',
                    value: _searching && _totalSources > 0
                        ? _completedSources / _totalSources
                        : null,
                    onStop: _stopSearch,
                  ),
                ),
              Expanded(child: _buildBody(enabledSources)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueryField(List<RegisteredBookSource> enabledSources) {
    final canSearch = enabledSources.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: TextField(
        key: const Key('bookSourceQueryControl'),
        controller: _queryController,
        focusNode: _queryFocus,
        enabled: canSearch,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 34,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          hintText: _selectedSourceId == null
              ? '搜索全部站点'
              : '搜索 ${_scopeLabel()}',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _queryController.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('bookSourceSearchClearButton'),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).deleteButtonTooltip,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: _clearSearch,
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildScopeChips(List<RegisteredBookSource> enabledSources) {
    return Padding(
      key: const Key('bookSourceScopeControl'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '搜索范围 · ${_scopeLabel()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            style: sourceTextActionStyle(context),
            key: const Key('bookSourceSearchSwitch'),
            onPressed: () async {
              _queryFocus.unfocus();
              final selected = await showSourcePicker(
                context,
                sources: enabledSources,
                selectedId: _selectedSourceId,
              );
              if (mounted && selected != null) _changeScope(selected.id);
            },
            child: const Text('切换'),
          ),
        ],
      ),
    );
  }

  void _changeScope(String? sourceId) {
    if (_selectedSourceId == sourceId) return;
    _searchGeneration++;
    setState(() {
      _selectedSourceId = sourceId;
      if (_hasSearched) {
        _searching = true;
        _results = const [];
        _pageStates = const {};
      }
    });
    if (_hasSearched && _activeQuery.isNotEmpty) {
      _queryController.text = _activeQuery;
      unawaited(_search());
    }
  }

  Widget _buildBody(List<RegisteredBookSource> enabledSources) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groupResults();
    if (enabledSources.isEmpty) {
      return _buildMessage(
        icon: Icons.travel_explore_outlined,
        title: context.l10n.bookSourcesNoSourcesTitle,
        message: context.l10n.bookSourcesNoSourcesDescription,
      );
    }
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasSearched) {
      return _buildHistory();
    }
    if (groups.isEmpty && !_hasMore && !_loadingMore) {
      return _buildMessage(
        icon: Icons.search_off_rounded,
        title: context.l10n.bookSourcesNoResults,
        message: _failedSourceCount > 0
            ? context.l10n.bookSourcesFailedCount(_failedSourceCount)
            : '',
      );
    }
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.l10n.bookSourcesSearch}'
                    ' · ${_scopeLabel()} · ${groups.length} 本书',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_failedSourceCount > 0)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                context.l10n.bookSourcesFailedCount(_failedSourceCount),
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          sliver: SliverList.separated(
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              final group = groups[index];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1048),
                  child: _buildBookGroup(group),
                ),
              );
            },
          ),
        ),
        if (groups.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('当前结果没有匹配的书籍，可调整过滤方式或继续加载。'),
            ),
          ),
        if (_hasMore || _loadingMore || _loadMoreFailed)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : OutlinedButton.icon(
                        key: const Key('bookSourceLoadMoreButton'),
                        onPressed: _loadMore,
                        icon: Icon(
                          _loadMoreFailed
                              ? Icons.refresh_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text(
                          _loadMoreFailed
                              ? context.l10n.retry
                              : context.l10n.bookSourcesLoadMore,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  String _scopeLabel() {
    for (final source in widget.sources) {
      if (source.id == _selectedSourceId) return source.name;
    }
    return context.l10n.statsRangeAll;
  }

  void _findSources(SourcedBook book) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourceSearchPage(
          sources: widget.sources,
          client: widget.client,
          shelfService: widget.shelfService,
          initialBook: book,
        ),
      ),
    );
  }

  Widget _buildSearchOptions() {
    final content = _reference != null
        ? _buildReferenceBanner(_reference!)
        : SourceFilterGrid(
            children: [
              SourceFilterControl<BookSearchField>(
                controlKey: const Key('bookSearchField'),
                label: '匹配字段',
                value: _field,
                items: const [
                  DropdownMenuItem(
                    value: BookSearchField.any,
                    child: Text('书名或作者'),
                  ),
                  DropdownMenuItem(
                    value: BookSearchField.title,
                    child: Text('书名'),
                  ),
                  DropdownMenuItem(
                    value: BookSearchField.author,
                    child: Text('作者'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _field = value!;
                  if (_match == BookSearchMatch.all) {
                    _match = BookSearchMatch.contains;
                  }
                }),
              ),
              SourceFilterControl<BookSearchMatch>(
                controlKey: const Key('bookSearchMatch'),
                label: '匹配方式',
                value: _match,
                items: const [
                  DropdownMenuItem(
                    value: BookSearchMatch.all,
                    child: Text('不过滤'),
                  ),
                  DropdownMenuItem(
                    value: BookSearchMatch.exact,
                    child: Text('精确匹配'),
                  ),
                  DropdownMenuItem(
                    value: BookSearchMatch.contains,
                    child: Text('模糊匹配'),
                  ),
                ],
                onChanged: (value) => setState(() => _match = value!),
              ),
            ],
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: content,
        ),
      ),
    );
  }

  Widget _buildReferenceBanner(SourcedBook reference) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: bookSourcePanelDecoration(
        context,
        radius: 16,
        stronger: true,
      ),
      child: Row(
        children: [
          Icon(Icons.manage_search_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '查找其他书源',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    reference.book.title,
                    reference.book.author,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: sourceTextActionStyle(context),
            onPressed: () => setState(() => _reference = null),
            child: const Text('普通搜索'),
          ),
        ],
      ),
    );
  }

  List<List<SourcedBook>> _groupResults() {
    final filter = BookSearchFilter(
      query: _activeQuery,
      field: _field,
      match: _match,
      reference: _reference?.book,
    );
    final groups = <String, List<SourcedBook>>{};
    for (final result in _results) {
      if (!filter.accepts(result.book)) continue;
      if (result.source.id == _reference?.source.id &&
          result.book.id == _reference?.book.id) {
        continue;
      }
      final key = BookSearchFilter.workKey(result.book, result.source.id);
      (groups[key] ??= []).add(result);
    }
    return groups.values.toList(growable: false);
  }

  Widget _buildBookGroup(List<SourcedBook> group) {
    final result = group.first;
    return SourcedBookListTile(
      result: result,
      onTap: () => _actions.showBookDetails(result),
      footer: group.length > 1
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _chooseBookSource(group),
                icon: const Icon(Icons.library_books_outlined, size: 16),
                label: Text(
                  '${group.map((b) => b.source.id).toSet().length} 个来源',
                ),
              ),
            )
          : _reference != null &&
                BookSearchFilter.normalizeAuthor(result.book.author).isEmpty
          ? Text('作者未标注，请核对简介和目录', style: Theme.of(context).textTheme.bodySmall)
          : null,
    );
  }

  void _chooseBookSource(List<SourcedBook> group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.first.book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '选择书源 · ${group.length} 条结果',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: group.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 76),
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(group[index].source.name),
                  subtitle: Text(
                    group[index].book.latestChapter ?? group[index].book.author,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).pop();
                    _actions.showBookDetails(group[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || _historyEdited) return;
      setState(() => _history = prefs.getStringList(_historyKey) ?? const []);
    } catch (_) {
      // Search remains available when local preferences cannot be read.
    }
  }

  void _saveHistory(List<String> entries) {
    _historyEdited = true;
    _history = entries;
    _historyWrites = _historyWrites
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(_historyKey, entries);
        })
        .catchError((Object _) {});
  }

  void _rememberQuery(String query) => _saveHistory(
    [query, ..._history.where((entry) => entry != query)].take(20).toList(),
  );

  Widget _buildHistory() => ListView(
    key: const Key('bookSourceSearchHistory'),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      Row(
        children: [
          const Expanded(child: Text('搜索历史')),
          TextButton(
            style: sourceTextActionStyle(context),
            key: const Key('bookSourceClearHistory'),
            onPressed: _history.isEmpty
                ? null
                : () => setState(() => _saveHistory([])),
            child: const Text('清空'),
          ),
        ],
      ),
      if (_history.isEmpty) const Text('输入书名或作者，开始找书'),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: _history.map(_historyChip).toList(),
      ),
    ],
  );

  Widget _historyChip(String query) => ActionChip(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    side: BorderSide.none,
    labelStyle: Theme.of(context).textTheme.bodySmall,
    label: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
    onPressed: () {
      _queryController.text = query;
      unawaited(_search());
    },
  );

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 42,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchBatch {
  final RegisteredBookSource source;
  final List<SourcedBook> items;
  final bool failed;
  final int page;
  final bool hasMore;

  const _SearchBatch({
    required this.source,
    required this.items,
    this.failed = false,
    this.page = 1,
    this.hasMore = false,
  });
}

class _SearchPageState {
  final RegisteredBookSource source;
  final int page;
  final bool hasMore;

  const _SearchPageState({
    required this.source,
    required this.page,
    required this.hasMore,
  });
}
