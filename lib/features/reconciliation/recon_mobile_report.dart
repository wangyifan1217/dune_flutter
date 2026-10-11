import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'tag2_entity_models.dart';
import 'tag3_daily_models.dart';
import 'recon_report_summary.dart';

/// Shared report controls. All mutations stay with the existing page callbacks.
class ReconMobileMetric {
  const ReconMobileMetric(
    this.label,
    this.value, {
    this.onTap,
    this.difference = false,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool difference;
}

class ReconMobileEntry {
  const ReconMobileEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.metrics,
    required this.groups,
    required this.comments,
    required this.audit,
    this.period = '',
    this.groupChannel,
    this.provinceName = '',
    this.dateLabel = '',
    this.reportLabels = const [],
    this.confirmStage = '',
    this.confirmedByMe = false,
    this.readOnly = false,
    this.busy = false,
    this.onConfirm,
    this.onComment,
    this.onReject,
    this.onDrill,
    this.onViewComments,
    this.summaryAmounts = const {},
  });
  final String id, title, subtitle, status, period, confirmStage;
  final List<ReconMobileMetric> metrics;
  final List<String> reportLabels;
  final String? groupChannel;
  final String dateLabel;
  final String provinceName;
  final Map<String, List<ReconMobileMetric>> groups;
  final List<Tag3DailyComment> comments;
  final List<Tag3DailyAuditLane> audit;
  final Map<String, double?> summaryAmounts;
  final bool confirmedByMe, readOnly, busy;
  final VoidCallback? onConfirm, onComment, onReject, onDrill, onViewComments;
}

/// 「业务：张三」。确认与否用图标区分，不把「未确认」写进文案。
String reconAuditLaneLabel(Tag3DailyAuditLane lane) {
  final who = lane.names.trim();
  if (who.isEmpty) return lane.role;
  return '${lane.role}：$who';
}

/// 卡片角标只写「待确认」，不再区分待业务 / 待运营。
String reconCardStatusLabel(String status) {
  switch (status.trim()) {
    case '待业务确认':
    case '待运营确认':
      return '待确认';
    default:
      return status.trim();
  }
}

Widget tag3MobileReport({
  required List<Tag3DailyRow> rows,
  required List<Tag3DailyAssignee> assignees,
  required List<Tag3DailyComment> comments,
  required int myUserId,
  required Set<String> busyKeys,
  ValueChanged<Tag3DailyRow>? onConfirm,
  ValueChanged<Tag3DailyRow>? onComment,
  ValueChanged<Tag3DailyRow>? onProjectTap,
  ValueChanged<Tag3DailyRow>? onReceivableTap,
  ValueChanged<Tag3DailyRow>? onViewComments,
  Widget Function(Set<String> visibleIds)? wideTableBuilder,
}) {
  return ReconMobileReport(
    wideTableBuilder: wideTableBuilder,
    searchHint: '搜索项目或渠道',
    entries: [
      for (final row in sortTag3DailyRows(rows))
        (() {
          final history = comments.where((c) => c.matchesRow(row)).toList();
          final mine =
              myUserId > 0 &&
              history.any((c) => c.isConfirm && c.userId == myUserId);
          Tag3DailyAssignee? assignee;
          for (final a in assignees) {
            if (a.rowKey == row.rowKey) {
              assignee = a;
              break;
            }
          }
          final cashMetrics = [
            ReconMobileMetric(
              '现金应收',
              tag3DailyMoney(row.cashReceivableAmount),
              onTap: onReceivableTap == null
                  ? null
                  : () => onReceivableTap(row),
            ),
            ReconMobileMetric('现金实收', tag3DailyMoney(row.cashPaidAmount)),
            ReconMobileMetric(
              '现金应收差额',
              tag3DailyMoney(row.cashReceivableDiff),
              difference: row.cashReceivableDiff != 0,
            ),
          ];
          return ReconMobileEntry(
            id: row.actionId,
            title: row.projectName,
            groupChannel: row.channelCategoryL1Name,
            dateLabel: row.periodLabel,
            subtitle: '${row.channelCategoryL1Name} · ${row.periodLabel}',
            reportLabels: [
              switch (row.period) {
                'DAY' => '日清',
                'PREV_MONTH' => '上月月结',
                'MONTH' => '本月累计',
                _ => row.period,
              },
              if (row.paymentTerm.trim().isNotEmpty) '回款周期 ${row.paymentTerm}',
            ],
            period: row.period,
            status: row.isMonthCumulative
                ? '仅供查看'
                : mine
                ? '我已确认'
                : row.showConfirmAction
                ? '待我确认'
                : row.confirmationStatusLabel,
            metrics: [
              ReconMobileMetric('销售规模', tag3DailyMoney(row.salesScale)),
              ...cashMetrics,
            ],
            summaryAmounts: {
              '销售额': row.salesAmount,
              '销售规模': row.salesScale,
              '核销额': row.writeOffAmount,
              '利润': row.profitAmount,
              '经营性现金流': row.cashFlowAmount,
              '现金应收': row.cashReceivableAmount,
              '现金实收': row.cashPaidAmount,
              '现金应收差额': row.cashReceivableDiff,
              '补贴应收': row.subsidyReceivableAmount,
            },
            groups: {
              '收款核对': cashMetrics,
              '经营数据': [
                ReconMobileMetric('销售额', tag3DailyMoney(row.salesAmount)),
                ReconMobileMetric('销售规模', tag3DailyMoney(row.salesScale)),
                ReconMobileMetric('核销额', tag3DailyMoney(row.writeOffAmount)),
                ReconMobileMetric('利润', tag3DailyMoney(row.profitAmount)),
                ReconMobileMetric('经营性现金流', tag3DailyMoney(row.cashFlowAmount)),
              ],
              '补贴数据': [
                ReconMobileMetric(
                  '补贴应收',
                  tag3DailyMoney(row.subsidyReceivableAmount),
                ),
              ],
            },
            comments: history,
            audit: row.isMonthCumulative
                ? []
                : tag3DailyAuditLanes(
                    assignee: assignee,
                    comments: history,
                    row: row,
                  ),
            confirmStage: row.canConfirmStage ?? '',
            confirmedByMe: mine,
            readOnly: row.isMonthCumulative,
            busy: busyKeys.contains(row.actionId),
            onConfirm: row.showConfirmAction && !mine && onConfirm != null
                ? () => onConfirm(row)
                : null,
            onComment: row.showCommentAction && onComment != null
                ? () => onComment(row)
                : null,
            onDrill: onProjectTap == null ? null : () => onProjectTap(row),
            onViewComments: onViewComments == null
                ? null
                : () => onViewComments(row),
          );
        })(),
    ],
  );
}

Widget tag2MobileReport({
  required List<Tag2EntityRow> rows,
  required List<Tag3DailyComment> comments,
  required Set<String> busyKeys,
  required int myUserId,
  required void Function(Tag2EntityRow, Tag2EntityAmount) onDrill,
  required ValueChanged<Tag2EntityRow> onConfirm,
  required ValueChanged<Tag2EntityRow> onComment,
  ValueChanged<Tag2EntityRow>? onReject,
  ValueChanged<Tag2EntityRow>? onViewComments,
  Widget Function(Set<String> visibleIds)? wideTableBuilder,
}) {
  return ReconMobileReport(
    wideTableBuilder: wideTableBuilder,
    searchHint: '搜索主体、省份或供应商',
    entries: [
      for (final row in rows.where((row) => !row.isTotal))
        (() {
          final history = comments
              .where((c) => c.rowKey == row.rowKey)
              .toList();
          final mine =
              myUserId > 0 &&
              history.any((c) => c.isConfirm && c.userId == myUserId);
          final metrics = [
            for (final a in row.amounts)
              ReconMobileMetric(
                a.label.isEmpty ? a.key : a.label,
                a.display,
                onTap: a.drill ? () => onDrill(row, a) : null,
              ),
          ];
          return ReconMobileEntry(
            id: row.rowKey,
            title: row.isTotal
                ? '合计'
                : row.counterpartyName.isEmpty
                ? row.title
                : row.counterpartyName,
            provinceName: row.isTotal ? '' : row.provinceName,
            subtitle: '我方：${row.ourEntityName} · 供应商：${row.supplierName}',
            status: row.isTotal
                ? '仅供查看'
                : row.showConfirm
                ? '待我确认'
                : mine
                ? '我已确认'
                : row.statusLabel,
            metrics: metrics.take(3).toList(),
            summaryAmounts: {
              for (final amount in row.amounts)
                if (amount.key != 'invoice_tax_rate' &&
                    !amount.display.contains('%'))
                  amount.label.isEmpty ? amount.key : amount.label:
                      reconSummaryAmount(amount.display),
            },
            groups: {
              '主体信息': [
                ReconMobileMetric('省份', row.provinceName),
                ReconMobileMetric('对方主体', row.counterpartyName),
                ReconMobileMetric('我方主体', row.ourEntityName),
                ReconMobileMetric('供应商', row.supplierName),
              ],
              '核对金额': metrics,
            },
            comments: history,
            audit: row.isTotal ? [] : tag2EntityAuditLanes(row, history),
            confirmStage: row.canConfirmStage,
            confirmedByMe: mine,
            readOnly: row.isTotal,
            busy: busyKeys.contains(row.rowKey),
            onConfirm: row.showConfirm ? () => onConfirm(row) : null,
            onComment: row.showComment ? () => onComment(row) : null,
            onReject: row.showReject && onReject != null
                ? () => onReject(row)
                : null,
            onViewComments: onViewComments == null
                ? null
                : () => onViewComments(row),
          );
        })(),
    ],
  );
}

enum _WorkFilter {
  all,
  pending,
  confirmed,
  opinions,
  businessPending,
  operationPending,
  businessConfirmed,
  operationConfirmed,
  completed,
  noRecords,
}

class ReconMobileReport extends StatefulWidget {
  const ReconMobileReport({
    super.key,
    required this.entries,
    required this.searchHint,
    this.wideTableBuilder,
  });
  final List<ReconMobileEntry> entries;
  final String searchHint;
  final Widget Function(Set<String> visibleIds)? wideTableBuilder;
  @override
  State<ReconMobileReport> createState() => _ReconMobileReportState();
}

class _ReconMobileReportState extends State<ReconMobileReport> {
  final _search = TextEditingController();
  String _period = 'ALL';
  _WorkFilter _filter = _WorkFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasPeriods => widget.entries.any((e) => e.period.isNotEmpty);
  bool _hasOpinion(ReconMobileEntry e) =>
      e.comments.any((c) => c.isOpinion || c.isReject);
  List<ReconMobileEntry> get _visible => widget.entries.where((e) {
    if (_hasPeriods && _period != 'ALL' && e.period != _period) return false;
    final term = _search.text.trim().toLowerCase();
    if (term.isNotEmpty &&
        !'${e.title} ${e.provinceName} ${e.subtitle} ${e.reportLabels.join(' ')}'
            .toLowerCase()
            .contains(term)) {
      return false;
    }
    return switch (_filter) {
      _WorkFilter.all => true,
      _WorkFilter.pending => e.onConfirm != null,
      _WorkFilter.confirmed => e.confirmedByMe,
      _WorkFilter.opinions => _hasOpinion(e),
      _WorkFilter.businessPending =>
        !e.readOnly && e.audit.any((l) => l.role == '业务' && !l.done),
      _WorkFilter.operationPending =>
        !e.readOnly && e.audit.any((l) => l.role == '运营' && !l.done),
      _WorkFilter.businessConfirmed =>
        !e.readOnly && e.audit.any((l) => l.role == '业务' && l.done),
      _WorkFilter.operationConfirmed =>
        !e.readOnly && e.audit.any((l) => l.role == '运营' && l.done),
      _WorkFilter.completed =>
        !e.readOnly && e.audit.isNotEmpty && e.audit.every((l) => l.done),
      _WorkFilter.noRecords => !e.readOnly && e.comments.isEmpty,
    };
  }).toList();

  @override
  Widget build(BuildContext context) =>
      widget.wideTableBuilder == null ? _list() : _desktopReport();

  Widget _desktopReport() {
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _desktopToolbar(),
        _desktopSummary(visible),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text('没有符合条件的记录', style: _secondaryStyle(13)))
              : widget.wideTableBuilder!({
                  for (final entry in visible) entry.id,
                }),
        ),
      ],
    );
  }

  List<List<ReconMobileEntry>> _groupedEntries(List<ReconMobileEntry> visible) {
    final grouped = <(String, String), List<ReconMobileEntry>>{};
    for (final e in visible) {
      final key = e.groupChannel == null
          ? (e.id, e.id)
          : (e.groupChannel!, e.title);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    for (final group in grouped.values) {
      group.sort((a, b) {
        final rank = tag3DailyPeriodRank(
          a.period,
        ).compareTo(tag3DailyPeriodRank(b.period));
        return rank == 0 ? a.dateLabel.compareTo(b.dateLabel) : rank;
      });
    }
    return grouped.values.toList();
  }

  Widget _desktopToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 820 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: compact ? constraints.maxWidth : 260,
              child: TextField(
                controller: _search,
                style: _style(12),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: DunesColors.resolve(
                    context,
                    DunesColors.bgSoft,
                    role: DunesColorRole.surface,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            if (_hasPeriods)
              _desktopSelect(
                '统计周期',
                _periodLabels,
                _period,
                (value) => setState(() {
                  _period = value;
                  _filter = _WorkFilter.all;
                }),
              ),
            _desktopSelect(
              '确认与记录',
              _filterLabels,
              _filter,
              (value) => setState(() => _filter = value),
            ),
            if (_period != 'ALL' ||
                _filter != _WorkFilter.all ||
                _search.text.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _period = 'ALL';
                  _filter = _WorkFilter.all;
                  _search.clear();
                }),
                child: const Text('重置筛选'),
              ),
          ],
        );
      },
    ),
  );

  Widget _desktopSelect<T>(
    String label,
    Map<T, String> labels,
    T value,
    ValueChanged<T> onChanged,
  ) => SizedBox(
    width: 168,
    child: DropdownButtonFormField<T>(
      key: ValueKey('recon-desktop-$label-$value'),
      initialValue: value,
      isExpanded: true,
      style: _style(12),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (final item in labels.entries)
          DropdownMenuItem(
            value: item.key,
            child: Text(item.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );

  Widget _desktopSummary(List<ReconMobileEntry> visible) {
    final review = visible.where((e) => !e.readOnly).toList();
    int confirmed(String role) => review
        .where((e) => e.audit.any((l) => l.role == role && l.done))
        .length;
    final opinions = <int>{
      for (final e in review)
        for (final c in e.comments)
          if (c.isOpinion || c.isReject) c.id,
    }.length;
    return Container(
      key: const ValueKey('recon-desktop-summary'),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: _panelDecoration(tinted: true),
      child: Wrap(
        spacing: 20,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final metric in {
            '业务已确认': confirmed('业务'),
            '运营已确认': confirmed('运营'),
            '意见': opinions,
          }.entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(metric.key, style: _secondaryStyle(12)),
                const SizedBox(width: 8),
                Text(
                  '${metric.value}',
                  key: ValueKey('recon-summary-${metric.key}'),
                  style: _style(19, bold: true).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          TextButton(
            onPressed: () => _showSummaryRecords(review, opinions: false),
            child: const Text('查看审核记录'),
          ),
          TextButton(
            onPressed: () => _showSummaryRecords(review, opinions: true),
            child: const Text('查看意见记录'),
          ),
        ],
      ),
    );
  }

  Color get _accent => DunesColors.resolve(context, DunesColors.accent);
  TextStyle _style(double size, {bool bold = false}) => DunesTypography.sans(
    context: context,
    fontSize: size,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    color: DunesColors.resolve(context, DunesColors.text),
    height: 1.3,
  );

  static const _periodLabels = {
    'ALL': '全部周期',
    'DAY': '日清',
    'PREV_MONTH': '上月月结',
    'MONTH': '本月累计',
  };
  static const _filterLabels = {
    _WorkFilter.all: '全部',
    _WorkFilter.pending: '待我确认',
    _WorkFilter.confirmed: '我已确认',
    _WorkFilter.opinions: '有意见',
    _WorkFilter.businessPending: '业务未确认',
    _WorkFilter.operationPending: '运营未确认',
    _WorkFilter.businessConfirmed: '业务已确认',
    _WorkFilter.operationConfirmed: '运营已确认',
    _WorkFilter.completed: '全部完成',
    _WorkFilter.noRecords: '无本地记录',
  };

  Widget _searchAndFilter() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: _style(13),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: _secondaryStyle(13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: DunesColors.resolve(
                    context,
                    DunesColors.bgSoft,
                    role: DunesColorRole.surface,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('recon-filter-open'),
              tooltip: '筛选明细',
              onPressed: _showFilters,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: DunesColors.resolve(
                  context,
                  DunesColors.accentSoft,
                  role: DunesColorRole.surface,
                ),
                foregroundColor: _accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        if (_period != 'ALL' || _filter != _WorkFilter.all)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_hasPeriods ? '${_periodLabels[_period]} · ' : ''}${_filterLabels[_filter]}',
                  style: _secondaryStyle(12),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _period = 'ALL';
                  _filter = _WorkFilter.all;
                }),
                child: const Text('重置筛选'),
              ),
            ],
          ),
      ],
    ),
  );

  Future<void> _showFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    var period = _period;
    var filter = _filter;
    final result = await showModalBottomSheet<(String, _WorkFilter)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          Widget options<T>(
            String title,
            Map<T, String> labels,
            T selected,
            ValueChanged<T> choose,
          ) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _style(14, bold: true)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in labels.entries)
                      ChoiceChip(
                        label: Text(option.value, style: _style(13)),
                        selected: selected == option.key,
                        showCheckmark: false,
                        selectedColor: DunesColors.resolve(
                          context,
                          DunesColors.accentSoft,
                          role: DunesColorRole.surface,
                        ),
                        side: BorderSide(
                          color: DunesColors.resolve(
                            context,
                            DunesColors.borderSoft,
                            role: DunesColorRole.border,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (_) => update(() => choose(option.key)),
                      ),
                  ],
                ),
              ],
            ),
          );
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('筛选明细', style: _style(18, bold: true)),
                        ),
                        IconButton(
                          tooltip: '关闭筛选',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_hasPeriods)
                              options('统计周期', _periodLabels, period, (value) {
                                period = value;
                                filter = _WorkFilter.all;
                              }),
                            options(
                              '确认与记录',
                              _filterLabels,
                              filter,
                              (value) => filter = value,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => update(() {
                              period = 'ALL';
                              filter = _WorkFilter.all;
                            }),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            child: const Text('重置'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            key: const ValueKey('recon-filter-apply'),
                            onPressed: () =>
                                Navigator.pop(sheetContext, (period, filter)),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            child: const Text('应用筛选'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _period = result.$1;
      _filter = result.$2;
    });
  }

  Widget _list() {
    final visible = _visible;
    final groups = _groupedEntries(visible);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchAndFilter(),
              _summary(visible),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                child: Text(
                  _hasPeriods && _period == 'MONTH'
                      ? '本月累计仅供查看，不参与确认 · ${groups.length} 项${_hasPeriods ? ' · ${visible.length} 条记录' : ''}'
                      : '${_hasPeriods ? '金额单位：元 · ' : ''}${groups.length} 项${_hasPeriods ? ' · ${visible.length} 条记录' : ''}',
                  style: _secondaryStyle(11),
                ),
              ),
            ],
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('没有符合条件的记录', style: _style(14))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            sliver: SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, i) => groups[i].first.groupChannel == null
                  ? _card(groups[i].first)
                  : _projectCard(groups[i]),
            ),
          ),
      ],
    );
  }

  Widget _card(ReconMobileEntry e) => Card(
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: .06),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: DunesColors.resolve(
          context,
          DunesColors.borderSoft,
          role: DunesColorRole.border,
        ),
      ),
    ),
    margin: const EdgeInsets.only(bottom: 12),
    color: DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: _entryBody(e),
    ),
  );

  BoxDecoration _panelDecoration({bool tinted = false}) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        DunesColors.resolve(
          context,
          tinted ? const Color(0xFFEDF5F2) : Colors.white,
          role: DunesColorRole.surface,
        ),
        DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
      ],
    ),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: DunesColors.resolve(
        context,
        tinted ? const Color(0xFFDCE8E2) : const Color(0xFFE6EAE7),
        role: DunesColorRole.border,
      ),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: .025),
        blurRadius: 18,
        offset: const Offset(0, 5),
      ),
    ],
  );

  Widget _summary(List<ReconMobileEntry> visible) {
    final review = <String, ReconMobileEntry>{
      for (final entry in visible)
        if (!entry.readOnly) entry.id: entry,
    }.values.toList();
    int confirmed(String role) => review
        .where((e) => e.audit.any((l) => l.role == role && l.done))
        .length;
    final opinions = <int>{
      for (final e in review)
        for (final c in e.comments)
          if (c.isOpinion || c.isReject) c.id,
    }.length;
    return Container(
      key: const ValueKey('recon-mobile-summary'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
      decoration: _panelDecoration(tinted: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final metric in {
                '业务已确认': confirmed('业务'),
                '运营已确认': confirmed('运营'),
                '意见': opinions,
              }.entries)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${metric.value}',
                        key: ValueKey('recon-summary-${metric.key}'),
                        style: _style(23, bold: true).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(metric.key, style: _secondaryStyle(11)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _showSummaryRecords(review, opinions: false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(
                    '查看审核记录',
                    style: _style(12).copyWith(color: _accent),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => _showSummaryRecords(review, opinions: true),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(
                    '查看意见记录',
                    style: _style(12).copyWith(color: _accent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showSummaryRecords(
    List<ReconMobileEntry> entries, {
    required bool opinions,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final matching = entries
        .where(
          (e) => opinions
              ? _hasOpinion(e)
              : e.comments.isNotEmpty || e.audit.any((l) => l.done),
        )
        .toList();
    await _showReportSheet(
      initialSize: .72,
      builder: (controller, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetHeader(
            opinions ? '意见记录 · 当前筛选' : '审核记录 · 当前筛选',
            '关闭汇总记录',
            close,
          ),
          Expanded(
            child: matching.isEmpty
                ? Center(
                    child: Text(
                      opinions ? '暂无意见记录' : '暂无审核记录',
                      style: _secondaryStyle(14),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: matching.length,
                    itemBuilder: (context, index) {
                      final e = matching[index];
                      final records =
                          e.comments
                              .where(
                                (c) => !opinions || c.isOpinion || c.isReject,
                              )
                              .toList()
                            ..sort(
                              (a, b) => b.createdAt.compareTo(a.createdAt),
                            );
                      return _section(
                        '${e.title} · ${e.dateLabel.isEmpty ? e.subtitle : e.dateLabel}',
                        [
                          if (!opinions) ...[
                            for (final lane in e.audit)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: _auditLane(lane),
                              ),
                            if (records.isEmpty)
                              Text(
                                '源系统已有确认状态，暂无本地操作记录。',
                                style: _secondaryStyle(12),
                              ),
                          ],
                          for (final record in records) _recordItem(record),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _projectCard(List<ReconMobileEntry> entries) {
    final first = entries.first;
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: .06),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: DunesColors.resolve(
              context,
              const Color(0xFFF1F6F3),
              role: DunesColorRole.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.title,
                  style: _style(16, bold: true).copyWith(letterSpacing: -.25),
                ),
                const SizedBox(height: 3),
                Text(
                  '${first.groupChannel} · ${entries.length} 条记录',
                  style: _secondaryStyle(12),
                ),
              ],
            ),
          ),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) _hairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: _entryBody(entries[i], grouped: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entryBody(ReconMobileEntry e, {bool grouped = false}) {
    return Column(
      key: ValueKey('recon-entry-${e.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: grouped
                  ? Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: _accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.dateLabel,
                            style: _style(
                              15,
                              bold: true,
                            ).copyWith(color: _accent),
                          ),
                        ),
                      ],
                    )
                  : _entryTitle(e),
            ),
            const SizedBox(width: 8),
            _statusPill(e),
          ],
        ),
        if (!grouped) const SizedBox(height: 4),
        if (!grouped)
          Text(
            e.subtitle,
            style: _style(
              12,
            ).copyWith(color: DunesColors.resolve(context, DunesColors.text2)),
          ),
        if (e.reportLabels.isNotEmpty) ...[
          const SizedBox(height: 5),
          _reportLabels(e),
        ],
        const SizedBox(height: 8),
        _metricTiles(e.metrics),
        const SizedBox(height: 10),
        if (e.audit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [for (final lane in e.audit) _auditLane(lane)],
            ),
          ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _recordLink('查看明细', () => _showDetails(e)),
            _recordLink('确认记录', () => _showRecords(e, opinions: false)),
            _recordLink('意见记录', () => _showRecords(e, opinions: true)),
          ],
        ),
        if (!e.readOnly &&
            (e.onConfirm != null ||
                e.onComment != null ||
                e.onReject != null)) ...[
          Divider(
            height: 12,
            color: DunesColors.resolve(
              context,
              DunesColors.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
          _actions(e),
        ],
      ],
    );
  }

  Widget _metricTiles(List<ReconMobileMetric> metrics) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 260 &&
          MediaQuery.textScalerOf(context).scale(1) < 1.5 &&
          !metrics.any(
            (m) =>
                m.value.length > 12 ||
                m.value.length *
                        18 *
                        .6 *
                        MediaQuery.textScalerOf(context).scale(1) >
                    (constraints.maxWidth - 10) / 2 - 24,
          );
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: twoColumns
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth,
              child: Material(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFF5F7F6),
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: metric.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                metric.label,
                                style: _secondaryStyle(11),
                              ),
                            ),
                            if (metric.onTap != null)
                              Icon(
                                Icons.north_east_rounded,
                                size: 13,
                                color: _accent,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          metric.value.isEmpty ? '—' : metric.value,
                          style: _style(18, bold: true).copyWith(
                            letterSpacing: -.35,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: metric.difference
                                ? DunesColors.resolve(
                                    context,
                                    DunesColors.coral,
                                  )
                                : metric.onTap != null
                                ? _accent
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _entryTitle(ReconMobileEntry e) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (e.provinceName.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.accentSoft,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            e.provinceName,
            style: _style(15, bold: true).copyWith(color: _accent),
          ),
        ),
      Text(e.title, style: _style(15, bold: true)),
    ],
  );

  Widget _reportLabels(ReconMobileEntry e) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final label in e.reportLabels.where((s) => s.isNotEmpty))
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.accentSoft,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: _style(11, bold: true).copyWith(color: _accent),
          ),
        ),
    ],
  );

  Widget _recordLink(String label, VoidCallback onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(72, 44),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(label, style: _style(13).copyWith(color: _accent)),
  );

  Future<void> _showRecords(
    ReconMobileEntry e, {
    required bool opinions,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final title = opinions ? '意见记录' : '确认记录';
    final records =
        e.comments
            .where((c) => opinions ? c.isOpinion || c.isReject : c.isConfirm)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _showReportSheet(
      initialSize: opinions && records.length <= 2 ? 0.42 : 0.6,
      builder: (controller, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetHeader(title, '关闭记录', close),
          Expanded(
            child: ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _entrySummary(e),
                if (!opinions && e.audit.isNotEmpty)
                  _section('确认进度', [
                    for (final lane in e.audit)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: _auditLane(lane, fontSize: 13),
                      ),
                  ]),
                _section('$title · ${records.length} 条', [
                  if (records.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        !opinions && e.audit.any((lane) => lane.done)
                            ? '源系统已有确认状态，暂无本地操作记录。'
                            : '暂无$title',
                        style: _secondaryStyle(13),
                      ),
                    ),
                  for (var i = 0; i < records.length; i++) ...[
                    if (i > 0) _hairline(),
                    _recordItem(records[i]),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _secondaryStyle(double size) => _style(
    size,
  ).copyWith(color: DunesColors.resolve(context, DunesColors.text2));

  Widget _hairline() => Divider(
    height: 1,
    thickness: 0.5,
    color: DunesColors.resolve(
      context,
      DunesColors.borderSoft,
      role: DunesColorRole.border,
    ),
  );

  Widget _recordItem(Tag3DailyComment c) {
    final stage = c.stage == 'OPERATION'
        ? '运营'
        : c.stage == 'BUSINESS'
        ? '业务'
        : '确认';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${c.userName.trim().isEmpty ? '同事' : c.userName} · ${c.kindLabel}'
                '${c.isConfirm ? ' · $stage' : ''}',
                style: _style(13, bold: true).copyWith(
                  color: c.isReject
                      ? DunesColors.resolve(context, DunesColors.coral)
                      : null,
                ),
              ),
              Text(
                tag3DailyCommentTime(c.createdAt),
                style: _secondaryStyle(11),
              ),
            ],
          ),
          if (c.displayBody.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(c.displayBody, style: _style(13)),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: _style(13, bold: true).copyWith(color: _accent)),
          const SizedBox(height: 5),
          _hairline(),
          const SizedBox(height: 3),
          ...children,
        ],
      ),
    ),
  );

  Widget _entrySummary(ReconMobileEntry e, {bool showStatus = false}) =>
      Container(
        margin: const EdgeInsets.only(top: 4, bottom: 6),
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration(tinted: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _entryTitle(e),
            const SizedBox(height: 3),
            Text(e.subtitle, style: _secondaryStyle(12)),
            if (e.reportLabels.isNotEmpty) ...[
              const SizedBox(height: 5),
              _reportLabels(e),
            ],
            if (showStatus) ...[
              const SizedBox(height: 5),
              Text(
                e.readOnly ? '仅供查看，不参与确认' : e.status,
                style: _style(13, bold: true).copyWith(color: _accent),
              ),
            ],
          ],
        ),
      );

  Widget _sheetHeader(String title, String closeLabel, VoidCallback close) =>
      Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                DunesColors.border,
                role: DunesColorRole.border,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: _style(15, bold: true))),
                IconButton(
                  tooltip: closeLabel,
                  onPressed: close,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Future<void> _showReportSheet({
    required double initialSize,
    required Widget Function(ScrollController, VoidCallback) builder,
  }) async {
    if (widget.wideTableBuilder != null) {
      final controller = ScrollController();
      try {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: DunesColors.resolve(
              context,
              DunesColors.bgApp,
              role: DunesColorRole.surface,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox(
              width: 760,
              height: MediaQuery.sizeOf(dialogContext).height * .78,
              child: builder(
                controller,
                () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        );
      } finally {
        controller.dispose();
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: DunesColors.resolve(
        context,
        DunesColors.bgApp,
        role: DunesColorRole.surface,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) =>
            builder(controller, () => Navigator.of(sheetContext).pop()),
      ),
    );
  }

  Widget _statusPill(ReconMobileEntry e) {
    final color = DunesColors.resolve(
      context,
      e.confirmedByMe
          ? DunesColors.green
          : e.onConfirm != null
          ? DunesColors.accent
          : DunesColors.text2,
    );
    final label =
        !e.readOnly &&
            e.onConfirm == null &&
            !e.confirmedByMe &&
            e.audit.isNotEmpty &&
            e.audit.every((l) => l.done)
        ? '已全部确认'
        : reconCardStatusLabel(e.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.isEmpty ? '查看状态' : label,
        style: _style(11, bold: true).copyWith(color: color),
      ),
    );
  }

  Widget _auditLane(Tag3DailyAuditLane lane, {double fontSize = 12}) {
    final done = lane.done;
    final color = DunesColors.resolve(
      context,
      done ? DunesColors.green : DunesColors.amber,
    );
    return Tooltip(
      message: lane.statusLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.schedule,
            size: fontSize,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            reconAuditLaneLabel(lane),
            style: _style(fontSize, bold: done).copyWith(
              color: done
                  ? DunesColors.resolve(context, DunesColors.green)
                  : DunesColors.resolve(context, DunesColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(ReconMobileEntry e) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.end,
    children: [
      if (e.onReject != null)
        _actionButton('驳回到业务', e.busy ? null : e.onReject, destructive: true),
      if (e.onComment != null)
        _actionButton('提意见', e.busy ? null : e.onComment),
      if (e.onConfirm != null)
        _actionButton(
          e.busy ? '提交中…' : '${e.confirmStage == 'OPERATION' ? '运营' : '业务'}确认',
          e.busy ? null : e.onConfirm,
          primary: true,
        ),
    ],
  );

  Widget _actionButton(
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
    bool destructive = false,
  }) {
    final color = destructive
        ? DunesColors.resolve(context, DunesColors.coral)
        : _accent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final text = Text(
      label,
      style: _style(
        13,
        bold: true,
      ).copyWith(color: primary ? Colors.white : color),
    );
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(96, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          shape: shape,
        ),
        child: text,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(80, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: color,
        side: BorderSide(
          color: color.withValues(alpha: onPressed == null ? 0.15 : 0.3),
        ),
        shape: shape,
      ),
      child: text,
    );
  }

  Future<void> _showDetails(ReconMobileEntry e) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _showReportSheet(
      initialSize: 0.78,
      builder: (controller, close) =>
          _detail(e, controller: controller, onClose: close),
    );
  }

  Widget _metric(ReconMobileMetric m, {bool compact = false}) {
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 3 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(m.label, style: _secondaryStyle(compact ? 13 : 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              m.value.isEmpty ? '—' : m.value,
              textAlign: TextAlign.right,
              style: _style(compact ? 13 : 14, bold: true).copyWith(
                color: m.difference
                    ? DunesColors.resolve(context, DunesColors.amber)
                    : m.onTap != null
                    ? _accent
                    : null,
              ),
            ),
          ),
          if (m.onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
    return m.onTap == null
        ? content
        : InkWell(
            onTap: m.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(heightFactor: 1, child: content),
            ),
          );
  }

  Widget _detail(
    ReconMobileEntry e, {
    required ScrollController controller,
    required VoidCallback onClose,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetHeader('报表明细', '关闭明细', onClose),
        Expanded(
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _entrySummary(e, showStatus: true),
              for (final group in e.groups.entries)
                _section(group.key, [
                  for (var i = 0; i < group.value.length; i++) ...[
                    if (i > 0) _hairline(),
                    _metric(group.value[i], compact: true),
                  ],
                ]),
              if (e.onDrill != null)
                TextButton.icon(
                  onPressed: e.onDrill,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('查看分省明细'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
