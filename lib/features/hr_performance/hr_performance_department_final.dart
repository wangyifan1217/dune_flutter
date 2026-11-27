import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Directly checks current department records and opens a concise second confirmation dialog.
Future<void> confirmHrDepartmentFinalDirect(
  BuildContext context,
  HrPerformanceService service,
  int recordId, {
  required Set<int> recordIds,
  String? departmentName,
}) async {
  try {
    final anchor = await service.detail(recordId);
    if (anchor.departmentId == null) throw Exception('该考核表未配置部门');
    final access = await service.access();
    if (!access.finalAccess) throw Exception('当前账号没有终审权限');
    final records = await service.records(anchor.month, 'all');
    final departmentRows = records
        .where((r) => recordIds.contains(r.id))
        .toList();
    final approvable = departmentRows
        .where((r) => r.stage == 'final' && r.actions.contains('approve_final'))
        .toList();
    if (!context.mounted) return;
    if (approvable.isEmpty) {
      showDunesToast(context, '当前没有可终审人员');
      return;
    }
    final upstreamCount = departmentRows
        .where(
          (r) => const [
            'opening',
            'self',
            'indicators',
            'review',
            'calibration',
            'hr',
            'ready_final',
          ].contains(r.stage),
        )
        .length;
    final otherFinalCount = departmentRows
        .where(
          (r) => r.stage == 'final' && !r.actions.contains('approve_final'),
        )
        .length;
    final dept = (departmentName?.trim().isNotEmpty ?? false)
        ? departmentName!.trim()
        : anchor.department;
    final extraNotes = <String>[
      if (upstreamCount > 0) '另有 $upstreamCount 人尚在前序环节',
      if (otherFinalCount > 0) '另有 $otherFinalCount 人当前不在您的办理范围',
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: hrConfigTheme(ctx),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            dept.isNotEmpty ? '$dept · 确认部门终审' : '确认部门终审',
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(ctx, DunesColors.text),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将通过并下发当前 ${approvable.length} 人的绩效考核结果。',
                style: DunesTypography.sans(
                  fontSize: 13.5,
                  color: DunesColors.resolve(ctx, DunesColors.text),
                  height: 1.45,
                ),
              ),
              if (extraNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  extraNotes.join('；'),
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.resolve(ctx, const Color(0xFFD97706)),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '如需退回修改，请先点击「展开人员」单独驳回。',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.resolve(ctx, DunesColors.text2),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.resolve(
                  ctx,
                  DunesColors.brandPurple,
                ),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx, true);
              },
              child: Text('确认下发 (${approvable.length})'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final results = await service.batch(approvable, 'approve_final', '');
    if (!context.mounted) return;
    final failures = results.where((r) => r['success'] != true).toList();
    if (failures.isEmpty) {
      showDunesToast(context, '已通过并下发 ${results.length} 人');
      return;
    }
    final names = {for (final r in approvable) r.id: r.name};
    final message =
        '已通过 ${results.length - failures.length} 人；${failures.map((r) => '${names[r['id']] ?? r['id']}：${r['message']}').join('；')}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('终审结果'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      showDunesToast(context, '操作失败：$e', kind: DunesToastKind.error);
    }
  }
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
  bool _onlyAttention = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = hrConfigSurface(context, Colors.white);
    final subtleBg = hrConfigSurface(context, const Color(0xFFF5F5F7));
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE5E5EA),
      role: DunesColorRole.border,
    );
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text2);
    final accent = DunesColors.resolve(context, DunesColors.brandPurple);
    final soft = hrConfigSurface(context, DunesColors.brandPurpleSoft);
    final attentionCount = _rows.where((r) => _attention(r) > 0).length;
    final q = _query.trim().toLowerCase();
    final filteredRows = _rows.where((r) {
      if (_onlyAttention && _attention(r) == 0) return false;
      if (q.isNotEmpty && !r.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 660,
          maxHeight: (screen.height - 80).clamp(320.0, 660.0),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: border.withValues(alpha: 0.7),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [soft, soft.withValues(alpha: 0.35)],
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: border.withValues(alpha: 0.55),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(accent, Colors.white, 0.22) ?? accent,
                            accent,
                            Color.lerp(accent, Colors.black, 0.14) ?? accent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _anchor == null
                                ? '部门终审'
                                : '${widget.departmentName ?? _anchor!.department} · 部门终审',
                            style: DunesTypography.sans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: text,
                            ),
                          ),
                          if (_anchor != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${_anchor!.month} · ${widget.recordIds == null ? '本部门考核记录' : '本次发送人员'} ${_departmentRows.length} 人${widget.recordIds == null ? '（不含下级部门）' : ''}',
                              style: DunesTypography.sans(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新最新状态',
                      onPressed: _busy ? null : _load,
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: 19,
                        color: muted,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 32,
                                color: muted,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                            final tone = switch (entry.key) {
                                              '已下发' => const Color(0xFF1F9D76),
                                              '待终审（可办理）' =>
                                                DunesColors.brandPurple,
                                              '前序环节' => const Color(0xFFD97706),
                                              _ => const Color(0xFF64748B),
                                            };
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: tone.withValues(
                                                  alpha: isDark ? 0.20 : 0.10,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '${entry.key} ${entry.value}',
                                                style: DunesTypography.sans(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: DunesColors.resolve(
                                                    ctx,
                                                    tone,
                                                  ),
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
                                      style: DunesTypography.sans(
                                        fontSize: 11.5,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                if (_rows.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _filterChip(
                                        label: '全部待审 (${_rows.length})',
                                        selected: !_onlyAttention,
                                        accent: accent,
                                        subtleBg: subtleBg,
                                        text: text,
                                        onTap: () => setState(
                                          () => _onlyAttention = false,
                                        ),
                                      ),
                                      if (attentionCount > 0) ...[
                                        const SizedBox(width: 6),
                                        _filterChip(
                                          label: '预警/调分 ($attentionCount)',
                                          selected: _onlyAttention,
                                          accent: const Color(0xFFD97706),
                                          subtleBg: subtleBg,
                                          text: text,
                                          onTap: () => setState(
                                            () => _onlyAttention = true,
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (_rows.length > 4)
                                        SizedBox(
                                          width: 150,
                                          height: 32,
                                          child: TextField(
                                            controller: _searchController,
                                            onChanged: (v) =>
                                                setState(() => _query = v),
                                            style: DunesTypography.sans(
                                              fontSize: 12,
                                              color: text,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: '搜索姓名',
                                              hintStyle: DunesTypography.sans(
                                                fontSize: 12,
                                                color: muted,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.search_rounded,
                                                size: 16,
                                                color: muted,
                                              ),
                                              prefixIconConstraints:
                                                  const BoxConstraints(
                                                    minWidth: 30,
                                                  ),
                                              filled: true,
                                              fillColor: subtleBg,
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                borderSide: BorderSide.none,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: border.withValues(alpha: 0.65),
                          ),
                          Expanded(
                            child: filteredRows.isEmpty
                                ? Center(
                                    child: Text(
                                      _rows.isEmpty
                                          ? '当前没有可终审人员'
                                          : '没有符合筛选条件的人员',
                                      style: DunesTypography.sans(
                                        fontSize: 13,
                                        color: muted,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      10,
                                      18,
                                      12,
                                    ),
                                    itemCount: filteredRows.length,
                                    itemBuilder: (context, index) {
                                      final r = filteredRows[index];
                                      return _buildPersonCard(
                                        context,
                                        r,
                                        surface: surface,
                                        subtleBg: subtleBg,
                                        soft: soft,
                                        border: border,
                                        text: text,
                                        muted: muted,
                                        accent: accent,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                decoration: BoxDecoration(
                  color: subtleBg.withValues(alpha: 0.65),
                  border: Border(
                    top: BorderSide(
                      color: border.withValues(alpha: 0.65),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _busy || _error != null
                            ? ''
                            : '共 ${_rows.length} 人可终审${attentionCount > 0 ? ' · $attentionCount 人有预警或调分' : ''}',
                        style: DunesTypography.sans(fontSize: 12, color: muted),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      onPressed: _busy || _error != null || _rows.isEmpty
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              _approve();
                            },
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                      label: Text(
                        _rows.isEmpty
                            ? '部门通过并下发'
                            : '通过并下发 (${_rows.length})',
                      ),
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

  Widget _filterChip({
    required String label,
    required bool selected,
    required Color accent,
    required Color subtleBg,
    required Color text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : subtleBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: DunesTypography.sans(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? accent : text,
          ),
        ),
      ),
    );
  }

  Widget _buildPersonCard(
    BuildContext context,
    HrPerformanceRecord r, {
    required Color surface,
    required Color subtleBg,
    required Color soft,
    required Color border,
    required Color text,
    required Color muted,
    required Color accent,
  }) {
    final attn = _attention(r);
    final warnTone = DunesColors.resolve(context, const Color(0xFFD97706));
    final danger = DunesColors.resolve(context, const Color(0xFFD9383A));
    final initial = r.name.trim().isEmpty
        ? '?'
        : r.name.trim().substring(0, 1);
    final before = _initialTotals[r.id];
    final now = (r.snapshot['total'] as num?)?.toDouble();
    final hasDelta =
        before != null && now != null && (now - before).abs() > 0.00001;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: attn > 0 ? warnTone.withValues(alpha: 0.04) : subtleBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: attn > 0
              ? warnTone.withValues(alpha: 0.35)
              : border.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  initial,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  r.name,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  HapticFeedback.selectionClick();
                  openHrPerformanceRecord(
                    context,
                    widget.service.session,
                    r.id,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '明细',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ),
              if (r.actions.contains('reject_final')) ...[
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _reject(r);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '驳回',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: danger,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (r.scoresVisible && r.snapshot['total'] != null) ...[
                _metricTag('${r.snapshot['total']} 分', accent, soft),
                if ('${r.snapshot['grade'] ?? ''}'.isNotEmpty)
                  _metricTag(
                    '${r.snapshot['grade']}',
                    const Color(0xFF1A8463),
                    const Color(0xFF1F9D76).withValues(alpha: 0.12),
                  ),
                if (r.snapshot['coefficient'] != null)
                  _metricTag(
                    '系数 ${r.snapshot['coefficient']}',
                    muted,
                    surface,
                  ),
              ],
              _metricTag(
                _comparison(r),
                hasDelta ? warnTone : const Color(0xFF1A8463),
                hasDelta
                    ? warnTone.withValues(alpha: 0.12)
                    : const Color(0xFF1F9D76).withValues(alpha: 0.10),
              ),
            ],
          ),
          if (r.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: warnTone.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: warnTone,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '预警：${r.warnings.join('；')}',
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: warnTone,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricTag(String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: DunesTypography.sans(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
    ),
  );
}
