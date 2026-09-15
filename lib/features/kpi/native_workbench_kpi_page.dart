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
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'kpi_score_summary_card.dart';
import 'native_workbench_kpi_detail.dart';
import 'workbench_kpi_service.dart';

const _accent = DunesColors.brandPurple;
const _pageBg = Color(0xFFF7F4FC);
const _line = Color(0xFFECE7F3);
const _tabular = <FontFeature>[FontFeature.tabularFigures()];

class NativeWorkbenchKpiPage extends StatefulWidget {
  const NativeWorkbenchKpiPage({
    super.key,
    required this.session,
    this.onChromeChanged,
    this.service,
    this.saveExport,
    this.pickImportFile,
    this.now,
    this.pickConversation,
    this.sendMarkdown,
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final WorkbenchKpiService? service;
  final Future<void> Function(Uint8List bytes, String name)? saveExport;
  final Future<({Uint8List bytes, String name})?> Function()? pickImportFile;
  final DateTime? now;
  final Future<int?> Function()? pickConversation;
  final Future<void> Function(int conversationId, String markdown)?
  sendMarkdown;

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
  String _sector = 'all';
  String _group = '';
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

  Future<void> _saveRubricDetail(
    List<WorkbenchKpiRubricItem> items,
    String summary,
  ) async {
    final ok = await _confirm(
      title: '确认录入量表分？',
      content: '$summary\n只写入工作台，不会通知员工。发布结果后才会发到绩效助手。',
      confirmLabel: '确认录入',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final score = await _service.saveRubricScore(
        month: formatKpiMonth(_month),
        userId: _detailUserId,
        items: items,
      );
      if (!mounted) return;
      setState(() => _detailScore = score);
      unawaited(_load());
      showDunesToast(context, '已保存量表分');
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

  Future<void> _ackRubricDetail() async {
    final ok = await _confirm(
      title: '确认本月绩效？',
      content: '确认后表示已知悉并接受本月量表结果。改分后需重新确认。',
      confirmLabel: '确认',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final score = await _service.ackRubricScore(
        month: formatKpiMonth(_month),
      );
      if (!mounted) return;
      setState(() => _detailScore = score);
      unawaited(_load());
      showDunesToast(context, '已确认本月绩效');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '确认失败'),
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
      showDunesToast(context, '$label 已计算：${score.people.length} 人');
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
      final name = '月度绩效考评-$month.xlsx';
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

  Future<void> _importRubric() async {
    final label = formatKpiMonthLabel(_month);
    ({Uint8List bytes, String name})? picked;
    if (widget.pickImportFile != null) {
      picked = await widget.pickImportFile!();
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel', extensions: <String>['xlsx']),
        ],
      );
      if (file == null) return;
      picked = (bytes: await file.readAsBytes(), name: file.name);
    }
    if (picked == null || !mounted) return;
    final ok = await _confirm(
      title: '确认导入量表？',
      content: '将读取个人量表，并把整体绩效评价表写成团队系数（不改个人分）。仍跳过汇总表和统计表。写入 $label，不会自动通知员工。',
      confirmLabel: '确认导入',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.importRubricScore(
        month: formatKpiMonth(_month),
        bytes: picked.bytes,
        fileName: picked.name,
      );
      if (!mounted) return;
      unawaited(_load());
      showDunesToast(
        context,
        result.imported > 0
            ? (result.teamHint.isEmpty
                  ? '$label 已导入 ${result.imported} 人'
                  : '$label 已导入 ${result.imported} 人，${result.teamHint}')
            : (result.people.isEmpty ? '没有导入任何人' : result.people.first),
      );
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '导入失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forwardSummary() async {
    final score = _score;
    final people = _filteredPeople;
    if (score == null || people.isEmpty) {
      showDunesToast(context, '暂无可转发内容');
      return;
    }
    final markdown = kpiScoreSummaryMarkdown(score, people: people);
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
            // 结构化名单：聊天里据此渲染汇总卡；正文 Markdown 留作预览 / 复制 / 旧客户端兜底。
            'kpiSummary': kpiScoreSummaryData(score, people: people).toJson(),
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

  Future<void> _publishRubric() async {
    final people = [
      for (final person in _filteredPeople)
        if (person.isRubric && person.canWrite) person,
    ];
    final scored = [
      for (final person in people)
        if (!person.isPending) person,
    ];
    if (scored.isEmpty) {
      showDunesToast(context, '当前没有可发布的量表结果');
      return;
    }
    final pending = people.length - scored.length;
    final unpublished = scored.where((p) => p.needsPublish).length;
    final bits = <String>[
      '将把当前筛选里已评完的量表结果发到当事人的绩效助手，共 ${scored.length} 人。',
      if (unpublished > 0) '其中 $unpublished 人尚未通知或分数有更新。',
      if (pending > 0) '还有 $pending 人未评完，这次不会通知他们。',
      '分数没有变化的人不会重复通知。',
    ];
    final ok = await _confirm(
      title: '发布到绩效助手？',
      content: bits.join(),
      confirmLabel: '确认发布',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.publishRubricScore(
        month: formatKpiMonth(_month),
        userIds: [for (final person in scored) person.userId],
      );
      if (!mounted) return;
      unawaited(_load());
      final parts = <String>[
        if (result.notified > 0) '新发布 ${result.notified} 人',
        if (result.updated > 0) '更新 ${result.updated} 人',
        if (result.unchanged > 0) '无变化 ${result.unchanged} 人',
        if (result.pending > 0) '未评完 ${result.pending} 人未通知',
      ];
      showDunesToast(
        context,
        result.sent > 0
            ? (parts.isEmpty ? '已发布到绩效助手' : parts.join('，'))
            : (result.pending > 0 ? '还有人未评完，没有发出通知' : '没有需要通知的人'),
      );
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '发布失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _sectorOrder = ['telecom', 'energy', 'rd', 'office'];
  static const _sectorLabels = {
    'telecom': '通信',
    'energy': '能源',
    'rd': '研发',
    'office': '职能',
  };

  List<WorkProfileKpiPerson> get _sectorPeople {
    final needle = _keywordCtrl.text.trim().toLowerCase();
    return [
      for (final person in kpiPeopleByScoreDesc(
        _score?.people ?? const <WorkProfileKpiPerson>[],
      ))
        if ((needle.isEmpty || _personMatches(person, needle)) &&
            _personInSector(person))
          person,
    ];
  }

  String get _effectiveGroup {
    if (_sector == 'all' || _group.isEmpty) return '';
    if (!_groupOptions.contains(_group)) return '';
    return _group;
  }

  List<String> get _groupOptions {
    if (_sector == 'all') return const [];
    return kpiProjectGroupFilterOptions(_sectorPeople, sector: _sector);
  }

  List<WorkProfileKpiPerson> get _filteredPeople {
    final people = _sectorPeople;
    final group = _effectiveGroup;
    if (group.isEmpty) return people;
    return [
      for (final person in people)
        if (kpiPersonProjectGroup(person, _sector) == group) person,
    ];
  }

  String _primarySectorOf(WorkProfileKpiPerson person) =>
      kpiPrimarySectorOf(person);

  List<_KpiGroup> get _groups {
    final people = _filteredPeople;
    if (people.isEmpty) return const [];
    if (_sector == 'rd' ||
        _sector == 'telecom' ||
        _sector == 'energy' ||
        _sector == 'office') {
      return [
        for (final entry in kpiPeopleByProjectGroup(people, sector: _sector))
          _KpiGroup(id: entry.key, title: entry.key, people: entry.value),
      ];
    }
    final buckets = <String, List<WorkProfileKpiPerson>>{
      for (final id in _sectorOrder) id: <WorkProfileKpiPerson>[],
      'none': <WorkProfileKpiPerson>[],
    };
    for (final person in people) {
      buckets.putIfAbsent(_primarySectorOf(person), () => []).add(person);
    }
    return [
      for (final id in _sectorOrder)
        if (buckets[id]!.isNotEmpty)
          _KpiGroup(
            id: id,
            title: _sectorLabels[id]!,
            people: kpiPeopleLeadersFirst(buckets[id]!, sector: id),
          ),
      if (buckets['none']!.isNotEmpty)
        _KpiGroup(
          id: 'none',
          title: '未分板块',
          people: kpiPeopleByScoreDesc(buckets['none']!),
        ),
    ];
  }

  bool _personInSector(WorkProfileKpiPerson person) {
    if (_sector == 'all') return true;
    return person.categories.any(
      (c) => c.category == _sector && c.tasks.isNotEmpty,
    );
  }

  String _deptNameOf(WorkProfileKpiPerson person) =>
      person.departmentName.trim();

  String _statsLine(List<WorkProfileKpiPerson> people) {
    final group = _effectiveGroup;
    final scope = _sector == 'all'
        ? '全部板块'
        : [
            _sectorLabels[_sector] ?? _sector,
            if (group.isNotEmpty) group,
          ].join(' · ');
    final scored = [
      for (final p in people)
        if (!p.isPending) p,
    ];
    final pending = people.length - scored.length;
    final unpublished = scored.where((p) => p.isUnpublished).length;
    final toAck = scored
        .where((p) => p.isRubric && !p.needsPublish && !p.isAcked)
        .length;
    final avg = scored.isEmpty
        ? null
        : scored.fold<double>(0, (s, p) => s + p.mainScore) / scored.length;
    return [
      '$scope · 共 ${people.length} 人',
      if (avg != null) '均分 ${avg.toStringAsFixed(1)}',
      if (pending > 0) '待录入 $pending',
      if (unpublished > 0) '未发布 $unpublished',
      if (toAck > 0) '待确认 $toAck',
    ].join(' · ');
  }

  void _jumpRosterTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _setSector(String value) {
    if (_sector == value) return;
    setState(() {
      _sector = value;
      _group = '';
    });
    _jumpRosterTop();
  }

  void _setGroup(String value) {
    if (_effectiveGroup == value) return;
    setState(() => _group = value);
    _jumpRosterTop();
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
    final person = _detailScore!.people.isEmpty
        ? null
        : _detailScore!.people.first;
    return WorkbenchKpiDetailPane(
      personName: _detailName,
      monthLabel: formatKpiMonthLabel(_month),
      score: _detailScore!,
      canEdit: person == null || !person.isRubric || person.canWrite,
      busy: _busy,
      onSave: _saveDetail,
      onSaveRubric: _saveRubricDetail,
      onAck: person != null && person.canAck ? _ackRubricDetail : null,
    );
  }

  Widget _buildListBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
      );
    }
    if (_error != null) {
      return _ErrorPane(message: _error!, onRetry: () => unawaited(_load()));
    }
    final people = _filteredPeople;
    return _KpiRosterPane(
      people: people,
      groups: _groups,
      showSections: true,
      emptyLabel: (_score?.people.isEmpty ?? true) ? '该月暂无绩效人员' : '当前筛选下暂无人员',
      deptNameOf: _deptNameOf,
      scrollController: _scrollController,
      busy: _busy,
      onOpen: (person) {
        final index = people.indexWhere((e) => e.userId == person.userId);
        unawaited(
          _openDetail(
            person.userId,
            kpiIndexedPersonName(index < 0 ? 0 : index, person.userName),
          ),
        );
      },
    );
  }

  Widget _buildMonthStepper() {
    final canPrev = !_month.isAtSameMomentAs(_earliestMonth);
    final canNext = _month.isBefore(_currentMonth);
    return _KpiMonthStepper(
      label: formatKpiMonthLabel(_month),
      onPick: _busy ? null : () => unawaited(_pickMonth()),
      onPrev: canPrev && !_busy ? () => _shiftMonth(-1) : null,
      onNext: canNext && !_busy ? () => _shiftMonth(1) : null,
    );
  }

  /// 操作按流程排：先处理数据（导入 / 重跑），再对外输出（导出 / 转发），
  /// 最后「发布结果」—— 唯一会通知到员工的动作，做成主按钮。
  List<_KpiAction> _actions(List<WorkProfileKpiPerson> people) {
    final idle = !_busy && !_loading;
    return [
      _KpiAction(
        key: const Key('kpi-import'),
        icon: Icons.upload_file_outlined,
        label: '导入量表',
        onTap: idle ? () => unawaited(_importRubric()) : null,
      ),
      _KpiAction(
        key: const Key('kpi-rerun'),
        icon: Icons.refresh_rounded,
        label: '重跑计算',
        onTap: idle ? () => unawaited(_rerun()) : null,
      ),
      _KpiAction(
        key: const Key('kpi-export'),
        icon: Icons.file_download_outlined,
        label: '导出 Excel',
        onTap: idle ? () => unawaited(_export()) : null,
      ),
      _KpiAction(
        key: const Key('kpi-summary-forward'),
        icon: Icons.send_outlined,
        label: '转发到 IM',
        onTap: _busy || people.isEmpty
            ? null
            : () => unawaited(_forwardSummary()),
      ),
      _KpiAction(
        key: const Key('kpi-publish'),
        icon: Icons.campaign_outlined,
        label: '发布结果',
        primary: true,
        onTap: idle ? () => unawaited(_publishRubric()) : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final gutter = narrow ? 12.0 : 20.0;
    if (_detailUserId > 0) {
      return Material(
        color: _pageBg,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 6),
              child: Row(
                children: [
                  _buildMonthStepper(),
                  if (_busy) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: _buildDetailBody()),
          ],
        ),
      );
    }
    final people = _loading || _error != null
        ? const <WorkProfileKpiPerson>[]
        : _filteredPeople;
    return Material(
      color: _pageBg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KpiSearchField(
              controller: _keywordCtrl,
              hint: narrow ? '搜索姓名 / 产品' : '搜索姓名 / 产品 / 省份 / 渠道 / 供给',
            ),
            const SizedBox(height: 10),
            _KpiControlPanel(
              compact: narrow,
              month: _buildMonthStepper(),
              stats: _loading ? '加载中…' : _statsLine(people),
              busy: _busy,
              actions: _actions(people),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _KpiSectorTabs(
                key: const Key('kpi-sector-filter'),
                value: _sector,
                expand: narrow,
                onChanged: _busy ? null : _setSector,
                options: const [
                  MapEntry('all', '全部'),
                  MapEntry('telecom', '通信'),
                  MapEntry('energy', '能源'),
                  MapEntry('rd', '研发'),
                  MapEntry('office', '职能'),
                ],
              ),
            ),
            if (_groupOptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _KpiGroupFilter(
                  value: _effectiveGroup,
                  options: _groupOptions,
                  onChanged: _busy ? null : _setGroup,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(child: _buildListBody()),
          ],
        ),
      ),
    );
  }
}

class _KpiGroup {
  const _KpiGroup({
    required this.id,
    required this.title,
    required this.people,
  });

  final String id;
  final String title;
  final List<WorkProfileKpiPerson> people;
}

class _KpiAction {
  const _KpiAction({
    required this.key,
    required this.icon,
    required this.label,
    this.primary = false,
    this.onTap,
  });

  final Key key;
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;
}

Color _kpiGradeColor(String code) {
  switch (code) {
    case '优':
      return DunesColors.green;
    case '良':
      return DunesColors.brandPurple;
    case '中':
      return DunesColors.blue;
    case '普':
      return DunesColors.amber;
    case '改':
    case '辅':
      return DunesColors.coral;
  }
  return DunesColors.text2;
}

class _KpiSearchField extends StatelessWidget {
  const _KpiSearchField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _line),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13.5, color: DunesColors.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13.5, color: DunesColors.text3),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: DunesColors.text3,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 36,
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : InkWell(
                  onTap: controller.clear,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: DunesColors.brandPurpleLine),
          ),
        ),
      ),
    );
  }
}

class _KpiMonthStepper extends StatelessWidget {
  const _KpiMonthStepper({
    required this.label,
    this.onPick,
    this.onPrev,
    this.onNext,
  });

  final String label;
  final VoidCallback? onPick;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(Icons.chevron_left_rounded, '上一月', onPrev),
          InkWell(
            key: const Key('kpi-month-pick'),
            onTap: onPick,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: DunesColors.brandPurpleDeep,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, '下一月', onNext),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, String tip, VoidCallback? onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 32,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? DunesColors.border : DunesColors.text2,
          ),
        ),
      ),
    );
  }
}

/// 顶部控制卡：月份 + 统计 + 操作（导入 / 重跑 / 导出 / 转发 / 发布）。
///
/// 手机上五个操作排成一行「快捷入口」：圆形图标 + 下方短标签，不再是
/// 3 + 2 两排大紫块（上下宽度不齐、整片紫色很重、禁用态灰块很突兀）。
/// 只有「发布结果」用实心紫圆，其余是浅紫圆 —— 主次一眼分开。
class _KpiControlPanel extends StatelessWidget {
  const _KpiControlPanel({
    required this.compact,
    required this.month,
    required this.stats,
    required this.busy,
    required this.actions,
  });

  final bool compact;
  final Widget month;
  final String stats;
  final bool busy;
  final List<_KpiAction> actions;

  @override
  Widget build(BuildContext context) {
    final statsText = Text(
      stats,
      key: const Key('kpi-scope-hint'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 12,
        color: DunesColors.text3,
        fontFeatures: _tabular,
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D2B1A4F),
            blurRadius: 12,
            spreadRadius: -2,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 2,
            child: busy
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    color: _accent,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 12, compact ? 4 : 12),
            child: Row(
              children: [
                month,
                const SizedBox(width: 10),
                Expanded(child: statsText),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: _line,
          ),
          if (compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final action in actions)
                    Expanded(child: _KpiActionTile(action: action)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in actions)
                    _KpiActionButton(action: action),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KpiActionTile extends StatelessWidget {
  const _KpiActionTile({required this.action});

  final _KpiAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final primary = action.primary;
    final Color iconColor;
    final BoxDecoration circle;
    if (!enabled) {
      iconColor = DunesColors.text3;
      circle = const BoxDecoration(
        color: Color(0xFFF3F1F6),
        shape: BoxShape.circle,
      );
    } else if (primary) {
      iconColor = Colors.white;
      circle = const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DunesColors.brandPurple, DunesColors.brandPurpleDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x407B5CD8),
            blurRadius: 8,
            spreadRadius: -2,
            offset: Offset(0, 3),
          ),
        ],
      );
    } else {
      iconColor = DunesColors.brandPurpleDeep;
      circle = const BoxDecoration(
        color: DunesColors.brandPurpleSoft,
        shape: BoxShape.circle,
      );
    }
    final labelColor = !enabled
        ? DunesColors.text3
        : (primary ? DunesColors.brandPurpleDeep : DunesColors.text2);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: action.key,
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 38,
                decoration: circle,
                child: Icon(action.icon, size: 18, color: iconColor),
              ),
              const SizedBox(height: 6),
              Text(
                action.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiActionButton extends StatelessWidget {
  const _KpiActionButton({required this.action});

  final _KpiAction action;

  @override
  Widget build(BuildContext context) {
    final primary = action.primary;
    return TextButton.icon(
      key: action.key,
      onPressed: action.onTap,
      style: TextButton.styleFrom(
        foregroundColor: primary ? Colors.white : DunesColors.brandPurpleDeep,
        backgroundColor: primary ? DunesColors.brandPurple : Colors.white,
        disabledForegroundColor: DunesColors.text3,
        disabledBackgroundColor: const Color(0xFFF3F1F6),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        side: primary ? null : const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      icon: Icon(action.icon, size: 16),
      label: Text(action.label),
    );
  }
}

class _KpiSectorTabs extends StatelessWidget {
  const _KpiSectorTabs({
    super.key,
    required this.value,
    required this.options,
    required this.expand,
    this.onChanged,
  });

  final String value;
  final List<MapEntry<String, String>> options;
  final bool expand;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFECE7F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final option in options)
            expand ? Expanded(child: _segment(option)) : _segment(option),
        ],
      ),
    );
  }

  Widget _segment(MapEntry<String, String> option) {
    final selected = value == option.key;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x1A2B1A4F),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('kpi-sector-${option.key}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onChanged == null ? null : () => onChanged!(option.key),
          child: Align(
            widthFactor: expand ? null : 1,
            heightFactor: 1,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expand ? 8 : 18,
                vertical: 6,
              ),
              child: Text(
                option.value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? DunesColors.text : DunesColors.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiGroupFilter extends StatelessWidget {
  const _KpiGroupFilter({
    required this.value,
    required this.options,
    this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('kpi-group-filter'),
      spacing: 6,
      runSpacing: 6,
      children: [
        _pill(id: '', label: '全部'),
        for (final option in options) _pill(id: option, label: option),
      ],
    );
  }

  Widget _pill({required String id, required String label}) {
    final selected = value == id;
    return Material(
      color: selected ? DunesColors.brandPurple : const Color(0xFFECE7F4),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key(id.isEmpty ? 'kpi-group-all' : 'kpi-group-$id'),
        borderRadius: BorderRadius.circular(8),
        onTap: onChanged == null ? null : () => onChanged!(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiRosterPane extends StatelessWidget {
  const _KpiRosterPane({
    required this.people,
    required this.groups,
    required this.showSections,
    required this.emptyLabel,
    required this.deptNameOf,
    required this.busy,
    required this.onOpen,
    this.scrollController,
  });

  final List<WorkProfileKpiPerson> people;
  final List<_KpiGroup> groups;
  final bool showSections;
  final String emptyLabel;
  final String Function(WorkProfileKpiPerson person) deptNameOf;
  final bool busy;
  final ValueChanged<WorkProfileKpiPerson> onOpen;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final entries = <Widget>[];
        for (final group in groups) {
          if (showSections) {
            entries.add(
              _KpiSectionHeader(
                key: Key('kpi-section-${group.id}'),
                title: group.title,
                count: group.people.length,
              ),
            );
          }
          for (var i = 0; i < group.people.length; i++) {
            final person = group.people[i];
            final last = i == group.people.length - 1;
            entries.add(
              compact
                  ? _KpiPersonTile(
                      person: person,
                      rank: i + 1,
                      deptName: deptNameOf(person),
                      last: last,
                      busy: busy,
                      onOpen: () => onOpen(person),
                    )
                  : _KpiTableRow(
                      person: person,
                      rank: i + 1,
                      deptName: deptNameOf(person),
                      last: last,
                      busy: busy,
                      onOpen: () => onOpen(person),
                    ),
            );
          }
        }
        return Container(
          key: const Key('kpi-summary'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          clipBehavior: Clip.antiAlias,
          child: people.isEmpty
              ? Center(
                  child: Text(
                    emptyLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DunesColors.text3,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact) const _KpiTableHeader(),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: entries,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _KpiSectionHeader extends StatelessWidget {
  const _KpiSectionHeader({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF8FD),
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count 人',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class _KpiBadge extends StatelessWidget {
  const _KpiBadge({required this.label, required this.color, this.fill});

  final String label;
  final Color color;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill ?? color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: color,
          fontFeatures: _tabular,
        ),
      ),
    );
  }
}

Widget _kpiAckText(WorkProfileKpiPerson person) {
  final unpublished = person.isUnpublished;
  return Text(
    unpublished ? '未发布' : (person.isAcked ? '已确认' : '待确认'),
    key: Key('kpi-ack-status-${person.userId}'),
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      color: unpublished
          ? DunesColors.text3
          : (person.isAcked ? DunesColors.text3 : DunesColors.amber),
    ),
  );
}

class _KpiRank extends StatelessWidget {
  const _KpiRank({required this.rank, required this.highlight});

  final int rank;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$rank',
      style: TextStyle(
        fontSize: 12,
        fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
        color: highlight ? _accent : DunesColors.text3,
        fontFeatures: _tabular,
      ),
    );
  }
}

class _KpiPersonTile extends StatelessWidget {
  const _KpiPersonTile({
    required this.person,
    required this.rank,
    required this.deptName,
    required this.last,
    required this.busy,
    required this.onOpen,
  });

  final WorkProfileKpiPerson person;
  final int rank;
  final String deptName;
  final bool last;
  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final grade = person.resolvedGrade;
    final post = person.position.trim();
    final subtitle = [
      if (deptName.isNotEmpty) deptName,
      if (post.isNotEmpty) post,
    ].join(' · ');
    return Material(
      color: Colors.white,
      child: InkWell(
        key: Key('kpi-person-${person.userId}'),
        onTap: busy ? null : onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: _KpiRank(
                  rank: rank,
                  highlight: rank <= 3 && !person.isPending,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      person.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (person.isPending)
                const _KpiBadge(
                  label: '待录入',
                  color: DunesColors.amber,
                  fill: DunesColors.amberSoft,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      person.mainScore.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                        fontFeatures: _tabular,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (person.isRubric) ...[
                          _kpiAckText(person),
                          const SizedBox(width: 6),
                        ],
                        _KpiBadge(
                          label:
                              '${grade.code} ×${formatKpiCoefficient(grade.coefficient)}',
                          color: _kpiGradeColor(grade.code),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _kColRank = 44.0;

class _KpiTableHeader extends StatelessWidget {
  const _KpiTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 18, 9),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF8FD),
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: const Row(
        children: [
          SizedBox(width: _kColRank, child: _KpiColLabel('排名')),
          Expanded(flex: 14, child: _KpiColLabel('部门')),
          Expanded(flex: 12, child: _KpiColLabel('姓名')),
          Expanded(flex: 18, child: _KpiColLabel('岗位')),
          Expanded(flex: 9, child: _KpiColLabel('得分', align: TextAlign.right)),
          SizedBox(width: 24),
          Expanded(flex: 15, child: _KpiColLabel('等级')),
          Expanded(flex: 6, child: _KpiColLabel('系数', align: TextAlign.right)),
          SizedBox(width: 24),
          Expanded(flex: 8, child: _KpiColLabel('状态')),
        ],
      ),
    );
  }
}

class _KpiColLabel extends StatelessWidget {
  const _KpiColLabel(this.text, {this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: DunesColors.text3,
      ),
    );
  }
}

class _KpiTableRow extends StatelessWidget {
  const _KpiTableRow({
    required this.person,
    required this.rank,
    required this.deptName,
    required this.last,
    required this.busy,
    required this.onOpen,
  });

  final WorkProfileKpiPerson person;
  final int rank;
  final String deptName;
  final bool last;
  final bool busy;
  final VoidCallback onOpen;

  static const _cell = TextStyle(fontSize: 13, color: DunesColors.text2);

  @override
  Widget build(BuildContext context) {
    final grade = person.resolvedGrade;
    final post = person.position.trim();
    return Material(
      color: Colors.white,
      child: InkWell(
        key: Key('kpi-person-${person.userId}'),
        onTap: busy ? null : onOpen,
        hoverColor: DunesColors.brandPurpleSoft.withValues(alpha: 0.6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 18, 11),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _kColRank,
                child: _KpiRank(
                  rank: rank,
                  highlight: rank <= 3 && !person.isPending,
                ),
              ),
              Expanded(
                flex: 14,
                child: Text(
                  deptName.isEmpty ? '—' : deptName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cell,
                ),
              ),
              Expanded(
                flex: 12,
                child: Text(
                  person.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              Expanded(
                flex: 18,
                child: Text(
                  post.isEmpty ? '—' : post,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cell,
                ),
              ),
              Expanded(
                flex: 9,
                child: Text(
                  person.isPending ? '—' : person.mainScore.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 15,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: person.isPending
                      ? const _KpiBadge(
                          label: '待录入',
                          color: DunesColors.amber,
                          fill: DunesColors.amberSoft,
                        )
                      : _KpiBadge(
                          label: grade.label,
                          color: _kpiGradeColor(grade.code),
                        ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  person.isPending
                      ? '—'
                      : formatKpiCoefficient(grade.coefficient),
                  textAlign: TextAlign.right,
                  style: _cell.copyWith(fontFeatures: _tabular),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 8,
                child: person.isRubric && !person.isPending
                    ? _kpiAckText(person)
                    : const Text('—', style: _cell),
              ),
            ],
          ),
        ),
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
