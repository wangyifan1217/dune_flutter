import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_upload_coordinator.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'native_drive_models.dart';
import 'native_drive_service.dart';

/// 将微盘文件以 IM「文件」消息推送到所选会话。
Future<bool> pushDriveItemToIm({
  required BuildContext context,
  required AuthSession session,
  required NativeDriveService service,
  required DriveItem item,
}) async {
  if (item.isFolder) {
    showDunesCenterToast(
      context,
      '文件夹暂不支持发送到聊天',
      kind: DunesToastKind.error,
    );
    return false;
  }

  final chat = ConversationService(session: session);
  var showingProgress = false;
  try {
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: chat,
      title: '发送到聊天',
    );
    if (conversationId == null || conversationId <= 0 || !context.mounted) {
      return false;
    }

    showingProgress = true;
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

      final fileName = item.name.trim().isEmpty ? '文件' : item.name.trim();
      final mimeType = item.mimeType.trim().isNotEmpty
          ? item.mimeType.trim()
          : (lookupMimeType(fileName) ?? 'application/octet-stream');

      await ChatFileUploadCoordinator.instance.sendFile(
        session: session,
        conversationId: conversationId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );

      if (!context.mounted) return true;
      Navigator.of(context, rootNavigator: true).maybePop();
      showingProgress = false;
      showDunesCenterToast(context, '已发送到聊天');
      return true;
    } finally {
      client.close();
    }
  } catch (e) {
    if (context.mounted) {
      if (showingProgress) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '发送失败，请稍后重试'),
        kind: DunesToastKind.error,
      );
    }
    return false;
  } finally {
    chat.close();
  }
}
