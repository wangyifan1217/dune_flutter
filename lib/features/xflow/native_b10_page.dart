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
import 'xflow_detail_renderer.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

/// 从审批详情打开关联提案：Navigator 叠一层，返回不影响原审批页。
Future<void> openLinkedProposalDetail({
  required BuildContext context,
  required AuthSession session,
  required int proposalId,
}) async {
  if (proposalId <= 0 || !context.mounted) return;

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) {
        void close() {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
        }

        return Material(
          color: DunesColors.bgApp,
          child: NativeB10Page(
            session: session,
            navigation: _LinkedProposalBackNav(onClose: close),
            proposalId: proposalId,
            todoHint: null,
            backScreen: 'linked-proposal',
            onReedit: (_) {
              showDunesToast(ctx, '请从提案列表重新编辑');
            },
          ),
        );
      },
    ),
  );
}

class _LinkedProposalBackNav extends DunesNavigationController {
  _LinkedProposalBackNav({required this.onClose})
      : super(initialScreen: 'linked-proposal');

  final VoidCallback onClose;

  @override
  void popTo(String screenId) => onClose();

  @override
  void back() => onClose();

  @override
  void go(String screenId) => onClose();
}

class NativeB10Page extends StatefulWidget {
  const NativeB10Page({
    super.key,
    required this.session,
    required this.navigation,
    required this.proposalId,
    required this.todoHint,
    required this.backScreen,
    required this.onReedit,
    this.onApprovalCompleted,
    this.onOpenPendingItem,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final int proposalId;
  final XflowTodoHint? todoHint;
  final String backScreen;
  final void Function(int proposalId) onReedit;
  final VoidCallback? onApprovalCompleted;
  /// 打开下一条待审批（宿主导航 / 覆盖层切换）。
  final ValueChanged<XflowProposalItem>? onOpenPendingItem;

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
  bool _forwarding = false;
  int _pendingTotal = 0;
  bool _pendingBusy = false;

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
        currentUserId: widget.session.userId,
      );
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
      _loadCcRules();
      if (bundle.myTodo != null) {
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
              businessType: 'PROPOSAL',
              businessId: widget.proposalId,
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

  Future<void> _approve(String comment) async {
    final todo = _bundle?.myTodo;
    if (todo == null) return;
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
    final todo = _bundle?.myTodo;
    if (todo == null) return;
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

  Future<void> _forwardApproval() async {
    final detail = _bundle?.detail;
    if (detail == null || _forwarding) return;
    setState(() => _forwarding = true);
    try {
      final share = ApprovalChatShare(
        businessType: 'PROPOSAL',
        businessId: detail.id,
        title: detail.title.trim().isEmpty ? '销售提案' : detail.title.trim(),
        status: detail.status,
        code: detail.code,
        templateKey: XflowService.salesTemplateKey,
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

  Future<void> _voidProposal() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作废提案'),
        content: const Text('确认作废此提案？作废后不可恢复。'),
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
      await _service.voidProposal(id);
      if (!mounted) return;
      showDunesToast(context, '提案已作废');
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

  Future<void> _withdrawProposal() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回审批'),
        content: const Text('确认撤回此审批？撤回后将保存为草稿，可修改后重新提交。'),
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
      await _service.withdrawProposal(id);
      if (!mounted) return;
      showDunesToast(context, '审批已撤回，已保存到草稿');
      widget.navigation.popTo(widget.backScreen);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '撤回失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _deleteDraft() async {
    final id = _bundle?.detail.id ?? 0;
    if (id <= 0) return;
    final isDraft =
        (_bundle?.detail.status ?? '').toLowerCase() == 'draft';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDraft ? '删除草稿' : '删除单据'),
        content: Text(
          isDraft ? '确认删除此草稿？删除后不可恢复。' : '确认删除此已作废单据？删除后不可恢复。',
        ),
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
      await _service.deleteProposal(id);
      if (!mounted) return;
      showDunesToast(context, isDraft ? '草稿已删除' : '单据已删除');
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
      showDunesToast(
        context,
        '发起失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认退回'),
          ),
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
      showDunesToast(
        context,
        '退回失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
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
        bottom: false,
        child: Column(
          children: [
            XflowDsBar(
              crumb: '提案详情 · 返回列表',
              title: detail?.code ?? 'PROP-${widget.proposalId}',
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
                  ? _buildError()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: SelectionArea(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          child: ListView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
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
                              onReedit: () =>
                                  widget.onReedit(_bundle!.detail.id),
                              onVoid: _voidProposal,
                              onWithdraw: _withdrawProposal,
                              onReturn: _return,
                              onOpenLinkedProposal: (proposalId) {
                                openLinkedProposalDetail(
                                  context: context,
                                  session: widget.session,
                                  proposalId: proposalId,
                                );
                              },
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
                    ),
            ),
            if (_bundle?.myTodo != null)
              XfDetNextPendingFooter(
                totalCount: _pendingTotal,
                loading: _pendingBusy,
                onPressed: _pendingBusy
                    ? null
                    : () => unawaited(_goNextPending(afterDecision: false)),
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
