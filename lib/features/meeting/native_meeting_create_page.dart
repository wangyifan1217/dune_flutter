import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'meeting_audio_file_picker.dart';
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
  bool _picking = false;
  bool _endingLive = false;
  bool _persistingAfterEnd = false;
  bool? _persistGenerate;
  bool _pendingPersistAfterEnd = false;
  String _pendingDraftTitle = '';
  bool _handlingBack = false;
  bool _fileDragging = false;
  String? _error;
  _CreateMode _mode = isDesktopCommOnly ? _CreateMode.upload : _CreateMode.live;
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
    _live.elapsed.addListener(_onLiveChanged);
    _live.interruptionHint.addListener(_onLiveInterruptionHint);
    _recordingCtrl.state.addListener(_onLiveChanged);
  }

  void _onLiveInterruptionHint() {
    final hint = _live.interruptionHint.value?.trim() ?? '';
    if (hint.isEmpty || !mounted) return;
    showDunesToast(context, hint);
  }

  void _onLiveChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.navigation.backInterceptor = null;
    _pulseController.dispose();
    _live.active.removeListener(_onLiveChanged);
    _live.paused.removeListener(_onLiveChanged);
    _live.elapsed.removeListener(_onLiveChanged);
    _live.interruptionHint.removeListener(_onLiveInterruptionHint);
    _recordingCtrl.state.removeListener(_onLiveChanged);
    _titleCtrl.dispose();
    super.dispose();
  }

  bool get _supportsDesktopDrop => isDesktopCommOnly;

  bool _dropListening = true;

  @override
  void activate() {
    super.activate();
    _dropListening = true;
  }

  @override
  void deactivate() {
    _dropListening = false;
    super.deactivate();
  }

  bool _canAcceptAudioDrop({required bool lookupTicker}) {
    if (!_dropListening || !mounted) return false;
    if (!_supportsDesktopDrop) return false;
    if (_mode != _CreateMode.upload) return false;
    if (_picking || _submitting || _showBusyOverlay) return false;
    if (!lookupTicker) return true;
    return TickerMode.valuesOf(context).enabled;
  }

  Future<void> _pickFile() async {
    if (_picking || _submitting) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final path = await MeetingAudioFilePicker.pick();
      if (!mounted || path == null || path.trim().isEmpty) return;
      setState(() {
        _filePath = path.trim();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(e);
      setState(() => _error = msg);
      showDunesToast(context, msg, kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (!_canAcceptAudioDrop(lookupTicker: false)) return;
    setState(() {
      _fileDragging = false;
      _picking = true;
      _error = null;
    });
    final accessed = <Uint8List>[];
    try {
      XFile? audio;
      var extraAudio = 0;
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        final name = item.name.trim().isNotEmpty ? item.name : item.path;
        if (item.path.trim().isEmpty) continue;
        if (!MeetingAudioFilePicker.isSupportedAudioName(name)) continue;
        if (audio != null) {
          extraAudio++;
          continue;
        }
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        audio = XFile(item.path, name: name);
      }
      if (audio == null) {
        const msg = '请拖入 wav / mp3 / m4a 录音文件';
        if (!mounted) return;
        setState(() => _error = msg);
        showDunesToast(context, msg, kind: DunesToastKind.error);
        return;
      }
      final path = await MeetingAudioFilePicker.persistPickedAudio(audio);
      if (!mounted) return;
      setState(() {
        _filePath = path.trim();
        _error = null;
      });
      if (extraAudio > 0) {
        showDunesToast(context, '已选用第一个录音文件');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(e, fallback: '无法读取拖入的录音');
      setState(() => _error = msg);
      showDunesToast(context, msg, kind: DunesToastKind.error);
    } finally {
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } catch (_) {}
      }
      if (mounted) setState(() => _picking = false);
    }
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
      return '现场录音服务暂不可用，请先使用“上传录音转写”';
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
    if (isDesktopCommOnly) {
      const msg = '桌面端请使用「上传录音转写」';
      setState(() {
        _mode = _CreateMode.upload;
        _error = msg;
      });
      showDunesToast(context, msg, kind: DunesToastKind.error);
      return;
    }
    if (!_hasMeetingTitle) {
      const msg = '请先填写会议标题后再开始录音';
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
    if (!_live.active.value || _endingLive || _persistingAfterEnd) return;
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
    setState(() {
      _endingLive = true;
      _error = null;
    });
    // 先画出「保存中」遮罩，再进入可能耗时的原生 stop/合并。
    await _waitForBusyOverlayFrame();
    try {
      final path = await _live.end();
      if (!mounted) return;
      final resolvedTitle = _resolvedPersistTitle();
      setState(() {
        _endingLive = false;
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
        setState(() => _error = '录音文件为空或未成功落盘，请重新录制后再保存');
        return;
      }
      await _promptPersistAfterEnd(filePath: path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _endingLive = false;
        _error = _mapRecordError(e);
      });
    } finally {
      if (mounted && _endingLive) {
        setState(() => _endingLive = false);
      }
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
          _endingLive
              ? '正在保存录音文件，现在离开可能中断保存。'
              : _persistingAfterEnd
                  ? '正在创建会议记录，请稍候...'
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
      if (_endingLive || _submitting || _persistingAfterEnd) {
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
    await _waitForBusyOverlayFrame();
    try {
      final meetingDate = DateTime.now().toIso8601String().substring(0, 10);
      final meetingId = await MeetingUploadCoordinator.instance.enqueue(
        session: widget.session,
        title: title,
        meetingDate: meetingDate,
        sourceFilePath: filePath,
        generate: generate,
        recordingDurationSeconds: _live.elapsed.value.inSeconds,
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

  Future<void> _waitForBusyOverlayFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
  }

  bool get _showBusyOverlay =>
      _endingLive || _persistingAfterEnd || _submitting || _picking;

  String get _busyOverlayMessage {
    if (_picking) return '正在导入录音文件…';
    if (_endingLive) return '正在保存录音…';
    if (_persistingAfterEnd) {
      return _persistGenerate == true ? '正在创建会议记录…' : '正在保存草稿…';
    }
    if (_submitting) return '正在创建会议记录…';
    return '处理中…';
  }

  String get _busyOverlayHint {
    if (_picking) return '文件较大时请稍候，不要退出页面';
    if (_endingLive) {
      return '录音越长，保存可能需要更久，请稍候';
    }
    return '完成后会自动进入会议详情';
  }

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
                    _busyOverlayHint,
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
    try {
      await _live.resume();
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(e, fallback: '继续录音失败，请稍后再试');
      setState(() => _error = msg);
      showDunesToast(context, msg, kind: DunesToastKind.error);
    }
  }

  Future<void> _submit() async {
    if (_filePath.isEmpty || _titleCtrl.text.trim().isEmpty) {
      setState(() => _error = '请先填写会议标题并选择录音文件');
      return;
    }
    setState(() => _submitting = true);
    await _waitForBusyOverlayFrame();
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
    if (_filePath.isEmpty) {
      return _supportsDesktopDrop ? '点击选择或拖拽录音到此处' : '未选择录音文件';
    }
    final normalized = _filePath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx < 0) return normalized;
    return normalized.substring(idx + 1);
  }

  String _formatLiveElapsed(Duration duration) {
    final total = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = _recordingCtrl.state.value;
    final liveWorking = _live.active.value;
    final livePaused = _live.paused.value;
    final liveElapsed = _live.elapsed.value;
    final recording = liveWorking;
    final canSubmit = !_submitting &&
        !_endingLive &&
        !_persistingAfterEnd &&
        _titleCtrl.text.trim().isNotEmpty &&
        _filePath.isNotEmpty &&
        (_mode != _CreateMode.live || !_live.active.value);
    final canEndLive = recording && !_endingLive && !_persistingAfterEnd;
    final canStartLive =
        !recording && _hasMeetingTitle && !_endingLive && !_persistingAfterEnd;
    final liveRecording = _mode == _CreateMode.live && recording;
    final statusText = switch (state) {
      MeetingRecordingState.recordingForeground => '正在录音（前台）',
      MeetingRecordingState.recordingBackground => '正在录音（后台/锁屏）',
      MeetingRecordingState.stopping => '停止录音中...',
      MeetingRecordingState.idle => '待开始',
    };

    final page = GestureDetector(
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
                colors: [Color(0xFF7B5CD8), Color(0xFF6A4FA0)],
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
                  child: Icon(
                    isDesktopCommOnly
                        ? Icons.upload_file_rounded
                        : Icons.mic_none_rounded,
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
                            ? (isDesktopCommOnly
                                ? '上传音频，生成摘要与待办'
                                : '上传或录制音频，生成摘要与待办')
                            : '现场录音，结束后一键生成纪要',
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

          if (!isDesktopCommOnly) ...[
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
              thumbColor: DunesColors.brandPurple,
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
                    '现场录音',
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
          ],

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
                    ? '开始录音前必须填写会议标题'
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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (_picking || _submitting) ? null : _pickFile,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: _fileDragging
                                ? DunesColors.brandPurpleSoft
                                : DunesColors.bgSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _fileDragging
                                  ? DunesColors.brandPurple
                                  : DunesColors.borderSoft,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fileDragging ? '松开以添加录音' : _fileLabel(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: _fileDragging
                                      ? DunesColors.brandPurpleDeep
                                      : (_filePath.isEmpty
                                          ? DunesColors.text3
                                          : DunesColors.text),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _supportsDesktopDrop
                                    ? '支持 wav/mp3/m4a · 可拖拽文件到本页'
                                    : '支持 wav/mp3/m4a',
                                style: DunesTypography.sans(
                                  fontSize: 11,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                    color: DunesColors.brandPurpleSoft,
                    onPressed: (_picking || _submitting) ? null : _pickFile,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.upload_rounded,
                          size: 18,
                          color: DunesColors.brandPurpleDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '上传',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.brandPurpleDeep,
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
              title: '录音控制',
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
                      if (liveWorking || liveElapsed > Duration.zero) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatLiveElapsed(liveElapsed),
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.brandPurpleDeep,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!recording)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: canStartLive ? _startLive : null,
                        icon: const Icon(Icons.mic_rounded),
                        label: const Text('开始录音'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DunesColors.brandPurpleDeep,
                          side: const BorderSide(color: DunesColors.brandPurpleLine),
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
                            onPressed: (_endingLive || _persistingAfterEnd)
                                ? null
                                : (livePaused ? _resumeLive : _pauseLive),
                            icon: Icon(
                              livePaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                            label: Text(livePaused ? '继续录音' : '暂停录音'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DunesColors.brandPurpleDeep,
                              side: const BorderSide(color: DunesColors.brandPurpleLine),
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
                            icon: (_endingLive || _persistingAfterEnd)
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
                              (_endingLive || _persistingAfterEnd)
                                  ? '保存中...'
                                  : '结束并保存',
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
              title: '录音状态',
              icon: Icons.graphic_eq_rounded,
              child: _buildRecordingStatusContent(
                recording: liveRecording,
                paused: livePaused,
                elapsed: liveElapsed,
                recorderState: state,
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
              backgroundColor: DunesColors.brandPurple,
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
    if (!_supportsDesktopDrop) return page;
    final dropEnabled = _canAcceptAudioDrop(lookupTicker: true);
    return DropTarget(
      enable: dropEnabled,
      onDragEntered: (_) {
        if (!mounted || !_canAcceptAudioDrop(lookupTicker: false)) return;
        if (!_fileDragging) setState(() => _fileDragging = true);
      },
      onDragExited: (_) {
        if (!mounted) return;
        if (_fileDragging) setState(() => _fileDragging = false);
      },
      onDragDone: (detail) {
        if (!mounted || !_canAcceptAudioDrop(lookupTicker: false)) return;
        if (_fileDragging) setState(() => _fileDragging = false);
        unawaited(_onDesktopDrop(detail));
      },
      child: page,
    );
  }

  Widget _buildRecordingStatusContent({
    required bool recording,
    required bool paused,
    required Duration elapsed,
    required MeetingRecordingState recorderState,
  }) {
    final elapsedText = _formatLiveElapsed(elapsed);
    if (!recording) {
      return Text(
        '点击「开始录音」后，这里会显示录音时长与状态。结束后再上传转写并生成纪要。',
        style: DunesTypography.sans(
          fontSize: 13,
          color: DunesColors.text3,
          height: 1.5,
        ),
      );
    }

    final systemPaused = paused && _live.pausedByInterruption;
    final title = systemPaused
        ? '来电已暂停'
        : paused
            ? '录音已暂停'
            : '正在录音中';
    final hint = _live.interruptionHint.value?.trim() ?? '';
    final subtitle = systemPaused
        ? (hint.isNotEmpty
            ? hint
            : '挂断后将自动继续，已录部分已保存。也可点「继续录音」。')
        : paused
        ? '点击「继续录音」后恢复采集，结束后再转写生成纪要'
        : switch (recorderState) {
            MeetingRecordingState.recordingBackground =>
              '已进入后台/锁屏，录音仍在继续',
            MeetingRecordingState.stopping => '正在停止并保存录音…',
            _ => '麦克风采集中，结束后可选择生成纪要或存为草稿',
          };

    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = !paused ? 0.92 + _pulseController.value * 0.16 : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (paused ? DunesColors.text3 : DunesColors.coral)
                      .withValues(alpha: 0.12),
                  border: Border.all(
                    color: paused ? DunesColors.text3 : DunesColors.coral,
                    width: 2,
                  ),
                ),
                child: Icon(
                  paused ? Icons.pause_rounded : Icons.mic_rounded,
                  color: paused ? DunesColors.text2 : DunesColors.coral,
                  size: 32,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: DunesTypography.sans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: paused ? DunesColors.text2 : DunesColors.coral,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          elapsedText,
          style: DunesTypography.sans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: DunesColors.brandPurpleDeep,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: DunesTypography.sans(
            fontSize: 12.5,
            color: DunesColors.text3,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
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
              Icon(icon, size: 18, color: DunesColors.brandPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (trailing != null) trailing,
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
