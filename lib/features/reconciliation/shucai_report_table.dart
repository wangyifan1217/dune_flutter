import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import 'recon_audit_record.dart';
import 'recon_pinned_table.dart';
import 'reconciliation_shucai_models.dart';

class _RowNote {
  const _RowNote({
    required this.label,
    required this.text,
    required this.color,
    required this.background,
  });

  final String label;
  final String text;
  final Color color;
  final Color background;
}

/// 明细表：左侧可固定操作列，右侧列超出宽度时可左右滑（触控 / 鼠标拖 / 滚轮）。
class ShucaiReportTable extends StatefulWidget {
  const ShucaiReportTable({
    super.key,
    required this.report,
    this.compact = false,
    this.showRowActions = false,
    this.showBatchSelect = false,
    this.showConfirmAction = true,
    this.showPrevious = false,
    this.rowActionsLocked = false,
    this.selectedRowKeys = const {},
    this.decisions = const {},
    this.previous = const {},
    this.acks = const [],
    this.visibleSteps = reconAuditChainSteps,
    this.avatarService,
    this.onToggleRow,
    this.onToggleSelectAll,
    this.onConfirmRow,
    this.onRejectRow,
  });

  final ShucaiReport report;
  final bool compact;
  final bool showRowActions;
  final bool showBatchSelect;
  final bool showConfirmAction;
  final bool showPrevious;
  final bool rowActionsLocked;
  final Set<String> selectedRowKeys;
  final Map<String, ReconRowDecision> decisions;
  final Map<String, List<ReconRowReviewer>> previous;
  final List<ReconPerson> acks;
  final List<String> visibleSteps;
  final ConversationService? avatarService;
  final ValueChanged<String>? onToggleRow;
  final VoidCallback? onToggleSelectAll;
  final ValueChanged<String>? onConfirmRow;
  final ValueChanged<String>? onRejectRow;

  @override
  State<ShucaiReportTable> createState() => _ShucaiReportTableState();
}

class _ShucaiReportTableState extends State<ShucaiReportTable> {
  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    if (report.columns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '暂无列定义',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
        ),
      );
    }
    if (report.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '当日无明细',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
        ),
      );
    }

    final compact = widget.compact;
    final fontSize = compact ? 11.0 : 12.0;
    final headerSize = compact ? 11.0 : 12.0;
    final nameMin = compact ? 200.0 : 228.0;
    final nameMax = compact ? 300.0 : 340.0;
    final numW = compact ? 120.0 : 132.0;
    final widths = <double>[
      for (var i = 0; i < report.columns.length; i++)
        shucaiIsNameColumn(report.columns[i])
            ? _nameColumnWidth(
                report,
                report.columns[i],
                fontSize: fontSize,
                headerSize: headerSize,
                minWidth: nameMin,
                maxWidth: nameMax,
              )
            : (i == 0 ? (compact ? 108.0 : 120.0) : numW),
    ];
    final totalWidth = widths.fold<double>(0, (a, b) => a + b);
    final baseRowH = compact ? 36.0 : 40.0;
    final headerH = compact ? 40.0 : 44.0;
    final heights = [
      for (var i = 0; i < report.rows.length; i++)
        _rowHeight(report, i, widths, fontSize, baseRowH),
    ];
    final notes = [
      for (var i = 0; i < report.rows.length; i++) _notesFor(report, i),
    ];
    final noteHeights = [
      for (final item in notes) _noteHeight(item),
    ];
    final actionW = widget.showRowActions
        ? (widget.showConfirmAction
              ? (widget.showBatchSelect
                    ? (compact ? 128.0 : 136.0)
                    : (compact ? 96.0 : 108.0))
              : (compact ? 72.0 : 80.0))
        : 0.0;
    final steps = widget.visibleSteps.isEmpty
        ? reconAuditChainSteps
        : widget.visibleSteps;
    final dataHeader = Row(
      children: [
        for (var c = 0; c < report.columns.length; c++)
          _cell(
            report.columns[c].label,
            width: widths[c],
            fontSize: headerSize,
            header: true,
            tooltip: report.columns[c].tip,
          ),
      ],
    );
    final dataBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < report.rows.length; i++) ...[
          _row(
            height: heights[i],
            color: _rowColor(report, i),
            children: [
              for (var c = 0; c < report.columns.length; c++)
                _cell(
                  _display(report, i, c),
                  width: widths[c],
                  fontSize: fontSize,
                  alignEnd: c > 0 && !shucaiIsNameColumn(report.columns[c]),
                  bold: shucaiIsSummaryRow(report.rows[i]),
                  wrap: shucaiIsNameColumn(report.columns[c]),
                  tooltip: shucaiMergedBlank(report, i, c)
                      ? ''
                      : shucaiNestedAmountTooltip(
                          shucaiCellRaw(report.rows[i], report.columns[c]),
                        ),
                ),
            ],
          ),
          if (notes[i].isNotEmpty)
            _noteRow(
              notes: notes[i],
              height: noteHeights[i],
              width: totalWidth,
            ),
        ],
      ],
    );
    Widget auditLane({required bool header, required bool body}) {
      return ReconFrozenAuditLane(
        compact: compact,
        headerH: headerH,
        fontSize: fontSize,
        rowCount: report.rows.length,
        heights: heights,
        noteHeights: noteHeights,
        rowColorAt: (i) => _rowColor(report, i),
        noteColorAt: (i) => notes[i].isEmpty ? null : notes[i].first.background,
        reviewersAt: (i) => _reviewersFor(report, _rowKey(report, i)),
        rowTitleAt: (i) => shucaiRowDisplayName(report.rows[i]),
        isSummaryAt: (i) => shucaiIsSummaryRow(report.rows[i]),
        avatarService: widget.avatarService,
        visibleSteps: steps,
        includeHeader: header,
        includeBody: body,
      );
    }

    final pinned = ReconPinnedTable(
      headerHeight: headerH,
      dataWidth: totalWidth,
      leadingHeader: widget.showRowActions
          ? _frozenActionColumn(
              report: report,
              heights: heights,
              noteHeights: noteHeights,
              notes: notes,
              headerH: headerH,
              width: actionW,
              fontSize: fontSize,
              includeHeader: true,
              includeBody: false,
            )
          : null,
      leadingBody: widget.showRowActions
          ? _frozenActionColumn(
              report: report,
              heights: heights,
              noteHeights: noteHeights,
              notes: notes,
              headerH: headerH,
              width: actionW,
              fontSize: fontSize,
              includeHeader: false,
              includeBody: true,
            )
          : null,
      trailingHeader: widget.showPrevious
          ? auditLane(header: true, body: false)
          : null,
      trailingBody: widget.showPrevious
          ? auditLane(header: false, body: true)
          : null,
      dataHeader: dataHeader,
      dataBody: dataBody,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final child = DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: pinned,
          ),
        );
        if (constraints.hasBoundedHeight) {
          return SizedBox.expand(child: child);
        }
        return child;
      },
    );
  }

  String _rowKey(ShucaiReport report, int index) {
    final row = report.rows[index];
    if (shucaiIsSummaryRow(row)) return '';
    return shucaiRowKey(row, index);
  }

  List<ReconRowReviewer> _reviewersFor(ShucaiReport report, String key) {
    if (key.isEmpty) return const [];
    return reconFilterReviewersForSteps(
      reconReviewersWithCardAcks(
        reviewers: reconReviewersForRow(
          previous: widget.previous,
          tab: report.tab,
          rowKey: key,
        ),
        acks: widget.visibleSteps.contains(reconChainL2)
            ? widget.acks
            : const [],
      ),
      widget.visibleSteps,
    );
  }

  Color _rowColor(ShucaiReport report, int index) {
    final key = _rowKey(report, index);
    if (key.isNotEmpty && widget.selectedRowKeys.contains(key)) {
      return const Color(0xFFF7F3FC);
    }
    if (_isTotalLike(report.rows[index])) return const Color(0xFFF3F6F5);
    final reviewers = _reviewersFor(report, key);
    if (reviewers.any((item) => item.rejected)) return const Color(0xFFFBEDEC);
    return Colors.white;
  }

  List<_RowNote> _notesFor(ShucaiReport report, int index) {
    final key = _rowKey(report, index);
    if (key.isEmpty) return const [];
    final notes = <_RowNote>[];
    for (final previous in _reviewersFor(report, key)) {
      final layer = reconChainStepLabel(previous.chainStepKey);
      if (previous.rejected && previous.reason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '$layer反驳',
            text: previous.reason.trim(),
            color: DunesColors.coral,
            background: DunesColors.coralSoft,
          ),
        );
      } else if (previous.rejectReason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '$layer驳回历史',
            text: previous.rejectReason.trim(),
            color: DunesColors.coral,
            background: DunesColors.coralSoft,
          ),
        );
      }
    }
    final mine = widget.decisions[key];
    if (mine != null) {
      if (mine.rejected && mine.reason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '你的反驳',
            text: mine.reason.trim(),
            color: DunesColors.coral,
            background: DunesColors.coralSoft,
          ),
        );
      } else if (mine.rejectReason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '驳回历史',
            text: mine.rejectReason.trim(),
            color: DunesColors.coral,
            background: DunesColors.coralSoft,
          ),
        );
      }
      if (mine.reconfirmed && mine.reason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '复核说明',
            text: mine.reason.trim(),
            color: DunesColors.green,
            background: DunesColors.greenSoft,
          ),
        );
      }
    }
    return notes;
  }

  double _noteHeight(List<_RowNote> notes) {
    if (notes.isEmpty) return 0;
    return 8 + notes.length * 22.0;
  }

  Widget _frozenActionColumn({
    required ShucaiReport report,
    required List<double> heights,
    required List<double> noteHeights,
    required List<List<_RowNote>> notes,
    required double headerH,
    required double width,
    required double fontSize,
    bool includeHeader = true,
    bool includeBody = true,
  }) {
    final keys = [
      for (var i = 0; i < report.rows.length; i++)
        if (!shucaiIsSummaryRow(report.rows[i])) shucaiRowKey(report.rows[i], i),
    ];
    final selected = widget.selectedRowKeys;
    final allSelected =
        keys.isNotEmpty && keys.every(selected.contains);
    final someSelected = keys.any(selected.contains);
    final locked = widget.rowActionsLocked;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            if (includeHeader)
              SizedBox(
                height: headerH,
                child: ColoredBox(
                  color: const Color(0xFFF6F7F9),
                  child: Row(
                    children: [
                      if (!locked && widget.showBatchSelect)
                        Checkbox(
                          value: keys.isEmpty
                              ? false
                              : (allSelected
                                    ? true
                                    : (someSelected ? null : false)),
                          tristate: true,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeColor: DunesColors.brandPurple,
                          onChanged: widget.onToggleSelectAll == null
                              ? null
                              : (_) => widget.onToggleSelectAll!(),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '操作',
                          style: DunesTypography.sans(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (includeBody)
              for (var i = 0; i < report.rows.length; i++) ...[
                _actionRow(
                  report: report,
                  index: i,
                  height: heights[i],
                  width: width,
                  fontSize: fontSize,
                  locked: locked,
                ),
                if (notes[i].isNotEmpty)
                  _noteSpacer(
                    height: noteHeights[i],
                    width: width,
                    color: notes[i].first.background,
                  ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _actionRow({
    required ShucaiReport report,
    required int index,
    required double height,
    required double width,
    required double fontSize,
    required bool locked,
  }) {
    final row = report.rows[index];
    final summary = shucaiIsSummaryRow(row);
    final key = summary ? '' : shucaiRowKey(row, index);
    final selected = key.isNotEmpty && widget.selectedRowKeys.contains(key);
    final decision = widget.decisions[key];
    return _row(
      height: height,
      color: selected
          ? const Color(0xFFF7F3FC)
          : (_isTotalLike(row) ? const Color(0xFFF3F6F5) : Colors.white),
      children: [
        SizedBox(
          width: width,
          child: summary
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    if (!locked && widget.showBatchSelect)
                      Checkbox(
                        value: selected,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: DunesColors.brandPurple,
                        onChanged: widget.onToggleRow == null
                            ? null
                            : (_) => widget.onToggleRow!(key),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: locked
                          ? _decisionLabel(decision, fontSize)
                          : Row(
                              children: [
                                if (widget.showConfirmAction ||
                                    decision?.rejected == true) ...[
                                  _miniAction(
                                    label: decision?.rejected == true
                                        ? '复核'
                                        : '确认',
                                    active: decision?.confirmed == true,
                                    color: DunesColors.green,
                                    onTap: widget.onConfirmRow == null
                                        ? null
                                        : () => widget.onConfirmRow!(key),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                _miniAction(
                                  label: '反驳',
                                  active: decision?.rejected == true,
                                  color: DunesColors.coral,
                                  onTap: widget.onRejectRow == null
                                      ? null
                                      : () => widget.onRejectRow!(key),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _decisionLabel(ReconRowDecision? decision, double fontSize) {
    if (decision == null) {
      return Text(
        '未处理',
        style: DunesTypography.sans(fontSize: fontSize, color: DunesColors.text3),
      );
    }
    return Text(
      decision.rejected
          ? '已驳回'
          : (decision.reconfirmed ? '已复核' : '已确认'),
      style: DunesTypography.sans(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: decision.rejected ? DunesColors.coral : DunesColors.green,
      ),
    );
  }

  Widget _miniAction({
    required String label,
    required bool active,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.55)
                  : DunesColors.borderSoft,
            ),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? color : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _noteRow({
    required List<_RowNote> notes,
    required double height,
    required double width,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: notes.first.background,
        border: const Border(
          bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: height,
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final note in notes)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${note.label}  ',
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: note.color,
                        ),
                      ),
                      TextSpan(
                        text: note.text,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteSpacer({
    required double height,
    required double width,
    required Color color,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(height: height, width: width),
    );
  }

  Widget _row({
    required double height,
    required Color color,
    required List<Widget> children,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: height,
        child: Row(children: children),
      ),
    );
  }

  String _display(
    ShucaiReport report,
    int rowIndex,
    int colIndex,
  ) {
    if (shucaiMergedBlank(report, rowIndex, colIndex)) return '';
    final col = report.columns[colIndex];
    final row = report.rows[rowIndex];
    if (shucaiIsNameColumn(col)) {
      final raw = row[col.field] ?? row['provinceName'] ?? row['detailName'];
      final text = (raw ?? '').toString().trim();
      return text.isEmpty ? '—' : text;
    }
    return shucaiCellText(shucaiCellRaw(row, col), preferText: col.text);
  }

  double _nameColumnWidth(
    ShucaiReport report,
    ShucaiColumn col, {
    required double fontSize,
    required double headerSize,
    required double minWidth,
    required double maxWidth,
  }) {
    var widest = _measure(col.label, headerSize, bold: true);
    final colIndex = report.columns.indexOf(col);
    for (var i = 0; i < report.rows.length; i++) {
      final text = _display(report, i, colIndex < 0 ? 0 : colIndex);
      final w = _measure(text, fontSize, bold: shucaiIsSummaryRow(report.rows[i]));
      if (w > widest) widest = w;
    }
    return (widest + 24).clamp(minWidth, maxWidth);
  }

  double _measure(String text, double fontSize, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DunesTypography.sans(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  double _rowHeight(
    ShucaiReport report,
    int rowIndex,
    List<double> widths,
    double fontSize,
    double baseHeight,
  ) {
    var lines = 1;
    for (var c = 0; c < report.columns.length; c++) {
      if (!shucaiIsNameColumn(report.columns[c])) continue;
      final text = _display(report, rowIndex, c);
      final inner = (widths[c] - 16).clamp(40.0, 400.0);
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DunesTypography.sans(fontSize: fontSize),
        ),
        maxLines: 3,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: inner);
      final n = painter.computeLineMetrics().length;
      if (n > lines) lines = n;
    }
    if (lines <= 1) return baseHeight;
    return baseHeight + (lines - 1) * (fontSize + 4);
  }

  Widget _cell(
    String text, {
    required double width,
    required double fontSize,
    bool header = false,
    bool alignEnd = false,
    bool bold = false,
    bool wrap = false,
    String tooltip = '',
  }) {
    final child = SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: header ? 2 : (wrap ? 3 : 1),
            softWrap: header || wrap,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style:
                (header || !alignEnd
                        ? DunesTypography.sans
                        : DunesTypography.mono)(
                      fontSize: fontSize,
                      fontWeight: header || bold
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: header ? DunesColors.text2 : DunesColors.text,
                    ),
          ),
        ),
      ),
    );
    if (tooltip.trim().isEmpty) return child;
    return Tooltip(message: tooltip, child: child);
  }
}

bool _isTotalLike(Map<String, dynamic> row) => shucaiIsSummaryRow(row);
