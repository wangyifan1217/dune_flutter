import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'hr_performance_overlay.dart';
import 'hr_performance_service.dart';
import 'hr_performance_sheets.dart';
import 'hr_performance_template_ui.dart';

/// Loads the current department and its permissions at the time of opening.
Future<void> showHrDepartmentFinal(
  BuildContext context,
  HrPerformanceService service,
  int recordId, {
  Set<int>? recordIds,
  String? departmentName,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Theme(
      data: hrConfigTheme(context),
      child: _DepartmentFinalDialog(
        service: service,
        recordId: recordId,
        recordIds: recordIds,
        departmentName: departmentName,
      ),
    ),
  );
}

class _DepartmentFinalDialog extends StatefulWidget {
  const _DepartmentFinalDialog({
    required this.service,
    required this.recordId,
    this.recordIds,
    this.departmentName,
  });
  final HrPerformanceService service;
  final int recordId;
  final Set<int>? recordIds;
  final String? departmentName;

  @override
  State<_DepartmentFinalDialog> createState() => _DepartmentFinalDialogState();
}

class _DepartmentFinalDialogState extends State<_DepartmentFinalDialog> {
  HrPerformanceRecord? _anchor;
  List<HrPerformanceRecord> _rows = [];
  List<HrPerformanceRecord> _departmentRows = [];
  Map<int, double?> _initialTotals = {};
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final anchor = await widget.service.detail(widget.recordId);
      if (anchor.departmentId == null) throw Exception('该考核表未配置部门');
      final access = await widget.service.access();
      if (!access.finalAccess) throw Exception('当前账号没有终审权限');
      final records = await widget.service.records(anchor.month, 'all');
      final departmentRows = records
          .where(
            (r) => widget.recordIds == null
                ? r.departmentId == anchor.departmentId
                : widget.recordIds!.contains(r.id),
          )
          .toList();
      final rows = departmentRows
          .where(
            (r) => r.stage == 'final' && r.actions.contains('approve_final'),
          )
          .toList();
      final totals = <int, double?>{};
      // Bound concurrent history requests so large departments do not flood the service.
      for (var offset = 0; offset < rows.length; offset += 8) {
        await Future.wait(
          rows.skip(offset).take(8).map((row) async {
            try {
              final logs = await widget.service.logs(row.id);
              final review = logs
                  .where((log) => log['action'] == 'submit_review')
                  .firstOrNull;
              final after = review?['after'];
              final snapshot = after is Map ? after['snapshot'] : null;
              totals[row.id] = snapshot is Map
                  ? (snapshot['total'] as num?)?.toDouble()
                  : null;
            } catch (_) {
              totals[row.id] = null;
            }
          }),
        );
      }
      if (!mounted) return;
      setState(() {
        _anchor = anchor;
        _departmentRows = departmentRows;
        _initialTotals = totals;
        _rows = rows..sort((a, b) => _attention(b).compareTo(_attention(a)));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, int> get _progress {
    final result = <String, int>{
      '前序环节': 0,
      '待终审（可办理）': 0,
      '待终审（其他）': 0,
      '已下发': 0,
      '免考核': 0,
      '其他归档': 0,
      '其他状态': 0,
    };
    for (final r in _departmentRows) {
      final String key;
      if (r.stage == 'exempt') {
        key = '免考核';
      } else if (r.stage == 'final') {
        key = r.actions.contains('approve_final') ? '待终审（可办理）' : '待终审（其他）';
      } else if (r.released) {
        key = '已下发';
      } else if (r.stage == 'archived') {
        key = '其他归档';
      } else if (const [
        'opening',
        'self',
        'indicators',
        'review',
        'calibration',
        'hr',
        'ready_final',
      ].contains(r.stage)) {
        key = '前序环节';
      } else {
        key = '其他状态';
      }
      result[key] = result[key]! + 1;
    }
    return result;
  }

  String get _upstreamDetail {
    const stages = [
      'opening',
      'self',
      'indicators',
      'review',
      'calibration',
      'hr',
      'ready_final',
    ];
    return stages
        .map((stage) {
          final count = _departmentRows.where((r) => r.stage == stage).length;
          return count == 0 ? '' : '${hrPerformanceStageLabels[stage]} $count';
        })
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }

  int _attention(HrPerformanceRecord r) {
    final before = _initialTotals[r.id];
    final now = (r.snapshot['total'] as num?)?.toDouble();
    return (r.warnings.isNotEmpty ? 2 : 0) +
        (before != null && now != null && (now - before).abs() > 0.00001
            ? 1
            : 0);
  }

  String _comparison(HrPerformanceRecord r) {
    final before = _initialTotals[r.id];
    final now = (r.snapshot['total'] as num?)?.toDouble();
    if (before == null || now == null) return '初评记录不可比较';
    final delta = now - before;
    return delta.abs() < 0.00001
        ? '与初评一致'
        : '初评 ${before.toStringAsFixed(1)} 分 · ${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} 分';
  }

  Future<void> _reject(HrPerformanceRecord record) async {
    final reason = await showHrReasonSheet(
      context,
      title: '驳回 ${record.name}',
      minLength: 1,
      message: record.skipsDirectReview
          ? '该人员将退回本人自评，其他人员不受影响。'
          : '该人员将退回主管初评，其他人员不受影响。',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.action(record, {
        'action': 'reject_final',
        ...reason,
      });
      if (mounted) showDunesToast(context, '已驳回 ${record.name}');
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '驳回失败：$e', kind: DunesToastKind.error);
      }
    }
    if (mounted) await _load();
  }

  Future<void> _approve() async {
    final rows = List<HrPerformanceRecord>.of(_rows);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认部门终审'),
        content: Text(
          '将通过并下发 ${widget.departmentName ?? _anchor?.department ?? ''} 当前列表中的 ${rows.length} 人。${_progress['前序环节']! > 0 ? '另有 ${_progress['前序环节']} 人尚在前序环节。' : ''}${_progress['待终审（其他）']! > 0 ? '另有 ${_progress['待终审（其他）']} 人当前不在您的办理范围。' : ''}请先逐一查看，并驳回需要修改的人员。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认通过并下发'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final results = await widget.service.batch(rows, 'approve_final', '');
      final failures = results.where((r) => r['success'] != true).toList();
      if (mounted) {
        final names = {for (final r in rows) r.id: r.name};
        final message = failures.isEmpty
            ? '已通过并下发 ${results.length} 人'
            : '已通过 ${results.length - failures.length} 人；${failures.map((r) => '${names[r['id']] ?? r['id']}：${r['message']}').join('；')}';
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('终审结果'),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '操作中断，部分人员可能已下发，请刷新查看：$e',
          kind: DunesToastKind.error,
        );
      }
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _anchor == null
          ? '部门终审'
          : '${widget.departmentName ?? _anchor!.department} · 部门终审',
    ),
    content: SizedBox(
      width: (MediaQuery.sizeOf(context).width - 80).clamp(200, 620),
      height: (MediaQuery.sizeOf(context).height - 240).clamp(160, 440),
      child: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_anchor!.month} · ${widget.recordIds == null ? '本部门考核记录' : '本次发送人员'} ${_departmentRows.length} 人${widget.recordIds == null ? '（不含下级部门）' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in _progress.entries)
                      if (entry.value > 0 ||
                          const [
                            '前序环节',
                            '待终审（可办理）',
                            '已下发',
                            '免考核',
                          ].contains(entry.key))
                        Builder(
                          builder: (ctx) {
                            final isDark =
                                Theme.of(ctx).brightness == Brightness.dark;
                            final tone = switch (entry.key) {
                              '已下发' => const Color(0xFF1F9D76),
                              '待终审（可办理）' => DunesColors.brandPurple,
                              '前序环节' => const Color(0xFFD97706),
                              _ => const Color(0xFF64748B),
                            };
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tone.withValues(
                                  alpha: isDark ? 0.20 : 0.10,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${entry.key} ${entry.value}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: DunesColors.resolve(ctx, tone),
                                ),
                              ),
                            );
                          },
                        ),
                  ],
                ),
                if (_upstreamDetail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '前序明细：$_upstreamDetail',
                      style: TextStyle(
                        fontSize: 11,
                        color: DunesColors.resolve(context, DunesColors.text2),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                  '预警和初评分数有变化的人员排在前面，可先查看或单独驳回。',
                  style: TextStyle(fontSize: 12),
                ),
                const Divider(),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('当前没有可终审人员'))
                      : ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final r = _rows[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(10, 4, 8, 10),
                              decoration: BoxDecoration(
                                color: hrConfigSurface(
                                  context,
                                  const Color(0xFFF7F4FC),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          minimumSize: const Size(0, 32),
                                          textStyle: DunesTypography.sans(
                                            fontSize: 12,
                                          ),
                                        ),
                                        onPressed: () =>
                                            openHrPerformanceRecord(
                                              context,
                                              widget.service.session,
                                              r.id,
                                            ),
                                        child: const Text('明细'),
                                      ),
                                      if (r.actions.contains('reject_final'))
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            minimumSize: const Size(0, 32),
                                            textStyle: DunesTypography.sans(
                                              fontSize: 12,
                                            ),
                                          ),
                                          onPressed: () => _reject(r),
                                          child: const Text('驳回'),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    [
                                      if (r.scoresVisible &&
                                          r.snapshot['total'] != null)
                                        '${r.snapshot['total']} 分 · ${r.snapshot['grade'] ?? ''} · 系数 ${r.snapshot['coefficient'] ?? ''}',
                                      _comparison(r),
                                      if (r.warnings.isNotEmpty)
                                        '预警：${r.warnings.join('；')}',
                                    ].join('\n'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: DunesColors.resolve(
                                        context,
                                        _attention(r) > 0
                                            ? DunesColors.brandPurpleDeep
                                            : DunesColors.text2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: _busy || _error != null || _rows.isEmpty ? null : _approve,
        child: const Text('部门通过并下发'),
      ),
    ],
  );
}
