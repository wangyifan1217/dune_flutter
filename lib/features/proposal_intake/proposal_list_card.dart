import 'package:flutter/material.dart';

import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'proposal_estimate_summary.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_ui.dart';
import 'proposal_sla_widgets.dart';

/// 销售提案列表的一张卡：照灯塔的产品卡排版。
///
/// ┌──────────────┬────────────┬────────────┐
/// │ 01 标签一     │ 产品  3个  │ 收入 0.975 │
/// │ 能源 新增     │ 年化规模 … │ 标签三 …   │
/// │ 提案名称 …  › │ 项目 …     │ 周转资金 … │
/// ├──────────────┴────────────┴────────────┤
/// │ 复核 3/5  ▬▬▬▬▬▬▬▬▬▬  财务部·待某某复核  停 4 天 │
/// └────────────────────────────────────────┘
///
/// 左：编号 + 标签一（产品）+ 小标签 + 提案名称；中：科技部的产品数据；右：财务部的收入与成本；
/// 底：复核进度条（提交 → 市场部 → 科技部 → 财务部 → 最终确认），卡在谁、停了几天。
class ProposalListCardMetric {
  const ProposalListCardMetric({
    required this.label,
    required this.value,
    this.unit = '',
    this.tag = '',
    this.warn = false,
    this.mono = false,
    this.wrap = false,
  });

  /// 文字类的值（标签一、标签三、项目名）：小一号、最多两行，放得下。
  final bool wrap;

  final String label;
  final String value;
  final String unit;

  /// 右上角小字（位置和灯塔的涨跌幅一样），如「待建品」「核销」「30 次」。
  final String tag;
  final bool warn;
  final bool mono;
}

enum ProposalListStepState { done, now, todo, rejected }

class ProposalListStep {
  const ProposalListStep(this.label, this.state);

  final String label;
  final ProposalListStepState state;
}

/// 把提案详情「审批进度」的每一步（[proposalIntakeProgressSteps]，列表和详情同一份）
/// 归成五段：提交 → 市场部 → 科技部 → 财务部 → 最终确认。
/// 一段里有驳回就红、有进行中就琥珀、全部通过才紫，其余灰。
List<ProposalListStep> proposalReviewSegments(
  List<ProposalIntakeProgressStep> steps,
) {
  const groups = <(String, Set<String>)>[
    ('提交', {'initiate', 'fill_tech', 'fill_finance_interface', 'start_review'}),
    ('市场部', {'review_market'}),
    ('科技部', {'review_tech'}),
    ('财务部', {'review_contract', 'review_finance_module'}),
    ('最终确认', {'notify_president', 'president', 'end'}),
  ];
  return [
    for (final (label, ids) in groups)
      if (steps.any((step) => ids.contains(step.id)))
        () {
          final members = [
            for (final step in steps)
              if (ids.contains(step.id)) step,
          ];
          final state =
              members.any((s) => s.state == ProposalIntakeProgressState.rejected)
              ? ProposalListStepState.rejected
              : members.any((s) => s.state == ProposalIntakeProgressState.current)
              ? ProposalListStepState.now
              : members.every((s) => s.state == ProposalIntakeProgressState.done)
              ? ProposalListStepState.done
              : ProposalListStepState.todo;
          return ProposalListStep(label, state);
        }(),
  ];
}

/// 进度条下面那句：现在卡在谁、在做什么。和详情「审批进度」同一份数据。
String proposalReviewNowText(List<ProposalIntakeProgressStep> steps) {
  String verb(String id) => switch (id) {
    'initiate' => '填写',
    'fill_tech' => '补全科技与产品',
    'fill_finance_interface' => '填财务技术接口',
    'start_review' => '提交复核',
    'notify_president' => '通知最终人',
    'president' => '最终确认',
    _ => '复核',
  };
  final parts = [
    for (final step in steps)
      if (step.state == ProposalIntakeProgressState.rejected)
        '${step.role.isEmpty ? step.title : step.role}已驳回'
      else if (step.state == ProposalIntakeProgressState.current)
        step.name.isEmpty || step.name == '未指定'
            ? '待${step.role}${verb(step.id)}'
            : '待${step.name}${verb(step.id)}',
  ];
  if (parts.isEmpty) {
    final finished = steps.any(
      (s) => s.id == 'end' && s.state == ProposalIntakeProgressState.done,
    );
    return finished ? '已完成' : '';
  }
  return parts.toSet().join('、');
}

/// 当前这一步已经停了多久（取进行中 / 驳回的步骤里最久的）。
Duration? proposalReviewWaited(List<ProposalIntakeProgressStep> steps) {
  Duration? out;
  for (final step in steps) {
    final waited = step.waited();
    if (waited == null) continue;
    if (out == null || waited > out) out = waited;
  }
  return out;
}

/// 「停 4 天」「停 5 小时」。
String proposalReviewWaitedLabel(Duration? waited) {
  if (waited == null) return '';
  if (waited.inDays >= 1) return '停 ${waited.inDays} 天';
  if (waited.inHours >= 1) return '停 ${waited.inHours} 小时';
  return '刚到';
}

/// 五段进度条（列表卡片底部、详情「审批进度」顶部共用）。
class ProposalReviewSegments extends StatelessWidget {
  const ProposalReviewSegments({
    super.key,
    required this.steps,
    this.showLabels = true,
    this.height = 5,
  });

  final List<ProposalListStep> steps;
  final bool showLabels;
  final double height;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    Color bar(ProposalListStepState s) => switch (s) {
      ProposalListStepState.done => c(const Color(0xFF4A3A9A)),
      ProposalListStepState.now => c(const Color(0xFFE3A53A)),
      ProposalListStepState.rejected => c(const Color(0xFFC0563F)),
      ProposalListStepState.todo => c(const Color(0xFFE6E3EF), DunesColorRole.border),
    };
    Color text(ProposalListStepState s) => switch (s) {
      ProposalListStepState.done => c(const Color(0xFF4D4860)),
      ProposalListStepState.now => c(const Color(0xFF8A5A12)),
      ProposalListStepState.rejected => c(const Color(0xFFB0412A)),
      ProposalListStepState.todo => c(const Color(0xFF9C97B0)),
    };
    String label(ProposalListStep s) => switch (s.state) {
      ProposalListStepState.done => '${s.label} ✓',
      ProposalListStepState.rejected => '${s.label} 驳回',
      _ => s.label,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Tooltip(
                  message: label(steps[i]),
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: bar(steps[i].state),
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (showLabels) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              for (final step in steps)
                Expanded(
                  child: Text(
                    label(step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      fontWeight: step.state == ProposalListStepState.now ||
                              step.state == ProposalListStepState.rejected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: text(step.state),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class ProposalListCardData {
  const ProposalListCardData({
    required this.index,
    required this.tag1,
    required this.name,
    this.chips = const [],
    this.rating = '',
    this.scale = '—',
    this.mid = const [],
    this.right = const [],
    this.steps = const [],
    this.nowText = '',
    this.days = '',
    this.daysWarn = false,
    this.sla,
  });

  /// 时限管理摘要；有时，底栏右侧用时限胶囊替换「停 N 天」。
  final ProposalSlaSummary? sla;

  /// 从 0 开始，显示 01、02。
  final int index;
  final String tag1;
  final String name;
  final List<String> chips;
  final String rating;
  final String scale;
  final List<ProposalListCardMetric> mid;
  final List<ProposalListCardMetric> right;
  final List<ProposalListStep> steps;

  /// 进度条下面一句：「财务部 · 待刘雨滴复核」。
  final String nowText;

  /// 右边小胶囊：「停 4 天」「10-12 完成」。
  final String days;
  final bool daysWarn;
}

class ProposalListCard extends StatelessWidget {
  const ProposalListCard({
    super.key,
    required this.data,
    this.onTap,
    this.more,
  });

  final ProposalListCardData data;
  final VoidCallback? onTap;

  /// 右上角「⋯」更多操作。
  final Widget? more;

  static const _accent = Color(0xFF4A3A9A);
  static const _ink = Color(0xFF1F1B2E);
  static const _text2 = Color(0xFF6B6680);
  static const _text3 = Color(0xFF8A85A0);

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    TextStyle sans(double size, {Color color = _ink, FontWeight? weight}) =>
        TextStyle(fontSize: size, height: 1.3, color: c(color), fontWeight: weight);
    TextStyle mono(double size, {Color color = _ink, FontWeight? weight}) =>
        TextStyle(
          fontSize: size,
          height: 1.3,
          color: c(color),
          fontWeight: weight,
          fontFamily: kProposalProtoMono,
          fontFamilyFallback: kProposalProtoMonoFallback,
        );

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final no = (data.index + 1).toString().padLeft(2, '0');

        // ---- 左列 ----
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 1, right: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: c(data.index.isEven ? _accent : const Color(0xFF3D5F96)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    no,
                    style: mono(11, color: Colors.white, weight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    data.tag1,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(narrow ? 13 : 14, weight: FontWeight.w700),
                  ),
                ),
                if (!narrow && more != null) more!,
              ],
            ),
            if (data.chips.isNotEmpty || data.rating.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 评级小方块按内容宽，不再被撑成一整条。
                  if (data.rating.isNotEmpty)
                    IntrinsicWidth(
                      child: ProposalRatingBadge(rating: data.rating, size: 16),
                    ),
                  for (final chip in data.chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: c(const Color(0xFFF1EFF8), DunesColorRole.surface),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(chip, style: sans(10.5, color: const Color(0xFF4D4860))),
                    ),
                ],
              ),
            ],
            const Spacer(),
            // 左下：提案名称（原来年化规模的位置），深紫加粗、最多两行，比标签少一级但一眼能看到。
            Text('提案名称', style: sans(10.5, color: _text3)),
            const SizedBox(height: 1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    data.name.isEmpty ? '—' : data.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(
                      narrow ? 12 : 12.5,
                      weight: FontWeight.w700,
                      color: const Color(0xFF3F2A9A),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c(const Color(0xFFEEEAFB), DunesColorRole.surface),
                    border: Border.all(
                      color: c(const Color(0xFFDCD3F7), DunesColorRole.border),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_right_rounded, size: 16, color: c(_accent)),
                ),
              ],
            ),
          ],
        );

        // ---- 中 / 右两块数据 ----
        Widget panel(List<ProposalListCardMetric> metrics, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: c(bg, DunesColorRole.surface),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < metrics.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: i == metrics.length - 1
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: c(const Color(0x1F504678), DunesColorRole.border),
                            ),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              metrics[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(10.5, color: _text2),
                            ),
                          ),
                          if (metrics[i].tag.isNotEmpty)
                            Flexible(
                              child: Text(
                              metrics[i].tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: sans(
                                10,
                                weight: FontWeight.w600,
                                color: metrics[i].warn
                                    ? const Color(0xFFA93A16)
                                    : _text3,
                              ),
                              ),
                            ),
                        ],
                      ),
                      Text.rich(
                        TextSpan(
                          text: metrics[i].value,
                          style: (metrics[i].mono ? mono : sans)(
                            metrics[i].wrap
                                ? (narrow ? 12 : 12.5)
                                : (narrow ? 13.5 : 14),
                            weight: metrics[i].wrap
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: metrics[i].value == '—' ? _text3 : _ink,
                          ),
                          children: [
                            if (metrics[i].unit.isNotEmpty && metrics[i].value != '—')
                              TextSpan(
                                text: metrics[i].unit,
                                style: sans(10, color: _text2),
                              ),
                          ],
                        ),
                        maxLines: metrics[i].wrap ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

        final mid = panel(data.mid, const Color(0xFFF1F3F8));
        final right = panel(data.right, const Color(0xFFF3F0FB));

        // ---- 底：复核进度条 ----
        final doneCount = data.steps
            .where((s) => s.state == ProposalListStepState.done)
            .length;
        final progress = Container(
          padding: EdgeInsets.fromLTRB(10, 7, narrow ? 4 : 10, 7),
          decoration: BoxDecoration(
            color: c(const Color(0xFFFBFAFE), DunesColorRole.surface),
            border: Border(
              top: BorderSide(color: c(const Color(0xFFEFEDF5), DunesColorRole.border)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c(const Color(0xFFEEEAFB), DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '复核 $doneCount/${data.steps.length}',
                  style: sans(10.5, color: _accent, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProposalReviewSegments(steps: data.steps, showLabels: !narrow),
                    if (data.nowText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        data.nowText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11.5, weight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              if (data.sla != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: narrow ? 120 : 200),
                  child: ProposalSlaChip(sla: data.sla!),
                ),
              ] else if (data.days.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: c(
                      data.daysWarn ? const Color(0xFFFBE6DE) : const Color(0xFFEEF2F7),
                      DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    data.days,
                    style: sans(
                      11,
                      weight: FontWeight.w700,
                      color: data.daysWarn
                          ? const Color(0xFFA93A16)
                          : const Color(0xFF4D5A6B),
                    ),
                  ),
                ),
              ],
              if (narrow && more != null) more!,
            ],
          ),
        );

        final top = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: narrow
                ? [
                    Expanded(child: left),
                    const SizedBox(width: 6),
                    Expanded(child: mid),
                    const SizedBox(width: 6),
                    Expanded(child: right),
                  ]
                : [
                    SizedBox(width: 250, child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: left,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: mid),
                    const SizedBox(width: 8),
                    Expanded(child: right),
                  ],
          ),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: c(Colors.white, DunesColorRole.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c(const Color(0xFFDCD6EF), DunesColorRole.border)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, narrow ? 6 : 8, 8),
                    child: top,
                  ),
                  progress,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
