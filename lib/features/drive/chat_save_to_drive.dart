import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'drive_subpages.dart';
import 'native_drive_service.dart';

/// 选择可写入的微盘空间与文件夹。
Future<DriveFolderPickResult?> pickDriveSaveLocation({
  required BuildContext context,
  required AuthSession session,
  required String fileName,
}) async {
  final drive = NativeDriveService(session: session);
  try {
    final spaces = await drive.fetchSpaces();
    final writable = spaces.where((s) => s.canEdit).toList(growable: false);
    if (writable.isEmpty) {
      if (context.mounted) {
        showDunesCenterToast(
          context,
          '没有可写入的微盘空间',
          kind: DunesToastKind.error,
        );
      }
      return null;
    }
    if (!context.mounted) return null;
    // 必须 await：否则 finally 会立刻 close client，选文件夹页加载会报网络失败。
    return await pushDrivePage<DriveFolderPickResult>(
      context,
      DriveFolderPickerPage(
        service: drive,
        spaces: writable,
        fileName: fileName,
      ),
    );
  } catch (e) {
    if (context.mounted) {
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '打开微盘失败，请稍后重试'),
        kind: DunesToastKind.error,
      );
    }
    return null;
  } finally {
    drive.close();
  }
}

/// 将字节上传到已选择的微盘位置。
///
/// [sourceKey] 为 IM 附件标识（objectKey / url），用于标记「已存入微盘」。
Future<bool> uploadBytesToDriveLocation({
  required BuildContext context,
  required AuthSession session,
  required DriveFolderPickResult location,
  required List<int> bytes,
  required String fileName,
  String? mimeType,
  String? sourceKey,
}) async {
  if (bytes.isEmpty) {
    showDunesCenterToast(
      context,
      '文件内容为空',
      kind: DunesToastKind.error,
    );
    return false;
  }

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

  final drive = NativeDriveService(session: session);
  try {
    final item = await drive.uploadBytes(
      spaceId: location.space.id,
      parentId: location.parentId,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final key = (sourceKey ?? '').trim();
    if (key.isNotEmpty) {
      try {
        await drive.markChatSaved(
          sourceKey: key,
          driveItemId: item.id,
          fileName: fileName,
        );
      } catch (_) {
        // 上传已成功；标记失败不阻断。
      }
    }
    if (!context.mounted) return true;
    Navigator.of(context, rootNavigator: true).maybePop();
    showDunesCenterToast(context, '已存入微盘「${location.space.name}」');
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '存入微盘失败，请稍后重试'),
        kind: DunesToastKind.error,
      );
    }
    return false;
  } finally {
    drive.close();
  }
}

/// 先选位置，再上传已有字节。
Future<bool> saveBytesToDrive({
  required BuildContext context,
  required AuthSession session,
  required List<int> bytes,
  required String fileName,
  String? mimeType,
  String? sourceKey,
}) async {
  final pick = await pickDriveSaveLocation(
    context: context,
    session: session,
    fileName: fileName,
  );
  if (pick == null || !context.mounted) return false;
  return uploadBytesToDriveLocation(
    context: context,
    session: session,
    location: pick,
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
    sourceKey: sourceKey,
  );
}

/// 查询指定 IM 附件是否已存入当前用户微盘。
Future<bool> isChatFileSavedToDrive({
  required AuthSession session,
  required String sourceKey,
}) async {
  final key = sourceKey.trim();
  if (key.isEmpty) return false;
  final drive = NativeDriveService(session: session);
  try {
    final saved = await drive.fetchChatSavedKeys([key]);
    return saved.contains(key);
  } catch (_) {
    return false;
  } finally {
    drive.close();
  }
}
