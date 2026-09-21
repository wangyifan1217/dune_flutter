import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'recon_pinned_table.dart';
import 'tag3_daily_models.dart';

const _kTag3DailyHeaderH = 40.0;
const _kTag3DailyActionWidth = 128.0;
const _kTag3DailyDataColWidths = <double>[
  88,
  108,
  92,
  72,
  88,
  80,
  80,
  96,
  88,
  80,
  96,
  72,
  148,
];
const _kTag3DailyDataWidth = 1188.0;
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
const _kTag3DailyRowLine = Border(bottom: BorderSide(color: Color(0xB3DAD5C7)));

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
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
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
    final pinned = ReconPinnedTable(
      headerHeight: _kTag3DailyHeaderH,
      dataWidth: _kTag3DailyDataWidth,
      dataHeader: Row(
        children: [
          for (var c = 0; c < _kTag3DailyDataLabels.length; c++)
            _head(_kTag3DailyDataLabels[c], _kTag3DailyDataColWidths[c]),
        ],
      ),
      trailingHeader: _actionChrome(child: _head('操作', _kTag3DailyActionWidth)),
      rowCount: sorted.length,
      rowHeight: (i) => heights[i],
      dataRowBuilder: (context, i) => _dataRow(sorted, i, heights[i]),
      trailingRowBuilder: (context, i) => _actionChrome(
        child: DecoratedBox(
          decoration: const BoxDecoration(border: _kTag3DailyRowLine),
          child: SizedBox(
            width: _kTag3DailyActionWidth,
            height: heights[i],
            child: _actionCell(sorted[i]),
          ),
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

  Widget _dataRow(List<Tag3DailyRow> sorted, int i, double height) {
    final row = sorted[i];
    final showChannel =
        i == 0 ||
        sorted[i - 1].channelCategoryL1Name != row.channelCategoryL1Name;
    final showProject = i == 0 || sorted[i - 1].rowKey != row.rowKey;
    return DecoratedBox(
      decoration: const BoxDecoration(border: _kTag3DailyRowLine),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            _cell(
              showChannel ? row.channelCategoryL1Name : '',
              _kTag3DailyDataColWidths[0],
              height,
            ),
            _tappable(
              showProject ? row.projectName : '',
              _kTag3DailyDataColWidths[1],
              height,
              onTap: showProject && onProjectTap != null
                  ? () => onProjectTap!(row)
                  : null,
            ),
            _cell(row.periodLabel, _kTag3DailyDataColWidths[2], height),
            _cell(row.paymentTerm, _kTag3DailyDataColWidths[3], height),
            _cell(
              tag3DailyMoney(row.salesAmount),
              _kTag3DailyDataColWidths[4],
              height,
              alignRight: true,
            ),
            _cell(
              tag3DailyMoney(row.writeOffAmount),
              _kTag3DailyDataColWidths[5],
              height,
              alignRight: true,
            ),
            _cell(
              tag3DailyMoney(row.profitAmount),
              _kTag3DailyDataColWidths[6],
              height,
              alignRight: true,
            ),
            _cell(
              tag3DailyMoney(row.cashFlowAmount),
              _kTag3DailyDataColWidths[7],
              height,
              alignRight: true,
            ),
            _tappable(
              tag3DailyMoney(row.cashReceivableAmount),
              _kTag3DailyDataColWidths[8],
              height,
              alignRight: true,
              onTap: onReceivableTap == null
                  ? null
                  : () => onReceivableTap!(row),
            ),
            _cell(
              tag3DailyMoney(row.cashPaidAmount),
              _kTag3DailyDataColWidths[9],
              height,
              alignRight: true,
            ),
            _cell(
              tag3DailyMoney(row.cashReceivableDiff),
              _kTag3DailyDataColWidths[10],
              height,
              alignRight: true,
            ),
            _cell(
              tag3DailyMoney(row.subsidyReceivableAmount),
              _kTag3DailyDataColWidths[11],
              height,
              alignRight: true,
            ),
            _auditCell(row, _kTag3DailyDataColWidths[12], height),
          ],
        ),
      ),
    );
  }

  Widget _actionChrome({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F8),
        border: Border(left: BorderSide(color: DunesColors.border, width: 0.5)),
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
    var height = 44.0;
    if (showChannel) {
      height = math.max(
        height,
        20 +
            _measureText(
              row.channelCategoryL1Name,
              _kTag3DailyDataColWidths[0],
            ),
      );
    }
    if (showProject) {
      height = math.max(
        height,
        20 + _measureText(row.projectName, _kTag3DailyDataColWidths[1]),
      );
    }
    return math.max(height, math.max(_auditHeight(row), _actionHeight(row)));
  }

  double _actionHeight(Tag3DailyRow row) {
    if (row.isMonthCumulative) return 44;
    return _commentsFor(row).isEmpty ? 48.0 : 68.0;
  }

  double _auditHeight(Tag3DailyRow row) {
    final lanes = tag3DailyAuditLanes(
      assignee: _assigneeFor(row),
      comments: _commentsFor(row),
    );
    var height = 20.0;
    if (row.confirmationStatusLabel.trim().isNotEmpty) {
      height += 22;
    }
    if (lanes.isNotEmpty) {
      height += lanes.length * 18 + (lanes.length - 1) * 4;
    }
    return height;
  }

  double _measureText(String text, double colWidth) {
    if (text.trim().isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (colWidth - 16).clamp(24.0, colWidth));
    return painter.height;
  }

  Widget _auditCell(Tag3DailyRow row, double width, double height) {
    final lanes = tag3DailyAuditLanes(
      assignee: _assigneeFor(row),
      comments: _commentsFor(row),
    );
    final statusLabel = row.confirmationStatusLabel.trim();
    final statusColor = switch (row.confirmationStatus) {
      'ALL_CONFIRMED' || 'CONFIRMED' => DunesColors.green,
      'WAIT_OPERATION' || 'WAIT_BUSINESS' => DunesColors.amber,
      _ => DunesColors.text2,
    };
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusLabel.isNotEmpty) ...[
              Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 4),
            ],
            for (var i = 0; i < lanes.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              Text(
                '${lanes[i].role} ${lanes[i].names} · ${lanes[i].statusLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 11.5,
                  fontWeight: lanes[i].done ? FontWeight.w600 : FontWeight.w400,
                  color: lanes[i].done ? DunesColors.green : DunesColors.text3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionCell(Tag3DailyRow row) {
    if (row.isMonthCumulative) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '月累计',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (showComment)
                Expanded(
                  child: _actionChip(
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
                      color: DunesColors.green,
                    ),
                  ),
                ),
            ],
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onViewComments == null ? null : () => onViewComments!(row),
              child: Text(
                '${history.length}条记录',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 11.5,
                  color: DunesColors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required bool filled,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    final color = enabled ? DunesColors.accent : DunesColors.text3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          height: 32,
          decoration: BoxDecoration(
            color: filled
                ? (enabled
                      ? DunesColors.accent
                      : DunesColors.accent.withValues(alpha: 0.35))
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(String text, double width) {
    return SizedBox(
      width: width,
      height: _kTag3DailyHeaderH,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    String text,
    double width,
    double height, {
    bool alignRight = false,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: DunesTypography.sans(
              fontSize: 12.5,
              color: DunesColors.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tappable(
    String text,
    double width,
    double height, {
    VoidCallback? onTap,
    bool alignRight = false,
  }) {
    final child = _cell(text, width, height, alignRight: alignRight);
    if (onTap == null || text.trim().isEmpty) return child;
    return InkWell(
      onTap: onTap,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          color: DunesColors.accent,
          decoration: TextDecoration.underline,
          decorationColor: DunesColors.accent,
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
                color: DunesColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '销售额 ${tag3DailyMoney(data.totalSales)}  ·  核销 ${tag3DailyMoney(data.totalWriteOff)}  ·  利润 ${tag3DailyMoney(data.totalProfit)}',
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 12),
            if (data.items.isEmpty)
              Text(
                '暂无下钻明细',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
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
                color: DunesColors.text2,
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
                '${row.projectName} · ${row.periodLabel} · 意见记录',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '按提交时间查看，可看到是哪个人提的意见。',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
              const SizedBox(height: 12),
              if (comments.isEmpty)
                Text(
                  '暂无意见',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
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
                            '$name · ${item.kindLabel} · ${tag3DailyCommentTime(item.createdAt)}',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.displayBody,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              color: DunesColors.text2,
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
