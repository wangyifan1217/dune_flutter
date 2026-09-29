import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import 'reconciliation_shucai_models.dart';
import 'reconciliation_shucai_service.dart';
import 'tag2_entity_models.dart';
import 'tag2_entity_table.dart';
import 'tag3_daily_models.dart';
import 'tag3_daily_preview.dart';
import 'tag3_daily_table.dart';

enum _ReconLevel { dates, table }

/// 工作台「每日对账」：日期列表 → 日清月结表。
class NativeDailyReconciliationPage extends StatefulWidget {
  const NativeDailyReconciliationPage({
    super.key,
    required this.session,
    this.initialAsOfDate = '',
    this.initialCardType = '',
    this.openToken = 0,
    this.onChromeChanged,
  });

  final AuthSession session;
  final String initialAsOfDate;
  final String initialCardType;
  final int openToken;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeDailyReconciliationPage> createState() =>
      _NativeDailyReconciliationPageState();
}

class _NativeDailyReconciliationPageState
    extends State<NativeDailyReconciliationPage> {
  late final ReconciliationShucaiService _api;
  _ReconLevel _level = _ReconLevel.dates;
  List<ReconDateItem> _dates = const [];
  String _selectedDate = '';
  String _asOfDate = '';
  String _cardKind = 'TAG3_DAILY';
  Tag3DailySnapshot? _tag3Daily;
  Tag2EntitySnapshot? _tag2;
  final Set<String> _tag2Busy = {};
  bool _tag3DailyPreview = false;
  final Set<String> _tag3ConfirmingKeys = {};
  bool _loading = true;
  String? _error;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _api = ReconciliationShucaiService(session: widget.session);
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant NativeDailyReconciliationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openToken != oldWidget.openToken && widget.openToken > 0) {
      final date = widget.initialAsOfDate.trim();
      if (date.isNotEmpty) {
        unawaited(_openCard(date, widget.initialCardType));
      } else {
        setState(() => _level = _ReconLevel.dates);
        _publishChrome();
        unawaited(_loadDates());
      }
    }
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadDates();
    final date = widget.initialAsOfDate.trim();
    if (date.isNotEmpty) {
      await _openCard(date, widget.initialCardType);
    } else {
      _publishChrome();
    }
  }

  void _publishChrome() {
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _level == _ReconLevel.dates ? null : _popLevel,
        lockPageSwipe: _level == _ReconLevel.table,
      ),
    );
  }

  void _popLevel() {
    _loadGen++;
    if (_level == _ReconLevel.table) {
      setState(() {
        _level = _ReconLevel.dates;
        _tag3Daily = null;
        _tag2 = null;
        _tag3DailyPreview = false;
        _tag3ConfirmingKeys.clear();
        _tag2Busy.clear();
      });
      _publishChrome();
    }
  }

  Future<void> _loadDates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.fetchDates();
      if (!mounted) return;
      final dates = padTag3DailyDateItems(items)
        ..sort((a, b) => b.asOfDate.compareTo(a.asOfDate));
      setState(() {
        _dates = dates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dates = const [];
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  List<ReconDateItem> get _visibleDates {
    final picked = _selectedDate.trim();
    if (picked.isEmpty) return _dates;
    for (final item in _dates) {
      if (item.asOfDate == picked) return [item];
    }
    return [ReconDateItem(asOfDate: picked)];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final current = DateTime.tryParse(
      _selectedDate.isEmpty ? tag3DailyYmd(yesterday) : _selectedDate,
    );
    var initial = current == null ? yesterday : tag3DailyCalendarDay(current);
    if (initial.isAfter(yesterday)) initial = yesterday;
    if (initial.isBefore(DateTime(2024, 1, 1))) initial = DateTime(2024, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: yesterday,
      helpText: '选择对账日',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;
    final day = tag3DailyCalendarDay(picked);
    if (!day.isBefore(today)) return;
    setState(() => _selectedDate = tag3DailyYmd(day));
  }

  Future<void> _openCard(String asOfDate, String cardType) async {
    final card = cardType.trim().toUpperCase() == 'TAG2_ENTITY'
        ? 'TAG2_ENTITY'
        : 'TAG3_DAILY';
    final gen = ++_loadGen;
    setState(() {
      _asOfDate = asOfDate;
      _cardKind = card;
      _level = _ReconLevel.table;
      _loading = true;
      _error = null;
      _tag3Daily = null;
      _tag2 = null;
      _tag3DailyPreview = false;
    });
    _publishChrome();
    if (card == 'TAG2_ENTITY') {
      try {
        final snap = await _api.fetchTag2Entity(asOfDate: asOfDate);
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _tag2 = snap;
          _loading = false;
        });
      } catch (e) {
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _error = friendlyErrorText(e);
          _loading = false;
        });
      }
      return;
    }
    try {
      final snap = await _api.fetchTag3Daily(asOfDate: asOfDate);
      if (!mounted || gen != _loadGen) return;
      final usePreview =
          kTag3DailyStaticPreview &&
          asOfDate.trim() == tag3DailyPreviewAsOfDate() &&
          snap.rows.isEmpty;
      setState(() {
        _tag3Daily = usePreview
            ? tag3DailyPreviewSnapshot(asOfDate: asOfDate)
            : snap;
        _tag3DailyPreview = usePreview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      if (kTag3DailyStaticPreview &&
          asOfDate.trim() == tag3DailyPreviewAsOfDate()) {
        setState(() {
          _tag3Daily = tag3DailyPreviewSnapshot(asOfDate: asOfDate);
          _tag3DailyPreview = true;
          _error = null;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _openTag2Drilldown(Tag2EntityRow row, Tag2EntityAmount amount) async {
    if (!amount.drill || row.isTotal) return;
    try {
      final data = await _api.fetchTag2EntityDrilldown(
        asOfDate: _asOfDate,
        rowKey: row.rowKey,
        kind: amount.key,
      );
      if (!mounted) return;
      await showTag2EntityDrilldown(
        context: context,
        title: '${row.title} · ${amount.label}',
        data: data,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submitTag2Action(Tag2EntityRow row, {required bool confirm}) async {
    if (confirm && !row.showConfirm) return;
    if (!confirm && !row.showComment) return;
    if (_tag2Busy.contains(row.rowKey)) return;
    final remark = await showTag2EntityActionDialog(
      context: context,
      row: row,
      confirm: confirm,
    );
    if (remark == null || !mounted) return;
    setState(() => _tag2Busy.add(row.rowKey));
    try {
      if (confirm) {
        await _api.confirmTag2Entity(
          asOfDate: _asOfDate,
          rowKey: row.rowKey,
          stage: row.canConfirmStage,
          expectedStatus: row.confirmationStatus,
          remark: remark,
          projectName: row.title,
        );
      } else {
        await _api.commentTag2Entity(
          asOfDate: _asOfDate,
          rowKey: row.rowKey,
          body: remark,
          projectName: row.title,
        );
      }
      final snap = await _api.fetchTag2Entity(asOfDate: _asOfDate);
      if (!mounted) return;
      setState(() => _tag2 = snap);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(confirm ? '已确认 ${row.title}' : '已记录 ${row.title} 的意见'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _tag2Busy.remove(row.rowKey));
    }
  }

  Future<void> _openTag3DailyDrilldown({
    required Tag3DailyRow row,
    required String metricKey,
  }) async {
    try {
      final data = await _api.fetchTag3DailyDrilldown(
        asOfDate: _asOfDate,
        rowKey: row.rowKey,
        metricKey: metricKey,
        period: metricKey == 'receivableAmount' ? row.period : null,
        statDate: metricKey == 'receivableAmount' && row.period == 'DAY'
            ? row.statDateDay
            : null,
        sourceTab: row.sourceTab,
      );
      if (!mounted) return;
      final title = metricKey == 'provinceSplit'
          ? '${row.projectName} · 分省'
          : '${row.projectName} · 应收 · ${row.periodLabel}';
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.72,
          child: Tag3DailyDrilldownSheet(title: title, data: data),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _appendPreviewComment(
    Tag3DailyRow row, {
    required bool confirm,
    required String body,
  }) {
    final current = _tag3Daily;
    if (current == null) return;
    final now = DateTime.now();
    setState(() {
      _tag3Daily = Tag3DailySnapshot(
        asOfDate: current.asOfDate,
        rows: current.rows,
        assignees: current.assignees,
        comments: [
          ...current.comments,
          Tag3DailyComment(
            id: now.millisecondsSinceEpoch,
            rowKey: row.rowKey,
            period: row.period,
            statDate: row.statDateDay,
            periodLabel: row.periodLabel,
            projectName: row.projectName,
            userId: widget.session.userId,
            userName: (widget.session.displayName ?? '').trim().isEmpty
                ? '我'
                : widget.session.displayName!.trim(),
            kind: confirm ? 'CONFIRM' : 'COMMENT',
            stage: (row.canConfirmStage ?? '').trim(),
            body: body,
            createdAt: now.toIso8601String(),
          ),
        ],
        snapshotHint: current.snapshotHint,
      );
    });
  }

  Future<void> _submitTag3DailyAction(
    Tag3DailyRow row, {
    required bool confirm,
  }) async {
    final stage = (row.canConfirmStage ?? '').trim();
    if (confirm && (!row.showConfirmAction || stage.isEmpty)) return;
    if (!confirm && !row.showCommentAction) return;
    if (_tag3ConfirmingKeys.contains(row.actionId)) return;
    final remark = await showTag3DailyActionDialog(
      context: context,
      row: row,
      confirm: confirm,
    );
    if (remark == null || !mounted) return;
    setState(() => _tag3ConfirmingKeys.add(row.actionId));
    try {
      if (_tag3DailyPreview) {
        _appendPreviewComment(row, confirm: confirm, body: remark);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirm
                  ? '已确认 ${row.projectName} · ${row.periodLabel}'
                  : '已记录 ${row.projectName} · ${row.periodLabel} 的意见',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (confirm) {
        await _api.confirmTag3Daily(
          asOfDate: _asOfDate,
          rowKeys: [row.rowKey],
          stage: stage,
          expectedStatus: row.confirmationStatus,
          remark: remark,
          period: row.period,
          statDate: row.statDateDay,
          periodLabel: row.periodLabel,
          projectName: row.projectName,
        );
      } else {
        await _api.commentTag3Daily(
          asOfDate: _asOfDate,
          row: row,
          body: remark,
        );
      }
      final snap = await _api.fetchTag3Daily(asOfDate: _asOfDate);
      if (!mounted) return;
      setState(() => _tag3Daily = snap);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirm
                ? '已确认 ${row.projectName} · ${row.periodLabel}'
                : '已记录 ${row.projectName} · ${row.periodLabel} 的意见',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _tag3ConfirmingKeys.remove(row.actionId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: _buildBody(),
    );
    if (_level != _ReconLevel.dates) return body;
    return RefreshIndicator(onRefresh: _loadDates, child: body);
  }

  Widget _buildBody() {
    if (_loading && _level == _ReconLevel.dates && _dates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final tableEmpty = _cardKind == 'TAG2_ENTITY'
        ? _tag2 == null
        : _tag3Daily == null;
    if (_error != null &&
        ((_level == _ReconLevel.dates && _dates.isEmpty) ||
            (_level == _ReconLevel.table && tableEmpty))) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 14, color: DunesColors.text2),
          ),
        ],
      );
    }
    switch (_level) {
      case _ReconLevel.dates:
        return _buildDateList();
      case _ReconLevel.table:
        return _buildTable();
    }
  }

  String _tag2DateProgress(ReconDateItem item) {
    final line = tag3DailyDateProgressLine(
      businessConfirmRows: item.tag2BusinessConfirmRows,
      operationConfirmRows: item.tag2OperationConfirmRows,
      commentCount: item.tag2CommentCount,
    );
    if (item.tag2BusinessConfirmRows == 0 &&
        item.tag2OperationConfirmRows == 0 &&
        item.tag2CommentCount == 0) {
      return '业务、运营各自确认，合计行只展示';
    }
    return line;
  }

  Widget _buildDateList() {
    final dates = _visibleDates;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildDatePicker(),
        if (dates.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 40, 8, 0),
            child: Text(
              '还没有日清月结。到达每日推送时间后会出现在这里。',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
            ),
          )
        else
          for (final item in dates) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                shucaiDisplayDate(item.asOfDate),
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
            ),
            _DailyCard(
              title: reconCardTitle('TAG3_DAILY'),
              subtitle: tag3DailyDispatchBody(item.asOfDate),
              progress: tag3DailyDateProgressLine(
                businessConfirmRows: item.tag3BusinessConfirmRows,
                operationConfirmRows: item.tag3OperationConfirmRows,
                commentCount: item.tag3CommentCount,
              ),
              pill: tag3DailyDateStatusPill(
                myConfirmed: item.tag3MyConfirmed,
                confirmRows: item.tag3ConfirmRows,
              ),
              done: item.tag3MyConfirmed,
              highlighted:
                  item.tag3ConfirmRows > 0 || item.tag3CommentCount > 0,
              onTap: () => unawaited(_openCard(item.asOfDate, 'TAG3_DAILY')),
            ),
            const SizedBox(height: 8),
            _DailyCard(
              title: reconCardTitle('TAG2_ENTITY'),
              subtitle: '${item.asOfDate} 按主体核对，业务/运营请各自确认',
              progress: _tag2DateProgress(item),
              pill: tag3DailyDateStatusPill(
                myConfirmed: item.tag2MyConfirmed,
                confirmRows: item.tag2ConfirmRows,
              ),
              done: item.tag2MyConfirmed,
              highlighted:
                  item.tag2ConfirmRows > 0 || item.tag2CommentCount > 0,
              onTap: () => unawaited(_openCard(item.asOfDate, 'TAG2_ENTITY')),
            ),
          ],
      ],
    );
  }

  Widget _buildDatePicker() {
    final picked = _selectedDate.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '对账日',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    picked.isEmpty ? '最近日期' : shucaiDisplayDate(picked),
                    style: DunesTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: _pickDate, child: const Text('选择日期')),
            if (picked.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _selectedDate = ''),
                child: const Text('全部'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    if (_cardKind == 'TAG2_ENTITY') return _buildTag2Table();
    final snap = _tag3Daily;
    if (_loading && snap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${shucaiDisplayDate(_asOfDate)} · ${reconCardTitle('TAG3_DAILY')}',
                          style: DunesTypography.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          snap == null
                              ? '右侧可直接确认，意见选填。'
                              : tag3DailySnapshotStatusLine(
                                  snap.rows,
                                  snapshotHint: snap.snapshotHint,
                                ),
                          style: DunesTypography.sans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (snap != null) ...[
                    const SizedBox(width: 8),
                    Tag3DailyOpinionEntry(
                      count: tag3DailyOpinionComments(snap.comments).length,
                      onTap: () {
                        unawaited(
                          showTag3DailyOpinionList(
                            context: context,
                            title: shucaiDisplayDate(_asOfDate),
                            comments: snap.comments,
                            rows: snap.rows,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _error!,
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.coral,
              ),
            ),
          ),
        Expanded(
          child: snap == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  child: Tag3DailyTable(
                    rows: snap.rows,
                    assignees: snap.assignees,
                    comments: snap.comments,
                    myUserId: widget.session.userId,
                    busyKeys: _tag3ConfirmingKeys,
                    onProjectTap: (row) => unawaited(
                      _openTag3DailyDrilldown(
                        row: row,
                        metricKey: 'provinceSplit',
                      ),
                    ),
                    onReceivableTap: (row) => unawaited(
                      _openTag3DailyDrilldown(
                        row: row,
                        metricKey: 'receivableAmount',
                      ),
                    ),
                    onConfirm: (row) =>
                        unawaited(_submitTag3DailyAction(row, confirm: true)),
                    onComment: (row) =>
                        unawaited(_submitTag3DailyAction(row, confirm: false)),
                    onViewComments: (row) {
                      unawaited(
                        showTag3DailyCommentHistory(
                          context: context,
                          row: row,
                          comments: snap.commentsFor(row),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTag2Table() {
    final snap = _tag2;
    if (_loading && snap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final hint = (snap?.snapshotHint ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${shucaiDisplayDate(_asOfDate)} · ${reconCardTitle('TAG2_ENTITY')}',
                    style: DunesTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint.isEmpty
                        ? '按主体核对。业务、运营各自确认，也可以提意见。合计行只展示。'
                        : hint,
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error!,
              style: DunesTypography.sans(fontSize: 13, color: DunesColors.coral),
            ),
          ),
        Expanded(
          child: snap == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Tag2EntityTable(
                  rows: snap.rows,
                  comments: snap.comments,
                  busyKeys: _tag2Busy,
                  onDrill: (row, amount) =>
                      unawaited(_openTag2Drilldown(row, amount)),
                  onConfirm: (row) =>
                      unawaited(_submitTag2Action(row, confirm: true)),
                  onComment: (row) =>
                      unawaited(_submitTag2Action(row, confirm: false)),
                ),
        ),
      ],
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.pill,
    required this.done,
    required this.highlighted,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String progress;
  final String pill;
  final bool done;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: DunesTypography.sans(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: DunesColors.text,
                            ),
                          ),
                        ),
                        _Tag3DailyDateStatusPill(label: pill, done: done),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: DunesColors.text2,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: highlighted
                            ? DunesColors.accent
                            : DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag3DailyDateStatusPill extends StatelessWidget {
  const _Tag3DailyDateStatusPill({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? DunesColors.greenSoft : DunesColors.amberSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: done ? DunesColors.green : DunesColors.amber,
        ),
      ),
    );
  }
}
