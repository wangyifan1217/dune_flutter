import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'xflow_form_renderer.dart';
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
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String templateKey;
  final int? editProposalId;
  final void Function(int proposalId) onSubmitted;

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
        _error = e.toString();
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
        _ccError = e.toString();
        _ccLoading = false;
      });
    }
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
    setState(() => _submitting = true);
    try {
      Map<String, dynamic> res;
      final status = _editingDetail?.status.toLowerCase() ?? '';
      if (_isEditing && status == 'rejected') {
        res = await _service.resubmitProposal(
          proposalId: widget.editProposalId!,
          formValues: _values,
        );
      } else if (_isEditing && status == 'pending_initiate') {
        await _service.initiateProposal(widget.editProposalId!);
        if (!mounted) return;
        showDunesToast(context, '已确认发起');
        widget.onSubmitted(widget.editProposalId!);
        return;
      } else {
        res = await _service.submitProposal(
          formValues: _values,
          templateKey: widget.templateKey,
        );
      }
      final pid = _int(res['businessId'] ?? res['proposalId'] ?? res['id']);
      if (!mounted) return;
      showDunesToast(context, '已提交审批');
      if (pid > 0) widget.onSubmitted(pid);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '提交失败：$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _handleAction(String kind) async {
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
    setState(() => _values..clear()..addAll(draft));
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
      showDunesToast(context, '推送失败：$e', kind: DunesToastKind.error);
    }
  }

  Future<void> _showPushDialog(int proposalId) async {
    final rules = _detailConfig['pushRules'];
    final users = <Map<String, dynamic>>[];
    if (rules is List) {
      for (final rule in rules) {
        if (rule is! Map) continue;
        if (rule['enabled'] == false) continue;
        final uid = _int(rule['userId'] ?? rule['id']);
        if (uid <= 0) continue;
        users.add(<String, dynamic>{
          'userId': uid,
          'id': uid,
          'displayName': rule['displayName'] ?? rule['userName'] ?? rule['name'] ?? '用户#$uid',
          'departmentName': rule['department'] ?? rule['departmentName'] ?? '',
          'title': rule['title'] ?? '',
        });
      }
    }
    if (!mounted) return;
    var selectedId = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DunesColors.bgApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('推送给同事', style: DunesTypography.sans(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    '将先保存草稿，再从运营白名单选择同事推送',
                    style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
                  ),
                  const SizedBox(height: 12),
                  if (users.isEmpty)
                    Text('暂无可用同事', style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3))
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final u in users)
                            ListTile(
                              dense: true,
                              selected: selectedId == _int(u['userId'] ?? u['id']),
                              title: Text(
                                '${u['displayName'] ?? u['name'] ?? ''}${u['departmentName'] != null ? ' · ${u['departmentName']}' : ''}',
                                style: DunesTypography.sans(fontSize: 12),
                              ),
                              onTap: () {
                                setSheetState(() => selectedId = _int(u['userId'] ?? u['id']));
                              },
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: selectedId <= 0
                        ? null
                        : () async {
                            Navigator.pop(context);
                            try {
                              await _service.pushProposal(
                                proposalId: proposalId,
                                initiatorUserId: selectedId,
                              );
                              if (!mounted) return;
                              showDunesToast(context, '已推送给同事，对方可代为填写并确认发起');
                            } catch (e) {
                              if (!mounted) return;
                              showDunesToast(context, '推送失败：$e', kind: DunesToastKind.error);
                            }
                          },
                    child: const Text('确认推送'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
    if (status == 'pending_initiate') return '确认发起';
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
              onBack: () => widget.navigation.go('B3'),
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
                                  fields: _template!.fields,
                                  values: _values,
                                  layout: _template!.layout,
                                  service: _service,
                                  embedded: true,
                                  onChanged: (key, value) {
                                    setState(() => _values[key] = value);
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
