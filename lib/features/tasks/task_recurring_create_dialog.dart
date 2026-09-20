import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'task_models.dart';
import 'task_widgets.dart';

/// 周期频率：每月可指定 1–28 日、月末或最后工作日。旧值「每月」仍按每月 1 日。
const kTaskRecurringKinds = <(String, String)>[
  ('monthly', '每月'),
  ('weekly', '每周'),
  ('daily', '每天'),
];

final kTaskRecurringMonthDays = <(String, String)>[
  for (var i = 1; i <= 28; i++) ('每月${i}日', '$i 日'),
  ('每月月末', '月末'),
  ('每月最后工作日', '最后工作日'),
];

const kTaskRecurringWeekdays = <(String, String)>[
  ('每周一', '周一'),
  ('每周二', '周二'),
  ('每周三', '周三'),
  ('每周四', '周四'),
  ('每周五', '周五'),
  ('每周六', '周六'),
  ('每周日', '周日'),
];

String encodeTaskRecurringFrequency({
  required String kind,
  String monthDay = '每月10日',
  String weekday = '每周一',
}) {
  return switch (kind) {
    'weekly' => weekday,
    'daily' => '每天',
    _ => monthDay,
  };
}

String taskRecurringFrequencyLabel(String frequency) {
  final raw = frequency.trim();
  if (raw.isEmpty) return '未设置周期';
  if (raw == '每天' || raw == '每日' || raw.toLowerCase() == 'daily') {
    return '每天';
  }
  if (raw == '每月') return '每月 1 日';
  for (final item in kTaskRecurringMonthDays) {
    if (item.$1 == raw) {
      if (raw == '每月月末') return '每月月末';
      if (raw == '每月最后工作日') return '每月最后工作日';
      return '每月 ${item.$2}';
    }
  }
  for (final item in kTaskRecurringWeekdays) {
    if (item.$1 == raw) return item.$1;
  }
  return raw;
}

String taskRecurringFrequencyHint(String frequency) {
  final raw = frequency.trim();
  if (raw == '每天' || raw == '每日') return '每个自然日生成一条主目标';
  if (raw.startsWith('每周')) return '${taskRecurringFrequencyLabel(raw)}生成一条主目标';
  if (raw == '每月最后工作日') {
    return '按公司节假日历，取当月最后一个工作日生成';
  }
  if (raw == '每月月末') return '每月最后一天生成一条主目标';
  if (raw == '每月') return '每月 1 日自动生成一条主目标';
  return '${taskRecurringFrequencyLabel(raw)}自动生成一条主目标；当月没有该日则在月末生成';
}

class TaskRecurringRuleDraft {
  const TaskRecurringRuleDraft({
    required this.title,
    required this.frequency,
    required this.startDate,
    this.endDate = '',
  });

  final String title;
  final String frequency;
  final String startDate;
  final String endDate;
}

Future<TaskRecurringRuleDraft?> showTaskRecurringCreateDialog(
  BuildContext context,
) {
  return showDialog<TaskRecurringRuleDraft>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => const _TaskRecurringCreateDialog(),
  );
}

class _TaskRecurringCreateDialog extends StatefulWidget {
  const _TaskRecurringCreateDialog();

  @override
  State<_TaskRecurringCreateDialog> createState() =>
      _TaskRecurringCreateDialogState();
}

class _TaskRecurringCreateDialogState extends State<_TaskRecurringCreateDialog> {
  final _titleCtrl = TextEditingController();
  String _kind = 'monthly';
  String _monthDay = '每月10日';
  String _weekday = '每周一';
  DateTime? _startAt;
  DateTime? _endAt;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String get _frequency => encodeTaskRecurringFrequency(
    kind: _kind,
    monthDay: _monthDay,
    weekday: _weekday,
  );

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startAt ?? now)
        : (_endAt ?? _startAt ?? now);
    final first = !isStart && _startAt != null
        ? _startAt!
        : DateTime(now.year - 1);
    final last = DateTime(now.year + 8);
    var initialDate = initial;
    if (initialDate.isBefore(first)) initialDate = first;
    if (initialDate.isAfter(last)) initialDate = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: first,
      lastDate: last,
      helpText: isStart ? '选择开始日期' : '选择结束日期',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: kTaskPurple),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      if (isStart) {
        _startAt = day;
        if (_endAt != null && _endAt!.isBefore(day)) _endAt = null;
      } else {
        _endAt = day;
      }
      _error = null;
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写任务名称');
      return;
    }
    if (_startAt == null) {
      setState(() => _error = '请选择开始日期');
      return;
    }
    if (_endAt != null && _endAt!.isBefore(_startAt!)) {
      setState(() => _error = '结束日期不能早于开始日期');
      return;
    }
    Navigator.pop(
      context,
      TaskRecurringRuleDraft(
        title: title,
        frequency: _frequency,
        startDate: formatTaskYmd(_startAt),
        endDate: _endAt == null ? '' : formatTaskYmd(_endAt),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 14,
        color: DunesColors.text3.withValues(alpha: 0.85),
      ),
      filled: true,
      fillColor: const Color(0xFFF5F6F8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kTaskPurple.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          if (required)
            const Text(
              ' *',
              style: TextStyle(fontSize: 12, color: Color(0xFFE35D6A)),
            ),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    String placeholder = '请选择',
    bool required = false,
    bool optional = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(label, required: required),
        Material(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('recurring-$label'),
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value == null ? placeholder : formatTaskYmd(value),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: value == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: value == null
                            ? DunesColors.text3
                            : DunesColors.text,
                      ),
                    ),
                  ),
                  if (optional && value != null)
                    InkWell(
                      onTap: () => setState(() {
                        _endAt = null;
                        _error = null;
                      }),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown({
    required Key key,
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: value,
      isExpanded: true,
      icon: const Icon(
        Icons.expand_more,
        size: 20,
        color: DunesColors.text3,
      ),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      decoration: _fieldDecoration(),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item.$1, child: Text(item.$2)),
      ],
      onChanged: (v) {
        if (v == null) return;
        onChanged(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: const Text(
        '新建周期任务',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '到达周期后会自动生成一条主目标。结束日期可不填，表示长期有效。',
                style: TextStyle(
                  fontSize: 13,
                  color: DunesColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _label('任务名称', required: true),
              TextField(
                key: const Key('recurring-title'),
                controller: _titleCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: _fieldDecoration(hint: '例如：每月报税、薪酬核算'),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('重复周期', required: true),
                        _dropdown(
                          key: const Key('recurring-frequency'),
                          value: _kind,
                          items: kTaskRecurringKinds,
                          onChanged: (value) => setState(() {
                            _kind = value;
                            _error = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                  if (_kind != 'daily') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label(_kind == 'weekly' ? '星期' : '每月哪一天', required: true),
                          if (_kind == 'weekly')
                            _dropdown(
                              key: const Key('recurring-weekday'),
                              value: _weekday,
                              items: kTaskRecurringWeekdays,
                              onChanged: (value) => setState(() {
                                _weekday = value;
                                _error = null;
                              }),
                            )
                          else
                            _dropdown(
                              key: const Key('recurring-month-day'),
                              value: _monthDay,
                              items: kTaskRecurringMonthDays,
                              onChanged: (value) => setState(() {
                                _monthDay = value;
                                _error = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                taskRecurringFrequencyHint(_frequency),
                style: const TextStyle(
                  fontSize: 12,
                  color: DunesColors.text3,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _dateTile(
                      label: '开始日期',
                      value: _startAt,
                      required: true,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateTile(
                      label: '结束日期',
                      value: _endAt,
                      placeholder: '长期有效',
                      optional: true,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE35D6A),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('recurring-create-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: kTaskPurple,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}
