import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/util/native_permissions.dart';
import 'attendance_models.dart';

Future<bool> openAttendanceCameraSettings() => openAppSettings();

/// Camera only. The returned bytes are kept for this attempt, never in app state.
Future<AttendanceFacePhoto?> captureAttendanceFace() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    throw Exception('请在安卓或 iOS 手机 App 中拍照完成人脸核验');
  }
  XFile? photo;
  try {
    if (!await ensureCameraPermission()) {
      throw Exception('打卡需要使用相机拍摄本人照片，请前往系统设置开启相机权限');
    }
    photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (photo == null) return null;
    if (await photo.length() > 5 * 1024 * 1024) {
      throw Exception('照片超过 5 MB，请重新拍照');
    }
    final bytes = await photo.readAsBytes();
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    const pngHeader = [137, 80, 78, 71, 13, 10, 26, 10];
    final png =
        bytes.length >= pngHeader.length &&
        listEquals(bytes.take(pngHeader.length).toList(), pngHeader);
    if (!jpeg && !png) throw Exception('拍照格式不受支持，请重新拍照');
    return AttendanceFacePhoto(bytes, jpeg ? 'image/jpeg' : 'image/png');
  } on PlatformException catch (error) {
    if (error.code.contains('access') || error.code.contains('permission')) {
      throw Exception('无法使用相机，请前往系统设置允许相机权限后重试');
    }
    throw Exception('无法打开相机，请关闭其他占用相机的应用后重试');
  } finally {
    // Only delete the temporary photo returned for this capture.
    if (photo != null) {
      try {
        await File(photo.path).delete();
      } catch (_) {
        // Native picker cache cleanup remains available if the file is locked.
      }
    }
  }
}
