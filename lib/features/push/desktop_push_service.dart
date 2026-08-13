import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import '../desktop/desktop_badge.dart';
import '../desktop/windows_desktop_tray.dart';

/// 桌面端本地系统通知（Win Toast / macOS 通知中心）。
/// 形态类似企业微信：标题=发送者，正文=消息摘要。
final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

bool _ready = false;
Future<void>? _initInFlight;
int _seq = 1000;

Future<void> ensurePushInitializedImpl() async {
  if (_ready) return;
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  final inFlight = _initInFlight;
  if (inFlight != null) return inFlight;
  final future = _ensurePushInitializedOnce();
  _initInFlight = future;
  try {
    await future;
  } finally {
    if (identical(_initInFlight, future)) _initInFlight = null;
  }
}

Future<void> _ensurePushInitializedOnce() async {
  if (_ready) return;
  try {
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );
    final iconPath = _resolveWindowsNotificationIconPath();
    final windows = WindowsInitializationSettings(
      appName: '沙丘',
      appUserModelId: 'com.nova.dunes.desktop',
      guid: 'a8e2c1d4-7b5f-4e9a-9c3d-1f2a6b8e0d71',
      // Debug / EXE 安装包都需要绝对路径，否则 Toast 左侧无应用图标。
      iconPath: iconPath,
    );
    if (iconPath == null) {
      debugPrint('[DesktopPush] Windows toast iconPath unresolved');
    }

    await _plugin.initialize(
      settings: InitializationSettings(
        macOS: Platform.isMacOS ? darwin : null,
        windows: Platform.isWindows ? windows : null,
      ),
      onDidReceiveNotificationResponse: (_) {
        unawaited(_bringAppToFront());
      },
    );

    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _ready = true;
  } catch (e, st) {
    debugPrint('[DesktopPush] initialize failed: $e\n$st');
  }
}

void registerPushLifecycleObserverImpl() {}

void setPushBadgeRefreshHandlerImpl(void Function()? handler) {}

Future<void> bindPushSessionImpl({
  required int userId,
  required String token,
  required String apiBase,
}) async {
  // Windows：登录进会话页时不要同步拉 WinRT Toast。
  // 未打包/无 AUMID 的机器上 initialize 可能把整进程打崩，且会与
  // main() 里的预热并发。Toast 延后到第一条桌面通知；任务栏角标不依赖它。
  if (Platform.isMacOS) {
    await ensurePushInitializedImpl();
  }
}

Future<void> unbindPushSessionImpl() async {
  try {
    await _plugin.cancelAll();
  } catch (_) {}
  syncPushBadgeCountImpl(0);
}

void syncPushBadgeCountImpl(int count) {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  final n = normalizeDesktopBadgeCount(count);
  unawaited(_syncDesktopBadge(n));
}

Future<int> readPushBadgeCountImpl() async => _lastDesktopBadgeCount;

int _lastDesktopBadgeCount = 0;

Future<void> _syncDesktopBadge(int count) async {
  _lastDesktopBadgeCount = count;
  try {
    if (Platform.isMacOS) {
      // Dock 数字角标；需通知权限（ensurePushInitialized 已申请 badge）。
      await ensurePushInitializedImpl();
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(count);
      }
      return;
    }
    if (Platform.isWindows) {
      final asset = windowsTaskbarBadgeAsset(count);
      final tip = desktopBadgeTooltip(count);
      if (asset == null) {
        await WindowsTaskbar.resetOverlayIcon();
      } else {
        await WindowsTaskbar.setOverlayIcon(
          ThumbnailToolbarAssetIcon(asset),
          tooltip: tip,
        );
      }
    }
  } catch (e, st) {
    debugPrint('[DesktopPush] badge sync failed count=$count err=$e\n$st');
  }
}

void notifyPushRealtimeMessageImpl({
  required String title,
  required String body,
  int conversationId = 0,
}) {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  unawaited(
    _showToast(title: title, body: body, conversationId: conversationId),
  );
}

Future<void> _showToast({
  required String title,
  required String body,
  int conversationId = 0,
}) async {
  try {
    await ensurePushInitializedImpl();
    final id = _seq++;
    if (_seq > 900000) _seq = 1000;

    final safeTitle = _compactNotificationText(
      title.trim().isEmpty ? '沙丘' : title,
      maxLength: 32,
    );
    final safeBody = _compactNotificationText(
      body.trim().isEmpty ? '您有新消息' : body,
      maxLength: 48,
    );

    await _plugin.show(
      id: id,
      title: safeTitle,
      body: safeBody,
      notificationDetails: NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          // Dock 角标统一由 syncPushBadgeCount → AppBadgePlus 控制，
          // 避免每条通知自行 +1 与真实未读数打架。
          presentBadge: false,
          threadIdentifier:
              conversationId > 0 ? 'conv_$conversationId' : 'dunes_desktop',
        ),
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
          // 必须用绝对 file URI。getAssetUri 在 Release 下依赖 CWD，
          // 从开始菜单/快捷方式启动时常解析失败，反而把左侧图标盖成空白。
          images: _windowsToastLogoImages(),
        ),
      ),
      payload: conversationId > 0 ? 'conv:$conversationId' : 'conv:0',
    );
  } catch (e, st) {
    debugPrint('[DesktopPush] show failed: $e\n$st');
  }
}

List<WindowsImage> _windowsToastLogoImages() {
  final path = _resolveWindowsNotificationLogoPath();
  if (path == null) return const <WindowsImage>[];
  return <WindowsImage>[
    WindowsImage(
      Uri.file(path, windows: true),
      altText: '沙丘',
      placement: WindowsImagePlacement.appLogoOverride,
      crop: WindowsImageCrop.circle,
    ),
  ];
}

/// 解析 Windows Toast 应用图标（注册表 IconUri，优先 .ico）。
String? _resolveWindowsNotificationIconPath() {
  return _resolveWindowsAssetPath(const <String>[
    'assets/images/tray_icon.ico',
    'assets/images/app_logo.png',
  ]);
}

/// 解析 Toast 左侧圆形 logo（优先高清 png）。
String? _resolveWindowsNotificationLogoPath() {
  return _resolveWindowsAssetPath(const <String>[
    'assets/images/app_logo.png',
    'assets/images/tray_icon.ico',
  ]);
}

/// 按「可执行文件旁打包资源 → 工程源码资源」解析绝对路径。
/// 快捷方式启动时 CWD 往往不是 exe 目录，不能依赖相对路径。
String? _resolveWindowsAssetPath(List<String> assetNames) {
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <File>[];
    for (final name in assetNames) {
      candidates.addAll(<File>[
        File('$exeDir\\data\\flutter_assets\\$name'),
        File('data/flutter_assets/$name'),
        File(name),
      ]);
    }
    for (final file in candidates) {
      if (file.existsSync()) {
        return file.absolute.path.replaceAll('/', '\\');
      }
    }
  } catch (e) {
    debugPrint('[DesktopPush] resolve icon failed: $e');
  }
  return null;
}

/// 系统通知只保留一行摘要，避免 Windows/macOS 因换行或长文本撑高横幅。
String _compactNotificationText(String value, {required int maxLength}) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= maxLength) return singleLine;
  return '${singleLine.substring(0, maxLength)}…';
}

Future<void> _bringAppToFront() async {
  try {
    windowsTrayReveal();
  } catch (_) {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[DesktopPush] bring front failed: $e');
    }
  }
}
