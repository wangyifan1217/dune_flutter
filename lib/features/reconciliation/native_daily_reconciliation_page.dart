import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import 'reconciliation_shucai_models.dart';
import 'reconciliation_shucai_service.dart';
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
  String _asOfDate = '';
  Tag3DailySnapshot? _tag3Daily;
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
        unawaited(_openDate(date));
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
      await _openDate(date);
    } else {
      _publishChrome();
    }
  }

  void _publishChrome() {
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _level == _ReconLevel.dates ? null : _popLevel,
      ),
    );
  }

  void _popLevel() {
    _loadGen++;
    if (_level == _ReconLevel.table) {
      setState(() {
        _level = _ReconLevel.dates;
        _tag3Daily = null;
        _tag3DailyPreview = false;
        _tag3ConfirmingKeys.clear();
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
      final dates = [...items]
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

  Future<void> _openDate(String asOfDate) async {
    final gen = ++_loadGen;
    setState(() {
      _asOfDate = asOfDate;
      _level = _ReconLevel.table;
      _loading = true;
      _error = null;
      _tag3Daily = null;
      _tag3DailyPreview = false;
    });
    _publishChrome();
    try {
      final snap = await _api.fetchTag3Daily(asOfDate: asOfDate);
      if (!mounted || gen != _loadGen) return;
      final usePreview = kTag3DailyStaticPreview &&
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
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: RefreshIndicator(
        onRefresh: () async {
          if (_level == _ReconLevel.dates) {
            await _loadDates();
          } else {
            await _openDate(_asOfDate);
          }
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _level == _ReconLevel.dates && _dates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null &&
        ((_level == _ReconLevel.dates && _dates.isEmpty) ||
            (_level == _ReconLevel.table && _tag3Daily == null))) {
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

  Widget _buildDateList() {
    if (_dates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
        children: [
          Text(
            '还没有日清月结。到达每日推送时间后会出现在这里。',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _dates.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _dates[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(_openDate(item.asOfDate)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shucaiDisplayDate(item.asOfDate),
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '业财一体-日清月结 · 日行确认，本月累计只展示',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            color: DunesColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTable() {
    final snap = _tag3Daily;
    if (_loading && snap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${shucaiDisplayDate(_asOfDate)} · 日清月结',
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '业务和运营一起审、不排队。轮到你名下的行点确认即可，不用填内容。意见另填。本月累计只展示。',
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      color: DunesColors.text2,
                    ),
                  ),
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
                    onConfirm: (row) => unawaited(
                      _submitTag3DailyAction(row, confirm: true),
                    ),
                    onComment: (row) => unawaited(
                      _submitTag3DailyAction(row, confirm: false),
                    ),
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
}
