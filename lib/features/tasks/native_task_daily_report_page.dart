import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_first_use_guide.dart';
import 'task_models.dart';

const _accent = Color(0xFF2F8F7E);

class NativeTaskDailyReportPage extends StatefulWidget {
  const NativeTaskDailyReportPage({
    super.key,
    required this.session,
    this.initialDate,
    required this.onBack,
  });

  final AuthSession session;
  final DateTime? initialDate;
  final VoidCallback onBack;

  @override
  State<NativeTaskDailyReportPage> createState() =>
      _NativeTaskDailyReportPageState();
}

class _DraftLine {
  _DraftLine(this.task)
    : progress = task.progressPct.toDouble(),
      work = TextEditingController(),
      next = TextEditingController();

  final TaskItem task;
  double progress;
  final TextEditingController work;
  final TextEditingController next;
}

class _NativeTaskDailyReportPageState extends State<NativeTaskDailyReportPage> {
  late final TaskApi _api = TaskApi(widget.session);
  late DateTime _date = widget.initialDate ?? DateTime.now();
  TaskDailyReportBundle? _bundle;
  List<_DraftLine> _lines = [];
  final _blockers = TextEditingController();
  final _otherWork = TextEditingController();
  final _nextPlan = TextEditingController();
  List<TaskDailyReport> _history = const [];
  bool _loading = true;
  bool _saving = false;
  bool _showHistory = false;
  bool _guideAutoStarted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showGuide());
    });
  }

  Future<void> _showGuide({bool force = false}) async {
    if (!force && _guideAutoStarted) return;
    if (!force) _guideAutoStarted = true;
    await showTaskFirstUseGuide(
      context,
      userId: widget.session.userId,
      page: TaskGuidePage.dailyReport,
      force: force,
    );
  }

  @override
  void dispose() {
    _blockers.dispose();
    _otherWork.dispose();
    _nextPlan.dispose();
    for (final line in _lines) {
      line.work.dispose();
      line.next.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bundle = await _api.getDailyReport(date: _date);
      if (!mounted) return;
      for (final line in _lines) {
        line.work.dispose();
        line.next.dispose();
      }
      final submitted = bundle.report;
      final lines = <_DraftLine>[];
      if (submitted != null && submitted.items.isNotEmpty) {
        for (final item in submitted.items) {
          final match = bundle.candidates.where((t) => t.id == item.taskId);
          final task = match.isNotEmpty
              ? match.first
              : TaskItem(
                  id: item.taskId,
                  title: item.taskTitle,
                  ownerUserId: 0,
                  creatorUserId: 0,
                  parentId: item.isItem ? item.mainTaskId : null,
                  progressPct: item.progressPct,
                );
          final line = _DraftLine(task);
          line.progress = item.progressPct.toDouble();
          line.work.text = item.workDone;
          line.next.text = item.nextAction;
          lines.add(line);
        }
      } else {
        for (final task in bundle.candidates) {
          lines.add(_DraftLine(task));
        }
      }
      _blockers.text = submitted?.blockers ?? '';
      _otherWork.text = submitted?.summary ?? '';
      _nextPlan.text = submitted?.nextPlan ?? '';
      setState(() {
        _bundle = bundle;
        _lines = lines;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final list = await _api.listDailyReportHistory();
      if (mounted) setState(() => _history = list);
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 14)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    await _reload();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final work = line.work.text.trim();
      if (work.isEmpty) continue;
      items.add({
        'taskId': line.task.id,
        'progressPct': line.progress.round().clamp(0, 100),
        'workDone': work,
        'nextAction': line.next.text.trim(),
      });
    }
    if (items.isEmpty &&
        _otherWork.text.trim().isEmpty &&
        _nextPlan.text.trim().isEmpty) {
      showDunesCenterToast(context, '请至少填写一条任务进展、其他工作或明日计划');
      return;
    }
    for (final line in _lines) {
      if (line.work.text.trim().isEmpty &&
          line.progress != line.task.progressPct) {
        showDunesCenterToast(context, '「${line.task.title}」改了进度，请填写今日完成');
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认提交日报'),
        content: Text(
          _bundle?.canBackfill == true
              ? '这是补填，提交时间会如实记录，不会改成按时提交。'
              : '确认提交 ${formatTaskYmd(_date)} 的日报？进度会同步到对应任务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _api.submitDailyReport({
        'reportDate': formatTaskYmd(_date),
        'summary': _otherWork.text.trim(),
        'blockers': _blockers.text.trim(),
        'nextPlan': _nextPlan.text.trim(),
        'items': items,
      });
      if (!mounted) return;
      showDunesCenterToast(context, '日报已提交');
      await _reload();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.bgApp,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onBack,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_back_ios_new,
                          size: 14,
                          color: DunesColors.text2,
                        ),
                        SizedBox(width: 2),
                        Text(
                          '返回',
                          style: TextStyle(
                            fontSize: 13,
                            color: DunesColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '使用指引',
                  onPressed: () => unawaited(_showGuide(force: true)),
                  icon: const Icon(
                    Icons.help_outline,
                    color: DunesColors.text2,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _showHistory = !_showHistory);
                    if (_showHistory) unawaited(_loadHistory());
                  },
                  child: Text(_showHistory ? '返回填写' : '历史日报'),
                ),
              ],
            ),
          ),
          Expanded(child: _showHistory ? _buildHistory() : _buildForm()),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Text('还没有历史日报', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _history[i];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(r.reportDate),
          subtitle: Text(r.source == 'backfill' ? '补填' : '已提交'),
          onTap: () {
            final parsed = DateTime.tryParse(r.reportDate);
            if (parsed == null) return;
            setState(() {
              _date = parsed;
              _showHistory = false;
            });
            unawaited(_reload());
          },
        );
      },
    );
  }

  Widget _buildForm() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _reload, child: Text('重试：$_error')),
      );
    }
    final bundle = _bundle;
    final submitted = bundle?.report?.submitted == true;
    final readOnly = submitted || bundle?.canSubmit != true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        InkWell(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event, color: _accent),
                const SizedBox(width: 8),
                Text(
                  formatTaskYmd(_date),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (submitted)
                  const Text('已提交', style: TextStyle(color: Color(0xFF1F9D76)))
                else if (bundle?.canBackfill == true)
                  Text(
                    '可补填至 ${bundle?.backfillUntil}',
                    style: const TextStyle(color: Color(0xFFB45309)),
                  )
                else if (bundle?.canSubmit == true)
                  const Text('待填', style: TextStyle(color: Color(0xFFB45309))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (bundle != null && !bundle.isWorkday) ...[
          _box(
            '非工作日',
            Text(
              bundle.nonWorkReason.isEmpty
                  ? '当前日期无需提交日报。'
                  : bundle.nonWorkReason,
              style: const TextStyle(color: DunesColors.text2, height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '当天没有进行中的主目标或子目标，可填写其他工作。',
              style: TextStyle(color: DunesColors.text3),
            ),
          ),
        for (final line in _lines) ...[
          _lineCard(line, readOnly: readOnly),
          const SizedBox(height: 10),
        ],
        if (!submitted && bundle?.canSubmit != true)
          _box(
            '填报状态',
            const Text(
              '当前日期不在可提交窗口内，请切换日期或查看历史日报。',
              style: TextStyle(color: DunesColors.text2, height: 1.4),
            ),
          ),
        if (!submitted && bundle?.canSubmit != true) const SizedBox(height: 10),
        _box(
          '阻塞',
          TextField(
            controller: _blockers,
            readOnly: readOnly,
            maxLines: 3,
            decoration: _inputDecoration('卡住的事（选填）'),
          ),
        ),
        const SizedBox(height: 10),
        _box(
          '其他工作',
          TextField(
            controller: _otherWork,
            readOnly: readOnly,
            maxLines: 3,
            decoration: _inputDecoration('未挂在主目标或子目标下的工作（选填）'),
          ),
        ),
        const SizedBox(height: 10),
        _box(
          '明日计划',
          TextField(
            controller: _nextPlan,
            readOnly: readOnly,
            maxLines: 3,
            decoration: _inputDecoration('明天准备继续推进什么（选填）'),
          ),
        ),
        if (!submitted && bundle?.canSubmit == true) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(_saving ? '提交中…' : '提交日报'),
          ),
        ],
      ],
    );
  }

  Widget _lineCard(_DraftLine line, {required bool readOnly}) {
    final accent = _lineAccent(line.task);
    final period = taskCreateRangeLabel(line.task.startAt, line.task.dueAt);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.task.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (line.task.parentTitle.trim().isNotEmpty)
                      Text(
                        '所属主目标：${line.task.parentTitle}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    if (period != null)
                      Text(
                        '任务周期：$period',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  line.task.isMain ? '主目标' : '子目标',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '当前进度',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${line.progress.round()}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: line.progress.clamp(0, 100),
            max: 100,
            divisions: 20,
            label: '${line.progress.round()}%',
            activeColor: accent,
            onChanged: readOnly
                ? null
                : (v) => setState(() => line.progress = v),
          ),
          const Text(
            '今日完成 *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: line.work,
            readOnly: readOnly,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration('写清楚今天完成了什么', accent: accent),
          ),
          const SizedBox(height: 10),
          const Text(
            '下一步',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: line.next,
            readOnly: readOnly,
            minLines: 1,
            maxLines: 3,
            decoration: _inputDecoration('下一步准备做什么（选填）', accent: accent),
          ),
        ],
      ),
    );
  }

  Widget _box(String label, Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Color _lineAccent(TaskItem task) {
    const colors = <Color>[
      Color(0xFF5B6FC4),
      Color(0xFF2F8F7E),
      Color(0xFFB7791F),
      Color(0xFF9C5FB5),
      Color(0xFF3D7A8C),
    ];
    return colors[task.id.abs() % colors.length];
  }

  InputDecoration _inputDecoration(String hint, {Color accent = _accent}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF6F7F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
    );
  }
}
