import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 横向滚动条：PC 鼠标可拖拽，滚轮上下也可横向滑动（部门筛选 chips 等）。
class HorizontalDragScrollView extends StatefulWidget {
  const HorizontalDragScrollView({
    super.key,
    required this.child,
    this.padding,
    this.controller,
    this.physics,
    this.showScrollbar = false,
    this.reverse = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool showScrollbar;
  final bool reverse;

  @override
  State<HorizontalDragScrollView> createState() =>
      _HorizontalDragScrollViewState();
}

class _HorizontalDragScrollViewState extends State<HorizontalDragScrollView> {
  ScrollController? _ownedController;

  ScrollController get _controller =>
      widget.controller ?? (_ownedController ??= ScrollController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final c = _controller;
    if (!c.hasClients) return;
    // 鼠标滚轮多为 dy；把垂直滚轮映射为横向位移。
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final pos = c.position;
    final next = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (next != pos.pixels) {
      c.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: widget.showScrollbar
            ? Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                interactive: true,
                child: _scrollView(),
              )
            : _scrollView(),
      ),
    );
  }

  Widget _scrollView() {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      reverse: widget.reverse,
      padding: widget.padding,
      physics: widget.physics,
      child: widget.child,
    );
  }
}
