import 'package:flutter/material.dart';
import 'package:xxread/utils/page_style_helper.dart';

import 'sourced_book_widgets.dart';

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
    final theme = Theme.of(context);
    final palette = PageStyleHelper.palette(context);
    return Container(
      decoration: bookSourcePanelDecoration(context, radius: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: controlKey,
              value: value,
              isExpanded: true,
              isDense: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              borderRadius: BorderRadius.circular(16),
              dropdownColor: palette.cardStrong,
              menuMaxHeight: 360,
              icon: Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: palette.iconMuted,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class SourceFilterGrid extends StatelessWidget {
  const SourceFilterGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      final columns = constraints.maxWidth >= 330 && !largeText ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
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
