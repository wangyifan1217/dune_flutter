import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 专题（2026-10-27）
//
//   专题 = 横跨产品 / 供给 / 渠道 / 人效的一刀切片（例如「金科」）。
//   后端把它当成跟权限同一条 WHERE 压在账本宽表上（lighthouse-go
//   internal/lighthouse/topic.go），前端只负责带 `topic=` 参数。
//
//   切专题时整页按 key 重建（见 NativeLighthousePage），期间 / 维度 / 分类
//   经由 [LighthouseTopicHandoff] 带过去 —— 不会有上一个专题的晚到响应。
//
//   key 必须和后端 lighthouseTopics 一致。
// ════════════════════════════════════════════════════════════════════════

/// 专题条入口开关。2026-10-27：先隐藏，Hero 上方这一格换成像素横幅；
/// 后端 topic 参数与整页重建逻辑保留，打开这个开关即可恢复。
const bool lighthouseTopicStripEnabled = false;

class LighthouseTopic {
  const LighthouseTopic({
    required this.key,
    required this.name,
    required this.mark,
    required this.color,
    required this.soft,
  });

  final String key;
  final String name;

  /// 胶囊里的单字标。
  final String mark;
  final Color color;
  final Color soft;
}

/// 全盘（不筛）。key 为空串。
const lighthouseTopicAll = LighthouseTopic(
  key: '',
  name: '全盘',
  mark: '全',
  color: Color(0xFF5A458F),
  soft: Color(0xFFF0ECF6),
);

const lighthouseTopics = <LighthouseTopic>[
  LighthouseTopic(
    key: 'jinke',
    name: '金科',
    mark: '金',
    color: Color(0xFF84581A),
    soft: DunesColors.amberSoft,
  ),
];

LighthouseTopic? lighthouseTopicOf(String key) {
  for (final t in lighthouseTopics) {
    if (t.key == key) return t;
  }
  return null;
}

/// 换专题时从旧页面带到新页面的浏览状态。
class LighthouseTopicHandoff {
  const LighthouseTopicHandoff({
    required this.period,
    required this.periodOffset,
    required this.customStart,
    required this.customEnd,
    required this.tab,
    required this.groupFilter,
    required this.tabBarShowsGroups,
  });

  final String period;
  final int periodOffset;
  final DateTime? customStart;
  final DateTime? customEnd;
  final String tab;
  final String groupFilter;
  final bool tabBarShowsGroups;
}

const _kPlumDeep = Color(0xFF5A458F);
const _kPlumLine = Color(0xFFE4DCF4);
const _kAmber = DunesColors.amber;
const _kAmberInk = Color(0xFF84581A);
const _kAmberWash = Color(0xFFFBF7EE);
const _kAmberLine = Color(0xFFF1E6D2);

/// Hero 上方的专题条：全盘 + 已配置专题。选中态 = 深紫实底（同分类胶囊）。
class LighthouseTopicStrip extends StatelessWidget {
  const LighthouseTopicStrip({
    super.key,
    required this.current,
    required this.onSelect,
    this.padding = EdgeInsets.zero,
  });

  final String current;
  final ValueChanged<String> onSelect;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final items = <LighthouseTopic>[lighthouseTopicAll, ...lighthouseTopics];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final t = items[i];
          return Center(
            child: _TopicPill(
              topic: t,
              selected: t.key == current,
              onTap: () => onSelect(t.key),
            ),
          );
        },
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final LighthouseTopic topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deep = DunesColors.resolve(
      context,
      _kPlumDeep,
      role: DunesColorRole.surface,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '专题 ${topic.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 34,
          padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
          decoration: BoxDecoration(
            color: selected
                ? deep
                : DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? deep
                  : DunesColors.resolve(
                      context,
                      _kPlumLine,
                      role: DunesColorRole.border,
                    ),
              width: 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _kPlumDeep.withAlpha(56),
                      blurRadius: 14,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withAlpha(40)
                      : DunesColors.resolve(
                          context,
                          topic.soft,
                          role: DunesColorRole.surface,
                        ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  topic.mark,
                  style: LhTypography.sans(
                    size: 12,
                    weight: FontWeight.w700,
                    height: 1.0,
                    color: selected
                        ? Colors.white
                        : DunesColors.resolve(context, topic.color),
                    context: context,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                topic.name,
                style: LhTypography.sans(
                  size: 13,
                  weight: FontWeight.w700,
                  height: 1.0,
                  color: selected
                      ? Colors.white
                      : DunesColors.resolve(context, LhColors.ink),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 账本卡顶上的专题标记：滑到列表时也知道自己在专题里，右侧一键退出。
class LighthouseTopicLedgerBar extends StatelessWidget {
  const LighthouseTopicLedgerBar({
    super.key,
    required this.topic,
    required this.onExit,
  });

  final LighthouseTopic topic;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final ink = DunesColors.resolve(context, _kAmberInk);
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          _kAmberWash,
          role: DunesColorRole.surface,
        ),
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              _kAmberLine,
              role: DunesColorRole.border,
            ),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: DunesColors.resolve(context, _kAmber),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            topic.name,
            style: LhTypography.sans(
              size: 12.5,
              weight: FontWeight.w700,
              height: 1.0,
              color: ink,
              context: context,
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: '退出${topic.name}专题',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExit,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      Colors.white,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFFEADBC0),
                        role: DunesColorRole.border,
                      ),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '退出',
                        style: LhTypography.sans(
                          size: 11.5,
                          weight: FontWeight.w600,
                          height: 1.0,
                          color: ink,
                          context: context,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.close_rounded, size: 13, color: ink),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
