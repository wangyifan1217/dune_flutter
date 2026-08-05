import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_type_icon.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';
import 'drive_subpages.dart';
import 'native_drive_models.dart';
import 'native_drive_service.dart';

/// 微盘主色（与空间列表/按钮一致）。
const _driveBlue = Color(0xFF3B82F6);

bool driveItemIsPdf(DriveItem item) {
  final mime = item.mimeType.trim().toLowerCase();
  if (mime == 'application/pdf') return true;
  return item.name.trim().toLowerCase().endsWith('.pdf');
}

/// 对齐 IM：PDF 应用内预览；其它文件 PC 系统打开 / APP 文件页。
Future<void> openDriveFile({
  required BuildContext context,
  required NativeDriveService service,
  required DriveItem item,
  AuthSession? session,
}) async {
  if (item.isFolder) return;
  final fileName = item.name.trim().isEmpty ? '文件' : item.name.trim();
  final cacheKey = 'drive-item-${item.id}';

  // PDF：PC 用系统阅读器（无微盘内嵌框）；APP 全屏预览。
  if (driveItemIsPdf(item)) {
    if (isDesktopCommOnly) {
      await _openOnDesktop(
        context: context,
        service: service,
        item: item,
        fileName: fileName,
        cacheKey: cacheKey,
      );
      return;
    }
    await _openPdfPreviewFullscreen(
      context: context,
      service: service,
      item: item,
      session: session,
    );
    return;
  }

  if (isDesktopCommOnly) {
    await _openOnDesktop(
      context: context,
      service: service,
      item: item,
      fileName: fileName,
      cacheKey: cacheKey,
    );
    return;
  }

  if (!context.mounted) return;
  await showDriveFilePreview(
    context: context,
    service: service,
    item: item,
    fileName: fileName,
    cacheKey: cacheKey,
  );
}

/// APP：全屏打开 PDF，避免走微盘弹层内框。
Future<void> _openPdfPreviewFullscreen({
  required BuildContext context,
  required NativeDriveService service,
  required DriveItem item,
  AuthSession? session,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: _driveBlue),
      ),
    ),
  );
  try {
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        service.contentUri(item.id, inline: true),
      );
      request.headers.addAll(service.contentHeaders());
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('下载失败（HTTP ${response.statusCode}）');
      }
      final bytes = Uint8List.fromList(await response.stream.toBytes());
      if (bytes.isEmpty) throw Exception('文件内容为空');
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DrivePreviewPage(
            item: item,
            bytes: bytes,
            session: session,
            service: service,
          ),
        ),
      );
    } finally {
      client.close();
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: 'PDF 预览失败'),
        kind: DunesToastKind.error,
      );
    }
  }
}

Future<void> _openOnDesktop({
  required BuildContext context,
  required NativeDriveService service,
  required DriveItem item,
  required String fileName,
  required String cacheKey,
}) async {
  final cached = await file_dl.findCachedDriveFile(
    fileName,
    cacheKey: cacheKey,
  );
  if (cached != null && cached.isNotEmpty) {
    try {
      await file_dl.openLocalFile(cached);
      return;
    } catch (_) {}
  }
  try {
    final path = await _downloadDriveFile(
      service: service,
      item: item,
      fileName: fileName,
      cacheKey: cacheKey,
    );
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        showDunesCenterToast(
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
        showDunesCenterToast(context, '已下载到本地，请用其他应用打开');
      }
      try {
        await file_dl.revealLocalFile(path);
      } catch (_) {}
    }
  } catch (e) {
    if (context.mounted) {
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '打开文件失败'),
        kind: DunesToastKind.error,
      );
    }
  }
}

Future<String?> _downloadDriveFile({
  required NativeDriveService service,
  required DriveItem item,
  required String fileName,
  required String cacheKey,
  void Function(double progress)? onProgress,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', service.contentUri(item.id));
    request.headers.addAll(service.contentHeaders());
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载失败（HTTP ${response.statusCode}）');
    }
    final total = response.contentLength ?? item.sizeBytes;
    final chunks = <int>[];
    var received = 0;
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call((received / total).clamp(0.0, 0.99));
      }
    }
    onProgress?.call(1);
    final bytes = Uint8List.fromList(chunks);
    if (bytes.isEmpty) throw Exception('文件内容为空');
    return file_dl.saveBytesAsDriveFile(
      bytes,
      fileName,
      cacheKey: cacheKey,
    );
  } finally {
    client.close();
  }
}

Future<void> showDriveFilePreview({
  required BuildContext context,
  required NativeDriveService service,
  required DriveItem item,
  required String fileName,
  required String cacheKey,
}) {
  final page = _DriveFilePreviewPage(
    service: service,
    item: item,
    fileName: fileName,
    cacheKey: cacheKey,
  );
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: size.height * 0.82,
              minWidth: 400,
              minHeight: 420,
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

/// APP：对齐 IM [ChatFilePreviewPage]（下载 / 用其他应用打开）。
class _DriveFilePreviewPage extends StatefulWidget {
  const _DriveFilePreviewPage({
    required this.service,
    required this.item,
    required this.fileName,
    required this.cacheKey,
  });

  final NativeDriveService service;
  final DriveItem item;
  final String fileName;
  final String cacheKey;

  @override
  State<_DriveFilePreviewPage> createState() => _DriveFilePreviewPageState();
}

class _DriveFilePreviewPageState extends State<_DriveFilePreviewPage> {
  bool _busy = false;
  double _progress = 0;
  String? _localPath;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveCached());
  }

  Future<void> _resolveCached() async {
    final path = await file_dl.findCachedDriveFile(
      widget.fileName,
      cacheKey: widget.cacheKey,
    );
    if (!mounted) return;
    setState(() {
      _localPath = path;
      _status = path == null ? null : '已下载到本地';
    });
  }

  Future<String?> _ensureDownloaded({bool force = false}) async {
    if (!force && _localPath != null && _localPath!.isNotEmpty) {
      return _localPath;
    }
    if (_busy) return null;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = force ? '重新下载中…' : '下载中…';
    });
    try {
      final path = await _downloadDriveFile(
        service: widget.service,
        item: widget.item,
        fileName: widget.fileName,
        cacheKey: widget.cacheKey,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return path;
      if (path != null && path.isNotEmpty) {
        try {
          await widget.service.markDownloaded(
            widget.item.id,
            version: widget.item.version,
          );
        } catch (_) {}
      }
      if (!mounted) return path;
      setState(() {
        _localPath = path;
        _status = path == null ? '下载失败' : '已下载到本地';
        _busy = false;
      });
      return path;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _busy = false;
        _status = friendlyErrorText(e, fallback: '下载失败');
      });
      return null;
    }
  }

  Future<void> _downloadOnly() async {
    await _ensureDownloaded(force: _localPath != null);
  }

  Future<void> _openWithOtherApp() async {
    final path = await _ensureDownloaded();
    if (path == null || path.isEmpty || !mounted) return;
    try {
      await file_dl.openLocalFile(path);
    } catch (e) {
      if (!mounted) return;
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '无法打开文件'),
        kind: DunesToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = _localPath != null && _localPath!.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF191919)),
        ),
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DunesTypography.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF191919),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF191919)),
            onSelected: (value) {
              if (value == 'download') unawaited(_downloadOnly());
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'download',
                enabled: !_busy,
                child: Text(downloaded ? '重新下载' : '下载'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              ChatFileTypeIcon(fileName: widget.fileName, size: 64),
              const SizedBox(height: 22),
              Text(
                widget.fileName,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF191919),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '暂不支持在应用内打开此类文件，你可以使用其他应用打开并预览。',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: const Color(0xFF888888),
                  height: 1.45,
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(
                  _busy && _progress > 0
                      ? '$_status ${(_progress * 100).round()}%'
                      : _status!,
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: const Color(0xFFAAAAAA),
                  ),
                ),
              ],
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _openWithOtherApp,
                  style: FilledButton.styleFrom(
                    backgroundColor: _driveBlue,
                    disabledBackgroundColor: _driveBlue.withValues(alpha: 0.45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _busy ? '处理中…' : '用其他应用打开',
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
