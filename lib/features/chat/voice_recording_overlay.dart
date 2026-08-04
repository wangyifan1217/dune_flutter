import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

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

const _kWeChatGreen = Color(0xFF07C160);
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
    final inActionPanel = widget.action != VoiceHoldAction.none;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 压暗会话内容，但不能拦截输入栏的拖动手势。
          const IgnorePointer(child: ColoredBox(color: Color(0x73000000))),
          IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 170),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                    child: child,
                  ),
                );
              },
              child: inActionPanel
                  ? _VoiceActionPanel(
                      key: const ValueKey('voice-actions'),
                      controller: _waveController,
                      durationMs: widget.durationMs,
                      action: widget.action,
                      transcribeEnabled: widget.transcribeEnabled,
                    )
                  : _RecordingCenterPanel(
                      key: const ValueKey('voice-center'),
                      controller: _waveController,
                      durationMs: widget.durationMs,
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

String _formatShortClock(int durationMs) {
  final seconds = (durationMs / 1000).floor();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// 图一：居中波形计时面板。
class _RecordingCenterPanel extends StatelessWidget {
  const _RecordingCenterPanel({
    super.key,
    required this.controller,
    required this.durationMs,
  });

  final Animation<double> controller;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final remainSec =
        ((kVoiceRecordMaxDurationMs - durationMs) / 1000).ceil();
    final tip = remainSec <= 10 && remainSec > 0
        ? '还可以说 $remainSec 秒'
        : '松手发送，上滑选择';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              color: const Color(0xD926262A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 40,
                  child: _WaveBars(
                    controller: controller,
                    barCount: 7,
                    maxHeight: 38,
                    barWidth: 3.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatClock(durationMs),
                  style: DunesTypography.mono(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tip,
            style: DunesTypography.sans(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图二：底部操作面板（发送 / 转文字 / 取消）。
class _VoiceActionPanel extends StatelessWidget {
  const _VoiceActionPanel({
    super.key,
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
    final remainSec =
        ((kVoiceRecordMaxDurationMs - durationMs) / 1000).ceil();
    final hint = remainSec <= 10 && remainSec > 0
        ? '还可以说 $remainSec 秒'
        : switch (action) {
            VoiceHoldAction.cancel => '松手取消',
            VoiceHoldAction.transcribe => '松手转文字',
            _ => '松手发送',
          };
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: kVoiceRecordingOverlayHeight,
        decoration: const BoxDecoration(
          color: Color(0xF226262A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 波形时长胶囊。
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x2EFFFFFF),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 16,
                    child: _WaveBars(
                      controller: controller,
                      barCount: 4,
                      maxHeight: 14,
                      barWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatShortClock(durationMs),
                    style: DunesTypography.mono(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 三个圆圈动作，几何与 resolveVoiceHoldAction 一致。
            SizedBox(
              height: 86,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return Stack(
                    children: [
                      for (final entry in voiceHoldCircleLayout(
                        transcribeEnabled,
                      ))
                        Positioned(
                          left: width * entry.fraction - 44,
                          top: 0,
                          bottom: 0,
                          width: 88,
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
            const Spacer(),
            // 录音状态行。
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 10),
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
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      hint,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
        const Icon(Icons.check_rounded, size: 30, color: Colors.white),
      ),
      VoiceHoldAction.transcribe => (
        '转文字',
        Text(
          '文',
          style: DunesTypography.sans(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      VoiceHoldAction.cancel => (
        '取消',
        const Icon(Icons.close_rounded, size: 30, color: Colors.white),
      ),
      _ => ('', const SizedBox.shrink()),
    };
    final highlightColor = action == VoiceHoldAction.cancel
        ? _kWeChatRed
        : _kWeChatGreen;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: highlighted ? 1.16 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted ? highlightColor : const Color(0xFF3A3A3C),
            ),
            alignment: Alignment.center,
            child: icon,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: DunesTypography.sans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: highlighted
                ? Colors.white
                : Colors.white.withValues(alpha: 0.6),
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
        final opacity = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(controller.value * math.pi * 2));
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kWeChatRed,
            ),
          ),
        );
      },
    );
  }
}

class _WaveBars extends StatelessWidget {
  const _WaveBars({
    required this.controller,
    required this.barCount,
    required this.maxHeight,
    required this.barWidth,
    required this.color,
  });

  final Animation<double> controller;
  final int barCount;
  final double maxHeight;
  final double barWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (index) {
            final wave = math.sin(
              controller.value * math.pi * 2 + index * 0.85,
            );
            return Container(
              width: barWidth,
              height: maxHeight * 0.25 + wave.abs() * maxHeight * 0.75,
              decoration: BoxDecoration(
                color: color,
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
      child: ColoredBox(
        color: const Color(0x59000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xE626262A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '语音转文字中…',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
