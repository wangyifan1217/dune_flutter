import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_service.dart';
import 'proposal_intake_ui.dart';

/// 时限状态配色，沿用提案页现有色：琥珀 = 进行中 / 卡点，橙红 = 驳回 / 超时，绿 = 完成。
({Color bg, Color fg, Color solid}) proposalSlaTone(String status) => switch (status) {
  'warning' => (bg: const Color(0xFFFBF1DE), fg: const Color(0xFF8A5A12), solid: const Color(0xFFE3A53A)),
  'overdue' => (bg: const Color(0xFFFBE6DE), fg: const Color(0xFFA93A16), solid: const Color(0xFFC0563F)),
  'exempt' || 'finished' => (bg: const Color(0xFFEEF6F1), fg: const Color(0xFF3B8B5A), solid: const Color(0xFF3B8B5A)),
  _ => (bg: const Color(0xFFEEF2F7), fg: const Color(0xFF4D5A6B), solid: const Color(0xFF6B4FD8)),
};

/// 列表卡底栏右侧的小胶囊，替换「停 N 天」，不增加行高。
class ProposalSlaChip extends StatelessWidget {
  const ProposalSlaChip({super.key, required this.sla});

  final ProposalSlaSummary sla;

  String get _text {
    final node = sla.tightest;
    switch (sla.status) {
      case 'exempt':
        return '已免责';
      case 'finished':
        return sla.overdueCount > 0 ? '已完成 · 超时 ${sla.overdueCount} 次' : '按时完成';
      case 'overdue':
        if (node != null && node.state == 'overdue') {
          return '已超时 ${proposalSlaDuration(node.overdueMinutes)}';
        }
        return '总时长已超时';
      case 'warning':
        return '卡点 · 剩 ${proposalSlaDuration(node?.remainingMinutes ?? 0)}';
      default:
        if (sla.suspended) return '填写中 · 暂停计时';
        return node == null ? sla.totalText : '剩 ${proposalSlaDuration(node.remainingMinutes)}';
    }
  }

  String get _tooltip {
    final lines = <String>[
      '时限：${sla.statusLabel}',
      sla.totalText,
      if (sla.currentStageLabel.isNotEmpty) '当前环节：${sla.currentStageLabel}',
      for (final n in sla.current) '${n.label} · ${n.assigneeName.isEmpty ? n.role : n.assigneeName} · ${n.clockText}',
      if (sla.round > 1) '第 ${sla.round - 1} 次轮回',
      if (sla.paused) '21:00–09:00 节点时钟暂停',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final tone = proposalSlaTone(sla.status);
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    return Tooltip(
      message: _tooltip,
      child: Container(
        key: const ValueKey('proposal-sla-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c(tone.bg, DunesColorRole.surface),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          sla.round > 1 ? '$_text · 轮回${sla.round - 1}' : _text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w700, color: c(tone.fg)),
        ),
      ),
    );
  }
}

/// 细进度条，和列表卡的五段进度条同样高度和圆角。
class _SlaBar extends StatelessWidget {
  const _SlaBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2.5),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: DunesColors.resolve(context, const Color(0xFFE6E3EF), role: DunesColorRole.border)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: DunesColors.resolve(context, color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 详情顶部的时限总览，样式照「被驳回」横幅：左边标签，右边标题和说明，下面两条细进度条。
class ProposalSlaOverview extends StatelessWidget {
  const ProposalSlaOverview({super.key, required this.sla, this.onOpenRecords});

  final ProposalSlaSummary sla;
  final VoidCallback? onOpenRecords;

  @override
  Widget build(BuildContext context) {
    Color c(int v, [DunesColorRole r = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: r);
    final tone = proposalSlaTone(sla.status);
    final tagText = switch (sla.status) {
      'finished' => '已结束',
      _ => sla.statusLabel.isEmpty ? '正常' : sla.statusLabel,
    };
    final meta = [
      if (sla.round > 1) '第 ${sla.round - 1} 次轮回',
      '催办 ${sla.remindCount} 次',
      if (sla.overdueCount > 0) '超时 ${sla.overdueCount} 次',
      if (sla.paused) '21:00–09:00 节点时钟暂停',
      if (sla.suspended) '退回填写中，重新开始复核后接着计时',
    ].join(' · ');
    final hours = (sla.totalLimitMinutes / 60).round();
    return Container(
      key: const ValueKey('proposal-sla-overview'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c(0xFFF7F5FC, DunesColorRole.surface),
        border: Border.all(color: c(0xFFDCD3F5, DunesColorRole.border)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(context, tone.solid, role: DunesColorRole.surface),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '时限 · $tagText',
                        style: TextStyle(color: c(0xFFFFFFFF), fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      sla.totalText,
                      style: TextStyle(color: c(0xFF3F2A9A), fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Text(meta, style: TextStyle(color: c(0xFF5B556A), fontSize: 12)),
                  ],
                ),
              ),
              if (onOpenRecords != null)
                TextButton.icon(
                  key: const ValueKey('proposal-sla-records'),
                  onPressed: onOpenRecords,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('时限记录'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text('总时钟 ${hours}h', style: TextStyle(fontSize: 11, color: c(0xFF8A85A0))),
              ),
              Expanded(
                child: _SlaBar(
                  value: sla.totalProgress,
                  color: sla.totalOverdue ? const Color(0xFFC0563F) : const Color(0xFF4A3A9A),
                ),
              ),
            ],
          ),
          for (final node in sla.current) ...[
            const SizedBox(height: 6),
            _SlaNodeLine(node: node),
          ],
        ],
      ),
    );
  }
}

class _SlaNodeLine extends StatelessWidget {
  const _SlaNodeLine({required this.node});

  final ProposalSlaNode node;

  @override
  Widget build(BuildContext context) {
    Color c(int v) => DunesColors.resolve(context, Color(v));
    final tone = proposalSlaTone(node.state);
    final who = node.assigneeName.isEmpty ? node.role : node.assigneeName;
    final limit = node.limitMinutes <= 0 ? 1 : node.limitMinutes;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(node.stageLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c(0xFF8A85A0))),
        ),
        Expanded(
          flex: 3,
          child: _SlaBar(value: node.effectiveMinutes / limit, color: tone.solid),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Text(
            '${node.label} · $who · ${node.clockText}${node.remindCount > 0 ? ' · 催办 ${node.remindCount}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: node.state == 'normal' ? FontWeight.w500 : FontWeight.w700,
              color: node.state == 'normal'
                  ? c(0xFF4D4860)
                  : DunesColors.resolve(context, tone.fg),
            ),
          ),
        ),
      ],
    );
  }
}

/// 最终驳回记录转成时限记录弹窗里的行，审批人按人员名单取名字。
List<({int round, String name, String date, String comment})> proposalSlaFinalRejections(
  ProposalIntakeRow row,
  List<ProposalPerson> people,
) {
  return [
    for (final record in row.finalRejectionHistory)
      () {
        final actor = '${record['actorUserId'] ?? ''}';
        final match = people.where((p) => '${p.userId}' == actor);
        final name = match.isEmpty ? (actor.isEmpty ? '未知审批人' : '用户 $actor') : match.first.name;
        final rawDate = '${record['decidedAt'] ?? ''}';
        final parsed = DateTime.tryParse(rawDate)?.toLocal();
        return (
          round: int.tryParse('${record['round'] ?? ''}') ?? 0,
          name: name,
          date: parsed == null ? rawDate : parsed.toString().split('.').first,
          comment: '${record['comment'] ?? ''}',
        );
      }(),
  ];
}

/// 时限记录：我的绩效记录（可申诉）、节点轨迹、时间线、最终驳回。
Future<void> showProposalSlaRecords({
  required BuildContext context,
  required ProposalIntakeService service,
  required int proposalId,
  List<({int round, String name, String date, String comment})> finalRejections = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ProposalSlaRecordsDialog(
      service: service,
      proposalId: proposalId,
      finalRejections: finalRejections,
    ),
  );
}

class _ProposalSlaRecordsDialog extends StatefulWidget {
  const _ProposalSlaRecordsDialog({
    required this.service,
    required this.proposalId,
    required this.finalRejections,
  });

  final ProposalIntakeService service;
  final int proposalId;
  final List<({int round, String name, String date, String comment})> finalRejections;

  @override
  State<_ProposalSlaRecordsDialog> createState() => _ProposalSlaRecordsDialogState();
}

class _ProposalSlaRecordsDialogState extends State<_ProposalSlaRecordsDialog> {
  ProposalSlaDetail? _detail;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.service.fetchSla(widget.proposalId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  Future<void> _appeal(ProposalSlaScore score) async {
    final reason = await showProposalRejectDialog(
      context: context,
      title: '发起申诉',
      hint: '请写明申诉理由。提交后由行政人事复核，复核前这条记录不会计入绩效。',
    );
    if (!mounted || reason == null) return;
    if (reason.trim().isEmpty) {
      setState(() => _error = '请填写申诉理由');
      return;
    }
    try {
      final detail = await widget.service.appealSla(
        id: widget.proposalId,
        scoreId: score.id,
        reason: reason.trim(),
      );
      if (!mounted) return;
      setState(() {
        if (detail != null) _detail = detail;
        _error = '';
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('已提交申诉')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorText(e));
    }
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
  );

  Widget _tag(String text, String status) {
    final tone = proposalSlaTone(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, tone.bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
          color: DunesColors.resolve(context, tone.fg))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 11, color: DunesColors.resolve(context, const Color(0xFF8A85A0)));
    final detail = _detail;
    final summary = detail?.summary;
    final children = <Widget>[];
    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (detail == null || summary == null) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('这张提案没有纳入时限管理。'),
      ));
    } else {
      children.add(Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _tag(summary.statusLabel, summary.status),
        Text(summary.totalText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        Text('开始 ${proposalSlaClock(summary.startedAt)}', style: muted),
      ]));
      if (detail.myScores.isNotEmpty) {
        children.add(_sectionTitle('我的时限记录'));
        for (final s in detail.myScores) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.kindLabel}${s.nodeLabel.isEmpty ? '' : ' · ${s.nodeLabel}'} · ${s.pointsText}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text([
                  s.statusLabel,
                  if (s.overdueMinutes > 0) '超时 ${proposalSlaDuration(s.overdueMinutes)}',
                  if (s.appealOpen && s.appealDeadline != null) '${proposalSlaClock(s.appealDeadline)} 前可申诉',
                  if (s.reviewComment.isNotEmpty) '复核意见：${s.reviewComment}',
                ].join(' · '), style: muted),
              ])),
              if (s.appealOpen)
                TextButton(onPressed: () => _appeal(s), child: const Text('申诉')),
            ]),
          ));
        }
      }
      children.add(_sectionTitle('节点轨迹'));
      final rounds = detail.nodes.map((n) => n.round).toSet().toList()..sort((a, b) => b.compareTo(a));
      for (final round in rounds) {
        if (rounds.length > 1) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(round == 1 ? '首轮' : '第 ${round - 1} 次轮回后', style: muted),
          ));
        }
        for (final n in detail.nodes.where((n) => n.round == round)) {
          final who = n.assigneeName.isEmpty ? n.role : n.assigneeName;
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n.stageLabel} · ${n.label} · $who', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text([
                  '开始 ${proposalSlaClock(n.startedAt)}',
                  if (n.endedAt != null) '完成 ${proposalSlaClock(n.endedAt)}',
                  n.clockText,
                  if (n.remindCount > 0) '催办 ${n.remindCount} 次',
                ].join(' · '), style: muted),
              ])),
              _tag(n.open ? n.stateLabel : (n.state == 'overdue' ? '超时完成' : (n.exempt ? '已免责' : '已完成')),
                  n.open ? n.state : (n.state == 'overdue' ? 'overdue' : 'finished')),
            ]),
          ));
        }
      }
      final timeline = detail.timeline.reversed.toList();
      if (timeline.isNotEmpty) {
        children.add(_sectionTitle('时间线'));
        for (final item in timeline) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 82, child: Text(proposalSlaClock(item.at), style: muted)),
              Expanded(child: Text.rich(TextSpan(children: [
                TextSpan(text: '${item.title}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: item.body),
              ]), style: const TextStyle(fontSize: 12.5))),
            ]),
          ));
        }
      }
      final appeals = detail.exemptions.where((e) => e.type == 'appeal').toList();
      if (appeals.isNotEmpty) {
        children.add(_sectionTitle('申诉'));
        for (final a in appeals) {
          final st = switch (a.status) { 'approved' => '申诉成立', 'rejected' => '申诉不成立', _ => '待行政人事复核' };
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${a.applicantName} · $st · ${a.reason}${a.reviewComment.isEmpty ? '' : '（${a.reviewComment}）'}',
                style: const TextStyle(fontSize: 12.5)),
          ));
        }
      }
    }
    if (widget.finalRejections.isNotEmpty) {
      children.add(_sectionTitle('最终驳回'));
      for (final r in widget.finalRejections.reversed) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('第 ${r.round} 次轮回 · ${r.name}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (r.date.isNotEmpty) Text(r.date, style: muted),
            SelectableText(r.comment, style: const TextStyle(fontSize: 13)),
          ]),
        ));
      }
    }
    if (_error.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_error, style: TextStyle(color: DunesColors.resolve(context, const Color(0xFFA93A16)))),
      ));
    }
    return AlertDialog(
      title: const Text('时限记录'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  }
}
