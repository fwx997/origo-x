import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Observes a short, stationary pointer sequence without entering Flutter's
/// gesture arena.
///
/// Reader text selection owns the arena for taps, long presses and drags. A
/// raw observer lets the reader still handle an ordinary page tap while long
/// presses and moved pointers remain available to selection and scrolling.
class ReaderTapObserver extends StatefulWidget {
  const ReaderTapObserver({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.onVerticalSwipe,
    this.onEdgeBack,
  });

  final Widget child;
  final ValueChanged<Offset> onTap;
  final bool enabled;
  final VoidCallback? onVerticalSwipe;
  final VoidCallback? onEdgeBack;

  @override
  State<ReaderTapObserver> createState() => _ReaderTapObserverState();
}

class _ReaderTapObserverState extends State<ReaderTapObserver> {
  int? _pointer;
  Offset? _origin;
  Timer? _longPressTimer;
  bool _moved = false;
  bool _expired = false;
  bool _verticalReported = false;
  double _edgeDistance = 0;

  void _reset() {
    _pointer = null;
    _origin = null;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _moved = false;
    _expired = false;
    _verticalReported = false;
  }

  void _handleDown(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _moved = false;
    _expired = false;
    _longPressTimer = Timer(
      const Duration(milliseconds: 420),
      () => _expired = true,
    );
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final origin = _origin;
    if (origin != null && (event.position - origin).distance >= kTouchSlop) {
      _moved = true;
      final delta = event.position - origin;
      if (!_verticalReported && delta.dy.abs() > delta.dx.abs()) {
        _verticalReported = true;
        widget.onVerticalSwipe?.call();
      }
    }
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final shouldTap = widget.enabled && !_moved && !_expired;
    final localPosition = event.localPosition;
    _reset();
    if (!shouldTap) return;
    // Let inline text recognizers run first. A tappable annotation can open a
    // route or disable reader input before this fallback page tap is handled.
    scheduleMicrotask(() {
      if (!mounted || !widget.enabled) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      widget.onTap(localPosition);
    });
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _reset();
  }

  @override
  void didUpdateWidget(covariant ReaderTapObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) _reset();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _finishEdgeSwipe(DragEndDetails details) {
    final shouldExit =
        _edgeDistance >= 72 ||
        (_edgeDistance > 20 && (details.primaryVelocity ?? 0) > 600);
    _edgeDistance = 0;
    if (shouldExit && widget.enabled) widget.onEdgeBack?.call();
  }

  @override
  Widget build(BuildContext context) {
    final content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.child,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (widget.enabled && widget.onEdgeBack != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 22,
            child: _edgeGesture(),
          ),
      ],
    );
  }

  Widget _edgeGesture() => GestureDetector(
    key: const ValueKey('reader-edge-swipe-back'),
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _edgeDistance = 0,
    onHorizontalDragUpdate: (details) => _edgeDistance += details.delta.dx,
    onHorizontalDragEnd: _finishEdgeSwipe,
    onHorizontalDragCancel: () => _edgeDistance = 0,
  );
}
