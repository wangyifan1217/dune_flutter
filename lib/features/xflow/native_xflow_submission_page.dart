import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'approval_chat_forward.dart';
import 'approval_chat_share.dart';
import 'approval_pending_nav.dart';
import 'native_b10_page.dart';
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
    this.onOpenPendingItem,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String businessType;
  final int businessId;
  final String backScreen;
  final VoidCallback onEdit;
  final XflowTodoHint? todoHint;
  final VoidCallback? onApprovalCompleted;
  /// 打开下一条待审批（宿主导航 / 覆盖层切换）。
  final ValueChanged<XflowProposalItem>? onOpenPendingItem;

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
  int _pendingTotal = 0;
  bool _pendingBusy = false;

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
      if (myTodo != null) {
        unawaited(_refreshPendingQueue());
      } else if (mounted) {
        setState(() => _pendingTotal = 0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  Future<MyOpenApprovalQueue?> _refreshPendingQueue() async {
    try {
      final queue = await loadMyOpenApprovalQueue(_service);
      if (!mounted) return null;
      setState(() => _pendingTotal = queue.total);
      return queue;
    } catch (_) {
      return null;
    }
  }

  Future<void> _goNextPending({required bool afterDecision}) async {
    if (_pendingBusy) return;
    setState(() => _pendingBusy = true);
    try {
      final queue = await loadMyOpenApprovalQueue(_service);
      if (!mounted) return;
      setState(() => _pendingTotal = queue.total);

      final XflowProposalItem? next = afterDecision
          ? queue.firstOrNull
          : queue.nextAfter(
              businessType: widget.businessType,
              businessId: widget.businessId,
            );

      if (next == null) {
        showDunesToast(context, '没有未审批的内容了');
        if (afterDecision) await _load();
        return;
      }

      final open = widget.onOpenPendingItem;
      if (open == null) {
        if (afterDecision) await _load();
        return;
      }
      open(next);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '加载待审批失败'),
        kind: DunesToastKind.error,
      );
      if (afterDecision) await _load();
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
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

  /// 已作废：创建人可删除（与草稿一致）。
  bool get _canDeleteVoided {
    if (_isApprover) return false;
    final detail = _detail;
    if (detail == null || detail.createdById != widget.session.userId) {
      return false;
    }
    return _resolvedStatus.toUpperCase() == 'VOIDED';
  }

  Future<void> _deleteVoided() async {
    final detail = _detail;
    if (detail == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除单据'),
        content: const Text('确认删除此已作废单据？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteDraft(
        businessType: detail.businessType,
        businessId: detail.businessId,
      );
      if (!mounted) return;
      showDunesToast(context, '单据已删除');
      widget.navigation.popTo(widget.backScreen);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '删除失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  /// 与提案详情对齐：仅提交人本人可对「已驳回」单据重新填写 / 作废。
  bool get _canReedit {
    if (_isApprover) return false;
    final detail = _detail;
    if (detail == null) return false;
    final st = _resolvedStatus.toLowerCase();
    if (st != 'rejected') return false;
    final uid = widget.session.userId;
    if (uid <= 0) return false;
    final initiator = _trail?.initiatorId ?? 0;
    return detail.createdById == uid || (initiator > 0 && initiator == uid);
  }

  Future<void> _voidSubmission() async {
    final detail = _detail;
    if (detail == null || !_canReedit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作废审批单'),
        content: const Text('确认作废此审批单？作废后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认作废'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.voidSubmission(
        businessType: detail.businessType,
        businessId: detail.businessId,
      );
      if (!mounted) return;
      showDunesToast(context, '审批单已作废');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '作废失败，请稍后重试'),
        kind: DunesToastKind.error,
      );
    }
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
    await _goNextPending(afterDecision: true);
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
    await _goNextPending(afterDecision: true);
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
      canReedit: _canReedit,
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
                        if (bundle != null) ...[
                          XfDetClosedBanner(detail: bundle.detail),
                          XfDetRejectBanner(
                            detail: bundle.detail,
                            info: lastRejectStep(
                              bundle.trail,
                              bundle.assigneeNames,
                            ),
                          ),
                        ],
                        XflowFormCard(
                          title: titledForm,
                          child: XfDetFormSections(
                            sections: buildFieldSections(
                              _template!.fields,
                              detail!.formData,
                              bundle!.detail,
                            ),
                            service: _service,
                            onOpenLinkedProposal: (proposalId) {
                              openLinkedProposalDetail(
                                context: context,
                                session: widget.session,
                                proposalId: proposalId,
                              );
                            },
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
                        XfDetActions(
                          detail: bundle.detail,
                          canReedit: bundle.canReedit,
                          onReedit: widget.onEdit,
                          onVoid: _voidSubmission,
                        ),
                      ],
                    ),
                    ),
            ),
            if (_myTodo != null)
              XfDetNextPendingFooter(
                totalCount: _pendingTotal,
                loading: _pendingBusy,
                onPressed: _pendingBusy
                    ? null
                    : () => unawaited(_goNextPending(afterDecision: false)),
              )
            else if (_canWithdraw || detail?.status.toUpperCase() == 'DRAFT')
              XflowXfActionBar(
                label: detail?.status.toUpperCase() == 'DRAFT'
                    ? '编辑并重新提交'
                    : '撤回审批',
                loading: false,
                onPressed: detail?.status.toUpperCase() == 'DRAFT'
                    ? widget.onEdit
                    : _withdraw,
              )
            else if (_canDeleteVoided)
              XflowXfActionBar(
                label: '删除',
                icon: Icons.delete_outline,
                loading: false,
                onPressed: _deleteVoided,
              ),
          ],
        ),
      ),
    );
  }
}
