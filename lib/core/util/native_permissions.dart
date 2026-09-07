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

bool _photosAccessGranted(PermissionStatus status) =>
    status.isGranted || status.isLimited;

Future<bool> ensurePhotosPermission() async {
  if (kIsWeb) return true;
  if (Platform.isIOS) {
    final status = await Permission.photos.status;
    if (_photosAccessGranted(status)) return true;
    final result = await Permission.photos.request();
    return _photosAccessGranted(result);
  }
  if (Platform.isAndroid) {
    // 选图走系统 Photo Picker，不需要 READ_MEDIA_* / 存储权限。
    // 先申请的话：拒绝或「仅选择部分照片」(limited) 会把相册拦死。
    // 保存到系统相册仍由 Gal 单独申请，不走这里。
    return true;
  }
  return true;
}

/// IM / 表单从系统相册选图、选视频。iOS 仍要相册权限；Android 交给 Photo Picker。
Future<bool> ensureGalleryPickerReady() async {
  if (kIsWeb) return true;
  if (Platform.isIOS) return ensurePhotosPermission();
  return true;
}

Future<bool> ensureMicrophonePermission() async {
  if (kIsWeb) return true;
  final status = await Permission.microphone.status;
  if (status.isGranted) return true;
  final result = await Permission.microphone.request();
  return result.isGranted;
}

Future<bool> ensureLocationPermission() async {
  if (kIsWeb) return true;
  final whenInUse = await Permission.locationWhenInUse.status;
  if (whenInUse.isGranted) return true;

  var result = await Permission.locationWhenInUse.request();
  if (result.isGranted) return true;

  // 部分 Android 机型（含小米）仅申请 locationWhenInUse 不够，再补一次 location。
  if (!kIsWeb && Platform.isAndroid) {
    final location = await Permission.location.status;
    if (location.isGranted) return true;
    result = await Permission.location.request();
    if (result.isGranted) return true;
  }
  return false;
}

String locationPermissionHint(PermissionStatus status) {
  if (status.isPermanentlyDenied || status.isRestricted) {
    return '定位权限未开启，请在系统设置中允许「沙丘X」使用位置信息';
  }
  return '请先允许定位权限，以便携程商旅打车与附近服务正常使用';
}

String cameraPermissionHint(PermissionStatus status) {
  if (status.isPermanentlyDenied || status.isRestricted) {
    return '相机权限未开启，请在系统设置中允许「沙丘X」使用相机';
  }
  return '请先允许相机权限，以便扫描内部员工邀请码完成注册，或在聊天、NOVA 中拍摄照片';
}

String photosPermissionHint(PermissionStatus status) {
  if (status.isPermanentlyDenied || status.isRestricted) {
    return '相册权限未开启，请在系统设置中允许「沙丘X」访问照片';
  }
  return '请先允许相册权限，以便选择图片、设置头像或上传审批附件';
}

String microphonePermissionHint(PermissionStatus status) {
  if (status.isPermanentlyDenied || status.isRestricted) {
    return '麦克风权限未开启，请在系统设置中允许「沙丘X」使用麦克风';
  }
  return '请先允许麦克风权限，以便发送语音、NOVA 语音输入或录制会议';
}
