import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 卡片永远先在这张宽画布上完成排版，再整体缩到聊天消息行。
/// 360 会让内部组件先走手机窄版、三列被挤窄后才缩放；480 则保留完整卡片比例，
/// 同时避免 620 画布缩到手机后字号过小。
const double lighthouseMessageCardDesignWidth = 480;

/// 先按当前设备屏宽确定目标宽度，再由真实消息行限宽。
/// 不能直接把消息行宽再乘一次比例，否则聊天布局已经收窄过的空间会二次缩水。
double lighthouseMessageCardWidth(
  double screenWidth, {
  double maxAvailable = double.infinity,
}) {
  final usableScreen = screenWidth.isFinite && screenWidth > 0
      ? screenWidth
      : 326.0;
  // 手机上比普通文字气泡略宽，但不再接近满屏；大屏也固定停在 360。
  final target = math.min(360.0, math.max(260.0, usableScreen * .76));
  if (!maxAvailable.isFinite || maxAvailable <= 0) return target;
  return math.min(target, maxAvailable);
}

/// 先按 480pt 的设计画布排版，再把整个卡片（字号、图高、冻结列一起）等比
/// 缩放到消息行宽度。这样小屏不是重新挤版，大屏也不会继续拉成 680pt。
class LighthouseMessageCardFrame extends StatelessWidget {
  const LighthouseMessageCardFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final width = lighthouseMessageCardWidth(
        screenWidth,
        maxAvailable: constraints.maxWidth,
      );
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: width,
          child: FittedBox(
            alignment: Alignment.topLeft,
            fit: BoxFit.fitWidth,
            child: SizedBox(
              width: lighthouseMessageCardDesignWidth,
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
