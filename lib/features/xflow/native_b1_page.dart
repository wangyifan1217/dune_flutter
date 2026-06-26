import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB1Page extends StatelessWidget {
  const NativeB1Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      type: _ListType.b1,
      workbenchRefresh: workbenchRefresh,
    );
  }
}

class NativeB14Page extends StatelessWidget {
  const NativeB14Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.initialStatusFilter,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final String? initialStatusFilter;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      type: _ListType.b14,
      initialStatusFilter: initialStatusFilter,
      workbenchRefresh: workbenchRefresh,
    );
  }
}

class NativeP1Page extends StatelessWidget {
  const NativeP1Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      type: _ListType.p1,
      workbenchRefresh: workbenchRefresh,
    );
  }
}

class NativeB13Page extends StatelessWidget {
  const NativeB13Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      type: _ListType.b13,
      workbenchRefresh: workbenchRefresh,
    );
  }
}

enum _ListType { b1, b14, p1, b13 }

class _NativeProposalListPage extends StatefulWidget {
  const _NativeProposalListPage({
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    required this.type,
    this.initialStatusFilter,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final _ListType type;
  final String? initialStatusFilter;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  State<_NativeProposalListPage> createState() => _NativeProposalListPageState();
}

class _NativeProposalListPageState extends State<_NativeProposalListPage> {
  late final XflowService _service;
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  late String _statusFilter = widget.initialStatusFilter ?? 'ALL';
  List<XflowProposalItem> _all = const <XflowProposalItem>[];

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _search.addListener(() => setState(() {}));
    widget.workbenchRefresh?.addListener(_onWorkbenchDataRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.workbenchRefresh?.removeListener(_onWorkbenchDataRefresh);
    _search.dispose();
    super.dispose();
  }

  void _onWorkbenchDataRefresh() {
    if (!mounted) return;
    unawaited(_load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = switch (widget.type) {
        _ListType.b1 || _ListType.b13 => await _service.fetchB1Approvals(),
        _ListType.b14 => await _service.fetchB14Initiated(),
        _ListType.p1 => await _service.fetchP1CcProposals(),
      };
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  String get _title => switch (widget.type) {
        _ListType.b1 => '我审批的',
        _ListType.b14 => '我发起的',
        _ListType.p1 => '抄送我的提案',
        _ListType.b13 => '审批待办',
      };

  String get _searchHint => switch (widget.type) {
        _ListType.b1 || _ListType.b13 => '搜索提案名称、编号、提交人…',
        _ListType.b14 => '搜索我发起的提案…',
        _ListType.p1 => '搜索抄送提案…',
      };

  XflowListCardMode get _cardMode => switch (widget.type) {
        _ListType.b1 || _ListType.b13 => XflowListCardMode.b1,
        _ListType.b14 => XflowListCardMode.b14,
        _ListType.p1 => XflowListCardMode.p1,
      };

  List<XflowProposalItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = _all.where((it) {
      if (_statusFilter != 'ALL') {
        if (_statusFilter == 'MINE') {
          // 待我审批：当前存在分配给我、状态为 OPEN 的审批待办。
          if (it.todoHint?.status.toUpperCase() != 'OPEN') return false;
        } else if (_normalizeStatus(it.status) != _statusFilter) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      final text =
          '${it.code} ${it.title} ${it.createdByName} ${it.tag1 ?? ''} ${it.txType ?? ''}'
              .toLowerCase();
      return text.contains(q);
    }).toList(growable: false);
    return list;
  }

  Future<void> _deleteDraft(XflowProposalItem item) async {
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
      await _service.deleteProposal(item.id);
      if (!mounted) return;
      showDunesToast(context, '草稿已删除');
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '删除失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _statusCounts(_all);
    final visible = _visible;
    final pending = counts['PENDING'] ?? 0;
    final isB1 = widget.type == _ListType.b1 || widget.type == _ListType.b13;
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                            children: [
                              XflowHeroStatCard(
                                kicker: isB1
                                    ? '我的审批 · ${_all.length} 项'
                                    : widget.type == _ListType.b14
                                        ? '我发起 · ${_all.length} 份'
                                        : '抄送提案 · ${_all.length} 份',
                                badgeText: isB1
                                    ? (pending > 0 ? '$pending 待处理' : '无待办')
                                    : (counts['REJECTED']! > 0 && widget.type == _ListType.b14)
                                        ? '${counts['REJECTED']} 已驳回'
                                        : pending > 0
                                            ? '$pending 审批中'
                                            : '无待审',
                                bigValue: isB1 ? '$pending' : '${_all.length}',
                                bigUnit: isB1 ? '项' : '份',
                                footItems: isB1
                                    ? <(String, String, String?)>[
                                        ('待审批', '$pending', pending > 0 ? 'urge' : null),
                                        ('抄送', '0', null),
                                        ('任务', '0', null),
                                        ('执行', '0', null),
                                      ]
                                    : widget.type == _ListType.b14
                                        ? <(String, String, String?)>[
                                            ('草稿', '${counts['DRAFT']}', null),
                                            ('审批中', '$pending', pending > 0 ? 'urge' : null),
                                            ('已通过', '${counts['APPROVED']}', 'pos'),
                                            ('已驳回', '${counts['REJECTED']}', counts['REJECTED']! > 0 ? 'neg' : null),
                                          ]
                                        : <(String, String, String?)>[
                                            ('草稿', '${counts['DRAFT']}', null),
                                            ('审批中', '$pending', pending > 0 ? 'urge' : null),
                                            ('已通过', '${counts['APPROVED']}', 'pos'),
                                            ('已上线', '${counts['LIVE']}', null),
                                          ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    XflowStatusChip(
                                      label: '全部 ${counts['ALL'] ?? 0}',
                                      active: _statusFilter == 'ALL',
                                      showDot: true,
                                      onTap: () => setState(() => _statusFilter = 'ALL'),
                                    ),
                                    const SizedBox(width: 6),
                                    for (final key in _chipKeys) ...[
                                      XflowStatusChip(
                                        label: '${_statusLabel(key)} ${counts[key] ?? 0}',
                                        active: _statusFilter == key,
                                        onTap: () => setState(() => _statusFilter = key),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              XflowWfListSearch(controller: _search, hint: _searchHint),
                              const SizedBox(height: 10),
                              XflowSectionLabel(
                                accent: widget.type == _ListType.p1 ? '抄送' : '审批',
                                title: '按发起时间倒序',
                              ),
                              const SizedBox(height: 8),
                              if (visible.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _search.text.trim().isEmpty ? '暂无数据' : '无匹配结果',
                                    style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
                                  ),
                                )
                              else
                                ...visible.map((item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 9),
                                      child: XflowProposalListCard(
                                        item: item,
                                        mode: _cardMode,
                                        showTrackButton: widget.type == _ListType.b14,
                                        onTrackTap: () => widget.onOpenProposal(item),
                                        onTap: () => widget.onOpenProposal(item),
                                        onDeleteDraft: widget.type == _ListType.b14 &&
                                                _normalizeStatus(item.status) == 'DRAFT'
                                            ? () => _deleteDraft(item)
                                            : null,
                                      ),
                                    )),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _chipKeys {
    switch (widget.type) {
      case _ListType.p1:
        return const ['DRAFT', 'PENDING', 'APPROVED', 'LIVE'];
      case _ListType.b14:
        return const ['DRAFT', 'PENDING_INITIATE', 'PENDING', 'APPROVED', 'REJECTED', 'VOIDED'];
      case _ListType.b1:
      case _ListType.b13:
        return const ['MINE', 'PENDING', 'APPROVED', 'REJECTED'];
    }
  }

  String _statusLabel(String key) {
    switch (key) {
      case 'MINE':
        return '待我审批';
      case 'DRAFT':
        return '草稿';
      case 'PENDING_INITIATE':
        return '待发起';
      case 'PENDING':
        return '审批中';
      case 'APPROVED':
        return '已通过';
      case 'REJECTED':
        return '已驳回';
      case 'LIVE':
        return '已上线';
      case 'VOIDED':
        return '已作废';
      default:
        return key;
    }
  }

  Widget _buildTopBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left, size: 26),
              tooltip: '返回',
            ),
          Expanded(
            child: Text(
              _title,
              style: DunesTypography.sans(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh, size: 20)),
        ],
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

Map<String, int> _statusCounts(List<XflowProposalItem> rows) {
  var mine = 0;
  var draft = 0;
  var pendingInitiate = 0;
  var pending = 0;
  var approved = 0;
  var rejected = 0;
  var live = 0;
  var voided = 0;
  for (final row in rows) {
    if (row.todoHint?.status.toUpperCase() == 'OPEN') mine++;
    switch (_normalizeStatus(row.status)) {
      case 'DRAFT':
        draft++;
        break;
      case 'PENDING_INITIATE':
        pendingInitiate++;
        break;
      case 'PENDING':
        pending++;
        break;
      case 'APPROVED':
        approved++;
        break;
      case 'REJECTED':
        rejected++;
        break;
      case 'LIVE':
        live++;
        break;
      case 'VOIDED':
        voided++;
        break;
      default:
        break;
    }
  }
  return <String, int>{
    'ALL': rows.length,
    'MINE': mine,
    'DRAFT': draft,
    'PENDING_INITIATE': pendingInitiate,
    'PENDING': pending,
    'APPROVED': approved,
    'REJECTED': rejected,
    'LIVE': live,
    'VOIDED': voided,
  };
}

String _normalizeStatus(String raw) {
  final status = raw.toUpperCase();
  if (status == 'OPEN' || status == 'PENDING') return 'PENDING';
  if (status == 'APPROVED' || status == 'DONE') return 'APPROVED';
  if (status == 'LIVE') return 'LIVE';
  if (status == 'REJECTED') return 'REJECTED';
  if (status == 'DRAFT') return 'DRAFT';
  if (status == 'PENDING_INITIATE') return 'PENDING_INITIATE';
  if (status == 'VOIDED') return 'VOIDED';
  if (status == 'SUPERSEDED') return 'SUPERSEDED';
  return 'OTHER';
}
