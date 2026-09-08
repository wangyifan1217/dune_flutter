import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
import '../robots/robot_markdown.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'native_workbench_kpi_detail.dart';
import 'workbench_kpi_service.dart';

const _accent = Color(0xFF3D7A8C);

class NativeWorkbenchKpiPage extends StatefulWidget {
  const NativeWorkbenchKpiPage({
    super.key,
    required this.session,
    this.onChromeChanged,
    this.service,
    this.saveExport,
    this.now,
    this.pickConversation,
    this.sendMarkdown,
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final WorkbenchKpiService? service;
  final Future<void> Function(Uint8List bytes, String name)? saveExport;
  final DateTime? now;
  final Future<int?> Function()? pickConversation;
  final Future<void> Function(int conversationId, String markdown)? sendMarkdown;

  @override
  State<NativeWorkbenchKpiPage> createState() => _NativeWorkbenchKpiPageState();
}

class _NativeWorkbenchKpiPageState extends State<NativeWorkbenchKpiPage> {
  late final WorkbenchKpiService _service;
  ConversationService? _conversations;
  final TextEditingController _keywordCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _keywordDebounce;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  WorkProfileKpiScore? _score;
  late DateTime _month;
  int _detailUserId = 0;
  String _detailName = '';
  WorkProfileKpiScore? _detailScore;
  bool _detailLoading = false;
  String? _detailError;

  DateTime get _clock => widget.now ?? DateTime.now();
  DateTime get _currentMonth => kpiMonthStart(_clock);
  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WorkbenchKpiService(session: widget.session);
    _month = DateTime(_currentMonth.year, _currentMonth.month - 1);
    _keywordCtrl.addListener(_onKeywordChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishChrome();
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _keywordCtrl.dispose();
    _scrollController.dispose();
    _conversations?.close();
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  void _publishChrome() {
    widget.onChromeChanged?.call(
      TaskShellChrome(
        trailing: null,
        onBack: _detailUserId > 0 ? _closeDetail : null,
      ),
    );
  }

  void _closeDetail() {
    setState(() {
      _detailUserId = 0;
      _detailName = '';
      _detailScore = null;
      _detailError = null;
      _detailLoading = false;
    });
    _publishChrome();
  }

  void _onKeywordChanged() {
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final score = await _service.fetchScore(month: formatKpiMonth(_month));
      if (!mounted) return;
      setState(() {
        _score = score;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e, fallback: '加载失败');
        _loading = false;
      });
    }
  }

  Future<bool> _confirm({
    required String title,
    String? content,
    String confirmLabel = '确认',
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: content == null || content.isEmpty ? null : Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('kpi-confirm-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: danger ? const Color(0xFFBC5C40) : _accent,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month.isBefore(_earliestMonth)
          ? _earliestMonth
          : (_month.isAfter(_currentMonth) ? _currentMonth : _month),
      firstDate: _earliestMonth,
      lastDate: _currentMonth,
      helpText: '选择月份',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() => _month = kpiMonthStart(picked));
    unawaited(_load());
    unawaited(_reloadDetail());
  }

  void _shiftMonth(int delta) {
    final next = kpiShiftMonth(_month, delta);
    if (next.isBefore(_earliestMonth) || next.isAfter(_currentMonth)) return;
    setState(() => _month = next);
    unawaited(_load());
    unawaited(_reloadDetail());
  }

  Future<void> _openDetail(int userId, String name) async {
    setState(() {
      _detailUserId = userId;
      _detailName = name;
      _detailLoading = true;
      _detailError = null;
      _detailScore = null;
    });
    _publishChrome();
    await _reloadDetail();
  }

  Future<void> _reloadDetail() async {
    if (_detailUserId <= 0) return;
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final score = await _service.fetchScore(
        month: formatKpiMonth(_month),
        userId: _detailUserId,
      );
      if (!mounted) return;
      setState(() {
        _detailScore = score;
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detailError = friendlyErrorText(e, fallback: '加载明细失败');
        _detailLoading = false;
      });
    }
  }

  Future<void> _saveDetail(
    List<WorkbenchKpiOverrideItem> items,
    String summary,
  ) async {
    final ok = await _confirm(
      title: '确认变更绩效？',
      content: summary,
      confirmLabel: '确认变更',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final score = await _service.saveOverrides(
        month: formatKpiMonth(_month),
        userId: _detailUserId,
        items: items,
      );
      if (!mounted) return;
      setState(() => _detailScore = score);
      showDunesToast(context, '已保存权重调整');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '保存失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rerun() async {
    final label = formatKpiMonthLabel(_month);
    final ok = await _confirm(
      title: '确认重跑绩效？',
      content: '将按当前灯塔数据规则即时计算 $label 的绩效，不会改写历史任务。',
      confirmLabel: '确认重跑',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final score = await _service.rerunScore(formatKpiMonth(_month));
      if (!mounted) return;
      setState(() => _score = score);
      showDunesToast(
        context,
        '$label 已计算：${score.people.length} 人',
      );
      unawaited(_reloadDetail());
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '重跑失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final label = formatKpiMonthLabel(_month);
    final ok = await _confirm(
      title: '确认导出绩效？',
      content: '将导出 $label 全部人员汇总与任务明细（Excel）。',
      confirmLabel: '确认导出',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final month = formatKpiMonth(_month);
      final bytes = await _service.exportScore(month);
      final name = '业务绩效-$month.xlsx';
      if (widget.saveExport != null) {
        await widget.saveExport!(bytes, name);
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Excel', extensions: <String>['xlsx']),
          ],
        );
        if (location == null) return;
        final file = XFile.fromData(
          bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: name,
        );
        await file.saveTo(location.path);
      }
      if (mounted) showDunesToast(context, '已导出 $label');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '导出失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forwardSummary() async {
    final score = _score;
    if (score == null || score.people.isEmpty) {
      showDunesToast(context, '暂无可转发内容');
      return;
    }
    final markdown = kpiScoreSummaryMarkdown(score);
    final conversationId = widget.pickConversation != null
        ? await widget.pickConversation!()
        : await showConversationPickerSheet(
            context: context,
            service: _conversations ??= ConversationService(
              session: widget.session,
            ),
            title: '转发到 IM',
          );
    if (conversationId == null || conversationId <= 0 || !mounted) return;
    try {
      if (widget.sendMarkdown != null) {
        await widget.sendMarkdown!(conversationId, markdown);
      } else {
        final conv = _conversations ??= ConversationService(
          session: widget.session,
        );
        await conv.sendText(
          conversationId,
          markdown,
          payload: <String, dynamic>{
            'robotMarkdown': true,
            'kpiScoreSummary': true,
            'month': score.month,
          },
        );
      }
      if (mounted) showDunesToast(context, '已转发到会话');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '转发失败'),
          kind: DunesToastKind.error,
        );
      }
    }
  }

  List<_PersonGroup> get _groups {
    final needle = _keywordCtrl.text.trim().toLowerCase();
    final people = kpiPeopleByScoreDesc(_score?.people ?? const <WorkProfileKpiPerson>[]);
    return [
      for (final person in people)
        if (needle.isEmpty || _personMatches(person, needle))
          _PersonGroup(person: person),
    ];
  }

  bool _personMatches(WorkProfileKpiPerson person, String needle) {
    if (person.userName.toLowerCase().contains(needle)) return true;
    for (final cat in person.categories) {
      for (final task in cat.tasks) {
        if (task.taskName.toLowerCase().contains(needle) ||
            task.province.toLowerCase().contains(needle) ||
            task.productName.toLowerCase().contains(needle) ||
            task.productGroup.toLowerCase().contains(needle) ||
            task.channelName.toLowerCase().contains(needle) ||
            task.supplyGroup.toLowerCase().contains(needle) ||
            kpiLighthouseSliceTitle(task).toLowerCase().contains(needle) ||
            kpiLighthouseSliceSubtitle(task).toLowerCase().contains(needle) ||
            task.matchSummary.toLowerCase().contains(needle)) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _buildDetailBody() {
    if (_detailLoading && _detailScore == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_detailError != null && _detailScore == null) {
      return _ErrorPane(
        message: _detailError!,
        onRetry: () => unawaited(_reloadDetail()),
      );
    }
    if (_detailScore == null) {
      return const Center(
        child: Text('该月暂无绩效明细', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return WorkbenchKpiDetailPane(
      personName: _detailName,
      monthLabel: formatKpiMonthLabel(_month),
      score: _detailScore!,
      canEdit: true,
      busy: _busy,
      onSave: _saveDetail,
    );
  }

  Widget _buildListBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorPane(message: _error!, onRetry: () => unawaited(_load()));
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (_groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('该月暂无灯塔数据规则切片', style: TextStyle(color: DunesColors.text3)),
            ),
          )
        else
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${group.person.userName}（${group.slices.length}条规则）',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text2,
                          ),
                        ),
                        Text(
                          group.person.mainScore.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: DunesColors.text,
                          ),
                        ),
                        Text(
                          group.person.resolvedGrade.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: Key('kpi-detail-${group.person.userId}'),
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _openDetail(group.person.userId, group.person.userName),
                          ),
                    child: const Text('查看明细'),
                  ),
                ],
              ),
            ),
            for (final task in group.slices)
              _SliceCard(
                task: task,
                onOpen: _busy
                    ? null
                    : () => unawaited(
                          _openDetail(group.person.userId, group.person.userName),
                        ),
              ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = !_month.isAtSameMomentAs(_earliestMonth);
    final canNext = _month.isBefore(_currentMonth);
    return Material(
      color: const Color(0xFFF7F8FA),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              children: [
                if (_detailUserId <= 0) ...[
                  TextField(
                    controller: _keywordCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索姓名 / 产品 / 省份 / 渠道 / 供给',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE8EAED)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE8EAED)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _pickMonth,
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(formatKpiMonthLabel(_month)),
                    ),
                    IconButton(
                      tooltip: '上一月',
                      visualDensity: VisualDensity.compact,
                      onPressed: !canPrev || _busy
                          ? null
                          : () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: '下一月',
                      visualDensity: VisualDensity.compact,
                      onPressed: !canNext || _busy
                          ? null
                          : () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (_detailUserId <= 0) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('kpi-rerun'),
                        onPressed: _busy ? null : () => unawaited(_rerun()),
                        style: FilledButton.styleFrom(backgroundColor: _accent),
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('重跑绩效'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('kpi-export'),
                        onPressed: _busy ? null : () => unawaited(_export()),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('导出'),
                      ),
                      if (_busy)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  if (_score != null && _score!.people.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _KpiSummaryPane(
                      markdown: kpiScoreSummaryMarkdown(_score!),
                      onForward: _busy ? null : () => unawaited(_forwardSummary()),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Expanded(
            child: _detailUserId > 0 ? _buildDetailBody() : _buildListBody(),
          ),
        ],
      ),
    );
  }
}

class _PersonGroup {
  _PersonGroup({required this.person});
  final WorkProfileKpiPerson person;
  List<WorkProfileKpiTask> get slices {
    final list = [
      for (final cat in person.categories) ...cat.tasks,
    ];
    list.sort((a, b) {
      final byScore = b.taskTotal.compareTo(a.taskTotal);
      if (byScore != 0) return byScore;
      return kpiLighthouseSliceTitle(a).compareTo(kpiLighthouseSliceTitle(b));
    });
    return list;
  }
}

class _SliceCard extends StatelessWidget {
  const _SliceCard({required this.task, this.onOpen});

  final WorkProfileKpiTask task;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final title = kpiLighthouseSliceTitle(task);
    final subtitle = kpiLighthouseSliceSubtitle(task);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('kpi-task-${task.taskId}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (task.bucketLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4F7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        task.bucketLabel.replaceAll('板块', ''),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                  ),
                Text(
                  task.taskTotal.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiSummaryPane extends StatelessWidget {
  const _KpiSummaryPane({required this.markdown, this.onForward});

  final String markdown;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('kpi-summary'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '汇总',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              TextButton.icon(
                key: const Key('kpi-summary-forward'),
                onPressed: onForward,
                icon: const Icon(Icons.ios_share_outlined, size: 16),
                label: const Text('转发到 IM'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: RobotMarkdown(
                markdown: markdown,
                compact: true,
                selectable: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: DunesColors.text2)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _KpiTaskEditorDialog extends StatefulWidget {
  const _KpiTaskEditorDialog({
    required this.initial,
    required this.searchPeople,
  });

  final WorkbenchKpiTask initial;
  final Future<List<WorkbenchKpiPersonRef>> Function(String q) searchPeople;

  @override
  State<_KpiTaskEditorDialog> createState() => _KpiTaskEditorDialogState();
}

class _KpiTaskEditorDialogState extends State<_KpiTaskEditorDialog> {
  late WorkbenchKpiTask _draft;
  final _nameCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _nameCtrl.text = _draft.name;
    _provinceCtrl.text = _draft.province;
    _contentCtrl.text = _draft.content;
    _tagCtrl.text = _draft.tagName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _provinceCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickUser() async {
    final person = await showDialog<WorkbenchKpiPersonRef>(
      context: context,
      builder: (ctx) => _KpiUserPickerDialog(
        searchPeople: widget.searchPeople,
        initialName: _draft.userName,
      ),
    );
    if (person == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        userId: person.userId,
        userName: person.displayName,
      );
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final raw = start ? _draft.startDate : _draft.endDate;
    final parsed = DateTime.tryParse(raw);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    final text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      _draft = start
          ? _draft.copyWith(startDate: text)
          : _draft.copyWith(endDate: text);
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (_draft.userId <= 0) {
      showDunesToast(context, '请选择负责人', kind: DunesToastKind.error);
      return;
    }
    if (name.isEmpty) {
      showDunesToast(context, '请填写任务名称', kind: DunesToastKind.error);
      return;
    }
    Navigator.pop(
      context,
      _draft.copyWith(
        name: name,
        province: _provinceCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        tagName: _tagCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creating = _draft.id <= 0;
    final maxW = (MediaQuery.sizeOf(context).width - 40).clamp(280.0, 420.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(creating ? '新增任务' : '编辑任务'),
      content: SizedBox(
        width: maxW,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('负责人'),
                subtitle: Text(
                  _draft.userName.isEmpty
                      ? (_draft.userId > 0 ? '${_draft.userId}' : '点击选择')
                      : _draft.userName,
                ),
                trailing: const Icon(Icons.person_search_outlined),
                onTap: _pickUser,
              ),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '任务名称',
                  hintText: '如：中石油、小套-加油会员',
                ),
              ),
              TextField(
                controller: _provinceCtrl,
                decoration: const InputDecoration(
                  labelText: '省份',
                  hintText: '空或全国=全国合计；可填广东,广西',
                ),
              ),
              TextField(
                controller: _contentCtrl,
                decoration: const InputDecoration(labelText: '内容'),
              ),
              TextField(
                controller: _tagCtrl,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '标签I / 标签II',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开始日期'),
                subtitle: Text(
                  _draft.startDate.isEmpty ? '不限' : _draft.startDate,
                ),
                onTap: () => unawaited(_pickDate(start: true)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('结束日期'),
                subtitle: Text(_draft.endDate.isEmpty ? '不限' : _draft.endDate),
                onTap: () => unawaited(_pickDate(start: false)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('计入绩效'),
                value: _draft.isCounted,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(isCounted: v);
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('kpi-editor-save'),
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: _accent),
          child: const Text('下一步'),
        ),
      ],
    );
  }
}

class _KpiUserPickerDialog extends StatefulWidget {
  const _KpiUserPickerDialog({
    required this.searchPeople,
    this.initialName = '',
  });

  final Future<List<WorkbenchKpiPersonRef>> Function(String q) searchPeople;
  final String initialName;

  @override
  State<_KpiUserPickerDialog> createState() => _KpiUserPickerDialogState();
}

class _KpiUserPickerDialogState extends State<_KpiUserPickerDialog> {
  late final TextEditingController _q;
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<WorkbenchKpiPersonRef> _items = const [];

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: widget.initialName);
    _q.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialName.trim().isNotEmpty) unawaited(_search());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.removeListener(_onChanged);
    _q.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_search());
    });
  }

  Future<void> _search() async {
    final needle = _q.text.trim();
    if (needle.isEmpty) {
      setState(() {
        _items = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.searchPeople(needle);
      if (!mounted) return;
      if (_q.text.trim() != needle) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: '搜索失败');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = (size.width - 40).clamp(280.0, 400.0);
    final maxH = (size.height * 0.72).clamp(320.0, 480.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('选择负责人'),
      content: SizedBox(
        width: maxW,
        height: maxH,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索姓名 / 手机号',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                  ? const Center(child: Text('输入关键词搜索'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) {
                        final p = _items[i];
                        return ListTile(
                          title: Text(p.displayName),
                          subtitle: Text(
                            [
                              p.dept,
                              p.title,
                            ].where((e) => e.isNotEmpty).join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
