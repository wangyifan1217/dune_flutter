import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'recon_pinned_table.dart';
import 'tag3_daily_models.dart';

const _kTag3DailyHeaderH = 48.0;
const _kTag3DailyActionWidth = 148.0;
const _kTag3DailyRowMin = 64.0;
const _kTag3DailyProjectGap = 12.0;
const _kTag3DailyDataColWidths = <double>[
  100,
  156,
  108,
  112,
  124,
  124,
  108,
  124,
  124,
  124,
  124,
  108,
  200,
];
const _kTag3DailyDataWidth = 1636.0;
const _kProjectFillA = Color(0xFFF3F0F8);
const _kProjectFillB = Color(0xFFFFFCF8);
const _kProjectEdge = Color(0xFFD4CCE3);
const _kTag3DailyDataLabels = <String>[
  '渠道',
  '项目',
  '统计周期',
  '回款周期',
  '销售额',
  '核销额',
  '利润',
  '经营性现金流',
  '现金应收',
  '现金实收',
  '现金应收差额',
  '补贴应收',
  '审核记录',
];

class _ProjectBand {
  const _ProjectBand({
    required this.fill,
    required this.accent,
    required this.start,
    required this.end,
  });

  final Color fill;
  final Color accent;
  final bool start;
  final bool end;
}

class Tag3DailyTable extends StatelessWidget {
  const Tag3DailyTable({
    super.key,
    required this.rows,
    this.assignees = const [],
    this.comments = const [],
    this.myUserId = 0,
    this.onProjectTap,
    this.onReceivableTap,
    this.onConfirm,
    this.onComment,
    this.onViewComments,
    this.busyKeys = const {},
  });

  final List<Tag3DailyRow> rows;
  final List<Tag3DailyAssignee> assignees;
  final List<Tag3DailyComment> comments;
  final int myUserId;
  final ValueChanged<Tag3DailyRow>? onProjectTap;
  final ValueChanged<Tag3DailyRow>? onReceivableTap;
  final ValueChanged<Tag3DailyRow>? onConfirm;
  final ValueChanged<Tag3DailyRow>? onComment;
  final ValueChanged<Tag3DailyRow>? onViewComments;
  final Set<String> busyKeys;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '暂无明细',
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.resolve(context, DunesColors.text3),
              context: context,
            ),
          ),
        ),
      );
    }
    final sorted = sortTag3DailyRows(rows);
    assert(
      _kTag3DailyDataColWidths.fold<double>(0, (a, b) => a + b) ==
          _kTag3DailyDataWidth,
    );
    final heights = [
      for (var i = 0; i < sorted.length; i++) _rowHeight(sorted, i),
    ];
    final bands = _projectBands(sorted);
    final pinned = ReconPinnedTable(
      headerHeight: _kTag3DailyHeaderH,
      dataWidth: _kTag3DailyDataWidth,
      dataHeader: Row(
        children: [
          for (var c = 0; c < _kTag3DailyDataLabels.length; c++)
            _head(
              context,
              _kTag3DailyDataLabels[c],
              _kTag3DailyDataColWidths[c],
            ),
        ],
      ),
      trailingHeader: _actionHeaderChrome(
        context,
        child: _head(context, '操作', _kTag3DailyActionWidth),
      ),
      rowCount: sorted.length,
      rowHeight: (i) => heights[i],
      dataRowBuilder: (context, i) =>
          _dataRow(context, sorted, i, heights[i], bands[i]),
      trailingRowBuilder: (context, i) => _projectBox(
        context,
        band: bands[i],
        height: heights[i],
        action: true,
        child: SizedBox(
          width: _kTag3DailyActionWidth,
          child: _actionCell(context, sorted[i]),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SizedBox.expand(child: pinned);
        }
        return pinned;
      },
    );
  }

  Widget _dataRow(
    BuildContext context,
    List<Tag3DailyRow> sorted,
    int i,
    double height,
    _ProjectBand band,
  ) {
    final row = sorted[i];
    final showChannel =
        i == 0 ||
        sorted[i - 1].channelCategoryL1Name != row.channelCategoryL1Name;
    final showProject = i == 0 || sorted[i - 1].rowKey != row.rowKey;
    final contentHeight = height - (band.end ? _kTag3DailyProjectGap : 0);
    return _projectBox(
      context,
      band: band,
      height: height,
      child: Row(
        children: [
          _cell(
            context,
            showChannel ? row.channelCategoryL1Name : '',
            _kTag3DailyDataColWidths[0],
            contentHeight,
          ),
          _projectMark(
            context,
            band,
            _tappable(
              context,
              showProject ? row.projectName : '',
              _kTag3DailyDataColWidths[1],
              contentHeight,
              onTap: showProject && onProjectTap != null
                  ? () => onProjectTap!(row)
                  : null,
            ),
          ),
          _cell(
            context,
            row.periodLabel,
            _kTag3DailyDataColWidths[2],
            contentHeight,
          ),
          _cell(
            context,
            row.paymentTerm,
            _kTag3DailyDataColWidths[3],
            contentHeight,
          ),
          _cell(
            context,
            tag3DailyMoney(row.salesAmount),
            _kTag3DailyDataColWidths[4],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _cell(
            context,
            tag3DailyMoney(row.writeOffAmount),
            _kTag3DailyDataColWidths[5],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _cell(
            context,
            tag3DailyMoney(row.profitAmount),
            _kTag3DailyDataColWidths[6],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _cell(
            context,
            tag3DailyMoney(row.cashFlowAmount),
            _kTag3DailyDataColWidths[7],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _tappable(
            context,
            tag3DailyMoney(row.cashReceivableAmount),
            _kTag3DailyDataColWidths[8],
            contentHeight,
            alignRight: true,
            maxLines: 1,
            onTap: onReceivableTap == null ? null : () => onReceivableTap!(row),
          ),
          _cell(
            context,
            tag3DailyMoney(row.cashPaidAmount),
            _kTag3DailyDataColWidths[9],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _cell(
            context,
            tag3DailyMoney(row.cashReceivableDiff),
            _kTag3DailyDataColWidths[10],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _cell(
            context,
            tag3DailyMoney(row.subsidyReceivableAmount),
            _kTag3DailyDataColWidths[11],
            contentHeight,
            alignRight: true,
            maxLines: 1,
          ),
          _auditCell(context, row, _kTag3DailyDataColWidths[12], contentHeight),
        ],
      ),
    );
  }

  List<_ProjectBand> _projectBands(List<Tag3DailyRow> sorted) {
    final out = <_ProjectBand>[];
    var group = 0;
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i].rowKey != sorted[i - 1].rowKey) group++;
      out.add(
        _ProjectBand(
          fill: group.isEven ? _kProjectFillA : _kProjectFillB,
          accent: group.isEven
              ? const Color(0xFF8B7BA8)
              : const Color(0xFF2F5D62),
          start: i == 0 || sorted[i].rowKey != sorted[i - 1].rowKey,
          end:
              i == sorted.length - 1 ||
              sorted[i].rowKey != sorted[i + 1].rowKey,
        ),
      );
    }
    return out;
  }

  Widget _projectBox(
    BuildContext context, {
    required _ProjectBand band,
    required double height,
    required Widget child,
    bool action = false,
  }) {
    final gap = band.end ? _kTag3DailyProjectGap : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DunesColors.resolveNullable(
            context,
            band.fill,
            role: DunesColorRole.surface,
          ),
          border: Border(
            left: action
                ? BorderSide(
                    color: DunesColors.resolve(
                      context,
                      Color(0xFFD9D4CC),
                      role: DunesColorRole.border,
                    ),
                    width: 0.5,
                  )
                : BorderSide.none,
            top: band.start
                ? BorderSide(
                    color: DunesColors.resolve(
                      context,
                      _kProjectEdge,
                      role: DunesColorRole.border,
                    ),
                  )
                : BorderSide.none,
            bottom: BorderSide(
              color: DunesColors.resolve(
                context,
                band.end ? _kProjectEdge : const Color(0x80E6E1D6),
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        child: SizedBox(
          height: height - gap,
          width: action ? null : double.infinity,
          child: child,
        ),
      ),
    );
  }

  Widget _projectMark(BuildContext context, _ProjectBand band, Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: DunesColors.resolve(
              context,
              band.accent,
              role: DunesColorRole.border,
            ),
            width: 3,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _actionHeaderChrome(BuildContext context, {required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          Color(0xFFF5F6F8),
          role: DunesColorRole.surface,
        ),
        border: Border(
          left: BorderSide(
            color: DunesColors.resolve(
              context,
              DunesColors.border,
              role: DunesColorRole.border,
            ),
            width: 0.5,
          ),
        ),
      ),
      child: child,
    );
  }

  Tag3DailyAssignee? _assigneeFor(Tag3DailyRow row) {
    final key = row.rowKey;
    for (final item in assignees) {
      if (item.rowKey == key) return item;
    }
    return null;
  }

  List<Tag3DailyComment> _commentsFor(Tag3DailyRow row) {
    return [
      for (final item in comments)
        if (item.matchesRow(row)) item,
    ];
  }

  double _rowHeight(List<Tag3DailyRow> sorted, int i) {
    final row = sorted[i];
    final showChannel =
        i == 0 ||
        sorted[i - 1].channelCategoryL1Name != row.channelCategoryL1Name;
    final showProject = i == 0 || sorted[i - 1].rowKey != row.rowKey;
    final projectEnd =
        i == sorted.length - 1 || sorted[i].rowKey != sorted[i + 1].rowKey;
    var height = _kTag3DailyRowMin;
    if (showChannel) {
      height = math.max(
        height,
        28 +
            _measureText(
              row.channelCategoryL1Name,
              _kTag3DailyDataColWidths[0],
            ),
      );
    }
    if (showProject) {
      height = math.max(
        height,
        28 + _measureText(row.projectName, _kTag3DailyDataColWidths[1]),
      );
    }
    height = math.max(
      height,
      28 + _measureText(row.paymentTerm, _kTag3DailyDataColWidths[3]),
    );
    height = math.max(height, math.max(_auditHeight(row), _actionHeight(row)));
    if (projectEnd) height += _kTag3DailyProjectGap;
    return height;
  }

  double _actionHeight(Tag3DailyRow row) {
    if (row.isMonthCumulative) return _kTag3DailyRowMin;
    return _commentsFor(row).isEmpty ? 68.0 : 108.0;
  }

  double _auditHeight(Tag3DailyRow row) {
    if (row.isMonthCumulative) return 0;
    final lanes = tag3DailyAuditLanes(
      assignee: _assigneeFor(row),
      comments: _commentsFor(row),
    );
    if (lanes.isEmpty) return 0;
    return 20 + lanes.length * 26 + (lanes.length - 1) * 8;
  }

  double _measureText(String text, double colWidth) {
    if (text.trim().isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DunesTypography.sans(
          fontSize: 13,
          height: 1.35,
          color: DunesColors.text,
        ),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (colWidth - 24).clamp(24.0, colWidth));
    return painter.height;
  }

  Widget _auditCell(
    BuildContext context,
    Tag3DailyRow row,
    double width,
    double height,
  ) {
    if (row.isMonthCumulative) {
      return SizedBox(width: width, height: height);
    }
    final lanes = tag3DailyAuditLanes(
      assignee: _assigneeFor(row),
      comments: _commentsFor(row),
    );
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lanes.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _auditLane(context, lanes[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _auditLane(BuildContext context, Tag3DailyAuditLane lane) {
    final color = lane.done
        ? DunesColors.resolve(context, DunesColors.green)
        : DunesColors.resolve(context, DunesColors.amber);
    final icon = lane.done ? Icons.check_circle : Icons.schedule;
    return Semantics(
      label: '${lane.role} ${lane.names} ${lane.statusLabel}',
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: DunesColors.resolveNullable(context, color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${lane.role} ${lane.names}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: lane.done
                    ? DunesColors.resolve(context, DunesColors.green)
                    : DunesColors.resolve(context, DunesColors.text),
                context: context,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCell(BuildContext context, Tag3DailyRow row) {
    if (row.isMonthCumulative) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '月累计',
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
              context: context,
            ),
          ),
        ),
      );
    }
    final busy = busyKeys.contains(row.actionId);
    final history = _commentsFor(row);
    final mineConfirmed =
        myUserId > 0 &&
        history.any((item) => item.isConfirm && item.userId == myUserId);
    final showConfirm = row.showConfirmAction && !mineConfirmed;
    final showComment = row.showCommentAction;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (history.isNotEmpty) ...[
            _commentEntry(context, row, history),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              if (showComment)
                Expanded(
                  child: _actionChip(
                    context,
                    label: '意见',
                    filled: false,
                    enabled: !busy && onComment != null,
                    onTap: () => onComment?.call(row),
                  ),
                ),
              if (showComment && (showConfirm || mineConfirmed))
                const SizedBox(width: 6),
              if (showConfirm)
                Expanded(
                  child: _actionChip(
                    context,
                    label: busy
                        ? '提交中'
                        : tag3DailyConfirmButtonLabel(row.canConfirmStage),
                    filled: true,
                    enabled: !busy && onConfirm != null,
                    onTap: () => onConfirm?.call(row),
                  ),
                )
              else if (mineConfirmed)
                Expanded(
                  child: Text(
                    '已确认',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.green),
                      context: context,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _commentEntry(
    BuildContext context,
    Tag3DailyRow row,
    List<Tag3DailyComment> history,
  ) {
    final ordered = [...history]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final latest = ordered.last;
    final name = latest.userName.trim().isEmpty ? '同事' : latest.userName.trim();
    final preview = latest.displayBody.trim();
    final count = history.length;
    final text = preview.isEmpty
        ? '$count条意见'
        : (count == 1 ? '$name：$preview' : '$name：$preview');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onViewComments == null ? null : () => onViewComments!(row),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.accent),
                    context: context,
                  ),
                ),
              ),
              if (count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '$count条',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, DunesColors.accent),
                    context: context,
                  ),
                ),
              ],
              Icon(
                Icons.chevron_right,
                size: 14,
                color: DunesColors.resolveNullable(context, DunesColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required String label,
    required bool filled,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    final color = enabled
        ? DunesColors.resolve(context, DunesColors.accent)
        : DunesColors.resolve(context, DunesColors.text3);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          height: 34,
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              filled
                  ? (enabled
                        ? DunesColors.accent
                        : DunesColors.accent.withValues(alpha: 0.35))
                  : Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: filled
                    ? DunesColors.resolve(context, Colors.white)
                    : color,
                context: context,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(BuildContext context, String text, double width) {
    return SizedBox(
      width: width,
      height: _kTag3DailyHeaderH,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text2),
              context: context,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String text,
    double width,
    double height, {
    bool alignRight = false,
    int maxLines = 2,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: DunesTypography.sans(
              fontSize: 13,
              height: 1.35,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tappable(
    BuildContext context,
    String text,
    double width,
    double height, {
    VoidCallback? onTap,
    bool alignRight = false,
    int maxLines = 2,
  }) {
    final child = _cell(
      context,
      text,
      width,
      height,
      alignRight: alignRight,
      maxLines: maxLines,
    );
    if (onTap == null || text.trim().isEmpty) return child;
    return InkWell(
      onTap: onTap,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: DunesColors.resolveNullable(context, DunesColors.accent),
          decoration: TextDecoration.underline,
          decorationColor: DunesColors.resolve(context, DunesColors.accent),
        ),
        child: child,
      ),
    );
  }
}

class Tag3DailyDrilldownSheet extends StatelessWidget {
  const Tag3DailyDrilldownSheet({
    super.key,
    required this.title,
    required this.data,
  });

  final String title;
  final Tag3DailyDrilldown data;

  @override
  Widget build(BuildContext context) {
    final province = data.metricKey == 'provinceSplit';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text),
                context: context,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '销售额 ${tag3DailyMoney(data.totalSales)}  ·  核销 ${tag3DailyMoney(data.totalWriteOff)}  ·  利润 ${tag3DailyMoney(data.totalProfit)}',
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            ),
            if (data.snapshotHint.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                data.snapshotHint.trim(),
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.accent),
                  context: context,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (data.items.isEmpty)
              Text(
                '暂无下钻明细',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              )
            else
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: const {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.unknown,
                    },
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      primary: false,
                      child: SingleChildScrollView(
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 36,
                          dataRowMinHeight: 36,
                          dataRowMaxHeight: 44,
                          columns: [
                            DataColumn(label: Text(province ? '省份' : '统计日')),
                            DataColumn(label: Text(province ? '周期' : '产品')),
                            const DataColumn(label: Text('销售额'), numeric: true),
                            const DataColumn(label: Text('核销额'), numeric: true),
                            const DataColumn(label: Text('利润'), numeric: true),
                            const DataColumn(label: Text('利润率')),
                            DataColumn(
                              label: Text(province ? '现金应收' : '应收'),
                              numeric: true,
                            ),
                          ],
                          rows: [
                            for (final item in data.items)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      province
                                          ? item.provinceName
                                          : item.statDate,
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      province
                                          ? item.periodLabel
                                          : item.productName,
                                    ),
                                  ),
                                  DataCell(
                                    Text(tag3DailyMoney(item.salesAmount)),
                                  ),
                                  DataCell(
                                    Text(tag3DailyMoney(item.writeOffAmount)),
                                  ),
                                  DataCell(
                                    Text(tag3DailyMoney(item.profitAmount)),
                                  ),
                                  DataCell(
                                    Text(tag3DailyPercent(item.profitRate)),
                                  ),
                                  DataCell(
                                    Text(
                                      tag3DailyMoney(
                                        province
                                            ? item.cashReceivableAmount
                                            : item.receivableAmount,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showTag3DailyActionDialog({
  required BuildContext context,
  required Tag3DailyRow row,
  required bool confirm,
}) {
  if (confirm) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('二次确认'),
          content: Text('确定确认「${row.projectName} · ${row.periodLabel}」？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('确定确认'),
            ),
          ],
        );
      },
    );
  }
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Tag3DailyCommentDialog(row: row),
  );
}

class Tag3DailyCommentDialog extends StatefulWidget {
  const Tag3DailyCommentDialog({super.key, required this.row});

  final Tag3DailyRow row;

  @override
  State<Tag3DailyCommentDialog> createState() => _Tag3DailyCommentDialogState();
}

class _Tag3DailyCommentDialogState extends State<Tag3DailyCommentDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _secondStep = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _controller.text.trim();
    if (_secondStep) {
      return AlertDialog(
        title: const Text('二次确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确定提交「${widget.row.projectName} · ${widget.row.periodLabel}」的意见？',
            ),
            const SizedBox(height: 10),
            Text(
              '意见：$body',
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _secondStep = false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(body),
            child: const Text('确定提交'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text('意见 ${widget.row.projectName} · ${widget.row.periodLabel}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        maxLength: 512,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: '填写意见'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: body.isNotEmpty
              ? () => setState(() => _secondStep = true)
              : null,
          child: const Text('下一步'),
        ),
      ],
    );
  }
}

class Tag3DailyOpinionEntry extends StatelessWidget {
  const Tag3DailyOpinionEntry({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.accent,
              role: DunesColorRole.surface,
            ).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                DunesColors.accent,
                role: DunesColorRole.border,
              ).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '意见 $count',
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, DunesColors.accent),
                  context: context,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: DunesColors.resolve(context, DunesColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showTag3DailyOpinionList({
  required BuildContext context,
  required String title,
  required List<Tag3DailyComment> comments,
  List<Tag3DailyRow> rows = const [],
}) {
  final opinions = tag3DailyOpinionComments(comments);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · 意见',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(ctx, DunesColors.text),
                  context: ctx,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '只显示填写了意见的内容，确认记录不在这里。',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.resolve(ctx, DunesColors.text3),
                  context: ctx,
                ),
              ),
              const SizedBox(height: 12),
              if (opinions.isEmpty)
                Text(
                  '暂无意见',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.resolve(ctx, DunesColors.text3),
                    context: ctx,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: opinions.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final item = opinions[i];
                      final name = item.userName.trim().isEmpty
                          ? '同事'
                          : item.userName.trim();
                      final place = tag3DailyCommentPlace(item, rows);
                      final where = [
                        if (place.channel.isNotEmpty) '渠道 ${place.channel}',
                        if (place.project.isNotEmpty) '项目 ${place.project}',
                      ].join(' · ');
                      final cycle = tag3DailyOpinionCycleDay(item, rows);
                      final written = tag3DailyCommentTime(item.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            where.isEmpty ? name : where,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(ctx, DunesColors.text),
                              context: ctx,
                            ),
                          ),
                          if (cycle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '统计周期 $cycle',
                              style: DunesTypography.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.resolve(
                                  ctx,
                                  DunesColors.text2,
                                ),
                                context: ctx,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            written.isEmpty ? name : '$name · 填写于 $written',
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.resolve(
                                ctx,
                                DunesColors.text3,
                              ),
                              context: ctx,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.body.trim(),
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                              color: DunesColors.resolve(ctx, DunesColors.text),
                              context: ctx,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showTag3DailyCommentHistory({
  required BuildContext context,
  required Tag3DailyRow row,
  required List<Tag3DailyComment> comments,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${row.projectName} · 统计周期 ${tag3DailyRowCycleDay(row)} · 意见记录',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(ctx, DunesColors.text),
                  context: ctx,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '按提交时间查看，可看到是哪个人提的意见。',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.resolve(ctx, DunesColors.text3),
                  context: ctx,
                ),
              ),
              const SizedBox(height: 12),
              if (comments.isEmpty)
                Text(
                  '暂无意见',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.resolve(ctx, DunesColors.text3),
                    context: ctx,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: comments.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final item = comments[i];
                      final name = item.userName.trim().isEmpty
                          ? '同事'
                          : item.userName.trim();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name · ${item.kindLabel} · 填写于 ${tag3DailyCommentTime(item.createdAt)}',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(ctx, DunesColors.text),
                              context: ctx,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.displayBody,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                              color: DunesColors.resolve(ctx, DunesColors.text),
                              context: ctx,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
