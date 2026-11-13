import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'hr_performance_detail.dart';
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: DunesColors.resolve(context, DunesColors.brandPurpleSoft),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$hrPerformanceTitle汇总 · ${p['month'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '共 ${rows.length} 人${p['hasScores'] == true ? ' · 已下发结果' : ' · 考核进度'}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final e in progress.entries)
                      Chip(
                        label: Text(
                          '${hrPerformanceStageLabels[e.key] ?? e.key} ${e.value}',
                        ),
                      ),
                  ],
                ),
              ),
              for (final row in _expanded ? rows : rows.take(5))
                ListTile(
                  dense: true,
                  title: Text('${row['name']} · ${row['department'] ?? ''}'),
                  subtitle: Text(
                    p['hasScores'] == true &&
                            [
                              'result',
                              'interview',
                              'archived',
                            ].contains(row['stage']) &&
                            row['total'] != null
                        ? '${row['total']} 分 · ${row['grade']} · 系数 ${row['coefficient']}'
                        : hrPerformanceStageLabels['${row['stage']}'] ?? '考核中',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openHrPerformanceRecord(
                    context,
                    widget.session,
                    int.tryParse('${row['id']}')??0,
                  ),
                ),
              if (rows.length > 5)
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? '收起' : '展开全部 ${rows.length} 人'),
                ),
              if (p['createdAt'] != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '发送时快照 · ${hrDate(p['createdAt'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noticeCard(Map<String, dynamic> payload) {
    final title = '${payload['title'] ?? '$hrPerformanceTitle提醒'}';
    final body = '${payload['body'] ?? ''}'.trim();
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
          if (body.isNotEmpty)
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
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: () =>
                    openHrPerformanceRecord(context, widget.session, recordId),
                child: const Text('查看考核表'),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
