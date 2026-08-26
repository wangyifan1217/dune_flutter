import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/util/native_permissions.dart';
import '../../auth/auth_session.dart';
import '../../chat/native_audio_recorder.dart';
import '../../meeting/meeting_live_controller.dart';
import 'native_tau_voice_call_audio.dart';
import 'native_tau_voice_call_callkit.dart';
import 'tau_voice_call_barge_in.dart';
import 'tau_voice_call_client.dart';
import 'tau_voice_call_playback.dart';

enum TauVoiceCallMode { professional, casual }

enum TauVoiceCallState { listening, thinking, speaking, muted }

class TauVoiceCallPage extends StatefulWidget {
  const TauVoiceCallPage({
    super.key,
    required this.session,
    required this.onProfessionalPrompt,
  });

  final AuthSession session;
  final Future<String> Function(String heardText) onProfessionalPrompt;

  @override
  State<TauVoiceCallPage> createState() => _TauVoiceCallPageState();
}

class _TauVoiceCallPageState extends State<TauVoiceCallPage>
    with TickerProviderStateMixin {
  static const _languageLabels = <String, String>{
    'zh': '普通话',
    'en': 'English',
    'yue': '粤语',
    'dongbei': '东北话',
    'chongqing': '重庆话',
    'beijing': '北京话',
    'wuhan': '武汉话',
  };

  late final TauVoiceCallClient _client;
  late final AudioPlayer _player;
  late final AnimationController _pulse;
  TauVoiceCallMode _mode = TauVoiceCallMode.professional;
  TauVoiceCallState _state = TauVoiceCallState.listening;
  StreamSubscription<Uint8List>? _pcmSubscription;
  BytesBuilder? _pcmBytes;
  DateTime? _lastVoiceAt;
  bool _hasVoice = false;
  final List<Map<String, String>> _casualHistory = [];
  bool _recording = false;
  bool _callStarted = false;
  bool _micStarted = false;
  bool _playbackActive = false;
  bool _turnInterrupted = false;
  int _listenEpoch = 0;
  final TauVoiceCallBargeIn _bargeIn = TauVoiceCallBargeIn();
  bool _webSearch = false;
  String _lang = 'zh';
  static const _gender = 'female';
  String _status = '点击通话开始';
  DateTime? _startedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  int _sessionId = 0;
  String? _callKitId;
  bool _closing = false;
  StreamSubscription<TauVoiceCallHangup>? _callKitHangupSubscription;
  StreamSubscription<Map<String, dynamic>>? _nativeEventSubscription;

  @override
  void initState() {
    super.initState();
    _client = TauVoiceCallClient(widget.session);
    _player = AudioPlayer(
      handleInterruptions: defaultTargetPlatform != TargetPlatform.iOS,
      handleAudioSessionActivation: defaultTargetPlatform != TargetPlatform.iOS,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _lang = widget.session.novaVoiceCallLang;
    _callKitHangupSubscription = NativeTauVoiceCallCallKit.instance.hangups
        .listen((_) {
          unawaited(_hangup());
        });
    _nativeEventSubscription = NativeTauVoiceCallAudio.instance.events().listen(
      (event) {
        if (event['kind'] == 'hangup') {
          unawaited(_hangup());
        }
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _startedAt;
      if (!mounted || startedAt == null || _closing) return;
      setState(() => _elapsed = DateTime.now().difference(startedAt));
    });
  }

  @override
  void dispose() {
    _closing = true;
    _ticker?.cancel();
    _pcmSubscription?.cancel();
    _nativeEventSubscription?.cancel();
    _callKitHangupSubscription?.cancel();
    _pulse.stop();
    if (_callKitId != null) {
      unawaited(NativeTauVoiceCallCallKit.instance.endCall(_callKitId));
    }
    unawaited(NativeTauVoiceCallAudio.instance.cancel());
    unawaited(stopTauVoicePlayback(_player));
    _pulse.dispose();
    if (_sessionId > 0) {
      unawaited(
        _client.endSession(_sessionId, durationSec: _elapsed.inSeconds),
      );
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _hangup() async {
    if (_closing) return;
    _closing = true;
    _ticker?.cancel();
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    _micStarted = false;
    _pulse.stop();
    try {
      await NativeTauVoiceCallAudio.instance.cancel();
    } catch (_) {}
    try {
      await stopTauVoicePlayback(_player);
    } catch (_) {}
    if (!mounted) return;
    // Let the route and the underlying chat finish their current layout pass
    // before removing this full-screen page. Popping in a layout callback can
    // trip RenderObject's debugNeedsLayout assertion on Windows.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _startCallKit() async {
    _callKitId = await NativeTauVoiceCallCallKit.instance.startCall();
  }

  Future<void> _startAuditSession() async {
    try {
      _sessionId = await _client.startSession(
        mode: _mode.name,
        lang: _lang,
        gender: _gender,
        webSearch: _webSearch,
      );
    } catch (_) {
      // Audit persistence must not prevent an entitled user from calling.
    }
  }

  Future<void> _toggleRecord() async {
    if (_closing || _state == TauVoiceCallState.muted) return;
    if (!_callStarted && MeetingLiveController.instance.isActive) {
      _showError('会议录音进行中，暂无法使用 τ 电话');
      return;
    }
    if (!_callStarted) {
      final needsMobilePermission =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);
      if (needsMobilePermission && !await _ensureCallPermissions()) {
        return;
      }
      _callStarted = true;
      _startedAt = DateTime.now();
      unawaited(_startAuditSession());
      try {
        await _startCallKit();
      } catch (_) {
        // CallKit is best-effort; capture and playback must still start.
      }
    } else if (_recording) {
      return;
    }
    try {
      await _ensureMic();
      _armCapture();
      if (mounted) {
        setState(() {
          _state = TauVoiceCallState.listening;
          _status = '已接通，请开始说话；停顿后 τ 会回复，说话中可打断';
        });
      }
    } catch (e) {
      await _pcmSubscription?.cancel();
      _pcmSubscription = null;
      _pcmBytes = null;
      _micStarted = false;
      if (!mounted) return;
      _showError(
        e is NativeAudioRecorderBusyException
            ? e.message
            : e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<bool> _ensureCallPermissions() async {
    if (!await ensureMicrophonePermission()) {
      if (mounted) {
        _showError(microphonePermissionHint(await Permission.microphone.status));
      }
      return false;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final notification = await Permission.notification.status;
      if (!notification.isGranted && !notification.isLimited) {
        await Permission.notification.request();
      }
    }
    return true;
  }

  Future<void> _ensureMic() async {
    _pcmSubscription ??= NativeTauVoiceCallAudio.instance.pcmStream().listen(
      _onPcmChunk,
    );
    if (_micStarted) return;
    await NativeTauVoiceCallAudio.instance.start();
    _micStarted = true;
  }

  void _armCapture() {
    _listenEpoch++;
    _pcmBytes = BytesBuilder(copy: false);
    _lastVoiceAt = null;
    _hasVoice = false;
    _recording = true;
    _bargeIn.reset();
  }

  void _onPcmChunk(Uint8List chunk) {
    if (_closing || _state == TauVoiceCallState.muted) return;
    if (_playbackActive && _state == TauVoiceCallState.speaking) {
      if (_bargeIn.observePeak(_pcmPeak(chunk))) {
        _interruptSpeaking(chunk);
      }
      return;
    }
    final builder = _pcmBytes;
    if (builder == null) return;
    builder.add(chunk);
    if (_state == TauVoiceCallState.thinking) return;
    if (_pcmPeak(chunk) > 900) {
      _hasVoice = true;
      _lastVoiceAt = DateTime.now();
      return;
    }
    final lastVoiceAt = _lastVoiceAt;
    if (_hasVoice &&
        lastVoiceAt != null &&
        DateTime.now().difference(lastVoiceAt) >=
            const Duration(milliseconds: 850) &&
        _recording) {
      unawaited(_finishTurn());
    }
  }

  void _interruptSpeaking(Uint8List firstChunk) {
    if (_closing || !_playbackActive || _state != TauVoiceCallState.speaking) {
      return;
    }
    _turnInterrupted = true;
    _playbackActive = false;
    _bargeIn.reset();
    unawaited(stopTauVoicePlayback(_player));
    _armCapture();
    _pcmBytes?.add(firstChunk);
    _hasVoice = true;
    _lastVoiceAt = DateTime.now();
    if (!mounted) return;
    setState(() {
      _state = TauVoiceCallState.listening;
      _status = '已打断，正在听';
    });
  }

  Future<void> _finishTurn() async {
    if (_closing || _state == TauVoiceCallState.thinking) return;
    setState(() {
      _recording = false;
      _state = TauVoiceCallState.thinking;
      _status = _mode == TauVoiceCallMode.professional ? 'τ 正在想' : '正在回复';
    });
    final pcm = _pcmBytes?.takeBytes() ?? Uint8List(0);
    _pcmBytes = null;
    // 16 kHz × 16-bit mono PCM = 32 bytes per millisecond.
    if (pcm.lengthInBytes < 350 * 32) {
      _armCapture();
      if (mounted) {
        setState(() {
          _state = TauVoiceCallState.listening;
          _status = '这句话太短了，请再说一次';
        });
      }
      return;
    }
    try {
      final audio = base64Encode(_pcm16MonoToWav(pcm, sampleRate: 16000));
      if (_mode == TauVoiceCallMode.professional) {
        final heard = await _client.listen(audio);
        if (_closing) return;
        if (heard.isEmpty || _looksLikeZhipuPersona(heard)) {
          throw Exception('没有听清，请再说一次');
        }
        final reply = await widget.onProfessionalPrompt(heard);
        if (_closing) return;
        var spokenText = reply.trim();
        if (spokenText.isEmpty) {
          throw Exception('NOVA 没有返回内容');
        }
        if (_mentionsZhipuPersona(spokenText)) {
          spokenText = _stripZhipuPersona(spokenText);
          if (spokenText.isEmpty) spokenText = '嗯，我在听。';
        }
        final spoken = await _client.speak(
          lang: _lang,
          gender: _gender,
          text: spokenText,
        );
        if (_closing) return;
        final interrupted = await _speak(spoken);
        if (_closing) return;
        if (_sessionId > 0) {
          unawaited(
            _client.addTurn(
              _sessionId,
              userText: heard,
              assistantText: spokenText,
              interrupted: interrupted,
              searchUsed: false,
            ),
          );
        }
      } else {
        final reply = await _client.chat(
          lang: _lang,
          gender: _gender,
          audioWavBase64: audio,
          webSearch: _webSearch,
          history: _casualHistory,
        );
        if (_closing) return;
        _casualHistory
          ..add({
            'role': 'user',
            'content': reply.heardText.isEmpty ? '用户刚才的语音' : reply.heardText,
          })
          ..add({'role': 'assistant', 'content': reply.text});
        if (_casualHistory.length > 20) {
          _casualHistory.removeRange(0, _casualHistory.length - 20);
        }
        final interrupted = await _speak(reply);
        if (_closing) return;
        if (_sessionId > 0) {
          unawaited(
            _client.addTurn(
              _sessionId,
              userText: reply.heardText,
              assistantText: reply.text,
              interrupted: interrupted,
              searchUsed: reply.searchUsed,
            ),
          );
        }
      }
    } catch (e) {
      if (!_recording) {
        _armCapture();
      }
      if (mounted) {
        setState(() {
          if (_state != TauVoiceCallState.listening) {
            _state = TauVoiceCallState.listening;
            _status = '正在听';
          }
        });
        _showError(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<bool> _speak(TauVoiceCallReply reply) async {
    if (_closing || !mounted) return false;
    if (reply.audioBase64.isEmpty) {
      throw Exception('τ电话没有返回语音');
    }
    if (_playbackActive) {
      await stopTauVoicePlayback(_player);
      _playbackActive = false;
    }
    final epoch = _listenEpoch;
    _turnInterrupted = false;
    setState(() {
      _state = TauVoiceCallState.speaking;
      _status = reply.searchUsed ? 'τ 正在说 · 已联网，可打断' : 'τ 正在说，可打断';
    });
    var bytes = base64Decode(reply.audioBase64);
    if (reply.isRawPcm && !_isWav(bytes)) {
      if (reply.channels != 1 || reply.bitsPerSample != 16) {
        throw Exception(
          'τ电话返回了不支持的 PCM 格式：'
          '${reply.channels} 声道 / ${reply.bitsPerSample} 位',
        );
      }
      final rate = reply.sampleRate > 0 ? reply.sampleRate : 24000;
      bytes = _pcm16MonoToWav(bytes, sampleRate: rate);
    } else if (!_isWav(bytes)) {
      throw Exception(
        'τ电话 audioBase64 不是有效 WAV'
        '（${reply.audioFormat} / ${reply.mimeType}）',
      );
    }
    _bargeIn.onPlaybackStarted();
    _playbackActive = true;
    try {
      await playTauVoiceBytes(
        _player,
        bytes,
        'audio/wav',
        isCancelled: () => _turnInterrupted || _closing,
      );
    } finally {
      _playbackActive = false;
      _bargeIn.reset();
    }
    if (!mounted || _closing) return _turnInterrupted || epoch != _listenEpoch;
    final interrupted = _turnInterrupted || epoch != _listenEpoch;
    if (interrupted) return true;
    if (_state != TauVoiceCallState.muted && _callStarted) {
      _armCapture();
    }
    if (mounted) {
      setState(() {
        _state = TauVoiceCallState.listening;
        _status = '正在听';
      });
    }
    return false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendlyCallError(message))));
  }

  String _friendlyCallError(String message) {
    final text = message.replaceFirst('Exception: ', '');
    final low = text.toLowerCase();
    if (low.contains('561017449') ||
        low.contains('osstatus') ||
        low.contains('cannotstartplaying') ||
        low.contains('voice_call_play_failed')) {
      return '暂时无法播放语音，请再说一次';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final speaking = _state == TauVoiceCallState.speaking;
    final thinking = _state == TauVoiceCallState.thinking;
    final activeCall = _recording || speaking || thinking;
    return Scaffold(
      backgroundColor: const Color(0xFF12101B),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 88,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    Material(
                      color: const Color(0xFF242033),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => _showCallSettings(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                '情景设置',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '女生声音 · ${_languageLabels[_lang] ?? _lang}',
                      style: const TextStyle(
                        color: Color(0xFF9A93B4),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final scale = activeCall
                    ? 1 +
                          (_pulse.value *
                              (speaking
                                  ? .14
                                  : thinking
                                  ? .06
                                  : .09))
                    : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 168,
                height: 168,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF30294B),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x667C5CFF),
                      blurRadius: 36,
                      spreadRadius: 12,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/images/tau_voice_avatar_female.png',
                        width: 168,
                        height: 168,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                    if (thinking)
                      const Positioned(
                        right: 20,
                        top: 21,
                        child: _CallStateBadge(
                          icon: Icons.auto_awesome_rounded,
                          color: Color(0xFFFFD580),
                        ),
                      ),
                    if (speaking)
                      const Positioned(
                        right: 20,
                        top: 21,
                        child: _CallStateBadge(
                          icon: Icons.graphic_eq_rounded,
                          color: Color(0xFFB4A7FF),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _CallStatusDots(active: activeCall, pulse: _pulse.value),
            const SizedBox(height: 14),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatElapsed(_elapsed),
              style: const TextStyle(color: Color(0xFFB8B1CC), fontSize: 13),
            ),
            const Spacer(),
            _controls(),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final callEngaged = _recording || _state == TauVoiceCallState.speaking;
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _modeOption(
              mode: TauVoiceCallMode.professional,
              label: '专业',
              icon: Icons.auto_awesome_rounded,
              onTap: () =>
                  setState(() => _mode = TauVoiceCallMode.professional),
            ),
            _modeOption(
              mode: TauVoiceCallMode.casual,
              label: '闲聊',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => setState(() {
                _mode = TauVoiceCallMode.casual;
                _webSearch = true;
              }),
            ),
            if (_mode == TauVoiceCallMode.casual)
              _modeOption(
                mode: null,
                label: '联网',
                icon: Icons.public_rounded,
                selected: _webSearch,
                onTap: () => setState(() => _webSearch = !_webSearch),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roundControl(
              tooltip: '静音',
              icon: _state == TauVoiceCallState.muted
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              onPressed: () => setState(() {
                _state = _state == TauVoiceCallState.muted
                    ? TauVoiceCallState.listening
                    : TauVoiceCallState.muted;
                _status = _state == TauVoiceCallState.muted ? '已静音' : '正在听';
              }),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 80,
              height: 80,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: callEngaged
                      ? const Color(0xFF7C5CFF)
                      : const Color(0xFF242033),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: _state == TauVoiceCallState.thinking
                    ? null
                    : _toggleRecord,
                child: const Icon(Icons.phone_in_talk_rounded, size: 32),
              ),
            ),
            const SizedBox(width: 16),
            _roundControl(
              tooltip: '挂断',
              icon: Icons.call_end_rounded,
              iconColor: const Color(0xFFFF2323),
              onPressed: _hangup,
            ),
          ],
        ),
      ],
    );
  }

  Widget _roundControl({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF242033),
        shape: const CircleBorder(),
        elevation: 0,
        child: SizedBox(
          width: 80,
          height: 80,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: iconColor),
            iconSize: 31,
            padding: const EdgeInsets.all(20),
          ),
        ),
      ),
    );
  }

  Widget _modeOption({
    required String label,
    required IconData icon,
    TauVoiceCallMode? mode,
    bool? selected,
    VoidCallback? onTap,
  }) {
    final isSelected = selected ?? _mode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? () => setState(() => _mode = mode!),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6F55F6)
                : const Color(0xFF242033),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFB4A7FF)
                  : const Color(0xFF3C3651),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: isSelected
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF9A93B4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCallSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1D192A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '情景设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF29233B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF3B3454)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.language_rounded,
                              color: Color(0xFFC8BBFF),
                            ),
                            SizedBox(width: 13),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '回答语言',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  '设置 τ 电话的默认回答语言',
                                  style: TextStyle(
                                    color: Color(0xFFAEA6C3),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _languageLabels.entries.map((entry) {
                            final selected = entry.key == _lang;
                            return ChoiceChip(
                              label: Text(entry.value),
                              selected: selected,
                              selectedColor: const Color(0xFF7C5CFF),
                              backgroundColor: const Color(0xFF211C31),
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xFFB4A7FF)
                                    : const Color(0xFF4B4267),
                              ),
                              labelStyle: TextStyle(
                                color: Colors.white,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              onSelected: (_) {
                                setState(() => _lang = entry.key);
                                setModalState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ],
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

  String _formatElapsed(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  int _pcmPeak(Uint8List bytes) {
    var peak = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      var sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final magnitude = sample.abs();
      if (magnitude > peak) peak = magnitude;
    }
    return peak;
  }

  Uint8List _pcm16MonoToWav(Uint8List pcm, {required int sampleRate}) {
    final bytes = ByteData(44 + pcm.length);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, pcm.length, Endian.little);
    bytes.buffer.asUint8List(44).setAll(0, pcm);
    return bytes.buffer.asUint8List();
  }

  bool _looksLikeZhipuPersona(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return true;
    return compact.contains('小智') &&
        (compact.contains('智谱') ||
            compact.contains('KEG') ||
            compact.contains('语音助手') ||
            compact.contains('我是小智') ||
            compact.contains('很高兴认识你'));
  }

  bool _mentionsZhipuPersona(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.contains('小智') || compact.contains('智谱');
  }

  String _stripZhipuPersona(String text) {
    final parts = text.split(RegExp(r'[。！？!?\n；;]+'));
    final kept = parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && !_mentionsZhipuPersona(part));
    return kept.join('。').trim();
  }

  bool _isWav(Uint8List bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;
}

class _CallStateBadge extends StatelessWidget {
  const _CallStateBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x180E1633), blurRadius: 10)],
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}

class _CallStatusDots extends StatelessWidget {
  const _CallStatusDots({required this.active, required this.pulse});

  final bool active;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final selected = active && index == 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: selected ? 10 + pulse * 4 : 8,
          height: selected ? 10 + pulse * 4 : 8,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF716D80) : const Color(0xFFB2B3BD),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
