import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/util/native_permissions.dart';
import 'attendance_auto_face_page.dart';
import 'attendance_models.dart';

Future<bool> openAttendanceCameraSettings() => openAppSettings();

/// 打开前置摄像头。预览后自动拍照并返回，用户取消时返回 null。
Future<AttendanceFacePhoto?> captureAttendanceFace(BuildContext context) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    throw Exception('请在安卓或 iOS 手机 App 中拍照完成人脸核验');
  }
  try {
    if (!await ensureCameraPermission()) {
      throw Exception('打卡需要使用相机拍摄本人照片，请前往系统设置开启相机权限');
    }
    if (!context.mounted) return null;
    return Navigator.of(context).push<AttendanceFacePhoto>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AttendanceAutoFacePage(),
      ),
    );
  } on PlatformException catch (error) {
    if (error.code.contains('access') || error.code.contains('permission')) {
      throw Exception('无法使用相机，请前往系统设置允许相机权限后重试');
    }
    throw Exception('无法打开相机，请关闭其他占用相机的应用后重试');
  }
}
