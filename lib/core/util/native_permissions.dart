import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// iOS/Android 原生权限封装。iOS 侧需在 Podfile 中开启对应 PERMISSION_* 宏。
Future<bool> ensureCameraPermission() async {
  if (kIsWeb) return true;
  final status = await Permission.camera.status;
  if (status.isGranted) return true;
  final result = await Permission.camera.request();
  return result.isGranted;
}

Future<bool> ensurePhotosPermission() async {
  if (kIsWeb) return true;
  if (!Platform.isIOS && !Platform.isAndroid) return true;
  final status = await Permission.photos.status;
  if (status.isGranted || status.isLimited) return true;
  final result = await Permission.photos.request();
  return result.isGranted || result.isLimited;
}

Future<bool> ensureMicrophonePermission() async {
  if (kIsWeb) return true;
  final status = await Permission.microphone.status;
  if (status.isGranted) return true;
  final result = await Permission.microphone.request();
  return result.isGranted;
}

String cameraPermissionHint(PermissionStatus status) {
  if (status.isPermanentlyDenied || status.isRestricted) {
    return '相机权限未开启，请在系统设置中允许「沙丘」使用相机';
  }
  return '请先允许相机权限';
}

String photosPermissionHint(PermissionStatus status) {
  if (status.isPermanentlyDenied || status.isRestricted) {
    return '相册权限未开启，请在系统设置中允许「沙丘」访问照片';
  }
  return '请先允许相册/照片权限';
}
