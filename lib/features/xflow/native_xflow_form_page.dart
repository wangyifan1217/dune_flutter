import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'xflow_approval_flow_ui.dart';
import 'xflow_form_styles.dart';
import 'xflow_form_renderer.dart';
import 'xflow_linkage.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeXflowFormPage extends StatefulWidget {
  const NativeXflowFormPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.templateKey,
    required this.editProposalId,
    required this.onSubmitted,
    this.editBusinessType = 'PROPOSAL',
    this.backScreen = 'B3',
    this.onDeleted,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String templateKey;
  final int? editProposalId;
  final void Function(int proposalId) onSubmitted;
  final String editBusinessType;

  /// 返回 / 删除后跳转的目标屏（新建来自 B3，编辑草稿来自 B14）。
  final String backScreen;

  /// 草稿删除成功后的回调（用于刷新来源列表）。
  final VoidCallback? onDeleted;

  @override
  State<NativeXflowFormPage> createState() => _NativeXflowFormPageState();
}

class _NativeXflowFormPageState extends State<NativeXflowFormPage>
    with WidgetsBindingObserver {
  late final XflowService _service;
  XflowTemplateDetail? _template;
  XflowProposalDetail? _editingDetail;
  XflowSubmissionDetail? _editingSubmission;
  Map<String, dynamic> _detailConfig = const {};
  final Map<String, dynamic> _values = <String, dynamic>{};
  List<Map<String, dynamic>> _ccRules = const [];
  bool _loading = true;
  bool _ccLoading = true;
  String? _error;
  String? _ccError;
  bool _submitting = false;
  int? _draftProposalId;
  Timer? _autosaveTimer;
  int _autosaveSeq = 0;
  String _autosaveHint = '填写中将自动保存草稿';
  bool _autosaving = false;

  void _dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && !focus.hasPrimaryFocus) {
      focus.unfocus();
      return;
    }
    focus?.unfocus();
  }

  bool get _isEditing =>
      widget.editProposalId != null && widget.editProposalId! > 0;
  bool get _isDynamicSubmission =>
      _isEditing && widget.editBusinessType.toUpperCase() != 'PROPOSAL';
  String get _editingStatus => _isDynamicSubmission
      ? (_editingSubmission?.status.toLowerCase() ?? '')
      : (_editingDetail?.status.toLowerCase() ?? '');
  bool get _isDelegatedPendingInitiate =>
      _isEditing &&
      (_editingDetail?.status.toLowerCase() == 'pending_initiate');

  int? get _activeDraftId =>
      _draftProposalId ??
      (widget.editProposalId != null && widget.editProposalId! > 0
          ? widget.editProposalId
          : null);

  bool get _canAutosave {
    if (_loading || _submitting || _isDelegatedPendingInitiate) return false;
    final st = _editingStatus;
    if (st.isEmpty) return true;
    return st == 'draft' ||
        st == 'rejected' ||
        st == 'withdrawn' ||
        st == 'pending_initiate';
  }

  bool _isDelegatedClearActionKind(String kind) {
    final k = kind.trim().toLowerCase();
    return k == 'clear-form' ||
        k == 'clear_form' ||
        k == 'clearform' ||
        k == 'reset-form';
  }

  /// 仅创建人本人的草稿(DRAFT)可删除；已推送的「待发起」由代发起人处理，不在此删除。
  bool get _canDeleteDraft {
    if (_isDynamicSubmission) return false;
    if (!_isEditing) return false;
    final st = _editingDetail?.status.toUpperCase() ?? '';
    if (st != 'DRAFT') return false;
    final createdBy = _editingDetail?.createdById ?? 0;
    return createdBy > 0 && createdBy == widget.session.userId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = XflowService(
      session: widget.session,
      templateKey: widget.templateKey,
    );
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    // iOS/Android 离开页时尽量落本地，避免未防抖完丢失。
    if (_canAutosave && XflowService.hasMeaningfulDraftValues(_values)) {
      unawaited(
        _service.saveLocalDraft(
          Map<String, dynamic>.from(_values),
          businessType: widget.editBusinessType,
          businessId: _activeDraftId,
        ),
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _autosaveTimer?.cancel();
      unawaited(_runAutosave(silent: true, forceLocalFirst: true));
    }
  }

  void _scheduleAutosave() {
    if (!_canAutosave) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_runAutosave(silent: true));
    });
  }

  Future<void> _runAutosave({
    bool silent = true,
    bool forceLocalFirst = false,
  }) async {
    if (!_canAutosave) return;
    if (!XflowService.hasMeaningfulDraftValues(_values)) return;
    if (_autosaving && !forceLocalFirst) return;
    final seq = ++_autosaveSeq;
    _autosaving = true;
    if (mounted && silent) {
      setState(() => _autosaveHint = '正在自动保存…');
    }
    try {
      if (forceLocalFirst) {
        await _service.saveLocalDraft(
          Map<String, dynamic>.from(_values),
          businessType: widget.editBusinessType,
          businessId: _activeDraftId,
        );
      }
      if (_isDynamicSubmission) {
        await _service.updateSubmissionDraft(
          businessType: widget.editBusinessType,
          businessId: widget.editProposalId!,
          formValues: Map<String, dynamic>.from(_values),
        );
      } else {
        final res = await _service.submitDraft(
          formValues: Map<String, dynamic>.from(_values),
          proposalId: _activeDraftId,
          templateKey: widget.templateKey,
        );
        final pid = _int(res['proposalId'] ?? res['businessId'] ?? res['id']);
        if (pid > 0) _draftProposalId = pid;
      }
      if (!mounted || seq != _autosaveSeq) return;
      setState(() => _autosaveHint = '已自动保存');
      if (!silent) showDunesToast(context, '草稿已保存');
    } catch (_) {
      await _service.saveLocalDraft(
        Map<String, dynamic>.from(_values),
        businessType: widget.editBusinessType,
        businessId: _activeDraftId,
      );
      if (!mounted || seq != _autosaveSeq) return;
      setState(() => _autosaveHint = '网络异常，已暂存到本机');
      if (!silent) {
        showDunesToast(context, '网络不可用，草稿已暂存到本机');
      }
    } finally {
      _autosaving = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _ccLoading = true;
      _ccError = null;
    });
    final ccFuture = _service.fetchCcRulesList(templateKey: widget.templateKey);
    try {
      final template = await _service.fetchTemplateDetail(
        templateKey: widget.templateKey,
      );
      final local = await _service.loadLocalDraft(
        businessType: widget.editBusinessType,
        businessId: widget.editProposalId,
      );
      _values
        ..clear()
        ..addAll(local);
      XflowProposalDetail? detail;
      if (_isDynamicSubmission) {
        final submission = await _service.fetchSubmissionDetail(
          businessType: widget.editBusinessType,
          businessId: widget.editProposalId!,
        );
        _editingSubmission = submission;
        _values.addAll(submission.formData);
      } else if (_isEditing) {
        detail = await _service.fetchProposalDetail(widget.editProposalId!);
        _mergeProposalToForm(detail);
        _draftProposalId = widget.editProposalId;
      }
      Map<String, dynamic> detailCfg = const {};
      try {
        detailCfg = await _service.fetchDetailConfig(
          templateKey: widget.templateKey,
        );
      } catch (_) {}
      // 初次渲染前先重算计算字段（如印花税），避免编辑/草稿预填时显示为空。
      XflowLinkage.recompute(template.fields, template.layout, _values);
      if (!mounted) return;
      setState(() {
        _template = template;
        _editingDetail = detail;
        _detailConfig = detailCfg;
        _loading = false;
        _autosaveHint = _canAutosave ? '填写中将自动保存草稿' : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
    try {
      final rules = await ccFuture;
      if (!mounted) return;
      setState(() {
        _ccRules = rules;
        _ccLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ccError = friendlyErrorText(e);
        _ccLoading = false;
      });
    }
  }

  /// 重算计算只读字段（印花税等）与 layout 联动，需在 _values 变化后调用。
  void _recompute() {
    final template = _template;
    if (template == null) return;
    XflowLinkage.recompute(template.fields, template.layout, _values);
  }

  void _mergeProposalToForm(XflowProposalDetail detail) {
    _values
      ..addAll(detail.formValues)
      ..putIfAbsent('title', () => detail.title)
      ..putIfAbsent('proposalCode', () => detail.code)
      ..putIfAbsent('owner1', () => detail.ownerName);
  }

  Future<void> _submit() async {
    final miss = _missingRequired();
    if (miss.isNotEmpty) {
      showDunesToast(
        context,
        '请填写：${miss.take(3).join('、')}${miss.length > 3 ? '…' : ''}',
        kind: DunesToastKind.error,
      );
      return;
    }
    final status = _editingStatus;
    if (_isEditing && status == 'pending_initiate') {
      final ok = await confirmInitiateProposal(context);
      if (!ok || !mounted) return;
    } else {
      final ok = await confirmSubmitForApproval(context);
      if (!ok || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      Map<String, dynamic> res;
      if (_isDynamicSubmission && status == 'draft') {
        res = await _service.resubmitSubmission(
          businessType: widget.editBusinessType,
          businessId: widget.editProposalId!,
          formValues: _values,
        );
      } else if (_isEditing && status == 'rejected') {
        res = await _service.resubmitProposal(
          proposalId: widget.editProposalId!,
          formValues: _values,
        );
      } else if (_isEditing && status == 'pending_initiate') {
        await _service.submitDraft(
          formValues: _values,
          proposalId: widget.editProposalId,
          templateKey: widget.templateKey,
        );
        await _service.initiateProposal(widget.editProposalId!);
        if (!mounted) return;
        showDunesToast(context, '已提交审批');
        widget.onSubmitted(widget.editProposalId!);
        return;
      } else {
        res = await _service.submitProposal(
          formValues: _values,
          templateKey: widget.templateKey,
          clearDraftBusinessId: _activeDraftId,
        );
        // 继续填写的服务端草稿在提交后会生成新的正式提案，
        // 删除原草稿以避免「我发起的」列表里残留重复的草稿项。
        if (_isEditing && status == 'draft' && !_isDynamicSubmission) {
          try {
            await _service.deleteProposal(widget.editProposalId!);
          } catch (_) {}
        }
      }
      final pid = _int(res['businessId'] ?? res['proposalId'] ?? res['id']);
      if (!mounted) return;
      showDunesToast(context, '已提交审批');
      if (pid > 0) widget.onSubmitted(pid);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '提交失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDeleteDraft() async {
    final id = widget.editProposalId;
    if (id == null || id <= 0) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除草稿'),
        content: const Text('确认删除该草稿？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: DunesColors.coral)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteProposal(id);
      await _service.clearLocalDraft(
        businessType: widget.editBusinessType,
        businessId: id,
      );
      await _service.clearLocalDraft(
        businessType: widget.editBusinessType,
        businessId: null,
      );
      if (!mounted) return;
      showDunesToast(context, '草稿已删除');
      widget.onDeleted?.call();
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

  Future<void> _handleAction(String kind) async {
    if (_isDelegatedPendingInitiate &&
        (kind == 'save-draft' ||
            kind == 'load-draft' ||
            kind == 'push-colleague')) {
      showDunesToast(context, '代发起提案请直接继续填写并提交审批');
      return;
    }
    switch (kind) {
      case 'save-draft':
        await _saveDraft();
      case 'load-draft':
        await _loadDraft();
      case 'push-colleague':
        await _pushToColleague();
      case 'clear-form':
        await _clearForm();
      default:
        showDunesToast(context, '操作：$kind');
    }
  }

  Future<void> _saveDraft() async {
    if (!_canAutosave && _isDelegatedPendingInitiate) {
      showDunesToast(context, '代发起提案请直接继续填写并提交审批');
      return;
    }
    showDunesToast(context, '正在保存草稿到服务端…');
    await _runAutosave(silent: false);
  }

  Future<void> _loadDraft() async {
    final draft = await _service.loadLocalDraft(
      businessType: widget.editBusinessType,
      businessId: _activeDraftId,
    );
    if (!XflowService.hasMeaningfulDraftValues(draft)) {
      showDunesToast(
        context,
        '当前模板暂无本地草稿，填写后会自动保存',
        kind: DunesToastKind.error,
      );
      return;
    }
    setState(() {
      _values
        ..clear()
        ..addAll(draft);
      _recompute();
    });
    if (!mounted) return;
    showDunesToast(context, '已恢复本地草稿，请核对后继续填写');
  }

  Future<void> _clearForm() async {
    setState(_values.clear);
    final oldId = _activeDraftId;
    _draftProposalId = null;
    await _service.clearLocalDraft(
      businessType: widget.editBusinessType,
      businessId: oldId,
    );
    await _service.clearLocalDraft(
      businessType: widget.editBusinessType,
      businessId: null,
    );
    if (!mounted) return;
    setState(() => _autosaveHint = '填写中将自动保存草稿');
    showDunesToast(context, '表单已清空');
  }

  Future<void> _pushToColleague() async {
    try {
      final res = await _service.submitDraft(
        formValues: _values,
        proposalId: _draftProposalId ?? widget.editProposalId,
        templateKey: widget.templateKey,
      );
      final pid = _int(res['proposalId'] ?? res['businessId'] ?? res['id']);
      if (pid <= 0) {
        showDunesToast(context, '草稿保存失败，无法推送', kind: DunesToastKind.error);
        return;
      }
      _draftProposalId = pid;
      if (!mounted) return;
      await _showPushDialog(pid);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '推送失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _showPushDialog(int proposalId) async {
    final suggested = _whitelistSuggestions(_detailConfig['pushRules']);
    if (!mounted) return;
    final target = await showXflowPushSheet(
      context: context,
      service: _service,
      subtitle: '在运营推送白名单同事中选择；对方可代为填写并确认发起',
      suggested: suggested,
    );
    if (target == null || !mounted) return;
    try {
      await _service.pushProposal(
        proposalId: proposalId,
        initiatorUserId: target.userId,
        message: target.message,
      );
      if (!mounted) return;
      showDunesToast(context, '已推送给同事，对方可代为填写并确认发起');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '推送失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  List<Map<String, dynamic>> _whitelistSuggestions(dynamic rules) {
    final users = <Map<String, dynamic>>[];
    if (rules is List) {
      for (final rule in rules) {
        if (rule is! Map) continue;
        if (rule['enabled'] == false) continue;
        final uid = _int(rule['userId'] ?? rule['id']);
        if (uid <= 0) continue;
        users.add(<String, dynamic>{
          'userId': uid,
          'displayName':
              rule['displayName'] ??
              rule['userName'] ??
              rule['name'] ??
              '用户#$uid',
          'departmentName': rule['department'] ?? rule['departmentName'] ?? '',
        });
      }
    }
    return users;
  }

  List<String> _missingRequired() {
    final template = _template;
    if (template == null) return const [];
    final out = <String>[];
    for (final field in template.fields) {
      if (!field.required || field.key.isEmpty || field.type == 'section')
        continue;
      final value = _values[field.key];
      final ok =
          value != null &&
          ((value is String && value.trim().isNotEmpty) ||
              (value is List && value.isNotEmpty) ||
              (value is Map && value.isNotEmpty) ||
              (value is! String && value is! List && value is! Map));
      if (!ok) out.add(field.label.isEmpty ? field.key : field.label);
    }
    return out;
  }

  String get _submitLabel => '提交审批';

  String get _templateName {
    final name = _template?.title.trim() ?? '';
    return name.isEmpty ? '提案' : name;
  }

  String get _pageTitle => _isEditing ? '编辑$_templateName' : '新建$_templateName';

  String get _pageCrumb {
    final templateObj = _template?.raw['template'];
    final submitRoute = templateObj is Map
        ? (templateObj['submitRoute'] ?? '').toString().trim()
        : '';
    if (submitRoute.isNotEmpty) return '$_templateName · $submitRoute';
    return _templateName;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: XfProposalUi.bg,
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: _pageCrumb,
              title: _pageTitle,
              onBack: () => widget.navigation.popTo(widget.backScreen),
              onMore: _canDeleteDraft ? _confirmDeleteDraft : null,
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? _errorView()
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _dismissKeyboard,
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          children: [
                            XflowFormCard(
                              title: _pageTitle,
                              tag: 'XFlow',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_autosaveHint.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Text(
                                        _autosaveHint,
                                        style: DunesTypography.sans(
                                          fontSize: 12,
                                          color: DunesColors.text3,
                                        ),
                                      ),
                                    ),
                                  XflowFormRenderer(
                                fields: _isDelegatedPendingInitiate
                                    ? _template!.fields
                                          .where((f) {
                                            if (f.type != 'action') return true;
                                            final kind =
                                                (f.raw['actionKind'] ?? f.key)
                                                    .toString();
                                            return _isDelegatedClearActionKind(
                                              kind,
                                            );
                                          })
                                          .toList(growable: false)
                                    : _template!.fields,
                                values: _values,
                                layout: _template!.layout,
                                service: _service,
                                embedded: true,
                                allowedActionKinds: _isDelegatedPendingInitiate
                                    ? <String>{
                                        'clear-form',
                                        'clear_form',
                                        'clearform',
                                        'reset-form',
                                      }
                                    : null,
                                onChanged: (key, value) {
                                  setState(() {
                                    _values[key] = value;
                                    _recompute();
                                  });
                                  _scheduleAutosave();
                                },
                                onAction: _handleAction,
                              ),
                                ],
                              ),
                            ),
                            XflowApprovalFlowSection(
                              stages: _template!.stages,
                              layout: _template!.layout,
                            ),
                            XflowCcRulesCard(
                              rules: _ccRules,
                              loading: _ccLoading,
                              error: _ccError,
                              hideWhenEmpty: true,
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
            ),
            XflowXfActionBar(
              label: _submitLabel,
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
              secondaryLabel: _canDeleteDraft ? '删除草稿' : null,
              secondaryDanger: true,
              onSecondaryPressed: _canDeleteDraft && !_submitting
                  ? _confirmDeleteDraft
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
