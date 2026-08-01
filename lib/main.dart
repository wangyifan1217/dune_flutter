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
import 'features/desktop/windows_desktop_tray.dart';
import 'features/push/push_service.dart';
import 'features/shell/splash_screen.dart';
import 'features/xflow/xflow_service.dart';
import 'features/drive/native_drive_share_page.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'core/web/text_input_guard_stub.dart'
    if (dart.library.html) 'core/web/text_input_guard_web.dart';

class DunesApp extends StatelessWidget {
  const DunesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '沙丘 · 统一审批',
      debugShowCheckedModeBanner: false,
      theme: DunesTheme.light(),
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
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(scale)),
              child: MobileViewportShell(
                child: AppWatermark(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
        );
      },
      home: _initialHome(),
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
  }
  return const AppBootGate();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installWebTextInputGuard();
  await AppTextScaleController.instance.load();
  if (isDesktopCommOnly) {
    await initWindowsDesktopTray();
    // 全局截图热键依赖 hotkey_manager 初始化。
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFBFAF6),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    unawaited(ensurePushInitialized());
    unawaited(XflowService.hydrateTemplateCache());
  }
  runApp(const DunesApp());
}
