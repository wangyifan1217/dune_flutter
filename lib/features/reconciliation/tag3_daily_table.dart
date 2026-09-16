import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'tag3_daily_models.dart';

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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1120),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(color: DunesColors.border.withValues(alpha: 0.7)),
            bottom: BorderSide(color: DunesColors.border.withValues(alpha: 0.7)),
          ),
          columnWidths: const {
            0: FixedColumnWidth(88),
            1: FixedColumnWidth(108),
            2: FixedColumnWidth(92),
            3: FixedColumnWidth(72),
            4: FixedColumnWidth(88),
            5: FixedColumnWidth(80),
            6: FixedColumnWidth(80),
            7: FixedColumnWidth(96),
            8: FixedColumnWidth(88),
            9: FixedColumnWidth(80),
            10: FixedColumnWidth(96),
            11: FixedColumnWidth(72),
            12: FixedColumnWidth(148),
            13: FixedColumnWidth(196),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF4F7F6)),
              children: [
                for (final label in const [
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
                  '操作',
                ])
                  _head(label),
              ],
            ),
            for (var i = 0; i < sorted.length; i++)
              _dataRow(sorted, i),
          ],
        ),
      ),
    );
  }

  TableRow _dataRow(List<Tag3DailyRow> sorted, int i) {
    final row = sorted[i];
    final showChannel = i == 0 || sorted[i - 1].channelCategoryL1Name != row.channelCategoryL1Name;
    final showProject = i == 0 || sorted[i - 1].rowKey != row.rowKey;
    return TableRow(
      children: [
        _cell(showChannel ? row.channelCategoryL1Name : ''),
        _tappable(
          showProject ? row.projectName : '',
          onTap: showProject && onProjectTap != null ? () => onProjectTap!(row) : null,
        ),
        _cell(row.periodLabel),
        _cell(row.paymentTerm),
        _cell(tag3DailyMoney(row.salesAmount), alignRight: true),
        _cell(tag3DailyMoney(row.writeOffAmount), alignRight: true),
        _cell(tag3DailyMoney(row.profitAmount), alignRight: true),
        _cell(tag3DailyMoney(row.cashFlowAmount), alignRight: true),
        _tappable(
          tag3DailyMoney(row.cashReceivableAmount),
          alignRight: true,
          onTap: onReceivableTap == null ? null : () => onReceivableTap!(row),
        ),
        _cell(tag3DailyMoney(row.cashPaidAmount), alignRight: true),
        _cell(tag3DailyMoney(row.cashReceivableDiff), alignRight: true),
        _cell(tag3DailyMoney(row.subsidyReceivableAmount), alignRight: true),
        _auditCell(row),
        _actionCell(row),
      ],
    );
  }

  Tag3DailyAssignee? _assigneeFor(Tag3DailyRow row) {
    final key = row.rowKey;
    for (final item in assignees) {
      if (item.rowKey == key) return item;
    }
    return null;
  }

  Widget _auditCell(Tag3DailyRow row) {
    final lanes = tag3DailyAuditLanes(
      assignee: _assigneeFor(row),
      comments: _commentsFor(row),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lanes.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Text(
              '${lanes[i].role} ${lanes[i].names} · ${lanes[i].statusLabel}',
              style: DunesTypography.sans(
                fontSize: 11.5,
                fontWeight: lanes[i].done ? FontWeight.w600 : FontWeight.w400,
                color: lanes[i].done ? DunesColors.green : DunesColors.text3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Tag3DailyComment> _commentsFor(Tag3DailyRow row) {
    return [for (final item in comments) if (item.matchesRow(row)) item];
  }

  Widget _actionCell(Tag3DailyRow row) {
    if (row.isMonthCumulative) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          '月累计',
          style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
        ),
      );
    }
    final busy = busyKeys.contains(row.actionId);
    final history = _commentsFor(row);
    final latest = history.isEmpty ? null : history.last;
    final mineConfirmed = myUserId > 0 &&
        history.any((item) => item.isConfirm && item.userId == myUserId);
    final showConfirm = row.showConfirmAction && !mineConfirmed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: busy || !row.showCommentAction || onComment == null
                      ? null
                      : () => onComment!(row),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DunesColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('意见'),
                ),
              ),
              if (showConfirm)
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: busy || onConfirm == null ? null : () => onConfirm!(row),
                    style: FilledButton.styleFrom(
                      backgroundColor: DunesColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(
                      busy ? '提交中…' : tag3DailyConfirmButtonLabel(row.canConfirmStage),
                    ),
                  ),
                ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: onViewComments == null ? null : () => onViewComments!(row),
              child: Text(
                '${history.length}条 · ${latest.userName.isEmpty ? '同事' : latest.userName} ${latest.kindLabel}',
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

  Widget _head(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: DunesColors.text2,
        ),
      ),
    );
  }

  Widget _cell(String text, {bool alignRight = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text),
      ),
    );
  }

  Widget _tappable(String text, {VoidCallback? onTap, bool alignRight = false}) {
    final child = _cell(text, alignRight: alignRight);
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
          mainAxisSize: MainAxisSize.min,
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
              style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
            if (data.items.isEmpty)
              Text(
                '暂无下钻明细',
                style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
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
                              DataCell(Text(province ? item.provinceName : item.statDate)),
                              DataCell(Text(province ? item.periodLabel : item.productName)),
                              DataCell(Text(tag3DailyMoney(item.salesAmount))),
                              DataCell(Text(tag3DailyMoney(item.writeOffAmount))),
                              DataCell(Text(tag3DailyMoney(item.profitAmount))),
                              DataCell(Text(tag3DailyPercent(item.profitRate))),
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
    final stageLabel = row.canConfirmStage == 'OPERATION' ? '运营' : '业务';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('二次确认'),
          content: Text(
            '确定以$stageLabel身份确认「${row.projectName} · ${row.periodLabel}」？',
          ),
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
  const Tag3DailyCommentDialog({
    super.key,
    required this.row,
  });

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
            Text('确定提交「${widget.row.projectName} · ${widget.row.periodLabel}」的意见？'),
            const SizedBox(height: 10),
            Text(
              '意见：$body',
              style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2),
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
        decoration: const InputDecoration(
          hintText: '填写意见',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: body.isNotEmpty ? () => setState(() => _secondStep = true) : null,
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
                style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 12),
              if (comments.isEmpty)
                Text(
                  '暂无意见',
                  style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: comments.length,
                    separatorBuilder: (context, index) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final item = comments[i];
                      final name = item.userName.trim().isEmpty ? '同事' : item.userName.trim();
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
