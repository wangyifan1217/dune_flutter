import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'chat_voice_player.dart';
import 'chat_voice_temp_stub.dart'
    if (dart.library.io) 'chat_voice_temp_io.dart' as voice_temp;

enum VoiceTranscriptAction { text, original }

class VoiceTranscriptResult {
  const VoiceTranscriptResult._(this.action, this.text);

  const VoiceTranscriptResult.text(String value)
    : this._(VoiceTranscriptAction.text, value);

  const VoiceTranscriptResult.original()
    : this._(VoiceTranscriptAction.original, '');

  final VoiceTranscriptAction action;
  final String text;
}

/// 微信式「语音转文字」半屏浮层。
///
/// 不再铺满整屏：上方露出聊天内容并压暗，内容在下侧深色面板中，
/// 底部为「取消 ｜ 发送原语音 ｜ 发送」三个操作胶囊。
Future<VoiceTranscriptResult?> showVoiceTranscriptPanel({
  required BuildContext context,
  required String transcript,
  required int durationSec,
  String? originalFilePath,
  Uint8List? originalBytes,
  Future<Uint8List> Function()? loadOriginalBytes,
  String fileName = 'voice.m4a',
}) {
  return showGeneralDialog<VoiceTranscriptResult>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '语音转文字',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (routeContext, animation, secondaryAnimation) {
      return VoiceTranscriptPanel(
        transcript: transcript,
        durationSec: durationSec,
        originalFilePath: originalFilePath,
        originalBytes: originalBytes,
        loadOriginalBytes: loadOriginalBytes,
        fileName: fileName,
      );
    },
    transitionBuilder: (routeContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class VoiceTranscriptPanel extends StatefulWidget {
  const VoiceTranscriptPanel({
    super.key,
    required this.transcript,
    required this.durationSec,
    this.originalFilePath,
    this.originalBytes,
    this.loadOriginalBytes,
    required this.fileName,
  });

  final String transcript;
  final int durationSec;
  final String? originalFilePath;
  final Uint8List? originalBytes;
  final Future<Uint8List> Function()? loadOriginalBytes;
  final String fileName;

  @override
  State<VoiceTranscriptPanel> createState() => _VoiceTranscriptPanelState();
}

class _VoiceTranscriptPanelState extends State<VoiceTranscriptPanel>
    with SingleTickerProviderStateMixin {
  static const _playKey = 'voice-transcript-draft';

  late final TextEditingController _controller;
  late final AnimationController _waveController;
  bool _preparingPlay = false;
  bool _canSubmit = true;

  bool get _playing => ChatVoicePlayer.instance.playingKey == _playKey;

  bool get _canSendOriginal =>
      widget.originalFilePath != null ||
      widget.originalBytes != null ||
      widget.loadOriginalBytes != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.transcript.trim());
    _canSubmit = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    ChatVoicePlayer.instance.addListener(_syncWave);
  }

  @override
  void dispose() {
    ChatVoicePlayer.instance.removeListener(_syncWave);
    ChatVoicePlayer.instance.stop();
    _waveController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final canSubmit = _controller.text.trim().isNotEmpty;
    if (canSubmit != _canSubmit) setState(() => _canSubmit = canSubmit);
  }

  void _syncWave() {
    if (!mounted) return;
    if (_playing) {
      if (!_waveController.isAnimating) _waveController.repeat();
    } else {
      _waveController.stop();
      _waveController.value = 0;
    }
  }

  Future<void> _togglePlay() async {
    if (_preparingPlay) return;
    setState(() => _preparingPlay = true);
    try {
      var path = widget.originalFilePath;
      if (path == null) {
        final bytes =
            widget.originalBytes ?? await widget.loadOriginalBytes?.call();
        if (bytes != null) {
          path = await voice_temp.writeChatVoiceTempFileImpl(
            bytes,
            fileName: widget.fileName,
          );
        }
      }
      if (path == null || !mounted) return;
      await ChatVoicePlayer.instance.toggleFile(_playKey, path);
    } catch (_) {
      // 播放失败不打断编辑，气泡保持可编辑状态。
    } finally {
      if (mounted) setState(() => _preparingPlay = false);
    }
  }

  void _submitText() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(VoiceTranscriptResult.text(value));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final maxSheetHeight = screen.height * 0.62;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 露出上层聊天并压暗。
          const ColoredBox(color: Color(0xA3000000)),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(screen.width, 560),
                maxHeight: maxSheetHeight,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF19191B),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: viewInsets.bottom > 0
                          ? viewInsets.bottom
                          : viewPadding.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        // 顶部指示条。
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                            child: _buildTranscriptCard(),
                          ),
                        ),
                        _buildActionBar(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF242426),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E31)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPlaybackRow(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 11),
            child: Divider(height: 1, color: Color(0xFF303034)),
          ),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 8,
            style: DunesTypography.sans(
              fontSize: 16,
              height: 1.5,
              color: Colors.white,
            ),
            cursorColor: const Color(0xFF07C160),
            decoration: InputDecoration.collapsed(
              hintText: '识别结果',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackRow() {
    return AnimatedBuilder(
      animation: ChatVoicePlayer.instance,
      builder: (context, _) {
        final playing = _playing;
        return Row(
          children: [
            _buildPlayButton(playing),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 20,
                child: _VoicePrintBars(
                  controller: _waveController,
                  playing: playing,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "${widget.durationSec}''",
              style: DunesTypography.mono(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayButton(bool playing) {
    if (!_canSendOriginal) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.22),
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: _preparingPlay
          ? const SizedBox(
              width: 30,
              height: 30,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF07C160),
                ),
              ),
            )
          : Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF07C160),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A2D))),
      ),
      child: Row(
        children: [
          _ActionCapsule(
            label: '取消',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          _ActionCapsule(
            label: '发送原语音',
            enabled: _canSendOriginal,
            onTap: () => Navigator.of(
              context,
            ).pop(const VoiceTranscriptResult.original()),
          ),
          const Spacer(),
          _SendCapsule(enabled: _canSubmit, onTap: _submitText),
        ],
      ),
    );
  }
}

class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF2E2E31)
              : const Color(0xFF2E2E31).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text(
          label,
          style: DunesTypography.sans(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: enabled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _SendCapsule extends StatelessWidget {
  const _SendCapsule({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF07C160)
              : const Color(0xFF07C160).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text(
          '发送',
          style: DunesTypography.sans(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 语音波纹：静止时展示固定纹样的声纹，播放中跳动。
class _VoicePrintBars extends StatelessWidget {
  const _VoicePrintBars({required this.controller, required this.playing});

  final Animation<double> controller;
  final bool playing;

  static const _barCount = 24;
  static const _green = Color(0xFF07C160);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_barCount, (index) {
            final seed = (math.sin(index * 1.73) + math.sin(index * 0.61)).abs();
            final base = 3 + (seed % 1) * 12;
            final sway = playing
                ? math.sin(controller.value * math.pi * 2 + index * 0.62).abs() *
                      7
                : 0.0;
            return Container(
              width: 2.5,
              height: base + sway,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: playing ? 0.95 : 0.42),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
