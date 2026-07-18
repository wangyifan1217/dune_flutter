import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_models.dart';
import 'qianji_widgets.dart';

/// Iteration · 迭代详情 · V2.0（静态，原生 Flutter）。
class NativeQianjiIterationPage extends StatelessWidget {
  const NativeQianjiIterationPage({
    super.key,
    required this.entity,
    required this.iteration,
    required this.onBack,
  });

  final QianjiEntity entity;
  final QianjiIteration iteration;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QianjiCrumbBar(
              backLabel: entity.name,
              crumb: '${iteration.version} 迭代',
              onBack: onBack,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
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
                              iteration.version,
                              style: DunesTypography.sans(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: DunesColors.text,
                              ),
                            ),
                            const SizedBox(width: 8),
                            QianjiPill(
                              iteration.statusLabel,
                              iterating: iteration.active,
                            ),
                            if (iteration.phase.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                iteration.phase,
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: DunesColors.text2,
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
                            color: DunesColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  QianjiSectionCard(
                    title: '迭代信息',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QianjiInfoRow(
                          '当前阶段',
                          iteration.phase.isEmpty ? iteration.statusLabel : iteration.phase,
                          accent: true,
                        ),
                        QianjiInfoRow('负责人', iteration.owner, accent: true),
                        QianjiInfoRow('开发成员', iteration.members),
                        const SizedBox(height: 2),
                        Text(
                          '迭代说明',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: DunesColors.text3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          iteration.description,
                          style: DunesTypography.sans(
                            fontSize: 13,
                            height: 1.45,
                            color: DunesColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (iteration.requirements.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    QianjiSectionCard(
                      title: '关联需求编号及需求名称',
                      trailing: QianjiPill(
                        '${iteration.requirements.length} 条',
                        iterating: true,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < iteration.requirements.length;
                              i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _ReqItem(iteration.requirements[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  QianjiSectionCard(
                    title: '开发甘特图',
                    trailing: Text(
                      iteration.currentLabel,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: iteration.active
                            ? DunesColors.blue
                            : DunesColors.green,
                      ),
                    ),
                    child: QianjiGanttBlock(
                      scale: iteration.ganttScale,
                      bars: iteration.ganttBars,
                      phases: iteration.phases,
                      currentLabel: iteration.currentLabel,
                      nowPercent: iteration.nowPercent,
                      showLegend: true,
                    ),
                  ),
                  if (iteration.files.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    QianjiSectionCard(
                      title: '开发文件',
                      trailing: QianjiPill(
                        '${iteration.files.length} 个',
                        iterating: true,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < iteration.files.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _FileItem(iteration.files[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (iteration.personChanges.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    QianjiSectionCard(
                      title: '关联人员变更',
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < iteration.personChanges.length;
                              i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _ChangeItem(
                              version: iteration.version,
                              change: iteration.personChanges[i],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReqItem extends StatelessWidget {
  const _ReqItem(this.req);

  final QianjiRequirement req;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            req.code,
            style: DunesTypography.mono(fontSize: 11, color: DunesColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            req.name,
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          if (req.kind.isNotEmpty || req.phase.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (req.kind.isNotEmpty) req.kind,
                if (req.phase.isNotEmpty) req.phase,
              ].join(' · '),
              style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
            ),
          ],
        ],
      ),
    );
  }
}

class _FileItem extends StatelessWidget {
  const _FileItem(this.file);

  final QianjiDevFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DunesColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(file.icon, size: 18, color: DunesColors.accentDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                if (file.meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    file.meta,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                ] else
                  Text(
                    file.size,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.download_rounded, size: 18, color: DunesColors.text3),
        ],
      ),
    );
  }
}

class _ChangeItem extends StatelessWidget {
  const _ChangeItem({required this.version, required this.change});

  final String version;
  final QianjiPersonChange change;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DunesColors.blueSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  version,
                  style: DunesTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                change.role,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Text(
                  change.from,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '→',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    color: DunesColors.text3,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  change.to,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.accentDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            change.time,
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}
