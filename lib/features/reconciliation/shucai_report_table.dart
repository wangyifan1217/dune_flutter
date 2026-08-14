import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'reconciliation_shucai_models.dart';

/// 明细表：列超出宽度时可左右滑（触控 / 鼠标拖 / 滚轮），并显示底栏滚动条。
class ShucaiReportTable extends StatefulWidget {
  const ShucaiReportTable({
    super.key,
    required this.report,
    this.compact = false,
  });

  final ShucaiReport report;
  final bool compact;

  @override
  State<ShucaiReportTable> createState() => _ShucaiReportTableState();
}

class _ShucaiReportTableState extends State<ShucaiReportTable> {
  final ScrollController _h = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report.withEnsuredGrandTotal;
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
    final spans = _firstColumnSpans(report);
    final baseRowH = compact ? 36.0 : 40.0;
    final headerH = compact ? 40.0 : 44.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ScrollConfiguration(
          behavior: const _TableScrollBehavior(),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Scrollbar(
              controller: _h,
              thumbVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _h,
                scrollDirection: Axis.horizontal,
                primary: false,
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: totalWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        height: headerH,
                        color: const Color(0xFFF6F7F9),
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
                      ),
                      for (var i = 0; i < report.rows.length; i++)
                        _row(
                          height: _rowHeight(
                            report,
                            report.rows[i],
                            widths,
                            fontSize,
                            baseRowH,
                            spans[i],
                          ),
                          color: _isTotalLike(report.rows[i])
                              ? const Color(0xFFF3F6F5)
                              : Colors.white,
                          children: [
                            for (var c = 0; c < report.columns.length; c++)
                              _cell(
                                c == 0 && spans[i] == 0
                                    ? ''
                                    : _display(
                                        report,
                                        report.rows[i],
                                        report.columns[c],
                                      ),
                                width: widths[c],
                                fontSize: fontSize,
                                alignEnd: c > 0 &&
                                    !shucaiIsNameColumn(report.columns[c]),
                                bold: shucaiIsSummaryRow(report.rows[i]),
                                header: false,
                                wrap: shucaiIsNameColumn(report.columns[c]),
                                tooltip: c == 0 && spans[i] == 0
                                    ? ''
                                    : shucaiNestedAmountTooltip(
                                        shucaiCellRaw(
                                          report.rows[i],
                                          report.columns[c],
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
      ),
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_h.hasClients) return;
    // 只吃横向位移；竖向滚轮交给外层 ListView，避免「往下滚表格却右滑」。
    final delta = event.scrollDelta.dx;
    if (delta == 0 || !_h.position.hasContentDimensions) return;
    final next = (_h.offset + delta).clamp(
      _h.position.minScrollExtent,
      _h.position.maxScrollExtent,
    );
    if (next != _h.offset) {
      _h.jumpTo(next);
    }
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
    Map<String, dynamic> row,
    ShucaiColumn col,
  ) {
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
    for (final row in report.rows) {
      final text = _display(report, row, col);
      final w = _measure(text, fontSize, bold: shucaiIsSummaryRow(row));
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
    Map<String, dynamic> row,
    List<double> widths,
    double fontSize,
    double baseHeight,
    int span,
  ) {
    var lines = 1;
    for (var c = 0; c < report.columns.length; c++) {
      if (c == 0 && span == 0) continue;
      if (!shucaiIsNameColumn(report.columns[c])) continue;
      final text = _display(report, row, report.columns[c]);
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

class _TableScrollBehavior extends MaterialScrollBehavior {
  const _TableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

bool _isTotalLike(Map<String, dynamic> row) => shucaiIsSummaryRow(row);

List<int> _firstColumnSpans(ShucaiReport report) {
  final rows = report.rows;
  final spans = List<int>.filled(rows.length, 1);
  final useGroupTotal = rows.any(
    (r) => (r['rowType'] ?? '').toString().toUpperCase() == 'GROUP_TOTAL',
  );
  if (useGroupTotal) {
    for (var i = 0; i < rows.length; i++) {
      final type = (rows[i]['rowType'] ?? '').toString().toUpperCase();
      if (type != 'GROUP_TOTAL') {
        spans[i] = 0;
        continue;
      }
      final key = (rows[i]['groupKey'] ?? rows[i]['groupName'] ?? '').toString();
      var span = 1;
      var j = i + 1;
      while (j < rows.length) {
        final nextType = (rows[j]['rowType'] ?? '').toString().toUpperCase();
        final nextKey =
            (rows[j]['groupKey'] ?? rows[j]['groupName'] ?? '').toString();
        if (nextType != 'DETAIL' || nextKey != key) break;
        span++;
        j++;
      }
      spans[i] = span;
    }
    return spans;
  }
  for (var i = 0; i < rows.length; i++) {
    final key = (rows[i]['groupKey'] ?? rows[i]['groupName'] ?? '').toString();
    if (i > 0) {
      final prev =
          (rows[i - 1]['groupKey'] ?? rows[i - 1]['groupName'] ?? '').toString();
      if (key.isNotEmpty && key == prev) {
        spans[i] = 0;
        continue;
      }
    }
    var span = 1;
    var j = i + 1;
    while (j < rows.length) {
      final next =
          (rows[j]['groupKey'] ?? rows[j]['groupName'] ?? '').toString();
      if (next != key || key.isEmpty) break;
      span++;
      j++;
    }
    spans[i] = span;
  }
  return spans;
}
