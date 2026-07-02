import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'meeting_live_controller.dart';
import 'meeting_upload_coordinator.dart';
import 'native_meeting_recording_controller.dart';
import 'native_meeting_service.dart';

class NativeMeetingCreatePage extends StatefulWidget {
  const NativeMeetingCreatePage({
    super.key,
    required this.session,
    required this.navigation,
    required this.onBack,
    required this.onCreated,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final VoidCallback onBack;
  final void Function(int meetingId, {required bool isDraft}) onCreated;

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
  bool _persistingAfterEnd = false;
  bool? _persistGenerate;
  bool _pendingPersistAfterEnd = false;
  String _pendingDraftTitle = '';
  bool _handlingBack = false;
  String? _error;
  _CreateMode _mode = _CreateMode.upload;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    widget.navigation.backInterceptor = _navigationBackInterceptor;
    if (_live.active.value) {
      _mode = _CreateMode.live;
      final savedTitle = _live.meetingTitle.value.trim();
      if (savedTitle.isNotEmpty && _titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = savedTitle;
      }
    } else {
      _live.clearPreview();
      final pendingPath = _live.recordedFilePath.value?.trim() ?? '';
      if (pendingPath.isNotEmpty) {
        _filePath = pendingPath;
        _pendingPersistAfterEnd = true;
        _pendingDraftTitle = _live.meetingTitle.value.trim();
        if (_pendingDraftTitle.isNotEmpty && _titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = _pendingDraftTitle;
        }
      } else {
        _live.consumeRecordedFile();
        _filePath = '';
        _pendingDraftTitle = '';
      }
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
    widget.navigation.backInterceptor = null;
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
    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'audio',
            extensions: ['wav', 'mp3', 'm4a'],
            mimeTypes: [
              'audio/wav',
              'audio/x-wav',
              'audio/mpeg',
              'audio/mp4',
              'audio/m4a',
            ],
            // iOS 必须提供 UTI，否则选择器无法选中音频文件。
            uniformTypeIdentifiers: [
              'public.audio',
              'com.microsoft.waveform-audio',
              'public.mp3',
              'public.mpeg-4-audio',
              'com.apple.m4a-audio',
            ],
          ),
        ],
      );
    } catch (_) {
      // iOS 上类型声明异常时兜底：不加过滤，避免选择器弹不出来。
      try {
        file = await openFile();
      } catch (_) {
        file = null;
      }
    }
    final picked = file;
    if (!mounted || picked == null) return;
    setState(() {
      _filePath = picked.path;
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

  bool get _hasMeetingTitle => _titleCtrl.text.trim().isNotEmpty;

  String _defaultDraftTitle() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '会议录音 $now.year-$month-$day $hour:$minute';
  }

  String _resolvedPersistTitle() {
    final fromField = _titleCtrl.text.trim();
    if (fromField.isNotEmpty) return fromField;
    final fromLive = _live.meetingTitle.value.trim();
    if (fromLive.isNotEmpty) return fromLive;
    final pending = _pendingDraftTitle.trim();
    if (pending.isNotEmpty) return pending;
    return _defaultDraftTitle();
  }

  Future<void> _startLive() async {
    if (!_hasMeetingTitle) {
      const msg = '请先填写会议标题后再开始实时转写';
      setState(() => _error = msg);
      showDunesToast(context, msg, kind: DunesToastKind.error);
      return;
    }
    try {
      final ok = await _ensureMicPermission();
      if (!ok) return;
      setState(() => _error = null);
      await _live.start(widget.session, title: _titleCtrl.text.trim());
    } catch (e) {
      try {
        await _live.end();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _error = _mapRecordError(e));
    }
  }

  Future<void> _confirmEndLive() async {
    if (!_live.active.value || _persistingAfterEnd) return;
    _dismissKeyboard();
    final title = _resolvedPersistTitle();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('结束并保存？'),
        content: Text(
          '确定要结束录音「$title」吗？\n\n'
          '结束后将无法继续追加录音，接下来可选择存为草稿或立即生成纪要。',
          style: DunesTypography.sans(fontSize: 13.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续录音'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('结束并保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _endLive();
  }

  Future<void> _endLive() async {
    try {
      final path = await _live.end();
      if (!mounted) return;
      final resolvedTitle = _resolvedPersistTitle();
      setState(() {
        if (path != null && path.isNotEmpty) {
          _filePath = path;
          _pendingPersistAfterEnd = true;
          _pendingDraftTitle = resolvedTitle;
          if (_titleCtrl.text.trim().isEmpty) {
            _titleCtrl.text = resolvedTitle;
          }
        }
        _error = null;
      });
      if (path == null || path.isEmpty) {
        setState(() => _error = '录音文件保存失败，请重试');
        return;
      }
      await _promptPersistAfterEnd(filePath: path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mapRecordError(e));
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool _navigationBackInterceptor() {
    if (_handlingBack) return true;
    unawaited(_handleBack());
    return true;
  }

  Future<void> _promptPersistAfterEnd({
    required String filePath,
  }) async {
    _dismissKeyboard();
    final displayTitle = _resolvedPersistTitle();
    final generate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('是否生成会议纪要？'),
        content: Text(
          '录音「$displayTitle」已结束。\n\n'
          '选择「立即生成」将上传录音并开始转写；'
          '选择「存为草稿」会保存到列表，稍后可进详情页生成。',
          style: DunesTypography.sans(fontSize: 13.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _dismissKeyboard();
              Navigator.of(ctx).pop(false);
            },
            child: const Text('存为草稿'),
          ),
          FilledButton(
            onPressed: () {
              _dismissKeyboard();
              Navigator.of(ctx).pop(true);
            },
            child: const Text('立即生成'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final title = _resolvedPersistTitle();
    if (generate == null) {
      // 系统返回键关闭弹窗时，自动存为草稿。
      await _persistAfterEnd(
        title: title,
        filePath: filePath,
        generate: false,
      );
      return;
    }
    await _persistAfterEnd(
      title: title,
      filePath: filePath,
      generate: generate,
    );
  }

  Future<bool> _confirmLeaveWhileProcessing() async {
    _dismissKeyboard();
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('正在处理中'),
        content: Text(
          _persistingAfterEnd
              ? '正在创建会议记录，现在离开可能导致提交失败。'
              : '录音正在后台上传，现在离开不影响上传进度。',
          style: DunesTypography.sans(fontSize: 13.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('仍要离开'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _handleBack() async {
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      if (_submitting || _persistingAfterEnd) {
        final leave = await _confirmLeaveWhileProcessing();
        if (!leave || !mounted) return;
        widget.onBack();
        return;
      }
      // 录音进行中：允许离开页面，后台继续录音（其它板块有悬浮入口可返回）。
      if (_live.active.value) {
        widget.onBack();
        return;
      }
      // 仅「结束并保存」后、尚未提交时，滑动返回自动存草稿。
      if (_pendingPersistAfterEnd && _filePath.trim().isNotEmpty) {
        final saved = await _tryAutoSaveDraftOnLeave();
        if (saved || !mounted) return;
      }
      widget.onBack();
    } finally {
      _handlingBack = false;
    }
  }

  Future<bool> _tryAutoSaveDraftOnLeave() async {
    final filePath = _filePath.trim();
    if (filePath.isEmpty || !_pendingPersistAfterEnd) return false;
    final title = _resolvedPersistTitle();

    try {
      await _persistAfterEnd(
        title: title,
        filePath: filePath,
        generate: false,
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      final msg = friendlyErrorText(
        e,
        fallback: '自动存草稿失败，请稍后重试',
      );
      setState(() => _error = '自动存草稿失败：$msg');
      showDunesToast(context, msg, kind: DunesToastKind.error);
      return false;
    }
  }

  Future<void> _persistAfterEnd({
    required String title,
    required String filePath,
    required bool generate,
  }) async {
    _dismissKeyboard();
    setState(() {
      _persistingAfterEnd = true;
      _persistGenerate = generate;
      _error = null;
    });
    try {
      final meetingDate = DateTime.now().toIso8601String().substring(0, 10);
      final meetingId = await MeetingUploadCoordinator.instance.enqueue(
        session: widget.session,
        title: title,
        meetingDate: meetingDate,
        sourceFilePath: filePath,
        generate: generate,
      );
      if (!mounted) return;
      showDunesToast(
        context,
        generate
            ? '录音正在后台上传，完成后将自动开始转写'
            : '录音正在后台上传，完成后可在详情页生成纪要',
      );
      _live.clearPreview();
      _live.consumeRecordedFile();
      setState(() {
        _filePath = '';
        _pendingPersistAfterEnd = false;
        _pendingDraftTitle = '';
      });
      widget.onCreated(meetingId, isDraft: !generate);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(
        e,
        fallback: generate ? '提交失败，请稍后重试' : '草稿保存失败，请稍后重试',
      );
      setState(() => _error = generate ? '提交失败：$msg' : '草稿保存失败：$msg');
      showDunesToast(
        context,
        msg,
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _persistingAfterEnd = false;
          _persistGenerate = null;
        });
      }
    }
  }

  bool get _showBusyOverlay => false;

  String get _busyOverlayMessage => '';

  Widget _buildBusyOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.32),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _busyOverlayMessage,
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '请勿离开页面，上传完成后会自动跳转',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                      height: 1.4,
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
      final meetingId = await MeetingUploadCoordinator.instance.enqueue(
        session: widget.session,
        title: _titleCtrl.text.trim(),
        meetingDate: DateTime.now().toIso8601String().substring(0, 10),
        sourceFilePath: _filePath,
        generate: true,
      );
      if (!mounted) return;
      showDunesToast(context, '录音正在后台上传，完成后将自动开始转写');
      widget.onCreated(meetingId, isDraft: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '提交失败：${friendlyErrorText(e)}');
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
        !_persistingAfterEnd &&
        _titleCtrl.text.trim().isNotEmpty &&
        _filePath.isNotEmpty &&
        (_mode != _CreateMode.live || !_live.active.value);
    final canEndLive = recording && !_persistingAfterEnd;
    final canStartLive = !recording && _hasMeetingTitle;
    final liveRecording = _mode == _CreateMode.live && recording;
    final statusText = switch (state) {
      MeetingRecordingState.recordingForeground => '正在录音（前台）',
      MeetingRecordingState.recordingBackground => '正在录音（后台/锁屏）',
      MeetingRecordingState.stopping => '停止录音中...',
      MeetingRecordingState.idle => '待开始',
    };

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
        title: const Text('新建会议纪要'),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              readOnly: _showBusyOverlay,
              onChanged: (value) {
                final title = value.trim();
                if (_live.active.value) {
                  _live.meetingTitle.value = title;
                } else if (_pendingPersistAfterEnd) {
                  _pendingDraftTitle = title;
                }
                setState(() => _error = null);
              },
              style: DunesTypography.sans(fontSize: 14, color: DunesColors.text),
              decoration: InputDecoration(
                hintText: '请输入会议标题，例如：周例会-销售复盘',
                helperText: _mode == _CreateMode.live && !recording && !_hasMeetingTitle
                    ? '开始实时转写前必须填写会议标题'
                    : null,
                helperStyle: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.coral,
                ),
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
                            ? (livePaused ? '录音已暂停' : '录音进行中')
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
                        onPressed: canStartLive ? _startLive : null,
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
                            label: Text(livePaused ? '继续录音' : '暂停录音'),
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
                            onPressed: canEndLive ? _confirmEndLive : null,
                            icon: _persistingAfterEnd
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.stop_rounded),
                            label: Text(
                              _persistingAfterEnd ? '保存中...' : '结束并保存',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: DunesColors.coral,
                              disabledBackgroundColor:
                                  DunesColors.coral.withValues(alpha: 0.35),
                              foregroundColor: Colors.white,
                              disabledForegroundColor:
                                  Colors.white.withValues(alpha: 0.75),
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
                          ? '已暂停，点击“继续录音”后恢复录音与实时转写'
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
      bottomNavigationBar: _mode == _CreateMode.upload
          ? SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: canSubmit ? _submit : null,
            icon: (_submitting || _persistingAfterEnd)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              (_submitting || _persistingAfterEnd)
                  ? '处理中...'
                  : '开始转写并生成纪要',
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
      )
          : null,
          ),
          if (_showBusyOverlay) _buildBusyOverlay(),
        ],
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
