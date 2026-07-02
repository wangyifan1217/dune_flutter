import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import 'meeting_minutes_export.dart';
import 'native_meeting_models.dart';
import 'native_meeting_service.dart';

class NativeMeetingDetailPage extends StatefulWidget {
  const NativeMeetingDetailPage({
    super.key,
    required this.session,
    required this.meetingId,
    required this.onBack,
  });

  final AuthSession session;
  final int meetingId;
  final VoidCallback onBack;

  @override
  State<NativeMeetingDetailPage> createState() =>
      _NativeMeetingDetailPageState();
}

class _NativeMeetingDetailPageState extends State<NativeMeetingDetailPage> {
  late final NativeMeetingService _service = NativeMeetingService(
    session: widget.session,
  );
  final AudioPlayer _player = AudioPlayer();
  NativeMeetingDetail? _detail;
  Timer? _poller;
  bool _loading = true;
  bool _regenerating = false;
  bool _startingTranscription = false;
  bool _downloadingAudio = false;
  double _downloadProgress = 0;
  String? _downloadLabel;
  bool _transcriptExpanded = false;
  int _segmentVisibleCount = 30;
  static const int _segmentPageSize = 30;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.meetingId <= 0) {
      _loading = false;
      _error = '无效的会议 ID';
      return;
    }
    _load();
    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
  }

  @override
  void didUpdateWidget(NativeMeetingDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meetingId == widget.meetingId) return;
    if (widget.meetingId <= 0) {
      setState(() {
        _detail = null;
        _loading = false;
        _error = '无效的会议 ID';
      });
      return;
    }
    setState(() {
      _detail = null;
      _loading = true;
      _error = null;
      _transcriptExpanded = false;
      _segmentVisibleCount = _segmentPageSize;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await _service.fetchDetail(widget.meetingId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _transcriptExpanded = false;
        _segmentVisibleCount = math.min(
          _segmentPageSize,
          detail.transcriptSegments.length,
        );
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _error = friendlyErrorText(e));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _downloadAudio() async {
    final detail = _detail;
    if (detail == null || _downloadingAudio) return;

    setState(() {
      _downloadingAudio = true;
      _downloadProgress = 0;
      _downloadLabel = '下载录音';
    });

    try {
      final url = await _service.resolveAudioDownloadUrl(detail);
      if (url.isEmpty) {
        throw Exception('暂无可下载的录音文件');
      }
      final fileName = _service.audioDownloadFileName(detail);
      final savedPath = await file_dl.openUrlAsFile(
        url,
        fileName,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _downloadProgress = p.clamp(0.0, 1.0));
        },
      );
      if (!mounted) return;
      await _showSaveSuccessDialog(
        fileName: fileName,
        savedPath: savedPath,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '下载失败，请稍后重试'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingAudio = false;
          _downloadProgress = 0;
          _downloadLabel = null;
        });
      }
    }
  }

  Future<void> _exportSummary(MeetingExportFormat format) async {
    final detail = _detail;
    if (detail == null || _downloadingAudio) return;
    if (!MeetingMinutesExport.canExport(detail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('纪要尚未生成，暂无法导出')),
      );
      return;
    }

    setState(() {
      _downloadingAudio = true;
      _downloadProgress = 0;
      _downloadLabel = '导出${format.label}';
    });

    try {
      final content = format == MeetingExportFormat.markdown
          ? MeetingMinutesExport.buildMarkdown(detail)
          : MeetingMinutesExport.buildPlainText(detail);
      final fileName = MeetingMinutesExport.fileName(detail, format);
      final savedPath = await file_dl.saveBytesAsFile(
        Uint8List.fromList(utf8.encode(content)),
        fileName,
      );
      if (!mounted) return;
      setState(() => _downloadProgress = 1);
      await _showSaveSuccessDialog(
        fileName: fileName,
        savedPath: savedPath,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '导出失败，请稍后重试'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingAudio = false;
          _downloadProgress = 0;
          _downloadLabel = null;
        });
      }
    }
  }

  String _formatSavedLocation(String? savedPath) {
    if (savedPath == null || savedPath.isEmpty) {
      return defaultTargetPlatform == TargetPlatform.iOS
          ? '可在「文件」App → 本应用 中查看'
          : '下载文件夹';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return '已保存至应用文档目录\n可在「文件」App → 本应用 中查看\n\n$savedPath';
    }
    return savedPath.replaceFirst('/storage/emulated/0', '内部存储');
  }

  Future<void> _showSaveSuccessDialog({
    required String fileName,
    String? savedPath,
  }) async {
    if (!mounted) return;
    if (savedPath == null || savedPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $fileName')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存完成'),
        content: Text(
          '文件：$fileName\n保存位置：\n${_formatSavedLocation(savedPath)}',
          style: DunesTypography.sans(fontSize: 13.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget? _buildSummaryExportMenu(NativeMeetingDetail d) {
    if (!MeetingMinutesExport.canExport(d)) return null;
    return PopupMenuButton<MeetingExportFormat>(
      tooltip: '导出纪要',
      enabled: !_downloadingAudio,
      icon: const Icon(Icons.download_outlined, size: 20),
      onSelected: _exportSummary,
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: MeetingExportFormat.markdown,
          child: Text('下载 Markdown (.md)'),
        ),
        PopupMenuItem(
          value: MeetingExportFormat.plainText,
          child: Text('下载文本 (.txt)'),
        ),
      ],
    );
  }

  Future<void> _playAudio() async {
    final detail = _detail;
    if (detail == null) return;
    var url = detail.audioPlayUrl.trim();
    if (url.isEmpty) {
      url = await _service.resolveAudioDownloadUrl(detail);
    }
    if (url.isEmpty) return;

    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.duration == null ||
          _player.processingState == ProcessingState.completed) {
        await _player.setUrl(url);
      }
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _regenerate() async {
    final detail = _detail;
    if (detail == null) return;
    try {
      setState(() => _regenerating = true);
      await _service.regenerate(widget.meetingId);
      await _load();
      if (!mounted) return;
      final refreshed = _detail;
      final restarted = refreshed != null &&
          refreshed.transcriptSegments.isEmpty &&
          refreshed.status.toUpperCase() == 'TRANSCRIBING';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restarted ? '已开始重新转写，请稍候查看进度' : '已重新生成纪要',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorText(e, fallback: '重新生成失败，请稍后重试'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _startTranscriptionFromDraft() async {
    final detail = _detail;
    if (detail == null) return;
    try {
      setState(() => _startingTranscription = true);
      await _service.startTranscriptionForDraft(detail);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始转写并生成会议纪要')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorText(e, fallback: '开始转写失败，请稍后重试'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _startingTranscription = false);
    }
  }

  bool _isDraftWithAudio(NativeMeetingDetail detail) {
    return detail.status.toUpperCase() == 'DRAFT' &&
        detail.audioObjectKey.trim().isNotEmpty;
  }

  bool _canRegenerate(NativeMeetingDetail detail) {
    final status = detail.status.toUpperCase();
    if (status == 'DRAFT' ||
        status == 'TRANSCRIBING' ||
        status == 'GENERATING') {
      return false;
    }
    return detail.transcriptSegments.isNotEmpty ||
        detail.audioObjectKey.trim().isNotEmpty;
  }

  String _regenerateLabel(NativeMeetingDetail detail) {
    if (detail.transcriptSegments.isEmpty &&
        detail.audioObjectKey.trim().isNotEmpty) {
      return '重新转写并生成纪要';
    }
    return '重新生成纪要';
  }

  Future<void> _delete() async {
    final title = _detail?.title.isNotEmpty == true ? _detail!.title : '未命名会议';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会议纪要'),
        content: Text('确定删除「$title」吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DunesColors.coral),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteMeeting(widget.meetingId);
      if (!mounted) return;
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '删除失败，请稍后重试'))),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$minutes:$seconds';
  }

  String _summaryText(NativeMeetingDetail d) {
    if (d.summary.isNotEmpty) return d.summary;
    return switch (d.status.toUpperCase()) {
      'DRAFT' => d.audioObjectKey.trim().isNotEmpty
          ? '录音已保存为草稿，尚未开始转写。请点击下方「开始转写并生成纪要」，系统将自动生成会议摘要与待办事项。'
          : '草稿尚未关联录音文件，请返回补充录音后再开始转写。',
      'TRANSCRIBING' || 'GENERATING' => '正在智能生成会议摘要，请稍候...',
      'FAILED' => '纪要生成失败，可尝试重新转写或重新生成。',
      _ => '暂无会议摘要',
    };
  }

  String _transcriptEmptyText(NativeMeetingDetail d) {
    return switch (d.status.toUpperCase()) {
      'DRAFT' => '尚未开始转写。开始转写后，原始逐句内容将显示在这里。',
      'TRANSCRIBING' || 'GENERATING' => '当前会议暂无逐句转写内容（可能仍在处理中）',
      _ => '当前会议暂无逐句转写内容',
    };
  }

  String _statusLabel(String status) {
    return switch (status.toUpperCase()) {
      'GENERATED' => '已生成',
      'TRANSCRIBING' => '转写中',
      'GENERATING' => '生成中',
      'FAILED' => '失败',
      'DRAFT' => '草稿',
      _ => status.isEmpty ? '处理中' : status,
    };
  }

  String _formatMillis(int ms) {
    final d = Duration(milliseconds: ms.clamp(0, 24 * 60 * 60 * 1000));
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _loadMoreSegments() {
    final total = _detail?.transcriptSegments.length ?? 0;
    if (_segmentVisibleCount >= total) return;
    setState(() {
      _segmentVisibleCount = math.min(total, _segmentVisibleCount + _segmentPageSize);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('会议纪要'),
        actions: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(d),
          if (_downloadingAudio) _buildDownloadOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody(NativeMeetingDetail? d) {
    return _loading && d == null
        ? const Center(child: CircularProgressIndicator())
        : _error != null && d == null
        ? _buildErrorState()
        : d == null
        ? _buildEmptyState()
        : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _buildHero(d),
                const SizedBox(height: 16),
                if (d.audioPlayUrl.isNotEmpty || d.audioObjectKey.isNotEmpty) ...[
                  _buildAudioCard(),
                  const SizedBox(height: 16),
                ],
                _buildSection(
                  title: '会议摘要',
                  icon: Icons.auto_awesome_outlined,
                  trailing: _buildSummaryExportMenu(d),
                  child: Text(
                    _summaryText(d),
                    style: DunesTypography.sans(
                      fontSize: 14,
                      color: d.status.toUpperCase() == 'DRAFT' &&
                              d.summary.isEmpty
                          ? DunesColors.accentDeep
                          : DunesColors.text2,
                      height: 1.7,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title: '原始逐句转写',
                  icon: Icons.article_outlined,
                  trailing: d.transcriptSegments.isNotEmpty
                      ? TextButton.icon(
                          onPressed: () {
                            setState(() => _transcriptExpanded = !_transcriptExpanded);
                          },
                          icon: Icon(
                            _transcriptExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                          label: Text(_transcriptExpanded ? '收起' : '展开'),
                        )
                      : null,
                  child: d.transcriptSegments.isEmpty
                      ? Text(
                          _transcriptEmptyText(d),
                          style: DunesTypography.sans(
                            fontSize: 13,
                            color: DunesColors.text3,
                          ),
                        )
                      : _transcriptExpanded
                          ? Column(
                              children: d.transcriptSegments
                                  .take(_segmentVisibleCount)
                                  .map<Widget>(
                                    (seg) => Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: DunesColors.bgSoft,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${seg.speaker} · ${_formatMillis(seg.startMs)}',
                                            style: DunesTypography.sans(
                                              fontSize: 11,
                                              color: DunesColors.text3,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            seg.text,
                                            style: DunesTypography.sans(
                                              fontSize: 13,
                                              color: DunesColors.text2,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList()
                                ..addAll(
                                  _segmentVisibleCount < d.transcriptSegments.length
                                      ? <Widget>[
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: OutlinedButton.icon(
                                              onPressed: _loadMoreSegments,
                                              icon: const Icon(Icons.expand_more_rounded),
                                              label: Text(
                                                '加载更多（$_segmentVisibleCount/${d.transcriptSegments.length}）',
                                              ),
                                            ),
                                          ),
                                        ]
                                      : const <Widget>[],
                                ),
                            )
                          : Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: DunesColors.bgSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '共 ${d.transcriptSegments.length} 条逐句转写，点击右上角展开查看',
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                ),
                const SizedBox(height: 20),
                if (_isDraftWithAudio(d)) ...[
                  FilledButton.icon(
                    onPressed: _startingTranscription
                        ? null
                        : _startTranscriptionFromDraft,
                    icon: _startingTranscription
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      _startingTranscription ? '启动中...' : '开始转写并生成纪要',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: DunesColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_canRegenerate(d)) ...[
                  OutlinedButton.icon(
                    onPressed: _regenerating ? null : _regenerate,
                    icon: _regenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      _regenerating ? '处理中...' : _regenerateLabel(d),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DunesColors.accentDeep,
                      side: const BorderSide(color: DunesColors.accentLine),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            );
  }

  Widget _buildDownloadOverlay() {
    final label = _downloadLabel ?? '下载中';
    final hasProgress = _downloadProgress > 0;
    final pct = (_downloadProgress * 100).round();
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: Container(
            width: 240,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xE61F2421),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasProgress ? '$label  $pct%' : '$label…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hasProgress ? _downloadProgress : null,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      DunesColors.accentLine,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_note_outlined, size: 48, color: DunesColors.text3),
            const SizedBox(height: 12),
            Text(
              '暂无会议详情',
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请返回列表重新进入，或下拉刷新重试',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: DunesColors.coral),
            const SizedBox(height: 12),
            Text(
              '加载会议详情失败',
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(NativeMeetingDetail? d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: DunesColors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: DunesColors.accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d?.title.isNotEmpty == true ? d!.title : '未命名会议',
                      style: DunesTypography.sans(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      d?.displayTime ?? '未设置时间',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: DunesColors.amberSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(d?.status ?? ''),
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.amber,
                  ),
                ),
              ),
            ],
          ),
          if ((d?.asrProgress ?? 0) > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (d!.asrProgress.clamp(0, 100)) / 100,
                minHeight: 6,
                backgroundColor: DunesColors.bgSoft,
                color: DunesColors.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '转写进度 ${d.asrProgress}%',
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              return Material(
                color: DunesColors.accent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _playAudio,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '会议录音',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                StreamBuilder<Duration?>(
                  stream: _player.durationStream,
                  builder: (context, snapshot) {
                    final detail = _detail;
                    final fallbackTotal = Duration(
                      seconds: (detail?.audioDurationSeconds ?? 0).clamp(0, 24 * 60 * 60),
                    );
                    final total = (snapshot.data ?? _player.duration ?? fallbackTotal);
                    final totalMs = total.inMilliseconds;
                    return StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, posSnap) {
                        final position = posSnap.data ?? Duration.zero;
                        final posMs = position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatDuration(position)} / ${_formatDuration(total)}',
                              style: DunesTypography.sans(
                                fontSize: 12,
                                color: DunesColors.text3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                              ),
                              child: Slider(
                                value: posMs.toDouble(),
                                min: 0,
                                max: totalMs > 0 ? totalMs.toDouble() : 1,
                                onChanged: totalMs > 0
                                    ? (v) => _player.seek(Duration(milliseconds: v.round()))
                                    : null,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _downloadingAudio ? null : _downloadAudio,
            icon: const Icon(Icons.download_rounded),
            color: DunesColors.accent,
            tooltip: '下载录音',
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: DunesColors.accent),
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
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
