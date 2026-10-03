import 'package:flutter/material.dart';

/// Shared interaction shell for local and online vertical paging.
///
/// Each annotated text page owns its selection policy. An outer selection
/// area would make text selectable again when page selection is disabled.
class ReaderVerticalPagingSurface extends StatelessWidget {
  const ReaderVerticalPagingSurface({
    super.key,
    required this.child,
    this.onTap,
    this.surfaceKey,
    this.onHorizontalDragEnd,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Key? surfaceKey;
  final GestureDragEndCallback? onHorizontalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: surfaceKey,
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onHorizontalDragEnd: onHorizontalDragEnd,
      child: child,
    );
  }
}
