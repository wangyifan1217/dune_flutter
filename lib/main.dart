import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/layout/mobile_viewport_shell.dart';
import 'core/theme/dunes_theme.dart';
import 'features/push/push_service.dart';
import 'features/shell/splash_screen.dart';
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
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      builder: (context, child) => MobileViewportShell(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppBootGate(),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installWebTextInputGuard();
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
  }
  runApp(const DunesApp());
}
