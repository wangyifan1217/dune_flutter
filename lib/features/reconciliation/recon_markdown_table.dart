import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import 'recon_audit_record.dart';
import 'recon_gfm.dart';
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

/// 资管 Markdown 表 + 与 JSON 表相同的行内确认/反驳。
class ReconMarkdownTable extends StatelessWidget {
  const ReconMarkdownTable({
    super.key,
    required this.markdown,
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

  final String markdown;
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
  Widget build(BuildContext context) {
    final tables = parseReconGfmTables(markdown);
    if (tables.isEmpty) return const SizedBox.shrink();
    final tableBlocks = <Widget>[];
    var offset = 0;
    for (final table in tables) {
      tableBlocks.add(
        _ReconGfmTableBlock(
          table: table,
          report: report,
          rowOffset: offset,
          showTitle: tables.length > 1,
          compact: compact,
          showRowActions: showRowActions,
          showBatchSelect: showBatchSelect,
          showConfirmAction: showConfirmAction,
          showPrevious: showPrevious,
          rowActionsLocked: rowActionsLocked,
          selectedRowKeys: selectedRowKeys,
          decisions: decisions,
          previous: previous,
          acks: acks,
          visibleSteps: visibleSteps,
          avatarService: avatarService,
          onToggleRow: onToggleRow,
          onToggleSelectAll: onToggleSelectAll,
          onConfirmRow: onConfirmRow,
          onRejectRow: onRejectRow,
        ),
      );
      offset += table.rows.length;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tableBlocks.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                tableBlocks[i],
              ],
            ],
          );
        }
        if (tableBlocks.length == 1) {
          return tableBlocks.first;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tableBlocks.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Expanded(child: tableBlocks[i]),
            ],
          ],
        );
      },
    );
  }
}

class _ReconGfmTableBlock extends StatefulWidget {
  const _ReconGfmTableBlock({
    required this.table,
    required this.report,
    required this.rowOffset,
    required this.showTitle,
    required this.compact,
    required this.showRowActions,
    required this.showBatchSelect,
    required this.showConfirmAction,
    required this.showPrevious,
    required this.rowActionsLocked,
    required this.selectedRowKeys,
    required this.decisions,
    required this.previous,
    this.acks = const [],
    this.visibleSteps = reconAuditChainSteps,
    this.avatarService,
    this.onToggleRow,
    this.onToggleSelectAll,
    this.onConfirmRow,
    this.onRejectRow,
  });

  final ReconGfmTable table;
  final ShucaiReport report;
  final int rowOffset;
  final bool showTitle;
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
  State<_ReconGfmTableBlock> createState() => _ReconGfmTableBlockState();
}

class _ReconGfmTableBlockState extends State<_ReconGfmTableBlock> {
  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    if (table.headers.isEmpty) return const SizedBox.shrink();
    final compact = widget.compact;
    final fontSize = compact ? 11.0 : 12.0;
    final headerH = compact ? 40.0 : 44.0;
    final baseRowH = compact ? 40.0 : 44.0;
    final widths = [
      for (var c = 0; c < table.headers.length; c++)
        _colWidth(table, c, fontSize, compact),
    ];
    final dataW = widths.fold<double>(0, (a, b) => a + b);
    final actionW = widget.showRowActions
        ? (widget.showConfirmAction
              ? (widget.showBatchSelect
                    ? (compact ? 128.0 : 136.0)
                    : (compact ? 96.0 : 108.0))
              : (compact ? 72.0 : 80.0))
        : 0.0;
    final heights = [
      for (var i = 0; i < table.rows.length; i++)
        _rowHeight(table.rows[i], widths, fontSize, baseRowH),
    ];
    final notes = [
      for (var i = 0; i < table.rows.length; i++) _notesForIndex(i),
    ];
    final noteH = [
      for (final item in notes) item.isEmpty ? 0.0 : 8.0 + item.length * 22.0,
    ];

    final steps = widget.visibleSteps.isEmpty
        ? reconAuditChainSteps
        : widget.visibleSteps;
    final dataHeader = Row(
      children: [
        for (var c = 0; c < table.headers.length; c++)
          _cell(
            table.headers[c],
            width: widths[c],
            height: headerH,
            fontSize: fontSize,
            header: true,
          ),
      ],
    );
    final dataBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < table.rows.length; i++) ...[
          _band(
            height: heights[i],
            color: _rowColor(i),
            child: Row(
              children: [
                for (var c = 0; c < table.headers.length; c++)
                  _cell(
                    c < table.rows[i].length ? table.rows[i][c] : '',
                    width: widths[c],
                    height: heights[i],
                    fontSize: fontSize,
                    header: false,
                    wrap: c == 0,
                    alignEnd: c > 0,
                    bold: _isSummary(i),
                  ),
              ],
            ),
          ),
          if (notes[i].isNotEmpty)
            _noteRow(
              notes: notes[i],
              height: noteH[i],
              width: dataW,
            ),
        ],
      ],
    );
    Widget auditLane({required bool header, required bool body}) {
      return ReconFrozenAuditLane(
        compact: compact,
        headerH: headerH,
        fontSize: fontSize,
        rowCount: widget.table.rows.length,
        heights: heights,
        noteHeights: noteH,
        rowColorAt: _rowColor,
        noteColorAt: (i) => notes[i].isEmpty ? null : notes[i].first.background,
        reviewersAt: _reviewersAt,
        rowTitleAt: (i) {
          final row = _jsonAt(i);
          return row == null ? '' : shucaiRowDisplayName(row);
        },
        isSummaryAt: _isSummary,
        avatarService: widget.avatarService,
        visibleSteps: steps,
        includeHeader: header,
        includeBody: body,
      );
    }

    final pinned = ReconPinnedTable(
      headerHeight: headerH,
      dataWidth: dataW,
      leadingHeader: widget.showRowActions
          ? _frozenActionColumn(
              heights: heights,
              noteHeights: noteH,
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
              heights: heights,
              noteHeights: noteH,
              notes: notes,
              headerH: headerH,
              width: actionW,
              fontSize: fontSize,
              includeHeader: false,
              includeBody: true,
            )
          : null,
      trailingHeader:
          widget.showPrevious ? auditLane(header: true, body: false) : null,
      trailingBody:
          widget.showPrevious ? auditLane(header: false, body: true) : null,
      dataHeader: dataHeader,
      dataBody: dataBody,
    );

    final title = widget.showTitle && table.title.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              table.title,
              style: DunesTypography.sans(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
                color: DunesColors.text,
              ),
            ),
          )
        : null;

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
            child: title == null
                ? pinned
                : constraints.hasBoundedHeight
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          Expanded(child: pinned),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, pinned],
                      ),
          ),
        );
        if (constraints.hasBoundedHeight) {
          return SizedBox.expand(child: child);
        }
        return child;
      },
    );
  }

  Widget _frozenActionColumn({
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
      for (var i = 0; i < widget.report.rows.length; i++)
        if (!shucaiIsSummaryRow(widget.report.rows[i]))
          shucaiRowKey(widget.report.rows[i], i),
    ];
    final selected = widget.selectedRowKeys;
    final allSelected = keys.isNotEmpty && keys.every(selected.contains);
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
              for (var i = 0; i < widget.table.rows.length; i++) ...[
                SizedBox(
                  height: heights[i],
                  child: ColoredBox(
                    color: _rowColor(i),
                    child: _actionCell(i),
                  ),
                ),
                if (notes[i].isNotEmpty)
                  ColoredBox(
                    color: notes[i].first.background,
                    child: SizedBox(height: noteHeights[i], width: width),
                  ),
              ],
          ],
        ),
      ),
    );
  }

  Color _rowColor(int i) {
    final key = _keyAt(i);
    if (key.isNotEmpty && widget.selectedRowKeys.contains(key)) {
      return const Color(0xFFF7F3FC);
    }
    if (_isSummary(i)) return const Color(0xFFF3F6F5);
    final decision = _decisionAt(i);
    final reviewers = _reviewersAt(i);
    if (decision?.rejected == true ||
        reviewers.any((item) => item.rejected)) {
      return const Color(0xFFFBEDEC);
    }
    return Colors.white;
  }

  int _jsonIndex(int i) => widget.rowOffset + i;

  Map<String, dynamic>? _jsonAt(int i) {
    final index = _jsonIndex(i);
    if (index < 0 || index >= widget.report.rows.length) return null;
    return widget.report.rows[index];
  }

  bool _isSummary(int i) {
    final row = _jsonAt(i);
    return row != null && shucaiIsSummaryRow(row);
  }

  String _keyAt(int i) {
    final row = _jsonAt(i);
    if (row == null || shucaiIsSummaryRow(row)) return '';
    return shucaiRowKey(row, _jsonIndex(i));
  }

  ReconRowDecision? _decisionAt(int i) {
    final key = _keyAt(i);
    if (key.isEmpty) return null;
    return widget.decisions[key] ??
        widget.decisions[reconRowDecisionId(widget.report.tab, key)];
  }

  List<ReconRowReviewer> _reviewersAt(int i) {
    final key = _keyAt(i);
    if (key.isEmpty) return const [];
    return reconFilterReviewersForSteps(
      reconReviewersWithCardAcks(
        reviewers: reconReviewersForRow(
          previous: widget.previous,
          tab: widget.report.tab,
          rowKey: key,
        ),
        acks: widget.visibleSteps.contains(reconChainL2)
            ? widget.acks
            : const [],
      ),
      widget.visibleSteps,
    );
  }

  double _colWidth(ReconGfmTable table, int c, double fontSize, bool compact) {
    var maxChars = table.headers[c].length;
    for (final row in table.rows) {
      if (c < row.length) {
        final n = row[c].length;
        if (n > maxChars) maxChars = n;
      }
    }
    final px = maxChars * fontSize * 0.95 + 20;
    final minW = c == 0 ? (compact ? 88.0 : 100.0) : (compact ? 80.0 : 92.0);
    return px.clamp(minW, compact ? 240.0 : 280.0);
  }

  double _rowHeight(
    List<String> cells,
    List<double> widths,
    double fontSize,
    double base,
  ) {
    var lines = 1;
    for (var c = 0; c < cells.length && c < widths.length; c++) {
      final inner = (widths[c] - 16).clamp(40.0, 400.0);
      final painter = TextPainter(
        text: TextSpan(
          text: cells[c],
          style: DunesTypography.sans(fontSize: fontSize),
        ),
        maxLines: 4,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: inner);
      final n = painter.computeLineMetrics().length;
      if (n > lines) lines = n;
    }
    if (lines <= 1) return base;
    return base + (lines - 1) * (fontSize + 4);
  }

  Widget _band({
    required double height,
    required Color color,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(height: height, child: child),
    );
  }

  Widget _cell(
    String text, {
    required double width,
    required double height,
    required double fontSize,
    required bool header,
    bool wrap = false,
    bool alignEnd = false,
    bool bold = false,
  }) {
    final style =
        (header || !alignEnd ? DunesTypography.sans : DunesTypography.mono)(
          fontSize: fontSize,
          fontWeight: header || bold ? FontWeight.w600 : FontWeight.w400,
          color: header ? DunesColors.text2 : DunesColors.text,
        );
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text.isEmpty ? ' ' : text,
            maxLines: header ? 2 : (wrap ? 4 : 1),
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: style,
          ),
        ),
      ),
    );
  }

  Widget _actionCell(int i) {
    final key = _keyAt(i);
    if (key.isEmpty) return const SizedBox.shrink();
    final decision = _decisionAt(i);
    final selected = widget.selectedRowKeys.contains(key);
    final locked = widget.rowActionsLocked;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          if (widget.showBatchSelect)
            SizedBox(
              width: 22,
              child: Checkbox(
                value: selected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: DunesColors.brandPurple,
                onChanged: widget.onToggleRow == null
                    ? null
                    : (_) => widget.onToggleRow!(key),
              ),
            ),
          Expanded(
            child: locked
                ? Text(
                    decision == null
                        ? '未处理'
                        : (decision.rejected
                              ? '已驳回'
                              : (decision.reconfirmed ? '已复核' : '已确认')),
                    style: DunesTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: decision == null
                          ? DunesColors.text3
                          : (decision.rejected
                                ? DunesColors.coral
                                : DunesColors.green),
                    ),
                  )
                : Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (widget.showConfirmAction ||
                          decision?.rejected == true)
                        _chip(
                          decision?.rejected == true ? '复核' : '确认',
                          active: decision?.confirmed == true,
                          color: DunesColors.green,
                          onTap: widget.onConfirmRow == null
                              ? null
                              : () => widget.onConfirmRow!(key),
                        ),
                      _chip(
                        '反驳',
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
    );
  }

  Widget _chip(
    String label, {
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

  List<_RowNote> _notesForIndex(int i) {
    return _notes(_decisionAt(i), _reviewersAt(i));
  }

  List<_RowNote> _notes(
    ReconRowDecision? mine,
    List<ReconRowReviewer> previous,
  ) {
    final notes = <_RowNote>[];
    for (final item in previous) {
      final layer = reconChainStepLabel(item.chainStepKey);
      if (item.rejected && item.reason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '$layer反驳',
            text: item.reason.trim(),
            color: DunesColors.coral,
            background: DunesColors.coralSoft,
          ),
        );
      } else if (item.rejectReason.trim().isNotEmpty) {
        notes.add(
          _RowNote(
            label: '$layer驳回历史',
            text: item.rejectReason.trim(),
            color: DunesColors.coral,
            background: DunesColors.coralSoft,
          ),
        );
      }
    }
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
}
