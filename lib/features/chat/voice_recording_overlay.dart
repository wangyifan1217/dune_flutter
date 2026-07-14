import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

const kVoiceRecordingOverlayHeight = 205.0;

/// 覆盖输入区的录音蒙层；主视觉不拦截长按手势，以便用户松手发送或上滑取消。
class VoiceRecordingOverlay extends StatefulWidget {
  const VoiceRecordingOverlay({
    super.key,
    required this.durationMs,
    required this.willCancel,
    this.focalPoint,
  });

  final int durationMs;
  final bool willCancel;
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
      duration: const Duration(milliseconds: 880),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: kVoiceRecordingOverlayHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final focal = widget.focalPoint;
            final x = focal == null
                ? 0.0
                : ((focal.dx / constraints.maxWidth) * 2 - 1)
                      .clamp(-1.0, 1.0)
                      .toDouble();
            final y = focal == null
                ? 0.35
                : (((focal.dy -
                                      (MediaQuery.sizeOf(context).height -
                                          constraints.maxHeight)) /
                                  constraints.maxHeight) *
                              2 -
                          1)
                      .clamp(-1.0, 1.0)
                      .toDouble();
            final colors = widget.willCancel
                ? const [
                    Color(0xB3FF7075),
                    Color(0x8FFF9FA2),
                    Color(0x33FFD7D8),
                  ]
                : const [
                    Color(0xB3009FEA),
                    Color(0x8F16B8F4),
                    Color(0x339BE7FF),
                  ];
            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(x, y),
                        radius: 1.05,
                        colors: colors,
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '松手发送，上移取消',
                            style: DunesTypography.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FractionallySizedBox(
                            widthFactor: 0.75,
                            child: AnimatedBuilder(
                              animation: _waveController,
                              builder: (context, _) {
                                return Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: List.generate(43, (index) {
                                    final wave = math.sin(
                                      (_waveController.value * math.pi * 2) +
                                          index * 0.72,
                                    );
                                    final envelope =
                                        0.35 +
                                        0.65 * math.sin(index * math.pi / 42);
                                    final height =
                                        5 + (wave.abs() * 18 * envelope);
                                    return Container(
                                      width: 2,
                                      height: height,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
