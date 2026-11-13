import 'package:flutter/material.dart';

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
  });

  final List<Map<String, dynamic>> lines;
  final bool scoresVisible;
  final String month;
  final String name;
  final String supervisor;

  static const columns = ['考核维度', '维度权重', '考核指标', '指标权重', '评分标准', '分值', '上级评分'];

  @override
  Widget build(BuildContext context) {
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE4DCEC),
      role: DunesColorRole.border,
    );
    final headerBg = DunesColors.resolve(context, const Color(0xFFF3EEF8));
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
    final heading = [
      if (month.isNotEmpty) '考核月份 $month',
      if (name.isNotEmpty) '姓名 $name',
      if (supervisor.isNotEmpty) '直接上级 $supervisor',
    ].join('    ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (heading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 980),
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  columnWidths: const {
                    0: FixedColumnWidth(88),
                    1: FixedColumnWidth(72),
                    2: FixedColumnWidth(160),
                    3: FixedColumnWidth(72),
                    4: FlexColumnWidth(),
                    5: FixedColumnWidth(64),
                    6: FixedColumnWidth(72),
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
                          _cell(title, color: muted, weight: FontWeight.w700),
                      ],
                    ),
                    for (final group in groups)
                      for (var i = 0; i < group.lines.length; i++)
                        for (var j = 0; j < _bands(group.lines[i]).length; j++)
                          TableRow(
                            children: [
                              _cell(
                                i == 0 && j == 0 ? group.dimension : '',
                                color: text,
                                weight: FontWeight.w600,
                              ),
                              _cell(
                                i == 0 && j == 0 ? _percent(group.weight) : '',
                                color: text,
                              ),
                              _cell(
                                j == 0 ? '${group.lines[i]['name'] ?? ''}' : '',
                                color: text,
                                weight: FontWeight.w600,
                              ),
                              _cell(
                                j == 0
                                    ? _percent(
                                        _num(group.lines[i]['weight']) ?? 0,
                                      )
                                    : '',
                                color: text,
                              ),
                              _cell(
                                '${_bands(group.lines[i])[j]['description']}',
                                color: muted,
                              ),
                              _cell(
                                '${_bands(group.lines[i])[j]['range']}',
                                color: muted,
                                align: TextAlign.center,
                              ),
                              _cell(
                                j == 0 ? _supervisor(group.lines[i]) : '',
                                color: text,
                                align: TextAlign.center,
                              ),
                            ],
                          ),
                    TableRow(
                      decoration: BoxDecoration(color: headerBg),
                      children: [
                        _cell('合计', color: text, weight: FontWeight.w700),
                        _cell(
                          _percent(weightTotal),
                          color: text,
                          weight: FontWeight.w700,
                        ),
                        _cell(
                          weightedTotal == null
                              ? (lines.any(
                                      (line) => line['directScore'] == true,
                                    )
                                    ? '最终得分 = 各指标得分相加'
                                    : '最终得分 = 各项加权得分相加')
                              : '最终得分 ${_score(weightedTotal)}',
                          color: text,
                          weight: FontWeight.w700,
                        ),
                        _cell(''),
                        _cell(''),
                        _cell(''),
                        _cell(''),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _supervisor(Map<String, dynamic> line) {
    if (!scoresVisible) return '—';
    final score = _num(line['score']);
    final suggested = _num(line['suggestedScore']);
    if (score == null && suggested == null) return '—';
    if (score == null) return '建议 ${_score(suggested!)}';
    if (suggested == null) return _score(score);
    return '${_score(score)}\n建议 ${_score(suggested)}';
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
  return TableCell(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    ),
  );
}
