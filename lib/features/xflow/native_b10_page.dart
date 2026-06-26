import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
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
        _ccError = friendlyErrorText(e);
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
        _error = friendlyErrorText(e);
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
      widget.navigation.popTo(widget.backScreen);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '删除失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
    }
  }

  Future<void> _initiate() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final ok = await confirmInitiateProposal(context);
    if (!ok || !mounted) return;
    try {
      await _service.initiateProposal(id);
      if (!mounted) return;
      showDunesToast(context, '已确认发起');
      if (_bundle?.isDesignatedInitiator == true) {
        widget.navigation.popTo('B2');
        return;
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '发起失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
    }
  }

  Future<void> _return() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退回给推送人'),
        content: const Text('确认退回此提案？退回后将回到推送人的草稿，由其继续提交或删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认退回')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.returnProposal(id);
      if (!mounted) return;
      showDunesToast(context, '已退回给推送人');
      widget.navigation.popTo(widget.backScreen);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '退回失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
    }
  }

  Future<void> _push() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final cfg = _bundle?.detailConfig ?? const {};
    final suggested = _whitelistSuggestions(cfg['pushRules']);
    if (!mounted) return;
    final target = await showXflowPushSheet(
      context: context,
      service: _service,
      subtitle: '在运营推送白名单同事中选择；不会直接进入审批链',
      suggested: suggested,
    );
    if (target == null || !mounted) return;
    try {
      await _service.pushProposal(
        proposalId: id,
        initiatorUserId: target.userId,
        message: target.message,
      );
      if (!mounted) return;
      showDunesToast(context, '已推送给同事，对方可代为填写并确认发起');
      await _load();
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
              onBack: () => widget.navigation.popTo(widget.backScreen),
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
                                onReturn: _return,
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
