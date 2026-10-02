import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/layout/mobile_viewport_shell.dart';
import 'core/platform/desktop_features.dart';
import 'core/theme/app_text_scale.dart';
import 'core/theme/dunes_theme.dart';
import 'core/widgets/app_watermark.dart';
import 'features/chat/chat_image_preview_window_stub.dart'
    if (dart.library.io) 'features/chat/chat_image_preview_window.dart';
import 'features/chat/im_celebration.dart';
import 'features/desktop/desktop_esc_minimize.dart';
import 'features/desktop/windows_desktop_tray.dart';
import 'features/push/push_service.dart';
import 'features/conversation/reply_sla_gallery_page.dart';
import 'features/shell/splash_screen.dart';
import 'features/xflow/xflow_service.dart';
import 'features/drive/native_drive_share_page.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'core/web/text_input_guard_stub.dart'
    if (dart.library.html) 'core/web/text_input_guard_web.dart';
import 'core/util/android_photo_picker_stub.dart'
    if (dart.library.io) 'core/util/android_photo_picker_io.dart';

class DunesApp extends StatelessWidget {
  const DunesApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppEggThemeController.instance.revision,
      builder: (context, revision, _) => _buildApp(),
    );
  }

  Widget _buildApp() {
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    return MaterialApp(
      title: '沙丘 · 统一审批',
      navigatorKey: dunesAppNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: mobile
          ? AppEggThemeController.instance.theme(DunesTheme.light())
          : DunesTheme.light(),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      builder: (context, child) {
        return ListenableBuilder(
          listenable: AppTextScaleController.instance,
          builder: (context, _) {
            final scale = AppTextScaleController.instance.scale;
            final media = MediaQuery.of(context);
            Widget wrapped = MobileViewportShell(
              child: AppWatermark(child: child ?? const SizedBox.shrink()),
            );
            if (mobile) {
              final night = AppEggThemeController.instance.isNight;
              final palette = night ? DunesPalette.night : DunesPalette.day;
              wrapped = AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: night
                      ? Brightness.light
                      : Brightness.dark,
                  statusBarBrightness: night
                      ? Brightness.dark
                      : Brightness.light,
                  systemNavigationBarColor: palette.app,
                  systemNavigationBarIconBrightness: night
                      ? Brightness.light
                      : Brightness.dark,
                  systemStatusBarContrastEnforced: false,
                  systemNavigationBarContrastEnforced: false,
                ),
                child: wrapped,
              );
            }
            if (isDesktopCommOnly) {
              wrapped = DesktopEscMinimize(child: wrapped);
              // 托盘 / 最小化 / Cmd+H / 切桌面：停动画。失焦不冻，避免双屏切窗看起来卡死。
              wrapped = ValueListenableBuilder<bool>(
                valueListenable: windowsTrayWindowObscuredListenable(),
                builder: (context, obscured, child) {
                  return TickerMode(enabled: !obscured, child: child!);
                },
                child: wrapped,
              );
            }
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(scale)),
              child: wrapped,
            );
          },
        );
      },
      home: home ?? _initialHome(),
    );
  }
}

Widget _initialHome() {
  if (kIsWeb) {
    final segments = Uri.base.pathSegments;
    if (segments.length >= 3 &&
        segments[0] == 'share' &&
        segments[1] == 'drive') {
      final token = segments[2].trim();
      if (token.isNotEmpty) return NativeDriveSharePage(token: token);
    }
    if (Uri.base.queryParameters['gallery'] == 'reply-sla') {
      return const ReplySlaGalleryPage();
    }
  }
  return const AppBootGate();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  enableAndroidPhotoPicker();

  // 桌面图片预览：desktop_multi_window 0.3 以独立 Engine 再进 main。
  if (isDesktopImagePreviewWindowArgs(args) ||
      await isDesktopImagePreviewEngine()) {
    await runDesktopImagePreviewWindow(args);
    return;
  }

  installWebTextInputGuard();
  await AppTextScaleController.instance.load();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)) {
    await AppEggThemeController.instance.load();
  }
  if (isDesktopCommOnly) {
    await initWindowsDesktopTray();
    // 全局截图热键依赖 hotkey_manager 初始化。
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
  if (!kIsWeb) {
    final night =
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android) &&
        AppEggThemeController.instance.isNight;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: night ? Brightness.light : Brightness.dark,
        statusBarBrightness: night ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: night
            ? DunesPalette.night.app
            : DunesPalette.day.app,
        systemNavigationBarIconBrightness: night
            ? Brightness.light
            : Brightness.dark,
      ),
    );
    // Windows 的 WinRT Toast 延后到第一条通知，避免登录进会话页时
    // 与 bindPushSession 并发 initialize 把进程打崩。
    if (defaultTargetPlatform != TargetPlatform.windows) {
      unawaited(ensurePushInitialized());
    }
    unawaited(XflowService.hydrateTemplateCache());
  }
  runApp(const DunesApp());
}
