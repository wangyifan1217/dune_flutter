import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/util/friendly_error.dart';

/// 跨平台 PDF 预览：桌面用 [PdfView]，移动端用 [PdfViewPinch]。
///
/// Windows 不支持 PdfViewPinch，会抛 UnimplementedError。
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
  PdfController? _desktopController;
  PdfControllerPinch? _pinchController;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _desktopController?.dispose();
    _pinchController?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _desktopController?.dispose();
    _pinchController?.dispose();
    _desktopController = null;
    _pinchController = null;
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
      final docFuture = Future<PdfDocument>.value(document);
      if (isDesktopCommOnly) {
        _desktopController = PdfController(document: docFuture);
      } else {
        _pinchController = PdfControllerPinch(document: docFuture);
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
      final controller = _desktopController;
      if (controller == null) return const SizedBox.shrink();
      return PdfView(
        controller: controller,
        scrollDirection: Axis.vertical,
      );
    }
    final controller = _pinchController;
    if (controller == null) return const SizedBox.shrink();
    return PdfViewPinch(
      controller: controller,
      padding: widget.padding,
      scrollDirection: Axis.vertical,
    );
  }
}
