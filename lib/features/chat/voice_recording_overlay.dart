import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'im_ui_kit.dart';

/// 微信式录音动作。
///
/// - [none]：手指仍在「按住 说话」按钮区，松手即发送语音；
/// - [send] / [transcribe] / [cancel]：上滑进入底部操作面板后，
///   距离手指最近的圆圈动作，松手触发对应行为。
enum VoiceHoldAction { none, send, transcribe, cancel }

/// 底部操作面板高度（贴屏幕底部，与手势判定共用同一份几何）。
const kVoiceRecordingOverlayHeight = 300.0;

/// IM 语音消息最长时长（到点自动发送）。
const kVoiceRecordMaxDurationMs = 60 * 1000;

/// 圆圈行中心距面板顶部的距离（与面板内部布局保持一致）。
const _kCircleRowCenterY = 93.0;

/// 圆圈行下方死区：手指滑回该区域视为回到按钮区（松手即发送）。
const _kCircleRowDeadZone = 70.0;

const _kWeChatRed = Color(0xFFFA5151);

/// 圆圈动作的水平布局（圆心 X = 屏幕宽 * fraction）。
List<({VoiceHoldAction action, double fraction})> voiceHoldCircleLayout(
  bool transcribeEnabled,
) {
  return transcribeEnabled
      ? const [
          (action: VoiceHoldAction.send, fraction: 0.20),
          (action: VoiceHoldAction.transcribe, fraction: 0.50),
          (action: VoiceHoldAction.cancel, fraction: 0.80),
        ]
      : const [
          (action: VoiceHoldAction.send, fraction: 0.26),
          (action: VoiceHoldAction.cancel, fraction: 0.74),
        ];
}

/// 手势判定：根据手指全局坐标解析当前高亮的录音动作。
///
/// 与操作面板共用几何常量，保证「看到的高亮」和「松手触发的结果」一致。
VoiceHoldAction resolveVoiceHoldAction(
  Offset focal,
  Size screen, {
  required bool transcribeEnabled,
}) {
  if (screen.width <= 0 || screen.height <= 0) return VoiceHoldAction.none;
  final panelTop = screen.height - kVoiceRecordingOverlayHeight;
  final rowCenterY = panelTop + _kCircleRowCenterY;
  if (focal.dy > rowCenterY + _kCircleRowDeadZone) {
    return VoiceHoldAction.none;
  }
  var best = VoiceHoldAction.none;
  var bestDistance = double.infinity;
  for (final entry in voiceHoldCircleLayout(transcribeEnabled)) {
    final center = Offset(screen.width * entry.fraction, rowCenterY);
    final distance = (focal - center).distance;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entry.action;
    }
  }
  return best;
}

/// 微信式录音蒙层。
///
/// 两个状态：按住未上滑时居中显示波形计时面板（松手发送，上滑取消）；
/// 上滑后底部升起操作面板（发送 / 转文字 / 取消三个圆圈）。
/// 蒙层只做展示，触摸仍由输入栏的 LongPress 手势处理。
class VoiceRecordingOverlay extends StatefulWidget {
  const VoiceRecordingOverlay({
    super.key,
    required this.durationMs,
    required this.action,
    this.transcribeEnabled = true,
    this.focalPoint,
  });

  final int durationMs;
  final VoiceHoldAction action;
  final bool transcribeEnabled;
  final Offset? focalPoint;

  @override
  State<VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 全屏轻磨砂紫灰遮罩，保留输入栏底层拖动手势透传。
          IgnorePointer(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: const ColoredBox(color: Color(0x78141122)),
            ),
          ),
          // 居中悬浮的毛玻璃紫色声纹卡片（始终于键盘区上方居中，不与底部操作弧遮挡）。
          Positioned(
            top: 0,
            left: 24,
            right: 24,
            bottom: kVoiceRecordingOverlayHeight * 0.72,
            child: IgnorePointer(
              child: Center(
                child: _RecordingCenterBubble(
                  controller: _waveController,
                  durationMs: widget.durationMs,
                  action: widget.action,
                ),
              ),
            ),
          ),
          // 底部弧形磨砂操作面板（发送 / 转文字 / 取消三个彩色磁吸圆环，几何与 resolveVoiceHoldAction 完全一致）。
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _VoiceActionPanel(
                controller: _waveController,
                durationMs: widget.durationMs,
                action: widget.action,
                transcribeEnabled: widget.transcribeEnabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatClock(int durationMs) {
  final seconds = (durationMs / 1000).floor();
  final mm = (seconds ~/ 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// 居中悬浮毛玻璃紫色声纹气泡。
class _RecordingCenterBubble extends StatelessWidget {
  const _RecordingCenterBubble({
    required this.controller,
    required this.durationMs,
    required this.action,
  });

  final Animation<double> controller;
  final int durationMs;
  final VoiceHoldAction action;

  @override
  Widget build(BuildContext context) {
    final remainSec = ((kVoiceRecordMaxDurationMs - durationMs) / 1000).ceil();
    final isCancel = action == VoiceHoldAction.cancel;
    final isTranscribe = action == VoiceHoldAction.transcribe;
    final tip = remainSec <= 10 && remainSec > 0
        ? '还可以说 $remainSec 秒'
        : switch (action) {
            VoiceHoldAction.cancel => '松手取消发送',
            VoiceHoldAction.transcribe => '松手转为文字',
            VoiceHoldAction.send => '松手发送语音',
            VoiceHoldAction.none => '松手发送，上滑更多操作',
          };
    final accentColor = isCancel
        ? _kWeChatRed
        : isTranscribe
        ? const Color(0xFF4F6CE6)
        : ImVisualTokens.purple;
    final cardTint = isCancel
        ? const Color(0xD93C212A)
        : Colors.white.withValues(alpha: 0.78);
    final clockColor = isCancel
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF3E2D7A);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: isCancel ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 224,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.30),
                  blurRadius: 30,
                  spreadRadius: -4,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  decoration: BoxDecoration(
                    color: cardTint,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isCancel
                          ? _kWeChatRed.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.65),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 176,
                        height: 46,
                        child: _SymmetricWaveBars(
                          controller: controller,
                          barCount: 19,
                          maxHeight: 44,
                          barWidth: 3.4,
                          primaryColor: isCancel
                              ? const Color(0xFFFF8686)
                              : accentColor,
                          secondaryColor: isCancel
                              ? _kWeChatRed
                              : ImVisualTokens.purpleLight,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isCancel
                              ? Colors.white.withValues(alpha: 0.14)
                              : accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _formatClock(durationMs),
                          style: DunesTypography.mono(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: clockColor,
                            context: context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tip,
            style: DunesTypography.sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.90),
              context: context,
            ),
          ),
        ),
      ],
    );
  }
}

/// 底部弧形磨砂面板裁切器：顶部呈柔和上凸圆弧，高度与 [kVoiceRecordingOverlayHeight] 一致。
class _VoiceDockArchClipper extends CustomClipper<Path> {
  const _VoiceDockArchClipper();

  static const double archDrop = 24.0;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, archDrop)
      ..quadraticBezierTo(size.width * 0.5, -archDrop * 0.45, size.width, archDrop)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _VoiceDockArchBorderPainter extends CustomPainter {
  const _VoiceDockArchBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, _VoiceDockArchClipper.archDrop)
      ..quadraticBezierTo(
        size.width * 0.5,
        -_VoiceDockArchClipper.archDrop * 0.45,
        size.width,
        _VoiceDockArchClipper.archDrop,
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.20);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 底部弧形磨砂操作面板（发送 / 转文字 / 取消）。
class _VoiceActionPanel extends StatelessWidget {
  const _VoiceActionPanel({
    required this.controller,
    required this.durationMs,
    required this.action,
    required this.transcribeEnabled,
  });

  final Animation<double> controller;
  final int durationMs;
  final VoiceHoldAction action;
  final bool transcribeEnabled;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final remainSec = ((kVoiceRecordMaxDurationMs - durationMs) / 1000).ceil();
    final hint = remainSec <= 10 && remainSec > 0
        ? '还可以说 $remainSec 秒'
        : switch (action) {
            VoiceHoldAction.cancel => '松手取消',
            VoiceHoldAction.transcribe => '松手转文字',
            VoiceHoldAction.send => '松手发送',
            VoiceHoldAction.none => '松手即发 · 上滑选操作',
          };
    return SizedBox(
      height: kVoiceRecordingOverlayHeight,
      width: double.infinity,
      child: ClipPath(
        clipper: const _VoiceDockArchClipper(),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: CustomPaint(
            painter: const _VoiceDockArchBorderPainter(),
            child: Container(
              height: kVoiceRecordingOverlayHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCF262139), Color(0xE81A1728)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  // 三个彩色磁吸圆圈，圆心 Y 严格保持在 _kCircleRowCenterY (93.0)。
                  Positioned(
                    top: _kCircleRowCenterY - 43,
                    left: 0,
                    right: 0,
                    height: 92,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        return Stack(
                          children: [
                            for (final entry in voiceHoldCircleLayout(
                              transcribeEnabled,
                            ))
                              Positioned(
                                left: width * entry.fraction - 46,
                                top: 0,
                                bottom: 0,
                                width: 92,
                                child: _VoiceActionCircle(
                                  action: entry.action,
                                  highlighted: action == entry.action,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: bottomInset + 14,
                    child: SizedBox(
                      height: 30,
                      child: Row(
                        children: [
                          _BlinkDot(controller: controller),
                          const SizedBox(width: 8),
                          Text(
                            '录音中…',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.72),
                              context: context,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            hint,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.72),
                              context: context,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceActionCircle extends StatelessWidget {
  const _VoiceActionCircle({required this.action, required this.highlighted});

  final VoiceHoldAction action;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (action) {
      VoiceHoldAction.send => (
        '发送',
        const Icon(Icons.check_rounded, size: 28, color: Colors.white),
      ),
      VoiceHoldAction.transcribe => (
        '转文字',
        Text(
          '文',
          style: DunesTypography.sans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            context: context,
          ),
        ),
      ),
      VoiceHoldAction.cancel => (
        '取消',
        const Icon(Icons.close_rounded, size: 28, color: Colors.white),
      ),
      _ => ('', const SizedBox.shrink()),
    };
    final baseColor = action == VoiceHoldAction.cancel
        ? _kWeChatRed
        : action == VoiceHoldAction.transcribe
        ? const Color(0xFF4F6CE6)
        : ImVisualTokens.purple;
    final secondaryColor = action == VoiceHoldAction.cancel
        ? const Color(0xFFD93B3B)
        : action == VoiceHoldAction.transcribe
        ? const Color(0xFF3954C9)
        : ImVisualTokens.purpleDeep;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: highlighted ? 1.18 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlighted
                    ? [baseColor, secondaryColor]
                    : [
                        baseColor.withValues(alpha: 0.48),
                        secondaryColor.withValues(alpha: 0.42),
                      ],
              ),
              border: Border.all(
                color: highlighted
                    ? Colors.white.withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.22),
                width: highlighted ? 1.6 : 0.8,
              ),
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.55),
                        blurRadius: 20,
                        spreadRadius: -1,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.20),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
            ),
            alignment: Alignment.center,
            child: icon,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
            color: highlighted
                ? Colors.white
                : Colors.white.withValues(alpha: 0.72),
            context: context,
          ),
        ),
      ],
    );
  }
}

class _BlinkDot extends StatelessWidget {
  const _BlinkDot({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final opacity =
            0.35 +
            0.65 * (0.5 + 0.5 * math.sin(controller.value * math.pi * 2));
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DunesColors.resolveNullable(
                context,
                _kWeChatRed,
                role: DunesColorRole.surface,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SymmetricWaveBars extends StatelessWidget {
  const _SymmetricWaveBars({
    required this.controller,
    required this.barCount,
    required this.maxHeight,
    required this.barWidth,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Animation<double> controller;
  final int barCount;
  final double maxHeight;
  final double barWidth;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    final mid = (barCount - 1) / 2.0;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (index) {
            final dist = (index - mid).abs() / mid;
            final envelope = 1.0 - 0.58 * dist * dist;
            final wave = math
                .sin(controller.value * math.pi * 2 + index * 0.65)
                .abs();
            final h =
                (maxHeight * 0.18 + wave * maxHeight * 0.76) * envelope;
            return Container(
              width: barWidth,
              height: h.clamp(4.0, maxHeight),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [secondaryColor, primaryColor],
                ),
                borderRadius: BorderRadius.circular(barWidth),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 松手选择「转文字」后的识别中提示。
class VoiceTranscribingIndicator extends StatelessWidget {
  const VoiceTranscribingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ColoredBox(
          color: const Color(0x66151221),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 22,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xDF242034),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ImVisualTokens.purpleLight.withValues(alpha: 0.30),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: ImVisualTokens.purpleLight,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '语音转文字中…',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
