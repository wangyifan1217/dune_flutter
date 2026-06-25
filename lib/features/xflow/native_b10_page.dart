import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'xflow_detail_renderer.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB10Page extends StatefulWidget {
  const NativeB10Page({
    super.key,
    required this.session,
    required this.navigation,
    required this.proposalId,
    required this.todoHint,
    required this.backScreen,
    required this.onReedit,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final int proposalId;
  final XflowTodoHint? todoHint;
  final String backScreen;
  final void Function(int proposalId) onReedit;

  @override
  State<NativeB10Page> createState() => _NativeB10PageState();
}

class _NativeB10PageState extends State<NativeB10Page> {
  late final XflowService _service;
  XflowDetailBundle? _bundle;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _ccRules = const [];
  bool _ccLoading = true;
  String? _ccError;

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _load();
  }

  Future<void> _loadCcRules() async {
    setState(() {
      _ccLoading = true;
      _ccError = null;
    });
    try {
      final rules = await _service.fetchCcRulesList();
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

  Future<void> _load() async {
    if (widget.proposalId <= 0) {
      setState(() {
        _loading = false;
        _error = '提案 ID 无效';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bundle = await _service.fetchB10Bundle(
        proposalId: widget.proposalId,
        todoHint: widget.todoHint,
        currentUserId: widget.session.userId,
      );
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
      _loadCcRules();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _approve(String comment) async {
    final todo = _bundle?.myTodo;
    if (todo == null) return;
    await _service.completeTodo(todoId: todo.id, approve: true, comment: comment);
    if (!mounted) return;
    showDunesToast(context, '已通过审批');
    await _load();
  }

  Future<void> _reject(String comment) async {
    final todo = _bundle?.myTodo;
    if (todo == null) return;
    await _service.completeTodo(todoId: todo.id, approve: false, comment: comment);
    if (!mounted) return;
    showDunesToast(context, '已驳回');
    await _load();
  }

  Future<void> _voidProposal() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作废提案'),
        content: const Text('确认作废此提案？作废后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认作废')),
        ],
      ),
    );
    if (ok != true) return;
    await _service.voidProposal(id);
    if (!mounted) return;
    showDunesToast(context, '提案已作废');
    await _load();
  }

  Future<void> _deleteDraft() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除草稿'),
        content: const Text('确认删除此草稿？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteProposal(id);
      if (!mounted) return;
      showDunesToast(context, '草稿已删除');
      widget.navigation.back();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '删除失败：$e', kind: DunesToastKind.error);
    }
  }

  Future<void> _initiate() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    try {
      await _service.initiateProposal(id);
      if (!mounted) return;
      showDunesToast(context, '已确认发起');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '发起失败：$e', kind: DunesToastKind.error);
    }
  }

  Future<void> _push() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final cfg = _bundle?.detailConfig ?? const {};
    final rules = cfg['pushRules'];
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
                    '推送给业务负责人确认发起；不会直接进入审批链。',
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
                              selected: selectedId == _int(u['userId']),
                              title: Text(
                                '${u['displayName']}${(u['departmentName'] ?? '').toString().isNotEmpty ? ' · ${u['departmentName']}' : ''}',
                                style: DunesTypography.sans(fontSize: 12),
                              ),
                              onTap: () => setSheetState(() => selectedId = _int(u['userId'])),
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
                                proposalId: id,
                                initiatorUserId: selectedId,
                              );
                              if (!mounted) return;
                              showDunesToast(context, '已推送给业务负责人');
                              await _load();
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

  int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _bundle?.detail;
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            XflowDsBar(
              crumb: '提案详情 · 返回列表',
              title: detail?.code ?? 'PROP-${widget.proposalId}',
              onBack: widget.navigation.back,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            children: [
                              XflowDetailRenderer(
                                bundle: _bundle!,
                                service: _service,
                                onApprove: _approve,
                                onReject: _reject,
                                onDelete: _deleteDraft,
                                onPush: _push,
                                onInitiate: _initiate,
                                onReedit: () => widget.onReedit(_bundle!.detail.id),
                                onVoid: _voidProposal,
                              ),
                              XflowCcRulesCard(
                                rules: _ccRules,
                                loading: _ccLoading,
                                error: _ccError,
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
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
}
