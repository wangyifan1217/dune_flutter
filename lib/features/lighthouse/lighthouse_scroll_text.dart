import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Whether [painter] would clip/ellipsis inside [maxWidth].
///
/// Single-line text is measured unconstrained so a truncated layout (width ==
/// maxWidth) is not mistaken for a fit.
bool lighthouseTextPainterOverflows(TextPainter painter, double maxWidth) {
  if (!maxWidth.isFinite || maxWidth <= 0) return false;
  final maxLines = painter.maxLines;
  if (maxLines == null || maxLines <= 1) {
    painter.layout();
    return painter.width > maxWidth + 0.5;
  }
  painter.layout(maxWidth: maxWidth);
  return painter.didExceedMaxLines;
}

bool lighthousePlainTextOverflows({
  required String text,
  TextStyle? style,
  required double maxWidth,
  TextDirection textDirection = TextDirection.ltr,
  int maxLines = 1,
  TextAlign textAlign = TextAlign.start,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textAlign: textAlign,
    textDirection: textDirection,
    ellipsis: '…',
  );
  try {
    return lighthouseTextPainterOverflows(painter, maxWidth);
  } finally {
    painter.dispose();
  }
}

bool _spanHasWidget(InlineSpan span) {
  if (span is WidgetSpan) return true;
  if (span is TextSpan && span.children != null) {
    return span.children!.any(_spanHasWidget);
  }
  return false;
}

/// Truncated lighthouse copy: keep one line, drag/swipe right to read the rest.
///
/// Implemented as a [RenderBox] so it can sit inside [IntrinsicHeight] (Hero
/// 规模/成本/利润板). [LayoutBuilder] cannot.
class LhScrollText extends StatelessWidget {
  const LhScrollText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    return LhScrollRichText(
      text: TextSpan(text: data, style: style),
      strutStyle: strutStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}

/// Same as [LhScrollText] for [RichText] / [Text.rich].
class LhScrollRichText extends StatelessWidget {
  const LhScrollRichText({
    super.key,
    required this.text,
    this.strutStyle,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap,
  });

  final InlineSpan text;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final align = textAlign ?? TextAlign.start;
    final lines = maxLines ?? 1;
    if (_spanHasWidget(text)) {
      return RichText(
        text: text,
        strutStyle: strutStyle,
        textAlign: align,
        maxLines: lines,
        overflow: overflow,
        softWrap: softWrap ?? true,
      );
    }
    return _LhPanPlainText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [text],
      ),
      textDirection: Directionality.of(context),
      textAlign: align,
      strutStyle: strutStyle,
    );
  }
}

class _LhPanPlainText extends LeafRenderObjectWidget {
  const _LhPanPlainText({
    required this.text,
    required this.textDirection,
    required this.textAlign,
    this.strutStyle,
  });

  final InlineSpan text;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final StrutStyle? strutStyle;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLhPanPlainText(
      text: text,
      textDirection: textDirection,
      textAlign: textAlign,
      strutStyle: strutStyle,
      gestureSettings: MediaQuery.maybeOf(context)?.gestureSettings,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLhPanPlainText renderObject,
  ) {
    renderObject
      ..text = text
      ..textDirection = textDirection
      ..textAlign = textAlign
      ..strutStyle = strutStyle
      ..gestureSettings = MediaQuery.maybeOf(context)?.gestureSettings;
  }
}

class _RenderLhPanPlainText extends RenderBox {
  _RenderLhPanPlainText({
    required InlineSpan text,
    required TextDirection textDirection,
    required TextAlign textAlign,
    StrutStyle? strutStyle,
    DeviceGestureSettings? gestureSettings,
  }) : _text = text,
       _textDirection = textDirection,
       _textAlign = textAlign,
       _strutStyle = strutStyle {
    _painter = TextPainter(
      text: text,
      textDirection: textDirection,
      textAlign: textAlign,
      maxLines: 1,
      strutStyle: strutStyle,
    );
    _drag = HorizontalDragGestureRecognizer(debugOwner: this)
      ..gestureSettings = gestureSettings
      ..supportedDevices = const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }
      ..onUpdate = _onDragUpdate;
  }

  late final TextPainter _painter;
  HorizontalDragGestureRecognizer? _drag;
  double _pan = 0;

  InlineSpan _text;
  set text(InlineSpan value) {
    if (_text == value) return;
    _text = value;
    _pan = 0;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  TextAlign _textAlign;
  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsLayout();
  }

  StrutStyle? _strutStyle;
  set strutStyle(StrutStyle? value) {
    if (_strutStyle == value) return;
    _strutStyle = value;
    markNeedsLayout();
  }

  set gestureSettings(DeviceGestureSettings? value) {
    _drag?.gestureSettings = value;
  }

  void _syncPainter() {
    _painter
      ..text = _text
      ..textDirection = _textDirection
      ..textAlign = _textAlign
      ..maxLines = 1
      ..strutStyle = _strutStyle;
    _painter.layout();
  }

  double get _minPan {
    final overflow = _painter.width - size.width;
    return overflow > 0.5 ? -overflow : 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_pan + details.delta.dx).clamp(_minPan, 0.0);
    if (next == _pan) return;
    _pan = next;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _drag ??= HorizontalDragGestureRecognizer(debugOwner: this)
      ..onUpdate = _onDragUpdate
      ..supportedDevices = const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
  }

  @override
  void dispose() {
    _drag?.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    _syncPainter();
    return _painter.width;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    _syncPainter();
    return _painter.height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _syncPainter();
    return constraints.constrain(Size(_painter.width, _painter.height));
  }

  @override
  void performLayout() {
    _syncPainter();
    size = constraints.constrain(Size(_painter.width, _painter.height));
    _pan = _pan.clamp(_minPan, 0.0);
  }

  @override
  bool hitTestSelf(Offset position) => size.contains(position);

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _drag?.addPointer(event);
    } else if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      final next = (_pan - delta).clamp(_minPan, 0.0);
      if (next == _pan) return;
      _pan = next;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.save();
    context.canvas.clipRect(offset & size);
    _painter.paint(context.canvas, offset + Offset(_pan, 0));
    context.canvas.restore();
  }

  @override
  bool get isRepaintBoundary => true;
}
