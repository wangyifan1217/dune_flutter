import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'recon_pinned_table.dart';
import 'tag2_entity_models.dart';
import 'tag3_daily_models.dart';

const _kHeaderH = 48.0;
const _kActionW = 148.0;
const _kRowMin = 64.0;
const _kGroupGap = 12.0;
const _kAmountW = 124.0;
const _kAuditW = 200.0;
const _kIdLabels = <String>['省份', '对方主体', '我方主体', '供应商'];
const _kIdWidths = <double>[108, 168, 168, 140];
const _kFillA = Color(0xFFF3F0F8);
const _kFillB = Color(0xFFFFFCF8);
const _kEdge = Color(0xFFD4CCE3);

class _AmountCol {
  const _AmountCol({required this.key, required this.label});

  final String key;
  final String label;
}

class _Band {
  const _Band({
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

class Tag2EntityTable extends StatelessWidget {
  const Tag2EntityTable({
    super.key,
    required this.rows,
    required this.comments,
    required this.busyKeys,
    required this.onDrill,
    required this.onConfirm,
    required this.onComment,
    this.onViewComments,
    this.onReject,
  });

  final List<Tag2EntityRow> rows;
  final List<Tag3DailyComment> comments;
  final Set<String> busyKeys;
  final void Function(Tag2EntityRow row, Tag2EntityAmount amount) onDrill;
  final ValueChanged<Tag2EntityRow> onConfirm;
  final ValueChanged<Tag2EntityRow> onComment;
  final ValueChanged<Tag2EntityRow>? onViewComments;
  final ValueChanged<Tag2EntityRow>? onReject;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '这一天没有你负责的主体。',
          style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
        ),
      );
    }
    final amounts = _amountColumns(rows);
    final dataWidth =
        _kIdWidths.fold<double>(0, (a, b) => a + b) +
        amounts.length * _kAmountW +
        _kAuditW;
    final bands = _bands(rows);
    final heights = [
      for (var i = 0; i < rows.length; i++) _rowHeight(rows[i], bands[i]),
    ];
    final pinned = ReconPinnedTable(
      headerHeight: _kHeaderH,
      dataWidth: dataWidth,
      dataHeader: Row(
        children: [
          for (var c = 0; c < _kIdLabels.length; c++)
            _head(_kIdLabels[c], _kIdWidths[c]),
          for (final col in amounts) _head(col.label, _kAmountW),
          _head('审核记录', _kAuditW),
        ],
      ),
      trailingHeader: _actionHeader(child: _head('操作', _kActionW)),
      rowCount: rows.length,
      rowHeight: (i) => heights[i],
      dataRowBuilder: (context, i) =>
          _dataRow(rows[i], amounts, heights[i], bands[i]),
      trailingRowBuilder: (context, i) => _bandBox(
        band: bands[i],
        height: heights[i],
        action: true,
        child: SizedBox(width: _kActionW, child: _actionCell(rows[i])),
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

  List<_AmountCol> _amountColumns(List<Tag2EntityRow> source) {
    final seen = <String>{};
    final out = <_AmountCol>[];
    for (final row in source) {
      for (final amount in row.amounts) {
        final key = amount.key.trim();
        if (key.isEmpty || !seen.add(key)) continue;
        final label = amount.label.trim().isEmpty ? key : amount.label.trim();
        out.add(_AmountCol(key: key, label: label));
      }
    }
    return out;
  }

  String _groupOf(Tag2EntityRow row) {
    if (row.isTotal) return '\u0000${row.rowKey}';
    final province = row.provinceName.trim();
    return province.isEmpty ? row.rowKey : province;
  }

  List<_Band> _bands(List<Tag2EntityRow> source) {
    final out = <_Band>[];
    var group = 0;
    for (var i = 0; i < source.length; i++) {
      if (i > 0 && _groupOf(source[i]) != _groupOf(source[i - 1])) group++;
      final total = source[i].isTotal;
      out.add(
        _Band(
          fill: total
              ? const Color(0xFFF7F8FA)
              : (group.isEven ? _kFillA : _kFillB),
          accent: group.isEven
              ? const Color(0xFF8B7BA8)
              : const Color(0xFF2F5D62),
          start: i == 0 || _groupOf(source[i]) != _groupOf(source[i - 1]),
          end:
              i == source.length - 1 ||
              _groupOf(source[i]) != _groupOf(source[i + 1]),
        ),
      );
    }
    return out;
  }

  Widget _dataRow(
    Tag2EntityRow row,
    List<_AmountCol> amounts,
    double height,
    _Band band,
  ) {
    final contentHeight = height - (band.end ? _kGroupGap : 0);
    final values = [
      row.provinceName,
      row.counterpartyName,
      row.ourEntityName,
      row.supplierName,
    ];
    return _bandBox(
      band: band,
      height: height,
      child: Row(
        children: [
          for (var c = 0; c < values.length; c++)
            c == 0
                ? _mark(
                    band,
                    _cell(
                      values[c],
                      _kIdWidths[c],
                      contentHeight,
                      bold: row.isTotal,
                    ),
                  )
                : _cell(
                    values[c],
                    _kIdWidths[c],
                    contentHeight,
                    bold: row.isTotal,
                  ),
          for (final col in amounts) _amountCell(row, col, contentHeight),
          _auditCell(row, contentHeight),
        ],
      ),
    );
  }

  Widget _amountCell(Tag2EntityRow row, _AmountCol col, double height) {
    Tag2EntityAmount? picked;
    for (final item in row.amounts) {
      if (item.key == col.key) {
        picked = item;
        break;
      }
    }
    final amount = picked;
    final text = (amount?.display ?? '').trim();
    if (amount != null && amount.drill && !row.isTotal) {
      final hit = amount;
      return _tappable(
        text.isEmpty ? '-' : text,
        _kAmountW,
        height,
        alignRight: true,
        maxLines: 1,
        bold: row.isTotal,
        onTap: () => onDrill(row, hit),
      );
    }
    return _tappable(
      text.isEmpty ? '-' : text,
      _kAmountW,
      height,
      alignRight: true,
      maxLines: 1,
      bold: row.isTotal,
    );
  }

  List<Tag3DailyComment> _commentsFor(Tag2EntityRow row) {
    return [
      for (final item in comments)
        if (item.rowKey == row.rowKey) item,
    ];
  }

  List<Tag3DailyAuditLane> _lanes(Tag2EntityRow row) {
    if (row.isTotal) return const [];
    final history = _commentsFor(row);
    final status = row.confirmationStatus;
    final businessDone = status.isNotEmpty
        ? status == 'WAIT_OPERATION' || status == 'ALL_CONFIRMED'
        : history.any((item) => item.isConfirm && item.stage == 'BUSINESS');
    final operationDone = status.isNotEmpty
        ? status == 'ALL_CONFIRMED'
        : history.any((item) => item.isConfirm && item.stage == 'OPERATION');
    String historyNames(String stage) {
      final names = <String>{};
      for (final item in history) {
        final name = item.userName.trim();
        if (item.isConfirm && item.stage == stage && name.isNotEmpty) {
          names.add(name);
        }
      }
      return names.join('、');
    }

    final businessNames = row.businessBy.trim().isNotEmpty
        ? row.businessBy
        : historyNames('BUSINESS').isNotEmpty
        ? historyNames('BUSINESS')
        : (status == 'WAIT_BUSINESS' ? row.currentHandlers : '');
    final operationNames = row.operationBy.trim().isNotEmpty
        ? row.operationBy
        : historyNames('OPERATION').isNotEmpty
        ? historyNames('OPERATION')
        : (status == 'WAIT_OPERATION' ? row.currentHandlers : '');
    return [
      Tag3DailyAuditLane(role: '业务', names: businessNames, done: businessDone),
      Tag3DailyAuditLane(
        role: '运营',
        names: operationNames,
        done: operationDone,
      ),
    ];
  }

  double _rowHeight(Tag2EntityRow row, _Band band) {
    var height = _kRowMin;
    final texts = [
      row.provinceName,
      row.counterpartyName,
      row.ourEntityName,
      row.supplierName,
    ];
    for (var c = 0; c < texts.length; c++) {
      height = math.max(height, 28 + _measure(texts[c], _kIdWidths[c]));
    }
    height = math.max(height, math.max(_auditHeight(row), _actionHeight(row)));
    if (band.end) height += _kGroupGap;
    return height;
  }

  double _auditHeight(Tag2EntityRow row) {
    final lanes = _lanes(row);
    if (lanes.isEmpty) return 0;
    return 20 + lanes.length * 26 + (lanes.length - 1) * 8;
  }

  double _actionHeight(Tag2EntityRow row) {
    if (row.isTotal) return _kRowMin;
    return (_commentsFor(row).isEmpty ? 68.0 : 108.0) +
        (row.showReject ? 38.0 : 0.0);
  }

  double _measure(String text, double colWidth) {
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

  Widget _auditCell(Tag2EntityRow row, double height) {
    final lanes = _lanes(row);
    return SizedBox(
      width: _kAuditW,
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
              _auditLane(lanes[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _auditLane(Tag3DailyAuditLane lane) {
    final color = lane.done ? DunesColors.green : DunesColors.amber;
    return Row(
      children: [
        Icon(
          lane.done ? Icons.check_circle : Icons.schedule,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${lane.role} ${lane.names}'.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: lane.done ? DunesColors.green : DunesColors.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionCell(Tag2EntityRow row) {
    if (row.isTotal) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '合计',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
        ),
      );
    }
    final busy = busyKeys.contains(row.rowKey);
    final history = _commentsFor(row);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (history.isNotEmpty) ...[
            _commentEntry(row, history),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              if (row.showComment)
                Expanded(
                  child: _chip(
                    label: '意见',
                    filled: false,
                    enabled: !busy,
                    onTap: () => onComment(row),
                  ),
                ),
              if (row.showComment && row.showConfirm) const SizedBox(width: 6),
              if (row.showConfirm)
                Expanded(
                  child: _chip(
                    label: busy ? '提交中' : '确认',
                    filled: true,
                    enabled: !busy,
                    onTap: () => onConfirm(row),
                  ),
                )
              else if (row.confirmationStatus == 'ALL_CONFIRMED')
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
          if (row.showReject) ...[
            const SizedBox(height: 5),
            SizedBox(
              height: 28,
              child: TextButton(
                onPressed: busy ? null : () => onReject?.call(row),
                style: TextButton.styleFrom(
                  foregroundColor: DunesColors.coral,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('驳回并退回业务'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _commentEntry(Tag2EntityRow row, List<Tag3DailyComment> history) {
    final ordered = [...history]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final latest = ordered.last;
    final name = latest.userName.trim().isEmpty ? '同事' : latest.userName.trim();
    final preview = latest.displayBody.trim();
    final count = history.length;
    final text = latest.isReject
        ? '$name 驳回：$preview'
        : preview.isEmpty
        ? '$count条意见'
        : '$name：$preview';
    return InkWell(
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
                  color: DunesColors.accent,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: DunesColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool filled,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final color = enabled ? DunesColors.accent : DunesColors.text3;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        height: 34,
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
    );
  }

  Widget _head(String text, double width) {
    return SizedBox(
      width: width,
      height: _kHeaderH,
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
    bool bold = false,
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
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
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
    bool bold = false,
    int maxLines = 2,
  }) {
    final child = _cell(
      text,
      width,
      height,
      alignRight: alignRight,
      bold: bold,
      maxLines: maxLines,
    );
    if (onTap == null || text.trim().isEmpty || text.trim() == '-') {
      return child;
    }
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

  Widget _mark(_Band band, Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: band.accent, width: 3)),
      ),
      child: child,
    );
  }

  Widget _bandBox({
    required _Band band,
    required double height,
    required Widget child,
    bool action = false,
  }) {
    final gap = band.end ? _kGroupGap : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: band.fill,
          border: Border(
            left: action
                ? const BorderSide(color: Color(0xFFD9D4CC), width: 0.5)
                : BorderSide.none,
            top: band.start ? const BorderSide(color: _kEdge) : BorderSide.none,
            bottom: BorderSide(
              color: band.end ? _kEdge : const Color(0x80E6E1D6),
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

  Widget _actionHeader({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F8),
        border: Border(left: BorderSide(color: DunesColors.border, width: 0.5)),
      ),
      child: child,
    );
  }
}

Future<String?> showTag2EntityActionDialog({
  required BuildContext context,
  required Tag2EntityRow row,
  required bool confirm,
  bool reject = false,
}) {
  if (confirm) {
    final who = row.canConfirmStage == 'OPERATION' ? '运营' : '业务';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('二次确认'),
          content: Text('确定以$who确认「${row.title}」？'),
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
  if (reject) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _Tag2RejectDialog(title: row.title),
    );
  }
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Tag2CommentDialog(title: row.title),
  );
}

class _Tag2RejectDialog extends StatefulWidget {
  const _Tag2RejectDialog({required this.title});

  final String title;

  @override
  State<_Tag2RejectDialog> createState() => _Tag2RejectDialogState();
}

class _Tag2RejectDialogState extends State<_Tag2RejectDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remark = _controller.text.trim();
    final tooLong = remark.runes.length > 512;
    return AlertDialog(
      title: const Text('驳回到业务确认'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '请填写驳回原因（必填，最多 512 字）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: remark.isEmpty || tooLong
              ? null
              : () => Navigator.of(context).pop(remark),
          child: const Text('确认驳回'),
        ),
      ],
    );
  }
}

class _Tag2CommentDialog extends StatefulWidget {
  const _Tag2CommentDialog({required this.title});

  final String title;

  @override
  State<_Tag2CommentDialog> createState() => _Tag2CommentDialogState();
}

class _Tag2CommentDialogState extends State<_Tag2CommentDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _controller.text.trim();
    final tooLong = body.runes.length > 512;
    return AlertDialog(
      title: const Text('提意见'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '1～512 字，不改变确认状态',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: body.isEmpty || tooLong
              ? null
              : () => Navigator.of(context).pop(body),
          child: const Text('提交'),
        ),
      ],
    );
  }
}

Future<void> showTag2EntityDrilldown({
  required BuildContext context,
  required String title,
  required Tag2EntityDrilldown data,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final rows = data.rows;
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        '没有明细',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          color: DunesColors.text3,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final lines = <Widget>[];
                        for (final entry in row.entries) {
                          final label =
                              tag2EntityDrillLabels[entry.key] ?? entry.key;
                          final value = '${entry.value ?? ''}'.trim();
                          if (value.isEmpty || value == 'null') continue;
                          lines.add(
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '$label：$value',
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          );
                        }
                        return Material(
                          color: const Color(0xFFF5F6F8),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: lines,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

String _tag2CommentPlace(Tag3DailyComment comment, List<Tag2EntityRow> rows) {
  for (final row in rows) {
    if (row.rowKey == comment.rowKey) return row.title;
  }
  final name = comment.projectName.trim();
  return name.isEmpty ? comment.rowKey : name;
}

Future<void> showTag2EntityOpinionList({
  required BuildContext context,
  required String title,
  required List<Tag3DailyComment> comments,
  List<Tag2EntityRow> rows = const [],
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
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '只显示填写了意见的内容，确认记录不在这里。',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
              const SizedBox(height: 12),
              if (opinions.isEmpty)
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
                    itemCount: opinions.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final item = opinions[i];
                      final name = item.userName.trim().isEmpty
                          ? '同事'
                          : item.userName.trim();
                      final where = _tag2CommentPlace(item, rows);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            where,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$name · ${tag3DailyCommentTime(item.createdAt)}',
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.text3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.body.trim(),
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

Future<void> showTag2EntityCommentHistory({
  required BuildContext context,
  required Tag2EntityRow row,
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
                '${row.title} · 意见记录',
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
