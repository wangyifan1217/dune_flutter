import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'hr_performance_detail.dart';
import 'hr_performance_department_final.dart';
import 'hr_performance_overlay.dart';
import 'hr_performance_service.dart';
import 'hr_performance_sheets.dart';

bool isHrPerformancePayload(Map<String, dynamic>? payload) =>
    payload?['hrPerformanceSummary'] == true ||
    payload?['hrPerformanceNotice'] == true;

class HrPerformanceChatCard extends StatefulWidget {
  const HrPerformanceChatCard({
    super.key,
    required this.payload,
    required this.session,
    this.caption,
  });
  final Map<String, dynamic> payload;
  final AuthSession session;
  final String? caption;
  @override
  State<HrPerformanceChatCard> createState() => _HrPerformanceChatCardState();
}

class _HrPerformanceChatCardState extends State<HrPerformanceChatCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.payload, rows = hrMaps(widget.payload['rows']);
    final notice = p['hrPerformanceNotice'] == true;
    if (notice) return _noticeCard(p);
    final progress = p['progress'] is Map
        ? Map<String, dynamic>.from(p['progress'])
        : <String, dynamic>{};
    final surface = DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
    final soft = DunesColors.resolve(
      context,
      DunesColors.brandPurpleSoft,
      role: DunesColorRole.surface,
    );
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE7DFF0),
      role: DunesColorRole.border,
    );
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text2);
    final accent = DunesColors.resolve(context, DunesColors.brandPurple);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 390),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: soft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.fact_check_outlined,
                      size: 17,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$hrPerformanceTitle汇总',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p['month'] ?? ''} · 发送时快照',
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${rows.length} 人',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                '共 ${rows.length} 人${p['hasScores'] == true ? ' · 含已下发结果' : ' · 考核进度'}',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
            if (progress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in progress.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${hrPerformanceStageLabels[e.key] ?? e.key} ${e.value}',
                          style: TextStyle(fontSize: 11, color: accent),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Column(
                children: [
                  for (final row in _expanded ? rows : rows.take(5))
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => openHrPerformanceRecord(
                          context,
                          widget.session,
                          int.tryParse('${row['id']}') ?? 0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${row['name']} · ${row['department'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DunesTypography.sans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: text,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      p['hasScores'] == true &&
                                              const [
                                                'result',
                                                'interview',
                                                'archived',
                                              ].contains(row['stage']) &&
                                              row['total'] != null
                                          ? '${row['total']} 分 · ${row['grade'] ?? '—'} · 系数 ${row['coefficient'] ?? '—'}'
                                          : hrPerformanceStageLabels['${row['stage']}'] ??
                                                '考核中',
                                      style: DunesTypography.sans(
                                        fontSize: 11,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '查看',
                                style: DunesTypography.sans(
                                  fontSize: 11,
                                  color: accent,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (rows.length > 5)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  textStyle: DunesTypography.sans(fontSize: 12),
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开全部 ${rows.length} 人'),
              ),
            if (p['createdAt'] != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '发送于 ${hrDate(p['createdAt'])} · 数据不会自动更新',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noticeCard(Map<String, dynamic> payload) {
    final title = '${payload['title'] ?? '$hrPerformanceTitle提醒'}';
    final body = '${payload['body'] ?? ''}'.trim();
    const reasonMarker = '\n督办内容：';
    final reasonAt = body.indexOf(reasonMarker);
    final structuredUrge =
        title == '人事绩效督办' &&
        body.startsWith('考核：') &&
        body.contains('\n发送时节点：') &&
        reasonAt >= 0;
    final urgeContext = structuredUrge ? body.substring(0, reasonAt) : '';
    final urgeReason = structuredUrge
        ? body.substring(reasonAt + reasonMarker.length).trim()
        : '';
    final recordId = int.tryParse('${payload['recordId']}') ?? 0;
    final surface = DunesColors.resolve(
      context,
      DunesColors.imSurface,
      role: DunesColorRole.surface,
    );
    final border = DunesColors.resolve(
      context,
      DunesColors.borderSoft,
      role: DunesColorRole.border,
    );
    final text = DunesColors.resolve(context, DunesColors.text);
    final text2 = DunesColors.resolve(context, DunesColors.text2);
    final text3 = DunesColors.resolve(context, DunesColors.text3);
    final accent = DunesColors.resolve(context, DunesColors.brandPurple);
    final caption = widget.caption?.trim() ?? '';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    DunesColors.brandPurpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.fact_check_outlined, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 4),
                  child: Text(
                    caption,
                    style: TextStyle(color: text3, fontSize: 11),
                  ),
                ),
            ],
          ),
          if (structuredUrge)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 7, 8, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    urgeContext,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: text2,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurpleSoft,
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '督办内容',
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          urgeReason,
                          style: DunesTypography.sans(
                            fontSize: 12.5,
                            color: text,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 6, 8, 0),
              child: Text(
                body,
                style: TextStyle(color: text2, fontSize: 13, height: 1.45),
              ),
            ),
          if (recordId > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  if (body.contains('当前节点 总裁办终审'))
                    TextButton(
                      onPressed: () => showHrDepartmentFinal(
                        context,
                        HrPerformanceService(widget.session),
                        recordId,
                      ),
                      child: const Text('部门终审'),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      textStyle: DunesTypography.sans(fontSize: 12),
                    ),
                    onPressed: () => openHrPerformanceRecord(
                      context,
                      widget.session,
                      recordId,
                    ),
                    child: const Text('查看考核表'),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
