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
}) {
  final page = ContractKbPdfPreviewPage(fileName: fileName, bytes: bytes);
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
  });

  final String fileName;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final valid = bytes.length >= 5 &&
        String.fromCharCodes(bytes.take(5)) == '%PDF-';
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
      body: valid
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
            ),
    );
  }
}
