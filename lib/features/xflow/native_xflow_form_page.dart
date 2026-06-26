import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
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
    this.backScreen = 'B3',
    this.onDeleted,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String templateKey;
  final int? editProposalId;
  final void Function(int proposalId) onSubmitted;

  /// 返回 / 删除后跳转的目标屏（新建来自 B3，编辑草稿来自 B14）。
  final String backScreen;

  /// 草稿删除成功后的回调（用于刷新来源列表）。
  final VoidCallback? onDeleted;

  @override
  State<NativeXflowFormPage> createState() => _NativeXflowFormPageState();
}

class _NativeXflowFormPageState extends State<NativeXflowFormPage> {
  late final XflowService _service;
  XflowTemplateDetail? _template;
  XflowProposalDetail? _editingDetail;
  Map<String, dynamic> _detailConfig = const {};
  final Map<String, dynamic> _values = <String, dynamic>{};
  List<Map<String, dynamic>> _ccRules = const [];
  bool _loading = true;
  bool _ccLoading = true;
  String? _error;
  String? _ccError;
  bool _submitting = false;
  int? _draftProposalId;

  bool get _isEditing => widget.editProposalId != null && widget.editProposalId! > 0;
  bool get _isDelegatedPendingInitiate =>
      _isEditing && (_editingDetail?.status.toLowerCase() == 'pending_initiate');

  bool _isDelegatedClearActionKind(String kind) {
    final k = kind.trim().toLowerCase();
    return k == 'clear-form' || k == 'clear_form' || k == 'clearform' || k == 'reset-form';
  }

  /// 仅创建人本人的草稿(DRAFT)可删除；已推送的「待发起」由代发起人处理，不在此删除。
  bool get _canDeleteDraft {
    if (!_isEditing) return false;
    final st = _editingDetail?.status.toUpperCase() ?? '';
    if (st != 'DRAFT') return false;
    final createdBy = _editingDetail?.createdById ?? 0;
    return createdBy > 0 && createdBy == widget.session.userId;
  }

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
      _ccLoading = true;
      _ccError = null;
    });
    final ccFuture = _service.fetchCcRulesList(templateKey: widget.templateKey);
    try {
      final template =
          await _service.fetchTemplateDetail(templateKey: widget.templateKey);
      _values
        ..clear()
        ..addAll(await _service.loadLocalDraft());
      XflowProposalDetail? detail;
      if (_isEditing) {
        detail = await _service.fetchProposalDetail(widget.editProposalId!);
        _mergeProposalToForm(detail);
      }
      Map<String, dynamic> detailCfg = const {};
      try {
        detailCfg = await _service.fetchDetailConfig(templateKey: widget.templateKey);
      } catch (_) {}
      // 初次渲染前先重算计算字段（如印花税），避免编辑/草稿预填时显示为空。
      XflowLinkage.recompute(template.fields, template.layout, _values);
      if (!mounted) return;
      setState(() {
        _template = template;
        _editingDetail = detail;
        _detailConfig = detailCfg;
        _loading = false;
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
    final status = _editingDetail?.status.toLowerCase() ?? '';
    if (_isEditing && status == 'pending_initiate') {
      final ok = await confirmInitiateProposal(context);
      if (!ok) return;
    }
    setState(() => _submitting = true);
    try {
      Map<String, dynamic> res;
      if (_isEditing && status == 'rejected') {
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
        );
        // 继续填写的服务端草稿在提交后会生成新的正式提案，
        // 删除原草稿以避免「我发起的」列表里残留重复的草稿项。
        if (_isEditing && status == 'draft') {
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
      showDunesToast(context, '提交失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
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
      await _service.clearLocalDraft();
      if (!mounted) return;
      showDunesToast(context, '草稿已删除');
      widget.onDeleted?.call();
      widget.navigation.popTo(widget.backScreen);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '删除失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
    }
  }

  Future<void> _handleAction(String kind) async {
    if (_isDelegatedPendingInitiate &&
        (kind == 'save-draft' || kind == 'load-draft' || kind == 'push-colleague')) {
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
    showDunesToast(context, '正在保存草稿到服务端…');
    try {
      final res = await _service.submitDraft(
        formValues: _values,
        proposalId: _draftProposalId ?? widget.editProposalId,
        templateKey: widget.templateKey,
      );
      final pid = _int(res['proposalId'] ?? res['businessId'] ?? res['id']);
      if (pid > 0) _draftProposalId = pid;
      if (!mounted) return;
      showDunesToast(context, '草稿已保存${pid > 0 ? ' · 提案 #$pid' : ''}');
    } catch (_) {
      await _service.saveLocalDraft(_values);
      if (!mounted) return;
      showDunesToast(context, '网络不可用，草稿已暂存到本机');
    }
  }

  Future<void> _loadDraft() async {
    final draft = await _service.loadLocalDraft();
    if (draft.isEmpty) {
      showDunesToast(
        context,
        '当前模板暂无本地草稿，请先点击「暂存草稿」保存后再恢复',
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
    _draftProposalId = null;
    await _service.clearLocalDraft();
    if (!mounted) return;
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
      showDunesToast(context, '推送失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
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
      showDunesToast(context, '推送失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
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
          'displayName': rule['displayName'] ?? rule['userName'] ?? rule['name'] ?? '用户#$uid',
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
      if (!field.required || field.key.isEmpty || field.type == 'section') continue;
      final value = _values[field.key];
      final ok = value != null &&
          ((value is String && value.trim().isNotEmpty) ||
              (value is List && value.isNotEmpty) ||
              (value is Map && value.isNotEmpty) ||
              (value is! String && value is! List && value is! Map));
      if (!ok) out.add(field.label.isEmpty ? field.key : field.label);
    }
    return out;
  }

  String get _submitLabel {
    final status = _editingDetail?.status.toLowerCase() ?? '';
    if (status == 'rejected') return '重新提交';
    if (status == 'pending_initiate') return '提交审批';
    return '提交审批';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: '销售提案 · PROPOSAL_3STEP',
              title: _isEditing ? '编辑销售提案' : '新建销售提案',
              onBack: () => widget.navigation.popTo(widget.backScreen),
              onMore: _canDeleteDraft ? _confirmDeleteDraft : null,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? _errorView()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                            children: [
                              XflowFormCard(
                                title: _isEditing ? '编辑销售提案' : '新建销售提案',
                                tag: 'XFlow',
                                child: XflowFormRenderer(
                                  fields: _isDelegatedPendingInitiate
                                      ? _template!.fields.where((f) {
                                          if (f.type != 'action') return true;
                                          final kind =
                                              (f.raw['actionKind'] ?? f.key).toString();
                                          return _isDelegatedClearActionKind(kind);
                                        }).toList(growable: false)
                                      : _template!.fields,
                                  values: _values,
                                  layout: _template!.layout,
                                  service: _service,
                                  embedded: true,
                                  allowedActionKinds:
                                      _isDelegatedPendingInitiate
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
                                  },
                                  onAction: _handleAction,
                                ),
                              ),
                              XflowFormCard(
                                title: '审批流程',
                                child: XflowStageList(
                                  stages: _template!.stages,
                                  layout: _template!.layout,
                                ),
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
            XflowXfActionBar(
              label: _submitLabel,
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
              secondaryLabel: _canDeleteDraft ? '删除草稿' : null,
              secondaryDanger: true,
              onSecondaryPressed: _canDeleteDraft && !_submitting ? _confirmDeleteDraft : null,
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
