import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 表头固定：有限高度时列头钉在顶部，仅表体竖向滚动；表头与表体横向滚动同步。
///
/// 传入 [rowCount] / [rowHeight] / [dataRowBuilder] 时按行构建表体，避免一次挂上全部行。
class ReconPinnedTable extends StatefulWidget {
  const ReconPinnedTable({
    super.key,
    required this.headerHeight,
    required this.dataWidth,
    required this.dataHeader,
    this.dataBody = const SizedBox.shrink(),
    this.leadingHeader,
    this.leadingBody,
    this.trailingHeader,
    this.trailingBody,
    this.rowCount,
    this.rowHeight,
    this.dataRowBuilder,
    this.trailingRowBuilder,
    this.leadingRowBuilder,
  });

  final double headerHeight;
  final double dataWidth;
  final Widget dataHeader;
  final Widget dataBody;
  final Widget? leadingHeader;
  final Widget? leadingBody;
  final Widget? trailingHeader;
  final Widget? trailingBody;
  final int? rowCount;
  final double Function(int index)? rowHeight;
  final Widget Function(BuildContext context, int index)? dataRowBuilder;
  final Widget Function(BuildContext context, int index)? trailingRowBuilder;
  final Widget Function(BuildContext context, int index)? leadingRowBuilder;

  bool get _virtualized =>
      rowCount != null && rowHeight != null && dataRowBuilder != null;

  @override
  State<ReconPinnedTable> createState() => _ReconPinnedTableState();
}

class _ReconPinnedTableState extends State<ReconPinnedTable> {
  final _hHeader = ScrollController();
  final _hBody = ScrollController();
  final _vertical = ScrollController();
  final _hOffset = ValueNotifier<double>(0);
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hHeader.addListener(_syncFromHeader);
    _hBody.addListener(_syncFromBody);
  }

  @override
  void dispose() {
    _hHeader
      ..removeListener(_syncFromHeader)
      ..dispose();
    _hBody
      ..removeListener(_syncFromBody)
      ..dispose();
    _vertical.dispose();
    _hOffset.dispose();
    super.dispose();
  }

  void _syncFromHeader() {
    if (_hHeader.hasClients && _hOffset.value != _hHeader.offset) {
      _hOffset.value = _hHeader.offset;
    }
    _jump(_hHeader, _hBody);
  }

  void _syncFromBody() => _jump(_hBody, _hHeader);

  void _jump(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    if (!to.position.hasContentDimensions) return;
    final next = from.offset.clamp(
      to.position.minScrollExtent,
      to.position.maxScrollExtent,
    );
    if (next == to.offset) return;
    _syncing = true;
    to.jumpTo(next);
    _syncing = false;
  }

  void _scrollH(double delta) {
    if (!_hHeader.hasClients || !_hHeader.position.hasContentDimensions) {
      return;
    }
    final next = (_hHeader.offset + delta).clamp(
      _hHeader.position.minScrollExtent,
      _hHeader.position.maxScrollExtent,
    );
    if (next != _hHeader.offset) _hHeader.jumpTo(next);
  }

  void _onPointerSignal(
    PointerSignalEvent event, [
    ScrollController? controller,
  ]) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dx;
    if (delta == 0) return;
    if (widget._virtualized) {
      _scrollH(delta);
      return;
    }
    if (controller == null || !controller.hasClients) return;
    if (!controller.position.hasContentDimensions) return;
    final next = (controller.offset + delta).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next != controller.offset) controller.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _ReconHScrollBehavior(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (widget._virtualized && constraints.hasBoundedHeight) {
            return _virtualizedTable();
          }
          return _legacyTable(constraints);
        },
      ),
    );
  }

  Widget _virtualizedTable() {
    final count = widget.rowCount!;
    final header = _band(
      height: widget.headerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.leadingHeader != null) widget.leadingHeader!,
          Expanded(
            child: _hPane(
              controller: _hHeader,
              child: widget.dataHeader,
              listenSignals: false,
            ),
          ),
          if (widget.trailingHeader != null) widget.trailingHeader!,
        ],
      ),
    );
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(HorizontalDragGestureRecognizer.new, (instance) {
                instance.onUpdate = (details) => _scrollH(-details.delta.dx);
              }),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Expanded(
              child: Scrollbar(
                controller: _vertical,
                thumbVisibility: true,
                interactive: true,
                child: ListView.builder(
                  controller: _vertical,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  itemCount: count,
                  itemExtentBuilder: (index, _) => widget.rowHeight!(index),
                  itemBuilder: (context, index) {
                    return RepaintBoundary(
                      child: SizedBox(
                        height: widget.rowHeight!(index),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.leadingRowBuilder != null)
                              widget.leadingRowBuilder!(context, index),
                            Expanded(child: _shiftedDataRow(context, index)),
                            if (widget.trailingRowBuilder != null)
                              widget.trailingRowBuilder!(context, index),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftedDataRow(BuildContext context, int index) {
    final row = widget.dataRowBuilder!(context, index);
    return ClipRect(
      child: ValueListenableBuilder<double>(
        valueListenable: _hOffset,
        child: SizedBox(width: widget.dataWidth, child: row),
        builder: (context, offset, child) {
          return OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: widget.dataWidth,
            maxWidth: widget.dataWidth,
            child: Transform.translate(
              offset: Offset(-offset, 0),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _legacyTable(BoxConstraints constraints) {
    final header = _band(
      height: widget.headerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.leadingHeader != null) widget.leadingHeader!,
          Expanded(
            child: _hPane(controller: _hHeader, child: widget.dataHeader),
          ),
          if (widget.trailingHeader != null) widget.trailingHeader!,
        ],
      ),
    );
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.leadingBody != null) widget.leadingBody!,
        Expanded(
          child: Scrollbar(
            controller: _hBody,
            thumbVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: _hPane(
              controller: _hBody,
              padding: const EdgeInsets.only(bottom: 10),
              child: widget.dataBody,
            ),
          ),
        ),
        if (widget.trailingBody != null) widget.trailingBody!,
      ],
    );

    if (constraints.hasBoundedHeight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Expanded(
            child: Scrollbar(
              controller: _vertical,
              thumbVisibility: true,
              interactive: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.vertical,
              child: SingleChildScrollView(
                controller: _vertical,
                primary: false,
                physics: const AlwaysScrollableScrollPhysics(),
                child: body,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, body],
    );
  }

  Widget _hPane({
    required ScrollController controller,
    required Widget child,
    EdgeInsetsGeometry? padding,
    bool listenSignals = true,
  }) {
    final pane = SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      primary: false,
      padding: padding,
      child: SizedBox(width: widget.dataWidth, child: child),
    );
    return ScrollConfiguration(
      behavior: const _ReconHScrollBehavior(),
      child: listenSignals
          ? Listener(
              onPointerSignal: (e) => _onPointerSignal(e, controller),
              child: pane,
            )
          : pane,
    );
  }

  Widget _band({required double height, required Widget child}) {
    return Material(
      color: const Color(0xFFF6F7F9),
      elevation: 0.5,
      shadowColor: Colors.black26,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFF6F7F9),
          border: Border(
            bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
          ),
        ),
        child: SizedBox(height: height, child: child),
      ),
    );
  }
}

class _ReconHScrollBehavior extends MaterialScrollBehavior {
  const _ReconHScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
