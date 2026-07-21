import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'qianji_perf_shared.dart';
import 'qianji_project_models.dart';

/// 07 · 我的项目列表。
class NativeQianjiProjectsPage extends StatelessWidget {
  const NativeQianjiProjectsPage({
    super.key,
    required this.onBack,
    required this.onOpenProject,
  });

  final VoidCallback onBack;
  final ValueChanged<QianjiProjectItem> onOpenProject;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            QianjiPerfNavBar(title: '我的项目', onBack: onBack),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _Hero(),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DunesColors.coralSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF5C4B5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: DunesColors.coral,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: DunesTypography.sans(
                                fontSize: 12,
                                color: const Color(0xFF7A2E10),
                              ),
                              children: const [
                                TextSpan(
                                  text: '1 项任务延期',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(text: '：灯塔数据切割已超期 10 天'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionHd('我负责的项目', '${QianjiProjectCatalog.owned.length} 项'),
                  const SizedBox(height: 6),
                  for (final p in QianjiProjectCatalog.owned) ...[
                    _ProjectCard(project: p, onTap: () => onOpenProject(p)),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  _sectionHd('我参与开发', '${QianjiProjectCatalog.joined.length} 项'),
                  const SizedBox(height: 6),
                  for (final p in QianjiProjectCatalog.joined) ...[
                    _ProjectCard(project: p, onTap: () => onOpenProject(p)),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHd(String title, String count) {
    return Row(
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
        Text(
          count,
          style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget cell(String v, String l, {Color? valueColor}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                v,
                style: DunesTypography.sans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l,
                style: DunesTypography.sans(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: QianjiPerfTheme.overviewGradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -36,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '工作概览',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  cell('4', '参与项目'),
                  const SizedBox(width: 6),
                  cell('12', '进行任务'),
                  const SizedBox(width: 6),
                  cell('2', '已延期', valueColor: const Color(0xFFFFD580)),
                  const SizedBox(width: 6),
                  cell('8', '本周提交', valueColor: const Color(0xFF80FFD4)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final QianjiProjectItem project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final late = project.status == QianjiProjectStatus.late;
    final done = project.status == QianjiProjectStatus.done;
    final fill = late
        ? DunesColors.coral
        : done
            ? DunesColors.green
            : QianjiPerfTheme.purple;
    final iconBg = late
        ? DunesColors.coralSoft
        : done
            ? DunesColors.greenSoft
            : QianjiPerfTheme.purpleSoft;
    final border = late
        ? const Color(0xFFF5C4B5)
        : project.id == 'voice-prd'
            ? QianjiPerfTheme.purpleLine
            : DunesColors.borderSoft;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(project.icon, size: 18, color: fill),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                project.name,
                                style: DunesTypography.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: DunesColors.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _chip(
                              project.statusLabel,
                              late
                                  ? DunesColors.coralSoft
                                  : done
                                      ? DunesColors.greenSoft
                                      : QianjiPerfTheme.purpleSoft,
                              late
                                  ? DunesColors.coral
                                  : done
                                      ? DunesColors.green
                                      : QianjiPerfTheme.purple,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          project.meta,
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: DunesColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _roleChip(project),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: project.progress,
                        minHeight: 4,
                        backgroundColor: DunesColors.bgSoft,
                        color: fill,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${(project.progress * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: DunesTypography.mono(
                        fontSize: 10,
                        color: fill,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.taskSummary,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                  Icon(
                    late
                        ? Icons.warning_amber_rounded
                        : done
                            ? Icons.check_rounded
                            : Icons.calendar_today_outlined,
                    size: 12,
                    color: late ? DunesColors.coral : DunesColors.text3,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    project.deadline,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: late ? DunesColors.coral : DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleChip(QianjiProjectItem p) {
    final bg = switch (p.role) {
      QianjiProjectRole.owner => QianjiPerfTheme.purpleSoft,
      QianjiProjectRole.developer => DunesColors.greenSoft,
      QianjiProjectRole.late => DunesColors.coralSoft,
    };
    final fg = switch (p.role) {
      QianjiProjectRole.owner => QianjiPerfTheme.purple,
      QianjiProjectRole.developer => DunesColors.green,
      QianjiProjectRole.late => DunesColors.coral,
    };
    return _chip(p.roleLabel, bg, fg);
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
