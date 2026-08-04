import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'chat_voice_player.dart';
import 'chat_voice_temp_stub.dart'
    if (dart.library.io) 'chat_voice_temp_io.dart' as voice_temp;

const _kWeChatGreen = Color(0xFF07C160);

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

/// 微信式「语音转文字」全屏面板（图三）。
///
/// 顶部：取消 ｜ 语音转文字 ｜ 发送原语音；
/// 内容：悬浮卡片，播放条（播放/波形/时长）与识别文本分层展示，
/// 点击文本直接编辑；底部：提示语 + 全宽绿色「发送」按钮。
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
    transitionDuration: const Duration(milliseconds: 260),
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
          begin: const Offset(0, 0.06),
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
    return Material(
      color: const Color(0xFFF5F6F7),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        MediaQuery.sizeOf(context).width * 0.9,
                        560,
                      ),
                    ),
                    child: _buildTranscriptCard(),
                  ),
                ),
              ),
            ),
            _buildBottomBar(viewInsets.bottom + viewPadding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEBECEE))),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _HeaderTextButton(
              label: '取消',
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Center(
            child: Text(
              '语音转文字',
              style: DunesTypography.sans(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ),
          if (_canSendOriginal)
            Align(
              alignment: Alignment.centerRight,
              child: _HeaderTextButton(
                label: '发送原语音',
                onTap: () => Navigator.of(
                  context,
                ).pop(const VoiceTranscriptResult.original()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEFF1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPlaybackRow(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF0F1F2)),
          ),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: null,
            style: DunesTypography.sans(
              fontSize: 16.5,
              height: 1.5,
              color: DunesColors.text,
            ),
            cursorColor: _kWeChatGreen,
            decoration: const InputDecoration.collapsed(hintText: '识别结果'),
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
                height: 22,
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
                color: DunesColors.text3,
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
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFD6D8DB),
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          size: 20,
          color: Colors.white,
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: _preparingPlay
          ? const SizedBox(
              width: 34,
              height: 34,
              child: Padding(
                padding: EdgeInsets.all(7),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _kWeChatGreen,
                ),
              ),
            )
          : Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kWeChatGreen,
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
    );
  }

  Widget _buildBottomBar(double bottomPadding) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEBECEE))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.edit_outlined,
                size: 13,
                color: DunesColors.text3,
              ),
              const SizedBox(width: 5),
              Text(
                '点击文字可以重新编辑或修改，点击发送',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: _canSubmit ? _submitText : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kWeChatGreen,
                disabledBackgroundColor: _kWeChatGreen.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23),
                ),
              ),
              child: Text(
                '发送',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: DunesTypography.sans(
            fontSize: 15.5,
            color: DunesColors.text2,
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
            final base = 4 + (seed % 1) * 14;
            final sway = playing
                ? math.sin(controller.value * math.pi * 2 + index * 0.62).abs() *
                      8
                : 0.0;
            return Container(
              width: 2.5,
              height: base + sway,
              decoration: BoxDecoration(
                color: _kWeChatGreen.withValues(alpha: playing ? 0.9 : 0.38),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
