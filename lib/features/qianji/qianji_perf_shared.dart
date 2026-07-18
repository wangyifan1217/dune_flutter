import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 与灯塔 / Tab 一致的主题紫。
abstract final class QianjiPerfTheme {
  static const purple = Color(0xFF7B5CD8);
  static const purpleDeep = Color(0xFF5B3FB0);
  static const purpleMid = Color(0xFF6A67D2);
  static const purpleSoft = Color(0xFFF0ECF6);
  static const purpleLine = Color(0xFFD9D0EF);

  static const overviewGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B7BE0), purple, purpleDeep],
  );
}

enum QianjiPerfFilter {
  all,
  pendingScore,
  running,
  done,
  frontend,
  backend,
  published,
  waitManager,
  waitSelf,
}

class QianjiPerfStat {
  const QianjiPerfStat({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;
}

class QianjiPerfCycle {
  const QianjiPerfCycle({
    required this.title,
    required this.meta,
    required this.score,
    required this.badge,
    required this.running,
    required this.iconLabel,
  });

  final String title;
  final String meta;
  final String score;
  final String badge;
  final bool running;
  final String iconLabel;
}

class QianjiPerfMember {
  const QianjiPerfMember({
    required this.name,
    required this.role,
    required this.score,
    required this.level,
    required this.avatarColor,
  });

  final String name;
  final String role;
  final String score;
  final String level;
  final Color avatarColor;
}

class QianjiMonthlyPerf {
  const QianjiMonthlyPerf({
    required this.monthLabel,
    required this.title,
    required this.meta,
    required this.score,
    required this.level,
    required this.running,
    required this.filterTags,
  });

  final String monthLabel;
  final String title;
  final String meta;
  final String score;
  final String level;
  final bool running;
  final Set<QianjiPerfFilter> filterTags;
}

/// 团队考核 / 我的绩效静态样例（对齐原型）。
abstract final class QianjiPerfCatalog {
  static const teamStats = [
    QianjiPerfStat(label: '团队人数', value: '18', sub: '已完成 12 人'),
    QianjiPerfStat(label: '平均分', value: '86.4', sub: '较上季 ↑2.1'),
    QianjiPerfStat(label: '优秀率', value: '33%', sub: '6人获优秀'),
  ];

  static const teamCycles = [
    QianjiPerfCycle(
      title: '2026年 Q2 季度考核',
      meta: '04/01 — 06/30 · 18人参与',
      score: '86.4',
      badge: '进行中',
      running: true,
      iconLabel: 'Q2',
    ),
    QianjiPerfCycle(
      title: '2026年 Q1 季度考核',
      meta: '01/01 — 03/31 · 16人参与',
      score: '84.3',
      badge: '已完成',
      running: false,
      iconLabel: 'Q1',
    ),
  ];

  static const teamMembers = [
    QianjiPerfMember(
      name: '张伟',
      role: '前端开发 · 高级工程师',
      score: '92.5',
      level: 'S级',
      avatarColor: Color(0xFF2F5D62),
    ),
    QianjiPerfMember(
      name: '李娜',
      role: '后端开发 · 中级工程师',
      score: '88.0',
      level: 'A级',
      avatarColor: Color(0xFF5D8A4E),
    ),
    QianjiPerfMember(
      name: '王磊',
      role: '后端开发 · 高级工程师',
      score: '85.5',
      level: 'A级',
      avatarColor: Color(0xFFB07A2B),
    ),
    QianjiPerfMember(
      name: '赵敏',
      role: '算法工程师 · 高级',
      score: '90.0',
      level: 'S级',
      avatarColor: Color(0xFF3B6E96),
    ),
  ];

  static const myStats = [
    QianjiPerfStat(label: '本年均分', value: '88.2', sub: '1—6 月'),
    QianjiPerfStat(label: '最新等级', value: 'A', sub: '6 月结果'),
    QianjiPerfStat(label: '已公示', value: '6', sub: '个月'),
  ];

  static const monthlyItems = [
    QianjiMonthlyPerf(
      monthLabel: '6月',
      title: '2026 年 6 月 · 月度绩效',
      meta: '自评 87.0 · 主管 88.5 · 已公示',
      score: '88.5',
      level: 'A',
      running: false,
      filterTags: {QianjiPerfFilter.published, QianjiPerfFilter.done},
    ),
    QianjiMonthlyPerf(
      monthLabel: '5月',
      title: '2026 年 5 月 · 月度绩效',
      meta: '自评 86.5 · 主管 87.0 · 已公示',
      score: '87.0',
      level: 'A',
      running: false,
      filterTags: {QianjiPerfFilter.published, QianjiPerfFilter.done},
    ),
    QianjiMonthlyPerf(
      monthLabel: '4月',
      title: '2026 年 4 月 · 月度绩效',
      meta: '自评 85.0 · 主管 86.5 · 已公示',
      score: '86.5',
      level: 'A',
      running: false,
      filterTags: {QianjiPerfFilter.published, QianjiPerfFilter.done},
    ),
    QianjiMonthlyPerf(
      monthLabel: '3月',
      title: '2026 年 3 月 · 月度绩效',
      meta: '自评 84.0 · 主管 85.5 · 已公示',
      score: '85.5',
      level: 'B+',
      running: false,
      filterTags: {QianjiPerfFilter.published, QianjiPerfFilter.done},
    ),
    QianjiMonthlyPerf(
      monthLabel: '2月',
      title: '2026 年 2 月 · 月度绩效',
      meta: '自评 83.5 · 主管评分中',
      score: '',
      level: '',
      running: true,
      filterTags: {QianjiPerfFilter.waitManager, QianjiPerfFilter.running},
    ),
  ];
}

class QianjiPerfNavBar extends StatelessWidget {
  const QianjiPerfNavBar({
    super.key,
    required this.title,
    required this.onBack,
    this.action,
  });

  final String title;
  final VoidCallback onBack;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          Material(
            color: DunesColors.bgSoft,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onBack,
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.chevron_left_rounded, color: DunesColors.text2),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: action == null
                ? const SizedBox.shrink()
                : Text(
                    action!,
                    textAlign: TextAlign.right,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: QianjiPerfTheme.purple,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class QianjiPerfOverviewCard extends StatelessWidget {
  const QianjiPerfOverviewCard({
    super.key,
    required this.label,
    required this.period,
    required this.stats,
    this.linkLabel,
    this.onLinkTap,
  });

  final String label;
  final String period;
  final List<QianjiPerfStat> stats;
  final String? linkLabel;
  final VoidCallback? onLinkTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: QianjiPerfTheme.overviewGradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: -48,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    label,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  if (linkLabel != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onLinkTap,
                      child: Text(
                        linkLabel!,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                period,
                style: DunesTypography.sans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stats[i].label,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stats[i].value,
                            style: DunesTypography.sans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            stats[i].sub,
                            style: DunesTypography.sans(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QianjiPerfFilterChips extends StatelessWidget {
  const QianjiPerfFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(QianjiPerfFilter, String)> options;
  final QianjiPerfFilter selected;
  final ValueChanged<QianjiPerfFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _chip(options[i].$1, options[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _chip(QianjiPerfFilter value, String label) {
    final on = selected == value;
    return Material(
      color: on ? QianjiPerfTheme.purple : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: on ? QianjiPerfTheme.purple : DunesColors.borderSoft,
            ),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              color: on ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class QianjiPerfSectionCard extends StatelessWidget {
  const QianjiPerfSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: QianjiPerfTheme.purple,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
