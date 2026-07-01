import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'meeting_live_controller.dart';
import 'native_meeting_recording_controller.dart';
import 'native_meeting_service.dart';

class NativeMeetingCreatePage extends StatefulWidget {
  const NativeMeetingCreatePage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onCreated,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int> onCreated;

  @override
  State<NativeMeetingCreatePage> createState() =>
      _NativeMeetingCreatePageState();
}

class _NativeMeetingCreatePageState extends State<NativeMeetingCreatePage>
    with SingleTickerProviderStateMixin {
  late final NativeMeetingService _service = NativeMeetingService(
    session: widget.session,
  );
  final MeetingRecordingController _recordingCtrl =
      MeetingRecordingController.instance;
  final MeetingLiveController _live = MeetingLiveController.instance;
  final TextEditingController _titleCtrl = TextEditingController();
  String _filePath = '';
  bool _submitting = false;
  String? _error;
  _CreateMode _mode = _CreateMode.upload;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    // 若已有正在进行的实时转写，进入页面默认切到该模式，回显进度。
    // 注意：不自动回填上一次录制的文件，避免上传区出现“莫名其妙的默认文件”。
    if (_live.active.value) {
      _mode = _CreateMode.live;
    }
    _live.active.addListener(_onLiveChanged);
    _live.paused.addListener(_onLiveChanged);
    _live.lines.addListener(_onLiveChanged);
    _live.partial.addListener(_onLiveChanged);
    _recordingCtrl.state.addListener(_onLiveChanged);
  }

  void _onLiveChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _live.active.removeListener(_onLiveChanged);
    _live.paused.removeListener(_onLiveChanged);
    _live.lines.removeListener(_onLiveChanged);
    _live.partial.removeListener(_onLiveChanged);
    _recordingCtrl.state.removeListener(_onLiveChanged);
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'audio', extensions: ['wav', 'mp3', 'm4a']),
      ],
    );
    if (!mounted || file == null) return;
    setState(() {
      _filePath = file.path;
      _error = null;
    });
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final asked = await Permission.microphone.request();
    if (asked.isGranted) return true;
    if (!mounted) return false;
    setState(() => _error = '未授予麦克风权限，请在系统设置中允许后重试');
    return false;
  }

  String _mapRecordError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('meeting session unavailable(501)')) {
      return '实时转写服务暂未在服务器启用（501），请先使用“上传录音转写”';
    }
    if (e is PlatformException) {
      final code = e.code.toLowerCase();
      if (code.contains('audio_strart_falied') ||
          code.contains('audio_start_failed')) {
        return '录音启动失败，请确认麦克风权限和系统录音占用情况';
      }
      if (code.contains('permission')) {
        return '麦克风权限不足，请前往系统设置开启';
      }
      final msg = e.message?.trim() ?? '';
      if (msg.isNotEmpty) return msg;
      return '录音失败：${e.code}';
    }
    return '录音失败：$e';
  }

  Future<void> _startLive() async {
    try {
      final ok = await _ensureMicPermission();
      if (!ok) return;
      setState(() => _error = null);
      await _live.start(widget.session);
    } catch (e) {
      try {
        await _live.end();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _error = _mapRecordError(e));
    }
  }

  Future<void> _endLive() async {
    try {
      final path = await _live.end();
      if (!mounted) return;
      setState(() {
        if (path != null && path.isNotEmpty) _filePath = path;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mapRecordError(e));
    }
  }

  Future<void> _pauseLive() async {
    await _live.pause();
  }

  Future<void> _resumeLive() async {
    await _live.resume();
  }

  Future<void> _submit() async {
    if (_filePath.isEmpty || _titleCtrl.text.trim().isEmpty) {
      setState(() => _error = '请先填写会议标题并选择录音文件');
      return;
    }
    setState(() => _submitting = true);
    try {
      final meetingId = await _service.createByMeetingDoc(
        title: _titleCtrl.text.trim(),
        meetingDate: DateTime.now().toIso8601String().substring(0, 10),
        filePath: _filePath,
      );
      if (!mounted) return;
      widget.onCreated(meetingId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fileLabel() {
    if (_filePath.isEmpty) return '未选择录音文件';
    final normalized = _filePath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx < 0) return normalized;
    return normalized.substring(idx + 1);
  }

  @override
  Widget build(BuildContext context) {
    final state = _recordingCtrl.state.value;
    final liveWorking = _live.active.value;
    final livePaused = _live.paused.value;
    final liveLines = _live.lines.value;
    final livePartial = _live.partial.value;
    final recording = liveWorking;
    final canSubmit = !_submitting &&
        _titleCtrl.text.trim().isNotEmpty &&
        _filePath.isNotEmpty;
    final liveRecording = _mode == _CreateMode.live && recording;
    final statusText = switch (state) {
      MeetingRecordingState.recordingForeground => '正在录音（前台）',
      MeetingRecordingState.recordingBackground => '正在录音（后台/锁屏）',
      MeetingRecordingState.stopping => '停止录音中...',
      MeetingRecordingState.idle => '待开始',
    };

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('新建会议纪要'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF2F5D62), Color(0xFF1B3A3F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 会议纪要',
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _mode == _CreateMode.upload
                            ? '上传或录制音频，生成摘要与待办'
                            : '边录边看实时转写，结束后一键生成纪要',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: CupertinoSlidingSegmentedControl<_CreateMode>(
              groupValue: _mode,
              thumbColor: DunesColors.accent,
              backgroundColor: DunesColors.bgSoft,
              children: {
                _CreateMode.upload: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '上传录音转写',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _mode == _CreateMode.upload
                          ? Colors.white
                          : DunesColors.text2,
                    ),
                  ),
                ),
                _CreateMode.live: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '录音实时转写',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _mode == _CreateMode.live
                          ? Colors.white
                          : DunesColors.text2,
                    ),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value == null || value == _mode) return;
                setState(() {
                  _mode = value;
                  _error = null;
                });
              },
            ),
          ),

          const SizedBox(height: 12),
          _sectionCard(
            title: '会议信息',
            icon: Icons.title_rounded,
            child: TextField(
              controller: _titleCtrl,
              onChanged: (_) => setState(() => _error = null),
              style: DunesTypography.sans(fontSize: 14, color: DunesColors.text),
              decoration: InputDecoration(
                hintText: '请输入会议标题，例如：周例会-销售复盘',
                filled: true,
                fillColor: DunesColors.bgSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DunesColors.borderSoft),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DunesColors.borderSoft),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          if (_mode == _CreateMode.upload) ...[
            _sectionCard(
              title: '录音文件',
              icon: Icons.audio_file_outlined,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: DunesColors.bgSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: DunesColors.borderSoft),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              color: _filePath.isEmpty
                                  ? DunesColors.text3
                                  : DunesColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '支持 wav/mp3/m4a',
                            style: DunesTypography.sans(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: DunesColors.accentSoft,
                    onPressed: _pickFile,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.upload_rounded,
                          size: 18,
                          color: DunesColors.accentDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '上传',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.accentDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_mode == _CreateMode.live) ...[
            _sectionCard(
              title: '实时转写控制',
              icon: Icons.fiber_manual_record_rounded,
              child: Column(
                children: [
                  Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final active = recording && !livePaused;
                          final scale = active ? 0.9 + _pulseController.value * 0.3 : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: recording ? DunesColors.coral : DunesColors.text3,
                                boxShadow: active
                                    ? [
                                        BoxShadow(
                                          color: DunesColors.coral.withValues(alpha: 0.45),
                                          blurRadius: 8,
                                          spreadRadius: 1.5,
                                        ),
                                      ]
                                    : const [],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        liveWorking
                            ? (livePaused ? '实时转写已暂停' : '实时转写进行中')
                            : statusText,
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.text2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!recording)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _startLive,
                        icon: const Icon(Icons.mic_rounded),
                        label: const Text('开始实时转写'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DunesColors.accentDeep,
                          side: const BorderSide(color: DunesColors.accentLine),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: livePaused ? _resumeLive : _pauseLive,
                            icon: Icon(
                              livePaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                            label: Text(livePaused ? '继续转写' : '暂停转写'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DunesColors.accentDeep,
                              side: const BorderSide(color: DunesColors.accentLine),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _endLive,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('结束并保存'),
                            style: FilledButton.styleFrom(
                              backgroundColor: DunesColors.coral,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: '实时转写预览',
              icon: Icons.record_voice_over_outlined,
              child: liveLines.isEmpty && livePartial.isEmpty
                  ? Text(
                      liveRecording && !livePaused
                          ? '正在监听语音，请开始发言...'
                          : (liveRecording && livePaused)
                          ? '已暂停，点击“继续转写”后恢复实时识别'
                          : '点击“开始实时转写”后，这里会实时显示文字',
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: DunesColors.text3,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (livePartial.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              livePartial,
                              style: DunesTypography.sans(
                                fontSize: 13,
                                color: DunesColors.accent,
                                height: 1.5,
                              ).copyWith(fontStyle: FontStyle.italic),
                            ),
                          ),
                        ...liveLines
                            .take(8)
                            .map(
                              (line) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  line,
                                  style: DunesTypography.sans(
                                    fontSize: 13,
                                    color: DunesColors.text2,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DunesColors.coralSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: DunesColors.coral,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.coral,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: canSubmit ? _submit : null,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _submitting
                  ? '处理中...'
                  : (_mode == _CreateMode.live ? '结束后生成会议纪要' : '开始转写并生成纪要'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: DunesColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

enum _CreateMode { upload, live }
