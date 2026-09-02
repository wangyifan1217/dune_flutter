import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/dunes_pdf_view.dart';

Future<void> showContractKbPdfPreview({
  required BuildContext context,
  required String fileName,
  required Uint8List bytes,
  String watermark = '',
}) {
  final page = ContractKbPdfPreviewPage(
    fileName: fileName,
    bytes: bytes,
    watermark: watermark,
  );
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(1280, size.width * 0.94),
              maxHeight: size.height * 0.92,
              minWidth: 640,
              minHeight: 520,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: page,
            ),
          ),
        );
      },
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => page),
  );
}

class ContractKbPdfPreviewPage extends StatelessWidget {
  const ContractKbPdfPreviewPage({
    super.key,
    required this.fileName,
    required this.bytes,
    this.watermark = '',
  });

  final String fileName;
  final Uint8List bytes;
  final String watermark;

  @override
  Widget build(BuildContext context) {
    final valid = bytes.length >= 5 &&
        String.fromCharCodes(bytes.take(5)) == '%PDF-';
    final viewer = valid
        ? DunesPdfView(bytes: bytes, padding: 10)
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                friendlyErrorText(
                  Exception('文件不是有效的 PDF'),
                  fallback: '暂不支持预览该文件',
                ),
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: DunesColors.text2,
                ),
              ),
            ),
          );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: watermark.trim().isEmpty
          ? viewer
          : Stack(
              children: [
                Positioned.fill(child: viewer),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PdfPreviewWatermarkPainter(
                        text: watermark.trim(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PdfPreviewWatermarkPainter extends CustomPainter {
  _PdfPreviewWatermarkPainter({required this.text});

  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.55);
    canvas.translate(-size.width, -size.height);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF3A3A3A).withValues(alpha: 0.14),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const dx = 220.0;
    const dy = 130.0;
    for (var y = 0.0; y < size.height * 2; y += dy) {
      for (var x = 0.0; x < size.width * 2; x += dx) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PdfPreviewWatermarkPainter oldDelegate) =>
      oldDelegate.text != text;
}
