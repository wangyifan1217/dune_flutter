import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/dunes_theme.dart';

/// 在 Web / 桌面宽屏下，将 App 约束为手机宽度并居中展示，便于移动端 UI 开发预览。
class MobileViewportShell extends StatelessWidget {
  const MobileViewportShell({super.key, required this.child});

  static const double phoneWidth = 400;

  final Widget child;

  static bool shouldConstrain(BuildContext context) {
    // 真机与桌面端用全窗口；仅 Web / Linux 等预览时约束为手机宽度。
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return false;
    }
    return MediaQuery.sizeOf(context).width > phoneWidth;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    if (!shouldConstrain(context)) return child;

    final palette =
        Theme.of(context).extension<DunesPalette>() ?? DunesPalette.day;
    final height = mediaQuery.size.height;
    return ColoredBox(
      color: palette.page,
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
