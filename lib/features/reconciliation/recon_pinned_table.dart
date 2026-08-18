import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 表头固定：有限高度时列头钉在顶部，仅表体竖向滚动；表头与表体横向滚动同步。
class ReconPinnedTable extends StatefulWidget {
  const ReconPinnedTable({
    super.key,
    required this.headerHeight,
    required this.dataWidth,
    required this.dataHeader,
    required this.dataBody,
    this.leadingHeader,
    this.leadingBody,
    this.trailingHeader,
    this.trailingBody,
  });

  final double headerHeight;
  final double dataWidth;
  final Widget dataHeader;
  final Widget dataBody;
  final Widget? leadingHeader;
  final Widget? leadingBody;
  final Widget? trailingHeader;
  final Widget? trailingBody;

  @override
  State<ReconPinnedTable> createState() => _ReconPinnedTableState();
}

class _ReconPinnedTableState extends State<ReconPinnedTable> {
  final _hHeader = ScrollController();
  final _hBody = ScrollController();
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
    super.dispose();
  }

  void _syncFromHeader() => _jump(_hHeader, _hBody);

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

  void _onPointerSignal(PointerSignalEvent event, ScrollController controller) {
    if (event is! PointerScrollEvent || !controller.hasClients) return;
    final delta = event.scrollDelta.dx;
    if (delta == 0 || !controller.position.hasContentDimensions) return;
    final next = (controller.offset + delta).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next != controller.offset) controller.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final header = _band(
      height: widget.headerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.leadingHeader != null) widget.leadingHeader!,
          Expanded(child: _hPane(controller: _hHeader, child: widget.dataHeader)),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  child: body,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, body],
        );
      },
    );
  }

  Widget _hPane({
    required ScrollController controller,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return ScrollConfiguration(
      behavior: const _ReconHScrollBehavior(),
      child: Listener(
        onPointerSignal: (e) => _onPointerSignal(e, controller),
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          primary: false,
          padding: padding,
          child: SizedBox(width: widget.dataWidth, child: child),
        ),
      ),
    );
  }

  Widget _band({required double height, required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF6F7F9),
        border: Border(
          bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(height: height, child: child),
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
  };
}
