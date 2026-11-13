import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_service.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_detail_page.dart';
import 'hr_performance_service.dart';
import 'hr_performance_sheet.dart';
import 'hr_performance_sheets.dart';

const hrActionLabels = <String, String>{
  'confirm_indicators': '确认无误',
  'request_adjustment': '申请调整',
  'approve_adjustment': '通过调整',
  'reject_adjustment': '驳回调整',
  'submit_review': '提交初评',
  'save_calibration': '调整校准分',
  'submit_calibration': '整部门提交 HR',
  'approve_hr': 'HR 通过',
  'approve_department_hr': '本部门全部通过',
  'return_hr': '退回校准',
  'approve_final': '终审通过并下发',
  'reject_final': '驳回至初评',
  'confirm_result': '确认结果',
  'request_appeal': '发起申诉',
  'resolve_appeal': '处理申诉',
  'complete_interview': '面谈完成并归档',
  'add_bonus': '录入加减分',
  'remove_bonus': '移除加减分',
  'exempt': '免考核',
  'resign': '离职归档',
  'assign_snapshot': '补配考核表',
  'verify_history': '核对月末资料',
  'urge': '督办',
  'initialize': '初始化',
  'assign': '补配快照',
  'auto_indicators': '窗口结束自动确认',
  'auto_result': '超时视为确认',
  'expire_adjustment': '调整超时未批',
  'skip_self_hr': '跳过本人 HR 审核',
  'close_alert': '处理预警',
};
String hrDate(dynamic value) {
  final d = value is DateTime ? value : DateTime.tryParse('$value');
  if (d == null) return '—';
  final t = d.toUtc().add(const Duration(hours: 8));
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class HrPerformanceDetail extends StatefulWidget {
  const HrPerformanceDetail({
    super.key,
    required this.session,
    required this.record,
    required this.service,
    this.onChanged,
  });
  final AuthSession session;
  final HrPerformanceRecord record;
  final HrPerformanceService service;
  final VoidCallback? onChanged;
  @override
  State<HrPerformanceDetail> createState() => _HrPerformanceDetailState();
}

class _HrPerformanceDetailState extends State<HrPerformanceDetail> {
  late HrPerformanceRecord _record;
  Map<String, dynamic>? _options;
  Set<int> _missing = {};
  bool _busy = false;
  Future<List<Map<String, dynamic>>>? _logs;
  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _loadOptions();
  }

  @override
  void didUpdateWidget(covariant HrPerformanceDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.version != widget.record.version) {
      _record = widget.record;
      _options = null;
      _logs = null;
      _loadOptions();
    }
  }

  Future<void> _loadOptions() async {
    try {
      final data = await widget.service.options(_record.id);
      if (!mounted) return;
      setState(() {
        _options = data;
        _missing = (data['missingTaskIds'] as List? ?? [])
            .map((x) => (x as num).toInt())
            .toSet();
      });
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '考核选项加载失败：$e', kind: DunesToastKind.error);
      }
    }
  }

  Future<void> _perform(String action, {String? requestId}) async {
    if (_busy) return;
    Map<String, dynamic>? data;
    try {
      if (_options == null) {
        await _loadOptions();
        if (!mounted || _options == null) return;
      }
      final config = Map<String, dynamic>.from(_options!['config'] as Map);
      final rules = Map<String, dynamic>.from(config['rules'] as Map? ?? {});
      if (!mounted) return;
      switch (action) {
        case 'submit_review':
        case 'save_calibration':
        case 'approve_final':
          data = await showHrScoreSheet(
            context,
            _record,
            config,
            title: hrActionLabels[action]!,
            initial: action == 'submit_review',
          );
        case 'request_adjustment':
          data = await showHrAdjustmentSheet(context, _record, _options!);
        case 'add_bonus':
          data = await showHrBonusSheet(context, config);
        case 'assign_snapshot':
          final contacts = await ContactService(
            session: widget.session,
          ).fetchContacts();
          if (!mounted) return;
          data = await showHrAssignmentSheet(
            context,
            _record,
            config,
            contacts,
            departments: hrMaps(_options!['departments']),
            positions: hrMaps(_options!['positions']),
          );
        case 'exempt':
          data = await showHrReasonSheet(
            context,
            title: '免考核',
            message: '免考核人员保留在名单，不产生等级与系数；以后周期暂停生成，HR 可在后台恢复参与。',
            targets: (config['exemptionReasons'] as List)
                .map((x) => '$x')
                .toList(),
          );
        case 'resign':
          data = await hrFormSheet(
            context,
            title: '离职归档',
            values: {'reason': '', 'date': '${_record.month}-01'},
            fields: (v, update) => [
              TextFormField(
                initialValue: '${v['date']}',
                decoration: const InputDecoration(
                  labelText: '考核月内离职日期（YYYY-MM-DD）',
                ),
                onChanged: (x) => v['date'] = x,
              ),
              hrReasonField(v),
            ],
            submit: (v) {
              if (DateTime.tryParse(hrText(v['date'])) == null ||
                  hrText(v['reason']).isEmpty) {
                throw const FormatException('请填写有效离职日期和说明');
              }
              return {'date': v['date'], 'reason': hrText(v['reason'])};
            },
          );
        case 'resolve_appeal':
          data = await showHrReasonSheet(
            context,
            title: '处理绩效申诉',
            targets: ['review', 'calibration', 'hr', 'reject'],
            minLength: 1,
            message: '先提交的处理结果生效。退回后，该节点及后续审核作废。',
          );
        case 'request_appeal':
          data = await showHrReasonSheet(
            context,
            title: '发起绩效申诉',
            minLength: (rules['appealMinLength'] as num?)?.toInt() ?? 10,
            message: '说明具体争议和依据。处理人会指定退回节点。',
          );
        default:
          final requiredReason =
              const [
                'approve_adjustment',
                'reject_adjustment',
                'return_hr',
                'reject_final',
                'complete_interview',
                'verify_history',
                'urge',
                'remove_bonus',
              ].contains(action) ||
              (['approve_hr', 'approve_department_hr'].contains(action) &&
                  _record.warnings.any((w) => !w.contains('不阻断提交')));
          data = await showHrReasonSheet(
            context,
            title: hrActionLabels[action] ?? action,
            minLength: requiredReason ? 1 : 0,
            message: action == 'confirm_indicators'
                ? '确认后将进入主管初评，调整窗口内也不能再次改动。'
                : action == 'submit_calibration'
                ? '本部门符合条件的人员全部到达校准后，将一并提交 HR；已进入后续节点的人员保持原节点。'
                : action == 'confirm_result'
                ? '确认后直属主管将收到面谈待办。'
                : _record.warnings.isNotEmpty
                ? _record.warnings.join('；')
                : null,
          );
      }
      if (data == null || !mounted) return;
      setState(() => _busy = true);
      final result = action == 'assign_snapshot'
          ? await widget.service.assign(_record, data)
          : await widget.service.action(_record, {
              'action': action,
              ...data,
              'requestId': ?requestId,
            });
      if (!mounted) return;
      setState(() {
        _record = result;
        _options = null;
        _logs = null;
      });
      widget.onChanged?.call();
      await _loadOptions();
      if (mounted) {
        showDunesToast(context, '${hrActionLabels[action] ?? '操作'}已完成');
      }
    } catch (e) {
      if (mounted) showDunesToast(context, '$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    final requests = r.requests;
    final visibleActions = r.actions
        .where(
          (a) => ![
            'approve_adjustment',
            'reject_adjustment',
            'resolve_appeal',
            'remove_bonus',
          ].contains(a),
        )
        .toList();
    final primaryActions = {
      'confirm_indicators',
      'submit_review',
      'submit_calibration',
      'approve_hr',
      'approve_final',
      'confirm_result',
      'complete_interview',
    };
    return Material(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF7F4FC),
        role: DunesColorRole.surface,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _HrPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, DunesColors.text),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_hrMonthLabel(r.month)} · ${r.department.isEmpty ? '未分配部门' : r.department} · ${r.position.isEmpty ? '未配置岗位' : r.position}',
                  style: TextStyle(
                    fontSize: 13,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HrTag(label: r.stageLabel),
                    if (r.probation) const _HrTag(label: '试用期'),
                    if (r.exemptionEligible) const _HrTag(label: '可免考核'),
                    if (r.snapshot['resigned'] == true)
                      const _HrTag(label: '已离职'),
                  ],
                ),
                const SizedBox(height: 12),
                if (r.scoresVisible && r.snapshot['total'] != null)
                  Text(
                    '得分 ${r.snapshot['total']} · ${r.snapshot['grade']} · 系数 ${r.snapshot['coefficient']}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurpleDeep,
                      ),
                    ),
                  )
                else if (r.stage == 'exempt')
                  Text(
                    '免考核：${r.workflow['exemptionReason'] ?? ''} ${r.workflow['exemptionNote'] ?? ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  )
                else if (r.stage == 'archived')
                  Text(
                    '归档：${r.workflow['archiveReason'] ?? ''} · ${hrDate(r.workflow['archivedAt'])}',
                    style: TextStyle(
                      fontSize: 13,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  )
                else
                  const Text(
                    '结果下发后显示分数、等级和系数。',
                    style: TextStyle(fontSize: 13, color: Color(0xFF8A8494)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _HrPanel(
            child: Column(
              children: [
                _HrMetaRow(
                  label: '调整截止',
                  value: '${hrDate(r.adjustmentDueAt)}（北京时间）',
                ),
                if (r.workflow['dueAt'] != null)
                  _HrMetaRow(
                    label: '当前节点截止',
                    value: hrDate(r.workflow['dueAt']),
                  ),
                _HrMetaRow(
                  label: '直属主管',
                  value: '${r.snapshot['directSupervisorName'] ?? '待补配'}',
                ),
                _HrMetaRow(
                  label: '分管主管',
                  value: '${r.snapshot['divisionSupervisorName'] ?? '待补配'}',
                  last: true,
                ),
              ],
            ),
          ),
          if (r.blockers.isNotEmpty) ...[
            const SizedBox(height: 10),
            _HrNotice(
              color: const Color(0xFFFFF8EE),
              border: const Color(0xFFF0E2C8),
              text: r.blockers.join('；'),
            ),
          ],
          if (r.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            _HrNotice(
              color: const Color(0xFFF4EFFB),
              border: const Color(0xFFDDD3EE),
              text: '预警：${r.warnings.join('；')}',
            ),
          ],
          if (hrText(_options?['taskSourceError']).isNotEmpty) ...[
            const SizedBox(height: 10),
            _HrNotice(
              color: const Color(0xFFFFF8EE),
              border: const Color(0xFFF0E2C8),
              text: hrText(_options?['taskSourceError']),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (visibleActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in visibleActions)
                  _HrActionButton(
                    key: ValueKey('hr-action-$a'),
                    label: hrActionLabels[a] ?? a,
                    primary: primaryActions.contains(a),
                    onPressed: _busy ? null : () => _perform(a),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _HrSectionTitle(
            '考核指标${hrText(r.snapshot['templateName']).isEmpty ? '' : ' · ${r.snapshot['templateName']}'}',
          ),
          const SizedBox(height: 8),
          if (r.lines.isEmpty)
            const _HrPanel(
              child: Text(
                '考核表待指定，匹配完成前没有指标。',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8494)),
              ),
            )
          else
            HrAssessmentSheet(
              lines: r.lines,
              scoresVisible: r.scoresVisible,
              month: _hrMonthLabel(r.month),
              name: r.name,
              supervisor: hrText(r.snapshot['directSupervisorName']),
            ),
          if (r.bonuses.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _HrSectionTitle('本月加减分'),
            const SizedBox(height: 8),
            for (final b in r.bonuses) ...[
              _HrPanel(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b['name']} · ${b['points']} 分',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (hrText(b['source']).isNotEmpty)
                            Text(
                              hrText(b['source']),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A8494),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (r.actions.contains('remove_bonus'))
                      IconButton(
                        tooltip: '移除加减分',
                        onPressed: _busy
                            ? null
                            : () => _perform(
                                'remove_bonus',
                                requestId: '${b['id']}',
                              ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 8),
          _HrSectionTitle('任务证据（${r.evidence.length}）'),
          const SizedBox(height: 8),
          if (r.evidence.isEmpty)
            const _HrPanel(
              child: Text(
                '暂无已纳入的任务证据',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8494)),
              ),
            )
          else
            for (final t in r.evidence) ...[
              _HrPanel(
                child: InkWell(
                  onTap: _missing.contains((t['id'] as num).toInt())
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => Scaffold(
                              appBar: AppBar(title: const Text('任务证据')),
                              body: NativeTaskDetailView(
                                session: widget.session,
                                taskId: (t['id'] as num).toInt(),
                                onBack: () => Navigator.pop(context),
                                backLabel: '考核表',
                                forceReadOnly: true,
                              ),
                            ),
                          ),
                        ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${t['title']}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${hrDate(t['completedAt'])}${_missing.contains((t['id'] as num).toInt()) ? ' · 原任务已不存在' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A8494),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8A8494),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 8),
          const _HrSectionTitle('调整与申诉记录'),
          const SizedBox(height: 8),
          if (requests.isEmpty)
            const _HrPanel(
              child: Text(
                '本周期还没有调整或申诉。',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8494)),
              ),
            )
          else
            for (final request in requests) ...[
              _HrPanel(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  key: ValueKey('hr-request-${request['id']}'),
                  title: Text(
                    '${request['kind'] == 'adjustment' ? '指标调整' : '绩效申诉'} · ${const {'pending': '待处理', 'approved': '已通过', 'rejected': '已驳回', 'expired': '超时未批'}[request['status']] ?? request['status']}',
                  ),
                  subtitle: Text('${request['reason']}'),
                  children: [
                    if (request['kind'] == 'adjustment') ...[
                      for (final l in hrMaps(request['lines']))
                        ListTile(
                          title: Text('${l['name']}'),
                          subtitle: Text(
                            '原权重 ${r.lines.where((x) => x['indicatorId'] == l['indicatorId']).map((x) => x['weight']).firstOrNull ?? '未纳入'}% → 申请权重 ${l['weight']}%',
                          ),
                        ),
                      for (final old in r.lines.where(
                        (old) => !hrMaps(request['lines']).any(
                          (line) => line['indicatorId'] == old['indicatorId'],
                        ),
                      ))
                        ListTile(
                          title: Text(
                            '剔除指标：${old['name']}（原权重 ${old['weight']}%）',
                          ),
                        ),
                      for (final t in hrMaps(request['evidence']))
                        ListTile(
                          title: Text(
                            '${r.evidence.any((old) => old['id'] == t['id']) ? '保留任务' : '补录任务'}：${t['title']}',
                          ),
                        ),
                      for (final old in r.evidence.where(
                        (old) => !hrMaps(
                          request['evidence'],
                        ).any((t) => t['id'] == old['id']),
                      ))
                        ListTile(title: Text('剔除任务：${old['title']}')),
                    ],
                    if (hrText(request['resolution']).isNotEmpty)
                      ListTile(
                        title: Text('${request['resolution']}'),
                        subtitle: Text('处理于 ${hrDate(request['handledAt'])}'),
                      ),
                    if (request['status'] == 'pending')
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final a
                              in request['kind'] == 'adjustment'
                                  ? ['approve_adjustment', 'reject_adjustment']
                                  : ['resolve_appeal'])
                            if (r.actions.contains(a))
                              _HrActionButton(
                                label: hrActionLabels[a]!,
                                onPressed: _busy
                                    ? null
                                    : () => _perform(
                                        a,
                                        requestId: '${request['id']}',
                                      ),
                              ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 8),
          _HrPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text('修改记录'),
              onExpansionChanged: (open) {
                if (open && _logs == null) {
                  setState(() => _logs = widget.service.logs(r.id));
                }
              },
              children: [
                if (_logs != null)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _logs,
                    builder: (context, s) {
                      if (s.hasError) return Text('加载失败：${s.error}');
                      if (!s.hasData) return const LinearProgressIndicator();
                      return Column(
                        children: [
                          for (final log in s.data!)
                            ExpansionTile(
                              title: Text(
                                '${hrActionLabels['${log['action']}'] ?? log['action']} · ${log['reason']}',
                              ),
                              subtitle: Text(
                                '${log['actor']} · ${hrDate(log['createdAt'])}',
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(_logChanges(log)),
                                ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _logChanges(Map<String, dynamic> log) {
    Map<String, dynamic> snap(dynamic v) => v is Map && v['snapshot'] is Map
        ? Map<String, dynamic>.from(v['snapshot'])
        : {};
    final before = snap(log['before']), after = snap(log['after']);
    final changes = <String>[];
    for (final f in {
      'templateName': '模板',
      'directSupervisorName': '直属主管',
      'divisionSupervisorName': '分管主管',
      'total': '总分',
      'grade': '等级',
      'coefficient': '系数',
    }.entries) {
      if (before[f.key] != after[f.key]) {
        changes.add(
          '${f.value}：${before[f.key] ?? '—'} → ${after[f.key] ?? '—'}',
        );
      }
    }
    final oldLines = hrMaps(before['lines']);
    for (final l in hrMaps(after['lines'])) {
      final old = oldLines
          .where((x) => x['indicatorId'] == l['indicatorId'])
          .firstOrNull;
      for (final key in ['weight', 'score', 'remark']) {
        if (old?[key] != l[key]) {
          changes.add(
            '${l['name']} ${key == 'weight'
                ? '权重'
                : key == 'score'
                ? '得分'
                : '备注'}：${old?[key] ?? '—'} → ${l[key] ?? '—'}',
          );
        }
      }
    }
    if (log['before'] is Map &&
        log['after'] is Map &&
        (log['before'] as Map)['stage'] != (log['after'] as Map)['stage']) {
      changes.insert(
        0,
        '节点：${hrPerformanceStageLabels[(log['before'] as Map)['stage']] ?? '—'} → ${hrPerformanceStageLabels[(log['after'] as Map)['stage']] ?? '—'}',
      );
    }
    Map<String, dynamic> flow(Map<String, dynamic> snapshot) =>
        snapshot['workflow'] is Map
        ? Map<String, dynamic>.from(snapshot['workflow'])
        : {};
    final oldFlow = flow(before), newFlow = flow(after);
    final oldBonus = hrMaps(oldFlow['bonuses']),
        newBonus = hrMaps(newFlow['bonuses']);
    for (final b in newBonus.where(
      (b) => !oldBonus.any((o) => o['id'] == b['id']),
    )) {
      changes.add('新增加减分：${b['name']} ${b['points']} 分；来源 ${b['source']}');
    }
    for (final b in oldBonus.where(
      (b) => !newBonus.any((o) => o['id'] == b['id']),
    )) {
      changes.add('移除加减分：${b['name']} ${b['points']} 分');
    }
    for (final request in hrMaps(newFlow['requests'])) {
      final old = hrMaps(
        oldFlow['requests'],
      ).where((p) => p['id'] == request['id']).firstOrNull;
      if (old?['status'] != request['status']) {
        changes.add(
          '${request['kind'] == 'appeal' ? '申诉' : '调整申请'}：${old?['status'] ?? '无'} → ${request['status']}',
        );
        if (request['kind'] == 'adjustment') {
          for (final line in hrMaps(request['lines'])) {
            changes.add('申请指标：${line['name']} ${line['weight']}%');
          }
        }
      }
    }
    return changes.isEmpty ? '${log['reason']}' : changes.join('\n');
  }
}

String _hrMonthLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final m = int.tryParse(parts[1]);
  return m == null ? month : '${parts[0]}年$m月';
}

class _HrPanel extends StatelessWidget {
  const _HrPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final color = DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: DunesColors.resolve(
              context,
              const Color(0xFFECE7F3),
              role: DunesColorRole.border,
            ),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _HrSectionTitle extends StatelessWidget {
  const _HrSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: DunesColors.resolve(context, DunesColors.text),
      ),
    );
  }
}

class _HrTag extends StatelessWidget {
  const _HrTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          DunesColors.brandPurpleSoft,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DunesColors.resolve(context, DunesColors.brandPurpleDeep),
        ),
      ),
    );
  }
}

class _HrMetaRow extends StatelessWidget {
  const _HrMetaRow({
    required this.label,
    required this.value,
    this.last = false,
  });
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFECE7F3),
                    role: DunesColorRole.border,
                  ),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HrNotice extends StatelessWidget {
  const _HrNotice({
    required this.color,
    required this.border,
    required this.text,
  });
  final Color color;
  final Color border;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          color,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: DunesColors.resolve(context, DunesColors.text),
        ),
      ),
    );
  }
}

class _HrActionButton extends StatelessWidget {
  const _HrActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: primary
            ? Colors.white
            : DunesColors.resolve(context, DunesColors.brandPurpleDeep),
        backgroundColor: DunesColors.resolve(
          context,
          primary ? DunesColors.brandPurple : DunesColors.brandPurpleSoft,
          role: DunesColorRole.surface,
        ),
        disabledForegroundColor: DunesColors.resolve(
          context,
          DunesColors.text3,
        ),
        disabledBackgroundColor: DunesColors.resolve(
          context,
          const Color(0xFFF3F1F6),
          role: DunesColorRole.surface,
        ),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
