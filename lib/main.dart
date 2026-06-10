import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/dunes_theme.dart';
import 'features/auth/login_flow.dart';
import 'core/web/text_input_guard_stub.dart'
    if (dart.library.html) 'core/web/text_input_guard_web.dart';
import 'features/prototype/webview_platform_init_stub.dart'
    if (dart.library.html) 'features/prototype/webview_platform_init_web.dart';

class DunesApp extends StatelessWidget {
  const DunesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '沙丘 · 统一审批',
      debugShowCheckedModeBanner: false,
      theme: DunesTheme.light(),
      home: const LoginFlow(),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installWebTextInputGuard();
  initWebViewPlatform();
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFBFAF6),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    );
  }
  runApp(const DunesApp());
}
