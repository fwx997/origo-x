import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

double readerToolbarWidth(int actionCount) => 18 + actionCount * 72.0;

enum ReaderToolbarAction {
  catalog('目录'),
  aloud('朗读'),
  ai('AI'),
  settings('阅读设置');

  const ReaderToolbarAction(this.label);
  final String label;
}

class ReaderToolbarPreferences {
  const ReaderToolbarPreferences({
    this.enabled = true,
    this.labels = false,
    this.order = ReaderToolbarAction.values,
    this.hidden = const {},
  });
  final bool enabled;
  final bool labels;
  final List<ReaderToolbarAction> order;
  final Set<ReaderToolbarAction> hidden;

  ReaderToolbarPreferences copyWith({
    bool? enabled,
    bool? labels,
    List<ReaderToolbarAction>? order,
    Set<ReaderToolbarAction>? hidden,
  }) => ReaderToolbarPreferences(
    enabled: enabled ?? this.enabled,
    labels: labels ?? this.labels,
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
  );
}

class ReaderToolbarStore {
  static final state = ValueNotifier(const ReaderToolbarPreferences());
  static Future<void>? _writes;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList('reader_toolbar_order') ?? [];
    final order = <ReaderToolbarAction>[];
    for (final name in names) {
      final matches = ReaderToolbarAction.values.where((a) => a.name == name);
      if (matches.isNotEmpty && !order.contains(matches.first)) {
        order.add(matches.first);
      }
    }
    order.addAll(ReaderToolbarAction.values.where((a) => !order.contains(a)));
    final hidden = prefs.getStringList('reader_toolbar_hidden') ?? [];
    state.value = ReaderToolbarPreferences(
      enabled: prefs.getBool('reader_toolbar_enabled') ?? true,
      labels: prefs.getBool('reader_toolbar_labels') ?? false,
      order: order,
      hidden: ReaderToolbarAction.values
          .where((a) => hidden.contains(a.name))
          .toSet(),
    );
  }

  static Future<void> save(ReaderToolbarPreferences value) {
    state.value = value;
    final previous = _writes;
    final next = previous == null
        ? _write(value)
        : previous.catchError((Object _) {}).then((_) => _write(value));
    _writes = next;
    return next.whenComplete(() {
      if (identical(_writes, next)) _writes = null;
    });
  }

  static Future<void> _write(ReaderToolbarPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_toolbar_enabled', value.enabled);
    await prefs.setBool('reader_toolbar_labels', value.labels);
    await prefs.setStringList(
      'reader_toolbar_order',
      value.order.map((a) => a.name).toList(),
    );
    await prefs.setStringList(
      'reader_toolbar_hidden',
      value.hidden.map((a) => a.name).toList(),
    );
  }
}

class ReaderToolbarBuilder extends StatefulWidget {
  const ReaderToolbarBuilder({super.key, required this.builder});
  final Widget Function(BuildContext, ReaderToolbarPreferences) builder;

  @override
  State<ReaderToolbarBuilder> createState() => _ReaderToolbarBuilderState();
}

class _ReaderToolbarBuilderState extends State<ReaderToolbarBuilder> {
  @override
  void initState() {
    super.initState();
    ReaderToolbarStore.load().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ReaderToolbarStore.state,
    builder: (context, value, _) => widget.builder(context, value),
  );
}

class ReaderToolbarSettingsPage extends StatelessWidget {
  const ReaderToolbarSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('阅读底部栏')),
    body: ReaderToolbarBuilder(builder: _content),
  );

  Widget _content(BuildContext context, ReaderToolbarPreferences value) =>
      ReorderableListView(
        padding: const EdgeInsets.all(20),
        buildDefaultDragHandles: false,
        header: _header(context, value),
        onReorderItem: (oldIndex, newIndex) {
          final order = [...value.order];
          order.insert(newIndex, order.removeAt(oldIndex));
          ReaderToolbarStore.save(value.copyWith(order: order));
        },
        children: [
          for (final action in value.order) _action(context, value, action),
        ],
      );

  Widget _header(BuildContext context, ReaderToolbarPreferences value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _preview(context, value),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('显示底部栏'),
                  value: value.enabled,
                  onChanged: (enabled) =>
                      ReaderToolbarStore.save(value.copyWith(enabled: enabled)),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: const Text('显示按钮文字'),
                  value: value.labels,
                  onChanged: (labels) =>
                      ReaderToolbarStore.save(value.copyWith(labels: labels)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
            child: Text('按钮与顺序', style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              '拖动手柄调整顺序。关闭底部栏后，仍可从右上角进入阅读设置。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      );

  Widget _preview(BuildContext context, ReaderToolbarPreferences value) {
    final scheme = Theme.of(context).colorScheme;
    final actions = value.order
        .where((a) => !value.hidden.contains(a))
        .toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Text(
            '底部栏预览',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          if (!value.enabled || actions.isEmpty)
            const Text('底部栏已隐藏')
          else
            SizedBox(
              width: readerToolbarWidth(actions.length),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final action in actions)
                    _previewAction(context, action, value.labels),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewAction(
    BuildContext context,
    ReaderToolbarAction action,
    bool labels,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(switch (action) {
        ReaderToolbarAction.catalog => Icons.format_list_bulleted_rounded,
        ReaderToolbarAction.aloud => Icons.headphones_rounded,
        ReaderToolbarAction.ai => Icons.auto_awesome_outlined,
        ReaderToolbarAction.settings => Icons.tune_rounded,
      }, color: Theme.of(context).colorScheme.primary),
      if (labels)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            action.label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
    ],
  );

  Widget _action(
    BuildContext context,
    ReaderToolbarPreferences value,
    ReaderToolbarAction action,
  ) => Card(
    key: ValueKey(action),
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: SwitchListTile(
      secondary: ReorderableDragStartListener(
        index: value.order.indexOf(action),
        child: Icon(
          Icons.drag_handle_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(action.label),
      value: !value.hidden.contains(action),
      onChanged: (visible) {
        final hidden = {...value.hidden};
        visible ? hidden.remove(action) : hidden.add(action);
        ReaderToolbarStore.save(value.copyWith(hidden: hidden));
      },
    ),
  );
}
