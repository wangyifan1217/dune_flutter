import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';
import 'native_drive_models.dart';
import 'native_drive_service.dart';

/// 将微盘文件下载到本地（二次确认 + 服务端按人标记）。
Future<bool> downloadDriveItemToLocal({
  required BuildContext context,
  required NativeDriveService service,
  required DriveItem item,
}) async {
  if (item.isFolder) {
    showDunesCenterToast(
      context,
      '文件夹不支持下载到本地',
      kind: DunesToastKind.error,
    );
    return false;
  }

  final title = item.name.trim().isEmpty ? '文件' : item.name.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('下载到本地'),
      content: Text(
        item.downloadedCurrent
            ? '「$title」已下载过当前版本。是否重新下载？'
            : (item.downloaded
                  ? '「$title」本地有旧版本。是否下载当前版本？'
                  : '将把「$title」下载到本地。\n\n是否继续？'),
        style: DunesTypography.sans(fontSize: 14, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(item.downloaded ? '确认重新下载' : '确认下载'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2.6),
      ),
    ),
  );

  final client = http.Client();
  try {
    final request = http.Request('GET', service.contentUri(item.id));
    request.headers.addAll(service.contentHeaders());
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载失败（HTTP ${response.statusCode}）');
    }
    final bytes = Uint8List.fromList(await response.stream.toBytes());
    if (bytes.isEmpty) throw Exception('文件内容为空');

    final path = await file_dl.saveBytesAsDriveFile(
      bytes,
      title,
      cacheKey: 'drive-item-${item.id}',
    );
    await service.markDownloaded(item.id, version: item.version);

    if (!context.mounted) return true;
    Navigator.of(context, rootNavigator: true).maybePop();
    final hint = (path != null && path.isNotEmpty)
        ? '已下载到本地'
        : '已开始下载';
    showDunesCenterToast(context, hint);

    if (path != null && path.isNotEmpty) {
      try {
        await file_dl.revealLocalFile(path);
      } catch (_) {}
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '下载失败，请稍后重试'),
        kind: DunesToastKind.error,
      );
    }
    return false;
  } finally {
    client.close();
  }
}
