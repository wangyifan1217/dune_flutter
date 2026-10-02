import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../tasks/task_widgets.dart';

const _themePurple = Color(0xFF7B5CD8);
const _warn = Color(0xFFB45309);

enum QianjiLookupKind { groupReply, monthlyOpinion, proposalReview }

/// 群响应、月结意见、提案审核的样例查阅页。筛选只作用于本页样例。
class NativeQianjiLookupPreviewPage extends StatefulWidget {
  const NativeQianjiLookupPreviewPage({
    super.key,
    required this.kind,
    required this.onBack,
    this.initialFrom,
    this.initialTo,
  });

  final QianjiLookupKind kind;
  final VoidCallback onBack;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<NativeQianjiLookupPreviewPage> createState() =>
      _NativeQianjiLookupPreviewPageState();
}

class _LookupLine {
  const _LookupLine({
    required this.bucket,
    required this.bucketMeta,
    required this.chip,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.date,
    required this.tone,
  });

  final String bucket;
  final String bucketMeta;
  final String chip;
  final String title;
  final String subtitle;
  final String trailing;
  final DateTime date;

  /// pending / done / bad
  final String tone;
}

class _NativeQianjiLookupPreviewPageState
    extends State<NativeQianjiLookupPreviewPage> {
  static final _groupReplies = <_LookupLine>[
    _LookupLine(
      bucket: '华东销售群',
      bucketMeta: '工作群',
      chip: '华东销售群',
      title: '赵敏 · 被林嘉宁 @',
      subtitle: '合同节点请今天确认',
      trailing: '已读未回复 6 小时',
      date: DateTime(2026, 9, 12),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '华东销售群',
      bucketMeta: '工作群',
      chip: '华东销售群',
      title: '林嘉宁 · 已回复赵敏',
      subtitle: '已按清单核对开票名单',
      trailing: '已回复 · 用时 22 分钟',
      date: DateTime(2026, 9, 18),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '研发值班群',
      bucketMeta: '工作群',
      chip: '研发值班群',
      title: '孙浩 · 被周致远 @',
      subtitle: '日报漏填提醒还没关',
      trailing: '已读未回复 1 天',
      date: DateTime(2026, 9, 20),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '研发值班群',
      bucketMeta: '工作群',
      chip: '研发值班群',
      title: '周致远 · 已回复孙浩',
      subtitle: '空态文案已补上',
      trailing: '已回复 · 用时 40 分钟',
      date: DateTime(2026, 9, 25),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '财务月结群',
      bucketMeta: '工作群',
      chip: '财务月结群',
      title: '王强 · 被陈丽 @',
      subtitle: '进项差异请说明原因',
      trailing: '未读 3 小时',
      date: DateTime(2026, 9, 8),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '财务月结群',
      bucketMeta: '工作群',
      chip: '财务月结群',
      title: '陈丽 · 已回复王强',
      subtitle: '差异已挂到 9 月供给单',
      trailing: '已回复 · 用时 1 小时',
      date: DateTime(2026, 9, 15),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '运营协同群',
      bucketMeta: '工作群',
      chip: '运营协同群',
      title: '王强 · 被赵敏 @',
      subtitle: '门店巡检问题请回一句',
      trailing: '已读未回复 2 天',
      date: DateTime(2026, 10, 3),
      tone: 'pending',
    ),
  ];

  static final _opinions = <_LookupLine>[
    _LookupLine(
      bucket: '9月5日 · 渠道月结',
      bucketMeta: '应收 · 华东',
      chip: '渠道',
      title: '林嘉宁 · 已确认',
      subtitle: '金额与对账清单一致',
      trailing: '已确认',
      date: DateTime(2026, 9, 5),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '9月5日 · 渠道月结',
      bucketMeta: '应收 · 华东',
      chip: '渠道',
      title: '陈丽 · 待确认',
      subtitle: '财务还没写确认意见',
      trailing: '待确认',
      date: DateTime(2026, 9, 5),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '9月12日 · 供给月结',
      bucketMeta: '应付 · 供给',
      chip: '供给',
      title: '王强 · 有异议',
      subtitle: '供给差异 1.2 万还没说明',
      trailing: '有异议',
      date: DateTime(2026, 9, 12),
      tone: 'bad',
    ),
    _LookupLine(
      bucket: '9月12日 · 供给月结',
      bucketMeta: '应付 · 供给',
      chip: '供给',
      title: '赵敏 · 已确认',
      subtitle: '业务侧同意按对账金额入账',
      trailing: '已确认',
      date: DateTime(2026, 9, 12),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '9月20日 · 油品月结',
      bucketMeta: '应收 · 油品',
      chip: '油品',
      title: '周致远 · 待确认',
      subtitle: '系统数和台账还差一笔运费',
      trailing: '待确认',
      date: DateTime(2026, 9, 20),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '9月20日 · 油品月结',
      bucketMeta: '应收 · 油品',
      chip: '油品',
      title: '孙浩 · 已确认',
      subtitle: '运费差异下月调整，本月先确认',
      trailing: '已确认',
      date: DateTime(2026, 9, 20),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '10月3日 · 渠道月结',
      bucketMeta: '应收 · 华东',
      chip: '渠道',
      title: '林嘉宁 · 待确认',
      subtitle: '10 月账单刚生成',
      trailing: '待确认',
      date: DateTime(2026, 10, 3),
      tone: 'pending',
    ),
  ];

  static final _proposals = <_LookupLine>[
    _LookupLine(
      bucket: '华东柴油采购',
      bucketMeta: '销售部 · 林嘉宁',
      chip: '市场',
      title: '市场部 · 已填写',
      subtitle: '规模、渠道和合同要点已填完',
      trailing: '已填写',
      date: DateTime(2026, 9, 6),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '华东柴油采购',
      bucketMeta: '销售部 · 林嘉宁',
      chip: '科技',
      title: '科技部 · 待审核',
      subtitle: '周致远尚未复核科技字段',
      trailing: '待审核',
      date: DateTime(2026, 9, 10),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '华东柴油采购',
      bucketMeta: '销售部 · 林嘉宁',
      chip: '财务',
      title: '财务部 · 已驳回',
      subtitle: '陈丽：缺财务技术接口',
      trailing: '已驳回',
      date: DateTime(2026, 9, 14),
      tone: 'bad',
    ),
    _LookupLine(
      bucket: '华东柴油采购',
      bucketMeta: '销售部 · 林嘉宁',
      chip: '合同',
      title: '合同 · 未开始',
      subtitle: '财务驳回后合同审核还没打开',
      trailing: '未开始',
      date: DateTime(2026, 9, 14),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '渠道开票调整',
      bucketMeta: '销售部 · 赵敏',
      chip: '市场',
      title: '市场部 · 已填写',
      subtitle: '开票名单和结算口径已提交',
      trailing: '已填写',
      date: DateTime(2026, 9, 9),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '渠道开票调整',
      bucketMeta: '销售部 · 赵敏',
      chip: '科技',
      title: '科技部 · 已通过',
      subtitle: '孙浩已复核业务平台产品',
      trailing: '已通过',
      date: DateTime(2026, 9, 18),
      tone: 'done',
    ),
    _LookupLine(
      bucket: '渠道开票调整',
      bucketMeta: '销售部 · 赵敏',
      chip: '财务',
      title: '财务部 · 待审核',
      subtitle: '陈丽还没审财务板块',
      trailing: '待审核',
      date: DateTime(2026, 9, 19),
      tone: 'pending',
    ),
    _LookupLine(
      bucket: '10月油品补充',
      bucketMeta: '运营部 · 王强',
      chip: '市场',
      title: '市场部 · 填写中',
      subtitle: '规模还没填完',
      trailing: '填写中',
      date: DateTime(2026, 10, 4),
      tone: 'pending',
    ),
  ];

  late DateTime _from;
  late DateTime _to;
  String? _chip;

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

  List<_LookupLine> get _source => switch (widget.kind) {
    QianjiLookupKind.groupReply => _groupReplies,
    QianjiLookupKind.monthlyOpinion => _opinions,
    QianjiLookupKind.proposalReview => _proposals,
  };

  List<String> get _chips => switch (widget.kind) {
    QianjiLookupKind.groupReply => ['华东销售群', '研发值班群', '财务月结群', '运营协同群'],
    QianjiLookupKind.monthlyOpinion => ['渠道', '供给', '油品'],
    QianjiLookupKind.proposalReview => ['市场', '科技', '财务', '合同'],
  };

  String get _title => switch (widget.kind) {
    QianjiLookupKind.groupReply => '群响应',
    QianjiLookupKind.monthlyOpinion => '月结意见',
    QianjiLookupKind.proposalReview => '提案审核',
  };

  String get _hint => switch (widget.kind) {
    QianjiLookupKind.groupReply => '工作群里被 @ 后的已读和回复',
    QianjiLookupKind.monthlyOpinion => '按月结日期看确认意见',
    QianjiLookupKind.proposalReview => '提案各板块的填写和审核',
  };

  String get _chipLabel => switch (widget.kind) {
    QianjiLookupKind.groupReply => '工作群',
    QianjiLookupKind.monthlyOpinion => '类型',
    QianjiLookupKind.proposalReview => '板块',
  };

  String get _allChip => switch (widget.kind) {
    QianjiLookupKind.groupReply => '全部工作群',
    QianjiLookupKind.monthlyOpinion => '全部类型',
    QianjiLookupKind.proposalReview => '全部板块',
  };

  String get _emptyText => switch (widget.kind) {
    QianjiLookupKind.groupReply => '这个范围内没有回复记录',
    QianjiLookupKind.monthlyOpinion => '这个范围内没有确认意见',
    QianjiLookupKind.proposalReview => '这个范围内没有提案进度',
  };

  List<_LookupLine> get _visible => _source
      .where(
        (line) => _inRange(line.date) && (_chip == null || line.chip == _chip),
      )
      .toList(growable: false);

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
    final groups = _groups();
    return Material(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF7F6FA),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(groups.length),
            _filters(),
            _summary(),
            Expanded(
              child: groups.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(
                            _emptyText,
                            style: TextStyle(
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => groups[index],
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
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onBack,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new,
                    size: 14,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                  SizedBox(width: 2),
                  Text(
                    '饕',
                    style: TextStyle(
                      fontSize: 13,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, _themePurple),
              ),
            ),
          ),
          Text(
            count == 0 ? '样例' : '$count 组 · 样例',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text2),
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
            _hint,
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '时间',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: _rangeLabel,
                selected: true,
                onTap: _pickRange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _chipLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          const SizedBox(height: 8),
          HorizontalDragScrollView(
            child: Row(
              children: [
                _FilterChip(
                  label: _allChip,
                  selected: _chip == null,
                  onTap: () => setState(() => _chip = null),
                ),
                const SizedBox(width: 8),
                for (final name in _chips) ...[
                  _FilterChip(
                    label: name,
                    selected: _chip == name,
                    onTap: () => setState(() => _chip = name),
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

  Widget _summary() {
    final lines = _visible;
    final pending = lines.where((line) => line.tone == 'pending').length;
    final done = lines.where((line) => line.tone == 'done').length;
    final bad = lines.where((line) => line.tone == 'bad').length;
    final cells = switch (widget.kind) {
      QianjiLookupKind.groupReply => [
        ('$pending', '未回复'),
        ('$done', '已回复'),
        ('${lines.map((line) => line.bucket).toSet().length}', '工作群'),
      ],
      QianjiLookupKind.monthlyOpinion => [
        ('$pending', '待确认'),
        ('$done', '已确认'),
        ('$bad', '有异议'),
      ],
      QianjiLookupKind.proposalReview => [
        ('$done', '已填写或通过'),
        ('$pending', '待处理'),
        ('$bad', '已驳回'),
      ],
    };
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
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolveNullable(context, _warn),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _groups() {
    final grouped = <String, List<_LookupLine>>{};
    for (final line in _visible) {
      grouped.putIfAbsent(line.bucket, () => []).add(line);
    }
    return [
      for (final entry in grouped.entries)
        _bucketCard(
          title: entry.key,
          meta: entry.value.first.bucketMeta,
          lines: entry.value,
        ),
    ];
  }

  Widget _bucketCard({
    required String title,
    required String meta,
    required List<_LookupLine> lines,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, DunesColors.text),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            meta,
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _line(lines[i]),
          ],
        ],
      ),
    );
  }

  Widget _line(_LookupLine line) {
    final color = switch (line.tone) {
      'done' => DunesColors.resolve(context, const Color(0xFF1F9D76)),
      'bad' => DunesColors.resolve(context, const Color(0xFFD4380D)),
      _ => DunesColors.resolve(context, _warn),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                line.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          line.trailing,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolveNullable(context, color),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
      color: selected
          ? DunesColors.resolve(
              context,
              const Color(0xFFF3EEFF),
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      _themePurple,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFE8EAED),
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? DunesColors.resolve(context, _themePurple)
                  : DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ),
      ),
    );
  }
}
