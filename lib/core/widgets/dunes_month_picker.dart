import 'package:flutter/material.dart';

import '../theme/dunes_theme.dart';

/// 仅选择年/月，不出现日期网格。
Future<DateTime?> showDunesMonthPicker({
  required BuildContext context,
  required DateTime initialMonth,
  required DateTime firstMonth,
  required DateTime lastMonth,
  String title = '选择月份',
  Color accent = const Color(0xFF7B5CD8),
}) {
  final initial = DateTime(initialMonth.year, initialMonth.month);
  final first = DateTime(firstMonth.year, firstMonth.month);
  final last = DateTime(lastMonth.year, lastMonth.month);
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _DunesMonthPickerDialog(
      title: title,
      initial: initial,
      firstMonth: first,
      lastMonth: last,
      accent: accent,
    ),
  );
}

class _DunesMonthPickerDialog extends StatefulWidget {
  const _DunesMonthPickerDialog({
    required this.title,
    required this.initial,
    required this.firstMonth,
    required this.lastMonth,
    required this.accent,
  });

  final String title;
  final DateTime initial;
  final DateTime firstMonth;
  final DateTime lastMonth;
  final Color accent;

  @override
  State<_DunesMonthPickerDialog> createState() => _DunesMonthPickerDialogState();
}

class _DunesMonthPickerDialogState extends State<_DunesMonthPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year.clamp(
      widget.firstMonth.year,
      widget.lastMonth.year,
    );
  }

  bool _canSelect(int year, int month) {
    final value = year * 100 + month;
    return value >= widget.firstMonth.year * 100 + widget.firstMonth.month &&
        value <= widget.lastMonth.year * 100 + widget.lastMonth.month;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一年',
                  onPressed: _year <= widget.firstMonth.year
                      ? null
                      : () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '$_year年',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  onPressed: _year >= widget.lastMonth.year
                      ? null
                      : () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                for (var month = 1; month <= 12; month++) _monthCell(month),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _monthCell(int month) {
    final enabled = _canSelect(_year, month);
    final selected =
        _year == widget.initial.year && month == widget.initial.month;
    return InkWell(
      onTap: enabled
          ? () => Navigator.pop(context, DateTime(_year, month))
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? widget.accent
              : enabled
              ? widget.accent.withValues(alpha: 0.08)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$month月',
          style: TextStyle(
            color: selected
                ? Colors.white
                : enabled
                ? DunesColors.text
                : DunesColors.text3,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
