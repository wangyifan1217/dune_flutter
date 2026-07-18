import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_perf_shared.dart';

/// 团队考核静态页（原生 Flutter）。
class NativeQianjiTeamPerfPage extends StatefulWidget {
  const NativeQianjiTeamPerfPage({
    super.key,
    required this.onBack,
    this.onOpenMyPerf,
  });

  final VoidCallback onBack;
  final VoidCallback? onOpenMyPerf;

  @override
  State<NativeQianjiTeamPerfPage> createState() =>
      _NativeQianjiTeamPerfPageState();
}

class _NativeQianjiTeamPerfPageState extends State<NativeQianjiTeamPerfPage> {
  QianjiPerfFilter _filter = QianjiPerfFilter.all;

  List<QianjiPerfMember> get _members {
    switch (_filter) {
      case QianjiPerfFilter.frontend:
        return QianjiPerfCatalog.teamMembers
            .where((m) => m.role.contains('前端'))
            .toList(growable: false);
      case QianjiPerfFilter.backend:
        return QianjiPerfCatalog.teamMembers
            .where((m) => m.role.contains('后端'))
            .toList(growable: false);
      case QianjiPerfFilter.pendingScore:
      case QianjiPerfFilter.running:
      case QianjiPerfFilter.waitManager:
      case QianjiPerfFilter.waitSelf:
      case QianjiPerfFilter.published:
        return const [];
      case QianjiPerfFilter.done:
      case QianjiPerfFilter.all:
        return QianjiPerfCatalog.teamMembers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;

    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            QianjiPerfNavBar(
              title: '团队考核',
              onBack: widget.onBack,
              action: '导出',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  QianjiPerfOverviewCard(
                    label: '2026年 研发团队绩效',
                    period: 'Q2 考核周期',
                    stats: QianjiPerfCatalog.teamStats,
                    linkLabel: '我的绩效 ›',
                    onLinkTap: widget.onOpenMyPerf,
                  ),
                  const SizedBox(height: 12),
                  QianjiPerfFilterChips(
                    selected: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                    options: const [
                      (QianjiPerfFilter.all, '全部'),
                      (QianjiPerfFilter.pendingScore, '待评分'),
                      (QianjiPerfFilter.running, '进行中'),
                      (QianjiPerfFilter.done, '已完成'),
                      (QianjiPerfFilter.frontend, '前端组'),
                      (QianjiPerfFilter.backend, '后端组'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  QianjiPerfSectionCard(
                    title: '考核周期',
                    trailing: '查看历史',
                    child: Column(
                      children: [
                        for (final c in QianjiPerfCatalog.teamCycles)
                          _CycleRow(cycle: c),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  QianjiPerfSectionCard(
                    title: '本期完成进度',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: const [
                          Expanded(
                            child: _ProgressRing(
                              percent: 0.70,
                              value: '70%',
                              label: '自评完成',
                              color: QianjiPerfTheme.purple,
                            ),
                          ),
                          Expanded(
                            child: _ProgressRing(
                              percent: 0.50,
                              value: '50%',
                              label: '主管评分',
                              color: DunesColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  QianjiPerfSectionCard(
                    title: '研发人员',
                    trailing: '排行榜',
                    child: members.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                '当前筛选暂无人员',
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final m in members) _MemberRow(member: m),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleRow extends StatelessWidget {
  const _CycleRow({required this.cycle});

  final QianjiPerfCycle cycle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cycle.running
                  ? QianjiPerfTheme.purpleSoft
                  : DunesColors.greenSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              cycle.iconLabel,
              style: DunesTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cycle.running
                    ? QianjiPerfTheme.purple
                    : DunesColors.green,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cycle.title,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cycle.meta,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                cycle.score,
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: QianjiPerfTheme.purple,
                ),
              ),
              const SizedBox(height: 4),
              _Badge(cycle.badge, running: cycle.running),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final QianjiPerfMember member;

  @override
  Widget build(BuildContext context) {
    final isS = member.level.startsWith('S');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: member.avatarColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              member.name.length <= 2
                  ? member.name
                  : member.name.substring(0, 2),
              style: DunesTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.role,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                member.score,
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isS ? QianjiPerfTheme.purple : DunesColors.green,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isS ? QianjiPerfTheme.purpleSoft : DunesColors.greenSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  member.level,
                  style: DunesTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isS ? QianjiPerfTheme.purple : DunesColors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.running});

  final String text;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: running ? DunesColors.amberSoft : DunesColors.greenSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: running ? DunesColors.amber : DunesColors.green,
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.percent,
    required this.value,
    required this.label,
    required this.color,
  });

  final double percent;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: percent,
                strokeWidth: 6,
                backgroundColor: DunesColors.bgSoft,
                color: color,
              ),
              Text(
                value,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: DunesTypography.sans(fontSize: 11, color: DunesColors.text2),
        ),
      ],
    );
  }
}
