import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_detail_page.dart';
import 'hr_performance_service.dart';
import 'hr_performance_management_ui.dart';
import 'hr_performance_department_final.dart';
import 'hr_performance_sheet.dart';
import 'hr_performance_sheets.dart';
import 'hr_performance_template_ui.dart';
import 'hr_performance_task_evidence.dart';

const hrActionLabels = <String, String>{
  'hr_edit_scores': 'HR 修改评分',
  'hr_skip': '跳过当前审批',
  'hr_return': '撤回 / 回退',
  'switch_template': '切换考核模板',
  'update_bonus': '修改加减分',
  'submit_self': '提交自评',
  'request_adjustment': '申请调整',
  'approve_adjustment': '通过调整',
  'reject_adjustment': '驳回调整',
  'submit_review': '提交初评',
  'save_calibration': '调整校准分',
  'submit_calibration': '提交校准至 HR',
  'approve_hr': 'HR 通过',
  'approve_department_hr': '本部门全部通过',
  'send_department_final': '发送部门终审',
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
  'undo_exempt': '撤销免考核',
  'resign': '离职归档',
  'assign_snapshot': '补配考核表',
  'verify_history': '核对月末资料',
  'urge': '督办',
  'start': '发起考核',
  'initialize': '生成考核表',
  'match_template': '自动匹配考核表',
  'grade_policy': '等级标准调整',
  'grade_recalculate': '等级系数重算',
  'assign': '补配快照',
  'auto_indicators': '窗口结束自动确认',
  'auto_result': '超时视为确认',
  'expire_adjustment': '调整超时未批',
  'skip_self_hr': '跳过本人 HR 审核',
  'skip_executive_calibration': '跳过分管校准',
  'close_alert': '处理预警',
};
String hrDate(dynamic value) {
  final d = value is DateTime ? value : DateTime.tryParse('$value');
  if (d == null) return '—';
  final t = d.toUtc().add(const Duration(hours: 8));
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

List<String> hrAssessmentActions(HrPerformanceRecord record) => record.actions
    .where(
      (a) =>
          hrActionLabels.containsKey(a) &&
          !const [
            'approve_department_hr',
            'confirm_indicators',
            'approve_adjustment',
            'reject_adjustment',
            'resolve_appeal',
            'remove_bonus',
            'assign_snapshot',
            'verify_history',
            'send_department_final',
          ].contains(a),
    )
    .toList();

String hrAssessmentActionLabel(HrPerformanceRecord record, String action) =>
    action == 'return_hr' && record.skipsDirectReview
    ? '退回自评'
    : action == 'return_hr' && record.skipsExecutiveCalibration
    ? '退回初评'
    : hrActionLabels[action] ?? action;

String? hrAssessmentActionImpact(HrPerformanceRecord record, String action) =>
    switch (action) {
      'hr_edit_scores' => hrScoreEditImpact(record),
      'hr_return' =>
        record.released
            ? '撤销已下发结果及自动确认。回到 HR 审核后可修改评分。'
            : '目标阶段及后续审批将失效，评分草稿和历史记录保留。',
      'hr_skip' when record.stage == 'final' => '将立即下发结果给员工。',
      _ => null,
    };

String? hrAssessmentScoreBlocked(HrPerformanceRecord record) {
  if (record.stage == 'archived') return '考核已归档，评分已锁定。';
  if (record.workflow['confirmedAt'] != null &&
      record.workflow['confirmationSource'] != 'auto') {
    return '考核结果已确认，评分已锁定。';
  }
  if (record.released && record.actions.contains('hr_return')) {
    return '结果已下发。请撤回至 HR 审核后再修改评分。';
  }
  return null;
}

class HrPerformanceDetail extends StatefulWidget {
  const HrPerformanceDetail({
    super.key,
    required this.session,
    required this.record,
    required this.service,
    this.monthStarted = true,
    this.onChanged,
    this.initialAction,
    this.hrAccess = false,
  });
  final AuthSession session;
  final HrPerformanceRecord record;
  final HrPerformanceService service;
  final bool monthStarted;
  final VoidCallback? onChanged;
  final String? initialAction;
  final bool hrAccess;
  @override
  State<HrPerformanceDetail> createState() => _HrPerformanceDetailState();
}

class _HrPerformanceDetailState extends State<HrPerformanceDetail> {
  late HrPerformanceRecord _record;
  Map<String, dynamic>? _options;
  Set<int> _missing = {};
  bool _busy = false;
  bool _showFullAssessment = true;
  Future<List<Map<String, dynamic>>>? _logs;
  bool get _skipExecutiveCalibration => _record.skipsExecutiveCalibration;
  bool get _skipDirectReview => _record.skipsDirectReview;
  String get _selfSubmissionMessage {
    if (!_skipDirectReview) {
      return '提交自评后进入主管初评。自评分数会保留给主管查看。';
    }
    if (_record.selfSupervised &&
        !_skipExecutiveCalibration &&
        _record.divisionSupervisorId != _record.userId) {
      return '提交后自评分数将交由分管主管校准。';
    }
    return '提交后自评分数将直接交由 HR 审核。';
  }

  String _actionLabel(String action) =>
      hrAssessmentActionLabel(_record, action);
  @override
  void initState() {
    super.initState();
    _record = widget.record;
    final action = widget.initialAction;
    if (action != null && hrAssessmentActions(_record).contains(action)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _perform(action);
      });
    } else {
      _loadOptions();
    }
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

  String _resultConfirmationHint(HrPerformanceRecord record) {
    final rawDue = record.workflow['dueAt'];
    final due = rawDue == null ? null : DateTime.tryParse('$rawDue');
    final deadline = due == null ? '确认截止时间：未设置' : '确认截止：${hrDate(due)}（北京时间）';
    final config = _options?['config'];
    final rules = config is Map ? config['rules'] : null;
    final autoConfirm = rules is Map ? rules['autoConfirm'] : null;
    if (autoConfirm is! bool) return '$deadline\n逾期处理规则暂不可用，请稍后刷新查看。';
    if (due == null) return '$deadline\n未设置截止时间，不会按截止时间自动确认。';
    final pendingAppeal = record.requests.any(
      (r) => r['kind'] == 'appeal' && r['status'] == 'pending',
    );
    final policy = autoConfirm
        ? '到期后没有待处理申诉时，系统会自动确认结果。'
        : '到期后不会自动确认，请主动确认或提出申诉。';
    final appeal = pendingAppeal
        ? (autoConfirm ? '\n当前申诉处理中，自动确认暂缓。' : '\n当前申诉处理中。')
        : '';
    return '$deadline\n$policy$appeal';
  }

  Future<void> _perform(
    String action, {
    String? requestId,
    bool adjustFinal = false,
  }) async {
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
        case 'hr_edit_scores':
        case 'submit_self':
        case 'submit_review':
        case 'save_calibration':
          data = await showHrScoreSheet(
            context,
            _record,
            config,
            title: hrActionLabels[action]!,
            initial: action == 'submit_review' || action == 'submit_self',
            self: action == 'submit_self',
            hrEdit: action == 'hr_edit_scores',
          );
        case 'approve_final':
          if (adjustFinal) {
            data = await showHrScoreSheet(
              context,
              _record,
              config,
              title: '调整分数后通过',
              initial: false,
            );
          } else {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('确认终审通过'),
                content: Text(
                  '确认通过 ${_record.name} 的绩效考核？\n当前得分 ${_record.snapshot['total'] ?? '—'} · 等级 ${_record.snapshot['grade'] ?? '—'} · 系数 ${_record.snapshot['coefficient'] ?? '—'}\n通过后结果立即下发给员工。',
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
            data = confirmed == true ? <String, dynamic>{} : null;
          }
        case 'update_bonus':
          final bonus = _record.bonuses
              .where((b) => '${b['id']}' == requestId)
              .first;
          data = await hrFormSheet(
            context,
            title: '修改加减分',
            values: {
              'points': '${(bonus['points'] as num).abs()}',
              'source': bonus['source'],
              'reason': '',
            },
            fields: (v, update) => [
              TextFormField(
                initialValue: '${v['points']}',
                decoration: const InputDecoration(labelText: '分值（正数）'),
                onChanged: (x) => v['points'] = x,
              ),
              hrReasonField(v, label: '来源说明', keyName: 'source'),
              hrReasonField(v, label: '修改原因'),
            ],
            submit: (v) {
              if (hrNumber(v['points']) <= 0 ||
                  hrText(v['source']).isEmpty ||
                  hrText(v['reason']).isEmpty) {
                throw const FormatException('请填写分值、来源及修改原因');
              }
              return {...v, 'points': hrNumber(v['points'])};
            },
          );
        case 'hr_skip':
          data = await showHrReasonSheet(
            context,
            title: '跳过当前审批',
            minLength: 1,
            message: _record.stage == 'final'
                ? '跳过终审将立即下发结果给员工。缺少完整评分时请先使用 HR 修改评分。'
                : '仅跳过所选人员当前审批。缺少完整评分时请先使用 HR 修改评分。',
          );
        case 'hr_return':
          data = await showHrReasonSheet(
            context,
            title: '撤回 / 回退考核',
            minLength: 1,
            targets: (_options!['hrReturnTargets'] as List? ?? [])
                .map((v) => '$v')
                .toList(),
            message: hrAssessmentActionImpact(_record, action),
          );
        case 'request_adjustment':
          data = await showHrAdjustmentSheet(context, _record, _options!);
        case 'add_bonus':
          data = await showHrBonusSheet(context, config, record: _record);
        case 'switch_template':
          final templates = hrMaps(_options!['assignmentTemplates']);
          if (templates.isEmpty) {
            showDunesToast(context, '暂无其他可用的考核模板');
            return;
          }
          data = await showHrAssignmentSheet(context, _record, {
            'templates': templates,
          });
        case 'assign_snapshot':
          data = await showHrAssignmentSheet(
            context,
            _record,
            config,
            positions: hrMaps(_options!['positions']),
          );
        case 'exempt':
          data = await showHrReasonSheet(
            context,
            title: '免考核',
            message: '免考核人员保留在名单，不产生等级与系数；以后周期暂停生成。HR 可在本条考核表中撤销误操作。',
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
            targets: [
              if (!_skipDirectReview) 'review',
              if (!_skipExecutiveCalibration && !_skipDirectReview)
                'calibration',
              'hr',
              'reject',
            ],
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
                'undo_exempt',
                'remove_bonus',
                'update_bonus',
              ].contains(action) ||
              (['approve_hr', 'approve_department_hr'].contains(action) &&
                  _record.warnings.any((w) => !w.contains('不阻断提交')));
          data = await showHrReasonSheet(
            context,
            title: _actionLabel(action),
            minLength: requiredReason ? 1 : 0,
            message: action == 'return_hr' && _skipDirectReview
                ? '该考核跳过主管初评，将退回本人自评。'
                : action == 'return_hr' && _skipExecutiveCalibration
                ? '该考核跳过分管校准，将退回直属主管初评。'
                : action == 'submit_self'
                ? _selfSubmissionMessage
                : action == 'submit_calibration'
                ? '本部门由你负责校准的人员全部到达校准后，将一并提交 HR。'
                : action == 'undo_exempt'
                ? '将恢复本月免考核前的考核内容和节点，并取消本次免考核造成的后续暂停。原有截止时间保持不变，若已到期可能自动推进；已开始的其他月份不会自动补生成。'
                : action == 'urge'
                ? '向该考核当前节点的办理人发送督办消息，请填写具体提醒内容。'
                : action == 'confirm_result'
                ? '请核对得分 ${_record.snapshot['total'] ?? '—'}、等级 ${_record.snapshot['grade'] ?? '—'}、系数 ${_record.snapshot['coefficient'] ?? '—'}。确认后${_skipDirectReview ? 'HR' : '直属主管'}将收到面谈待办。'
                : _record.warnings.isNotEmpty
                ? _record.warnings.join('；')
                : null,
          );
      }
      if (data == null || !mounted) return;
      setState(() => _busy = true);
      final result =
          (action == 'assign_snapshot' || action == 'switch_template')
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
        showDunesToast(context, '${_actionLabel(action)}已完成');
      }
    } catch (e) {
      if (mounted) showDunesToast(context, '$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: hrConfigTheme(context),
    child: Builder(builder: (context) => _buildDetail(context)),
  );

  Widget _summaryValue(String label, String value, {bool highlight = false}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(
                context,
                highlight ? DunesColors.brandPurpleDeep : DunesColors.text,
              ),
            ),
          ),
        ],
      );

  String? _hrScoreAvailability(HrPerformanceRecord record, bool started) {
    if (!widget.hrAccess ||
        _options == null ||
        record.actions.contains('hr_edit_scores')) {
      return null;
    }
    if (record.stage == 'exempt') return null;
    if (hrAssessmentScoreBlocked(record) case final blocked?) return blocked;
    if (!started || record.stage == 'opening' || record.lines.isEmpty) {
      return '请先发起考核并补齐模板，再修改评分。';
    }
    if (!_options!.containsKey('hrManagementLocked')) {
      return '当前考核服务尚未提供 HR 改分功能。';
    }
    return '当前考核节点未开放 HR 改分。';
  }

  Widget _buildDetail(BuildContext context) {
    final r = _record;
    final requests = r.requests;
    final started = r.started ?? widget.monthStarted;
    final visibleActions = hrAssessmentActions(r);
    final scoreAvailability = _hrScoreAvailability(r, started);
    final primaryActions = {
      'submit_self',
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
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _HrPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.name,
                                  key: const ValueKey('hr-detail-name'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_hrMonthLabel(r.month)} · ${r.department.isEmpty ? '未分配部门' : r.department} · ${r.position.isEmpty ? '未配置岗位' : r.position}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _HrTag(label: r.stageLabel),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          if (r.snapshot['selfTotal'] != null)
                            _summaryValue('自评', '${r.snapshot['selfTotal']}'),
                          if (r.scoresVisible &&
                              r.snapshot['total'] != null) ...[
                            _summaryValue(
                              '得分',
                              '${r.snapshot['total']}',
                              highlight: true,
                            ),
                            _summaryValue(
                              '等级',
                              '${r.snapshot['grade'] ?? '—'}',
                              highlight: true,
                            ),
                            _summaryValue(
                              '系数',
                              '${r.snapshot['coefficient'] ?? '—'}',
                            ),
                          ],
                          if (r.probation) const _HrTag(label: '试用期'),
                          if (r.exemptionEligible) const _HrTag(label: '可免考核'),
                          if (r.snapshot['resigned'] == true)
                            const _HrTag(label: '已离职'),
                        ],
                      ),
                      if (r.stage == 'exempt')
                        Text(
                          '免考核：${r.workflow['exemptionReason'] ?? ''} ${r.workflow['exemptionNote'] ?? ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (!r.scoresVisible && r.stage != 'exempt')
                        const Text(
                          '结果下发后显示分数、等级和系数。',
                          style: TextStyle(fontSize: 12),
                        ),
                      if (r.stage == 'result' &&
                          r.userId == widget.session.userId)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _resultConfirmationHint(r),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (r.workflow['confirmedAt'] != null)
                        Text(
                          r.workflow['confirmationSource'] == 'auto'
                              ? '系统自动确认（未归档前 HR 可撤回）'
                              : '员工已确认，考核已锁定',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (r.stage == 'archived')
                        Text(
                          '归档：${r.workflow['archiveReason'] ?? '—'} · ${hrDate(r.workflow['archivedAt'])}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      const Divider(height: 18),
                      LayoutBuilder(
                        builder: (context, c) {
                          final fields = [
                            (
                              '调整截止',
                              started
                                  ? '${hrDate(r.adjustmentDueAt)}（北京时间）'
                                  : '开始考核后起算',
                            ),
                            (
                              '当前节点截止',
                              started ? hrDate(r.workflow['dueAt']) : '开始考核后起算',
                            ),
                            (
                              '直属主管',
                              hrText(r.snapshot['directSupervisorName']).isEmpty
                                  ? '未设置'
                                  : hrText(r.snapshot['directSupervisorName']),
                            ),
                            (
                              '分管主管',
                              hrText(
                                    r.snapshot['divisionSupervisorName'],
                                  ).isEmpty
                                  ? '未设置'
                                  : hrText(
                                      r.snapshot['divisionSupervisorName'],
                                    ),
                            ),
                          ];
                          final columns = c.maxWidth >= 720 ? 2 : 1;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              for (final field in fields)
                                SizedBox(
                                  width:
                                      (c.maxWidth - 16 * (columns - 1)) /
                                      columns,
                                  child: _HrMetaRow(
                                    label: field.$1,
                                    value: field.$2,
                                    last: true,
                                  ),
                                ),
                            ],
                          );
                        },
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
                if (scoreAvailability != null) ...[
                  const SizedBox(height: 8),
                  _HrNotice(
                    color: const Color(0xFFF4EFFB),
                    border: const Color(0xFFDDD3EE),
                    text: scoreAvailability,
                  ),
                ],
                if (visibleActions.isNotEmpty)
                  Container(
                    key: const ValueKey('hr-detail-actions'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        Colors.white,
                        role: DunesColorRole.surface,
                      ),
                      border: Border(
                        top: BorderSide(
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFFECE7F3),
                          ),
                        ),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (r.actions.contains('approve_final'))
                          _HrActionButton(
                            label: '部门终审',
                            onPressed: _busy
                                ? null
                                : () async {
                                    await showHrDepartmentFinal(
                                      context,
                                      widget.service,
                                      r.id,
                                    );
                                    widget.onChanged?.call();
                                    try {
                                      final latest = await widget.service
                                          .detail(r.id);
                                      if (!mounted) return;
                                      setState(() {
                                        _record = latest;
                                        _options = null;
                                        _logs = null;
                                      });
                                      await _loadOptions();
                                    } catch (e) {
                                      if (mounted) {
                                        showDunesToast(
                                          this.context,
                                          '刷新考核表失败：$e',
                                          kind: DunesToastKind.error,
                                        );
                                      }
                                    }
                                  },
                          ),
                        for (final a in visibleActions.where(
                          (a) =>
                              primaryActions.contains(a) ||
                              a == 'hr_edit_scores',
                        ))
                          _HrActionButton(
                            key: ValueKey('hr-action-$a'),
                            label: _actionLabel(a),
                            primary: primaryActions.contains(a),
                            onPressed: _busy ? null : () => _perform(a),
                          ),
                        for (final a in visibleActions.where(
                          (a) =>
                              !primaryActions.contains(a) &&
                              a != 'hr_edit_scores',
                        ))
                          _HrActionButton(
                            key: ValueKey('hr-action-$a'),
                            label: _actionLabel(a),
                            onPressed: _busy ? null : () => _perform(a),
                          ),
                        if (r.actions.contains('approve_final'))
                          _HrActionButton(
                            label: '调整分数后通过',
                            onPressed: _busy
                                ? null
                                : () => _perform(
                                    'approve_final',
                                    adjustFinal: true,
                                  ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final desktop =
                          MediaQuery.sizeOf(context).width >= 800 &&
                          constraints.maxWidth >= 360;
                      final sheet = HrAssessmentSheet(
                        lines: r.lines,
                        bonuses: r.bonuses,
                        finalTotal: r.snapshot['total'] as num?,
                        deductionInstructions: hrText(
                          r.snapshot['deductionInstructions'],
                        ),
                        deductionEditor: r.actions.contains('add_bonus')
                            ? HrInlineDeductionEditor(
                                onSave: (points, reason) async {
                                  final result = await widget.service
                                      .action(_record, {
                                        'action': 'add_bonus',
                                        'itemId': 'hr-regulation-deduction',
                                        'points': points,
                                        'source': reason,
                                      });
                                  if (!mounted) return;
                                  setState(() {
                                    _record = result;
                                    _options = null;
                                    _logs = null;
                                  });
                                  widget.onChanged?.call();
                                  await _loadOptions();
                                },
                              )
                            : null,
                        scoresVisible: r.scoresVisible,
                        month: _hrMonthLabel(r.month),
                        name: r.name,
                        supervisor: hrText(r.snapshot['directSupervisorName']),
                      );
                      if (!desktop) return sheet;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _showFullAssessment
                                      ? '共 ${r.lines.length} 项 · 标准与评分完整展示'
                                      : '共 ${r.lines.length} 项 · 点击指标查看评分标准',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text2,
                                    ),
                                  ),
                                ),
                              ),
                              SegmentedButton<bool>(
                                showSelectedIcon: false,
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: const WidgetStatePropertyAll(
                                    TextStyle(fontSize: 12),
                                  ),
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith(
                                        (states) => DunesColors.resolve(
                                          context,
                                          states.contains(WidgetState.selected)
                                              ? DunesColors.brandPurpleSoft
                                              : Colors.white,
                                        ),
                                      ),
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith(
                                        (states) => DunesColors.resolve(
                                          context,
                                          states.contains(WidgetState.selected)
                                              ? DunesColors.brandPurpleDeep
                                              : DunesColors.text2,
                                        ),
                                      ),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('指标总览'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('完整表格'),
                                  ),
                                ],
                                selected: {_showFullAssessment},
                                onSelectionChanged: (s) => setState(
                                  () => _showFullAssessment = s.first,
                                ),
                              ),
                            ],
                          ),
                          if (_showFullAssessment)
                            sheet
                          else
                            HrAssessmentOverview(
                              lines: r.lines,
                              scoresVisible: r.scoresVisible,
                            ),
                        ],
                      );
                    },
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
                                    fontSize: 13,
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
                          if (r.actions.contains('update_bonus'))
                            IconButton(
                              tooltip: '修改加减分',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: _busy
                                  ? null
                                  : () => _perform(
                                      'update_bonus',
                                      requestId: '${b['id']}',
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
                _HrPanel(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    key: ValueKey('hr-evidence-${r.id}'),
                    initiallyExpanded: false,
                    title: _HrSectionTitle('任务证据（${r.evidence.length}）'),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    children: [
                      if (r.evidence.isEmpty)
                        const _HrPanel(
                          child: Text(
                            '暂无已纳入的任务证据',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A8494),
                            ),
                          ),
                        )
                      else
                        for (final t in r.evidence) ...[
                          _HrPanel(
                            child: InkWell(
                              onTap:
                                  (_missing.contains(
                                        (t['id'] as num).toInt(),
                                      ) ||
                                      t['missing'] == true)
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (context) => Scaffold(
                                          appBar: AppBar(
                                            title: const Text('任务证据'),
                                          ),
                                          body: NativeTaskDetailView(
                                            session: widget.session,
                                            taskId: (t['id'] as num).toInt(),
                                            onBack: () =>
                                                Navigator.pop(context),
                                            backLabel: '考核表',
                                            forceReadOnly: true,
                                          ),
                                        ),
                                      ),
                                    ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: HrTaskEvidenceContent(
                                      task: t,
                                      ownerName: r.name,
                                      missing:
                                          _missing.contains(
                                            (t['id'] as num).toInt(),
                                          ) ||
                                          t['missing'] == true,
                                      indicatorNames: [
                                        for (final line in r.lines)
                                          if ((line['taskIds'] as List? ?? [])
                                              .contains(t['id']))
                                            hrText(line['name']),
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
                    ],
                  ),
                ),
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
                                (line) =>
                                    line['indicatorId'] == old['indicatorId'],
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
                              subtitle: Text(
                                '处理于 ${hrDate(request['handledAt'])}',
                              ),
                            ),
                          if (request['status'] == 'pending')
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final a
                                    in request['kind'] == 'adjustment'
                                        ? [
                                            'approve_adjustment',
                                            'reject_adjustment',
                                          ]
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
                        final logs = widget.service.logs(r.id);
                        setState(() {
                          _logs = logs;
                        });
                      }
                    },
                    children: [
                      if (_logs != null)
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _logs,
                          builder: (context, s) {
                            if (s.hasError) return Text('加载失败：${s.error}');
                            if (!s.hasData) {
                              return const LinearProgressIndicator();
                            }
                            final visibleLogs = s.data!
                                .where((log) => _showAuditLog(log))
                                .toList();
                            if (visibleLogs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('暂无修改记录'),
                              );
                            }
                            return Column(
                              children: [
                                for (final log in visibleLogs)
                                  ExpansionTile(
                                    title: Text(
                                      '${hrActionLabels['${log['action']}'] ?? '考核记录'}${hrText(log['reason']).isEmpty ? '' : ' · ${log['reason']}'}',
                                    ),
                                    subtitle: Text(
                                      '${_auditActor(log['actor'])} · ${hrDate(log['createdAt'])}',
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
          ),
        ],
      ),
    );
  }

  bool _showAuditLog(Map<String, dynamic> log) {
    final actor = hrText(log['actor']).toLowerCase();
    final parts = actor.split(':');
    return !parts.any(
      (part) => part.trim() == 'system' || part.trim() == 'admin',
    );
  }

  String _auditActor(dynamic value) {
    final actor = hrText(value);
    if (actor.startsWith('system:') || actor == 'system') return '系统';
    if (actor.startsWith('user:')) {
      final parts = actor.split(':');
      return parts.length > 2 && parts.last.trim().isNotEmpty
          ? parts.last
          : '操作人';
    }
    return actor.isEmpty ? '操作人' : actor;
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
    this.padding = const EdgeInsets.all(12),
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
        fontSize: 13,
        fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(vertical: 3),
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
            width: 84 * MediaQuery.textScalerOf(context).scale(1),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
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
        textStyle: DunesTypography.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}
