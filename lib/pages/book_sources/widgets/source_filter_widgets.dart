import 'package:flutter/material.dart';

ButtonStyle sourceTextActionStyle(BuildContext context) => ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(36, 32)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  ),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: WidgetStatePropertyAll(
    Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
  ),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
  ),
);

/// Shared by search and discovery so new source controls follow the page theme.
class SourceFilterControl<T> extends StatelessWidget {
  const SourceFilterControl({
    super.key,
    required this.controlKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key controlKey;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: controlKey,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          for (final item in items) _option(context, item),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, DropdownMenuItem<T> item) {
    final selected = item.value == value;
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      key: ValueKey('${controlKey.toString()}:${item.value}'),
      onPressed: item.enabled ? () => onChanged(item.value) : null,
      style: TextButton.styleFrom(
        foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        backgroundColor: Colors.transparent,
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Semantics(selected: selected, child: item.child),
    );
  }
}

class SourceFilterGrid extends StatelessWidget {
  const SourceFilterGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

class SourceLoadingStatus extends StatelessWidget {
  const SourceLoadingStatus({
    super.key,
    required this.label,
    this.value,
    this.onStop,
  });
  final String label;
  final double? value;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onStop != null)
              IconButton(
                key: const Key('bookSourceStopSearch'),
                tooltip: '停止搜索',
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value, minHeight: 3),
        ),
      ],
    );
  }
}
