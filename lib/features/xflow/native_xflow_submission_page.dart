import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'approval_chat_forward.dart';
import 'approval_chat_share.dart';
import 'xflow_detail_comments.dart';
import 'xflow_detail_logic.dart';
import 'xflow_detail_widgets.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

/// Detail view for dynamic submissions (everything except PROPOSAL).
/// Supports both initiator actions and approver actions from inbox.
class NativeXflowSubmissionPage extends StatefulWidget {
  const NativeXflowSubmissionPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.businessType,
    required this.businessId,
    required this.backScreen,
    required this.onEdit,
    this.todoHint,
    this.onApprovalCompleted,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String businessType;
  final int businessId;
  final String backScreen;
  final VoidCallback onEdit;
  final XflowTodoHint? todoHint;
  final VoidCallback? onApprovalCompleted;

  @override
  State<NativeXflowSubmissionPage> createState() =>
      _NativeXflowSubmissionPageState();
}

class _NativeXflowSubmissionPageState extends State<NativeXflowSubmissionPage> {
  late final XflowService _service;
  XflowSubmissionDetail? _detail;
  XflowTemplateDetail? _template;
  XflowApprovalTrail? _trail;
  XflowTodoHint? _myTodo;
  Map<int, String> _assigneeNames = const {};
  String? _error;
  bool _loading = true;
  bool _forwarding = false;

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.fetchSubmissionDetail(
        businessType: widget.businessType,
        businessId: widget.businessId,
      );
      final results = await Future.wait([
        _service.fetchTemplateDetail(templateKey: detail.templateKey),
        _service.fetchSubmissionTrail(
          businessType: detail.businessType,
          businessId: detail.businessId,
        ),
        _service.findMyOpenTodo(
          businessType: widget.businessType,
          businessId: widget.businessId,
        ),
      ]);
      final trail = results[1] as XflowApprovalTrail?;
      final assigneeNames = await _service.fetchSubmissionAssigneeNames(
        trail: trail,
        createdById: detail.createdById,
      );
      if (!mounted) return;
      final myTodo = results[2] as XflowTodoHint?;
      setState(() {
        _detail = detail;
        _template = results[0] as XflowTemplateDetail;
        _trail = trail;
        _myTodo = myTodo;
        _assigneeNames = assigneeNames;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _forwardApproval() async {
    final detail = _detail;
    final template = _template;
    if (detail == null || _forwarding) return;
    setState(() => _forwarding = true);
    try {
      final title = (template?.title.trim().isNotEmpty == true)
          ? template!.title.trim()
          : (detail.title.trim().isEmpty ? '审批单' : detail.title.trim());
      final share = ApprovalChatShare(
        businessType: detail.businessType,
        businessId: detail.businessId,
        title: title,
        status: _resolvedStatus,
        templateKey: detail.templateKey,
        code: detail.businessId > 0 ? '#${detail.businessId}' : '',
      );
      await forwardApprovalToConversation(
        context: context,
        session: widget.session,
        share: share,
      );
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
  }

  bool get _isApprover => _myTodo != null;

  bool get _canWithdraw {
    if (_isApprover) return false;
    final detail = _detail;
    return detail != null &&
        detail.status.toUpperCase() == 'PENDING' &&
        !(_trail?.steps.any((step) => step.decision.trim().isNotEmpty) ?? true);
  }

  Future<void> _withdraw() async {
    final detail = _detail;
    if (detail == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回审批'),
        content: const Text('确认撤回？已填写的表单会保留为草稿，可修改后重新提交。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.withdrawSubmission(
        businessType: detail.businessType,
        businessId: detail.businessId,
      );
      if (!mounted) return;
      showDunesToast(context, '审批已撤回，已保存为草稿');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '撤回失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _approve(String comment) async {
    final todo = _myTodo;
    if (todo == null) return;
    if (todo.id <= 0) {
      showDunesToast(context, '预览模式：不会真正提交审批');
      return;
    }
    await _service.completeTodo(
      todoId: todo.id,
      approve: true,
      comment: comment,
    );
    if (!mounted) return;
    showDunesToast(context, '已通过审批');
    widget.onApprovalCompleted?.call();
    await _load();
  }

  Future<void> _reject(String comment) async {
    final todo = _myTodo;
    if (todo == null) return;
    if (todo.id <= 0) {
      showDunesToast(context, '预览模式：不会真正提交审批');
      return;
    }
    await _service.completeTodo(
      todoId: todo.id,
      approve: false,
      comment: comment,
    );
    if (!mounted) return;
    showDunesToast(context, '已驳回');
    widget.onApprovalCompleted?.call();
    await _load();
  }

  String get _submitterName {
    final detail = _detail;
    if (detail != null) {
      final fromDetail = detail.createdByName.trim();
      if (fromDetail.isNotEmpty) return fromDetail;
      if (detail.createdById > 0) {
        final fromMap = _assigneeNames[detail.createdById]?.trim() ?? '';
        if (fromMap.isNotEmpty) return fromMap;
      }
    }
    final trail = _trail;
    if (trail != null) {
      final fromTrail = (trail.raw['initiatorName'] ?? '').toString().trim();
      if (fromTrail.isNotEmpty) return fromTrail;
      if (trail.initiatorId > 0) {
        return _assigneeNames[trail.initiatorId]?.trim() ?? '';
      }
    }
    return '';
  }

  XflowDetailBundle? get _detailBundle {
    final detail = _detail;
    final template = _template;
    if (detail == null || template == null) return null;
    final submitter = _submitterName;
    final proposalDetail = XflowProposalDetail(
      id: detail.businessId,
      code: '#${detail.businessId}',
      title: template.title,
      status: _resolvedStatus,
      summary: '',
      beaconId: '',
      ownerName: submitter,
      amountText: '',
      formValues: detail.formData,
      products: const [],
      slots: const [],
      createdById: detail.createdById,
      raw: <String, dynamic>{
        'createdAt': detail.createdAt?.toIso8601String(),
        'createdById': detail.createdById,
        'createdBy': submitter,
        'createdByName': submitter,
        'businessType': detail.businessType,
      },
    );
    return XflowDetailBundle(
      detail: proposalDetail,
      trail: _trail,
      fields: template.fields,
      detailConfig: const <String, dynamic>{'showApprovalFlow': true},
      stages: template.stages,
      myTodo: _myTodo,
      assigneeNames: _assigneeNames,
      layout: template.layout,
    );
  }

  List<ApprovalStakeholderPerson> _fallbackStakeholders(XflowDetailBundle bundle) {
    final out = <ApprovalStakeholderPerson>[];
    final seen = <int>{};
    void add(int id, String name) {
      if (id <= 0 || seen.contains(id)) return;
      seen.add(id);
      out.add(
        ApprovalStakeholderPerson(
          id: id,
          displayName: name.trim().isEmpty ? '用户$id' : name.trim(),
        ),
      );
    }
    for (final e in bundle.assigneeNames.entries) {
      add(e.key, e.value);
    }
    final createdBy = bundle.detail.createdById;
    if (createdBy > 0) {
      add(createdBy, bundle.detail.ownerName);
    }
    return out;
  }

  String get _resolvedStatus {
    final detail = _detail;
    final trail = _trail;
    if (trail != null) {
      final ts = trail.status.toUpperCase();
      if (ts == 'APPROVED' ||
          ts == 'REJECTED' ||
          ts == 'CANCELLED' ||
          ts == 'VOIDED') {
        return ts;
      }
      if (trail.steps.isNotEmpty &&
          trail.steps.every((s) => s.decision.trim().isNotEmpty)) {
        final rejected = trail.steps.any(
          (s) => s.decision.trim().toUpperCase() == 'REJECTED',
        );
        return rejected ? 'REJECTED' : 'APPROVED';
      }
    }
    return (detail?.status ?? '').trim().isEmpty
        ? 'PENDING'
        : detail!.status;
  }

  XflowProposalDetail? get _heroDetail {
    final detail = _detail;
    final template = _template;
    if (detail == null) return null;
    final form = detail.formData;
    final formTitle = (template?.title.trim().isNotEmpty == true)
        ? template!.title.trim()
        : (detail.title.trim().isEmpty ? '审批详情' : detail.title.trim());
    final submitter = _submitterName.trim();
    final title = submitter.isEmpty ? formTitle : '$submitter - $formTitle';
    final code = detail.businessId > 0
        ? 'S-${detail.businessId}'
        : (detail.templateKey.isEmpty ? '—' : detail.templateKey);
    // 仅展示表单里真实有的字段，不编造「C 级」等默认值。
    final tag1 = (form['tag1'] ?? form['businessSegment'] ?? form['proposalType'] ?? '')
        .toString()
        .trim();
    final taskLevel = (form['taskLevel'] ?? form['level'] ?? '').toString().trim();
    final coverage = form['provinces'] ?? form['coverage'] ?? form['region'];
    return XflowProposalDetail(
      id: detail.businessId,
      code: code,
      title: title,
      status: _resolvedStatus,
      summary: '',
      beaconId: '',
      ownerName: submitter,
      amountText: (form['totalAmount'] ?? form['amount'] ?? '').toString(),
      formValues: form,
      products: const [],
      slots: const [],
      createdById: detail.createdById,
      raw: <String, dynamic>{
        if (tag1.isNotEmpty) 'tag1': tag1,
        if (taskLevel.isNotEmpty) 'taskLevel': taskLevel,
        if (coverage != null) 'coverage': coverage,
        'createdAt': detail.createdAt?.toIso8601String(),
        'createdByName': submitter,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final bundle = _detailBundle;
    final hero = _heroDetail;
    final formTitle = _template?.title ?? detail?.title ?? '提交详情';
    final submitter = _submitterName.trim();
    final titledForm =
        submitter.isEmpty ? formTitle : '$submitter - $formTitle';
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XflowDsBar(
              crumb: '动态审批 · 返回列表',
              title: formTitle,
              onBack: () => widget.navigation.popTo(widget.backScreen),
              onForward:
                  detail == null ? null : () => unawaited(_forwardApproval()),
              forwarding: _forwarding,
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? Center(child: Text(_error!))
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(14),
                      children: [
                        if (hero != null)
                          XfDetHero(detail: hero, showStatus: false),
                        XflowFormCard(
                          title: titledForm,
                          child: XfDetFormSections(
                            sections: buildFieldSections(
                              _template!.fields,
                              detail!.formData,
                              bundle!.detail,
                            ),
                            service: _service,
                          ),
                        ),
                        const SizedBox(height: 12),
                        XfDetCommentsSection(
                          service: _service,
                          businessType: widget.businessType,
                          businessId: widget.businessId,
                          fallbackPeople: _fallbackStakeholders(bundle),
                        ),
                        const SizedBox(height: 12),
                        XflowFormCard(
                          title: '审批进度',
                          tag: _trail == null ? '待同步' : '流程追踪',
                          child: XfDetTrackTimeline(bundle: bundle),
                        ),
                        if (_myTodo != null) ...[
                          const SizedBox(height: 12),
                          XfDetApproveCard(
                            onApprove: _approve,
                            onReject: _reject,
                          ),
                        ],
                      ],
                    ),
                    ),
            ),
            if (!_isApprover &&
                (_canWithdraw || detail?.status.toUpperCase() == 'DRAFT'))
              XflowXfActionBar(
                label: detail?.status.toUpperCase() == 'DRAFT'
                    ? '编辑并重新提交'
                    : '撤回审批',
                loading: false,
                onPressed: detail?.status.toUpperCase() == 'DRAFT'
                    ? widget.onEdit
                    : _withdraw,
              ),
          ],
        ),
      ),
    );
  }
}
