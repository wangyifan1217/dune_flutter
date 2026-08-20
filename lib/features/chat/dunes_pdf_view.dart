import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/util/friendly_error.dart';

/// 跨平台 PDF 预览。
///
/// Windows 不支持 [PdfViewPinch]。桌面端改为按 DPR/缩放倍率栅格化 PNG，
/// 并提供放大缩小；移动端继续用 pinch。
class DunesPdfView extends StatefulWidget {
  const DunesPdfView({
    super.key,
    required this.bytes,
    this.padding = 8,
  });

  final Uint8List bytes;
  final double padding;

  @override
  State<DunesPdfView> createState() => _DunesPdfViewState();
}

class _DunesPdfViewState extends State<DunesPdfView> {
  PdfControllerPinch? _pinchController;
  PdfDocument? _desktopDocument;
  String? _error;
  bool _loading = true;
  double _zoom = 1;
  int _pageCount = 0;
  double _pageAspect = 1.414;
  Future<void> _renderLock = Future.value();

  static const _minZoom = 0.75;
  static const _maxZoom = 3.0;
  static const _zoomStep = 0.25;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant DunesPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _pinchController?.dispose();
    unawaited(_desktopDocument?.close());
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
      _zoom = 1;
    });
    _pinchController?.dispose();
    _pinchController = null;
    _renderLock = Future.value();
    final oldDoc = _desktopDocument;
    _desktopDocument = null;
    if (oldDoc != null) unawaited(oldDoc.close());
    try {
      final bytes = Uint8List.fromList(widget.bytes);
      if (bytes.length < 5 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw Exception('文件不是有效的 PDF');
      }
      final document = await PdfDocument.openData(bytes);
      if (!mounted) {
        await document.close();
        return;
      }
      if (isDesktopCommOnly) {
        final first = await document.getPage(1);
        final aspect = first.width <= 0 ? 1.414 : first.height / first.width;
        await first.close();
        _desktopDocument = document;
        _pageCount = document.pagesCount;
        _pageAspect = aspect;
      } else {
        _pinchController = PdfControllerPinch(
          document: Future<PdfDocument>.value(document),
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: 'PDF 加载失败');
      });
    }
  }

  void _setZoom(double next) {
    final zoom = ((next * 100).round() / 100).clamp(_minZoom, _maxZoom);
    if ((zoom - _zoom).abs() < 0.001) return;
    setState(() => _zoom = zoom);
  }

  void _nudgeZoom(double delta) => _setZoom(_zoom + delta);

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (isDesktopCommOnly) {
      final document = _desktopDocument;
      if (document == null) return const SizedBox.shrink();
      return _buildDesktopReader(document);
    }
    final controller = _pinchController;
    if (controller == null) return const SizedBox.shrink();
    return PdfViewPinch(
      controller: controller,
      padding: widget.padding,
      scrollDirection: Axis.vertical,
      minScale: 1,
      maxScale: 4,
    );
  }

  Widget _buildDesktopReader(PdfDocument document) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true):
            () => _nudgeZoom(_zoomStep),
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            () => _nudgeZoom(-_zoomStep),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            () => _setZoom(1),
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            () => _nudgeZoom(_zoomStep),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            () => _nudgeZoom(-_zoomStep),
      },
      child: Focus(
        autofocus: true,
        child: Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent) return;
        if (!HardwareKeyboard.instance.isControlPressed) return;
        _nudgeZoom(signal.scrollDelta.dy > 0 ? -_zoomStep : _zoomStep);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewWidth = math.max(120.0, constraints.maxWidth);
                final pageWidth = viewWidth * _zoom;
                return Scrollbar(
                  child: ListView.separated(
                    padding: EdgeInsets.all(widget.padding),
                    itemCount: _pageCount,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return Align(
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _DesktopPdfPage(
                            document: document,
                            pageNumber: index + 1,
                            aspect: _pageAspect,
                            displayWidth: pageWidth,
                            devicePixelRatio:
                                MediaQuery.devicePixelRatioOf(context),
                            renderLock: _enqueueRender,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _ZoomBar(
              zoom: _zoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onZoomOut: () => _nudgeZoom(-_zoomStep),
              onZoomIn: () => _nudgeZoom(_zoomStep),
              onReset: () => _setZoom(1),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Future<T> _enqueueRender<T>(Future<T> Function() task) {
    final next = _renderLock.then((_) => task());
    _renderLock = next.then((_) {}, onError: (_) {});
    return next;
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '缩小',
              onPressed: zoom <= minZoom + 0.001 ? null : onZoomOut,
              icon: const Icon(Icons.remove, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            TextButton(
              onPressed: zoom == 1 ? null : onReset,
              child: Text(
                '${(zoom * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              tooltip: '放大',
              onPressed: zoom >= maxZoom - 0.001 ? null : onZoomIn,
              icon: const Icon(Icons.add, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPdfPage extends StatefulWidget {
  const _DesktopPdfPage({
    required this.document,
    required this.pageNumber,
    required this.aspect,
    required this.displayWidth,
    required this.devicePixelRatio,
    required this.renderLock,
  });

  final PdfDocument document;
  final int pageNumber;
  final double aspect;
  final double displayWidth;
  final double devicePixelRatio;
  final Future<T> Function<T>(Future<T> Function() task) renderLock;

  @override
  State<_DesktopPdfPage> createState() => _DesktopPdfPageState();
}

class _DesktopPdfPageState extends State<_DesktopPdfPage> {
  Uint8List? _bytes;
  bool _loading = true;
  int _renderGen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_render());
  }

  @override
  void didUpdateWidget(covariant _DesktopPdfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.pageNumber != widget.pageNumber ||
        (oldWidget.displayWidth - widget.displayWidth).abs() > 8 ||
        (oldWidget.devicePixelRatio - widget.devicePixelRatio).abs() > 0.05) {
      unawaited(_render());
    }
  }

  Future<void> _render() async {
    final gen = ++_renderGen;
    setState(() => _loading = _bytes == null);
    try {
      final bytes = await widget.renderLock(() async {
        final page = await widget.document.getPage(widget.pageNumber);
        try {
          if (!mounted || gen != _renderGen) return null;
          final dpr = widget.devicePixelRatio.clamp(1.0, 3.0);
          final targetWidth = (widget.displayWidth * dpr).clamp(720, 4200);
          final scale = targetWidth / math.max(page.width, 1);
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          return image?.bytes;
        } finally {
          await page.close();
        }
      });
      if (!mounted || gen != _renderGen) return;
      setState(() {
        if (bytes != null) _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _renderGen) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.displayWidth * widget.aspect;
    final bytes = _bytes;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: widget.displayWidth,
        height: height,
        child: bytes == null
            ? Center(
                child: _loading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Text('第 ${widget.pageNumber} 页加载失败'),
              )
            : Image.memory(
                bytes,
                width: widget.displayWidth,
                height: height,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
