import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 在 Web / 桌面宽屏下，将 App 约束为手机宽度并居中展示，便于移动端 UI 开发预览。
class MobileViewportShell extends StatelessWidget {
  const MobileViewportShell({super.key, required this.child});

  static const double phoneWidth = 400;

  final Widget child;

  static bool shouldConstrain(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      return false;
    }
    return MediaQuery.sizeOf(context).width > phoneWidth;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    if (!shouldConstrain(context)) return child;

    final height = mediaQuery.size.height;
    return ColoredBox(
      color: const Color(0xFF14120F),
      child: Center(
        child: SizedBox(
          width: phoneWidth,
          height: height,
          child: MediaQuery(
            data: mediaQuery.copyWith(size: Size(phoneWidth, height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
