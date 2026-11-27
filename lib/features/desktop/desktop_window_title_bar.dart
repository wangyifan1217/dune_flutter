import 'package:flutter/widgets.dart';

import 'desktop_window_title_bar_stub.dart'
    if (dart.library.io) 'desktop_window_title_bar_io.dart'
    as impl;

const double kDunesDesktopTitleBarHeight = 30.0;

/// Windows 沉浸式一体顶栏（隐藏系统原生白条，与淡紫雾感 L 型外框无缝融合）。
class DunesDesktopWindowTitleBar extends StatelessWidget {
  const DunesDesktopWindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) => impl.buildDesktopWindowTitleBar(context);
}
