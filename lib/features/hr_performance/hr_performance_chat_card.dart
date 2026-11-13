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
  });
  final Map<String, dynamic> payload;
  final AuthSession session;
  @override
  State<HrPerformanceChatCard> createState() => _HrPerformanceChatCardState();
}

class _HrPerformanceChatCardState extends State<HrPerformanceChatCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.payload, rows = hrMaps(widget.payload['rows']);
    final notice = p['hrPerformanceNotice'] == true;
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
                      notice
                          ? '${p['title'] ?? '$hrPerformanceTitle提醒'}'
                          : '$hrPerformanceTitle汇总 · ${p['month'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (notice)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('${p['body'] ?? ''}'),
              ),
            if (!notice) ...[
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
            if (notice && (int.tryParse('${p['recordId']}')??0)>0)
              TextButton(
                onPressed: () => openHrPerformanceRecord(
                  context,
                  widget.session,
                  int.tryParse('${p['recordId']}')??0,
                ),
                child: const Text('查看考核表'),
              ),
          ],
        ),
      ),
    );
  }
}
