import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 豆包风格的底部录音面板；不拦截长按手势，以便用户松手发送或上滑取消。
class VoiceRecordingOverlay extends StatefulWidget {
  const VoiceRecordingOverlay({
    super.key,
    required this.durationMs,
    required this.willCancel,
  });

  final int durationMs;
  final bool willCancel;

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
    final prompt = widget.willCancel ? '松手取消' : '松手发送，上滑取消';
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipPath(
          clipper: _VoiceRecordingArcClipper(),
          child: Container(
            height: 205,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0.42),
                radius: 1.08,
                colors: [
                  Color(0xFF00A7F1),
                  Color(0xFF08B9F6),
                  Color(0xFF47CFFB),
                  Color(0xFF9AE8FF),
                ],
                stops: [0, 0.42, 0.76, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x330075A8),
                  blurRadius: 16,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 63),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: widget.willCancel
                        ? const Color(0xD9D94B4B)
                        : const Color(0x26006699),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    prompt,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(31, (index) {
                        final wave = math.sin(
                          (_waveController.value * math.pi * 2) + index * 0.72,
                        );
                        final envelope =
                            0.36 + 0.64 * math.sin(index * math.pi / 30);
                        final height = 5 + (wave.abs() * 25 * envelope);
                        return Container(
                          width: 2.5,
                          height: height,
                          margin: const EdgeInsets.symmetric(horizontal: 1.3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 参考豆包录音面板：顶部向上拱起、两侧回落的半椭圆边缘。
class _VoiceRecordingArcClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const edgeDrop = 22.0;
    return Path()
      ..moveTo(0, edgeDrop)
      ..quadraticBezierTo(size.width / 2, -edgeDrop, size.width, edgeDrop)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_VoiceRecordingArcClipper oldClipper) => false;
}
