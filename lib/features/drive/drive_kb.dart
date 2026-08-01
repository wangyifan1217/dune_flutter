import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_preview_page.dart';
import '../kb/kb_document_coordinator.dart';
import '../kb/native_kb_service.dart';
import '../shell/dunes_toast.dart';
import 'native_drive_models.dart';
import 'native_drive_service.dart';

bool driveItemSupportsKbUpload(DriveItem item) {
  if (item.isFolder) return false;
  return chatFileSupportsKbUpload(item.name, {
    'mimeType': item.mimeType,
  });
}

/// 将微盘文件存入当前用户知识库（沿用 IM 上传逻辑 + 二次确认 + 服务端标记）。
Future<bool> saveDriveItemToKb({
  required BuildContext context,
  required AuthSession session,
  required NativeDriveService service,
  required DriveItem item,
}) async {
  if (!driveItemSupportsKbUpload(item)) {
    showDunesCenterToast(
      context,
      '仅支持 PDF / Word / Excel / Markdown',
      kind: DunesToastKind.error,
    );
    return false;
  }

  final title = item.name.trim().isEmpty ? '文档' : item.name.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('存入我的知识库'),
      content: Text(
        item.kbSavedCurrent
            ? '「$title」已存入过你的知识库。是否再次上传当前版本？\n\n上传后可检索引用。'
            : (item.kbSaved
                  ? '「$title」知识库中有旧版本。是否将当前版本存入你的知识库？\n\n上传后可检索引用。'
                  : '将把「$title」存入你的知识库，上传后可检索引用。\n\n是否继续？'),
        style: DunesTypography.sans(fontSize: 14, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(item.kbSaved ? '确认更新' : '确认存入'),
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

  final kb = NativeKbService(session: session);
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
    await kb.uploadDocument(
      bytes: bytes,
      fileName: title,
      title: title,
    );
    await service.markKbSaved(item.id, version: item.version);
    KbDocumentCoordinator.instance.notifyChanged();
    if (!context.mounted) return true;
    Navigator.of(context, rootNavigator: true).maybePop();
    showDunesCenterToast(context, '已存入你的知识库，正在后台解析入库');
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '存入知识库失败，请稍后重试'),
        kind: DunesToastKind.error,
      );
    }
    return false;
  } finally {
    client.close();
  }
}
