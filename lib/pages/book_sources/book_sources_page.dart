// 文件说明：先选择站点，再展示该站点的推荐、分类与最新书籍。
// 技术要点：Flutter UI、按 Tab 缓存的书源请求、下拉刷新。

import 'dart:async';
import 'package:xxread/book_sources/services/source_task_pool.dart';
import 'package:xxread/book_sources/services/book_download_cancellation.dart';
import 'package:xxread/book_sources/xbs/xbs_discovery.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/services/book_source_client.dart';
import 'package:xxread/book_sources/services/book_source_registry.dart';
import 'package:xxread/book_sources/services/book_source_shelf_service.dart';
import 'package:xxread/pages/home/home_mobile_chrome.dart';
import 'package:xxread/pages/home/home_shell_page.dart';
import 'package:xxread/utils/localization_extension.dart';
import 'package:xxread/utils/page_style_helper.dart';

import 'book_source_management_page.dart';
import 'source_search_page.dart';
import 'widgets/sourced_book_widgets.dart';
import 'widgets/source_filter_widgets.dart';
import 'widgets/source_picker.dart';

/// 发现页：只负责展示书籍内容。
///
/// 搜索收纳在顶栏的搜索按钮里（独立页面），书源配置收纳在管理页。
class BookSourcesPage extends StatefulWidget {
  final BookSourceClient? client;

  static const int maxLatestItemsPerSource = 12;
  static const selectedSourceKey = 'discovery_selected_source_v1';

  const BookSourcesPage({super.key, this.client});

  @visibleForTesting
  static List<RegisteredBookSource> searchTargets(
    Iterable<RegisteredBookSource> sources,
    String? selectedSourceId,
  ) => SourceSearchPage.searchTargets(sources, selectedSourceId);

  /// 保留每个书源自己的 latest 顺序，再按来源轮流穿插。
  ///
  /// 首轮优先展示头部更新时间较新的书源；随后每轮每源最多贡献一本，
  /// 避免单一书源依靠时间戳或返回数量占满聚合列表。
  @visibleForTesting
  static List<SourcedBook> interleaveLatestBatches(
    Iterable<List<SourcedBook>> batches, {
    int maxItemsPerSource = maxLatestItemsPerSource,
  }) {
    if (maxItemsPerSource <= 0) return const [];
    final queues = batches
        .where((batch) => batch.isNotEmpty)
        .map((batch) => batch.take(maxItemsPerSource).toList(growable: false))
        .toList();
    queues.sort((left, right) {
      final leftTime = left.first.book.updatedAt;
      final rightTime = right.first.book.updatedAt;
      if (leftTime != null && rightTime != null) {
        final byTime = rightTime.compareTo(leftTime);
        if (byTime != 0) return byTime;
      } else if (leftTime != null) {
        return -1;
      } else if (rightTime != null) {
        return 1;
      }
      return left.first.source.name.compareTo(right.first.source.name);
    });

    final results = <SourcedBook>[];
    for (var index = 0; index < maxItemsPerSource; index++) {
      var added = false;
      for (final queue in queues) {
        if (index >= queue.length) continue;
        results.add(queue[index]);
        added = true;
      }
      if (!added) break;
    }
    return results;
  }

  @override
  State<BookSourcesPage> createState() => _BookSourcesPageState();
}

class _BookSourcesPageState extends State<BookSourcesPage> {
  final BookSourceRegistry _registry = BookSourceRegistry();
  late final BookSourceClient _client;
  late final BookSourceShelfService _shelfService = BookSourceShelfService(
    client: _client,
  );
  late final SourcedBookActions _actions = SourcedBookActions(
    context: context,
    client: _client,
    shelfService: _shelfService,
    onFindSources: _findSources,
  );
  StreamSubscription<void>? _registrySubscription;

  List<RegisteredBookSource> _sources = const [];
  bool _loadingSources = true;
  _DiscoverSection _section = _DiscoverSection.recommended;
  String? _selectedSourceId;

  // 每个 Tab 的内容独立缓存，切换回来不再重新请求。
  final Map<_DiscoverSection, _SectionCache> _cache = {};
  final Map<_DiscoverSection, BookDownloadCancellation> _sectionRequests = {};
  BookDownloadCancellation _categoryRequest = BookDownloadCancellation();
  int _sourceGeneration = 0;
  _SourcedCategory? _selectedCategory;
  List<SourcedBook> _categoryBooks = const [];
  bool _loadingCategoryBooks = false;
  Map<String, String> _categoryFilters = {};
  int _categoryPage = 0;
  bool _categoryHasMore = false;
  String? _categoryError;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? BookSourceClient();
    _registrySubscription = _registry.changes.listen((_) => _reloadAll());
    unawaited(_loadSources());
  }

  @override
  void dispose() {
    _cancelRequests();
    _registrySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final generation = ++_sourceGeneration;
    final sources = await _registry.loadRunnable();
    final prefs = await SharedPreferences.getInstance();
    final selectedId =
        _selectedSourceId ?? prefs.getString(BookSourcesPage.selectedSourceKey);
    if (!mounted || generation != _sourceGeneration) return;
    setState(() {
      _sources = sources;
      _selectedSourceId = sources.any((source) => source.id == selectedId)
          ? selectedId
          : null;
      _section = _availableSection(_section);
      _loadingSources = false;
    });
    await _loadSection(_section);
  }

  Future<void> _reloadAll() async {
    _cancelRequests();
    _cache.clear();
    _selectedCategory = null;
    _categoryBooks = const [];
    _loadingCategoryBooks = false;
    _categoryFilters = {};
    _categoryError = null;
    _categoryHasMore = false;
    await _loadSources();
  }

  void _cancelRequests() {
    _categoryRequest.cancel();
    for (final request in _sectionRequests.values) {
      request.cancel();
    }
  }

  List<RegisteredBookSource> _targets(String capability) => _sources
      .where((source) => source.enabled)
      .where((source) => source.capabilities.contains(capability))
      .toList(growable: false);

  String _capabilityFor(_DiscoverSection section) => switch (section) {
    _DiscoverSection.recommended => 'discover',
    _DiscoverSection.categories => 'categories',
    _DiscoverSection.latest => 'browse',
  };

  List<RegisteredBookSource> _sourcesFor(_DiscoverSection section) => _targets(
    _capabilityFor(section),
  ).where((source) => source.id == _selectedSourceId).toList();

  _DiscoverSection _availableSection(_DiscoverSection preferred) {
    if (_sourcesFor(preferred).isNotEmpty) return preferred;
    return _DiscoverSection.values
            .where((section) => _sourcesFor(section).isNotEmpty)
            .firstOrNull ??
        preferred;
  }

  bool _matchesSelectedSource(RegisteredBookSource source) =>
      _selectedSourceId == null || source.id == _selectedSourceId;

  Future<void> _loadSection(
    _DiscoverSection section, {
    bool force = false,
    bool retryFailed = false,
  }) async {
    if (_selectedSourceId == null) return;
    final cached = _cache[section];
    final interrupted =
        cached != null &&
        cached.pending.isNotEmpty &&
        _sectionRequests[section]?.isCancelled == true;
    if (!force && !retryFailed && cached != null && !interrupted) return;
    _sectionRequests[section]?.cancel();
    final cancellation = BookDownloadCancellation();
    _sectionRequests[section] = cancellation;
    final reuse = cached != null && (interrupted || retryFailed) && !force;
    final targets = _sourcesFor(section)
        .where(
          (source) =>
              !reuse ||
              cached.pending.contains(source.id) ||
              retryFailed && cached.failures.containsKey(source.id),
        )
        .toList();
    final pending = targets.map((source) => source.id).toSet();
    if (force && section == _DiscoverSection.categories) {
      _categoryRequest.cancel();
      _selectedCategory = null;
      _categoryBooks = const [];
      _loadingCategoryBooks = false;
      _categoryError = null;
      _categoryHasMore = false;
    }
    setState(
      () => _cache[section] = _SectionCache(
        pending: pending,
        shelves: reuse ? cached.shelves : const [],
        categories: reuse ? cached.categories : const [],
        books: reuse ? cached.books : const [],
        failures: reuse
            ? {
                for (final failure in cached.failures.entries)
                  if (!pending.contains(failure.key))
                    failure.key: failure.value,
              }
            : const {},
      ),
    );
    if (section == _DiscoverSection.categories && section == _section) {
      _autoSelectFirstCategory();
    }
    final pool = SourceTaskPool(limit: 12, perHost: 12);
    await Future.wait(
      targets.map(
        (source) => pool
            .run(
              source.apiBaseUrl.host,
              () => _fetchSectionSource(section, source, cancellation),
              cancellation: cancellation,
            )
            .onError((_, _) {}),
      ),
    );
  }

  Future<void> _fetchSectionSource(
    _DiscoverSection section,
    RegisteredBookSource source,
    BookDownloadCancellation cancellation,
  ) async {
    _SectionCache batch;
    try {
      batch = await SourceTaskContext.run(
        cancellation,
        () => _fetchSectionContent(section, source),
      );
    } catch (error) {
      batch = _SectionCache(failures: {source.id: '${source.name}: $error'});
    }
    if (!mounted ||
        cancellation.isCancelled ||
        _sectionRequests[section] != cancellation) {
      return;
    }
    final previous = _cache[section]!;
    setState(
      () => _cache[section] = _SectionCache(
        shelves: [...previous.shelves, ...batch.shelves],
        categories: [...previous.categories, ...batch.categories],
        books: [...previous.books, ...batch.books],
        pending: {...previous.pending}..remove(source.id),
        failures: {...previous.failures, ...batch.failures},
      ),
    );
    if (section == _DiscoverSection.categories && section == _section) {
      _autoSelectFirstCategory();
    }
  }

  Future<_SectionCache> _fetchSectionContent(
    _DiscoverSection section,
    RegisteredBookSource source,
  ) async {
    switch (section) {
      case _DiscoverSection.recommended:
        final page = await _client.getDiscovery(source);
        return _SectionCache(
          shelves: page.sections
              .where((section) => section.items.isNotEmpty)
              .map(
                (section) => _DiscoveryShelf(
                  source: source,
                  title: section.title,
                  items: section.items,
                ),
              )
              .toList(growable: false),
        );
      case _DiscoverSection.categories:
        final categories = await _client.getCategories(source);
        return _SectionCache(
          categories: categories
              .map(
                (category) =>
                    _SourcedCategory(source: source, category: category),
              )
              .toList(growable: false),
        );
      case _DiscoverSection.latest:
        final page = await _client.browse(source, sort: 'latest');
        return _SectionCache(
          books: page.items
              .take(BookSourcesPage.maxLatestItemsPerSource)
              .map((book) => SourcedBook(source: source, book: book))
              .toList(growable: false),
        );
    }
  }

  void _autoSelectFirstCategory() {
    final cache = _cache[_DiscoverSection.categories];
    final categories = (cache?.categories ?? const <_SourcedCategory>[])
        .where((category) => _matchesSelectedSource(category.source))
        .toList(growable: false);
    if (_selectedCategory != null || categories.isEmpty) return;
    unawaited(_selectCategory(categories.first));
  }

  void _changeSourceScope(String? sourceId) {
    if (sourceId == null || _selectedSourceId == sourceId) return;
    _cancelRequests();
    setState(() {
      _cache.clear();
      _selectedSourceId = sourceId;
      _section = _availableSection(_section);
      _selectedCategory = null;
      _categoryBooks = const [];
      _loadingCategoryBooks = false;
      _categoryFilters = {};
      _categoryError = null;
      _categoryHasMore = false;
    });
    unawaited(_rememberSource(sourceId));
    unawaited(_loadSection(_section));
  }

  Future<void> _rememberSource(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BookSourcesPage.selectedSourceKey, sourceId);
  }

  Future<void> _changeSection(_DiscoverSection section) async {
    if (_section != section) _sectionRequests[_section]?.cancel();
    if (_section == _DiscoverSection.categories && _section != section) {
      _categoryRequest.cancel();
      _selectedCategory = null;
      _categoryBooks = const [];
      _categoryError = null;
      _categoryHasMore = false;
      _loadingCategoryBooks = false;
    }
    setState(() {
      _section = section;
    });
    await _loadSection(section);
    if (mounted && section == _DiscoverSection.categories) {
      _autoSelectFirstCategory();
    }
  }

  Future<void> _selectCategory(
    _SourcedCategory category, {
    Map<String, String>? filters,
  }) async {
    _categoryRequest.cancel();
    _categoryRequest = BookDownloadCancellation();
    setState(() {
      _selectedCategory = category;
      _categoryBooks = const [];
      _categoryFilters =
          filters ??
          {
            for (final group in category.category.filterGroups)
              group.id: group.options.first.value,
          };
      _categoryPage = 0;
      _categoryHasMore = category.source.capabilities.contains('browse');
      _categoryError = null;
      _loadingCategoryBooks = false;
    });
    if (_categoryHasMore) await _loadCategoryPage();
  }

  Future<void> _loadCategoryPage() async {
    final category = _selectedCategory;
    if (category == null || _loadingCategoryBooks || !_categoryHasMore) return;
    final cancellation = _categoryRequest;
    final pageNumber = _categoryPage + 1;
    final categoryId =
        category.source.sourceProtocol == BookSourceProtocolKind.xbs
        ? XbsDiscovery.withFilters(category.id, _categoryFilters)
        : category.id;
    setState(() {
      _loadingCategoryBooks = true;
      _categoryError = null;
    });
    try {
      final page = await SourceTaskContext.run(
        cancellation,
        () => _client.browse(
          category.source,
          category: categoryId,
          sort: 'popular',
          page: pageNumber,
        ),
      );
      if (!mounted ||
          cancellation.isCancelled ||
          _categoryRequest != cancellation) {
        return;
      }
      final seen = _categoryBooks.map((item) => item.book.id).toSet();
      final added = page.items
          .where((book) => seen.add(book.id))
          .map((book) => SourcedBook(source: category.source, book: book))
          .toList(growable: false);
      setState(() {
        _categoryBooks = [..._categoryBooks, ...added];
        _categoryPage = pageNumber;
        _categoryHasMore = page.hasMore && added.isNotEmpty;
        _loadingCategoryBooks = false;
      });
    } catch (error) {
      if (!mounted ||
          cancellation.isCancelled ||
          _categoryRequest != cancellation) {
        return;
      }
      setState(() {
        _categoryError = error.toString();
        _loadingCategoryBooks = false;
      });
    }
  }

  Future<void> _openCategoryPicker(List<_SourcedCategory> categories) async {
    final size = MediaQuery.sizeOf(context);
    final picker = _CategoryPickerPanel(
      categories: categories,
      selectedCategory: _selectedCategory,
      title: context.l10n.discoverCategories,
      searchLabel: context.l10n.search,
      noResultsLabel: context.l10n.bookSourcesNoResults,
    );
    final _SourcedCategory? selected;
    if (size.width >= 720) {
      selected = await showDialog<_SourcedCategory>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: (size.width - 48).clamp(320, 520).toDouble(),
            height: (size.height - 48).clamp(320, 680).toDouble(),
            child: picker,
          ),
        ),
      );
    } else {
      selected = await showModalBottomSheet<_SourcedCategory>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        clipBehavior: Clip.antiAlias,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: picker,
          ),
        ),
      );
    }
    if (selected != null && mounted && selected != _selectedCategory) {
      await _selectCategory(selected);
    }
  }

  void _openSearch() {
    _findSources(null);
  }

  void _findSources(SourcedBook? book) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourceSearchPage(
          sources: _sources,
          client: _client,
          shelfService: _shelfService,
          initialBook: book,
          initialSourceId: book == null ? _selectedSourceId : null,
        ),
      ),
    );
  }

  Future<void> _openSourceManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BookSourceManagementPage()),
    );
    if (mounted) await _reloadAll();
  }

  @override
  Widget build(BuildContext context) {
    final useRailNavigation =
        NavigationContext.of(context)?.useRailNavigation ?? false;
    final mobileChrome = HomeMobileChromeScope.of(context);
    final bottomPadding = useRailNavigation
        ? 32.0
        : mobileChrome.pageBottomPadding;

    return Container(
      decoration: BoxDecoration(
        gradient: PageStyleHelper.backgroundGradient(context),
      ),
      child: SafeArea(
        top: useRailNavigation,
        bottom: false,
        child: RefreshIndicator(
          edgeOffset: useRailNavigation ? 90 : mobileChrome.topBarHeight,
          onRefresh: () => _loadSection(_section, force: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        useRailNavigation ? 16 : mobileChrome.pageTopPadding,
                        16,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (useRailNavigation) _buildRailHeader(),
                          if (_sources.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildSourceScope(_sources),
                          ],
                          if (_selectedSourceId != null) _buildSectionTabs(),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ..._buildSectionSlivers(bottomPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRailHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.discover,
              style: TextStyle(
                fontSize: 36,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          IconButton.filledTonal(
            key: const Key('bookSourceSearchEntry'),
            tooltip: context.l10n.bookSourcesSearch,
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: context.l10n.bookSourceManagementTitle,
            onPressed: _openSourceManagement,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabs() {
    return SourceFilterControl<_DiscoverSection>(
      controlKey: const Key('discoverSectionTabs'),
      label: '',
      value: _section,
      items: [
        if (_sourcesFor(_DiscoverSection.recommended).isNotEmpty)
          DropdownMenuItem(
            value: _DiscoverSection.recommended,
            child: Text(context.l10n.discoverRecommended),
          ),
        if (_sourcesFor(_DiscoverSection.categories).isNotEmpty)
          DropdownMenuItem(
            value: _DiscoverSection.categories,
            child: Text(context.l10n.discoverCategories),
          ),
        if (_sourcesFor(_DiscoverSection.latest).isNotEmpty)
          DropdownMenuItem(
            value: _DiscoverSection.latest,
            child: Text(context.l10n.discoverLatest),
          ),
      ],
      onChanged: (section) {
        if (section != null) unawaited(_changeSection(section));
      },
    );
  }

  Widget _buildSourceScope(List<RegisteredBookSource> sources) {
    final selected = sources.where((source) => source.id == _selectedSourceId);
    final label = selected.isEmpty ? '选择一个站点开始浏览' : selected.first.name;
    return Row(
      key: const Key('bookSourceDiscoverScopeControl'),
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        TextButton(
          style: sourceTextActionStyle(context),
          onPressed: _openSearch,
          child: const Text('搜索'),
        ),
        TextButton(
          style: sourceTextActionStyle(context),
          key: const Key('bookSourceDiscoverSwitch'),
          onPressed: () async {
            final selected = await showSourcePicker(
              context,
              sources: sources,
              selectedId: _selectedSourceId,
              allowAll: false,
            );
            if (mounted && selected != null) _changeSourceScope(selected.id);
          },
          child: Text(_selectedSourceId == null ? '选择站点' : '切换'),
        ),
      ],
    );
  }

  List<Widget> _buildSectionSlivers(double bottomPadding) {
    if (_loadingSources) {
      return [
        _paddedSectionSliver(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 44),
            child: Center(child: CircularProgressIndicator()),
          ),
          bottomPadding: bottomPadding,
        ),
      ];
    }
    if (_selectedSourceId == null) return _buildSourceChoices(bottomPadding);
    final cache = _cache[_section];
    if (cache == null) return const [];
    final pending = cache.pending
        .where((id) => _selectedSourceId == null || id == _selectedSourceId)
        .length;
    final failures = cache.failures.entries
        .where(
          (entry) =>
              _selectedSourceId == null || entry.key == _selectedSourceId,
        )
        .toList();
    final hasContent = cache.hasContent(_selectedSourceId);
    final slivers = <Widget>[];
    if (pending > 0) {
      slivers.add(
        _paddedSectionSliver(
          SourceLoadingStatus(label: '还有 $pending 个书源正在加载'),
          bottomPadding: 12,
        ),
      );
    }
    if (failures.isNotEmpty) {
      slivers.add(
        _paddedSectionSliver(
          _buildLoadFailure(
            failures.map((entry) => entry.value).join('\n'),
            () => _loadSection(_section, retryFailed: true),
          ),
          bottomPadding: 12,
        ),
      );
    }
    if (!hasContent && (pending > 0 || failures.isNotEmpty)) return slivers;
    slivers.addAll(switch (_section) {
      _DiscoverSection.recommended => _buildShelvesSlivers(
        cache,
        bottomPadding,
      ),
      _DiscoverSection.categories => _buildCategoriesSlivers(
        cache,
        bottomPadding,
      ),
      _DiscoverSection.latest => _buildLatestSlivers(cache, bottomPadding),
    });
    return slivers;
  }

  List<Widget> _buildShelvesSlivers(_SectionCache cache, double bottomPadding) {
    final shelves = cache.shelves
        .where((shelf) => _matchesSelectedSource(shelf.source))
        .toList(growable: false);
    if (shelves.isEmpty) {
      return [
        _paddedSectionSliver(
          _sourcesFor(_DiscoverSection.recommended).isEmpty
              ? _buildUnsupportedMessage('discover')
              : _buildEmptyMessage(),
          bottomPadding: bottomPadding,
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
        sliver: SliverList.builder(
          itemCount: shelves.length,
          itemBuilder: (context, index) =>
              _centerSectionChild(_buildShelf(shelves[index])),
        ),
      ),
    ];
  }

  Widget _buildShelf(_DiscoveryShelf shelf) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shelf.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              _buildSourceBadge(shelf.source.name),
            ],
          ),
          const SizedBox(height: 12),
          for (final book in shelf.items)
            SourcedBookListTile(
              result: SourcedBook(source: shelf.source, book: book),
              onTap: () => _actions.showBookDetails(
                SourcedBook(source: shelf.source, book: book),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildCategoriesSlivers(
    _SectionCache cache,
    double bottomPadding,
  ) {
    final categories = cache.categories
        .where((category) => _matchesSelectedSource(category.source))
        .toList(growable: false);
    if (categories.isEmpty) {
      return [
        _paddedSectionSliver(
          _sourcesFor(_DiscoverSection.categories).isEmpty
              ? _buildUnsupportedMessage('categories')
              : _buildEmptyMessage(),
          bottomPadding: bottomPadding,
        ),
      ];
    }
    final selected = _selectedCategory ?? categories.first;
    final slivers = <Widget>[
      _paddedSectionSliver(
        _CategoryPickerButton(
          category: selected,
          onTap: () => _openCategoryPicker(categories),
        ),
        bottomPadding: 2,
      ),
      if (selected.category.filterGroups.isNotEmpty)
        _paddedSectionSliver(
          _buildCategoryFilters(selected),
          bottomPadding: 12,
        ),
    ];
    if (_categoryBooks.isNotEmpty) {
      slivers.add(_bookListSliver(_categoryBooks, bottomPadding: 12));
    }
    if (_categoryError != null) {
      slivers.add(
        _paddedSectionSliver(
          _buildLoadFailure(_categoryError!, _loadCategoryPage),
          bottomPadding: bottomPadding,
        ),
      );
    } else if (_loadingCategoryBooks) {
      slivers.add(
        _paddedSectionSliver(
          const Center(child: CircularProgressIndicator()),
          bottomPadding: bottomPadding,
        ),
      );
    } else if (_categoryBooks.isEmpty) {
      slivers.add(
        _paddedSectionSliver(
          _buildMessageCard(
            icon: Icons.menu_book_outlined,
            title: context.l10n.bookSourcesNoResults,
            message: context.l10n.discoverCategoryEmpty,
          ),
          bottomPadding: bottomPadding,
        ),
      );
    }
    if (_categoryHasMore && !_loadingCategoryBooks && _categoryError == null) {
      slivers.add(
        _paddedSectionSliver(
          Center(
            child: OutlinedButton.icon(
              key: const Key('bookSourceCategoryLoadMore'),
              onPressed: _loadCategoryPage,
              icon: const Icon(Icons.expand_more),
              label: Text(context.l10n.bookSourcesLoadMore),
            ),
          ),
          bottomPadding: bottomPadding,
        ),
      );
    }
    return slivers;
  }

  Widget _buildCategoryFilters(_SourcedCategory category) {
    final groups = category.category.filterGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++)
          _categoryFilterField(category, groups[index], index),
      ],
    );
  }

  Widget _categoryFilterField(
    _SourcedCategory category,
    BookSourceFilterGroup group,
    int index,
  ) => SourceFilterControl<String>(
    controlKey: ValueKey('categoryFilter:${group.id}'),
    label: group.name == '筛选' ? '筛选 ${index + 1}' : group.name,
    value: _categoryFilters[group.id] ?? group.options.first.value,
    items: group.options
        .map(
          (option) => DropdownMenuItem(
            value: option.value,
            child: Text(
              option.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(growable: false),
    onChanged: (value) {
      if (value == null) return;
      unawaited(
        _selectCategory(
          category,
          filters: {..._categoryFilters, group.id: value},
        ),
      );
    },
  );

  List<Widget> _buildLatestSlivers(_SectionCache cache, double bottomPadding) {
    final batches = <String, List<SourcedBook>>{};
    for (final result in cache.books) {
      if (!_matchesSelectedSource(result.source)) continue;
      (batches[result.source.id] ??= []).add(result);
    }
    final books = BookSourcesPage.interleaveLatestBatches(
      batches.values.toList(),
    );
    if (books.isEmpty) {
      return [
        _paddedSectionSliver(
          _sourcesFor(_DiscoverSection.latest).isEmpty
              ? _buildUnsupportedMessage('browse')
              : _buildEmptyMessage(),
          bottomPadding: bottomPadding,
        ),
      ];
    }
    return [_bookListSliver(books, bottomPadding: bottomPadding)];
  }

  Widget _bookListSliver(
    List<SourcedBook> books, {
    required double bottomPadding,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      sliver: SliverList.separated(
        itemCount: books.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) {
          final result = books[index];
          return _centerSectionChild(
            SourcedBookListTile(
              result: result,
              onTap: () => _actions.showBookDetails(result),
            ),
          );
        },
      ),
    );
  }

  Widget _paddedSectionSliver(
    Widget child, {
    double topPadding = 8,
    required double bottomPadding,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
      sliver: SliverToBoxAdapter(child: _centerSectionChild(child)),
    );
  }

  Widget _centerSectionChild(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1048),
      child: child,
    ),
  );

  Widget _buildUnsupportedMessage(String capability) {
    final hasEnabledSources = _sources.any((source) => source.enabled);
    return _buildMessageCard(
      icon: hasEnabledSources
          ? Icons.extension_off_outlined
          : Icons.travel_explore_outlined,
      title: hasEnabledSources
          ? context.l10n.discoverUnsupportedTitle
          : context.l10n.bookSourcesNoSourcesTitle,
      message: hasEnabledSources
          ? context.l10n.discoverUnsupportedMessage(capability)
          : context.l10n.bookSourcesNoSourcesDescription,
      actionLabel: context.l10n.bookSourceManagementTitle,
      onAction: _openSourceManagement,
    );
  }

  Widget _buildEmptyMessage() {
    return _buildMessageCard(
      icon: Icons.inbox_outlined,
      title: context.l10n.discoverEmptyTitle,
      message: context.l10n.discoverEmptyMessage,
    );
  }

  List<Widget> _buildSourceChoices(double bottomPadding) {
    if (_sources.isEmpty) {
      return [
        _paddedSectionSliver(
          _buildUnsupportedMessage('discover'),
          bottomPadding: bottomPadding,
        ),
      ];
    }
    return [
      _paddedSectionSliver(
        Text('推荐、分类和最新内容均来自所选站点', style: Theme.of(context).textTheme.bodySmall),
        bottomPadding: 12,
      ),
      SliverList.builder(
        itemCount: _sources.length,
        itemBuilder: (_, index) =>
            _centerSectionChild(_sourceChoice(_sources[index])),
      ),
      SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
    ];
  }

  Widget _sourceChoice(RegisteredBookSource source) => ListTile(
    key: ValueKey('discover-source-${source.id}'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    leading: const Icon(Icons.language_rounded, size: 22),
    title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      source.apiBaseUrl.host,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: () => _changeSourceScope(source.id),
  );

  Widget _buildLoadFailure(String error, Future<void> Function() retry) =>
      Padding(
        key: const ValueKey('discover-load-failure'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.discoverLoadFailed,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: '查看失败详情',
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              onPressed: () => _showFailureDetails(error),
            ),
            TextButton(
              onPressed: retry,
              child: Text(context.l10n.discoverRetry),
            ),
          ],
        ),
      );

  void _showFailureDetails(String error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.discoverLoadFailed),
        content: SingleChildScrollView(child: Text(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    FutureOr<void> Function()? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: bookSourcePanelDecoration(context, radius: 22),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => onAction(),
              icon: const Icon(Icons.tune_rounded),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceBadge(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum _DiscoverSection { recommended, categories, latest }

/// Each source publishes its batch immediately; failures never erase successes.
class _SectionCache {
  final Set<String> pending;
  final Map<String, String> failures;
  final List<_DiscoveryShelf> shelves;
  final List<_SourcedCategory> categories;
  final List<SourcedBook> books;

  const _SectionCache({
    this.pending = const {},
    this.failures = const {},
    this.shelves = const [],
    this.categories = const [],
    this.books = const [],
  });

  bool hasContent(String? sourceId) =>
      shelves.any((item) => sourceId == null || item.source.id == sourceId) ||
      categories.any(
        (item) => sourceId == null || item.source.id == sourceId,
      ) ||
      books.any((item) => sourceId == null || item.source.id == sourceId);
}

class _DiscoveryShelf {
  final RegisteredBookSource source;
  final String title;
  final List<BookSourceBook> items;

  const _DiscoveryShelf({
    required this.source,
    required this.title,
    required this.items,
  });
}

class _SourcedCategory {
  final RegisteredBookSource source;
  final BookSourceCategory category;
  String get id => category.id;
  String get name => category.name;

  const _SourcedCategory({required this.source, required this.category});
}

class _CategoryPickerButton extends StatelessWidget {
  final _SourcedCategory category;
  final VoidCallback onTap;

  const _CategoryPickerButton({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('bookSourceCategoryPickerButton'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.name,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                category.source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerPanel extends StatefulWidget {
  final List<_SourcedCategory> categories;
  final _SourcedCategory? selectedCategory;
  final String title;
  final String searchLabel;
  final String noResultsLabel;

  const _CategoryPickerPanel({
    required this.categories,
    required this.selectedCategory,
    required this.title,
    required this.searchLabel,
    required this.noResultsLabel,
  });

  @override
  State<_CategoryPickerPanel> createState() => _CategoryPickerPanelState();
}

class _CategoryPickerPanelState extends State<_CategoryPickerPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_CategoryPickerEntry> _entries() {
    final query = _query.trim().toLowerCase();
    final matches = widget.categories.where((category) {
      if (query.isEmpty) return true;
      return category.name.toLowerCase().contains(query) ||
          category.source.name.toLowerCase().contains(query);
    });
    final entries = <_CategoryPickerEntry>[];
    String? sourceId;
    for (final category in matches) {
      if (category.source.id != sourceId) {
        sourceId = category.source.id;
        entries.add(_CategoryPickerEntry.header(category.source.name));
      }
      entries.add(_CategoryPickerEntry.category(category));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              key: const Key('bookSourceCategorySearchField'),
              controller: _searchController,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: widget.searchLabel,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      widget.noResultsLabel,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    key: const Key('bookSourceCategoryLazyList'),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final category = entry.category;
                      if (category == null) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                          child: Text(
                            entry.header!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        );
                      }
                      final selected = category == widget.selectedCategory;
                      return ListTile(
                        key: Key(
                          'bookSourceCategory-${category.source.id}-${category.id}',
                        ),
                        selected: selected,
                        title: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? Icon(Icons.check_rounded, color: scheme.primary)
                            : null,
                        onTap: () => Navigator.of(context).pop(category),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPickerEntry {
  final String? header;
  final _SourcedCategory? category;

  const _CategoryPickerEntry.header(this.header) : category = null;

  const _CategoryPickerEntry.category(this.category) : header = null;
}
