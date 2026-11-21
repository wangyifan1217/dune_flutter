import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
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
  bool get _isPreview => widget.payload['preview'] == true;
  bool _loadingFinal = false;
  bool _loadedFinal = false;
  Map<int, HrPerformanceRecord> _currentFinalRows = {};

  Future<void> _refreshFinalRows() async {
    if (_isPreview) return;
    if (_loadingFinal) return;
    setState(() => _loadingFinal = true);
    try {
      final records = await HrPerformanceService(
        widget.session,
      ).records('${widget.payload['month'] ?? ''}', 'all');
      final ids = hrMaps(
        widget.payload['rows'],
      ).map((row) => int.tryParse('${row['id']}')).whereType<int>().toSet();
      if (mounted) {
        setState(() {
          _currentFinalRows = {
            for (final record in records)
              if (ids.contains(record.id)) record.id: record,
          };
          _loadedFinal = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadedFinal = false);
    } finally {
      if (mounted) setState(() => _loadingFinal = false);
    }
  }

  Future<void> _rejectFinal(int id) async {
    if (_isPreview) {
      showDunesToast(context, '这是样式预览，不会执行实际驳回');
      return;
    }
    final service = HrPerformanceService(widget.session);
    try {
      final record = await service.detail(id);
      if (!mounted) return;
      if (!record.actions.contains('reject_final')) {
        showDunesToast(
          context,
          '该考核已不在您的终审待办中，请刷新',
          kind: DunesToastKind.error,
        );
        await _refreshFinalRows();
        return;
      }
      final skipReview = record.skipsDirectReview;
      final reason = await showHrReasonSheet(
        context,
        title: '驳回 ${record.name}',
        minLength: 1,
        message: skipReview ? '该人员将退回本人自评，其他人员不受影响。' : '该人员将退回主管初评，其他人员不受影响。',
      );
      if (reason == null || !mounted) return;
      await service.action(record, {'action': 'reject_final', ...reason});
      if (!mounted) return;
      showDunesToast(context, '已驳回 ${record.name}');
      await _refreshFinalRows();
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '驳回失败：$e', kind: DunesToastKind.error);
      }
    }
  }

  Future<void> _openDepartmentFinal(List<Map<String, dynamic>> rows) async {
    if (_isPreview) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('部门确认 · 样式预览'),
          content: Text(
            '实际操作时，将核对本部门 ${rows.length} 人的最新状态；确认后通过并下发。此处为静态预览，不会提交。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final ids = rows
        .map((row) => int.tryParse('${row['id']}'))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    if (ids.isEmpty) return;
    await showHrDepartmentFinal(
      context,
      HrPerformanceService(widget.session),
      ids.first,
      recordIds: ids,
      departmentName: '${widget.payload['department'] ?? ''}',
    );
    if (mounted) await _refreshFinalRows();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload, rows = hrMaps(widget.payload['rows']);
    final notice = p['hrPerformanceNotice'] == true;
    if (notice) return _noticeCard(p);
    final departmentFinal = p['hrPerformanceFinalSummary'] == true;
    final readOnlySummary = p['hrPerformanceReadOnlySummary'] == true;
    final finalStyle = departmentFinal || readOnlySummary;
    final averageCoefficient = (p['averageCoefficient'] as num?)?.toDouble();
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
                          departmentFinal
                              ? '部门绩效终审'
                              : readOnlySummary
                              ? '绩效考核汇总'
                              : '$hrPerformanceTitle汇总',
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          finalStyle
                              ? '${p['department'] ?? ''} · ${p['month'] ?? ''}'
                              : '${p['month'] ?? ''} · 发送时快照',
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
                departmentFinal
                    ? '发送时共 ${rows.length} 人待终审'
                    : readOnlySummary
                    ? '发送时共 ${rows.length} 人 · 绩效快照'
                    : '共 ${rows.length} 人${p['hasScores'] == true ? ' · 含已下发结果' : ' · 考核进度'}',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
            if (finalStyle)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        readOnlySummary ? '已评分人员平均系数' : '部门平均系数',
                        style: DunesTypography.sans(fontSize: 12, color: muted),
                      ),
                    ),
                    Text(
                      averageCoefficient?.toStringAsFixed(2) ?? '—',
                      style: DunesTypography.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
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
                  for (final row
                      in _expanded
                          ? rows
                          : finalStyle
                          ? <Map<String, dynamic>>[]
                          : rows.take(5))
                    if (finalStyle)
                      _finalPersonRow(
                        row,
                        text,
                        muted,
                        accent,
                        readOnly: readOnlySummary,
                      )
                    else
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
            if (!finalStyle && rows.length > 5)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  textStyle: DunesTypography.sans(fontSize: 12),
                ),
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded && departmentFinal) _refreshFinalRows();
                },
                child: Text(_expanded ? '收起人员' : '展开全部 ${rows.length} 人'),
              ),
            if (readOnlySummary && rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                child: OutlinedButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? '收起人员' : '展开人员（${rows.length}）'),
                ),
              ),
            if (departmentFinal && rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.45),
                          ),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          setState(() => _expanded = !_expanded);
                          if (_expanded) _refreshFinalRows();
                        },
                        child: Text(
                          _expanded ? '收起人员' : '展开人员（${rows.length}）',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: accent.withValues(
                            alpha: 0.35,
                          ),
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _loadingFinal
                            ? null
                            : () => _openDepartmentFinal(rows),
                        child: const Text('部门确认'),
                      ),
                    ),
                  ],
                ),
              ),
            if (p['createdAt'] != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  departmentFinal && _loadedFinal
                      ? '发送于 ${hrDate(p['createdAt'])} · 人员状态已刷新'
                      : '发送于 ${hrDate(p['createdAt'])} · 发送时快照',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _finalPersonRow(
    Map<String, dynamic> row,
    Color text,
    Color muted,
    Color accent, {
    bool readOnly = false,
  }) {
    final id = int.tryParse('${row['id']}') ?? 0;
    final current = _currentFinalRows[id];
    final total = _loadedFinal && current != null
        ? current.snapshot['total']
        : row['total'];
    final grade = _loadedFinal && current != null
        ? current.snapshot['grade']
        : row['grade'];
    final stage = readOnly
        ? (hrPerformanceStageLabels['${row['stage']}'] ?? '考核中')
        : (_loadedFinal ? (current?.stageLabel ?? '无法查看') : '发送时待终审');
    final canReject =
        id > 0 &&
        !_loadingFinal &&
        (!_loadedFinal || (current?.actions.contains('reject_final') ?? false));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['name'] ?? ''} · ${row['department'] ?? ''}',
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
                  '${total ?? '—'} 分${grade == null || '$grade'.isEmpty ? '' : ' · $grade'}${row['coefficient'] == null ? '' : ' · 系数 ${row['coefficient']}'} · $stage',
                  style: DunesTypography.sans(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          if (!readOnly)
            TextButton(
              onPressed: canReject ? () => _rejectFinal(id) : null,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('驳回'),
            ),
          if (!readOnly)
            TextButton(
              onPressed: _isPreview
                  ? () => showDunesToast(context, '这是样式预览，不打开真实考核表')
                  : id > 0
                  ? () => openHrPerformanceRecord(context, widget.session, id)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('查看'),
            ),
        ],
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
    final transition = RegExp(
      r'^(\d{4}-\d{2}) · (.+)：当前节点 (.+)，请进入人事绩效查看。$',
    ).firstMatch(body);
    if (transition != null) {
      return _transitionCard(transition, recordId);
    }
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

  Widget _transitionCard(RegExpMatch transition, int recordId) {
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
    final soft = DunesColors.resolve(
      context,
      DunesColors.brandPurpleSoft,
      role: DunesColorRole.surface,
    );
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text2);
    final accent = DunesColors.resolve(context, DunesColors.brandPurple);
    final caption = widget.caption?.trim() ?? '';
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.fact_check_outlined,
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '绩效考核待办',
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                  ),
                  if (caption.isNotEmpty)
                    Text(caption, style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                '${transition.group(2)} · ${transition.group(1)} 考核',
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '发送时节点：${transition.group(3)}',
                style: DunesTypography.sans(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: border),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '当前进度请查看考核表',
                      style: DunesTypography.sans(fontSize: 11, color: muted),
                    ),
                  ),
                  if (recordId > 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 36),
                        textStyle: DunesTypography.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}
