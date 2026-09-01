import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import '../xflow/approval_chat_forward.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/proposal_import_template.dart';
import '../xflow/xflow_detail_comments.dart';
import '../xflow/xflow_file_open.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'flow_panorama/flow_ctx.dart';
import 'flow_panorama/flow_ctx_mapper.dart';
import 'flow_panorama/flow_panorama_section.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_select.dart';
import 'proposal_intake_service.dart';
import 'proposal_intake_ui.dart';
import 'settlement_catalog.dart';

enum _ProposalPage { list, form }

const _proposalStatusFilters = <(String, String)>[
  ('', '全部'),
  ('draft', '草稿'),
  ('filling', '填写中'),
  ('reviewing', '复核中'),
  ('pending_president', '待最终确认'),
  ('done', '已完成'),
];

class NativeProposalIntakePage extends StatefulWidget {
  const NativeProposalIntakePage({
    super.key,
    required this.session,
    this.onChromeChanged,
    this.showCreate = true,
    this.assistantMode = false,
    this.initialIntakeId,
    this.kind = '',
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final bool showCreate;
  final bool assistantMode;
  final int? initialIntakeId;

  /// `sales` / `purchase` 只列该类；空字符串表示全部（审批助手）。
  final String kind;

  @override
  State<NativeProposalIntakePage> createState() =>
      _NativeProposalIntakePageState();
}

class _NativeProposalIntakePageState extends State<NativeProposalIntakePage> {
  late final ProposalIntakeService _service = ProposalIntakeService(
    session: widget.session,
  );
  final _search = TextEditingController();
  final ScrollController _listScroll = ScrollController();
  _ProposalPage _page = _ProposalPage.list;
  List<ProposalIntakeRow> _rows = const [];
  ProposalIntakeOptions? _options;
  List<ProposalPerson> _people = const [];
  ProposalIntakeRow? _editing;
  int _formSession = 0;
  bool _loading = true;
  bool _saving = false;
  bool _opening = false;
  bool _nextBusy = false;
  String? _error;
  String _statusFilter = '';
  List<ProposalIntakeRow> _actionQueue = const [];
  double _listScrollOffset = 0;
  bool _didOpenInitial = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  void _rememberListScroll() {
    if (_listScroll.hasClients) {
      _listScrollOffset = _listScroll.offset;
    }
  }

  void _restoreListScroll({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page != _ProposalPage.list) return;
      if (!_listScroll.hasClients) {
        if (attempt < 10) _restoreListScroll(attempt: attempt + 1);
        return;
      }
      final max = _listScroll.position.maxScrollExtent;
      final target = _listScrollOffset.clamp(0.0, max);
      if ((_listScroll.offset - target).abs() > 0.5) {
        _listScroll.jumpTo(target);
      }
    });
  }

  Future<void> _load({bool quiet = false, bool resetScroll = false}) async {
    if (resetScroll) {
      _listScrollOffset = 0;
      if (_listScroll.hasClients) _listScroll.jumpTo(0);
    }
    if (!quiet || _rows.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await Future.wait([
        _service.fetchList(
          keyword: widget.assistantMode ? '' : _search.text,
          status: widget.assistantMode ? '' : _statusFilter,
          kind: widget.assistantMode ? '' : widget.kind,
          actionable: widget.assistantMode,
          pageSize: widget.assistantMode ? 100 : 20,
        ),
        _service.fetchOptions(),
        _service.fetchPeople(),
      ]);
      if (!mounted) return;
      var items = (result[0] as ProposalIntakeListResult).items;
      if (widget.assistantMode) {
        final q = _search.text.trim().toLowerCase();
        if (q.isNotEmpty) {
          items = items
              .where((row) {
                final hay = '${row.title} ${row.code}'.toLowerCase();
                return hay.contains(q);
              })
              .toList(growable: false);
        }
      }
      setState(() {
        _rows = items;
        _options = result[1] as ProposalIntakeOptions;
        _people = result[2] as List<ProposalPerson>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _openInitialIfNeeded();
  }

  Future<void> _openInitialIfNeeded() async {
    if (_didOpenInitial) return;
    final id = widget.initialIntakeId ?? 0;
    if (id <= 0) return;
    _didOpenInitial = true;
    await _openExisting(
      ProposalIntakeRow(
        id: id,
        code: '',
        title: '',
        status: 'draft',
        form: const {},
        review: const {},
        createdBy: 0,
        createdAt: '',
        updatedAt: '',
        version: 0,
      ),
    );
  }

  Future<void> _refreshLookups() async {
    final result = await Future.wait([
      _service.fetchOptions(),
      _service.fetchPeople(),
    ]);
    if (!mounted) return;
    setState(() {
      _options = result[0] as ProposalIntakeOptions;
      _people = result[1] as List<ProposalPerson>;
    });
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      await _refreshLookups();
      if (!mounted) return;
      _openForm(
        ProposalIntakeRow(
          id: 0,
          code: '',
          title: '',
          kind: widget.kind.trim().isEmpty
              ? 'sales'
              : normalizeProposalIntakeKind(widget.kind),
          status: 'draft',
          form: _defaultForm(),
          review: _defaultReview(
            purchase: proposalIntakeIsPurchase(widget.kind),
          ),
          createdBy: widget.session.userId,
          createdAt: '',
          updatedAt: '',
          version: 1,
        ),
      );
    } catch (error) {
      _toast(friendlyErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatusFilter(String status) async {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    await _load(resetScroll: true);
  }

  Future<void> _forwardRow(ProposalIntakeRow row) async {
    if (row.id <= 0) return;
    await forwardApprovalToConversation(
      context: context,
      session: widget.session,
      share: ApprovalChatShare.fromProposalIntake(
        id: row.id,
        title: row.title,
        status: row.status,
        code: row.code,
        submitterName: row.initiatorDisplayName(_people),
      ),
    );
  }

  Future<void> _showStakeholders(ProposalIntakeRow row) async {
    final lines = row.stakeholderLines(people: _people, options: _options);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('相关人员'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 118,
                        child: Text(
                          line.role,
                          style: const TextStyle(
                            color: ProposalPalette.text3,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line.name,
                          style: const TextStyle(
                            color: ProposalPalette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ProposalIntakeRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提案'),
        content: Text('确定删除「${row.code}」？最终审核开始前可以删除，删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ProposalPalette.coral,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(row.id);
      if (!mounted) return;
      _toast('已删除');
      await _load();
    } catch (error) {
      _toast(friendlyErrorText(error), error: true);
    }
  }

  /// 新建提案不预填业务值。市场部负责人二由提交人另行指定。
  Map<String, dynamic> _defaultForm() => {
    'supplies': <String>[],
    'channels': <String>[],
    'profitModes': <String>[],
    'technologyCapabilities': <String>[],
    'outputForms': <String>[],
    'developmentTypes': <String>[],
    'costItems': <String>[],
    'costItemCodes': <String>[],
    'costItemAmounts': <String, dynamic>{},
    'costItemSettleTerms': <String, dynamic>{},
    'businessCostItems': <String>[],
    'businessCostItemCodes': <String>[],
    'businessCostItemAmounts': <String, dynamic>{},
    'businessCostItemSettleTerms': <String, dynamic>{},
    'operatingCostItems': <String>[],
    'operatingCostItemCodes': <String>[],
    'operatingCostItemAmounts': <String, dynamic>{},
    'taxCostItems': <String>[],
    'taxCostItemCodes': <String>[],
    'taxCostItemAmounts': <String, dynamic>{},
    'purchaseProducts': <String>[],
    'financeInterfaces': <String, dynamic>{},
  };

  Map<String, dynamic> _defaultReview({bool purchase = false}) => {
    'marketCompleted': false,
    'technologyCompleted': false,
    'financeInterfaceCompleted': false,
    'financeCompleted': false,
    'purchaseContractCompleted': false,
    'salesContractCompleted': purchase,
    'contractsCompleted': false,
    'technologyItems': <String, dynamic>{},
    'financeItems': <String, dynamic>{},
    'contractItems': <String, dynamic>{},
  };

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showProposalCenterToast(context, message, error: error);
  }

  Future<void> _openExisting(ProposalIntakeRow row) async {
    if (_opening) return;
    _rememberListScroll();
    setState(() => _opening = true);
    try {
      final detail = await _service.fetchDetail(row.id);
      await _refreshLookups();
      if (mounted) _openForm(detail);
    } catch (error) {
      _toast(friendlyErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openForm(ProposalIntakeRow row) {
    if (_page == _ProposalPage.list) _rememberListScroll();
    setState(() {
      _formSession++;
      _editing = row;
      _page = _ProposalPage.form;
    });
    widget.onChromeChanged?.call(
      TaskShellChrome(onBack: () => unawaited(_backToList())),
    );
    if (widget.assistantMode) unawaited(_refreshActionQueue());
  }

  Future<void> _refreshActionQueue() async {
    try {
      final result = await _service.fetchList(actionable: true, pageSize: 100);
      if (!mounted) return;
      setState(() => _actionQueue = result.items);
    } catch (_) {}
  }

  Future<void> _goNext({
    required int fromId,
    required bool afterDecision,
  }) async {
    if (_nextBusy) return;
    setState(() => _nextBusy = true);
    try {
      final result = await _service.fetchList(actionable: true, pageSize: 100);
      if (!mounted) return;
      setState(() => _actionQueue = result.items);
      final next = nextProposalIntake(
        items: result.items,
        currentId: fromId,
        afterDecision: afterDecision,
      );
      if (next == null) {
        _toast('没有需要处理的提案了');
        if (afterDecision) _backToList();
        return;
      }
      await _openExisting(next);
    } catch (error) {
      _toast(friendlyErrorText(error, fallback: '加载下一提案失败'), error: true);
      if (afterDecision) _backToList();
    } finally {
      if (mounted) setState(() => _nextBusy = false);
    }
  }

  Future<void> _backToList() async {
    final editing = _editing;
    if (editing != null &&
        editing.id <= 0 &&
        proposalIntakeHasMeaningfulContent(editing)) {
      try {
        await _service.create(
          title: editing.title,
          kind: editing.kind,
          form: proposalIntakeConfirmContractEdits(editing.form),
          review: editing.review,
        );
        if (mounted) _toast('已保存草稿');
      } catch (error) {
        _toast(friendlyErrorText(error, fallback: '保存草稿失败'), error: true);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _page = _ProposalPage.list;
      _editing = null;
    });
    widget.onChromeChanged?.call(const TaskShellChrome());
    await _load(quiet: true);
    _restoreListScroll();
  }

  @override
  Widget build(BuildContext context) {
    final showForm =
        _page == _ProposalPage.form && _editing != null && _options != null;
    return IndexedStack(
      index: showForm ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        TickerMode(enabled: !showForm, child: _buildList()),
        if (showForm) _buildForm() else const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildForm() {
    final row = _editing!;
    return ProposalIntakeForm(
      key: ValueKey('proposal-form-$_formSession'),
      row: row,
      session: widget.session,
      options: _options!,
      people: _people,
      contracts: const [],
      saving: _saving,
      service: _service,
      onChanged: (next) => _editing = next,
      onSaved: (next) {
        setState(() => _editing = next);
        _toast('已保存');
      },
      onSubmit: (next) {
        setState(() => _editing = next);
        _toast(
          next.status == 'done'
              ? '提案已通过'
              : next.status == 'pending_president'
              ? '已通知最终人'
              : '已更新',
        );
      },
      onError: (message) => _toast(message, error: true),
      onDeleted: () => unawaited(_backToList()),
      onNext: widget.assistantMode
          ? () => unawaited(_goNext(fromId: row.id, afterDecision: false))
          : null,
      onAfterFinalDecision: widget.assistantMode
          ? (id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                unawaited(_goNext(fromId: id, afterDecision: true));
              });
            }
          : null,
      nextCount: widget.assistantMode
          ? _actionQueue.where((item) => item.id != row.id).length
          : 0,
      nextBusy: _nextBusy,
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildListBody(compact: constraints.maxWidth < 560),
    );
  }

  Widget _buildListBody({required bool compact}) {
    final search = TextField(
      controller: _search,
      onSubmitted: (_) => unawaited(_load(resetScroll: true)),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: const TextStyle(fontSize: 13),
      decoration: proposalInputDecoration(
        hint: '搜索提案编号或名称',
      ).copyWith(prefixIcon: const Icon(Icons.search, size: 19)),
    );
    final refresh = OutlinedButton.icon(
      onPressed: _loading ? null : _load,
      icon: const Icon(Icons.refresh, size: 17),
      label: const Text('刷新'),
    );
    final create = widget.showCreate
        ? FilledButton.icon(
            onPressed: _saving || _options == null ? null : _create,
            style: FilledButton.styleFrom(
              backgroundColor: ProposalPalette.purple,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              proposalIntakeIsPurchase(widget.kind) ? '新建采购提案' : '新建提案',
            ),
          )
        : null;
    final statusFilter = compact
        ? InputDecorator(
            decoration: proposalInputDecoration(hint: '状态').copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                isExpanded: true,
                items: [
                  for (final item in _proposalStatusFilters)
                    DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                ],
                onChanged: _loading
                    ? null
                    : (value) => unawaited(_setStatusFilter(value ?? '')),
              ),
            ),
          )
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _proposalStatusFilters)
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _statusFilter == item.$1,
                  selectedColor: ProposalPalette.purpleSoft,
                  labelStyle: TextStyle(
                    color: _statusFilter == item.$1
                        ? ProposalPalette.purpleDeep
                        : ProposalPalette.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: _statusFilter == item.$1
                        ? ProposalPalette.purpleLine
                        : ProposalPalette.border,
                  ),
                  onSelected: _loading
                      ? null
                      : (_) => unawaited(_setStatusFilter(item.$1)),
                ),
            ],
          );
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        color: ProposalPalette.page,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 20,
            8,
            compact ? 12 : 20,
            36,
          ),
          child: Column(
            children: [
              ProposalCard(
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: compact
                    ? Column(
                        children: [
                          search,
                          if (!widget.assistantMode) ...[
                            const SizedBox(height: 10),
                            statusFilter,
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: refresh),
                              if (create != null) ...[
                                const SizedBox(width: 10),
                                Expanded(child: create),
                              ],
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: search),
                              const SizedBox(width: 10),
                              refresh,
                              if (create != null) ...[
                                const SizedBox(width: 10),
                                create,
                              ],
                            ],
                          ),
                          if (!widget.assistantMode) ...[
                            const SizedBox(height: 10),
                            statusFilter,
                          ],
                        ],
                      ),
              ),
              Expanded(child: _buildListContent(compact: compact)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListContent({required bool compact}) {
    if (_error != null && _rows.isEmpty) {
      return _ListMessage(
        icon: Icons.error_outline,
        title: '加载失败',
        message: _error!,
      );
    }
    if (_rows.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _ListMessage(
        icon: Icons.assignment_outlined,
        title: '暂无提案',
        message: widget.showCreate
            ? (proposalIntakeIsPurchase(widget.kind)
                  ? '点击右上角「新建采购提案」开始录入'
                  : '点击右上角「新建提案」开始录入')
            : '当前没有需要你处理的提案',
      );
    }
    final list = ListView.separated(
      key: const PageStorageKey('proposal-intake-list'),
      controller: _listScroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final row = _rows[index];
        return _ProposalListTile(
          row: row,
          initiatorName: row.initiatorDisplayName(_people),
          canDelete: row.canDeleteBy(widget.session.userId),
          compact: compact,
          onTap: () => unawaited(_openExisting(row)),
          onPeople: () => unawaited(_showStakeholders(row)),
          onForward: () => unawaited(_forwardRow(row)),
          onDelete: () => unawaited(_confirmDelete(row)),
        );
      },
    );
    if (!_loading) return list;
    return Stack(
      children: [
        list,
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ],
    );
  }
}

class _ProposalListTile extends StatelessWidget {
  const _ProposalListTile({
    required this.row,
    required this.initiatorName,
    required this.canDelete,
    required this.compact,
    required this.onTap,
    required this.onPeople,
    required this.onForward,
    required this.onDelete,
  });

  final ProposalIntakeRow row;
  final String initiatorName;
  final bool canDelete;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onPeople;
  final VoidCallback onForward;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = switch (row.status) {
      'done' => ('已完成', ProposalChipKind.ok),
      'pending_president' => ('待最终确认', ProposalChipKind.purple),
      'reviewing' => ('复核中', ProposalChipKind.purple),
      'filling' => ('填写中', ProposalChipKind.draft),
      _ => ('草稿', ProposalChipKind.draft),
    };
    final updated = formatProposalIntakeDateTime(row.updatedAt);
    final metaStyle = const TextStyle(
      color: ProposalPalette.text3,
      fontSize: 11,
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE9E2EF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 38 : 42,
                height: compact ? 38 : 42,
                decoration: BoxDecoration(
                  color: ProposalPalette.purpleSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: ProposalPalette.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title.isEmpty
                          ? proposalIntakeUntitledTitle(row.kind)
                          : row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProposalPalette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (compact) ...[
                      Text(
                        '${row.code}  ·  发起人 $initiatorName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                      if (updated.isNotEmpty)
                        Text('更新 $updated', style: metaStyle),
                    ] else
                      Text(
                        updated.isEmpty
                            ? '${row.code}  ·  发起人 $initiatorName'
                            : '${row.code}  ·  发起人 $initiatorName  ·  更新 $updated',
                        style: metaStyle,
                      ),
                    if (proposalIntakeActionLabel(row.myAction).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        proposalIntakeActionLabel(row.myAction),
                        style: const TextStyle(
                          color: ProposalPalette.purpleDeep,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ProposalStatusChip(label: label, kind: kind),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '相关人员',
                        visualDensity: VisualDensity.compact,
                        onPressed: onPeople,
                        icon: const Icon(
                          Icons.people_alt_outlined,
                          color: ProposalPalette.purpleDeep,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        tooltip: '转发',
                        visualDensity: VisualDensity.standard,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: onForward,
                        icon: const Icon(
                          Icons.forward_outlined,
                          color: ProposalPalette.purpleDeep,
                          size: 24,
                        ),
                      ),
                      if (canDelete)
                        IconButton(
                          tooltip: '删除',
                          visualDensity: VisualDensity.compact,
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: ProposalPalette.coral,
                            size: 20,
                          ),
                        ),
                      const Icon(
                        Icons.chevron_right,
                        color: ProposalPalette.text3,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListMessage extends StatelessWidget {
  const _ListMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: ProposalPalette.purpleLine),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: ProposalPalette.text,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          style: const TextStyle(color: ProposalPalette.text3, fontSize: 12),
        ),
      ],
    ),
  );
}

class ProposalIntakeForm extends StatefulWidget {
  const ProposalIntakeForm({
    super.key,
    required this.row,
    required this.session,
    required this.options,
    required this.people,
    required this.contracts,
    required this.saving,
    required this.service,
    required this.onChanged,
    required this.onSaved,
    required this.onSubmit,
    required this.onError,
    this.enableComments = true,
    this.onDeleted,
    this.onClose,
    this.onNext,
    this.onAfterFinalDecision,
    this.nextCount = 0,
    this.nextBusy = false,
    this.catalog,
  });

  final ProposalIntakeRow row;
  final AuthSession session;
  final ProposalIntakeOptions options;
  final List<ProposalPerson> people;
  final List<ProposalContractChoice> contracts;
  final bool saving;
  final ProposalIntakeService service;
  final bool enableComments;
  final ValueChanged<ProposalIntakeRow> onChanged;
  final ValueChanged<ProposalIntakeRow> onSaved;
  final ValueChanged<ProposalIntakeRow> onSubmit;
  final ValueChanged<String> onError;
  final VoidCallback? onDeleted;
  final VoidCallback? onClose;
  final VoidCallback? onNext;
  final ValueChanged<int>? onAfterFinalDecision;
  final int nextCount;
  final bool nextBusy;
  final SettlementCatalogService? catalog;

  @override
  State<ProposalIntakeForm> createState() => _ProposalIntakeFormState();
}

class _ProposalIntakeFormState extends State<ProposalIntakeForm> {
  late ProposalIntakeRow _row;
  final _scroll = ScrollController();
  final _marketKey = GlobalKey();
  final _techKey = GlobalKey();
  final _financeKey = GlobalKey();
  final _flowKey = GlobalKey();
  List<String> _issues = const [];
  bool _dirty = false;
  int _fieldEpoch = 0;
  bool _deleting = false;
  bool _forwarding = false;
  List<ProposalContractChoice> _contractHits = const [];
  int _contractSearchSeq = 0;
  String? _uploadingContractPrefix;
  String? _openingContractPrefix;
  List<ProposalImportTemplateItem> _importTemplates =
      const <ProposalImportTemplateItem>[];
  bool _importTemplatesLoading = false;
  String? _importTemplatesError;
  bool _uploadingProductFile = false;
  bool _draggingProduct = false;
  String? _draggingUnsignedPrefix;
  String? _openingProductFile;
  String? _downloadingProductFile;
  String? _downloadingContractPrefix;
  late final SettlementCatalogService _catalog;
  bool _ownsCatalog = false;
  List<CatalogRef> _sectorCatalog = const [];
  List<CatalogRef> _productCatalog = const [];
  List<CatalogRef> _projectCatalog = const [];
  List<CatalogRef> _syncSourceCatalog = const [];
  final Map<String, _SettleCatalogBundle> _settleBundles = {};
  final Set<String> _settleLoading = {};
  final Map<String, List<ChannelProductHit>> _assetProductHits = {};
  final Map<String, int> _assetProductSearchSeq = {};
  final Set<String> _assetProductSearching = {};
  int _productCatalogSeq = 0;

  static const _financeFields = <(String, String)>[
    ('salesScale', '销售规模目标（万元）'),
    ('revenue', '收入（万元）'),
    ('invoiceAmount', '发票（万元）'),
    ('profit', '利润（万元）'),
    ('margin', '毛利率（%）'),
    ('turnoverCash', '预计周转资金（万元）'),
    ('turnoverTimes', '月周转次数'),
    ('supplySettleMode', '供给侧 · 结算模式'),
    ('supplySettleCycle', '供给侧 · 结算周期'),
    ('supplyPayer', '供给侧 · 付款主体'),
    ('supplyPayAccount', '供给侧 · 付款账户'),
    ('channelSettleMode', '渠道侧 · 结算模式'),
    ('channelSettleCycle', '渠道侧 · 结算周期'),
    ('channelPayee', '渠道侧 · 收款主体'),
    ('channelReceiveAccount', '渠道侧 · 收款账户'),
    ('financeRemark', '备注'),
  ];

  /// 与后端 proposalTechnologyReviewFields 保持一致。
  static const _technologyReviewFields = <String>[
    'technologyPlatform',
    'technologyCapabilities',
    'outputForms',
    'developmentTypes',
    'hasRdCost',
    'rdAmount',
    'deliveryDate',
  ];

  /// 与后端 proposalContractReviewFields 保持一致（复核键为 prefix.字段）。
  static const _contractReviewFields = <String>[
    'Mode',
    'No',
    'Name',
    'SignDate',
    'OurParty',
    'Counterparty',
    'ValidPeriod',
    'CoreTerms',
  ];

  static const _contractReviewFieldLabels = <String, String>{
    'Mode': '合同状态',
    'No': '合同编号',
    'Name': '合同名称',
    'SignDate': '签署时间',
    'OurParty': '我方签约主体',
    'Counterparty': '对方签约主体',
    'ValidPeriod': '有效期',
    'CoreTerms': '核心条款',
  };

  static const _techReviewLabel = '市场部负责人二复核';
  static const _financeReviewLabel = '财务部负责人二复核';

  static const _kFinanceReviewKeys = <String>[
    'salesScale',
    'revenue',
    'invoiceAmount',
    'profit',
    'margin',
    'turnoverCash',
    'turnoverTimes',
    'supplySettleMode',
    'supplySettleCycle',
    'supplyPayer',
    'supplyPayAccount',
    'channelSettleMode',
    'channelSettleCycle',
    'channelPayee',
    'channelReceiveAccount',
    'financeRemark',
    'costItems',
    'operatingCost',
    'taxCost',
    'rollback',
  ];

  @override
  void initState() {
    super.initState();
    _row = widget.row;
    _ownsCatalog = widget.catalog == null;
    _catalog = widget.catalog ?? SettlementCatalogService();
    unawaited(_loadMarketCatalog());
    if (_showProductTemplates) unawaited(_loadImportTemplates());
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_ownsCatalog) _catalog.dispose();
    super.dispose();
  }

  int get _me => widget.session.userId;

  bool get _isPurchase => proposalIntakeIsPurchase(_row.kind);

  bool get _isLocked =>
      _row.status == 'pending_president' ||
      (_row.status == 'done' && !_row.techRevisionOpen);

  /// 最终审核人、已通过提案只看已填结果，不铺开未选项。
  bool get _showSelectedAsText =>
      _row.status == 'pending_president' ||
      (_row.status == 'done' && !_row.isTechRevising);

  bool get _isReviewing =>
      _stage == 'reviewing' ||
      _stage == 'awaiting_submit' ||
      _stage == 'tech_reviewing';

  /// 复核开始后整单只读；要改内容必须先驳回。科技变更填写轮除外。
  bool get _isContentFrozen =>
      _row.status == 'pending_president' ||
      (_row.status == 'done' && !_row.isTechRevising) ||
      _isReviewing;

  int _ownerId(String key) => int.tryParse(_text('${key}UserId')) ?? 0;

  bool get _isSubmitter => _me > 0 && _row.createdBy == _me;

  bool _isOwner(String key) => _me > 0 && _ownerId(key) == _me;

  /// 科技逐条复核人：已指定则只认负责二；旧单未指定时回退提交人。
  bool get _isMarketOwner2 {
    if (_me <= 0) return false;
    final owner = _ownerId('marketOwner2');
    if (owner > 0) return owner == _me;
    return _row.createdBy == _me;
  }

  bool get _isTechFiller => _isOwner('technologyOwner');

  bool get _isPresident {
    if (_me <= 0) return false;
    if (widget.options.presidentUserIds.isNotEmpty) {
      return widget.options.isConfiguredPresident(_me);
    }
    return _isOwner('president');
  }

  String get _stage => _row.resolvedStage;

  bool get _canEditMarket =>
      !_isContentFrozen && _isSubmitter && !_row.techRevisionOpen;

  bool get _canEditTech =>
      _isTechFiller && (!_isContentFrozen || _row.isTechRevising);

  bool get _canEditProductFiles =>
      _canEditMarket ||
      (_row.isTechRevising && (_isTechFiller || _isSubmitter));

  bool get _canEditFinanceModules =>
      !_isLocked &&
      _isOwner('financeOwner2') &&
      _row.status == 'reviewing' &&
      !_row.techRevisionOpen;

  bool get _canEditSkuSettlements =>
      !_showSelectedAsText && (_canEditMarket || _canEditFinanceModules);

  List<String> get _financeReviewKeys => [
    ..._kFinanceReviewKeys,
    ...proposalIntakeLaunchModuleReviewKeys(_form),
    ...proposalIntakeSkuSettleReviewKeys(_form),
  ];

  bool get _isMarketOwner1 => _isOwner('marketOwner1');

  bool get _isAnyOwner2 =>
      _isOwner('financeOwner2') || _isOwner('marketOwner2');

  bool get _businessCostSealed =>
      _form['businessCostRedacted'] == true ||
      (_isAnyOwner2 && !_isMarketOwner1);

  bool get _canEditBusinessCost =>
      !_isLocked && _isMarketOwner1 && _stage == 'reviewing';

  bool get _canSave =>
      (_row.isTechRevising && _isTechFiller) ||
      _canEditBusinessCost ||
      _canEditFinanceModules ||
      (!_isContentFrozen &&
          !_row.techRevisionOpen &&
          (_isSubmitter || _isTechFiller));

  bool get _canStartTechRevision =>
      _row.id > 0 &&
      _row.status == 'done' &&
      !_row.techRevisionOpen &&
      _isTechFiller;

  bool get _canConfirmTechRevision =>
      _row.id > 0 && _row.isTechRevising && _isTechFiller;

  bool get _canDecidePresident =>
      _row.id > 0 && _row.status == 'pending_president' && _isPresident;

  bool get _canNotifyTech =>
      _row.id > 0 &&
      !_isLocked &&
      _isSubmitter &&
      _stage == 'filling' &&
      _review['reviewRejected'] != true;

  bool get _canNotifyMarket2 =>
      _row.id > 0 && !_isLocked && _isTechFiller && _stage == 'awaiting_tech';

  bool get _canStartReview =>
      _row.id > 0 &&
      !_isLocked &&
      _isSubmitter &&
      (_stage == 'awaiting_start_review' ||
          (_stage == 'filling' &&
              _review['reviewRejected'] == true &&
              _review['presidentRejected'] != true));

  bool get _canSubmit =>
      _row.id > 0 && !_isLocked && _isSubmitter && _stage == 'awaiting_submit';

  bool get _canDelete => _row.id > 0 && _row.canDeleteBy(_me);

  bool _fillEnabled(bool? writable) {
    if (writable != null) return writable;
    return !_isContentFrozen && _canEditMarket;
  }

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Widget _readonlySelectedText(String value, {int maxLines = 6}) {
    final text = value.trim();
    final display = text.isEmpty ? '未填写' : text;
    final child = Align(
      alignment: Alignment.centerLeft,
      child: SelectableText(
        display,
        maxLines: maxLines,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          fontWeight: text.isEmpty ? FontWeight.w500 : FontWeight.w600,
          color: text.isEmpty ? ProposalPalette.text3 : ProposalPalette.text,
        ),
      ),
    );
    if (text.isEmpty) return child;
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 350),
      child: child,
    );
  }

  bool _reviewEnabled(String? section) {
    if (section == null || !_isReviewing || _me <= 0) return false;
    if (section.startsWith('technologyItem:')) return _isMarketOwner2;
    if (section.startsWith('financeItem:')) {
      return !_row.techRevisionOpen && _isOwner('financeOwner2');
    }
    if (section.startsWith('contractItem:')) {
      return !_row.techRevisionOpen && _isOwner('financeOwner2');
    }
    return false;
  }

  bool get _financeInterfaceNeedsReview =>
      _row.isTechReviewing &&
      !proposalIntakeFinanceInterfacesUnchanged(form: _form, review: _review);

  bool _moduleReviewEnabled(String keyName) {
    if (!_isReviewing || _me <= 0) return false;
    if (_row.techRevisionOpen) {
      return switch (keyName) {
        'marketCompleted' => _isOwner('marketOwner1'),
        'technologyCompleted' => _isMarketOwner2,
        'financeInterfaceCompleted' =>
          _isOwner('financeOwner2') && _financeInterfaceNeedsReview,
        _ => false,
      };
    }
    return switch (keyName) {
      'marketCompleted' => _isOwner('marketOwner1'),
      'technologyCompleted' => _isMarketOwner2,
      'financeInterfaceCompleted' => _isOwner('financeOwner2'),
      'financeCompleted' => _isOwner('financeOwner1'),
      'purchaseContractCompleted' ||
      'salesContractCompleted' => _isOwner('financeOwner2'),
      _ => false,
    };
  }

  Map<String, dynamic> get _form => _row.form;
  Map<String, dynamic> get _review => _row.review;

  int _reviewInt(String key) {
    final raw = _review[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  String _personNameById(int userId) {
    if (userId <= 0) return '';
    return widget.people
            .where((person) => person.userId == userId)
            .map((person) => person.name)
            .where((name) => name.trim().isNotEmpty)
            .firstOrNull ??
        '';
  }

  String _rejectSectionRole(String section) {
    return switch (section) {
      'market' || 'marketCompleted' => '市场部负责人一',
      'technology' || 'technologyCompleted' => '市场部负责人二',
      'financeInterface' || 'financeInterfaceCompleted' => '财务部负责人二',
      'finance' || 'financeCompleted' => '财务部负责人一',
      'purchaseContract' ||
      'purchaseContractCompleted' ||
      'salesContract' ||
      'salesContractCompleted' => '财务部负责人二',
      _ => '对应审核人',
    };
  }

  /// 板块驳回后的修改只动被驳板块，不要把整单打回「填写中」以免其他复核被清掉。
  String get _statusAfterEdit {
    if (_row.status == 'done' || _row.status == 'pending_president') {
      return _row.status;
    }
    if (_isContentFrozen) return _row.status;
    final moduleRevise =
        _review['reviewRejected'] == true &&
        _review['presidentRejected'] != true;
    if (moduleRevise) return _row.status;
    return 'filling';
  }

  void _set(
    String key,
    Object? value, {
    String? resetReview,
    bool rebuild = true,
  }) {
    final form = Map<String, dynamic>.from(_form)..[key] = value;
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _dirty = true;
    _row = _row.copyWith(
      title: key == 'proposalName' ? '$value'.trim() : _row.title,
      status: _statusAfterEdit,
      form: form,
      review: review,
    );
    if (rebuild && mounted) setState(() {});
    widget.onChanged(_row);
  }

  void _setContractMode(String prefix, String? mode) {
    final form = Map<String, dynamic>.from(_form)
      ..addAll(proposalIntakeResetContractFields(prefix))
      ..['${prefix}Mode'] = mode ?? '';
    final snapshots = form[kProposalContractSnapshotKey] is Map
        ? Map<String, dynamic>.from(form[kProposalContractSnapshotKey] as Map)
        : <String, dynamic>{};
    snapshots.remove(prefix);
    form[kProposalContractSnapshotKey] = snapshots;
    final edits = form[kProposalContractEditsKey] is Map
        ? Map<String, dynamic>.from(form[kProposalContractEditsKey] as Map)
        : <String, dynamic>{};
    for (final key in proposalIntakeContractFillKeys(prefix)) {
      edits.remove(key);
    }
    form[kProposalContractEditsKey] = edits;
    setState(() {
      _dirty = true;
      _fieldEpoch++;
      _row = _row.copyWith(
        form: form,
        review: proposalIntakeClearContractReview(_review, prefix: prefix),
        status: _statusAfterEdit,
      );
    });
    widget.onChanged(_row);
  }

  String _reviewSectionForFlag(String key) => switch (key) {
    'marketCompleted' => 'market',
    'technologyCompleted' => 'technology',
    'financeInterfaceCompleted' => 'financeInterface',
    'financeCompleted' => 'finance',
    'purchaseContractCompleted' => 'purchaseContract',
    'salesContractCompleted' => 'salesContract',
    _ => key,
  };

  Future<bool> _confirmFinal({
    required String title,
    required String message,
    String confirmLabel = '确认',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ProposalPalette.purpleDeep,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _setReview(String key, bool value) async {
    if (!value) return;
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return;
    }
    final confirmed = await _confirmFinal(
      title: '确认本板块复核完成',
      message: '确认后该板块复核完成。这是本板块的最终确认，提交后不可直接撤回。',
      confirmLabel: '确认完成',
    );
    if (!confirmed) return;
    try {
      final saved = await widget.service.saveReview(
        _row.id,
        _reviewSectionForFlag(key),
        true,
        _row.version,
      );
      if (!mounted) return;
      setState(() => _row = saved);
      widget.onChanged(saved);
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _rejectReview(String key) async {
    final comment = await showProposalRejectDialog(
      context: context,
      title: '驳回本板块',
      hint: '请填写驳回意见。可直接整板块驳回，不必先逐条点完复核。仅作废本板块，其他板块复核仍保留。',
    );
    if (!mounted) return;
    if (comment == null) return;
    if (comment.isEmpty) {
      widget.onError('驳回时请填写意见');
      return;
    }
    try {
      final saved = await widget.service.saveReview(
        _row.id,
        _reviewSectionForFlag(key),
        false,
        _row.version,
        comment: comment,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _row = saved);
        widget.onChanged(saved);
      });
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  /// 逐条复核：section 形如 financeItem:margin、technologyItem:rdAmount、
  /// contractItem:purchase.Name。
  Future<void> _setItemReview(String section, bool value) async {
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return;
    }
    try {
      final saved = await widget.service.saveReview(
        _row.id,
        section,
        value,
        _row.version,
      );
      if (!mounted) return;
      setState(() => _row = saved);
      widget.onChanged(saved);
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  (String, String) _reviewItemLocation(String section) {
    final index = section.indexOf(':');
    final itemKey = section.substring(index + 1);
    return switch (section.substring(0, index)) {
      'technologyItem' => ('technologyItems', itemKey),
      'contractItem' => ('contractItems', itemKey),
      _ => ('financeItems', itemKey),
    };
  }

  bool _itemReviewed(String section) {
    final (mapKey, itemKey) = _reviewItemLocation(section);
    final items = _review[mapKey];
    return items is Map && items[itemKey] == true;
  }

  int _reviewedCount(String prefix, List<String> keys) =>
      keys.where((key) => _itemReviewed('$prefix:$key')).length;

  bool _itemsReviewed(String prefix, List<String> keys) =>
      _reviewedCount(prefix, keys) == keys.length;

  bool get _allTechnologyItemsReviewed =>
      _itemsReviewed('technologyItem', _technologyReviewFields);

  List<String> _contractItemKeys(String prefix) =>
      _contractReviewFields.map((field) => '$prefix.$field').toList();

  List<String> _pendingContractReviewLabels(String prefix) =>
      _contractReviewFields
          .where((field) => !_itemReviewed('contractItem:$prefix.$field'))
          .map((field) => _contractReviewFieldLabels[field] ?? field)
          .toList();

  Widget? _rowReviewToggle(String? section, String pendingLabel) {
    if (section == null) return null;
    final reviewed = _itemReviewed(section);
    return ProposalReviewToggle(
      reviewed: reviewed,
      pendingLabel: pendingLabel,
      onPressed: _reviewEnabled(section)
          ? () => unawaited(_setItemReview(section, !reviewed))
          : null,
    );
  }

  Set<String> _setOf(String key) {
    final value = _form[key];
    return value is List ? value.map((item) => '$item').toSet() : <String>{};
  }

  void _toggleList(
    String key,
    String value, {
    String? resetReview,
    bool single = false,
  }) {
    if (single) {
      final current = _setOf(key);
      final next = (current.length == 1 && current.contains(value))
          ? <String>[]
          : <String>[value];
      _set(key, next, resetReview: resetReview);
      return;
    }
    final values = _setOf(key);
    if (key == 'costItems') {
      final aliases = proposalProjectCostNamesOf(value);
      final selected = aliases.any(values.contains);
      values.removeAll(aliases);
      if (!selected) values.add(proposalProjectCostDisplayName(value));
      final next = values.toList();
      _setCostSelection(
        namesKey: 'costItems',
        codesKey: 'costItemCodes',
        amountsKey: 'costItemAmounts',
        totalKey: 'projectCost',
        names: next,
        catalog: widget.options.costItemOptions,
        settleTermsKey: 'costItemSettleTerms',
        resetReview: resetReview,
      );
      return;
    }
    values.contains(value) ? values.remove(value) : values.add(value);
    final next = values.toList();
    if (key == 'businessCostItems') {
      if (!_canEditBusinessCost) return;
      _setCostSelection(
        namesKey: 'businessCostItems',
        codesKey: 'businessCostItemCodes',
        amountsKey: 'businessCostItemAmounts',
        totalKey: 'businessCost',
        names: next,
        catalog: widget.options.businessCostItemOptions,
        settleTermsKey: 'businessCostItemSettleTerms',
        resetReview: resetReview,
      );
      return;
    }
    if (key == 'operatingCostItems') {
      _setCostSelection(
        namesKey: 'operatingCostItems',
        codesKey: 'operatingCostItemCodes',
        amountsKey: 'operatingCostItemAmounts',
        totalKey: 'operatingCost',
        names: next,
        catalog: const [],
        resetReview: resetReview,
      );
      return;
    }
    if (key == 'taxCostItems') {
      _setCostSelection(
        namesKey: 'taxCostItems',
        codesKey: 'taxCostItemCodes',
        amountsKey: 'taxCostItemAmounts',
        totalKey: 'taxCost',
        names: next,
        catalog: const [],
        resetReview: resetReview,
      );
      return;
    }
    _set(key, next, resetReview: resetReview);
  }

  void _setCostSelection({
    required String namesKey,
    required String codesKey,
    required String amountsKey,
    required String totalKey,
    required List<String> names,
    required List<ProposalCostItemOption> catalog,
    String settleTermsKey = '',
    String? resetReview,
  }) {
    final form = proposalSyncCostSelection(
      form: _form,
      names: names,
      catalog: catalog,
      namesKey: namesKey,
      codesKey: codesKey,
      amountsKey: amountsKey,
      totalKey: totalKey,
      settleTermsKey: settleTermsKey,
    );
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _dirty = true;
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    widget.onChanged(_row);
  }

  void _setCostAmount({
    required String amountsKey,
    required String totalKey,
    required String id,
    required double? value,
    String? resetReview,
  }) {
    if (amountsKey == 'businessCostItemAmounts' && !_canEditBusinessCost) {
      return;
    }
    final amounts = proposalCostAmountMap(_form[amountsKey]);
    if (value == null) {
      amounts.remove(id);
    } else {
      amounts[id] = value;
    }
    final form = Map<String, dynamic>.from(_form)
      ..[amountsKey] = {
        for (final entry in amounts.entries) entry.key: entry.value,
      }
      ..[totalKey] = proposalCostAmountTotal(amounts);
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _dirty = true;
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    widget.onChanged(_row);
  }

  void _setCostSettleTerms({
    required String settleTermsKey,
    required String id,
    required ProposalFinanceSettleTerms terms,
  }) {
    if (settleTermsKey == 'businessCostItemSettleTerms' &&
        !_canEditBusinessCost) {
      return;
    }
    final map = proposalCostSettleTermsMap(_form[settleTermsKey]);
    map[id] = terms;
    final form = Map<String, dynamic>.from(_form)
      ..[settleTermsKey] = {
        for (final entry in map.entries) entry.key: entry.value.toJson(),
      };
    final review = Map<String, dynamic>.from(_review)
      ..['financeCompleted'] = false;
    _dirty = true;
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    widget.onChanged(_row);
  }

  String _text(String key) => '${_form[key] ?? ''}';
  double _number(String key) => _form[key] is num
      ? (_form[key] as num).toDouble()
      : double.tryParse(_text(key)) ?? 0;

  CatalogRef? _formRef(String key) => proposalIntakeFormRef(_form, key);

  void _setMany(
    Map<String, Object?> values, {
    String? resetReview,
    bool rebuild = true,
  }) {
    final form = Map<String, dynamic>.from(_form)..addAll(values);
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _dirty = true;
    _row = _row.copyWith(
      title: values.containsKey('proposalName')
          ? '${values['proposalName'] ?? ''}'.trim()
          : _row.title,
      status: _statusAfterEdit,
      form: form,
      review: review,
    );
    if (rebuild && mounted) setState(() {});
    widget.onChanged(_row);
  }

  Future<void> _loadMarketCatalog() async {
    final results = await Future.wait([
      _catalog.fetchProductCategoryL1(),
      _catalog.fetchProjects(),
      _catalog.fetchSyncSources(),
    ]);
    if (!mounted) return;
    setState(() {
      _sectorCatalog = results[0];
      _projectCatalog = results[1];
      _syncSourceCatalog = results[2];
    });
    final sector = _formRef('sectorRef');
    if (sector != null && sector.isNotEmpty) {
      await _loadProductCatalog(sector);
    }
  }

  Future<void> _loadProductCatalog(CatalogRef? sector) async {
    final seq = ++_productCatalogSeq;
    if (sector == null || sector.isEmpty) {
      if (mounted) setState(() => _productCatalog = const []);
      return;
    }
    final rows = await _catalog.fetchProductCategoryL2(
      parentCode: sector.code,
      parentId: sector.id,
    );
    if (!mounted || seq != _productCatalogSeq) return;
    setState(() => _productCatalog = rows);
  }

  int _projectSearchSeq = 0;

  Future<void> _searchProjects(String keyword) async {
    final seq = ++_projectSearchSeq;
    final rows = await _catalog.fetchProjects(keyword: keyword);
    if (!mounted || seq != _projectSearchSeq) return;
    setState(() => _projectCatalog = rows);
  }

  Future<void> _searchAssetProducts(
    String rowId,
    String syncSource,
    String keyword,
  ) async {
    final source = syncSource.trim();
    final query = keyword.trim();
    final seq = (_assetProductSearchSeq[rowId] ?? 0) + 1;
    _assetProductSearchSeq[rowId] = seq;
    if (source.isEmpty || query.isEmpty) {
      if (mounted) {
        setState(() {
          _assetProductHits[rowId] = const [];
          _assetProductSearching.remove(rowId);
        });
      }
      return;
    }
    _assetProductSearching.add(rowId);
    if (mounted) setState(() {});
    final rows = await _catalog.fetchChannelProducts(
      syncSource: source,
      keyword: query,
    );
    if (!mounted || _assetProductSearchSeq[rowId] != seq) return;
    setState(() {
      _assetProductSearching.remove(rowId);
      _assetProductHits[rowId] = rows;
    });
  }

  String _settleCacheKey(String syncSource, String productSource) =>
      '${syncSource.trim()}|${productSource.trim().toUpperCase()}';

  Future<_SettleCatalogBundle> _ensureSettleBundle({
    required String syncSource,
    required String productSource,
  }) async {
    final source = syncSource.trim();
    final side = productSource.trim().toUpperCase();
    final key = _settleCacheKey(source, side);
    final cached = _settleBundles[key];
    if (cached != null) return cached;
    if (source.isEmpty || _settleLoading.contains(key)) {
      return cached ?? const _SettleCatalogBundle();
    }
    _settleLoading.add(key);
    try {
      final results = await Future.wait([
        _catalog.fetchChannels(syncSource: source),
        _catalog.fetchBillTypes(syncSource: source, productSource: side),
        _catalog.fetchSettleMethods(syncSource: source, productSource: side),
        _catalog.fetchFormulas(syncSource: source, productSource: side),
      ]);
      final bundle = _SettleCatalogBundle(
        channels: results[0],
        billTypes: results[1],
        settleMethods: results[2],
        formulas: results[3],
      );
      _settleBundles[key] = bundle;
      return bundle;
    } catch (_) {
      return cached ?? const _SettleCatalogBundle();
    } finally {
      _settleLoading.remove(key);
      if (mounted) setState(() {});
    }
  }

  void _prefetchSettle(String syncSource, String productSource) {
    if (syncSource.trim().isEmpty) return;
    unawaited(
      _ensureSettleBundle(
        syncSource: syncSource,
        productSource: productSource,
      ),
    );
  }

  List<CatalogRef> _sectorOptions() {
    if (_sectorCatalog.isNotEmpty) return _sectorCatalog;
    return [
      for (final item in widget.options.sectors) CatalogRef.fromName(item),
    ];
  }

  List<CatalogRef> _productOptions() {
    if (_productCatalog.isNotEmpty) return _productCatalog;
    return [
      for (final item in widget.options.products) CatalogRef.fromName(item.value),
    ];
  }

  List<CatalogRef> _projectOptions() {
    if (_projectCatalog.isNotEmpty) return _projectCatalog;
    return [
      for (final item in widget.options.products)
        if (item.value == _text('product'))
          for (final child in item.children) CatalogRef.fromName(child),
    ];
  }

  CatalogRef? _selectedCatalog(
    CatalogRef? current,
    List<CatalogRef> options,
  ) {
    if (current == null || current.isEmpty) return null;
    for (final item in options) {
      if (item == current) return item;
    }
    return current;
  }

  List<CatalogRef> _withCurrent(List<CatalogRef> options, CatalogRef? current) {
    if (current == null || current.isEmpty) return options;
    if (options.any((item) => item == current)) return options;
    return [current, ...options];
  }

  String get _rating {
    final raw = _form['salesScale'];
    if (raw == null || '$raw'.trim().isEmpty) return '—';
    return widget.options.ratingFor(_number('salesScale'));
  }

  /// 金额统一按万元展示，并按千分位分组。
  String _money(double value) {
    if (value == 0) return '0 万元';
    final fixed = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final decimals = parts.length > 1 ? '.${parts[1]}' : '';
    return '$buffer$decimals 万元';
  }

  Future<void> _addOption(
    String key,
    String title, {
    String? resetReview,
    bool single = false,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: proposalInputDecoration(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    _toggleList(key, value, resetReview: resetReview, single: single);
  }

  Future<void> _addDropdownValue(
    String key,
    String title, {
    String? resetReview,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: proposalInputDecoration(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    _set(key, value, resetReview: resetReview);
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      ),
    );
  }

  void _jumpToSection(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null || !_scroll.hasClients) return;
    final target = targetContext.findRenderObject();
    final viewport = _scroll.position.context.notificationContext
        ?.findRenderObject();
    if (target is! RenderBox ||
        viewport is! RenderBox ||
        !target.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final destination =
        (_scroll.offset +
                target.localToGlobal(Offset.zero).dy -
                viewport.localToGlobal(Offset.zero).dy)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    unawaited(
      _scroll.animateTo(
        destination,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      ),
    );
  }

  List<String> _validate() {
    final issues = <String>[];
    if (_row.title.trim().isEmpty) issues.add('产品提案名称不能为空');
    if (_number('salesScale') < widget.options.minimumScale) {
      issues.add('销售规模低于 ${_money(widget.options.minimumScale)}');
    }
    if (_number('margin') < widget.options.minimumMargin) {
      issues.add('毛利率低于 ${widget.options.minimumMargin}%');
    }
    final interfaceValues = _form['financeInterfaces'] is Map
        ? Map<String, dynamic>.from(_form['financeInterfaces'])
        : <String, dynamic>{};
    final missing = widget.options.financeInterfaces
        .where((item) => item.required && interfaceValues[item.key] != true)
        .map((item) => item.label)
        .toList();
    if (missing.isNotEmpty) issues.add('财务技术接口缺少：${missing.join('、')}');
    if (_text('hasRdCost') == '是' && _number('rdAmount') <= 0) {
      issues.add('已选择涉及研发费用，金额必须大于 0');
    }
    if (_text('purchaseMode') == '未签署合同' &&
        _text('purchaseFileName').trim().isEmpty) {
      issues.add('请上传未签署的采购合同文件');
    }
    if (_text('salesMode') == '未签署合同' &&
        _text('salesFileName').trim().isEmpty) {
      issues.add('请上传未签署的销售合同文件');
    }
    if (widget.options.presidentUserIds.isEmpty && _ownerId('president') <= 0) {
      issues.add('请在管理后台「提案录入选项」中配置最终确认人');
    }
    for (final name in missingProposalReviewAssignees(_form)) {
      issues.add('请指定$name');
    }
    issues.addAll(proposalIntakeLaunchFinanceIssues(_form));
    issues.addAll(proposalIntakeSkuSettleIssues(_form));
    for (final entry in const {
      'marketCompleted': '市场部',
      'technologyCompleted': '科技部',
      'financeInterfaceCompleted': '财务技术接口',
      'financeCompleted': '财务部',
      'purchaseContractCompleted': '采购合同',
      'salesContractCompleted': '销售合同',
    }.entries) {
      if (_review[entry.key] != true) issues.add('${entry.value}尚未完成复核');
    }
    return issues;
  }

  Future<void> _submit() async {
    if (_dirty) {
      widget.onError('请先保存最新修改，再完成各环节复核并提交');
      return;
    }
    final issues = _validate();
    setState(() => _issues = issues);
    if (issues.isNotEmpty) {
      _scrollToTop();
      return;
    }
    final confirmed = await _confirmFinal(
      title: '确认通知最终人',
      message: '确认后提案将交给最终人，内容锁定，不可再改。这是通知最终人的最终确认。',
      confirmLabel: '确认通知',
    );
    if (!confirmed) return;
    try {
      final submitted = await widget.service.submit(_row.id);
      if (!mounted) return;
      setState(() => _row = submitted);
      widget.onSubmit(submitted);
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _handoff(String action) async {
    if (_dirty) {
      widget.onError('请先保存最新修改，再通知下一位');
      return;
    }
    final missing = missingProposalReviewAssignees(
      _form,
      includeTech: action == 'notify_tech',
    );
    if (missing.isNotEmpty) {
      final issues = [for (final name in missing) '请指定$name'];
      setState(() => _issues = issues);
      _scrollToTop();
      widget.onError('请先指定：${missing.join('、')}');
      return;
    }
    final (title, message, confirmLabel) = switch (action) {
      'notify_tech' => ('确认通知科技负责人', '确认后科技负责人将填写科技部内容。这是本步骤的最终确认。', '确认通知'),
      'notify_market2' => (
        '确认提交复核',
        '确认后将通知全部复核人，提案内容锁定。这是科技填写完成的最终确认。',
        '确认提交',
      ),
      'start_review' => (
        '确认重新提交复核',
        '确认后将通知${_rejectSectionRole('${_review['reviewRejectSection'] ?? ''}'.trim())}重新复核本板块，其他已通过板块保持不变。这是本步骤的最终确认。',
        '确认提交',
      ),
      'start_tech_revision' => (
        '确认发起科技变更',
        '确认后可修改科技部内容。市场将按先科技后市场重新打勾。财务接口没变则不重审财务。',
        '确认发起',
      ),
      'confirm_tech_revision' => (
        '确认提交本轮科技变更',
        '确认后由市场部负责人二复核科技，再由市场部负责人一复核市场。',
        '确认提交',
      ),
      _ => ('', '', ''),
    };
    if (title.isNotEmpty) {
      final confirmed = await _confirmFinal(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      );
      if (!confirmed) return;
    }
    try {
      final next = await widget.service.handoff(_row.id, action, _row.version);
      if (!mounted) return;
      setState(() => _row = next);
      widget.onSaved(next);
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _decidePresident({required bool approved}) async {
    var comment = '${_review['presidentComment'] ?? ''}'.trim();
    if (!approved) {
      final typed = await showProposalRejectDialog(
        context: context,
        title: '驳回提案',
        hint: '请填写驳回意见。确认后提案退回提交人，全部流程重新开始。',
      );
      if (!mounted) return;
      if (typed == null) return;
      if (typed.isEmpty) {
        widget.onError('驳回时请填写意见');
        return;
      }
      comment = typed;
    } else {
      final confirmed = await _confirmFinal(
        title: '确认通过提案',
        message: '确认后提案完成。这是最终人的最终确认，通过后不可再改。',
        confirmLabel: '确认通过',
      );
      if (!confirmed) return;
    }
    try {
      final next = await widget.service.decidePresident(
        id: _row.id,
        approved: approved,
        version: _row.version,
        comment: comment,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _row = next);
        widget.onSubmit(next);
        widget.onAfterFinalDecision?.call(next.id);
      });
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _saveDraft() async {
    if (!proposalIntakeHasMeaningfulContent(_row)) {
      widget.onError('请先填写提案信息后再保存草稿');
      return;
    }
    try {
      final confirmed = _row.copyWith(
        form: proposalIntakeConfirmContractEdits(_form),
      );
      final saved = confirmed.id <= 0
          ? await widget.service.create(
              title: confirmed.title,
              form: confirmed.form,
              review: confirmed.review,
            )
          : await widget.service.save(confirmed);
      if (!mounted) return;
      setState(() {
        _row = saved;
        _dirty = false;
      });
      widget.onSaved(saved);
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _forwardToChat() async {
    if (_row.id <= 0 || _forwarding) return;
    setState(() => _forwarding = true);
    try {
      final share = ApprovalChatShare.fromProposalIntake(
        id: _row.id,
        title: _headerTitle,
        status: _row.status,
        code: _row.code,
        submitterName: _row.initiatorDisplayName(widget.people),
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

  Future<void> _confirmDeleteProposal() async {
    if (!_canDelete || _deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提案'),
        content: Text('确定删除「${_row.code}」？最终审核开始前可以删除，删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ProposalPalette.coral,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await widget.service.delete(_row.id);
      if (!mounted) return;
      showProposalCenterToast(context, '已删除');
      widget.onDeleted?.call();
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '删除失败'));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final compact = constraints.maxWidth < 620;
          return ColoredBox(
            color: ProposalPalette.page,
            child: Column(
              children: [
                _topbar(compact: compact),
                _sectionNav(compact: compact),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFF8F6FA), Color(0xFFF4F1F7)],
                      ),
                    ),
                    child: CustomScrollView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      cacheExtent: 480,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 28 : 14,
                            wide ? 22 : 14,
                            wide ? 28 : 14,
                            _canDecidePresident ? 24 : 80,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_issues.isNotEmpty) _issueBanner(),
                                if (_review['presidentRejected'] == true ||
                                    _review['reviewRejected'] == true)
                                  _rejectBanner(),
                                if (_stage == 'awaiting_submit')
                                  _awaitingSubmitBanner(),
                                _overview(),
                                _marketSection(wide),
                                _techSection(wide),
                                _financeSection(wide),
                                _flowSection(wide),
                                if (widget.enableComments && _row.id > 0)
                                  _commentsSection(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_canDecidePresident)
                  ProposalPresidentDecisionBar(
                    onApprove: () =>
                        unawaited(_decidePresident(approved: true)),
                    onReject: () =>
                        unawaited(_decidePresident(approved: false)),
                  ),
                if (widget.onNext != null)
                  ProposalNextPendingFooter(
                    totalCount: widget.nextCount,
                    loading: widget.nextBusy,
                    onPressed: widget.nextBusy ? null : widget.onNext,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String get _headerTitle {
    final name = _row.title.trim();
    if (name.isNotEmpty) return name;
    final fromForm = _text('proposalName').trim();
    if (fromForm.isNotEmpty) return fromForm;
    return proposalIntakeUntitledTitle(_row.kind);
  }

  Widget _topbar({required bool compact}) {
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!compact) ...[
            ProposalStatusChip(
              label: _row.id <= 0 || _row.code.isEmpty ? '未保存' : _row.code,
            ),
            const SizedBox(width: 7),
          ],
          ProposalStatusChip(
            label: proposalIntakeStatusLabel(_row.status),
            kind: _row.status == 'done'
                ? ProposalChipKind.ok
                : ProposalChipKind.purple,
          ),
          if (_row.techRevisionOpen) ...[
            const SizedBox(width: 7),
            const ProposalStatusChip(
              label: '科技变更中',
              kind: ProposalChipKind.purple,
            ),
          ],
          const SizedBox(width: 7),
          ProposalStatusChip(
            label: '评级 $_rating',
            kind: ProposalChipKind.purple,
          ),
        ],
      ),
    );

    if (compact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
        decoration: const BoxDecoration(
          color: Color(0xFFFBFAFD),
          border: Border(bottom: BorderSide(color: Color(0xFFEAE3F0))),
          boxShadow: [BoxShadow(color: Color(0x0E4E3A6C), blurRadius: 14)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.onClose != null) _closeButton(),
                Expanded(
                  child: Text(
                    _headerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProposalPalette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const ProposalIntakeProcessHelpButton(compact: true),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: widget.onClose != null ? 8 : 4),
              child: chips,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: widget.onClose != null ? 8 : 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _topActionButtons(compact: true),
              ),
            ),
          ],
        ),
      );
    }

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in _topActionButtons(compact: false).indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          child,
        ],
      ],
    );

    return Container(
      height: 56,
      padding: EdgeInsets.fromLTRB(widget.onClose != null ? 8 : 18, 0, 18, 0),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFAFD),
        border: Border(bottom: BorderSide(color: Color(0xFFEAE3F0))),
        boxShadow: [BoxShadow(color: Color(0x0E4E3A6C), blurRadius: 14)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.onClose != null) _closeButton(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              _headerTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ProposalPalette.text,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: chips),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 0,
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: actions,
            ),
          ),
          const ProposalIntakeProcessHelpButton(),
        ],
      ),
    );
  }

  Widget _closeButton() {
    return IconButton(
      tooltip: '关闭',
      onPressed: widget.onClose,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: const Icon(Icons.close_rounded, size: 22),
    );
  }

  Widget _sectionNav({required bool compact}) {
    const navH = 32.0;
    Widget chip(String label, GlobalKey key) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton(
          onPressed: () => _jumpToSection(key),
          style: OutlinedButton.styleFrom(
            foregroundColor: ProposalPalette.purpleDeep,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFDDD1E8)),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
            minimumSize: const Size(0, navH),
            maximumSize: const Size(double.infinity, navH),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(label, style: const TextStyle(fontSize: 12, height: 1.1)),
        ),
      );
    }

    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFAFD),
        border: Border(bottom: BorderSide(color: Color(0xFFEAE3F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            height: navH,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_outlined,
                  size: 15,
                  color: ProposalPalette.purple,
                ),
                SizedBox(width: 6),
                Text(
                  '定位',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.1,
                    color: ProposalPalette.text3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: navH,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  chip('市场部', _marketKey),
                  chip('科技部', _techKey),
                  chip('财务部', _financeKey),
                  chip('四流', _flowKey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIconAction({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    bool filled = false,
    bool loading = false,
    Color? foreground,
    Color? background,
    Color? border,
    double dimension = 36,
  }) {
    final iconWidget = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled
                  ? Colors.white
                  : (foreground ?? ProposalPalette.purple),
            ),
          )
        : Icon(icon, size: 18);
    final size = Size(dimension, dimension);
    final button = filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: background ?? ProposalPalette.purple,
              foregroundColor: Colors.white,
              minimumSize: size,
              maximumSize: size,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: iconWidget,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: foreground ?? ProposalPalette.purpleDeep,
              side: BorderSide(color: border ?? const Color(0xFFDDD1E8)),
              minimumSize: size,
              maximumSize: size,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: iconWidget,
          );
    return Tooltip(message: tooltip, child: button);
  }

  Widget _topLabeledAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool compact,
    bool filled = true,
    bool loading = false,
    Color? foreground,
    Color? border,
  }) {
    final height = compact ? 44.0 : 40.0;
    final iconWidget = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled
                  ? Colors.white
                  : (foreground ?? ProposalPalette.purpleDeep),
            ),
          )
        : Icon(icon, size: compact ? 18 : 17);
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: compact ? 14 : 13,
        fontWeight: FontWeight.w700,
      ),
    );
    final button = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: labelWidget,
            style: FilledButton.styleFrom(
              backgroundColor: ProposalPalette.purple,
              foregroundColor: Colors.white,
              minimumSize: Size(0, height),
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: labelWidget,
            style: OutlinedButton.styleFrom(
              foregroundColor: foreground ?? ProposalPalette.purpleDeep,
              side: BorderSide(color: border ?? const Color(0xFFDDD1E8)),
              minimumSize: Size(0, height),
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          );
    return Tooltip(message: label, child: button);
  }

  List<Widget> _topActionButtons({required bool compact}) {
    final dim = compact ? 32.0 : 36.0;
    Widget btn({
      required IconData icon,
      required String tooltip,
      VoidCallback? onPressed,
      bool filled = false,
      bool loading = false,
      Color? foreground,
      Color? background,
      Color? border,
    }) {
      return _topIconAction(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        filled: filled,
        loading: loading,
        foreground: foreground,
        background: background,
        border: border,
        dimension: dim,
      );
    }

    final actions = <Widget>[
      _topLabeledAction(
        icon: Icons.save_outlined,
        label: '保存',
        filled: false,
        compact: compact,
        onPressed: widget.saving || !_canSave
            ? null
            : () => unawaited(_saveDraft()),
      ),
      _topLabeledAction(
        icon: Icons.forward_outlined,
        label: _forwarding ? '转发中…' : '转发',
        filled: false,
        compact: compact,
        loading: _forwarding,
        onPressed: _forwarding || _row.id <= 0
            ? null
            : () => unawaited(_forwardToChat()),
      ),
    ];
    if (_canNotifyTech) {
      actions.add(
        btn(
          icon: Icons.science_outlined,
          tooltip: '通知科技负责人',
          filled: true,
          onPressed: () => unawaited(_handoff('notify_tech')),
        ),
      );
    }
    if (_canNotifyMarket2) {
      actions.add(
        btn(
          icon: Icons.assignment_turned_in_outlined,
          tooltip: '确认并提交复核',
          filled: true,
          onPressed: () => unawaited(_handoff('notify_market2')),
        ),
      );
    }
    if (_canStartTechRevision) {
      actions.add(
        _topLabeledAction(
          icon: Icons.science_outlined,
          label: '发起科技变更',
          onPressed: () => unawaited(_handoff('start_tech_revision')),
          compact: compact,
        ),
      );
    }
    if (_canConfirmTechRevision) {
      actions.add(
        _topLabeledAction(
          icon: Icons.assignment_turned_in_outlined,
          label: '确认本轮科技变更',
          onPressed: () => unawaited(_handoff('confirm_tech_revision')),
          compact: compact,
        ),
      );
    }
    if (_canStartReview) {
      actions.add(
        btn(
          icon: Icons.assignment_turned_in_outlined,
          tooltip: '重新提交并通知审核人',
          filled: true,
          onPressed: () => unawaited(_handoff('start_review')),
        ),
      );
    }
    if (_canSubmit) {
      actions.add(
        btn(
          icon: Icons.send_outlined,
          tooltip: '通知最终人',
          filled: true,
          background: ProposalPalette.purpleDeep,
          onPressed: _submit,
        ),
      );
    }
    if (_canDecidePresident && !compact) {
      actions
        ..add(
          _topLabeledAction(
            icon: Icons.check_rounded,
            label: '确认通过',
            onPressed: () => unawaited(_decidePresident(approved: true)),
            compact: compact,
          ),
        )
        ..add(
          _topLabeledAction(
            icon: Icons.close_rounded,
            label: '驳回',
            onPressed: () => unawaited(_decidePresident(approved: false)),
            compact: compact,
            filled: false,
            foreground: ProposalPalette.coral,
            border: const Color(0xFFE7C2B0),
          ),
        );
    }
    if (_canDelete) {
      actions.add(
        btn(
          icon: Icons.delete_outline,
          tooltip: _deleting ? '删除中…' : '删除',
          loading: _deleting,
          foreground: ProposalPalette.coral,
          border: const Color(0xFFE7C2B0),
          onPressed: _deleting
              ? null
              : () => unawaited(_confirmDeleteProposal()),
        ),
      );
    }
    return actions;
  }

  Widget _rejectBanner() {
    final president = _review['presidentRejected'] == true;
    final comment = president
        ? '${_review['presidentComment'] ?? ''}'.trim()
        : '${_review['reviewRejectComment'] ?? ''}'.trim();
    final section = '${_review['reviewRejectSection'] ?? ''}'.trim();
    final rejectorId = president
        ? _reviewInt('presidentRejectUserId')
        : _reviewInt('reviewRejectUserId');
    var rejector = _personNameById(rejectorId);
    if (rejector.isEmpty && president) {
      rejector = widget.options.presidentDisplayNames(widget.people);
    }
    if (rejector.isEmpty && !president) {
      rejector = _rejectSectionRole(section);
    }
    final role = president ? '最终人' : _rejectSectionRole(section);
    final who = rejector.isEmpty
        ? role
        : (president ? '最终人 $rejector' : '$role $rejector');
    final techRound = _row.isTechRevising || _row.isTechReviewing;
    final text = comment.isEmpty
        ? (president
              ? '$who 已驳回，请修改后重新通知科技负责人，全部流程重新开始。'
              : techRound
              ? '$who 已驳回本轮科技变更。请修改后点右上角「确认本轮科技变更」。'
              : '$who 已驳回本板块。填写人修改后请点右上角「重新提交并通知审核人」，将通知$role再次审核。其他板块复核仍保留。')
        : (president
              ? '$who 驳回意见：$comment。请修改后重新通知科技负责人，全部流程重新开始。'
              : techRound
              ? '$who 驳回意见：$comment。请修改后重新提交本轮科技变更。'
              : '$who 驳回意见：$comment。填写人修改后请点右上角「重新提交并通知审核人」，将通知$role再次审核。其他板块复核仍保留。');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ProposalPalette.coralSoft,
        border: Border.all(color: const Color(0xFFE7C2B0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: ProposalPalette.coral,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _awaitingSubmitBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ProposalPalette.greenSoft,
        border: Border.all(color: const Color(0xFFB9DDBE)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _canSubmit
            ? '单条复核和板块复核都已完成。请点击右上角「通知最终人」。提交前内容仍不可改，如需改请驳回。'
            : '各环节已复核完成。提交人请点击右上角「通知最终人」。提交前内容仍不可改，如需改请驳回。',
        style: const TextStyle(
          color: ProposalPalette.green,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _commentsSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: XfDetCommentsSection(
        service: XflowService(session: widget.session),
        businessType: 'PROPOSAL_INTAKE',
        businessId: _row.id,
        fallbackPeople: [
          for (final person in widget.people)
            ApprovalStakeholderPerson(
              id: person.userId,
              displayName: person.name,
            ),
        ],
      ),
    );
  }

  Widget _issueBanner() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ProposalPalette.coralSoft,
      border: Border.all(color: const Color(0xFFE7C2B0)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '规则校验未通过，禁止提交',
          style: TextStyle(
            color: ProposalPalette.coral,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final issue in _issues)
          Text(
            '• $issue',
            style: const TextStyle(color: ProposalPalette.coral, fontSize: 11),
          ),
      ],
    ),
  );

  Widget _overview() {
    final compact = MediaQuery.sizeOf(context).width < 620;
    return ProposalCard(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFBF7F0), Color(0xFFF5F0FA), Color(0xFFECE4F6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${proposalIntakeKindEyebrow(_row.kind)} · 新增',
            style: TextStyle(
              color: ProposalPalette.purple,
              fontSize: 10,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _row.title.isEmpty
                ? proposalIntakeUntitledTitle(_row.kind)
                : _row.title,
            style: TextStyle(
              color: ProposalPalette.text,
              fontSize: compact ? 20 : 25,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marketSection(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeyedSubtree(
        key: _marketKey,
        child: ProposalSectionTitle(
          title: '一、市场部内容',
          tag: 'Market',
          description: _canEditMarket
              ? (_isPurchase
                    ? '提交人填写；市场部负责人一复核市场整板块，采购合同由财务部负责人二复核。'
                    : '提交人填写；市场部负责人一复核市场整板块，采购/销售合同由财务部负责人二复核。')
              : '由提交人填写。当前账号不可编辑本板块。',
        ),
      ),
      _stepCard(
        '01',
        '基础信息',
        '提案身份与所属业务',
            _fieldGrid(wide, [
              _catalogDropdownField(
                '业务板块',
                current: _formRef('sectorRef') ??
                    CatalogRef.fromName(_text('sector')),
                options: _sectorOptions(),
                required: true,
                resetReview: 'marketCompleted',
                hint: _sectorCatalog.isEmpty ? '请选择业务板块' : '请选择资管一级分类',
                onSelected: (value) {
                  _setMany({
                    'sector': value?.name ?? '',
                    'sectorRef': catalogRefToJson(value),
                    'product': '',
                    'productRef': null,
                  }, resetReview: 'marketCompleted');
                  unawaited(_loadProductCatalog(value));
                },
              ),
          ProposalField(
            label: '提案编号',
            source: '系统自动生成',
            tone: ProposalFieldTone.auto,
            child: TextFormField(
              readOnly: true,
              initialValue: _row.code,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: proposalInputDecoration(
                readOnly: true,
                tone: ProposalFieldTone.auto,
              ),
            ),
          ),
          _personField(
            '市场部负责人二（科技审核）',
            'marketOwner2',
            positionIncludes: '市场部负责人二',
            required: true,
          ),
          _textField(
            '产品提案名称',
            'proposalName',
            required: true,
            resetReview: 'marketCompleted',
          ),
          _dropdownField(
            '提案类型',
            'proposalType',
            widget.options.proposalTypes,
            required: true,
            resetReview: 'marketCompleted',
          ),
        ]),
      ),
      _stepCard(
        '02',
        '产品、标签与人员',
        '选择产品后补充项目、供给和渠道',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldGrid(wide, [
              _catalogDropdownField(
                '产品（标签一）',
                current: _formRef('productRef') ??
                    CatalogRef.fromName(_text('product')),
                options: _productOptions(),
                resetReview: 'marketCompleted',
                enabled: (_formRef('sectorRef') ??
                            CatalogRef.fromName(_text('sector')))
                        .isNotEmpty ||
                    _productOptions().isNotEmpty,
                hint: (_formRef('sectorRef') ??
                            CatalogRef.fromName(_text('sector')))
                        .isEmpty
                    ? '请先选择业务板块'
                    : '请选择产品二级分类',
                onSelected: (value) => _setMany({
                  'product': value?.name ?? '',
                  'productRef': catalogRefToJson(value),
                }, resetReview: 'marketCompleted'),
              ),
              _catalogDropdownField(
                '项目名称（标签一二级）',
                current: _formRef('projectRef') ??
                    CatalogRef.fromName(_text('projectName')),
                options: _projectOptions(),
                resetReview: 'marketCompleted',
                searchable: true,
                remoteSearch: true,
                hint: '请选择或搜索项目',
                onQueryChanged: (query) => unawaited(_searchProjects(query)),
                onSelected: (value) => _setMany({
                  'projectName': value?.name ?? '',
                  'projectRef': catalogRefToJson(value),
                }, resetReview: 'marketCompleted'),
              ),
              _multiField(
                '供给（标签二）',
                'supplies',
                widget.options.supplies,
                '新增供给',
                resetReview: 'marketCompleted',
                single: true,
              ),
              _multiField(
                '渠道（标签三）',
                'channels',
                widget.options.channels,
                '新增渠道',
                resetReview: 'marketCompleted',
              ),
              _personField(
                '市场部负责人一（整板块复核）',
                'marketOwner1',
                positionIncludes: '市场部负责人一',
                required: true,
              ),
              _configuredPresidentsField(),
              _personField('运营', 'operator', positionIncludes: '运营'),
            ]),
            const SizedBox(height: 14),
            _skuDetailsBlock(wide),
          ],
        ),
      ),
      _contractCard('03', '采购合同', 'purchase', wide),
      if (!_isPurchase) _contractCard('04', '销售合同', 'sales', wide),
      _stepCard(
        _isPurchase ? '04' : '05',
        '政策与执行',
        _isPurchase
            ? '供货商政策、合作计划与风险点'
            : '合同政策、合作计划与盈利方式',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldGrid(wide, [
              _textField(
                '供货商政策',
                'supplierPolicy',
                maxLines: 3,
                source: '合同抓取 · 可修改',
                resetReview: 'marketCompleted',
              ),
              if (!_isPurchase)
                _textField(
                  '渠道政策',
                  'channelPolicy',
                  maxLines: 3,
                  source: '合同抓取 · 可修改',
                  resetReview: 'marketCompleted',
                ),
              if (_isPurchase)
                _textField(
                  'HUN 联系方式',
                  'hunContact',
                  source: '加密处理，仅责任一可见',
                  resetReview: 'marketCompleted',
                ),
              _textField(
                '提案执行计划',
                'executionPlan',
                maxLines: 4,
                resetReview: 'marketCompleted',
              ),
              _textField(
                '合作风险点',
                'riskPoints',
                maxLines: 4,
                resetReview: 'marketCompleted',
              ),
              if (!_isPurchase) ...[
                _multiField(
                  '盈利模式 · 需写明计算方式',
                  'profitModes',
                  widget.options.profitModes,
                  '新增盈利模式',
                  resetReview: 'marketCompleted',
                ),
                _textField(
                  '盈利计算说明',
                  'profitFormula',
                  maxLines: 3,
                  resetReview: 'marketCompleted',
                ),
              ],
            ]),
          ],
        ),
      ),
      _moduleReview(
        title: '市场部板块统一复核',
        description: proposalIntakeMarketReviewBlocked(_review)
            ? '请先完成科技部复核，再复核市场（先科技后市场）。'
            : '市场部负责人一确认提交人填写的全部业务内容',
        keyName: 'marketCompleted',
        buttonLabel: '整个板块复核通过',
        locked: proposalIntakeMarketReviewBlocked(_review),
      ),
    ],
  );

  void _appendTechnologyRecord() {
    if (!_canEditTech) return;
    final next = proposalIntakeAppendTechnologyRecord(_form);
    final review = Map<String, dynamic>.from(_review)
      ..['technologyCompleted'] = false;
    setState(() {
      _dirty = true;
      _row = _row.copyWith(
        form: next,
        review: review,
        status: _statusAfterEdit,
      );
    });
    widget.onChanged(_row);
  }

  void _renameTechnologyRecord(int index, String title) {
    final records = [
      for (final item
          in (_form['technologyRecords'] is List
              ? _form['technologyRecords'] as List
              : const []))
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    if (index < 0 || index >= records.length) return;
    records[index]['title'] = title.trim();
    _set('technologyRecords', records, resetReview: 'technologyCompleted');
  }

  List<Widget> _technologyRecordCards() {
    final records = proposalIntakeTechnologyRecords(_form);
    if (records.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      for (var i = 0; i < records.length; i++) ...[
        _technologySnapshotCard(
          title: records[i].title,
          subtitle: '累计对接记录 ${i + 1}',
          record: records[i],
          titleEditable: _canEditTech,
          onTitle: (value) => _renameTechnologyRecord(i, value),
        ),
        if (i != records.length - 1) const SizedBox(height: 8),
      ],
    ];
  }

  List<Widget> _technologyHistoryCards() {
    final history = proposalIntakeTechnologyHistory(_form);
    if (history.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '历史轮次（${history.length}）',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ProposalPalette.text,
          ),
        ),
        children: [
          for (final item in history.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _technologySnapshotCard(
                title: item.title.isEmpty ? '第 ${item.round} 轮' : item.title,
                subtitle: '已归档',
                record: item,
              ),
            ),
        ],
      ),
    ];
  }

  Widget _technologySnapshotCard({
    required String title,
    required String subtitle,
    required ProposalTechnologyRecord record,
    bool titleEditable = false,
    ValueChanged<String>? onTitle,
  }) {
    final summary = [
      if (record.platform.isNotEmpty) record.platform,
      if (record.capabilities.isNotEmpty) record.capabilities.join('、'),
      if (record.deliveryDate.isNotEmpty) '交付 ${record.deliveryDate}',
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4FA),
        border: Border.all(color: const Color(0xFFE2D8EC)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: ProposalPalette.text3),
          ),
          if (titleEditable)
            TextFormField(
              initialValue: title,
              onChanged: onTitle,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '对接记录标题',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            )
          else
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: ProposalPalette.text,
              ),
            ),
          if (summary.isNotEmpty)
            Text(
              summary,
              style: const TextStyle(
                fontSize: 12,
                color: ProposalPalette.text2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _techSection(bool wide) {
    final platform = widget.options.platforms
        .where((item) => item.value == _text('technologyPlatform'))
        .firstOrNull;
    final interfaces = _form['financeInterfaces'] is Map
        ? Map<String, dynamic>.from(_form['financeInterfaces'])
        : <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _techKey,
          child: ProposalSectionTitle(
            title: '二、科技部内容',
            tag: 'Tech',
            description: _canStartTechRevision
                ? '提案已通过。点右上角「发起科技变更」后，可覆盖当前字段或新增对接记录。'
                : _row.isTechRevising
                ? '本轮科技变更可覆盖当前字段，或新增一条对接记录。改完后提交，由市场部先科技后市场重新打勾。'
                : _canEditTech
                ? '请填写科技部内容；完成后由市场部负责人二逐条复核。'
                : _canEditMarket
                ? '请指定科技部负责人。技术字段由对方填写，市场部负责人二做逐条复核。'
                : '科技部负责人填写；市场部负责人二做逐条复核。',
          ),
        ),
        ProposalCard(
          child: Column(
            children: [
              _fieldGrid(wide, [
                _personField(
                  '科技部负责人（填写人）',
                  'technologyOwner',
                  positionIncludes: '科技部负责人',
                  required: true,
                ),
                _dropdownField(
                  'τ-标签一',
                  'technologyPlatform',
                  widget.options.platforms.map((item) => item.value).toList(),
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:technologyPlatform',
                  reviewLabel: _techReviewLabel,
                  addLabel: '新增标签一',
                ),
                _multiField(
                  'τ-标签二 · 与标签一联动',
                  'technologyCapabilities',
                  platform?.children ?? const [],
                  '新增能力',
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:technologyCapabilities',
                  reviewLabel: _techReviewLabel,
                ),
                _multiField(
                  '能力输出形式',
                  'outputForms',
                  widget.options.outputForms,
                  null,
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:outputForms',
                  reviewLabel: _techReviewLabel,
                ),
              ]),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF8FC),
                  border: Border.all(color: const Color(0xFFE2D8EC)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '财务技术接口 · 根据项目成本动态生成',
                      style: TextStyle(
                        color: ProposalPalette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_showSelectedAsText)
                      _readonlySelectedText(
                        widget.options.financeInterfaces
                            .where((item) => interfaces[item.key] == true)
                            .map((item) => item.label)
                            .join('、'),
                      )
                    else
                      IgnorePointer(
                        ignoring: !_canEditTech,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in widget.options.financeInterfaces)
                              ProposalChoiceChip(
                                label:
                                    '${item.label}${item.required ? ' *' : ''}',
                                selected: interfaces[item.key] == true,
                                enabled: _canEditTech,
                                onSelected: (selected) {
                                  if (!_canEditTech) return;
                                  final next = Map<String, dynamic>.from(
                                    interfaces,
                                  )..[item.key] = selected;
                                  _set(
                                    'financeInterfaces',
                                    next,
                                    resetReview: 'financeInterfaceCompleted',
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _fieldGrid(wide, [
                _multiField(
                  '研发类型',
                  'developmentTypes',
                  widget.options.developmentTypes,
                  null,
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:developmentTypes',
                  reviewLabel: _techReviewLabel,
                ),
                _dropdownField(
                  '是否涉及研发费用',
                  'hasRdCost',
                  const ['是', '否'],
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:hasRdCost',
                  reviewLabel: _techReviewLabel,
                ),
                _numberField(
                  '研发费用金额（万元）',
                  'rdAmount',
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:rdAmount',
                  reviewLabel: _techReviewLabel,
                ),
                _dateField(
                  '交付时间',
                  'deliveryDate',
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:deliveryDate',
                  reviewLabel: _techReviewLabel,
                ),
              ]),
              if (_canEditTech) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _appendTechnologyRecord,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新增对接记录'),
                  ),
                ),
              ],
              ..._technologyRecordCards(),
              ..._technologyHistoryCards(),
            ],
          ),
        ),
        _moduleReview(
          title: '科技部板块审核',
          description: '科技部负责人填写，市场部负责人二逐条复核后统一确认。发现问题可直接驳回本板块。',
          keyName: 'technologyCompleted',
          buttonLabel: '科技部字段全部复核',
          locked: !_allTechnologyItemsReviewed,
          progress:
              '逐条复核 ${_reviewedCount('technologyItem', _technologyReviewFields)}/${_technologyReviewFields.length}',
        ),
        if (!_row.techRevisionOpen || _financeInterfaceNeedsReview)
          _moduleReview(
            title: '财务技术接口复核',
            description: '由本单财务部负责人二确认科技填写的财务技术接口，不是财务整板块复核。',
            keyName: 'financeInterfaceCompleted',
            buttonLabel: '确认财务技术接口',
          ),
      ],
    );
  }

  Widget _financeSection(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeyedSubtree(
        key: _financeKey,
        child: ProposalSectionTitle(
          title: '三、财务部内容',
          tag: 'Finance',
          description: _canEditBusinessCost
              ? '业务成本由你在财务复核时填写；其余财务项由提交人填写，财务部负责人二逐条复核。'
              : _canEditMarket
              ? '提交人填写 · 业务成本由市场部负责人一在财务复核时填写 · 财务部负责人二逐条复核 · 财务部负责人一整板块复核。'
              : '本板块由提交人填写；业务成本由市场部负责人一在财务复核时填写。',
        ),
      ),
      ProposalCard(
        child: Column(
          children: [
            _fieldGrid(wide, [
              _personField(
                '财务部负责人一（整板块复核）',
                'financeOwner1',
                positionIncludes: '财务部负责人一',
                required: true,
              ),
              _personField(
                '财务部负责人二（逐条复核）',
                'financeOwner2',
                positionIncludes: '财务部负责人二',
                required: true,
              ),
              ProposalField(
                label: '任务评级（按年化规模自动）',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ProposalPalette.purple,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        _rating,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '财务部复核',
                    style: TextStyle(
                      color: ProposalPalette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ProposalStatusChip(
                  label: _review['financeCompleted'] == true
                      ? '财务部复核已完成'
                      : '待财务部负责人二逐项复核',
                  kind: _review['financeCompleted'] == true
                      ? ProposalChipKind.ok
                      : ProposalChipKind.purple,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (_, box) {
                final columns = !wide
                    ? 1
                    : box.maxWidth >= 1180
                    ? 3
                    : box.maxWidth >= 760
                    ? 2
                    : 1;
                final itemWidth =
                    (box.maxWidth - (columns - 1) * 14 - 0.5) / columns;
                return Wrap(
                  spacing: 14,
                  children: [
                    for (final field in _financeFields)
                      SizedBox(width: itemWidth, child: _financeItem(field)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _costSelectField(
              label: '项目成本',
              namesKey: 'costItems',
              amountsKey: 'costItemAmounts',
              totalKey: 'projectCost',
              options: kProposalProjectCostItems,
              catalog: widget.options.costItemOptions,
              addLabel: widget.options.costItemSource == 'asset'
                  ? null
                  : '新增成本项',
              reviewSection: 'financeItem:costItems',
              wide: wide,
            ),
            const SizedBox(height: 10),
            _businessCostField(wide: wide),
            const SizedBox(height: 10),
            _costSelectField(
              label: '经营成本',
              namesKey: 'operatingCostItems',
              amountsKey: 'operatingCostItemAmounts',
              totalKey: 'operatingCost',
              options: kProposalOperatingCostItems,
              catalog: const [],
              reviewSection: 'financeItem:operatingCost',
              wide: wide,
            ),
            const SizedBox(height: 10),
            _costSelectField(
              label: '税务成本',
              namesKey: 'taxCostItems',
              amountsKey: 'taxCostItemAmounts',
              totalKey: 'taxCost',
              options: kProposalTaxCostItems,
              catalog: const [],
              reviewSection: 'financeItem:taxCost',
              wide: wide,
            ),
            const SizedBox(height: 10),
            _dropdownField(
              '是否回滚',
              'rollback',
              widget.options.rollbackOptions,
              resetReview: 'financeCompleted',
              reviewSection: 'financeItem:rollback',
              reviewLabel: _financeReviewLabel,
            ),
            if (_isPurchase) ...[
              const SizedBox(height: 10),
              _dropdownField(
                '渠道侧 · 白名单',
                'channelWhitelist',
                const ['是', '否'],
                resetReview: 'financeCompleted',
              ),
            ],
            const SizedBox(height: 16),
            _skuSettlementsBlock(wide),
            const SizedBox(height: 16),
            _financeModulesBlock(wide),
          ],
        ),
      ),
      _moduleReview(
        title: '财务部负责人一 · 整板块复核',
        description: '仅当财务部负责人二逐条复核完成后才能通过。发现问题可直接驳回本板块。',
        keyName: 'financeCompleted',
        buttonLabel: '整个财务部板块复核通过',
        locked: !_allFinanceItemsReviewed,
      ),
    ],
  );

  bool get _allFinanceItemsReviewed =>
      _itemsReviewed('financeItem', _financeReviewKeys);

  Widget _flowSection(bool wide) {
    final ctx = FlowCtxMapper.fromForm(
      form: _form,
      review: _review,
      proposalTitle: _row.title,
      financeReviewKeys: _financeReviewKeys,
      financeInterfaces: widget.options.financeInterfaces,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _flowKey,
          child: const ProposalSectionTitle(
            title: '四、风控与四流',
            tag: 'Auto',
            description: '自动串联市场、合同、科技和财务数据，字段变化后实时重算四流。',
          ),
        ),
        ProposalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final stacked = box.maxWidth < 520;
                  final title = const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '提案全链路',
                        style: TextStyle(
                          color: ProposalPalette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '上游板块是数据源，下方四流展示业务如何穿过各板块。',
                        style: TextStyle(
                          color: ProposalPalette.text3,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  );
                  final chip = const ProposalStatusChip(
                    label: '实时串联',
                    icon: Icons.circle,
                    kind: ProposalChipKind.purple,
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 8), chip],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      chip,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, box) {
                  final stacked = box.maxWidth < 560;
                  final cards = [
                    _sourceCard(
                      '市场部',
                      ctx.proposal,
                      '${ctx.sector} · ${ctx.project} · ${ctx.channels.join('、')}',
                      expanded: stacked,
                    ),
                    _sourceCard(
                      '采购 / 销售合同',
                      '${ctx.purchaseNo} ↔ ${ctx.salesNo}',
                      '${ctx.purchaseTheirs} → ${ctx.salesTheirs}',
                      expanded: stacked,
                    ),
                    _sourceCard(
                      '科技部',
                      ctx.tau1,
                      '${ctx.tau2.join('、')} · ${ctx.outputs.join('、')}',
                      expanded: stacked,
                    ),
                    _sourceCard(
                      '财务部',
                      ctx.financeSourceTitle,
                      ctx.financeSourceMeta,
                      expanded: stacked,
                    ),
                  ];
                  if (stacked) {
                    return Column(
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          cards[i],
                        ],
                      ],
                    );
                  }
                  return Wrap(spacing: 10, runSpacing: 10, children: cards);
                },
              ),
              const SizedBox(height: 14),
              RepaintBoundary(
                child: FlowPanoramaSection(
                  ctx: ctx,
                  compact: !wide,
                  canRename: _canEditMarket,
                  onNodeRenamed: _renameFlowNode,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _renameFlowNode(String nodeId, String name) {
    final key = kEditableNodeFields[nodeId];
    if (key == null) return;
    setState(() => _fieldEpoch++);
    _set(key, name.trim());
  }

  Widget _sourceCard(
    String label,
    String value,
    String meta, {
    bool expanded = false,
  }) => Container(
    width: expanded ? double.infinity : 250,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFAF8FC),
      border: Border.all(color: const Color(0xFFE4DAED)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: ProposalPalette.text3, fontSize: 9),
        ),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? '待填写' : value,
          maxLines: expanded ? 4 : 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ProposalPalette.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        Text(
          meta.isEmpty ? '—' : meta,
          maxLines: expanded ? 4 : 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ProposalPalette.text3,
            fontSize: 9,
            height: 1.35,
          ),
        ),
      ],
    ),
  );

  Widget _stepCard(String step, String title, String subtitle, Widget child) {
    return ProposalCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF8F4FB),
                  Color(0xFFFCFAFD),
                  Color(0xFFF4EEF9),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFE8E0EE))),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final stacked = box.maxWidth < 420;
                final badge = Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFD8CBE6)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      step,
                      style: const TextStyle(
                        color: Color(0xFF7255A8),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
                final titles = Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF393141),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF918799),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
                const chip = ProposalStatusChip(
                  label: '负责人填写',
                  kind: ProposalChipKind.purple,
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [badge, const SizedBox(width: 10), titles]),
                      const SizedBox(height: 8),
                      chip,
                    ],
                  );
                }
                return Row(
                  children: [badge, const SizedBox(width: 10), titles, chip],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 620 ? 8 : 10,
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _contractCard(String step, String title, String prefix, bool wide) {
    final mode = _text('${prefix}Mode');
    final signed = mode == '已签署合同';
    final unsigned = mode == '未签署合同';
    final flag = '${prefix}ContractCompleted';
    final keys = _contractItemKeys(prefix);
    final pending = _pendingContractReviewLabels(prefix);
    return _stepCard(
      step,
      title,
      '已签自动抓取 · 未签上传后解析',
      Column(
        children: [
          _fieldGrid(wide, [
            _dropdownField(
              '合同状态',
              '${prefix}Mode',
              const ['已签署合同', '未签署合同'],
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Mode',
              reviewLabel: _financeReviewLabel,
              onSelected: (value) => _setContractMode(prefix, value),
            ),
            if (signed) _contractSelector(prefix),
            _textField(
              '合同编号',
              '${prefix}No',
              source: signed
                  ? '合同抓取 · 可修改'
                  : unsigned
                  ? '未签合同'
                  : null,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.No',
              reviewLabel: _financeReviewLabel,
            ),
            if (unsigned) _unsignedFileField(prefix),
            _textField(
              '合同名称',
              '${prefix}Name',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Name',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '签署时间',
              '${prefix}SignDate',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.SignDate',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '我方签约主体',
              '${prefix}OurParty',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.OurParty',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '对方签约主体',
              '${prefix}Counterparty',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Counterparty',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '有效期',
              '${prefix}ValidPeriod',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.ValidPeriod',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '核心条款',
              '${prefix}CoreTerms',
              maxLines: 3,
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.CoreTerms',
              reviewLabel: _financeReviewLabel,
            ),
            if (prefix == 'purchase')
              _multiField(
                '采购产品',
                'purchaseProducts',
                widget.options.products.map((e) => e.value).toList(),
                '新增产品',
                resetReview: 'marketCompleted',
              ),
          ]),
          const SizedBox(height: 8),
          _moduleReview(
            title: '$title复核',
            description: [
              _isOwner('financeOwner2')
                  ? '由你逐条点「财务部负责人二复核」，或直接整板块驳回。'
                  : '采购/销售合同由财务部负责人二逐条复核，或直接整板块驳回。',
              if (pending.isNotEmpty) '还差：${pending.join('、')}。',
            ].join(),
            keyName: flag,
            buttonLabel: '合同字段审核通过',
            compact: true,
            locked: !_itemsReviewed('contractItem', keys),
            progress:
                '财务部负责人二复核 ${_reviewedCount('contractItem', keys)}/${keys.length}',
          ),
        ],
      ),
    );
  }

  Widget _contractSelector(String prefix) {
    final currentId = int.tryParse(_text('${prefix}ContractId'));
    final selectedNo = _text('${prefix}No');
    final selectedName = _text('${prefix}Name');
    return ProposalField(
      label: '选择合同',
      required: true,
      source: '从合同归集带出编号',
      tone: proposalFieldTone(enabled: _canEditMarket, source: '从合同归集带出编号'),
      child: ProposalSelectField<int>(
        key: ValueKey(
          'contract-$prefix-${_text('${prefix}ContractId')}-$_fieldEpoch',
        ),
        value: currentId,
        title: '选择合同归集中的合同',
        hint: '输入合同编号、名称或对方主体搜索',
        searchable: true,
        requireKeyword: true,
        remoteOptions: true,
        allowClear: false,
        onQueryChanged: _searchContracts,
        options: [
          if (currentId != null &&
              (selectedNo.isNotEmpty || selectedName.isNotEmpty))
            ProposalSelectOption(
              value: currentId,
              label: selectedName.isEmpty
                  ? selectedNo
                  : selectedNo.isEmpty
                  ? selectedName
                  : '$selectedNo · $selectedName',
              meta: _text('${prefix}Counterparty'),
            ),
          for (final contract in _contractHits)
            if (contract.id != currentId)
              ProposalSelectOption(
                value: contract.id,
                label: contract.label,
                meta: [
                  contract.partyA,
                  contract.partyB,
                  contract.signDate,
                ].where((item) => item.isNotEmpty).join(' · '),
              ),
        ],
        onSelected: !_canEditMarket
            ? null
            : (id) {
                if (id != null) {
                  unawaited(_applyContract(prefix, id));
                }
              },
      ),
    );
  }

  Future<void> _searchContracts(String keyword) async {
    final seq = ++_contractSearchSeq;
    final needle = keyword.trim();
    if (needle.isEmpty) {
      if (mounted) setState(() => _contractHits = const []);
      return;
    }
    try {
      final rows = await widget.service.fetchContracts(keyword: needle);
      if (!mounted || seq != _contractSearchSeq) return;
      setState(() => _contractHits = rows);
    } catch (error) {
      if (!mounted || seq != _contractSearchSeq) return;
      setState(() => _contractHits = const []);
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _applyContract(String prefix, int id) async {
    if (!_canEditMarket) return;
    try {
      final detail = await widget.service.fetchContractDetail(id);
      final form = Map<String, dynamic>.from(_form)
        ..addAll(
          proposalIntakePatchFromContract(prefix: prefix, detail: detail),
        );
      if (!mounted) return;
      setState(() {
        _dirty = true;
        _fieldEpoch++;
        _row = _row.copyWith(
          form: proposalIntakeRememberContractSnapshot(
            form: form,
            prefix: prefix,
          ),
          review: proposalIntakeClearContractReview(_review, prefix: prefix),
          status: _statusAfterEdit,
        );
      });
      widget.onChanged(_row);
      showProposalCenterToast(context, '已从合同归集带入可修改字段');
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _loadImportTemplates() async {
    if (!mounted) return;
    setState(() {
      _importTemplatesLoading = true;
      _importTemplatesError = null;
    });
    try {
      final items = await fetchProposalImportTemplates(
        apiBase: widget.session.apiBase,
        token: widget.session.token,
        allowDirectFallback: false,
      );
      if (!mounted) return;
      setState(() {
        _importTemplates = items;
        _importTemplatesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importTemplates = const [];
        _importTemplatesLoading = false;
        _importTemplatesError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _downloadImportTemplate(ProposalImportTemplateItem item) async {
    if (!item.available) {
      widget.onError(item.message.isNotEmpty ? item.message : '该业务平台暂未提供导入模板');
      return;
    }
    final url = item.downloadUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) {
      widget.onError('下载地址无效');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) widget.onError('无法打开下载链接');
    } catch (e) {
      widget.onError(friendlyErrorText(e, fallback: '下载失败'));
    }
  }

  List<Map<String, dynamic>> _onlineProductFiles() {
    final raw = _form['onlineProductFiles'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => '${e['fileName'] ?? ''}'.trim().isNotEmpty)
        .toList();
  }

  static const _productFileExts = <String>[
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'zip',
  ];
  static const _maxProductFiles = 5;

  /// 产品模板下载区先屏蔽，只保留上线产品文件上传。
  static const bool _showProductTemplates = false;
  static const _maxProductFileBytes = 20 * 1024 * 1024;

  bool _allowedProductFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return false;
    return _productFileExts.contains(name.substring(dot + 1).toLowerCase());
  }

  String _productFileMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pickOnlineProductFiles() async {
    if (!_canEditProductFiles || _uploadingProductFile) return;
    final current = _onlineProductFiles();
    final room = _maxProductFiles - current.length;
    if (room <= 0) {
      widget.onError('最多上传 $_maxProductFiles 个上线产品文件');
      return;
    }
    setState(() => _uploadingProductFile = true);
    try {
      final group = XTypeGroup(label: '上线产品文件', extensions: _productFileExts);
      List<XFile> picked = const [];
      try {
        picked = await openFiles(acceptedTypeGroups: [group]);
      } catch (_) {
        picked = await openFiles();
      }
      if (picked.isEmpty) return;
      await _ingestProductFiles(picked, room: room);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingProductFile = false);
    }
  }

  Future<void> _onProductFilesDropped(DropDoneDetails detail) async {
    if (!_canEditProductFiles || _uploadingProductFile) return;
    final current = _onlineProductFiles();
    final room = _maxProductFiles - current.length;
    if (room <= 0) {
      widget.onError('最多上传 $_maxProductFiles 个上线产品文件');
      return;
    }
    setState(() {
      _uploadingProductFile = true;
      _draggingProduct = false;
    });
    try {
      final picked = await _xfilesFromDrop(detail);
      if (picked.isEmpty) {
        widget.onError('请拖入文件（不支持文件夹）');
        return;
      }
      await _ingestProductFiles(picked, room: room);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '拖拽上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingProductFile = false);
    }
  }

  Future<void> _ingestProductFiles(
    List<XFile> picked, {
    required int room,
  }) async {
    final current = _onlineProductFiles();
    final next = [...current];
    var accepted = 0;
    for (final file in picked.take(room)) {
      final name = file.name.isEmpty ? 'product.pdf' : file.name;
      if (!_allowedProductFile(name)) {
        widget.onError('请上传 PDF / Word / Excel / PPT 文件：$name');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxProductFileBytes) {
        widget.onError('$name 超过 20MB 限制');
        continue;
      }
      final uploaded = await widget.service.uploadFile(
        bytes: bytes,
        fileName: name,
        mimeType: _productFileMime(name),
      );
      next.add({
        'fileName': uploaded.fileName,
        'objectKey': uploaded.objectKey,
        'url': uploaded.url,
        'sizeBytes': uploaded.sizeBytes,
        'mimeType': uploaded.mimeType,
      });
      accepted += 1;
    }
    if (!mounted || accepted == 0) return;
    _set('onlineProductFiles', next, resetReview: 'marketCompleted');
    showProposalCenterToast(context, '已上传上线产品文件');
  }

  void _removeOnlineProductFile(int index) {
    if (!_canEditProductFiles) return;
    final next = [..._onlineProductFiles()]..removeAt(index);
    _set('onlineProductFiles', next, resetReview: 'marketCompleted');
  }

  Future<void> _openOnlineProductFile(Map<String, dynamic> file) async {
    final name = '${file['fileName'] ?? ''}'.trim();
    final key = name.isEmpty ? '${file['objectKey'] ?? ''}' : name;
    if (_openingProductFile != null || _downloadingProductFile != null) return;
    setState(() => _openingProductFile = key);
    try {
      await openXflowAttachment(
        context: context,
        service: XflowService(session: widget.session),
        item: file,
        preferPreview: true,
      );
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '无法打开文件'));
    } finally {
      if (mounted) setState(() => _openingProductFile = null);
    }
  }

  Future<void> _downloadOnlineProductFile(Map<String, dynamic> file) async {
    final name = '${file['fileName'] ?? ''}'.trim();
    final key = name.isEmpty ? '${file['objectKey'] ?? ''}' : name;
    if (_openingProductFile != null || _downloadingProductFile != null) return;
    setState(() => _downloadingProductFile = key);
    try {
      await downloadXflowAttachment(
        context: context,
        service: XflowService(session: widget.session),
        item: file,
      );
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '下载失败'));
    } finally {
      if (mounted) setState(() => _downloadingProductFile = null);
    }
  }

  Future<List<XFile>> _xfilesFromDrop(DropDoneDetails detail) async {
    final files = <XFile>[];
    final accessed = <Uint8List>[];
    try {
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        files.add(XFile(item.path, name: item.name));
      }
      return files;
    } finally {
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } catch (_) {}
      }
    }
  }

  Widget _dropTarget({
    required bool enabled,
    required bool dragging,
    required ValueChanged<bool> onHover,
    required Future<void> Function(DropDoneDetails) onDrop,
    required Widget child,
  }) {
    if (!_supportsDesktopDrop || !enabled) return child;
    return DropTarget(
      enable: TickerMode.valuesOf(context).enabled,
      onDragEntered: (_) {
        if (!TickerMode.valuesOf(context).enabled) return;
        if (!dragging) onHover(true);
      },
      onDragExited: (_) => onHover(false),
      onDragDone: (detail) {
        if (!TickerMode.valuesOf(context).enabled) return;
        unawaited(onDrop(detail));
      },
      child: child,
    );
  }

  void _writeSkuDetails(
    List<ProposalSkuDetailRow> rows, {
    String resetReview = 'marketCompleted',
    List<ProposalCouponPackRow>? packs,
    bool? isCouponPack,
    bool? isExistingBuilt,
    bool rebuild = true,
  }) {
    final skuIds = {for (final row in rows) row.id};
    final nextPacks = [
      for (final pack in packs ?? proposalIntakeCouponPacks(_form))
        pack.copyWith(
          skuIds: [
            for (final id in pack.skuIds)
              if (skuIds.contains(id)) id,
          ],
        ),
    ];
    final form = Map<String, dynamic>.from(_form)
      ..['skuDetails'] = [for (final row in rows) row.toJson()]
      ..['couponPacks'] = [for (final pack in nextPacks) pack.toJson()];
    if (isCouponPack != null) form['isCouponPack'] = isCouponPack;
    if (isExistingBuilt != null) form['isExistingBuilt'] = isExistingBuilt;
    final review = Map<String, dynamic>.from(_review)..[resetReview] = false;
    _dirty = true;
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (rebuild && mounted) setState(() {});
    widget.onChanged(_row);
  }

  ProposalSkuDetailRow _newSkuDetailRow() => ProposalSkuDetailRow(
    id: proposalIntakeNewSkuId(),
    existingBuilt: proposalIntakeIsExistingBuilt(_form) ? '是' : '否',
    settlements: [ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId())],
  );

  ProposalCouponPackRow _newCouponPackRow() => ProposalCouponPackRow(
    id: proposalIntakeNewCouponPackId(),
    existingBuilt: proposalIntakeIsExistingBuilt(_form) ? '是' : '否',
    settlements: [ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId())],
  );

  void _setExistingBuiltEnabled(bool enabled) {
    if (!_canEditMarket) return;
    final label = enabled ? '是' : '否';
    _writeSkuDetails(
      [
        for (final row in proposalIntakeSkuDetails(_form))
          row.copyWith(
            existingBuilt: label,
            assetProduct: enabled ? row.assetProduct : null,
          ),
      ],
      packs: [
        for (final pack in proposalIntakeCouponPacks(_form))
          pack.copyWith(
            existingBuilt: label,
            assetProduct: enabled ? pack.assetProduct : null,
          ),
      ],
      isExistingBuilt: enabled,
    );
  }

  void _setCouponPackEnabled(bool enabled) {
    if (!_canEditMarket) return;
    final packs = proposalIntakeCouponPacks(_form);
    _writeSkuDetails(
      proposalIntakeSkuDetails(_form),
      packs: enabled && packs.isEmpty ? [_newCouponPackRow()] : packs,
      isCouponPack: enabled,
    );
  }

  void _writeCouponPacks(
    List<ProposalCouponPackRow> packs, {
    String resetReview = 'marketCompleted',
    bool rebuild = true,
  }) {
    _writeSkuDetails(
      proposalIntakeSkuDetails(_form),
      packs: packs,
      isCouponPack: true,
      resetReview: resetReview,
      rebuild: rebuild,
    );
  }

  void _addCouponPack() {
    if (!_canEditMarket) return;
    _writeCouponPacks([
      ...proposalIntakeCouponPacks(_form),
      _newCouponPackRow(),
    ]);
  }

  void _removeCouponPack(String id) {
    if (!_canEditMarket) return;
    _writeCouponPacks([
      for (final pack in proposalIntakeCouponPacks(_form))
        if (pack.id != id) pack,
    ]);
  }

  void _patchCouponPack(
    String id,
    ProposalCouponPackRow Function(ProposalCouponPackRow pack) update, {
    bool rebuild = true,
  }) {
    if (!_canEditMarket) return;
    _writeCouponPacks([
      for (final pack in proposalIntakeCouponPacks(_form))
        if (pack.id == id) update(pack) else pack,
    ], rebuild: rebuild);
  }

  void _toggleCouponPackSku(String packId, String skuId) {
    if (!_canEditMarket) return;
    _patchCouponPack(packId, (pack) {
      final selected = [...pack.skuIds];
      if (selected.contains(skuId)) {
        selected.remove(skuId);
      } else {
        selected.add(skuId);
      }
      return pack.copyWith(skuIds: selected);
    });
  }

  void _writePackSettlements(
    String packId,
    List<ProposalSkuSettleRow> settlements, {
    bool rebuild = true,
  }) {
    if (!_canEditSkuSettlements) return;
    _writeCouponPacks(
      [
        for (final pack in proposalIntakeCouponPacks(_form))
          if (pack.id == packId)
            pack.copyWith(settlements: settlements)
          else
            pack,
      ],
      resetReview: _canEditMarket ? 'marketCompleted' : 'financeCompleted',
      rebuild: rebuild,
    );
  }

  void _addPackSettle(String packId) {
    if (!_canEditSkuSettlements) return;
    final pack = proposalIntakeCouponPacks(
      _form,
    ).where((item) => item.id == packId).firstOrNull;
    if (pack == null) return;
    _writePackSettlements(packId, [
      ...proposalIntakePackSettlements(pack),
      ProposalSkuSettleRow(
        id: proposalIntakeNewSkuSettleId(),
        terms: ProposalFinanceSettleTerms(channelRef: pack.channelRef),
      ),
    ]);
  }

  void _removePackSettle(String packId, String settleId) {
    if (!_canEditSkuSettlements) return;
    final pack = proposalIntakeCouponPacks(
      _form,
    ).where((item) => item.id == packId).firstOrNull;
    if (pack == null) return;
    final next = [
      for (final item in proposalIntakePackSettlements(pack))
        if (item.id != settleId) item,
    ];
    if (next.isEmpty) return;
    _writePackSettlements(packId, next);
  }

  void _patchPackSettle(
    String packId,
    String settleId,
    ProposalFinanceSettleTerms terms,
  ) {
    if (!_canEditSkuSettlements) return;
    final pack = proposalIntakeCouponPacks(
      _form,
    ).where((item) => item.id == packId).firstOrNull;
    if (pack == null) return;
    _writePackSettlements(packId, [
      for (final item in proposalIntakePackSettlements(pack))
        if (item.id == settleId) item.copyWith(terms: terms) else item,
    ]);
  }

  void _addSkuDetail() {
    if (!_canEditMarket) return;
    _writeSkuDetails([...proposalIntakeSkuDetails(_form), _newSkuDetailRow()]);
  }

  void _patchSkuDetail(
    String id,
    ProposalSkuDetailRow Function(ProposalSkuDetailRow row) update, {
    bool rebuild = true,
  }) {
    _writeSkuDetails([
      for (final row in proposalIntakeSkuDetails(_form))
        if (row.id == id) update(row) else row,
    ], rebuild: rebuild);
  }

  void _removeSkuDetail(String id) {
    if (!_canEditMarket) return;
    _writeSkuDetails([
      for (final row in proposalIntakeSkuDetails(_form))
        if (row.id != id) row,
    ]);
  }

  void _writeSkuSettlements(
    String skuId,
    List<ProposalSkuSettleRow> settlements, {
    bool rebuild = true,
  }) {
    if (!_canEditSkuSettlements) return;
    _writeSkuDetails(
      [
        for (final row in proposalIntakeSkuDetails(_form))
          if (row.id == skuId)
            row.copyWith(settlements: settlements)
          else
            row,
      ],
      resetReview: _canEditMarket ? 'marketCompleted' : 'financeCompleted',
      rebuild: rebuild,
    );
  }

  void _addSkuSettle(String skuId) {
    if (!_canEditSkuSettlements) return;
    final row = proposalIntakeSkuDetails(
      _form,
    ).where((item) => item.id == skuId).firstOrNull;
    if (row == null) return;
    _writeSkuSettlements(skuId, [
      ...proposalIntakeSkuSettlements(row),
      ProposalSkuSettleRow(
        id: proposalIntakeNewSkuSettleId(),
        terms: ProposalFinanceSettleTerms(channelRef: row.channelRef),
      ),
    ]);
  }

  void _removeSkuSettle(String skuId, String settleId) {
    if (!_canEditSkuSettlements) return;
    final row = proposalIntakeSkuDetails(
      _form,
    ).where((item) => item.id == skuId).firstOrNull;
    if (row == null) return;
    final next = [
      for (final item in proposalIntakeSkuSettlements(row))
        if (item.id != settleId) item,
    ];
    if (next.isEmpty) return;
    _writeSkuSettlements(skuId, next);
  }

  void _patchSkuSettle(
    String skuId,
    String settleId,
    ProposalFinanceSettleTerms terms,
  ) {
    if (!_canEditSkuSettlements) return;
    final row = proposalIntakeSkuDetails(
      _form,
    ).where((item) => item.id == skuId).firstOrNull;
    if (row == null) return;
    _writeSkuSettlements(skuId, [
      for (final item in proposalIntakeSkuSettlements(row))
        if (item.id == settleId) item.copyWith(terms: terms) else item,
    ]);
  }

  Widget _skuDetailsBlock(bool wide) {
    final rows = proposalIntakeSkuDetails(_form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '渠道产品',
                style: TextStyle(
                  color: ProposalPalette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            if (_canEditMarket)
              TextButton.icon(
                onPressed: _addSkuDetail,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增渠道产品'),
              ),
          ],
        ),
        const Text(
          '可添加多条渠道产品。结算条款在财务部按产品或券包填写。',
          style: TextStyle(color: ProposalPalette.text3, fontSize: 11),
        ),
        const SizedBox(height: 8),
        _existingBuiltToggle(
          locked: _showSelectedAsText || !_canEditMarket,
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '尚未添加渠道产品',
              style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
            ),
          ),
        for (var i = 0; i < rows.length; i++) ...[
          const SizedBox(height: 10),
          _skuDetailCard(rows[i], i + 1, wide),
        ],
        const SizedBox(height: 12),
        _couponPackBlock(wide),
      ],
    );
  }

  Widget _existingBuiltToggle({required bool locked}) {
    final enabled = proposalIntakeIsExistingBuilt(_form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: locked ? null : () => _setExistingBuiltEnabled(!enabled),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: enabled,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: locked
                      ? null
                      : (value) => _setExistingBuiltEnabled(value == true),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '是否已经建产品',
                style: TextStyle(
                  color: ProposalPalette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '勾选后只需选择业务平台，再输入产品名称关键字搜索已建产品。券包同样。',
            style: TextStyle(color: ProposalPalette.text3, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _couponPackBlock(bool wide) {
    final enabled = proposalIntakeIsCouponPack(_form);
    final packs = proposalIntakeCouponPacks(_form);
    final products = proposalIntakeSkuDetails(_form);
    final locked = _showSelectedAsText || !_canEditMarket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: locked ? null : () => _setCouponPackEnabled(!enabled),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: enabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: locked
                          ? null
                          : (value) => _setCouponPackEnabled(value == true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '是否为券包',
                    style: TextStyle(
                      color: ProposalPalette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (enabled && _canEditMarket) ...[
              const Spacer(),
              TextButton.icon(
                onPressed: _addCouponPack,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增券包'),
              ),
            ],
          ],
        ),
        const Text(
          '勾选后可创建多个券包：填写券包名称，并勾选已填写的渠道产品。结算条款按券包填写，一个券包可有多套结算。',
          style: TextStyle(color: ProposalPalette.text3, fontSize: 11),
        ),
        if (enabled && packs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '尚未添加券包',
              style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
            ),
          ),
        if (enabled)
          for (var i = 0; i < packs.length; i++) ...[
            const SizedBox(height: 10),
            _couponPackCard(packs[i], i + 1, products, wide, locked),
          ],
      ],
    );
  }

  Widget _couponPackCard(
    ProposalCouponPackRow pack,
    int index,
    List<ProposalSkuDetailRow> products,
    bool wide,
    bool locked,
  ) {
    final existing = proposalIntakeIsExistingBuilt(_form);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4FB),
        border: Border.all(color: const Color(0xFFD9CDE8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '券包 $index',
                  style: const TextStyle(
                    color: ProposalPalette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_canEditMarket)
                TextButton(
                  onPressed: () => _removeCouponPack(pack.id),
                  child: const Text('删除'),
                ),
            ],
          ),
          _fieldGrid(wide, [
            _skuCatalogCell(
              label: '业务平台',
              current: pack.syncSourceRef,
              options: _syncSourceCatalog,
              locked: locked,
              hint: _syncSourceCatalog.isEmpty ? '字典加载中或暂无平台' : '请选择业务平台',
              onSelected: (value) {
                _patchCouponPack(pack.id, (current) {
                  final changed = current.syncSourceCode != (value?.code ?? '');
                  var next = current.copyWith(
                    syncSourceRef: value,
                    channelRef: changed ? null : current.channelRef,
                    assetProduct: changed ? null : current.assetProduct,
                    name: changed && existing ? '' : current.name,
                    settlements: changed
                        ? [
                            for (final item
                                in proposalIntakePackSettlements(current))
                              item.copyWith(
                                terms: item.terms.clearedCatalog(
                                  keepManual: false,
                                ),
                              ),
                          ]
                        : current.settlements,
                  );
                  if (changed && existing) {
                    next = next.applyAssetProduct(null);
                  }
                  return next;
                });
                if (value != null && value.isNotEmpty) {
                  _prefetchSettle(value.code, 'CHANNEL');
                }
              },
            ),
            if (existing)
              _assetProductSearchCell(
                rowId: pack.id,
                current: pack.assetProduct,
                syncSource: pack.syncSourceCode,
                locked: locked,
                label: '已建券包',
                onSelected: (value) => _patchCouponPack(
                  pack.id,
                  (current) => current.applyAssetProduct(value),
                ),
              )
            else ...[
            _skuTextCell(
              rowId: pack.id,
              label: '券包名称',
              value: pack.name,
              fieldKey: 'pack-name',
              locked: locked,
              onChanged: (value) => _patchCouponPack(
                pack.id,
                (current) => current.copyWith(name: value),
                rebuild: false,
              ),
            ),
            _skuChannelCell(
              current: pack.channelRef,
              locked: locked,
              syncSource: pack.syncSourceCode,
              onSelected: (value) => _patchCouponPack(
                pack.id,
                (current) => current.copyWith(
                  channelRef: value,
                  settlements: [
                    for (final item in proposalIntakePackSettlements(current))
                      item.copyWith(
                        terms: item.terms.copyWith(channelRef: value),
                      ),
                  ],
                ),
              ),
            ),
            _skuInstitutionCell(
              current: pack.institutionRef,
              locked: locked,
              onSelected: (value) => _patchCouponPack(
                pack.id,
                (current) => current.copyWith(institutionRef: value),
              ),
            ),
            ],
          ]),
          if (!existing) ...[
          const SizedBox(height: 8),
          const Text(
            '包含渠道产品',
            style: TextStyle(
              color: ProposalPalette.text2,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          if (products.isEmpty)
            const Text(
              '请先添加渠道产品后再勾选。',
              style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
            )
          else if (locked)
            _readonlySelectedText(
              [
                for (final sku in products)
                  if (pack.skuIds.contains(sku.id))
                    sku.productName.trim().isEmpty
                        ? '未填写产品名称'
                        : sku.productName.trim(),
              ].join('、'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sku in products)
                  ProposalChoiceChip(
                    label: sku.productName.trim().isEmpty
                        ? '未填写产品名称'
                        : [
                            sku.productName.trim(),
                            if (sku.faceValue.trim().isNotEmpty)
                              sku.faceValue.trim(),
                          ].join(' · '),
                    selected: pack.skuIds.contains(sku.id),
                    enabled: _canEditMarket,
                    onSelected: (_) => _toggleCouponPackSku(pack.id, sku.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _skuDetailCard(ProposalSkuDetailRow row, int index, bool wide) {
    final locked = _showSelectedAsText || !_canEditMarket;
    final existing = proposalIntakeIsExistingBuilt(_form);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FC),
        border: Border.all(color: const Color(0xFFE2D8EC)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '渠道产品 $index',
                  style: const TextStyle(
                    color: ProposalPalette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_canEditMarket)
                TextButton(
                  onPressed: () => _removeSkuDetail(row.id),
                  child: const Text('删除'),
                ),
            ],
          ),
          _fieldGrid(wide, [
            _skuCatalogCell(
              label: '业务平台',
              current: row.syncSourceRef,
              options: _syncSourceCatalog,
              locked: locked,
              hint: _syncSourceCatalog.isEmpty ? '字典加载中或暂无平台' : '请选择业务平台',
              onSelected: (value) {
                _patchSkuDetail(row.id, (current) {
                  final changed = current.syncSourceCode != (value?.code ?? '');
                  var next = current.copyWith(
                    syncSourceRef: value,
                    channelRef: changed ? null : current.channelRef,
                    settlements: changed
                        ? [
                            for (final item
                                in proposalIntakeSkuSettlements(current))
                              item.copyWith(
                                terms: item.terms.clearedCatalog(
                                  keepManual: false,
                                ),
                              ),
                          ]
                        : current.settlements,
                  );
                  if (changed && existing) {
                    next = next.applyAssetProduct(null);
                  }
                  return next;
                });
                if (value != null && value.isNotEmpty) {
                  _prefetchSettle(value.code, 'CHANNEL');
                }
              },
            ),
            if (existing)
              _assetProductSearchCell(
                rowId: row.id,
                current: row.assetProduct,
                syncSource: row.syncSourceCode,
                locked: locked,
                label: '已建产品',
                onSelected: (value) => _patchSkuDetail(
                  row.id,
                  (current) => current.applyAssetProduct(value),
                ),
              )
            else ...[
            _skuTextCell(
              rowId: row.id,
              label: '产品名称',
              value: row.productName,
              fieldKey: 'name',
              locked: locked,
              onChanged: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(productName: value),
                rebuild: false,
              ),
            ),
            _skuChannelCell(
              current: row.channelRef,
              locked: locked,
              syncSource: row.syncSourceCode,
              onSelected: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(
                  channelRef: value,
                  settlements: [
                    for (final item in proposalIntakeSkuSettlements(current))
                      item.copyWith(
                        terms: item.terms.copyWith(channelRef: value),
                      ),
                  ],
                ),
              ),
            ),
            _skuInstitutionCell(
              current: row.institutionRef,
              locked: locked,
              onSelected: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(institutionRef: value),
              ),
            ),
            _skuTextCell(
              rowId: row.id,
              label: '面值',
              value: row.faceValue,
              fieldKey: 'face',
              hint: '手填',
              locked: locked,
              onChanged: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(faceValue: value),
                rebuild: false,
              ),
            ),
            ProposalField(
              label: '是否同步中油好客',
              child: locked
                  ? _readonlySelectedText(row.syncZhongyouHaoke)
                  : ProposalSelectField<String>(
                      value: row.syncZhongyouHaoke.isEmpty
                          ? null
                          : row.syncZhongyouHaoke,
                      title: '是否同步中油好客',
                      hint: '请选择',
                      options: const [
                        ProposalSelectOption(value: '同步', label: '同步'),
                        ProposalSelectOption(value: '不同步', label: '不同步'),
                      ],
                      onSelected: (value) => _patchSkuDetail(
                        row.id,
                        (current) =>
                            current.copyWith(syncZhongyouHaoke: value ?? ''),
                      ),
                    ),
            ),
            _skuTextCell(
              rowId: row.id,
              label: '库存数量',
              value: row.inventoryQty,
              fieldKey: 'qty',
              hint: '数字',
              locked: locked,
              keyboardType: TextInputType.number,
              onChanged: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(inventoryQty: value),
                rebuild: false,
              ),
            ),
            ],
          ]),
          if (!existing) ...[
          const SizedBox(height: 8),
          _fieldGrid(wide, [
            _skuDateCell(
              rowId: row.id,
              label: '产品生效日期',
              value: row.effectiveDate,
              fieldKey: 'effective',
              locked: locked,
              onPicked: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(effectiveDate: value),
              ),
            ),
            _skuDateCell(
              rowId: row.id,
              label: '产品失效日期',
              value: row.expireDate,
              fieldKey: 'expire',
              locked: locked,
              onPicked: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(expireDate: value),
              ),
            ),
          ], columns: 2),
          const SizedBox(height: 8),
          _fieldGrid(wide, [
            _skuTextCell(
              rowId: row.id,
              label: '供应商编码（多个，用 | 分隔）',
              value: row.supplierCodes,
              fieldKey: 'suppliers',
              hint: '越前面的排名越高，例如 A|B|C',
              locked: locked,
              onChanged: (value) => _patchSkuDetail(
                row.id,
                (current) => current.copyWith(supplierCodes: value),
                rebuild: false,
              ),
            ),
          ], columns: 1),
          ],
        ],
      ),
    );
  }

  Widget _assetProductSearchCell({
    required String rowId,
    required ChannelProductHit? current,
    required String syncSource,
    required bool locked,
    required String label,
    required ValueChanged<ChannelProductHit?> onSelected,
  }) {
    final noPlatform = syncSource.trim().isEmpty;
    final searching = _assetProductSearching.contains(rowId);
    final hits = _assetProductHits[rowId] ?? const <ChannelProductHit>[];
    final values = [
      if (current != null &&
          current.isNotEmpty &&
          !hits.any((item) => item == current))
        current,
      ...hits,
    ];
    return ProposalField(
      label: label,
      required: true,
      child: locked
          ? _readonlySelectedText(current?.label ?? '')
          : ProposalSelectField<ChannelProductHit>(
              value: current == null || current.isEmpty ? null : current,
              title: label,
              hint: noPlatform ? '请先选择业务平台' : '输入产品名称关键字搜索',
              searchable: true,
              requireKeyword: true,
              remoteOptions: true,
              emptyText: noPlatform
                  ? '请先选择业务平台'
                  : (searching ? '搜索中…' : '未找到已建产品'),
              options: [
                for (final item in values)
                  ProposalSelectOption(
                    value: item,
                    label: item.label,
                    meta: [
                      if (item.productCode.isNotEmpty) item.productCode,
                      if (item.channelName.isNotEmpty) item.channelName,
                    ].join(' · '),
                  ),
              ],
              onQueryChanged: noPlatform
                  ? null
                  : (query) => unawaited(
                      _searchAssetProducts(rowId, syncSource, query),
                    ),
              onSelected: onSelected,
            ),
    );
  }

  Widget _skuInstitutionCell({
    required CatalogRef? current,
    required bool locked,
    required ValueChanged<CatalogRef?> onSelected,
  }) {
    final options = widget.options.institutions;
    return _skuCatalogCell(
      label: '机构',
      current: current,
      options: options,
      locked: locked,
      hint: options.isEmpty ? '请先在管理端配置机构' : '请选择机构',
      emptyText: options.isEmpty ? '请先在管理后台「提案录入选项」中配置机构' : null,
      onSelected: onSelected,
    );
  }

  Widget _skuChannelCell({
    required CatalogRef? current,
    required bool locked,
    required String syncSource,
    required ValueChanged<CatalogRef?> onSelected,
  }) {
    if (syncSource.trim().isNotEmpty) {
      _prefetchSettle(syncSource, 'CHANNEL');
    }
    final settleKey = _settleCacheKey(syncSource, 'CHANNEL');
    final loading = _settleLoading.contains(settleKey);
    final options =
        (_settleBundles[settleKey] ?? const _SettleCatalogBundle()).channels;
    final noPlatform = syncSource.trim().isEmpty;
    return _skuCatalogCell(
      label: '渠道',
      current: current,
      options: options,
      locked: locked,
      hint: noPlatform
          ? '请先选择业务平台'
          : (options.isEmpty
                ? (loading ? '字典加载中…' : '该业务平台暂无渠道')
                : '请选择渠道'),
      emptyText: noPlatform
          ? '请先选择业务平台'
          : (loading ? '字典加载中…' : '该业务平台暂无渠道'),
      onSelected: onSelected,
    );
  }

  Widget _skuCatalogCell({
    required String label,
    required CatalogRef? current,
    required List<CatalogRef> options,
    required bool locked,
    required ValueChanged<CatalogRef?> onSelected,
    String? hint,
    String? emptyText,
  }) {
    final selected = _selectedCatalog(current, options);
    final values = _withCurrent(options, selected);
    return ProposalField(
      label: label,
      child: locked || _showSelectedAsText
          ? _readonlySelectedText(selected?.label ?? '')
          : ProposalSelectField<CatalogRef>(
              value: selected == null || selected.isEmpty ? null : selected,
              title: label,
              hint: hint ?? '请选择',
              searchable: true,
              emptyText: emptyText,
              options: [
                for (final item in values)
                  ProposalSelectOption(
                    value: item,
                    label: item.label,
                    meta: item.code.isEmpty || item.code == item.name
                        ? null
                        : item.code,
                  ),
              ],
              onSelected: onSelected,
            ),
    );
  }

  Widget _skuTextCell({
    required String rowId,
    required String label,
    required String value,
    required String fieldKey,
    required bool locked,
    required ValueChanged<String> onChanged,
    String? hint,
    String? source,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final tone = proposalFieldTone(enabled: !locked, source: source);
    final multiline = maxLines > 1;
    final field = ProposalField(
      label: label,
      source: source,
      tone: tone,
      child: locked
          ? _readonlySelectedText(value, maxLines: maxLines)
          : TextFormField(
              key: ValueKey('sku-$rowId-$fieldKey-$_fieldEpoch'),
              initialValue: value,
              minLines: multiline ? 3 : 1,
              maxLines: multiline ? null : 1,
              keyboardType:
                  keyboardType ??
                  (multiline ? TextInputType.multiline : null),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: onChanged,
              decoration: proposalInputDecoration(hint: hint, tone: tone),
            ),
    );
    return multiline ? _FullWidthField(child: field) : field;
  }

  Widget _skuDateCell({
    required String rowId,
    required String label,
    required String value,
    required String fieldKey,
    required bool locked,
    required ValueChanged<String> onPicked,
  }) {
    final parsed = _parseDate(value);
    return _datePickerField(
      fieldKey: 'sku-$rowId-$fieldKey',
      label: label,
      display: parsed == null ? value : _fmtDate(parsed),
      empty: value.trim().isEmpty,
      enabled: !locked,
      onTap: locked
          ? null
          : () async {
              final picked = await _pickDate(parsed);
              if (picked != null) onPicked(_fmtDate(picked));
            },
    );
  }

  Widget _skuYesNoCell({
    required String rowId,
    required String label,
    required String value,
    required String fieldKey,
    required bool locked,
    required ValueChanged<String> onChanged,
  }) {
    return ProposalField(
      label: label,
      child: locked
          ? _readonlySelectedText(value)
          : ProposalSelectField<String>(
              key: ValueKey('sku-$rowId-$fieldKey-$_fieldEpoch'),
              value: value.isEmpty ? null : value,
              title: label,
              hint: '请选择',
              options: const [
                ProposalSelectOption(value: '是', label: '是'),
                ProposalSelectOption(value: '否', label: '否'),
              ],
              onSelected: (next) => onChanged(next ?? ''),
            ),
    );
  }

  void _writeLaunchFinance({
    required List<ProposalLaunchRow> rows,
    required List<ProposalFinanceModule> modules,
    String? resetReview,
    bool rebuild = true,
  }) {
    final form = Map<String, dynamic>.from(_form)
      ..['launchRows'] = [for (final row in rows) row.toJson()]
      ..['financeModules'] = [for (final item in modules) item.toJson()];
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    if (resetReview != 'financeCompleted') {
      review['financeCompleted'] = false;
    }
    _dirty = true;
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (rebuild && mounted) setState(() {});
    widget.onChanged(_row);
  }

  void _addFinanceModule() {
    if (!_canEditFinanceModules) return;
    final modules = proposalIntakeFinanceModules(_form);
    _writeLaunchFinance(
      rows: proposalIntakeLaunchRows(_form),
      modules: [
        ...modules,
        ProposalFinanceModule(
          id: proposalIntakeNewFinanceModuleId(),
          title: '财务模块${modules.length + 1}',
        ),
      ],
      resetReview: 'financeCompleted',
    );
  }

  void _removeFinanceModule(String id) {
    if (!_canEditFinanceModules) return;
    _writeLaunchFinance(
      rows: proposalIntakeLaunchRows(_form),
      modules: [
        for (final item in proposalIntakeFinanceModules(_form))
          if (item.id != id) item,
      ],
      resetReview: 'financeCompleted',
    );
  }

  void _patchFinanceModule(
    String id,
    ProposalFinanceModule Function(ProposalFinanceModule item) update, {
    bool rebuild = true,
  }) {
    if (!_canEditFinanceModules) return;
    final modules = [
      for (final item in proposalIntakeFinanceModules(_form))
        if (item.id == id) update(item) else item,
    ];
    _writeLaunchFinance(
      rows: proposalIntakeLaunchRows(_form),
      modules: modules,
      resetReview: 'financeCompleted',
      rebuild: rebuild,
    );
  }

  Widget _skuSettlementsBlock(bool wide) {
    final packMode = proposalIntakeIsCouponPack(_form);
    final channelRows = proposalIntakeSkuDetails(_form);
    final packs = proposalIntakeCouponPacks(_form);
    final enabled = _canEditSkuSettlements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          packMode ? '券包结算' : '产品结算',
          style: const TextStyle(
            color: ProposalPalette.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          packMode
              ? '按券包填写。一个券包对应一套结算，可再新增明细。'
              : '按渠道产品填写。一个产品对应一套结算，可再新增明细。',
          style: const TextStyle(color: ProposalPalette.text3, fontSize: 11),
        ),
        if (!packMode && channelRows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '请先在市场部添加渠道产品。',
              style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
            ),
          ),
        if (packMode && packs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '请先在市场部勾选是否为券包并创建券包。',
              style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
            ),
          ),
        if (packMode)
          for (final pack in packs) ...[
            const SizedBox(height: 8),
            _skuSettleProductCard(
              skuId: pack.id,
              title: [
                if (pack.name.trim().isNotEmpty) pack.name.trim(),
                for (final sku in channelRows)
                  if (pack.skuIds.contains(sku.id) &&
                      sku.productName.trim().isNotEmpty)
                    sku.productName.trim(),
              ].join(' · '),
              emptyTitle: '未填写券包名称',
              reviewPrefix: 'packSettle',
              settlements: proposalIntakePackSettlements(pack),
              wide: wide,
              enabled: enabled,
              syncSource: pack.syncSourceCode,
              productSource: 'CHANNEL',
              onAdd: () => _addPackSettle(pack.id),
              onRemove: (settleId) => _removePackSettle(pack.id, settleId),
              onPatch: (settleId, terms) =>
                  _patchPackSettle(pack.id, settleId, terms),
            ),
          ]
        else
          for (final sku in channelRows) ...[
            const SizedBox(height: 8),
            _skuSettleProductCard(
              skuId: sku.id,
              title: [
                if (sku.productName.trim().isNotEmpty) sku.productName.trim(),
                if (sku.faceValue.trim().isNotEmpty)
                  '面值 ${sku.faceValue.trim()}',
              ].join(' · '),
              emptyTitle: '未填写产品名称',
              reviewPrefix: 'skuSettle',
              settlements: proposalIntakeSkuSettlements(sku),
              wide: wide,
              enabled: enabled,
              syncSource: sku.syncSourceCode,
              productSource: 'CHANNEL',
              onAdd: () => _addSkuSettle(sku.id),
              onRemove: (settleId) => _removeSkuSettle(sku.id, settleId),
              onPatch: (settleId, terms) =>
                  _patchSkuSettle(sku.id, settleId, terms),
            ),
          ],
      ],
    );
  }

  String _primarySyncSource() {
    if (proposalIntakeIsCouponPack(_form)) {
      for (final pack in proposalIntakeCouponPacks(_form)) {
        if (pack.syncSourceCode.isNotEmpty) return pack.syncSourceCode;
      }
    }
    for (final sku in proposalIntakeSkuDetails(_form)) {
      if (sku.syncSourceCode.isNotEmpty) return sku.syncSourceCode;
    }
    return '';
  }

  Widget _skuSettleProductCard({
    required String skuId,
    required String title,
    required String emptyTitle,
    required String reviewPrefix,
    required List<ProposalSkuSettleRow> settlements,
    required bool wide,
    required bool enabled,
    required String syncSource,
    required String productSource,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
    required void Function(String settleId, ProposalFinanceSettleTerms terms)
        onPatch,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: const Color(0xFFD9E3F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? emptyTitle : title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ProposalPalette.text,
                  ),
                ),
              ),
              if (enabled)
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增明细'),
                ),
            ],
          ),
          for (var i = 0; i < settlements.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _skuSettleTable(
              skuId: skuId,
              settle: settlements[i],
              index: i,
              wide: wide,
              enabled: enabled,
              canRemove: enabled && settlements.length > 1,
              reviewPrefix: reviewPrefix,
              syncSource: syncSource,
              productSource: productSource,
              onRemove: () => onRemove(settlements[i].id),
              onPatch: (terms) => onPatch(settlements[i].id, terms),
            ),
          ],
        ],
      ),
    );
  }

  Widget _skuSettleTable({
    required String skuId,
    required ProposalSkuSettleRow settle,
    required int index,
    required bool wide,
    required bool enabled,
    required bool canRemove,
    required String reviewPrefix,
    required String syncSource,
    required String productSource,
    required VoidCallback onRemove,
    required ValueChanged<ProposalFinanceSettleTerms> onPatch,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E3F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            alignment: Alignment.center,
            color: const Color(0xFFEEF3FA),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  proposalIntakeSettleLabel(index),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: ProposalPalette.text,
                    height: 1.25,
                  ),
                ),
                if (canRemove)
                  TextButton(
                    onPressed: onRemove,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('删除', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child:
                      _rowReviewToggle(
                        'financeItem:$reviewPrefix:$skuId:${settle.id}',
                        _financeReviewLabel,
                      ) ??
                      const SizedBox.shrink(),
                ),
                _settleTermsGrid(
                  wide: wide,
                  keyPrefix: '$reviewPrefix-$skuId-${settle.id}',
                  terms: settle.terms,
                  enabled: enabled,
                  includeParties: false,
                  includeChannel: false,
                  syncSource: syncSource,
                  productSource: productSource,
                  onChanged: onPatch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeModulesBlock(bool wide) {
    final modules = proposalIntakeFinanceModules(_form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '财务模块',
                style: TextStyle(
                  color: ProposalPalette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            if (_canEditFinanceModules)
              TextButton.icon(
                onPressed: _addFinanceModule,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增财务模块'),
              ),
          ],
        ),
        const Text(
          '收入和每条成本按结算单填写：账单类型、结算方式、结算比例/单价、计算公式、发票类型、税率、生效/失效时间，以及对方/我方主体。非自然月需选择项目周期。',
          style: TextStyle(color: ProposalPalette.text3, fontSize: 11),
        ),
        if (modules.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '尚未添加财务模块',
              style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
            ),
          ),
        for (final item in modules) ...[
          const SizedBox(height: 10),
          _financeModuleCard(item, wide),
        ],
      ],
    );
  }

  Widget _financeModuleCard(ProposalFinanceModule module, bool wide) {
    final enabled = _canEditFinanceModules && !_showSelectedAsText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: const Color(0xFFD9E3F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  module.title.isEmpty ? '财务模块' : module.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ProposalPalette.text,
                  ),
                ),
              ),
              _rowReviewToggle(
                    'financeItem:launchModule:${module.id}',
                    _financeReviewLabel,
                  ) ??
                  const SizedBox.shrink(),
              if (enabled)
                TextButton(
                  onPressed: () => _removeFinanceModule(module.id),
                  child: const Text('删除'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _fieldGrid(wide, [
            ProposalField(
              label: '是否自然月',
              required: true,
              child: _showSelectedAsText || !enabled
                  ? _readonlySelectedText(module.naturalMonth)
                  : ProposalSelectField<String>(
                      value: module.naturalMonth.isEmpty
                          ? null
                          : module.naturalMonth,
                      title: '是否自然月',
                      hint: '请选择',
                      allowClear: false,
                      options: const [
                        ProposalSelectOption(value: '是', label: '是'),
                        ProposalSelectOption(value: '否', label: '否'),
                      ],
                      onSelected: (value) => _patchFinanceModule(
                        module.id,
                        (current) => current.copyWith(
                          naturalMonth: value ?? '',
                          projectPeriodStart: value == '否'
                              ? current.projectPeriodStart
                              : '',
                          projectPeriodEnd: value == '否'
                              ? current.projectPeriodEnd
                              : '',
                        ),
                      ),
                    ),
            ),
            if (module.usesProjectPeriod)
              ProposalField(
                label: '项目周期',
                required: true,
                child: _showSelectedAsText || !enabled
                    ? _readonlySelectedText(module.projectPeriodLabel)
                    : _financeProjectPeriodPicker(module),
              ),
          ]),
          const SizedBox(height: 10),
          const Text(
            '收入',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: ProposalPalette.text2,
            ),
          ),
          _settleTermsGrid(
            wide: wide,
            keyPrefix: '${module.id}-rev',
            terms: module.revenue,
            enabled: enabled,
            syncSource: _primarySyncSource(),
            productSource: 'CHANNEL',
            onChanged: (terms) => _patchFinanceModule(
              module.id,
              (current) => current.copyWith(revenue: terms),
              rebuild: false,
            ),
          ),
          const SizedBox(height: 10),
          _financeCostLines(
            wide: wide,
            label: '项目成本',
            lines: module.projectCosts,
            names: kProposalProjectCostItems,
            enabled: enabled,
            productSource: 'SUPPLIER',
            onChanged: (lines) => _patchFinanceModule(
              module.id,
              (current) => current.copyWith(projectCosts: lines),
              rebuild: false,
            ),
          ),
          const SizedBox(height: 10),
          _financeCostLines(
            wide: wide,
            label: '业务成本',
            lines: module.businessCosts,
            names: widget.options.businessCostItems,
            enabled: enabled,
            productSource: 'SUPPLIER',
            onChanged: (lines) => _patchFinanceModule(
              module.id,
              (current) => current.copyWith(businessCosts: lines),
              rebuild: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeProjectPeriodPicker(ProposalFinanceModule module) {
    final start = _parseDate(module.projectPeriodStart);
    final end = _parseDate(module.projectPeriodEnd);
    final empty = module.projectPeriodLabel.isEmpty;
    final tone = proposalFieldTone(enabled: true);
    return InkWell(
      key: ValueKey('date-${module.id}-period'),
      onTap: () async {
        final picked = await _pickDateRange(start: start, end: end);
        if (picked == null || !mounted) return;
        _patchFinanceModule(
          module.id,
          (current) => current.copyWith(
            projectPeriodStart: _fmtDate(picked.start),
            projectPeriodEnd: _fmtDate(picked.end),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration:
            proposalInputDecoration(
              hint: '请选择项目周期',
              readOnly: true,
              tone: tone,
            ).copyWith(
              suffixIcon: const Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: ProposalPalette.text3,
              ),
            ),
        child: Text(
          empty ? '请选择项目周期' : module.projectPeriodLabel,
          style: TextStyle(
            fontSize: 13,
            color: empty ? ProposalPalette.text3 : ProposalPalette.text,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _financeCostLines({
    required bool wide,
    required String label,
    required List<ProposalFinanceCostLine> lines,
    required List<String> names,
    required bool enabled,
    required String productSource,
    required ValueChanged<List<ProposalFinanceCostLine>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: ProposalPalette.text2,
                ),
              ),
            ),
            if (enabled)
              TextButton(
                onPressed: () {
                  final unused = names.where(
                    (name) => !lines.any(
                      (line) => proposalProjectCostNamesOf(
                        line.name,
                      ).contains(name),
                    ),
                  );
                  final name = unused.isNotEmpty
                      ? unused.first
                      : '成本项${lines.length + 1}';
                  onChanged([
                    ...lines,
                    ProposalFinanceCostLine(
                      id: 'cl-${DateTime.now().microsecondsSinceEpoch}',
                      name: name,
                    ),
                  ]);
                },
                child: const Text('新增成本项'),
              ),
          ],
        ),
        if (lines.isEmpty)
          const Text(
            '暂无成本项',
            style: TextStyle(color: ProposalPalette.text3, fontSize: 12),
          ),
        for (final line in lines) ...[
          const SizedBox(height: 8),
          Text(
            line.name,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: ProposalPalette.text,
            ),
          ),
          _settleTermsGrid(
            wide: wide,
            keyPrefix: line.id,
            terms: line.terms,
            enabled: enabled,
            syncSource: _primarySyncSource(),
            productSource: productSource,
            onChanged: (terms) => onChanged([
              for (final item in lines)
                if (item.id == line.id)
                  ProposalFinanceCostLine(
                    id: item.id,
                    name: item.name,
                    terms: terms,
                  )
                else
                  item,
            ]),
          ),
        ],
      ],
    );
  }

  Widget _settleTermsGrid({
    required bool wide,
    required String keyPrefix,
    required ProposalFinanceSettleTerms terms,
    required bool enabled,
    required ValueChanged<ProposalFinanceSettleTerms> onChanged,
    int? columns,
    bool includeParties = true,
    bool includeChannel = true,
    String syncSource = '',
    String productSource = 'CHANNEL',
  }) {
    if (syncSource.trim().isNotEmpty) {
      _prefetchSettle(syncSource, productSource);
    }
    final settleKey = _settleCacheKey(syncSource, productSource);
    final loading = _settleLoading.contains(settleKey);
    final bundle = _settleBundles[settleKey] ?? const _SettleCatalogBundle();
    final noPlatform = syncSource.trim().isEmpty;
    final catalogHint = noPlatform ? '请先选择业务平台' : '请选择';
    final catalogEmptyText = noPlatform
        ? '请先在渠道产品上选择业务平台'
        : (loading ? '字典加载中…' : '该业务平台暂无选项');

    Widget field(
      String label,
      String value,
      ProposalFinanceSettleTerms Function(String) write, {
      String? hint,
    }) {
      return ProposalField(
        label: label,
        child: !enabled
            ? _readonlySelectedText(value)
            : TextFormField(
                key: ValueKey('settle-$keyPrefix-$label-$_fieldEpoch'),
                initialValue: value,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onChanged: (next) => onChanged(write(next.trim())),
                decoration: proposalInputDecoration(hint: hint),
              ),
      );
    }

    Widget catalogField({
      required String label,
      required CatalogRef? current,
      required List<CatalogRef> options,
      required ProposalFinanceSettleTerms Function(CatalogRef?) write,
      String? Function(CatalogRef item)? metaOf,
    }) {
      final selected = _selectedCatalog(current, options);
      final values = _withCurrent(options, selected);
      return ProposalField(
        label: label,
        child: !enabled
            ? _readonlySelectedText(
                selected?.label ?? current?.label ?? '',
                maxLines: 4,
              )
            : ProposalSelectField<CatalogRef>(
                value: selected == null || selected.isEmpty ? null : selected,
                title: label,
                hint: catalogHint,
                searchable: true,
                emptyText: catalogEmptyText,
                options: [
                  for (final item in values)
                    ProposalSelectOption(
                      value: item,
                      label: item.label,
                      meta: metaOf?.call(item) ??
                          (item.code.isEmpty || item.code == item.name
                              ? null
                              : item.code),
                    ),
                ],
                onSelected: (value) => onChanged(write(value)),
              ),
      );
    }

    final formulaOptions = [
      for (final item in bundle.formulas)
        if (terms.settleModeRef == null ||
            terms.settleModeRef!.isEmpty ||
            item.settleMethod.isEmpty ||
            item.settleMethod == terms.settleModeRef!.code)
          item,
    ];

    Widget dateField(String label, String value, String fieldKey,
        ProposalFinanceSettleTerms Function(String) write) {
      final parsed = _parseDate(value);
      return _datePickerField(
        fieldKey: 'settle-$keyPrefix-$fieldKey',
        label: label,
        display: parsed == null ? value : _fmtDate(parsed),
        empty: value.trim().isEmpty,
        enabled: enabled,
        onTap: !enabled
            ? null
            : () async {
                final picked = await _pickDate(parsed);
                if (picked != null) onChanged(write(_fmtDate(picked)));
              },
      );
    }

    final topColumns = columns ?? (includeChannel ? 5 : 4);
    return Column(
      children: [
        _fieldGrid(wide, [
          if (includeChannel)
            catalogField(
              label: '渠道',
              current: terms.channelRef,
              options: bundle.channels,
              write: (value) => terms.copyWith(channelRef: value),
            ),
          catalogField(
            label: '账单类型',
            current: terms.billTypeRef ??
                CatalogRef.fromName(terms.billType),
            options: bundle.billTypes,
            write: (value) => terms.copyWith(
              billType: value?.name ?? '',
              billTypeRef: value,
            ),
          ),
          catalogField(
            label: '结算方式',
            current: terms.settleModeRef ??
                CatalogRef.fromName(terms.settleMode),
            options: bundle.settleMethods,
            write: (value) => terms.copyWith(
              settleMode: value?.name ?? '',
              settleModeRef: value,
              formula: '',
              formulaRef: null,
            ),
          ),
          field(
            '结算比例',
            terms.displayRatio,
            (value) => terms.copyWith(settleRatio: value),
          ),
          field(
            '结算单价',
            terms.displayUnitPrice,
            (value) => terms.copyWith(settleUnitPrice: value),
          ),
        ], columns: topColumns),
        _fieldGrid(wide, [
          catalogField(
            label: '计算公式',
            current: terms.formulaRef ?? CatalogRef.fromName(terms.formula),
            options: formulaOptions,
            metaOf: (item) => item.formulaExpression.isEmpty
                ? null
                : item.formulaExpression,
            write: (value) => terms.copyWith(
              formula: value?.name ?? value?.formulaExpression ?? '',
              formulaRef: value,
            ),
          ),
          _settleStringSelectField(
            label: '发票类型',
            value: terms.invoiceType,
            options: kProposalInvoiceTypes,
            enabled: enabled,
            onSelected: (value) =>
                onChanged(terms.copyWith(invoiceType: value ?? '')),
          ),
          _settleStringSelectField(
            label: '税率',
            value: terms.taxRate,
            options: kProposalTaxRates,
            enabled: enabled,
            onSelected: (value) =>
                onChanged(terms.copyWith(taxRate: value ?? '')),
          ),
          dateField(
            '生效时间',
            terms.effectiveTime,
            'effective',
            (value) => terms.copyWith(effectiveTime: value),
          ),
          dateField(
            '失效时间',
            terms.expireTime,
            'expire',
            (value) => terms.copyWith(expireTime: value),
          ),
        ], columns: 5),
        if (includeParties)
          _fieldGrid(wide, [
            field(
              '对方主体',
              terms.counterparty,
              (value) => terms.copyWith(counterparty: value),
            ),
            field(
              '我方主体',
              terms.ourParty,
              (value) => terms.copyWith(ourParty: value),
            ),
          ], columns: 2),
      ],
    );
  }

  Widget _settleStringSelectField({
    required String label,
    required String value,
    required List<String> options,
    required bool enabled,
    required ValueChanged<String?> onSelected,
  }) {
    final current = value.trim();
    final values = [
      if (current.isNotEmpty && !options.contains(current)) current,
      ...options,
    ];
    return ProposalField(
      label: label,
      child: !enabled
          ? _readonlySelectedText(current, maxLines: 3)
          : ProposalSelectField<String>(
              value: current.isEmpty ? null : current,
              title: label,
              hint: '请选择',
              searchable: true,
              options: [
                for (final item in values)
                  ProposalSelectOption(value: item, label: item),
              ],
              onSelected: onSelected,
            ),
    );
  }

  // ignore: unused_element
  Widget _productAssetsCard() {
    final files = _onlineProductFiles();
    final enabled = _canEditProductFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showProductTemplates) ...[
          Row(
            children: [
              const Text(
                '产品模板',
                style: TextStyle(
                  color: ProposalPalette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (_importTemplatesLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else
                TextButton(
                  onPressed: _loadImportTemplates,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: ProposalPalette.purpleDeep,
                  ),
                  child: const Text('刷新'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_importTemplatesError != null && _importTemplates.isEmpty)
            Text(
              _importTemplatesError!,
              style: const TextStyle(
                color: ProposalPalette.coral,
                fontSize: 12,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in _importTemplates)
                  _ProposalTemplateChip(
                    item: item,
                    onTap: () => unawaited(_downloadImportTemplate(item)),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          const Text(
            '与提案审批相同：数商 / 运营商 / 出行-订阅 / 出行-权益金 / 民营。',
            style: TextStyle(color: ProposalPalette.text3, fontSize: 11),
          ),
          const SizedBox(height: 16),
        ],
        ProposalField(
          label: '上线产品文件',
          source: '提交人上传',
          tone: proposalFieldTone(enabled: enabled, source: '提交人上传'),
          child: _dropTarget(
            enabled: enabled && !_uploadingProductFile,
            dragging: _draggingProduct,
            onHover: (hover) => setState(() => _draggingProduct = hover),
            onDrop: _onProductFilesDropped,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: _draggingProduct
                    ? Border.all(color: ProposalPalette.purple, width: 1.4)
                    : null,
                color: _draggingProduct
                    ? ProposalPalette.purpleSoft.withValues(alpha: 0.35)
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.all(_draggingProduct ? 6 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (files.isEmpty)
                      InkWell(
                        onTap: enabled && !_uploadingProductFile
                            ? () => unawaited(_pickOnlineProductFiles())
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration:
                              proposalInputDecoration(
                                hint: _uploadingProductFile
                                    ? '上传中…'
                                    : '点击选择文件，最多 5 个',
                                readOnly: !enabled,
                                tone: proposalFieldTone(
                                  enabled: enabled,
                                  source: '提交人上传',
                                ),
                              ).copyWith(
                                suffixIcon: Icon(
                                  _uploadingProductFile
                                      ? Icons.hourglass_top_rounded
                                      : Icons.upload_file_outlined,
                                  size: 18,
                                  color: enabled
                                      ? ProposalPalette.purple
                                      : ProposalPalette.text3,
                                ),
                              ),
                          child: Text(
                            _uploadingProductFile
                                ? '上传中…'
                                : (enabled
                                      ? (_supportsDesktopDrop
                                            ? '点击选择或拖拽上线产品文件'
                                            : '点击选择上线产品文件')
                                      : '由提交人上传'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: ProposalPalette.text3,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      for (var i = 0; i < files.length; i++)
                        _OnlineProductFileTile(
                          file: files[i],
                          opening:
                              _openingProductFile ==
                              '${files[i]['fileName'] ?? files[i]['objectKey'] ?? ''}'
                                  .trim(),
                          downloading:
                              _downloadingProductFile ==
                              '${files[i]['fileName'] ?? files[i]['objectKey'] ?? ''}'
                                  .trim(),
                          canRemove: enabled,
                          onOpen: () =>
                              unawaited(_openOnlineProductFile(files[i])),
                          onDownload: () =>
                              unawaited(_downloadOnlineProductFile(files[i])),
                          onRemove: () => _removeOnlineProductFile(i),
                        ),
                      if (enabled && files.length < _maxProductFiles)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _uploadingProductFile
                                ? null
                                : () => unawaited(_pickOnlineProductFiles()),
                            icon: const Icon(Icons.add, size: 16),
                            label: Text(
                              _uploadingProductFile ? '上传中…' : '继续上传',
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _supportsDesktopDrop
                          ? '支持 PDF / Word / Excel / PPT / zip，单个不超过 20MB。PC 可拖拽到此处。'
                          : '支持 PDF / Word / Excel / PPT，单个不超过 20MB。',
                      style: const TextStyle(
                        color: ProposalPalette.text3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _contractEditFooter(String key) {
    final edit = proposalIntakeContractEdit(_form, key);
    if (edit == null) return null;
    return InkWell(
      onTap: () => unawaited(_showContractDiff(key, edit)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(
              Icons.difference_outlined,
              size: 16,
              color: ProposalPalette.amber,
            ),
            const SizedBox(width: 6),
            Text(
              '已改过抓取内容，点击对照合同原文',
              style: const TextStyle(
                fontSize: 11,
                color: ProposalPalette.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContractDiff(
    String key,
    ProposalContractFieldEdit edit,
  ) async {
    final label = _contractEditLabel(key);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('查看「$label」改动'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '合同匹配原文',
              style: TextStyle(
                fontSize: 12,
                color: ProposalPalette.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              edit.original.isEmpty ? '（空）' : edit.original,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            const Text(
              '确认后的内容',
              style: TextStyle(
                fontSize: 12,
                color: ProposalPalette.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              edit.current.isEmpty ? '（空）' : edit.current,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _contractEditLabel(String key) {
    const labels = <String, String>{
      'purchaseNo': '采购合同编号',
      'purchaseName': '采购合同名称',
      'purchaseSignDate': '采购合同签署时间',
      'purchaseOurParty': '采购合同我方签约主体',
      'purchaseCounterparty': '采购合同对方签约主体',
      'purchaseValidPeriod': '采购合同有效期',
      'purchaseCoreTerms': '采购合同核心条款',
      'salesNo': '销售合同编号',
      'salesName': '销售合同名称',
      'salesSignDate': '销售合同签署时间',
      'salesOurParty': '销售合同我方签约主体',
      'salesCounterparty': '销售合同对方签约主体',
      'salesValidPeriod': '销售合同有效期',
      'salesCoreTerms': '销售合同核心条款',
      'supplierPolicy': '供货商政策',
      'channelPolicy': '渠道政策',
      'supplySettleMode': '供给侧结算模式',
      'supplySettleCycle': '供给侧结算周期',
      'supplyPayer': '供给侧付款主体',
      'supplyPayAccount': '供给侧付款账户',
      'channelSettleMode': '渠道侧结算模式',
      'channelSettleCycle': '渠道侧结算周期',
      'channelPayee': '渠道侧收款主体',
      'channelReceiveAccount': '渠道侧收款账户',
    };
    return labels[key] ?? key;
  }

  static const _unsignedFileExts = <String>['pdf', 'doc', 'docx'];
  static const _maxUnsignedFileBytes = 20 * 1024 * 1024;

  bool _allowedUnsignedFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return false;
    return _unsignedFileExts.contains(name.substring(dot + 1).toLowerCase());
  }

  String _unsignedFileMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pickUnsignedFile(String prefix) async {
    if (!_canEditMarket || _uploadingContractPrefix != null) return;
    setState(() => _uploadingContractPrefix = prefix);
    try {
      final group = XTypeGroup(label: '合同文件', extensions: _unsignedFileExts);
      XFile? picked;
      try {
        picked = await openFile(acceptedTypeGroups: [group]);
      } catch (_) {
        picked = await openFile();
      }
      if (picked == null) return;
      await _ingestUnsignedFile(prefix, picked);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingContractPrefix = null);
    }
  }

  Future<void> _onUnsignedFileDropped(
    String prefix,
    DropDoneDetails detail,
  ) async {
    if (!_canEditMarket || _uploadingContractPrefix != null) return;
    setState(() {
      _uploadingContractPrefix = prefix;
      _draggingUnsignedPrefix = null;
    });
    try {
      final picked = await _xfilesFromDrop(detail);
      if (picked.isEmpty) {
        widget.onError('请拖入文件（不支持文件夹）');
        return;
      }
      await _ingestUnsignedFile(prefix, picked.first);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '拖拽上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingContractPrefix = null);
    }
  }

  Future<void> _ingestUnsignedFile(String prefix, XFile picked) async {
    final name = picked.name.isEmpty ? 'contract.pdf' : picked.name;
    if (!_allowedUnsignedFile(name)) {
      widget.onError('请上传 PDF 或 Word 文件');
      return;
    }
    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxUnsignedFileBytes) {
      widget.onError('$name 超过 20MB 限制');
      return;
    }
    final uploaded = await widget.service.uploadFile(
      bytes: bytes,
      fileName: name,
      mimeType: _unsignedFileMime(name),
    );
    if (uploaded.objectKey.isEmpty && uploaded.url.isEmpty) {
      throw Exception('未返回文件地址');
    }
    if (!mounted) return;
    final form = Map<String, dynamic>.from(_form)
      ..['${prefix}FileName'] = uploaded.fileName
      ..['${prefix}ObjectKey'] = uploaded.objectKey
      ..['${prefix}FileUrl'] = uploaded.url
      ..['${prefix}FileSize'] = uploaded.sizeBytes
      ..['${prefix}No'] = uploaded.fileName;
    final review = proposalIntakeClearContractReview(_review, prefix: prefix);
    setState(() {
      _dirty = true;
      _fieldEpoch++;
      _row = _row.copyWith(
        form: form,
        review: review,
        status: _statusAfterEdit,
      );
    });
    widget.onChanged(_row);
    showProposalCenterToast(context, '已上传「${uploaded.fileName}」');
  }

  void _clearUnsignedFile(String prefix) {
    if (!_canEditMarket) return;
    final form = Map<String, dynamic>.from(_form)
      ..['${prefix}FileName'] = ''
      ..['${prefix}ObjectKey'] = ''
      ..['${prefix}FileUrl'] = ''
      ..['${prefix}FileSize'] = null
      ..['${prefix}No'] = '';
    final review = proposalIntakeClearContractReview(_review, prefix: prefix);
    setState(() {
      _dirty = true;
      _fieldEpoch++;
      _row = _row.copyWith(
        form: form,
        review: review,
        status: _statusAfterEdit,
      );
    });
    widget.onChanged(_row);
  }

  Future<void> _openUnsignedFile(String prefix) async {
    final name = _text('${prefix}FileName').trim();
    final objectKey = _text('${prefix}ObjectKey').trim();
    final url = _text('${prefix}FileUrl').trim();
    if (name.isEmpty && objectKey.isEmpty && url.isEmpty) {
      widget.onError('还没有上传合同文件');
      return;
    }
    if (_openingContractPrefix != null || _downloadingContractPrefix != null) {
      return;
    }
    setState(() => _openingContractPrefix = prefix);
    try {
      await openXflowAttachment(
        context: context,
        service: XflowService(session: widget.session),
        item: {
          'fileName': name.isEmpty ? '合同文件' : name,
          'objectKey': objectKey,
          'url': url,
          'mimeType': _unsignedFileMime(name),
        },
        preferPreview: true,
      );
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '无法打开合同文件'));
    } finally {
      if (mounted) setState(() => _openingContractPrefix = null);
    }
  }

  Future<void> _downloadUnsignedFile(String prefix) async {
    final name = _text('${prefix}FileName').trim();
    final objectKey = _text('${prefix}ObjectKey').trim();
    final url = _text('${prefix}FileUrl').trim();
    if (name.isEmpty && objectKey.isEmpty && url.isEmpty) {
      widget.onError('还没有上传合同文件');
      return;
    }
    if (_openingContractPrefix != null || _downloadingContractPrefix != null) {
      return;
    }
    setState(() => _downloadingContractPrefix = prefix);
    try {
      await downloadXflowAttachment(
        context: context,
        service: XflowService(session: widget.session),
        item: {
          'fileName': name.isEmpty ? '合同文件' : name,
          'objectKey': objectKey,
          'url': url,
          'mimeType': _unsignedFileMime(name),
        },
      );
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '下载失败'));
    } finally {
      if (mounted) setState(() => _downloadingContractPrefix = null);
    }
  }

  Widget _unsignedFileField(String prefix) {
    final enabled = _canEditMarket;
    final uploading = _uploadingContractPrefix == prefix;
    final opening = _openingContractPrefix == prefix;
    final downloading = _downloadingContractPrefix == prefix;
    final dragging = _draggingUnsignedPrefix == prefix;
    final name = _text('${prefix}FileName');
    final canOpen = name.isNotEmpty;
    final picker = name.isEmpty
        ? InkWell(
            onTap: enabled && !uploading
                ? () => unawaited(_pickUnsignedFile(prefix))
                : null,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration:
                  proposalInputDecoration(
                    hint: uploading ? '上传中…' : '选择 PDF / Word 文件',
                    readOnly: !enabled,
                  ).copyWith(
                    suffixIcon: Icon(
                      uploading
                          ? Icons.hourglass_top_rounded
                          : Icons.upload_file_outlined,
                      size: 18,
                      color: enabled
                          ? ProposalPalette.purple
                          : ProposalPalette.text3,
                    ),
                  ),
              child: Text(
                uploading
                    ? '上传中…'
                    : (_supportsDesktopDrop
                          ? '点击选择或拖拽未签合同 PDF / Word'
                          : '点击选择未签合同 PDF / Word'),
                style: const TextStyle(
                  fontSize: 13,
                  color: ProposalPalette.text3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        : InkWell(
            onTap: opening ? null : () => unawaited(_openUnsignedFile(prefix)),
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: proposalInputDecoration(readOnly: true),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: ProposalPalette.purple,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ProposalPalette.purpleDeep,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (enabled)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => _clearUnsignedFile(prefix),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: ProposalPalette.text3,
                    ),
                ],
              ),
            ),
          );
    return _FullWidthField(
      child: ProposalField(
        label: '上传合同文件',
        required: true,
        source: canOpen ? '未签合同 · 可查看下载' : '未签合同',
        tone: proposalFieldTone(
          enabled: enabled,
          source: canOpen ? '未签合同 · 可查看下载' : '未签合同',
        ),
        trailing: canOpen
            ? Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: opening || downloading
                        ? null
                        : () => unawaited(_openUnsignedFile(prefix)),
                    icon: Icon(
                      opening
                          ? Icons.hourglass_top_rounded
                          : Icons.visibility_outlined,
                      size: 16,
                    ),
                    label: Text(opening ? '打开中…' : '查看合同'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: ProposalPalette.purpleDeep,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: opening || downloading
                        ? null
                        : () => unawaited(_downloadUnsignedFile(prefix)),
                    icon: Icon(
                      downloading
                          ? Icons.hourglass_top_rounded
                          : Icons.download_outlined,
                      size: 16,
                    ),
                    label: Text(downloading ? '下载中…' : '下载合同'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: ProposalPalette.purpleDeep,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              )
            : null,
        child: _dropTarget(
          enabled: enabled && !uploading && name.isEmpty,
          dragging: dragging,
          onHover: (hover) =>
              setState(() => _draggingUnsignedPrefix = hover ? prefix : null),
          onDrop: (detail) => _onUnsignedFileDropped(prefix, detail),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: dragging
                  ? Border.all(color: ProposalPalette.purple, width: 1.4)
                  : null,
              color: dragging
                  ? ProposalPalette.purpleSoft.withValues(alpha: 0.35)
                  : null,
            ),
            child: picker,
          ),
        ),
      ),
    );
  }

  Widget _moduleReview({
    required String title,
    required String description,
    required String keyName,
    required String buttonLabel,
    bool locked = false,
    bool compact = false,
    String? progress,
  }) {
    final done = _review[keyName] == true;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 0 : 14, top: compact ? 4 : 0),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFBF9FD), ProposalPalette.purpleSoft],
        ),
        border: Border.all(
          color: done
              ? const Color(0xFFB9DDBE)
              : locked
              ? const Color(0xFFE8E1ED)
              : const Color(0xFFDDD1E8),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          final reviewerCanAct = _moduleReviewEnabled(keyName);
          final canApprove = reviewerCanAct && !locked && !done;
          final canReject = reviewerCanAct;
          final action = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: ValueKey('proposal-module-approve-$keyName'),
                onPressed: canApprove
                    ? () => unawaited(_setReview(keyName, true))
                    : null,
                child: Text(
                  done ? '已复核' : buttonLabel,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              if (canReject)
                OutlinedButton(
                  key: ValueKey('proposal-module-reject-$keyName'),
                  onPressed: () => unawaited(_rejectReview(keyName)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ProposalPalette.coral,
                    side: const BorderSide(color: Color(0xFFE7C2B0)),
                  ),
                  child: const Text('驳回', style: TextStyle(fontSize: 10)),
                ),
            ],
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF3D3546),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF82778D), fontSize: 10),
              ),
              if (!done && !locked && progress != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '逐条复核已全部完成，请点击右侧按钮做本板块最后确认。',
                    style: TextStyle(
                      color: ProposalPalette.purpleDeep,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!done && locked && canReject)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '发现问题可直接点「驳回」，不必先逐条点完复核。通过本板块仍需先完成逐条复核。',
                    style: TextStyle(
                      color: ProposalPalette.coral,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          );
          final icon = Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: done ? ProposalPalette.greenSoft : const Color(0xFFE9DFF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check : Icons.fact_check_outlined,
              color: done ? ProposalPalette.green : ProposalPalette.purpleDeep,
              size: 18,
            ),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(child: copy),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ProposalStatusChip(
                    label: done ? '板块审核完成' : progress,
                    kind: done ? ProposalChipKind.ok : ProposalChipKind.purple,
                  ),
                ],
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(child: copy),
              if (progress != null) ...[
                ProposalStatusChip(
                  label: done ? '板块审核完成' : progress,
                  kind: done ? ProposalChipKind.ok : ProposalChipKind.purple,
                ),
                const SizedBox(width: 8),
              ],
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _financeItem((String, String) field) {
    final key = field.$1;
    final textual =
        key == 'financeRemark' ||
        key.contains('Mode') ||
        key.contains('Cycle') ||
        key.contains('Payer') ||
        key.contains('Payee') ||
        key.contains('Account');
    final source = switch (key) {
      'revenue' => '已确认收入 · 核销/结算口径',
      'invoiceAmount' => '已开票金额 · 与收入差额为开票缺口',
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ProposalPalette.borderSoft)),
      ),
      child: textual
          ? _textField(
              field.$2,
              key,
              resetReview: 'financeCompleted',
              reviewSection: 'financeItem:$key',
              reviewLabel: _financeReviewLabel,
            )
          : _numberField(
              field.$2,
              key,
              source: source,
              resetReview: 'financeCompleted',
              reviewSection: 'financeItem:$key',
              reviewLabel: _financeReviewLabel,
            ),
    );
  }

  Widget _fieldGrid(bool wide, List<Widget> fields, {int? columns}) =>
      LayoutBuilder(
        builder: (_, constraints) {
          final resolved =
              columns ??
              (!wide
                  ? 1
                  : constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 660
                  ? 2
                  : 1);
          final rows = _groupFields(fields, resolved);
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: ProposalPalette.borderSoft),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var row = 0; row < rows.length; row++)
                  _gridRow(
                    rows[row],
                    resolved,
                    lastRow: row == rows.length - 1,
                  ),
              ],
            ),
          );
        },
      );

  Widget _gridRow(List<Widget> cells, int columns, {required bool lastRow}) {
    if (cells.length == 1) {
      return _gridCell(
        child: cells.first,
        lastInRow: true,
        lastRow: lastRow,
        compact: columns == 1,
      );
    }
    final filler = cells.length < columns;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cells.length; index++)
            Expanded(
              child: _gridCell(
                child: cells[index],
                lastInRow: index == cells.length - 1 && !filler,
                lastRow: lastRow,
              ),
            ),
          if (filler)
            Expanded(
              flex: columns - cells.length,
              child: _gridCell(lastInRow: true, lastRow: lastRow),
            ),
        ],
      ),
    );
  }

  /// 按列数切分字段，[_FullWidthField] 独占一行。
  List<List<Widget>> _groupFields(List<Widget> fields, int columns) {
    final rows = <List<Widget>>[];
    var current = <Widget>[];
    for (final field in fields) {
      if (field is _FullWidthField) {
        if (current.isNotEmpty) {
          rows.add(current);
          current = <Widget>[];
        }
        rows.add([field]);
        continue;
      }
      current.add(field);
      if (current.length == columns) {
        rows.add(current);
        current = <Widget>[];
      }
    }
    if (current.isNotEmpty) rows.add(current);
    return rows;
  }

  Widget _gridCell({
    Widget? child,
    required bool lastInRow,
    required bool lastRow,
    bool compact = false,
  }) => SizedBox(
    width: double.infinity,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 56 : 90),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: lastInRow
                ? BorderSide.none
                : const BorderSide(color: ProposalPalette.borderSoft),
            bottom: lastRow
                ? BorderSide.none
                : const BorderSide(color: ProposalPalette.borderSoft),
          ),
        ),
        child: child,
      ),
    ),
  );

  DateTime? _parseDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final match = RegExp(
      r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})',
    ).firstMatch(text);
    if (match == null) return null;
    return DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  String _fmtDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Widget _datePickerTheme(Widget? child) {
    const accent = ProposalPalette.purple;
    const accentSoft = ProposalPalette.purpleSoft;
    const dayColor = ProposalPalette.text2;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: accent,
          onPrimary: Colors.white,
          secondary: accent,
          onSecondary: Colors.white,
          secondaryContainer: accentSoft,
          onSecondaryContainer: accent,
          surface: Colors.white,
          onSurface: dayColor,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          headerBackgroundColor: accentSoft,
          headerForegroundColor: accent,
          rangeSelectionBackgroundColor: accentSoft,
          rangeSelectionOverlayColor: WidgetStatePropertyAll(
            accent.withValues(alpha: 0.08),
          ),
          weekdayStyle: const TextStyle(
            color: dayColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return null;
          }),
          dayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            if (states.contains(WidgetState.disabled)) {
              return ProposalPalette.text3;
            }
            return dayColor;
          }),
          todayForegroundColor: const WidgetStatePropertyAll(accent),
          todayBackgroundColor: const WidgetStatePropertyAll(accentSoft),
          todayBorder: const BorderSide(color: accent),
          confirmButtonStyle: TextButton.styleFrom(foregroundColor: accent),
          cancelButtonStyle: TextButton.styleFrom(foregroundColor: accent),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Future<DateTime?> _pickDate(DateTime? current) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => _datePickerTheme(child),
    );
  }

  Future<DateTimeRange?> _pickDateRange({DateTime? start, DateTime? end}) {
    final now = DateTime.now();
    final initialStart = start ?? now;
    final initialEnd = end ?? initialStart;
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialEnd.isBefore(initialStart) ? initialStart : initialEnd,
      ),
      helpText: '选择项目周期',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
      builder: (context, child) => _datePickerTheme(child),
    );
  }

  Widget _datePickerField({
    required String fieldKey,
    required String label,
    required String display,
    required bool empty,
    required bool enabled,
    required VoidCallback? onTap,
    String? source,
    String? reviewSection,
    String reviewLabel = '复核',
    String hint = '请选择日期',
  }) {
    final tone = proposalFieldTone(enabled: enabled, source: source);
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        source: source,
        tone: tone,
        footer: _contractEditFooter(fieldKey),
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(empty ? '' : display),
      );
    }
    return ProposalField(
      label: label,
      source: source,
      tone: tone,
      footer: _contractEditFooter(fieldKey),
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: InkWell(
        key: ValueKey('date-$fieldKey'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration:
              proposalInputDecoration(
                hint: hint,
                readOnly: !enabled,
                tone: tone,
              ).copyWith(
                suffixIcon: Icon(
                  enabled
                      ? Icons.calendar_today_outlined
                      : Icons.lock_outline_rounded,
                  size: 16,
                  color: ProposalPalette.text3,
                ),
              ),
          child: Text(
            empty ? hint : display,
            style: TextStyle(
              fontSize: 13,
              color: empty || !enabled
                  ? ProposalPalette.text3
                  : ProposalPalette.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField(
    String label,
    String key, {
    String? source,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    bool? writable,
  }) {
    final enabled = _fillEnabled(writable);
    final raw = _text(key).trim();
    final parsed = _parseDate(raw);
    return _datePickerField(
      fieldKey: key,
      label: label,
      display: parsed == null ? raw : _fmtDate(parsed),
      empty: raw.isEmpty,
      enabled: enabled,
      source: source,
      reviewSection: reviewSection,
      reviewLabel: reviewLabel,
      onTap: enabled
          ? () async {
              final picked = await _pickDate(parsed);
              if (picked != null) {
                _set(key, _fmtDate(picked), resetReview: resetReview);
              }
            }
          : null,
    );
  }

  Widget _textField(
    String label,
    String key, {
    bool required = false,
    int maxLines = 1,
    String? source,
    String? hint,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    bool? writable,
  }) {
    final enabled = _fillEnabled(writable);
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final footer = _contractEditFooter(key);
    final multiline = maxLines > 1;
    final Widget input = _showSelectedAsText
        ? _readonlySelectedText(_text(key), maxLines: maxLines)
        : TextFormField(
            key: ValueKey('$key-${_row.id}-$_fieldEpoch'),
            initialValue: _text(key),
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? null : 1,
            keyboardType: multiline ? TextInputType.multiline : null,
            enabled: enabled,
            readOnly: !enabled,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: enabled ? ProposalPalette.text : ProposalPalette.text3,
            ),
            onChanged: enabled
                ? (value) => _set(
                    key,
                    value,
                    resetReview: resetReview,
                    rebuild: key == 'proposalName',
                  )
                : null,
            decoration: proposalInputDecoration(
              hint: hint,
              readOnly: !enabled,
              tone: tone,
            ),
          );
    final field = ProposalField(
      label: label,
      required: required,
      source: source,
      tone: tone,
      footer: footer,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: input,
    );
    return multiline ? _FullWidthField(child: field) : field;
  }

  Widget _numberField(
    String label,
    String key, {
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    String? source,
    bool? writable,
  }) {
    final enabled = _fillEnabled(writable);
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final footer = _contractEditFooter(key);
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        source: source,
        tone: tone,
        footer: footer,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(_text(key)),
      );
    }
    return ProposalField(
      label: label,
      source: source,
      tone: tone,
      footer: footer,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: TextFormField(
        key: ValueKey('$key-${_row.id}-$_fieldEpoch'),
        initialValue: _text(key),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        enabled: enabled,
        readOnly: !enabled,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: enabled ? ProposalPalette.text : ProposalPalette.text3,
        ),
        onChanged: enabled
            ? (value) => _set(
                key,
                value.trim().isEmpty ? null : double.tryParse(value) ?? 0,
                resetReview: resetReview,
                rebuild: false,
              )
            : null,
        decoration: proposalInputDecoration(readOnly: !enabled, tone: tone),
      ),
    );
  }

  Widget _catalogDropdownField(
    String label, {
    required CatalogRef? current,
    required List<CatalogRef> options,
    required ValueChanged<CatalogRef?> onSelected,
    bool required = false,
    bool enabled = true,
    bool searchable = true,
    String? hint,
    String? emptyText,
    bool remoteSearch = false,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    ValueChanged<String>? onQueryChanged,
  }) {
    final canEdit = _fillEnabled(null) && enabled;
    final tone = proposalFieldTone(enabled: canEdit);
    final selected = _selectedCatalog(current, options);
    final values = _withCurrent(options, selected);
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        required: required,
        tone: tone,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(selected?.label ?? ''),
      );
    }
    return ProposalField(
      label: label,
      required: required,
      tone: tone,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: ProposalSelectField<CatalogRef>(
        value: selected == null || selected.isEmpty ? null : selected,
        title: label,
        hint: hint ?? (values.isEmpty ? '暂无选项' : '请选择或输入搜索'),
        searchable: searchable,
        options: [
          for (final item in values)
            ProposalSelectOption(
              value: item,
              label: item.label,
              meta: item.code.isEmpty || item.code == item.name
                  ? null
                  : item.code,
            ),
        ],
        onQueryChanged: onQueryChanged,
        remoteOptions: remoteSearch || onQueryChanged != null,
        emptyText: emptyText,
        onSelected: canEdit ? onSelected : null,
      ),
    );
  }

  Widget _dropdownField(
    String label,
    String key,
    List<String> options, {
    bool required = false,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    String? addLabel,
    bool? writable,
    ValueChanged<String?>? onSelected,
  }) {
    final enabled = _fillEnabled(writable);
    final tone = proposalFieldTone(enabled: enabled);
    final current = _text(key);
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        required: required,
        tone: tone,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(current),
      );
    }
    final values = [...options];
    if (current.isNotEmpty && !values.contains(current)) {
      values.insert(0, current);
    }
    return ProposalField(
      label: label,
      required: required,
      tone: tone,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: ProposalSelectField<String>(
        value: current.isEmpty ? null : current,
        title: label,
        hint: values.isEmpty && addLabel == null ? '请先在管理端配置选项' : '请选择或输入搜索',
        searchable: true,
        onAdd: addLabel == null || !enabled
            ? null
            : () => unawaited(
                _addDropdownValue(key, addLabel, resetReview: resetReview),
              ),
        addLabel: addLabel,
        options: [
          for (final value in values)
            ProposalSelectOption(value: value, label: value),
        ],
        onSelected: enabled
            ? (onSelected ??
                  (value) => _set(key, value ?? '', resetReview: resetReview))
            : null,
      ),
    );
  }

  Widget _configuredPresidentsField() {
    final names = widget.options.presidentDisplayNames(widget.people);
    return ProposalField(
      label: '最终确认人',
      tone: ProposalFieldTone.auto,
      child: Text(
        names.isEmpty ? '请在管理后台「提案录入选项」中配置最终确认人' : names,
        style: TextStyle(
          color: names.isEmpty ? ProposalPalette.coral : ProposalPalette.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _personField(
    String label,
    String key, {
    required String positionIncludes,
    String? reviewSection,
    String reviewLabel = '复核',
    String? badge,
    bool? writable,
    bool required = false,
  }) {
    final enabled = _fillEnabled(writable);
    final tone = proposalFieldTone(enabled: enabled, source: badge);
    final preferredIds = {
      for (final person in widget.people)
        if (person.positionName.contains(positionIncludes)) person.userId,
    };
    final source = [
      ...widget.people.where((person) => preferredIds.contains(person.userId)),
      ...widget.people.where((person) => !preferredIds.contains(person.userId)),
    ];
    final currentId = int.tryParse(_text('${key}UserId'));
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        required: required,
        source: badge,
        tone: tone,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(_text(key)),
      );
    }
    return ProposalField(
      label: label,
      required: required,
      source: badge,
      tone: tone,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: ProposalSelectField<int>(
        value: currentId,
        title: label,
        hint: source.isEmpty ? '暂无人员，请确认通讯录' : '输入姓名或岗位搜索',
        searchable: true,
        requireKeyword: true,
        options: [
          for (final person in source)
            ProposalSelectOption(
              value: person.userId,
              label: person.name,
              meta: [
                person.positionName,
                person.departmentName,
                person.username,
              ].where((item) => item.isNotEmpty).join(' · '),
            ),
        ],
        onSelected: enabled
            ? (userId) {
                final selected = source
                    .where((person) => person.userId == userId)
                    .firstOrNull;
                final form = Map<String, dynamic>.from(_form)
                  ..[key] = selected?.name ?? ''
                  ..['${key}UserId'] = selected?.userId;
                setState(() {
                  _dirty = true;
                  _row = _row.copyWith(form: form, status: _statusAfterEdit);
                });
                widget.onChanged(_row);
              }
            : null,
      ),
    );
  }

  Widget _businessCostField({bool wide = true}) {
    if (_businessCostSealed) {
      return const ProposalField(
        label: '业务成本',
        tone: ProposalFieldTone.locked,
        child: Text(
          '已加密上锁，负责人二不可查看。由市场部负责人一在财务复核时填写。',
          style: TextStyle(
            color: ProposalPalette.text2,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final names = _form['businessCostItems'] is List
        ? [
            for (final item in _form['businessCostItems'] as List)
              if ('$item'.trim().isNotEmpty) '$item'.trim(),
          ]
        : const <String>[];
    if (!_canEditBusinessCost && names.isEmpty) {
      return const ProposalField(
        label: '业务成本',
        tone: ProposalFieldTone.locked,
        child: Text(
          '由市场部负责人一在财务复核时填写',
          style: TextStyle(
            color: ProposalPalette.text3,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return _costSelectField(
      label: '业务成本',
      namesKey: 'businessCostItems',
      amountsKey: 'businessCostItemAmounts',
      totalKey: 'businessCost',
      options: widget.options.businessCostItems,
      catalog: widget.options.businessCostItemOptions,
      addLabel: widget.options.costItemSource == 'asset'
          ? null
          : (widget.options.businessCostItems.isEmpty ? null : '新增成本项'),
      writable: _canEditBusinessCost,
      allowDuringReview: true,
      wide: wide,
    );
  }

  Widget _costSelectField({
    required String label,
    required String namesKey,
    required String amountsKey,
    required String totalKey,
    required List<String> options,
    required List<ProposalCostItemOption> catalog,
    String? reviewSection,
    String? addLabel,
    bool? writable,
    bool allowDuringReview = false,
    String settleTermsKey = '',
    bool wide = true,
  }) {
    final enabled = allowDuringReview
        ? (!_isLocked && (writable ?? false))
        : _fillEnabled(writable);
    final tone = proposalFieldTone(enabled: enabled);
    final selectedRaw = _setOf(namesKey);
    final selected = namesKey == 'costItems'
        ? {
            for (final item in selectedRaw)
              proposalProjectCostDisplayName(item),
          }
        : selectedRaw;
    final names = _form[namesKey] is List
        ? [
            for (final item in _form[namesKey] as List)
              if ('$item'.trim().isNotEmpty)
                namesKey == 'costItems'
                    ? proposalProjectCostDisplayName('$item')
                    : '$item'.trim(),
          ]
        : selected.toList();
    final chipOptions = namesKey == 'costItems'
        ? kProposalProjectCostItems
        : options;
    final amounts = proposalCostAmountMap(_form[amountsKey]);
    final total = proposalCostAmountTotal(amounts);
    final settleMap = settleTermsKey.isEmpty
        ? const <String, ProposalFinanceSettleTerms>{}
        : proposalCostSettleTermsMap(_form[settleTermsKey]);
    Widget settleFields(String name) {
      if (settleTermsKey.isEmpty) return const SizedBox.shrink();
      final id = proposalCostAmountId(name, catalog);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _settleTermsGrid(
          wide: wide,
          keyPrefix: '$settleTermsKey-$id',
          terms: proposalCostSettleTermsOf(
            terms: settleMap,
            name: name,
            id: id,
          ),
          enabled: enabled,
          columns: 5,
          syncSource: _primarySyncSource(),
          productSource: 'SUPPLIER',
          onChanged: (terms) => _setCostSettleTerms(
            settleTermsKey: settleTermsKey,
            id: id,
            terms: terms,
          ),
        ),
      );
    }

    Widget amountRows() {
      if (names.isEmpty) return const SizedBox.shrink();
      final withSettle = settleTermsKey.isNotEmpty;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            for (final name in names) ...[
              if (withSettle)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: ProposalPalette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                _costAmountRow(
                  name: name,
                  id: proposalCostAmountId(name, catalog),
                  amount:
                      amounts[proposalCostAmountId(name, catalog)] ??
                      amounts[name] ??
                      0,
                  amountsKey: amountsKey,
                  totalKey: totalKey,
                  enabled: enabled,
                ),
              settleFields(name),
            ],
            if (!withSettle)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '合计 ${_money(total)}',
                    style: const TextStyle(
                      color: ProposalPalette.text2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (_showSelectedAsText) {
      return _FullWidthField(
        child: ProposalField(
          label: label,
          tone: tone,
          trailing: _rowReviewToggle(reviewSection, _financeReviewLabel),
          child: names.isEmpty
              ? _readonlySelectedText('')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final name in names) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          settleTermsKey.isEmpty
                              ? '$name  ${_money(amounts[proposalCostAmountId(name, catalog)] ?? amounts[name] ?? 0)}'
                              : name,
                          style: const TextStyle(
                            color: ProposalPalette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      settleFields(name),
                    ],
                    if (settleTermsKey.isEmpty)
                      Text(
                        '合计 ${_money(total)}',
                        style: const TextStyle(
                          color: ProposalPalette.text2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
        ),
      );
    }

    return _FullWidthField(
      child: ProposalField(
        label: label,
        tone: tone,
        trailing: _rowReviewToggle(reviewSection, _financeReviewLabel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProposalPills(
              options: [
                ...chipOptions,
                ...names.where((value) => !chipOptions.contains(value)),
              ],
              selected: selected,
              enabled: enabled,
              onToggle: (value) {
                if (enabled) {
                  _toggleList(namesKey, value, resetReview: 'financeCompleted');
                }
              },
              onAdd: addLabel == null || !enabled
                  ? null
                  : () => _addOption(
                      namesKey,
                      addLabel,
                      resetReview: 'financeCompleted',
                    ),
            ),
            amountRows(),
          ],
        ),
      ),
    );
  }

  Widget _costAmountRow({
    required String name,
    required String id,
    required double amount,
    required String amountsKey,
    required String totalKey,
    required bool enabled,
  }) {
    final tone = proposalFieldTone(enabled: enabled);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ProposalPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 148,
            child: TextFormField(
              key: ValueKey('$amountsKey-$id-${_row.id}-$_fieldEpoch'),
              initialValue: amount == 0 ? '' : _textFromAmount(amount),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: enabled,
              readOnly: !enabled,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: enabled ? ProposalPalette.text : ProposalPalette.text3,
              ),
              onChanged: enabled
                  ? (value) => _setCostAmount(
                      amountsKey: amountsKey,
                      totalKey: totalKey,
                      id: id,
                      value: value.trim().isEmpty
                          ? null
                          : double.tryParse(value),
                      resetReview: 'financeCompleted',
                    )
                  : null,
              decoration: proposalInputDecoration(
                hint: '预计（万元）',
                readOnly: !enabled,
                tone: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _textFromAmount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  Widget _multiField(
    String label,
    String key,
    List<String> options,
    String? addLabel, {
    String? source,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    bool? writable,
    bool single = false,
  }) {
    final enabled = _fillEnabled(writable);
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final selected = _setOf(key);
    if (_showSelectedAsText) {
      return _FullWidthField(
        child: ProposalField(
          label: label,
          source: source,
          tone: tone,
          trailing: _rowReviewToggle(reviewSection, reviewLabel),
          child: _readonlySelectedText(selected.join('、')),
        ),
      );
    }
    return _FullWidthField(
      child: ProposalField(
        label: label,
        source: source,
        tone: tone,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: ProposalPills(
          options: [
            ...options,
            ..._setOf(key).where((v) => !options.contains(v)),
          ],
          selected: _setOf(key),
          enabled: enabled,
          single: single,
          onToggle: (value) {
            if (enabled) {
              _toggleList(
                key,
                value,
                resetReview: resetReview,
                single: single,
              );
            }
          },
          onAdd: addLabel == null || !enabled
              ? null
              : () => _addOption(
                  key,
                  addLabel,
                  resetReview: resetReview,
                  single: single,
                ),
        ),
      ),
    );
  }
}

/// 在 [_fieldGrid] 中独占一整行的字段（多行文本、多选标签等）。
class _FullWidthField extends StatelessWidget {
  const _FullWidthField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _ProposalTemplateChip extends StatelessWidget {
  const _ProposalTemplateChip({required this.item, required this.onTap});

  final ProposalImportTemplateItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = item.available && item.downloadUrl.isNotEmpty;
    final subtitle = item.profileName.isNotEmpty
        ? item.profileName
        : (enabled ? '可下载' : '暂未提供');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF7F4FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFD9CDE8)
                  : const Color(0xFFE9E2F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled
                    ? Icons.download_outlined
                    : Icons.hourglass_empty_outlined,
                size: 15,
                color: enabled ? ProposalPalette.purple : ProposalPalette.text3,
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? ProposalPalette.text
                          : ProposalPalette.text3,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: ProposalPalette.text3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineProductFileTile extends StatelessWidget {
  const _OnlineProductFileTile({
    required this.file,
    required this.opening,
    required this.downloading,
    required this.canRemove,
    required this.onOpen,
    required this.onDownload,
    required this.onRemove,
  });

  final Map<String, dynamic> file;
  final bool opening;
  final bool downloading;
  final bool canRemove;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = '${file['fileName'] ?? '未命名文件'}'.trim();
    final busy = opening || downloading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF8F6FB),
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          onTap: busy ? null : onOpen,
          leading: Icon(
            busy
                ? Icons.hourglass_top_rounded
                : Icons.insert_drive_file_outlined,
            color: ProposalPalette.purple,
          ),
          title: Text(
            name.isEmpty ? '未命名文件' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            opening
                ? '打开中…'
                : downloading
                ? '下载中…'
                : '查看或下载',
            style: const TextStyle(fontSize: 11, color: ProposalPalette.text3),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '查看',
                onPressed: busy ? null : onOpen,
                icon: const Icon(Icons.visibility_outlined, size: 18),
              ),
              IconButton(
                tooltip: '下载',
                onPressed: busy ? null : onDownload,
                icon: const Icon(Icons.download_outlined, size: 18),
              ),
              if (canRemove)
                IconButton(
                  tooltip: '移除',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettleCatalogBundle {
  const _SettleCatalogBundle({
    this.channels = const [],
    this.billTypes = const [],
    this.settleMethods = const [],
    this.formulas = const [],
  });

  final List<CatalogRef> channels;
  final List<CatalogRef> billTypes;
  final List<CatalogRef> settleMethods;
  final List<CatalogRef> formulas;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
