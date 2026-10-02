import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_models.dart';
import 'qianji_widgets.dart';

/// Detail · 产品详情 · 迭代中（静态，原生 Flutter）。
class NativeQianjiDetailPage extends StatelessWidget {
  const NativeQianjiDetailPage({
    super.key,
    required this.entity,
    required this.onBack,
    required this.onOpenIteration,
  });

  final QianjiEntity entity;
  final VoidCallback onBack;
  final ValueChanged<QianjiIteration> onOpenIteration;

  @override
  Widget build(BuildContext context) {
    final detail = QianjiStaticCatalog.detailFor(entity);

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        DunesColors.bgApp,
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QianjiCrumbBar(backLabel: '返回', crumb: '产品/能力', onBack: onBack),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  QianjiSectionCard(
                    title: '基础信息',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QianjiInfoRow('产品名称', detail.name),
                        QianjiInfoRow('负责人', detail.owner, accent: true),
                        QianjiInfoRow(
                          detail.entity.kind == QianjiEntityKind.capability
                              ? '赋能方式'
                              : '适用行业',
                          detail.industryOrMode,
                        ),
                        QianjiInfoRow('应用现状', detail.application),
                        const SizedBox(height: 2),
                        Text(
                          '产品说明',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                            context: context,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detail.description,
                          style: DunesTypography.sans(
                            fontSize: 13,
                            height: 1.45,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text2,
                            ),
                            context: context,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'demo演示',
                              style: DunesTypography.sans(
                                fontSize: 12,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text3,
                                ),
                                context: context,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                detail.demoLabel,
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.accent,
                                  ),
                                  fontWeight: FontWeight.w500,
                                  context: context,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '状态',
                              style: DunesTypography.sans(
                                fontSize: 12,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text3,
                                ),
                                context: context,
                              ),
                            ),
                            const SizedBox(width: 12),
                            QianjiPill(
                              detail.statusLabel,
                              iterating: detail.statusLabel != '已上线',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  QianjiSectionCard(
                    title: '系统关联',
                    child: Column(
                      children: [
                        for (
                          var i = 0;
                          i < detail.capabilities.length;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _CapabilityTile(detail.capabilities[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  QianjiSectionCard(
                    title: '版本记录',
                    trailing: QianjiPill(
                      '${detail.iterations.length} 个版本',
                      iterating: true,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < detail.iterations.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _IterationCard(
                            iteration: detail.iterations[i],
                            onOpen: () => onOpenIteration(detail.iterations[i]),
                          ),
                        ],
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

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile(this.cap);

  final QianjiCapabilityLink cap;

  @override
  Widget build(BuildContext context) {
    final iterating = cap.status != '已上线';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          DunesColors.bgApp,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    DunesColors.accentSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  cap.icon,
                  size: 16,
                  color: DunesColors.resolve(context, DunesColors.accentDeep),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cap.title,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
              ),
              QianjiPill(cap.status, iterating: iterating),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cap.description,
            style: DunesTypography.sans(
              fontSize: 12,
              height: 1.4,
              color: DunesColors.resolve(context, DunesColors.text2),
              context: context,
            ),
          ),
        ],
      ),
    );
  }
}

class _IterationCard extends StatelessWidget {
  const _IterationCard({required this.iteration, required this.onOpen});

  final QianjiIteration iteration;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final active = iteration.active;
    return Material(
      color: active
          ? DunesColors.resolve(
              context,
              DunesColors.accentSoft,
              role: DunesColorRole.surface,
            ).withValues(alpha: 0.35)
          : DunesColors.resolve(
              context,
              DunesColors.bgApp,
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? DunesColors.resolve(
                      context,
                      DunesColors.accentLine,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      DunesColors.borderSoft,
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    iteration.version,
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  const SizedBox(width: 8),
                  QianjiPill(iteration.statusLabel, iterating: active),
                  if (iteration.phase.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      iteration.phase,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text2),
                        context: context,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                iteration.meta,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
              const SizedBox(height: 10),
              QianjiInfoRow('负责人', iteration.owner, accent: true),
              QianjiInfoRow('开发成员', iteration.members),
              const SizedBox(height: 4),
              QianjiGanttBlock(
                scale: iteration.ganttScale,
                bars: iteration.ganttBars,
                phases: iteration.phases,
                currentLabel: iteration.currentLabel,
                nowPercent: iteration.nowPercent,
              ),
              if (iteration.requirements.isNotEmpty) ...[
                const SizedBox(height: 12),
                _miniHd(
                  context,
                  Icons.link_rounded,
                  '关联需求池 · ${iteration.requirements.length} 条',
                ),
                const SizedBox(height: 6),
                for (final r in iteration.requirements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
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
                            DunesColors.borderSoft,
                            role: DunesColorRole.border,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.code,
                            style: DunesTypography.mono(
                              fontSize: 11,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.accent,
                              ),
                              context: context,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.name,
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text,
                              ),
                              context: context,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (iteration.files.isNotEmpty) ...[
                const SizedBox(height: 4),
                _miniHd(
                  context,
                  Icons.folder_outlined,
                  '开发文件 · ${iteration.files.length} 个',
                ),
                const SizedBox(height: 6),
                for (final f in iteration.files)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          f.icon,
                          size: 16,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.name,
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text,
                              ),
                              context: context,
                            ),
                          ),
                        ),
                        Text(
                          f.size,
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: DunesColors.resolve(
                      context,
                      DunesColors.borderSoft,
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_circle_right_outlined,
                      size: 18,
                      color: DunesColors.resolve(context, DunesColors.accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '查看迭代详情',
                        style: DunesTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.accentDeep,
                          ),
                          context: context,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniHd(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: DunesColors.resolveNullable(context, DunesColors.text2),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text2),
            context: context,
          ),
        ),
      ],
    );
  }
}
