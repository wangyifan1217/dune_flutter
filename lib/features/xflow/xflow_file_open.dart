import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/dunes_pdf_view.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';
import 'xflow_service.dart';

bool xflowItemIsPdf(Map<String, dynamic> item, String fileName) {
  final mime = (item['mimeType'] ?? '').toString().trim().toLowerCase();
  if (mime == 'application/pdf') return true;
  return fileName.trim().toLowerCase().endsWith('.pdf');
}

bool xflowItemIsImage(Map<String, dynamic> item, String fileName) {
  final mime = (item['mimeType'] ?? '').toString().trim().toLowerCase();
  if (mime.startsWith('image/')) return true;
  return RegExp(
    r'\.(jpg|jpeg|png|heic|heif|gif|webp|bmp)$',
  ).hasMatch(fileName.trim().toLowerCase());
}

String xflowAttachmentFileName(Map<String, dynamic> item) {
  final name = (item['fileName'] ?? item['name'] ?? '未命名文件').toString().trim();
  return name.isEmpty ? '未命名文件' : name;
}

String xflowAttachmentCacheKey(Map<String, dynamic> item, {String url = ''}) {
  final key = (item['objectKey'] ?? item['url'] ?? url).toString().trim();
  return key;
}

/// 本地是否已有该审批附件缓存（对齐微盘「已下载」状态）。
Future<bool> isXflowAttachmentDownloaded(Map<String, dynamic> item) async {
  if (kIsWeb) return false;
  final fileName = xflowAttachmentFileName(item);
  final cacheKey = xflowAttachmentCacheKey(item);
  if (cacheKey.isEmpty) return false;
  final path = await file_dl.findCachedChatFile(cacheKey, fileName);
  return path != null && path.isNotEmpty;
}

/// 下载审批附件到本地（不强制打开）；[force] 为 true 时先清缓存再下。
/// 成功返回本地路径；失败返回 null。
Future<String?> downloadXflowAttachment({
  required BuildContext context,
  required XflowService service,
  required Map<String, dynamic> item,
  bool force = false,
  bool reveal = true,
}) async {
  final fileName = xflowAttachmentFileName(item);
  final url = await service.resolveFileUrl(item);
  if (url.isEmpty) {
    if (context.mounted) {
      showDunesToast(context, '无法获取文件链接', kind: DunesToastKind.error);
    }
    return null;
  }
  final cacheKey = xflowAttachmentCacheKey(item, url: url);

  if (kIsWeb) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showDunesToast(context, '无法打开下载链接', kind: DunesToastKind.error);
      }
      return null;
    }
    return url;
  }

  if (!force && cacheKey.isNotEmpty) {
    final cached = await file_dl.findCachedChatFile(cacheKey, fileName);
    if (cached != null && cached.isNotEmpty) {
      if (context.mounted) {
        showDunesToast(context, '已下载到本地');
      }
      if (reveal) {
        try {
          await file_dl.revealLocalFile(cached);
        } catch (_) {}
      }
      return cached;
    }
  }

  if (force && cacheKey.isNotEmpty) {
    try {
      await file_dl.deleteCachedChatFile(cacheKey, fileName);
    } catch (_) {}
  }

  if (context.mounted) {
    showDunesToast(context, force ? '正在重新下载…' : '正在下载…');
  }
  try {
    final path = await file_dl.openUrlAsFile(
      url,
      fileName,
      cacheKey: cacheKey.isEmpty ? null : cacheKey,
    );
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        showDunesToast(context, '下载失败', kind: DunesToastKind.error);
      }
      return null;
    }
    if (context.mounted) {
      showDunesToast(context, force ? '已重新下载到本地' : '已下载到本地');
    }
    if (reveal) {
      try {
        await file_dl.revealLocalFile(path);
      } catch (_) {}
    }
    return path;
  } catch (e) {
    if (context.mounted) {
      showDunesToast(
        context,
        '下载失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
    return null;
  }
}

/// 审批附件打开：对齐企业微盘（PC 系统打开；APP PDF/图片应用内预览；失败可定位本地文件）。
Future<void> openXflowAttachment({
  required BuildContext context,
  required XflowService service,
  required Map<String, dynamic> item,
  bool preferPreview = false,
}) async {
  final fileName = xflowAttachmentFileName(item);
  final url = await service.resolveFileUrl(item);
  if (url.isEmpty) {
    if (context.mounted) {
      showDunesToast(context, '无法获取文件链接', kind: DunesToastKind.error);
    }
    return;
  }
  final cacheKey = xflowAttachmentCacheKey(item, url: url);

  if (kIsWeb) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showDunesToast(context, '无法打开链接', kind: DunesToastKind.error);
      }
    }
    return;
  }

  if (!context.mounted) return;

  // APP：PDF / 图片优先应用内预览（与微盘一致）。
  if (!isDesktopCommOnly &&
      preferPreview &&
      (xflowItemIsPdf(item, fileName) || xflowItemIsImage(item, fileName))) {
    final ok = await _previewInApp(
      context: context,
      url: url,
      fileName: fileName,
      isPdf: xflowItemIsPdf(item, fileName),
    );
    if (ok) return;
  }

  // PC：图片用应用内小窗预览（系统照片查看器默认窗口过大）；失败回退系统打开。
  if (isDesktopCommOnly && preferPreview && xflowItemIsImage(item, fileName)) {
    if (!context.mounted) return;
    final ok = await _previewImageDialogOnDesktop(
      context: context,
      url: url,
      fileName: fileName,
      cacheKey: cacheKey,
    );
    if (ok) return;
  }

  if (!context.mounted) return;
  await _openWithSystem(
    context: context,
    url: url,
    fileName: fileName,
    cacheKey: cacheKey,
  );
}

/// PC 图片小窗预览：约 60% 屏宽（上限 640）居中弹层，支持缩放；
/// 右上角可切换系统应用打开原图。
Future<bool> _previewImageDialogOnDesktop({
  required BuildContext context,
  required String url,
  required String fileName,
  required String cacheKey,
}) async {
  Uint8List bytes;
  try {
    final client = http.Client();
    try {
      final resp = await client.get(Uri.parse(url));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return false;
      }
      bytes = Uint8List.fromList(resp.bodyBytes);
      if (bytes.isEmpty) return false;
    } finally {
      client.close();
    }
  } catch (_) {
    return false;
  }
  if (!context.mounted) return false;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final maxW = size.width * 0.6 < 640 ? size.width * 0.6 : 640.0;
      final maxH = size.height * 0.72;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW,
            maxHeight: maxH,
            minWidth: 280,
            minHeight: 200,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '用系统应用打开',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          unawaited(
                            _openWithSystem(
                              context: context,
                              url: url,
                              fileName: fileName,
                              cacheKey: cacheKey,
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ColoredBox(
                    color: const Color(0xFFF3F4F6),
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return true;
}

Future<void> _openWithSystem({
  required BuildContext context,
  required String url,
  required String fileName,
  required String cacheKey,
}) async {
  try {
    if (cacheKey.isNotEmpty) {
      final cached = await file_dl.findCachedChatFile(cacheKey, fileName);
      if (cached != null && cached.isNotEmpty) {
        try {
          await file_dl.openLocalFile(cached);
          return;
        } catch (_) {}
      }
    }
    if (context.mounted) {
      showDunesToast(
        context,
        isDesktopCommOnly ? '正在打开 $fileName…' : '正在准备用其他应用打开…',
      );
    }
    final path = await file_dl.openUrlAsFile(
      url,
      fileName,
      cacheKey: cacheKey.isEmpty ? null : cacheKey,
    );
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        showDunesToast(
          context,
          '文件已保存，但无法自动打开',
          kind: DunesToastKind.error,
        );
      }
      return;
    }
    try {
      await file_dl.openLocalFile(path);
    } catch (_) {
      if (context.mounted) {
        showDunesToast(context, '已下载到本地，请用其他应用打开');
      }
      try {
        await file_dl.revealLocalFile(path);
      } catch (_) {}
    }
  } catch (e) {
    if (context.mounted) {
      showDunesToast(
        context,
        '打开失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }
}

Future<bool> _previewInApp({
  required BuildContext context,
  required String url,
  required String fileName,
  required bool isPdf,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: DunesColors.accent,
        ),
      ),
    ),
  );
  try {
    final client = http.Client();
    try {
      final resp = await client.get(Uri.parse(url));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('下载失败（HTTP ${resp.statusCode}）');
      }
      final bytes = Uint8List.fromList(resp.bodyBytes);
      if (bytes.isEmpty) throw Exception('文件内容为空');
      if (!context.mounted) return false;
      Navigator.of(context, rootNavigator: true).pop();
      if (isPdf) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => _XflowPdfPreviewPage(
              fileName: fileName,
              bytes: bytes,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => _XflowImagePreviewPage(
              fileName: fileName,
              bytes: bytes,
            ),
          ),
        );
      }
      return true;
    } finally {
      client.close();
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    return false;
  }
}

class _XflowPdfPreviewPage extends StatelessWidget {
  const _XflowPdfPreviewPage({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: DunesPdfView(bytes: bytes, padding: 8),
    );
  }
}

class _XflowImagePreviewPage extends StatelessWidget {
  const _XflowImagePreviewPage({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
