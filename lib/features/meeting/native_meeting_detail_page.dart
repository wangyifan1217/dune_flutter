import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
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
        _segmentVisibleCount = math.min(
          _segmentPageSize,
          detail.transcriptSegments.length,
        );
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _playAudio() async {
    final url = _detail?.audioPlayUrl ?? '';
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
    try {
      setState(() => _regenerating = true);
      await _service.regenerate(widget.meetingId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重新生成纪要')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新生成失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除会议纪要')),
      );
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$minutes:$seconds';
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
      body: _loading && d == null
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
                if (d.audioPlayUrl.isNotEmpty) ...[
                  _buildAudioCard(),
                  const SizedBox(height: 16),
                ],
                _buildSection(
                  title: '会议摘要',
                  icon: Icons.auto_awesome_outlined,
                  child: Text(
                    d.summary.isNotEmpty
                        ? d.summary
                        : '正在智能生成会议摘要，请稍候...',
                    style: DunesTypography.sans(
                      fontSize: 14,
                      color: DunesColors.text2,
                      height: 1.7,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title: '原始逐句转写',
                  icon: Icons.article_outlined,
                  child: d.transcriptSegments.isNotEmpty
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
                              .toList(growable: false)
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
                      : Text(
                          '当前会议暂无逐句转写内容（可能仍在处理中）',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            color: DunesColors.text3,
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _regenerating ? null : _regenerate,
                  icon: _regenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_regenerating ? '生成中...' : '重新生成纪要'),
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
                StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final total = _player.duration ?? Duration.zero;
                    final value = total.inMilliseconds > 0
                        ? (position.inMilliseconds / total.inMilliseconds)
                              .clamp(0.0, 1.0)
                        : 0.0;
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: total.inMilliseconds > 0 ? value : null,
                            minHeight: 5,
                            backgroundColor: DunesColors.bgSoft,
                            color: DunesColors.accent,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
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
