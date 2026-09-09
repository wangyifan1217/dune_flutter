import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../proposal_intake/proposal_intake_select.dart';
import '../shell/dunes_toast.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'approval_list_cache.dart';
import 'approval_todo_flow_guide.dart';
import 'task_todo_actions.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

class NativeB1Page extends StatelessWidget {
  const NativeB1Page({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.initialStatusFilter = 'MINE',
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;

  /// 默认「待我审批」；进页时优先于列表缓存里的旧筛选。
  final String? initialStatusFilter;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  Widget build(BuildContext context) {
    return _NativeProposalListPage(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      type: _ListType.b1,
      initialStatusFilter: initialStatusFilter,
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
      initialStatusFilter: 'MINE',
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
  State<_NativeProposalListPage> createState() =>
      _NativeProposalListPageState();
}

class _NativeProposalListPageState extends State<_NativeProposalListPage> {
  late final XflowService _service;
  final TextEditingController _search = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;

  /// 静默刷新中（切筛选/推送等）：保留当前列表，仅局部更新数据。
  bool _refreshing = false;
  String? _error;
  late String _statusFilter =
      widget.initialStatusFilter ??
      (widget.type == _ListType.b1 ? 'MINE' : 'ALL');
  String _templateFilter = 'ALL';
  Map<String, String> _templateTitles = const <String, String>{};
  List<XflowProposalItem> _all = const <XflowProposalItem>[];

  /// 快速切换筛选时丢弃过期响应，避免旧请求覆盖新数据。
  int _loadSeq = 0;
  Timer? _scrollRestoreRetry;
  bool _searchListenerReady = false;

  String get _cacheListType => widget.type.name;

  @override
  void initState() {
    super.initState();
    _service = XflowService(session: widget.session);
    _scrollController.addListener(_onScroll);
    widget.workbenchRefresh?.addListener(_onWorkbenchDataRefresh);
    final cached = ApprovalListCache.instance.peek(
      userId: widget.session.userId,
      listType: _cacheListType,
    );
    if (cached != null) {
      _all = cached.rows;
      // 显式初始筛选（如 B1 默认「待我审批」）优先生效，避免被历史「全部」缓存盖住。
      if (widget.initialStatusFilter == null) {
        _statusFilter = cached.statusFilter;
      }
      _search.text = cached.searchQuery;
      _loading = false;
      _searchListenerReady = true;
      _search.addListener(_onSearchChanged);
      _scheduleScrollRestore();
      unawaited(_load(silent: true));
    } else {
      _searchListenerReady = true;
      _search.addListener(_onSearchChanged);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _persistScrollNow();
    _persistListSnapshot();
    _scrollRestoreRetry?.cancel();
    widget.workbenchRefresh?.removeListener(_onWorkbenchDataRefresh);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (_searchListenerReady) {
      _search.removeListener(_onSearchChanged);
    }
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _persistListSnapshot();
  }

  void _onScroll() {
    _persistScrollNow();
  }

  void _persistScrollNow() {
    if (!_scrollController.hasClients) return;
    ApprovalListCache.instance.saveScrollOffset(
      userId: widget.session.userId,
      listType: _cacheListType,
      offset: _scrollController.offset,
    );
  }

  void _persistListSnapshot() {
    if (_all.isEmpty) return;
    ApprovalListCache.instance.put(
      userId: widget.session.userId,
      listType: _cacheListType,
      rows: _all,
      statusFilter: _statusFilter,
      searchQuery: _search.text,
    );
  }

  void _scheduleScrollRestore() {
    _scrollRestoreRetry?.cancel();
    void attempt() {
      if (!mounted) return;
      _applySavedScroll();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
    _scrollRestoreRetry = Timer.periodic(const Duration(milliseconds: 48), (t) {
      if (!mounted || t.tick > 12) {
        t.cancel();
        return;
      }
      attempt();
    });
  }

  void _applySavedScroll() {
    if (!mounted) return;
    final target = ApprovalListCache.instance.peekScrollOffset(
      userId: widget.session.userId,
      listType: _cacheListType,
    );
    if (target <= 0 || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final next = target.clamp(0.0, max);
    if ((_scrollController.offset - next).abs() < 0.5) return;
    _scrollController.jumpTo(next);
  }

  void _openProposal(XflowProposalItem item) {
    _persistScrollNow();
    _persistListSnapshot();
    widget.onOpenProposal(item);
  }

  void _onWorkbenchDataRefresh() {
    if (!mounted) return;
    // 静默拉新并写回缓存；保留滚动，避免在列表页被推送刷回顶部。
    unawaited(_load(silent: true));
  }

  /// 状态芯片切换：先切本地筛选，再静默拉接口局部刷新。
  void _selectStatusFilter(String key) {
    if (_statusFilter == key) {
      unawaited(_load(silent: true));
      return;
    }
    setState(() => _statusFilter = key);
    _persistListSnapshot();
    unawaited(_load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_loadSeq;
    final templateTitlesFuture = _fetchTemplateTitles();
    if (!silent) {
      setState(() {
        _loading = true;
        _refreshing = false;
        _error = null;
      });
      ApprovalListCache.instance.saveScrollOffset(
        userId: widget.session.userId,
        listType: _cacheListType,
        offset: 0,
      );
    } else if (!_loading && mounted) {
      setState(() => _refreshing = true);
    }
    try {
      final rows = switch (widget.type) {
        _ListType.b1 => await _service.fetchB1Approvals(
          templateKey: _templateFilter == 'ALL' ? '' : _templateFilter,
        ),
        _ListType.b13 => await _service.fetchB13Todos(
          templateKey: _templateFilter == 'ALL' ? '' : _templateFilter,
        ),
        _ListType.b14 => await _service.fetchB14Initiated(
          templateKey: _templateFilter == 'ALL' ? '' : _templateFilter,
        ),
        _ListType.p1 => await _service.fetchP1CcProposals(
          templateKey: _templateFilter == 'ALL' ? '' : _templateFilter,
        ),
      };
      final templateTitles = await templateTitlesFuture;
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _all = rows;
        _templateTitles = templateTitles;
        if (_templateFilter != 'ALL' &&
            !_templateOptions.contains(_templateFilter)) {
          _templateFilter = 'ALL';
        }
        _loading = false;
        _refreshing = false;
      });
      _persistListSnapshot();
      if (silent) _scheduleScrollRestore();
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (silent) {
        setState(() => _refreshing = false);
        return;
      }
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<Map<String, String>> _fetchTemplateTitles() async {
    final templates = <XflowTemplateCard>[
      ...XflowService.cachedTemplatesByCategory('biz'),
      ...XflowService.cachedTemplatesByCategory('adm'),
    ];
    try {
      final remote = await Future.wait([
        _service.fetchTemplatesByCategory('biz'),
        _service.fetchTemplatesByCategory('adm'),
      ]);
      templates.addAll(remote.expand((items) => items));
    } catch (_) {
      // 模板目录加载失败时，仍使用当前列表记录中的模板信息筛选。
    }
    return Map<String, String>.fromEntries(
      templates
          .where((item) => item.enabled && item.templateKey.trim().isNotEmpty)
          .map((item) => MapEntry(item.templateKey, item.title)),
    );
  }

  String get _title => switch (widget.type) {
    _ListType.b1 => '我审批的',
    _ListType.b14 => '我发起的',
    _ListType.p1 => '抄送我的提案',
    _ListType.b13 => '审批待办',
  };

  String get _searchHint => switch (widget.type) {
    _ListType.b1 => '搜索提案名称、编号、提交人…',
    _ListType.b13 => '搜索单据名称、编号、办理动作…',
    _ListType.b14 => '搜索我发起的提案…',
    _ListType.p1 => '搜索抄送提案…',
  };

  XflowListCardMode get _cardMode => switch (widget.type) {
    _ListType.b1 => XflowListCardMode.b1,
    _ListType.b13 => XflowListCardMode.b1,
    _ListType.b14 => XflowListCardMode.b14,
    _ListType.p1 => XflowListCardMode.p1,
  };

  List<XflowProposalItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = _all
        .where((it) {
          if (_statusFilter != 'ALL') {
            if (widget.type == _ListType.b13) {
              if (_statusFilter == 'MINE' && !_isMyOpenTodo(it)) return false;
              if (_statusFilter == 'DONE' &&
                  (it.todoHint?.status.toUpperCase() ?? '') != 'DONE') {
                return false;
              }
              if (_statusFilter != 'MINE' && _statusFilter != 'DONE') {
                return false;
              }
            } else if (_statusFilter == 'MINE') {
              if (!_isMyOpenTodo(it)) return false;
            } else if (_normalizeStatus(it.status) != _statusFilter) {
              return false;
            }
          }
          if (_templateFilter != 'ALL' &&
              _approvalTemplateKey(it) != _templateFilter) {
            return false;
          }
          if (q.isEmpty) return true;
          final text =
              '${it.code} ${it.title} ${it.createdByName} ${it.tag1 ?? ''} ${it.txType ?? ''} ${it.actionTitle ?? ''} ${it.primaryAction ?? ''} ${it.documentKind ?? ''} ${it.proposalType ?? ''} ${it.templateKey ?? ''} ${it.businessType}'
                  .toLowerCase();
          return text.contains(q);
        })
        .toList(growable: false);
    return list;
  }

  Future<void> _deleteDraft(XflowProposalItem item) async {
    final isDraft = _normalizeStatus(item.status) == 'DRAFT';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDraft ? '删除草稿' : '删除单据'),
        content: Text(isDraft ? '确认删除此草稿？删除后不可恢复。' : '确认删除此已作废单据？删除后不可恢复。'),
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
        businessType: item.businessType,
        businessId: item.id,
      );
      if (!mounted) return;
      showDunesToast(context, '草稿已删除');
      ApprovalListCache.instance.invalidate(
        userId: widget.session.userId,
        listType: _cacheListType,
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '删除失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _completeB13Task(
    XflowProposalItem item, {
    bool? verifyPassed,
  }) async {
    final ok = await confirmAndCompleteTaskTodo(
      context: context,
      service: _service,
      item: item,
      verifyPassed: verifyPassed,
    );
    if (!ok || !mounted) return;
    ApprovalListCache.instance.invalidate(
      userId: widget.session.userId,
      listType: _cacheListType,
    );
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _statusCounts(_all);
    final visible = _visible;
    final mine = counts['MINE'] ?? 0;
    final pending = counts['PENDING'] ?? 0;
    final isB1 = widget.type == _ListType.b1;
    final isB13 = widget.type == _ListType.b13;
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? _buildError()
                  : RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        children: [
                          XflowHeroStatCard(
                            kicker: isB1
                                ? '我的审批 · ${_all.length} 项'
                                : isB13
                                ? '审批待办 · ${_all.length} 项'
                                : widget.type == _ListType.b14
                                ? '我发起 · ${_all.length} 份'
                                : '抄送提案 · ${_all.length} 份',
                            badgeText: isB1 || isB13
                                ? (mine > 0
                                      ? (isB13 ? '$mine 待办理' : '$mine 待处理')
                                      : '无待办')
                                : (counts['REJECTED']! > 0 &&
                                      widget.type == _ListType.b14)
                                ? '${counts['REJECTED']} 已驳回'
                                : pending > 0
                                ? '$pending 审批中'
                                : '无待审',
                            badgeUrge: isB1 || isB13
                                ? mine > 0
                                : (pending > 0 ||
                                      (widget.type == _ListType.b14 &&
                                          (counts['REJECTED'] ?? 0) > 0)),
                            bigValue: isB1 || isB13
                                ? '$mine'
                                : '${_all.length}',
                            bigUnit: isB1 || isB13 ? '项' : '份',
                            footItems: isB13
                                ? <(String, String, String?)>[
                                    ('待办理', '$mine', mine > 0 ? 'urge' : null),
                                    ('已办理', '${counts['DONE']}', 'pos'),
                                  ]
                                : isB1
                                ? <(String, String, String?)>[
                                    ('待审批', '$mine', mine > 0 ? 'urge' : null),
                                    ('抄送', '0', null),
                                    ('任务', '0', null),
                                    ('执行', '0', null),
                                  ]
                                : widget.type == _ListType.b14
                                ? <(String, String, String?)>[
                                    (
                                      '审批中',
                                      '$pending',
                                      pending > 0 ? 'urge' : null,
                                    ),
                                    ('已通过', '${counts['APPROVED']}', 'pos'),
                                    (
                                      '已驳回',
                                      '${counts['REJECTED']}',
                                      (counts['REJECTED'] ?? 0) > 0
                                          ? 'neg'
                                          : null,
                                    ),
                                  ]
                                : <(String, String, String?)>[
                                    (
                                      '审批中',
                                      '$pending',
                                      pending > 0 ? 'urge' : null,
                                    ),
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
                                  onTap: () => _selectStatusFilter('ALL'),
                                ),
                                const SizedBox(width: 6),
                                for (final key in _chipKeys) ...[
                                  XflowStatusChip(
                                    label:
                                        '${_statusLabel(key)} ${counts[key] ?? 0}',
                                    active: _statusFilter == key,
                                    onTap: () => _selectStatusFilter(key),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '审批模板',
                                style: DunesTypography.sans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DunesColors.text2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ProposalSelectField<String>(
                                  value: _templateFilter == 'ALL'
                                      ? null
                                      : _templateFilter,
                                  hint: '全部模板',
                                  searchable: true,
                                  options: _templateOptions
                                      .where((key) => key != 'ALL')
                                      .map(
                                        (key) => ProposalSelectOption(
                                          value: key,
                                          label: _templateLabel(key),
                                          meta: key,
                                        ),
                                      )
                                      .toList(growable: false),
                                  onSelected: (key) =>
                                      _selectTemplateFilter(key ?? 'ALL'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          XflowWfListSearch(
                            controller: _search,
                            hint: _searchHint,
                          ),
                          const SizedBox(height: 10),
                          XflowSectionLabel(
                            accent: widget.type == _ListType.p1 ? '抄送' : '审批',
                            title: '按发起时间倒序',
                          ),
                          if (_refreshing) ...[
                            const SizedBox(height: 10),
                            const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (visible.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              alignment: Alignment.center,
                              child: Text(
                                _search.text.trim().isEmpty ? '暂无数据' : '无匹配结果',
                                style: DunesTypography.sans(
                                  fontSize: 12,
                                  color: DunesColors.text3,
                                ),
                              ),
                            )
                          else
                            ...visible.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: XflowProposalListCard(
                                  item: item,
                                  mode: _cardMode,
                                  onTap: () => _openProposal(item),
                                  onPrimaryAction:
                                      widget.type == _ListType.b13 &&
                                          _isMyOpenTodo(item)
                                      ? () => _completeB13Task(
                                          item,
                                          verifyPassed:
                                              (item.primaryAction ?? '')
                                                      .toUpperCase() ==
                                                  'VERIFY_INVOICE'
                                              ? true
                                              : null,
                                        )
                                      : null,
                                  primaryActionLabel:
                                      (item.primaryAction ?? '')
                                              .toUpperCase() ==
                                          'VERIFY_INVOICE'
                                      ? '核验通过'
                                      : item.actionTitle,
                                  onDangerAction:
                                      widget.type == _ListType.b13 &&
                                          _isMyOpenTodo(item) &&
                                          (item.primaryAction ?? '')
                                                  .toUpperCase() ==
                                              'VERIFY_INVOICE'
                                      ? () => _completeB13Task(
                                          item,
                                          verifyPassed: false,
                                        )
                                      : null,
                                  dangerActionLabel: '核验失败',
                                  onDeleteDraft:
                                      widget.type == _ListType.b14 &&
                                          (_normalizeStatus(item.status) ==
                                                  'DRAFT' ||
                                              _normalizeStatus(item.status) ==
                                                  'VOIDED')
                                      ? () => _deleteDraft(item)
                                      : null,
                                ),
                              ),
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

  List<String> get _chipKeys {
    switch (widget.type) {
      case _ListType.p1:
        return const ['DRAFT', 'PENDING', 'APPROVED', 'LIVE'];
      case _ListType.b14:
        return const [
          'DRAFT',
          'PENDING_INITIATE',
          'PENDING',
          'APPROVED',
          'REJECTED',
          'VOIDED',
        ];
      case _ListType.b1:
        return const ['MINE', 'PENDING', 'APPROVED', 'REJECTED'];
      case _ListType.b13:
        return const ['MINE', 'DONE'];
    }
  }

  List<String> get _templateOptions {
    final keys = <String>{
      ..._templateTitles.keys,
      ..._all.map(_approvalTemplateKey).where((key) => key.isNotEmpty),
    }.toList()..sort((a, b) => _templateLabel(a).compareTo(_templateLabel(b)));
    return <String>['ALL', ...keys];
  }

  String _approvalTemplateKey(XflowProposalItem item) {
    final templateKey = item.templateKey?.trim() ?? '';
    if (templateKey.isNotEmpty) return templateKey;
    for (final value in [
      item.documentKind,
      item.proposalType,
      item.txType,
      item.businessType,
    ]) {
      final key = value?.trim() ?? '';
      if (key.isNotEmpty) return key;
    }
    return '';
  }

  String _templateLabel(String key) => _templateTitles[key] ?? key;

  void _selectTemplateFilter(String? value) {
    if (value == null || value == _templateFilter) return;
    setState(() => _templateFilter = value);
    unawaited(_load(silent: true));
  }

  String _statusLabel(String key) {
    switch (key) {
      case 'MINE':
        return widget.type == _ListType.b13 ? '待办理' : '待我审批';
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
      case 'DONE':
        return '已办理';
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
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.type == _ListType.b13)
            IconButton(
              onPressed: () => showApprovalTodoFlowGuide(context),
              icon: const Icon(Icons.help_outline, size: 20),
              tooltip: '通过后待办流程',
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
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

String _normalizeStatus(String raw) {
  final status = raw.toUpperCase();
  if (status == 'OPEN' || status == 'PENDING') return 'PENDING';
  if (status == 'APPROVED') return 'APPROVED';
  // DONE 代表当前用户的待办已处理，不代表整单审批已通过。
  if (status == 'DONE') return 'PENDING';
  if (status == 'LIVE') return 'LIVE';
  if (status == 'REJECTED') return 'REJECTED';
  if (status == 'DRAFT') return 'DRAFT';
  if (status == 'PENDING_INITIATE') return 'PENDING_INITIATE';
  if (status == 'VOIDED' || status == 'WITHDRAWN' || status == 'CANCELLED') {
    return status;
  }
  if (status == 'SUPERSEDED') return 'SUPERSEDED';
  return 'OTHER';
}

bool _isMyOpenTodo(XflowProposalItem row) {
  final todoStatus = row.todoHint?.status.toUpperCase() ?? '';
  if (todoStatus == 'OPEN') return true;
  // 部分 inbox 行未带 status，但仍有有效 todo 且展示为待审批。
  if (todoStatus.isEmpty &&
      (row.todoHint?.id ?? 0) > 0 &&
      _normalizeStatus(row.status) == 'PENDING') {
    return true;
  }
  return false;
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
  var done = 0;
  for (final row in rows) {
    if (_isMyOpenTodo(row)) mine++;
    if ((row.todoHint?.status.toUpperCase() ?? '') == 'DONE') done++;
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
    'DONE': done,
  };
}
