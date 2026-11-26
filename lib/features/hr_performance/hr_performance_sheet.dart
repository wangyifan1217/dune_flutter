import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../core/theme/dunes_theme.dart';

/// 员工看到的考核表，使用固定七列。
class HrAssessmentSheet extends StatelessWidget {
  const HrAssessmentSheet({
    super.key,
    required this.lines,
    this.scoresVisible = false,
    this.month = '',
    this.name = '',
    this.supervisor = '',
    this.bonuses = const [],
    this.finalTotal,
    this.deductionEditor,
    this.deductionInstructions = '',
    this.forceTable = false,
  });

  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> bonuses;
  final num? finalTotal;
  final Widget? deductionEditor;
  final String deductionInstructions;
  final bool scoresVisible;
  final bool forceTable;
  final String month;
  final String name;
  final String supervisor;

  static const columns = ['考核维度', '维度权重', '考核指标', '指标权重', '评分标准', '分值', '上级评分'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE4DCEC),
      role: DunesColorRole.border,
    );
    final headerBg = isDark
        ? DunesColors.brandPurple.withValues(alpha: 0.22)
        : const Color(0xFFF2EEFA);
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text3);
    final groups = _groups(lines);
    final weightTotal = lines.fold<double>(
      0,
      (sum, line) => sum + (_num(line['weight']) ?? 0),
    );
    double? weightedTotal;
    if (scoresVisible) {
      var total = 0.0;
      var complete = lines.isNotEmpty;
      for (final line in lines) {
        final score = _num(line['score']);
        final weight = _num(line['weight']);
        if (score == null || weight == null) {
          complete = false;
          break;
        }
        total += line['directScore'] == true ? score : score * weight / 100;
      }
      if (complete) weightedTotal = total;
    }
    if (scoresVisible && finalTotal != null) {
      weightedTotal = finalTotal!.toDouble();
    }
    final headingParts = [
      if (month.isNotEmpty) '考核月份 $month',
      if (name.isNotEmpty) '姓名 $name',
      if (supervisor.isNotEmpty) '直接上级 $supervisor',
    ];
    final heading = headingParts.join('    ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1D2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: hairline,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (heading.isNotEmpty ||
                (!forceTable && MediaQuery.sizeOf(context).width < 640))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final part in headingParts)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : const Color(0xFFF6F4FB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                part,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: text,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!forceTable && MediaQuery.sizeOf(context).width < 640)
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => Dialog(
                            insetPadding: const EdgeInsets.all(12),
                            child: SizedBox(
                              height: MediaQuery.sizeOf(context).height * .85,
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                            '完整考核表',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: HrAssessmentSheet(
                                        lines: lines,
                                        scoresVisible: scoresVisible,
                                        month: month,
                                        name: name,
                                        supervisor: supervisor,
                                        bonuses: bonuses,
                                        finalTotal: finalTotal,
                                        deductionInstructions:
                                            deductionInstructions,
                                        forceTable: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        child: const Text('完整表格'),
                      ),
                  ],
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) =>
                  !forceTable && constraints.maxWidth < 640
                  ? _compactSheet(context, groups, weightTotal, weightedTotal)
                  : _HrSheetViewport(
                      child: SizedBox(
                        width: constraints.maxWidth < 860
                            ? 860
                            : constraints.maxWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Table(
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.top,
                              columnWidths: const {
                                0: FixedColumnWidth(74),
                                1: FixedColumnWidth(72),
                                2: FixedColumnWidth(150),
                                3: FixedColumnWidth(72),
                                4: FlexColumnWidth(),
                                5: FixedColumnWidth(64),
                                6: FixedColumnWidth(74),
                              },
                              border: TableBorder(
                                top: heading.isEmpty
                                    ? BorderSide.none
                                    : BorderSide(color: border),
                                horizontalInside: BorderSide(color: border),
                                verticalInside: BorderSide(color: border),
                              ),
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(color: headerBg),
                                  children: [
                                    for (final title in columns)
                                      _cell(
                                        title,
                                        color: text,
                                        weight: FontWeight.w600,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            for (final group in groups)
                              _mergedGroup(context, group, border, text, muted),
                            Table(
                              columnWidths: const {
                                0: FixedColumnWidth(74),
                                1: FixedColumnWidth(72),
                                2: FixedColumnWidth(150),
                                3: FixedColumnWidth(72),
                                4: FlexColumnWidth(),
                                5: FixedColumnWidth(64),
                                6: FixedColumnWidth(74),
                              },
                              border: TableBorder(
                                horizontalInside: BorderSide(color: border),
                                verticalInside: BorderSide(color: border),
                                top: BorderSide(color: border),
                              ),
                              children: [
                                TableRow(
                                  children: [
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.middle,
                                      child: _cell(
                                        '减分项',
                                        color: text,
                                        weight: FontWeight.w700,
                                        align: TextAlign.center,
                                      ),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.middle,
                                      child: _cell(
                                        '—',
                                        align: TextAlign.center,
                                      ),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.middle,
                                      child: _cell(
                                        '规章制度遵守情况',
                                        color: text,
                                        align: TextAlign.center,
                                      ),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.middle,
                                      child: _cell(
                                        '0%',
                                        align: TextAlign.center,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            deductionInstructions.isEmpty
                                                ? '按本次考核冻结的规章制度和扣分上限执行。'
                                                : deductionInstructions,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: muted,
                                            ),
                                          ),
                                          for (final b in bonuses.where(
                                            (b) => (_num(b['points']) ?? 0) < 0,
                                          ))
                                            Text(
                                              '${b['name']}：${b['points']} 分 · ${b['source'] ?? ''}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ?deductionEditor,
                                        ],
                                      ),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.middle,
                                      child: _cell(
                                        '扣分',
                                        align: TextAlign.center,
                                      ),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.fill,
                                      child: ColoredBox(
                                        color: const Color(0xFFEDE5FA),
                                        child: Center(
                                          child: _cell(
                                            scoresVisible
                                                ? _score(
                                                    bonuses.fold<double>(
                                                      0,
                                                      (sum, b) =>
                                                          sum +
                                                          ((_num(b['points']) ??
                                                                      0) <
                                                                  0
                                                              ? _num(
                                                                  b['points'],
                                                                )!
                                                              : 0),
                                                    ),
                                                  )
                                                : '—',
                                            align: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                TableRow(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFFF2CC),
                                  ),
                                  children: [
                                    _cell(
                                      '合计',
                                      color: text,
                                      weight: FontWeight.w700,
                                    ),
                                    _cell(
                                      _percent(weightTotal),
                                      color: text,
                                      weight: FontWeight.w700,
                                    ),
                                    _cell(''),
                                    _cell(''),
                                    _cell(
                                      weightedTotal == null
                                          ? (lines.any(
                                                  (line) =>
                                                      line['directScore'] ==
                                                      true,
                                                )
                                                ? '最终得分 = 各指标得分相加'
                                                : '最终得分 = 各项加权得分相加')
                                          : '最终得分 ${_score(weightedTotal)}',
                                      color: text,
                                      weight: FontWeight.w700,
                                    ),
                                    _cell(''),
                                    _cell(
                                      weightedTotal == null
                                          ? '—'
                                          : _score(weightedTotal),
                                      color: text,
                                      weight: FontWeight.w700,
                                      align: TextAlign.center,
                                    ),
                                  ],
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

  Widget _mergedGroup(
    BuildContext context,
    _DimensionGroup group,
    Color border,
    Color text,
    Color muted,
  ) {
    final dimensionColor = DunesColors.resolve(
      context,
      const Color(0xFFF0F4FA),
    );
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(74),
        1: FixedColumnWidth(72),
        2: FlexColumnWidth(),
      },
      border: TableBorder(
        top: BorderSide(color: border),
        verticalInside: BorderSide(color: border),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.fill,
              child: ColoredBox(
                color: dimensionColor,
                child: Center(
                  child: _cell(
                    group.dimension,
                    color: text,
                    weight: FontWeight.w600,
                    align: TextAlign.center,
                  ),
                ),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.fill,
              child: ColoredBox(
                color: dimensionColor,
                child: Center(
                  child: _cell(
                    _percent(group.weight),
                    color: text,
                    align: TextAlign.center,
                  ),
                ),
              ),
            ),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(150),
                1: FixedColumnWidth(72),
                2: FlexColumnWidth(),
                3: FixedColumnWidth(74),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: border),
                verticalInside: BorderSide(color: border),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                for (final line in group.lines)
                  TableRow(
                    children: [
                      TableCell(
                        verticalAlignment: TableCellVerticalAlignment.middle,
                        child: _cell(
                          '${line['name'] ?? ''}',
                          color: text,
                          weight: FontWeight.w600,
                          align: TextAlign.center,
                        ),
                      ),
                      TableCell(
                        verticalAlignment: TableCellVerticalAlignment.middle,
                        child: _cell(
                          _percent(_num(line['weight']) ?? 0),
                          color: text,
                          align: TextAlign.center,
                        ),
                      ),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(),
                          1: FixedColumnWidth(64),
                        },
                        border: TableBorder(
                          horizontalInside: BorderSide(color: border),
                          verticalInside: BorderSide(color: border),
                        ),
                        children: [
                          for (final band in _bands(line))
                            TableRow(
                              children: [
                                _cell('${band['description']}', color: muted),
                                _cell(
                                  '${band['range']}',
                                  color: muted,
                                  align: TextAlign.center,
                                ),
                              ],
                            ),
                        ],
                      ),
                      TableCell(
                        verticalAlignment: TableCellVerticalAlignment.fill,
                        child: ColoredBox(
                          color: const Color(0xFFEDE5FA),
                          child: Center(
                            child: _cell(
                              _supervisor(line),
                              color: text,
                              align: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactSheet(
    BuildContext context,
    List<_DimensionGroup> groups,
    double weightTotal,
    double? weightedTotal,
  ) {
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text2);
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE4DCEC),
      role: DunesColorRole.border,
    );
    final surface = DunesColors.resolve(
      context,
      const Color(0xFFD9E7F5),
      role: DunesColorRole.surface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: surface,
            child: Text(
              "${group.dimension} · 维度权重 ${_percent(group.weight)}",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
          for (final line in group.lines)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${line['name'] ?? ''}",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "指标权重 ${_percent(_num(line['weight']) ?? 0)}${_num(line['selfScore']) == null ? '' : ' · 自评分 ${_score(_num(line['selfScore'])!)}'}${scoresVisible ? ' · 上级评分 ${_supervisor(line).replaceAll("\n", " · ")}' : ''}",
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  for (final band in _bands(line))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              band['description'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            band['range'] ?? '',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '减分项 · 规章制度遵守情况',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                deductionInstructions.isEmpty
                    ? '按本次考核冻结的规章制度和扣分上限执行。'
                    : deductionInstructions,
              ),
              for (final b in bonuses.where(
                (b) => (_num(b['points']) ?? 0) < 0,
              ))
                Text('${b['points']} 分 · ${b['source'] ?? ''}'),
              ?deductionEditor,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            "合计 ${_percent(weightTotal)}${weightedTotal == null ? (lines.any((line) => line['directScore'] == true) ? ' · 最终得分 = 各指标得分相加' : ' · 最终得分 = 各项加权得分相加') : ' · 最终得分 ${_score(weightedTotal)}'}",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ),
      ],
    );
  }

  String _supervisor(Map<String, dynamic> line) {
    if (!scoresVisible) return '—';
    final score = _num(line['score']);
    return score == null ? '—' : _score(score);
  }

  List<Map<String, String>> _bands(Map<String, dynamic> line) {
    final bands = (line['bands'] as List? ?? []).whereType<Map>().toList();
    if (bands.isEmpty) {
      return [
        {
          'description': '${line['instructions'] ?? ''}',
          'range': line['directScore'] == true
              ? '0–${_score(_num(line['weight']) ?? 0)}'
              : '0–100',
        },
      ];
    }
    return [
      for (final band in bands)
        {
          'description': '${band['description']}',
          'range': '${band['min']}–${band['max']}',
        },
    ];
  }
}

/// 电脑端先展示所有指标的概要；评分标准可按指标展开。
class HrAssessmentOverview extends StatelessWidget {
  const HrAssessmentOverview({
    super.key,
    required this.lines,
    required this.scoresVisible,
  });
  final List<Map<String, dynamic>> lines;
  final bool scoresVisible;

  @override
  Widget build(BuildContext context) {
    final groups = _groups(lines);
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text2);
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE4DCEC),
      role: DunesColorRole.border,
    );
    final surface = DunesColors.resolve(
      context,
      const Color(0xFFD9E7F5),
      role: DunesColorRole.surface,
    );
    final formatter = HrAssessmentSheet(
      lines: lines,
      scoresVisible: scoresVisible,
    );
    final total = lines.fold<double>(
      0,
      (sum, line) => sum + (_num(line['weight']) ?? 0),
    );
    return Container(
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups) ...[
              Container(
                color: surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '${group.dimension} · 维度权重 ${_percent(group.weight)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                ),
              ),
              for (final line in group.lines)
                ExpansionTile(
                  key: ValueKey(
                    'hr-overview-${line['indicatorId'] ?? line['name']}',
                  ),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  title: Text(
                    '${line['name'] ?? ''}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '权重 ${_percent(_num(line['weight']) ?? 0)}',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      if (scoresVisible) ...[
                        const SizedBox(width: 18),
                        Text(
                          '上级评分 ${formatter._supervisor(line).replaceAll("\n", " · ")}',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more_rounded, size: 20, color: muted),
                    ],
                  ),
                  children: [
                    for (final band in formatter._bands(line))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                band['description'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              band['range'] ?? '',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Text(
                '合计权重 ${_percent(total)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DimensionGroup {
  _DimensionGroup(this.dimension, this.lines);
  final String dimension;
  final List<Map<String, dynamic>> lines;
  double get weight =>
      lines.fold<double>(0, (sum, line) => sum + (_num(line['weight']) ?? 0));
}

List<_DimensionGroup> _groups(List<Map<String, dynamic>> lines) {
  final order = <String>[];
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final line in lines) {
    final dimension = '${line['project'] ?? ''}'.trim();
    final key = dimension.isEmpty ? '未分组' : dimension;
    grouped
        .putIfAbsent(key, () {
          order.add(key);
          return [];
        })
        .add(line);
  }
  return [for (final key in order) _DimensionGroup(key, grouped[key]!)];
}

double? _num(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String _percent(double value) {
  final text = _score(value);
  return '$text%';
}

String _score(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1);
}

Widget _cell(
  String text, {
  Color? color,
  FontWeight? weight,
  TextAlign align = TextAlign.start,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    child: Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: color,
        fontWeight: weight,
      ),
    ),
  );
}

class _HrSheetViewport extends StatefulWidget {
  const _HrSheetViewport({required this.child});
  final Widget child;
  @override
  State<_HrSheetViewport> createState() => _HrSheetViewportState();
}

class _HrSheetViewportState extends State<_HrSheetViewport> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: PointerDeviceKind.values.toSet(),
    ),
    child: Scrollbar(
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    ),
  );
}
