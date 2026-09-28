import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../tasks/task_widgets.dart';

const _themePurple = Color(0xFF7B5CD8);

enum QianjiMonitorPreviewKind { task, dailyReport }

/// 千机业务查阅的任务 / 日报监控样例页。筛选只作用于本页样例，不请求接口。
class NativeQianjiMonitorPreviewPage extends StatefulWidget {
  const NativeQianjiMonitorPreviewPage({
    super.key,
    required this.kind,
    required this.onBack,
    this.initialFrom,
    this.initialTo,
  });

  final QianjiMonitorPreviewKind kind;
  final VoidCallback onBack;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<NativeQianjiMonitorPreviewPage> createState() =>
      _NativeQianjiMonitorPreviewPageState();
}

class _SubtaskSample {
  const _SubtaskSample({
    required this.owner,
    required this.department,
    required this.title,
    required this.parentTitle,
    required this.due,
  });

  final String owner;
  final String department;
  final String title;
  final String parentTitle;
  final DateTime due;
}

class _MissingSample {
  const _MissingSample({
    required this.owner,
    required this.department,
    required this.dates,
  });

  final String owner;
  final String department;
  final List<DateTime> dates;
}

class _NativeQianjiMonitorPreviewPageState
    extends State<NativeQianjiMonitorPreviewPage> {
  static final _subtasks = <_SubtaskSample>[
    _SubtaskSample(
      owner: '林嘉宁',
      department: '销售部',
      title: '跟进华东柴油合同',
      parentTitle: 'Q3 销售回款',
      due: DateTime(2026, 9, 12),
    ),
    _SubtaskSample(
      owner: '林嘉宁',
      department: '销售部',
      title: '补齐客户对账明细',
      parentTitle: 'Q3 销售回款',
      due: DateTime(2026, 9, 18),
    ),
    _SubtaskSample(
      owner: '赵敏',
      department: '销售部',
      title: '确认渠道开票名单',
      parentTitle: '渠道月度复盘',
      due: DateTime(2026, 9, 9),
    ),
    _SubtaskSample(
      owner: '赵敏',
      department: '销售部',
      title: '回收华东未回款说明',
      parentTitle: 'Q3 销售回款',
      due: DateTime(2026, 9, 21),
    ),
    _SubtaskSample(
      owner: '周致远',
      department: '研发部',
      title: '修复日报漏填提醒',
      parentTitle: '任务中心稳定性',
      due: DateTime(2026, 9, 20),
    ),
    _SubtaskSample(
      owner: '孙浩',
      department: '研发部',
      title: '补齐任务详情空态',
      parentTitle: '任务中心稳定性',
      due: DateTime(2026, 9, 25),
    ),
    _SubtaskSample(
      owner: '陈丽',
      department: '财务部',
      title: '完成 9 月进项核对',
      parentTitle: '月结关账',
      due: DateTime(2026, 9, 15),
    ),
    _SubtaskSample(
      owner: '王强',
      department: '运营部',
      title: '整理门店巡检问题',
      parentTitle: '门店运营周报',
      due: DateTime(2026, 9, 11),
    ),
    _SubtaskSample(
      owner: '王强',
      department: '运营部',
      title: '回访逾期客户',
      parentTitle: '门店运营周报',
      due: DateTime(2026, 9, 19),
    ),
    _SubtaskSample(
      owner: '陈丽',
      department: '财务部',
      title: '整理下月预算草稿',
      parentTitle: '月结关账',
      due: DateTime(2026, 10, 8),
    ),
  ];

  static final _missing = <_MissingSample>[
    _MissingSample(
      owner: '林嘉宁',
      department: '销售部',
      dates: [DateTime(2026, 9, 16), DateTime(2026, 9, 17)],
    ),
    _MissingSample(
      owner: '周致远',
      department: '研发部',
      dates: [DateTime(2026, 9, 22)],
    ),
    _MissingSample(
      owner: '陈丽',
      department: '财务部',
      dates: [DateTime(2026, 9, 8), DateTime(2026, 10, 3)],
    ),
    _MissingSample(
      owner: '王强',
      department: '运营部',
      dates: [
        DateTime(2026, 9, 4),
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 18),
      ],
    ),
    _MissingSample(
      owner: '赵敏',
      department: '销售部',
      dates: [DateTime(2026, 9, 23)],
    ),
    _MissingSample(
      owner: '孙浩',
      department: '研发部',
      dates: [DateTime(2026, 9, 25)],
    ),
  ];

  static const _departments = ['销售部', '研发部', '财务部', '运营部'];

  late DateTime _from;
  late DateTime _to;
  String? _department;

  bool get _isTask => widget.kind == QianjiMonitorPreviewKind.task;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = _day(widget.initialFrom ?? DateTime(now.year, now.month, 1));
    _to = _day(widget.initialTo ?? DateTime(now.year, now.month + 1, 0));
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  bool _inRange(DateTime value) {
    final day = _day(value);
    return !day.isBefore(_from) && !day.isAfter(_to);
  }

  bool _inDept(String department) =>
      _department == null || _department == department;

  String get _rangeLabel {
    String fmt(DateTime value, {required bool withYear}) {
      return withYear
          ? '${value.year}/${value.month}/${value.day}'
          : '${value.month}/${value.day}';
    }

    final sameYear = _from.year == _to.year;
    return '${fmt(_from, withYear: true)}–${fmt(_to, withYear: !sameYear)}';
  }

  Future<void> _pickRange() async {
    final picked = await showTaskDateRangePicker(
      context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: '选择时间',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _from = _day(picked.start);
      _to = _day(picked.end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final people = _isTask ? _taskPeople() : _reportPeople();
    return Material(
      color: const Color(0xFFF7F6FA),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(people.length),
            _filters(),
            _summary(),
            Expanded(
              child: people.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemCount: people.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => people[index],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
      child: Row(
        children: [
          InkWell(
            key: const Key('monitor-back'),
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onBack,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new,
                    size: 14,
                    color: DunesColors.text2,
                  ),
                  SizedBox(width: 2),
                  Text(
                    '饕',
                    style: TextStyle(fontSize: 13, color: DunesColors.text2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isTask ? '任务' : '日报',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          Text(
            count == 0 ? '样例' : '$count 人 · 样例',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isTask ? '只看逾期还没办结的子任务' : '所选时间内还没交的人',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                '时间',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _FilterChip(
                    key: const Key('monitor-date-range'),
                    label: _rangeLabel,
                    selected: true,
                    onTap: _pickRange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '部门',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 8),
          HorizontalDragScrollView(
            child: Row(
              children: [
                _FilterChip(
                  key: const Key('monitor-dept-all'),
                  label: '全部部门',
                  selected: _department == null,
                  onTap: () => setState(() => _department = null),
                ),
                const SizedBox(width: 8),
                for (final name in _departments) ...[
                  _FilterChip(
                    key: Key('monitor-dept-$name'),
                    label: name,
                    selected: _department == name,
                    onTap: () => setState(() => _department = name),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_SubtaskSample> get _visibleSubtasks => _subtasks
      .where((item) => _inDept(item.department) && _inRange(item.due))
      .toList(growable: false);

  List<_MissingSample> get _visibleMissing => [
    for (final item in _missing)
      if (_inDept(item.department))
        _MissingSample(
          owner: item.owner,
          department: item.department,
          dates: item.dates.where(_inRange).toList(growable: false),
        ),
  ].where((item) => item.dates.isNotEmpty).toList(growable: false);

  int _lateDays(DateTime due) {
    final days = _day(DateTime.now()).difference(_day(due)).inDays;
    return days < 0 ? 0 : days;
  }

  Widget _summary() {
    final cells = _isTask
        ? <(String, String)>[
            ('${_visibleSubtasks.length}', '逾期子任务'),
            (
              '${_visibleSubtasks.map((item) => item.owner).toSet().length}',
              '涉及人数',
            ),
            (
              '${_visibleSubtasks.map((item) => item.parentTitle).toSet().length}',
              '主目标',
            ),
          ]
        : <(String, String)>[
            ('${_visibleMissing.length}', '未交人数'),
            (
              '${_visibleMissing.fold<int>(0, (sum, item) => sum + item.dates.length)}',
              '未交天数',
            ),
            (
              '${_visibleMissing.map((item) => item.department).toSet().length}',
              '涉及部门',
            ),
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _statCell(cells[i].$1, cells[i].$2)),
          ],
        ],
      ),
    );
  }

  Widget _statCell(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB45309),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _taskPeople() {
    final grouped = <String, List<_SubtaskSample>>{};
    for (final item in _visibleSubtasks) {
      grouped.putIfAbsent(item.owner, () => []).add(item);
    }
    return [
      for (final entry in grouped.entries)
        _personCard(
          name: entry.key,
          department: entry.value.first.department,
          badge: '${entry.value.length} 条',
          children: [
            for (final item in entry.value)
              _detailLine(
                title: item.title,
                subtitle: '主目标 · ${item.parentTitle}',
                trailing:
                    '截止 ${item.due.month}/${item.due.day} · 逾期 ${_lateDays(item.due)} 天',
              ),
          ],
        ),
    ];
  }

  List<Widget> _reportPeople() {
    return [
      for (final row in _visibleMissing)
        _personCard(
          name: row.owner,
          department: row.department,
          badge: '未交 ${row.dates.length} 天',
          children: [
            for (final date in row.dates)
              _detailLine(
                title: '${date.month}月${date.day}日',
                subtitle: '工作日未提交日报',
                trailing: '未交',
              ),
          ],
        ),
    ];
  }

  Widget _personCard({
    required String name,
    required String department,
    required String badge,
    required List<Widget> children,
  }) {
    return Material(
      key: Key('monitor-person-$name'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$name · $department',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailLine({
    required String title,
    required String subtitle,
    required String trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          trailing,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFFB45309),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(
            _isTask ? '这个范围内没有逾期子任务' : '这个范围内都已提交',
            style: const TextStyle(color: DunesColors.text3, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF3EEFF) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _themePurple : const Color(0xFFE8EAED),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? _themePurple : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
