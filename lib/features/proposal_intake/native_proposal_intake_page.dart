import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import '../xflow/approval_chat_forward.dart';
import '../xflow/approval_chat_share.dart';
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
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final bool showCreate;
  final bool assistantMode;

  @override
  State<NativeProposalIntakePage> createState() =>
      _NativeProposalIntakePageState();
}

class _NativeProposalIntakePageState extends State<NativeProposalIntakePage> {
  late final ProposalIntakeService _service = ProposalIntakeService(
    session: widget.session,
  );
  final _search = TextEditingController();
  _ProposalPage _page = _ProposalPage.list;
  List<ProposalIntakeRow> _rows = const [];
  ProposalIntakeOptions? _options;
  List<ProposalPerson> _people = const [];
  ProposalIntakeRow? _editing;
  bool _loading = true;
  bool _saving = false;
  bool _nextBusy = false;
  String? _error;
  String _statusFilter = '';
  List<ProposalIntakeRow> _actionQueue = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _service.fetchList(
          keyword: widget.assistantMode ? '' : _search.text,
          status: widget.assistantMode ? '' : _statusFilter,
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
      final row = await _service.create(
        form: _defaultForm(),
        review: _defaultReview(),
      );
      if (!mounted) return;
      _openForm(row);
    } catch (error) {
      _toast(friendlyErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatusFilter(String status) async {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    await _load();
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

  String get _currentUserName {
    final fromPeople = _people
        .where((person) => person.userId == widget.session.userId)
        .map((person) => person.name)
        .where((name) => name.isNotEmpty)
        .firstOrNull;
    return fromPeople ?? widget.session.displayName?.trim() ?? '';
  }

  /// 新建提案不预填业务值。填写人固定为当前登录用户。
  Map<String, dynamic> _defaultForm() => {
    'supplies': <String>[],
    'channels': <String>[],
    'profitModes': <String>[],
    'technologyCapabilities': <String>[],
    'outputForms': <String>[],
    'developmentTypes': <String>[],
    'costItems': <String>[],
    'purchaseProducts': <String>[],
    'financeInterfaces': <String, dynamic>{},
    if (widget.session.userId > 0) ...{
      'marketOwner2': _currentUserName,
      'marketOwner2UserId': widget.session.userId,
    },
  };

  Map<String, dynamic> _defaultReview() => {
    'marketCompleted': false,
    'technologyCompleted': false,
    'financeInterfaceCompleted': false,
    'financeCompleted': false,
    'purchaseContractCompleted': false,
    'salesContractCompleted': false,
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
    setState(() => _loading = true);
    try {
      final detail = await _service.fetchDetail(row.id);
      await _refreshLookups();
      if (mounted) _openForm(detail);
    } catch (error) {
      _toast(friendlyErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openForm(ProposalIntakeRow row) {
    setState(() {
      _editing = row;
      _page = _ProposalPage.form;
    });
    widget.onChromeChanged?.call(TaskShellChrome(onBack: _backToList));
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

  void _backToList() {
    setState(() {
      _page = _ProposalPage.list;
      _editing = null;
    });
    widget.onChromeChanged?.call(const TaskShellChrome());
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    if (_page == _ProposalPage.form && _editing != null && _options != null) {
      return ProposalIntakeForm(
        key: ValueKey(_editing!.id),
        row: _editing!,
        session: widget.session,
        options: _options!,
        people: _people,
        contracts: const [],
        saving: _saving,
        service: _service,
        onChanged: (row) => _editing = row,
        onSaved: (row) {
          setState(() => _editing = row);
          _toast('已保存');
        },
        onSubmit: (row) {
          setState(() => _editing = row);
          _toast(
            row.status == 'done'
                ? '提案已通过'
                : row.status == 'pending_president'
                ? '已通知最终人'
                : '已更新',
          );
        },
        onError: (message) => _toast(message, error: true),
        onDeleted: _backToList,
        onNext: widget.assistantMode
            ? () =>
                  unawaited(_goNext(fromId: _editing!.id, afterDecision: false))
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
            ? _actionQueue.where((item) => item.id != _editing!.id).length
            : 0,
        nextBusy: _nextBusy,
      );
    }
    return _buildList();
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
      onSubmitted: (_) => unawaited(_load()),
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
            label: const Text('新建提案'),
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
    return ColoredBox(
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ListMessage(
                      icon: Icons.error_outline,
                      title: '加载失败',
                      message: _error!,
                    )
                  : _rows.isEmpty
                  ? _ListMessage(
                      icon: Icons.assignment_outlined,
                      title: '暂无提案',
                      message: widget.showCreate
                          ? '点击右上角「新建提案」开始录入'
                          : '当前没有需要你处理的提案',
                    )
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        return _ProposalListTile(
                          row: row,
                          initiatorName: row.initiatorDisplayName(_people),
                          canDelete: row.canDeleteBy(widget.session.userId),
                          compact: compact,
                          onTap: () => _openExisting(row),
                          onPeople: () => unawaited(_showStakeholders(row)),
                          onForward: () => unawaited(_forwardRow(row)),
                          onDelete: () => unawaited(_confirmDelete(row)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
                      row.title.isEmpty ? '未命名销售业务提案' : row.title,
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
                        visualDensity: VisualDensity.compact,
                        onPressed: onForward,
                        icon: const Icon(
                          Icons.forward_outlined,
                          color: ProposalPalette.purpleDeep,
                          size: 20,
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
    this.onNext,
    this.onAfterFinalDecision,
    this.nextCount = 0,
    this.nextBusy = false,
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
  final VoidCallback? onNext;
  final ValueChanged<int>? onAfterFinalDecision;
  final int nextCount;
  final bool nextBusy;

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

  static const _financeFields = <(String, String)>[
    ('salesScale', '销售规模目标（元）'),
    ('revenue', '收入（元）'),
    ('invoiceAmount', '发票（元）'),
    ('profit', '利润（元）'),
    ('projectCost', '项目成本（元）'),
    ('taxCost', '税务成本（元）'),
    ('operatingCost', '经营成本（元）'),
    ('margin', '毛利率（%）'),
    ('turnoverCash', '预计周转资金（元）'),
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
  static const _contractReviewLabel = '行政复核';

  static const _financeReviewKeys = <String>[
    'salesScale',
    'revenue',
    'invoiceAmount',
    'profit',
    'projectCost',
    'taxCost',
    'operatingCost',
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
    'rollback',
  ];

  @override
  void initState() {
    super.initState();
    _row = _withCurrentUserFiller(widget.row);
    if (_text('marketOwner2UserId') !=
        '${widget.row.form['marketOwner2UserId'] ?? ''}') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_row);
      });
    }
  }

  String get _currentUserName {
    final fromPeople = widget.people
        .where((person) => person.userId == widget.session.userId)
        .map((person) => person.name)
        .where((name) => name.isNotEmpty)
        .firstOrNull;
    return fromPeople ?? widget.session.displayName?.trim() ?? '';
  }

  ProposalIntakeRow _withCurrentUserFiller(ProposalIntakeRow row) {
    if ('${row.form['marketOwner2UserId'] ?? ''}'.trim().isNotEmpty) {
      return row;
    }
    if (widget.session.userId <= 0) return row;
    final form = Map<String, dynamic>.from(row.form)
      ..['marketOwner2UserId'] = widget.session.userId
      ..['marketOwner2'] = _currentUserName;
    return row.copyWith(form: form);
  }

  int get _me => widget.session.userId;

  bool get _isLocked =>
      _row.status == 'done' || _row.status == 'pending_president';

  /// 最终审核人、已通过提案只看已填结果，不铺开未选项。
  bool get _showSelectedAsText => _isLocked;

  bool get _isReviewing => _stage == 'reviewing' || _stage == 'awaiting_submit';

  /// 复核开始后整单只读；要改内容必须先驳回。
  bool get _isContentFrozen => _isLocked || _isReviewing;

  int _ownerId(String key) => int.tryParse(_text('${key}UserId')) ?? 0;

  bool _isOwner(String key) => _me > 0 && _ownerId(key) == _me;

  /// 新建提案人即市场部负责人二，由其先填市场/合同/财务与人员指定。
  bool get _isMarketFiller {
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

  bool get _canEditMarket => !_isContentFrozen && _isMarketFiller;

  bool get _canEditTech => !_isContentFrozen && _isTechFiller;

  bool get _canSave => !_isContentFrozen && (_isMarketFiller || _isTechFiller);

  bool get _canNotifyTech =>
      !_isLocked &&
      _isMarketFiller &&
      _stage == 'filling' &&
      _review['reviewRejected'] != true;

  bool get _canNotifyMarket2 =>
      !_isLocked && _isTechFiller && _stage == 'awaiting_tech';

  bool get _canStartReview =>
      !_isLocked &&
      _isMarketFiller &&
      (_stage == 'awaiting_start_review' ||
          (_stage == 'filling' &&
              _review['reviewRejected'] == true &&
              _review['presidentRejected'] != true));

  bool get _canSubmit =>
      !_isLocked && _isMarketFiller && _stage == 'awaiting_submit';

  bool get _canDelete => _row.canDeleteBy(_me);

  bool _fillEnabled(bool? writable) =>
      !_isContentFrozen && (writable ?? _canEditMarket);

  Widget _readonlySelectedText(String value) {
    final text = value.trim();
    // 最终审核 / 已完成：明细只读展示，但仍需支持长按选中复制。
    return SelectableText(
      text.isEmpty ? '未填写' : text,
      style: TextStyle(
        fontSize: 13,
        height: 1.45,
        fontWeight: text.isEmpty ? FontWeight.w500 : FontWeight.w600,
        color: text.isEmpty ? ProposalPalette.text3 : ProposalPalette.text,
      ),
    );
  }

  bool _reviewEnabled(String? section) {
    if (section == null || !_isReviewing || _me <= 0) return false;
    if (section.startsWith('technologyItem:')) return _isMarketFiller;
    if (section.startsWith('financeItem:')) return _isOwner('financeOwner2');
    if (section.startsWith('contractItem:')) return _isOwner('contractAdmin');
    return false;
  }

  bool _moduleReviewEnabled(String keyName) {
    if (!_isReviewing || _me <= 0) return false;
    return switch (keyName) {
      'marketCompleted' => _isOwner('marketOwner1'),
      'technologyCompleted' => _isMarketFiller,
      'financeInterfaceCompleted' => _isOwner('financeOwner2'),
      'financeCompleted' => _isOwner('financeOwner1'),
      'purchaseContractCompleted' ||
      'salesContractCompleted' => _isOwner('contractAdmin'),
      _ => false,
    };
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
      'marketCompleted' => '市场部负责人一',
      'technologyCompleted' => '市场部负责人二',
      'financeInterfaceCompleted' => '财务部负责人二',
      'financeCompleted' => '财务部负责人一',
      'purchaseContractCompleted' || 'salesContractCompleted' => '行政负责人',
      _ => '复核人',
    };
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
      status: _isContentFrozen ? _row.status : 'filling',
      form: form,
      review: review,
    );
    if (rebuild && mounted) setState(() {});
    widget.onChanged(_row);
  }

  void _setContractMode(String prefix, String? mode) {
    final flag = '${prefix}ContractCompleted';
    final form = Map<String, dynamic>.from(_form)
      ..addAll(proposalIntakeResetContractFields(prefix))
      ..['${prefix}Mode'] = mode ?? '';
    final contractItems = _review['contractItems'] is Map
        ? Map<String, dynamic>.from(_review['contractItems'] as Map)
        : <String, dynamic>{};
    contractItems.removeWhere((key, _) => key.startsWith('$prefix.'));
    final review = Map<String, dynamic>.from(_review)
      ..[flag] = false
      ..['contractItems'] = contractItems
      ..['marketCompleted'] = false
      ..['financeCompleted'] = false;
    setState(() {
      _dirty = true;
      _fieldEpoch++;
      _row = _row.copyWith(form: form, review: review, status: 'filling');
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
      hint: '请填写驳回意见。仅作废本板块，其他板块复核仍保留。',
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

  void _toggleList(String key, String value, {String? resetReview}) {
    final values = _setOf(key);
    values.contains(value) ? values.remove(value) : values.add(value);
    _set(key, values.toList(), resetReview: resetReview);
  }

  String _text(String key) => '${_form[key] ?? ''}';
  double _number(String key) => _form[key] is num
      ? (_form[key] as num).toDouble()
      : double.tryParse(_text(key)) ?? 0;

  String get _rating {
    final raw = _form['salesScale'];
    if (raw == null || '$raw'.trim().isEmpty) return '—';
    return widget.options.ratingFor(_number('salesScale'));
  }

  /// 金额统一按元展示，并按千分位分组。
  String _money(double value) {
    if (value == 0) return '0 元';
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
    return '$buffer$decimals 元';
  }

  Future<void> _addOption(
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
    _toggleList(key, value, resetReview: resetReview);
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
        '确认后被驳回的板块将重新进入复核，其他已通过板块保持不变。这是本步骤的最终确认。',
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
    try {
      final saved = await widget.service.save(_row);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ColoredBox(
          color: ProposalPalette.page,
          child: Column(
            children: [
              _topbar(compact: constraints.maxWidth < 620),
              _sectionNav(compact: constraints.maxWidth < 620),
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
                    cacheExtent: 4000,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 28 : 14,
                          wide ? 22 : 14,
                          wide ? 28 : 14,
                          80,
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
                              if (widget.enableComments) _commentsSection(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
    );
  }

  String get _headerTitle {
    final name = _row.title.trim();
    if (name.isNotEmpty) return name;
    final fromForm = _text('proposalName').trim();
    if (fromForm.isNotEmpty) return fromForm;
    return '未命名销售业务提案';
  }

  Widget _topbar({required bool compact}) {
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!compact) ...[
            ProposalStatusChip(label: _row.code),
            const SizedBox(width: 7),
          ],
          ProposalStatusChip(
            label: proposalIntakeStatusLabel(_row.status),
            kind: _row.status == 'done'
                ? ProposalChipKind.ok
                : ProposalChipKind.purple,
          ),
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Color(0xFFFBFAFD),
          border: Border(bottom: BorderSide(color: Color(0xFFEAE3F0))),
          boxShadow: [BoxShadow(color: Color(0x0E4E3A6C), blurRadius: 14)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _headerTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ProposalPalette.text,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            chips,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _topActionButtons(compact: true),
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
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFAFD),
        border: Border(bottom: BorderSide(color: Color(0xFFEAE3F0))),
        boxShadow: [BoxShadow(color: Color(0x0E4E3A6C), blurRadius: 14)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
        ],
      ),
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
      btn(
        icon: Icons.save_outlined,
        tooltip: '保存',
        onPressed: widget.saving || !_canSave
            ? null
            : () => unawaited(_saveDraft()),
      ),
      btn(
        icon: Icons.forward_outlined,
        tooltip: _forwarding ? '转发中…' : '转发',
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
    if (_canStartReview) {
      actions.add(
        btn(
          icon: Icons.assignment_turned_in_outlined,
          tooltip: '重新提交复核',
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
    if (_row.status == 'pending_president' && _isPresident) {
      actions
        ..add(
          btn(
            icon: Icons.check_rounded,
            tooltip: '确认通过',
            filled: true,
            background: ProposalPalette.purpleDeep,
            onPressed: () => unawaited(_decidePresident(approved: true)),
          ),
        )
        ..add(
          btn(
            icon: Icons.close_rounded,
            tooltip: '驳回',
            foreground: ProposalPalette.coral,
            border: const Color(0xFFE7C2B0),
            onPressed: () => unawaited(_decidePresident(approved: false)),
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
    final text = comment.isEmpty
        ? (president
              ? '$who 已驳回，请修改后重新通知科技负责人，全部流程重新开始。'
              : '$who 已驳回本板块，请修改后重新提交该板块复核。其他板块复核仍保留。')
        : (president
              ? '$who 驳回意见：$comment。请修改后重新通知科技负责人，全部流程重新开始。'
              : '$who 驳回意见：$comment。请修改后重新提交该板块复核。其他板块复核仍保留。');
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
            : '各环节已复核完成。市场部负责人二请点击右上角「通知最终人」。提交前内容仍不可改，如需改请驳回。',
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

  Widget _overview() => ProposalCard(
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBF7F0), Color(0xFFF5F0FA), Color(0xFFECE4F6)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '销售业务提案 · 新增',
          style: TextStyle(
            color: ProposalPalette.purple,
            fontSize: 10,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _row.title.isEmpty ? '未命名销售业务提案' : _row.title,
          style: const TextStyle(
            color: ProposalPalette.text,
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _marketSection(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeyedSubtree(
        key: _marketKey,
        child: ProposalSectionTitle(
          title: '一、市场部内容',
          tag: 'Market',
          description: _canEditMarket
              ? '市场部负责人二填写；市场部负责人一整板块复核。'
              : '由市场部负责人二填写。当前账号不可编辑本板块。',
        ),
      ),
      _stepCard(
        '01',
        '基础信息',
        '提案身份与所属业务',
        _fieldGrid(wide, [
          _dropdownField(
            '业务板块',
            'sector',
            widget.options.sectors,
            required: true,
            resetReview: 'marketCompleted',
          ),
          ProposalField(
            label: '提案编号',
            source: '系统自动生成',
            child: TextFormField(
              readOnly: true,
              initialValue: _row.code,
              decoration: proposalInputDecoration(readOnly: true),
            ),
          ),
          _currentUserField('市场部负责人二（填写人）', 'marketOwner2'),
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
        _fieldGrid(wide, [
          _dropdownField(
            '产品（标签一）',
            'product',
            widget.options.products.map((item) => item.value).toList(),
            resetReview: 'marketCompleted',
            addLabel: '新增标签一',
          ),
          _dropdownField(
            '项目名称（标签一二级）',
            'projectName',
            widget.options.products
                .where((item) => item.value == _text('product'))
                .expand((item) => item.children)
                .toList(),
            resetReview: 'marketCompleted',
            addLabel: '新增项目',
          ),
          _multiField(
            '供给（标签二）',
            'supplies',
            widget.options.supplies,
            '新增供给',
            resetReview: 'marketCompleted',
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
      ),
      _contractCard('03', '采购合同', 'purchase', wide),
      _contractCard('04', '销售合同', 'sales', wide),
      _stepCard(
        '05',
        '政策与执行',
        '合同政策、合作计划与盈利方式',
        _fieldGrid(wide, [
          _textField(
            '供货商政策',
            'supplierPolicy',
            maxLines: 3,
            source: '合同抓取 · 可修改',
            resetReview: 'marketCompleted',
          ),
          _textField(
            '渠道政策',
            'channelPolicy',
            maxLines: 3,
            source: '合同抓取 · 可修改',
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
        ]),
      ),
      _moduleReview(
        title: '市场部板块统一复核',
        description: '市场部负责人一确认市场部负责人二填写的全部业务内容',
        keyName: 'marketCompleted',
        buttonLabel: '整个板块复核通过',
      ),
    ],
  );

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
            description: _canEditTech
                ? '请填写科技部内容；完成后由市场部负责人二逐条复核。'
                : _canEditMarket
                ? '请指定科技部负责人。技术字段由对方填写，你只做逐条复核。'
                : '科技部负责人填写；市场部负责人二逐条复核。',
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
                              ChoiceChip(
                                label: Text(
                                  '${item.label}${item.required ? ' *' : ''}',
                                ),
                                selected: interfaces[item.key] == true,
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
                                selectedColor: ProposalPalette.purpleSoft,
                                backgroundColor: const Color(0xFFF7F5FA),
                                surfaceTintColor: Colors.transparent,
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                side: BorderSide(
                                  color: interfaces[item.key] == true
                                      ? ProposalPalette.purple
                                      : const Color(0xFFC9C0D4),
                                ),
                                labelStyle: TextStyle(
                                  color: interfaces[item.key] == true
                                      ? ProposalPalette.purpleDeep
                                      : ProposalPalette.text,
                                  fontSize: 12,
                                  fontWeight: interfaces[item.key] == true
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                shape: const StadiumBorder(),
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
                  '研发费用金额（元）',
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
            ],
          ),
        ),
        _moduleReview(
          title: '科技部板块审核',
          description: '科技部负责人填写，市场部负责人二逐条复核后统一确认',
          keyName: 'technologyCompleted',
          buttonLabel: '科技部字段全部复核',
          locked: !_allTechnologyItemsReviewed,
          progress:
              '逐条复核 ${_reviewedCount('technologyItem', _technologyReviewFields)}/${_technologyReviewFields.length}',
        ),
        _moduleReview(
          title: '财务技术接口复核',
          description: '财务部负责人二逐条复核后，由财务部负责人一整板块复核',
          keyName: 'financeInterfaceCompleted',
          buttonLabel: '财务技术接口复核通过',
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
          description: _canEditMarket
              ? '市场部负责人二填写 · 财务部负责人二逐条复核 · 财务部负责人一整板块复核。'
              : '本板块由市场部负责人二填写；财务负责人只做复核。',
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
            _multiField(
              '项目成本明细',
              'costItems',
              widget.options.costItems,
              '新增成本项',
              resetReview: 'financeCompleted',
              reviewSection: 'financeItem:costItems',
              reviewLabel: _financeReviewLabel,
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
          ],
        ),
      ),
      _moduleReview(
        title: '财务部负责人一 · 整板块复核',
        description: '仅当财务部负责人二逐条复核完成后执行',
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
              const Text(
                '四流主体',
                style: TextStyle(
                  color: ProposalPalette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                '由市场部负责人二（填写人）填写；也可直接点图中节点改名。复核开始后锁定。',
                style: TextStyle(color: ProposalPalette.text3, fontSize: 10),
              ),
              const SizedBox(height: 10),
              _fieldGrid(wide, [
                _textField(
                  '补贴出资方',
                  'subsidyName',
                  hint: FlowCtxMapper.subsidyPlaceholder,
                ),
                _textField(
                  '清算 / 支付机构',
                  'clearingName',
                  hint: FlowCtxMapper.clearingPlaceholder,
                ),
                _textField('我方开票主体', 'billingName', hint: '空则使用销售合同我方主体'),
                _textField(
                  '服务 / 承接机构',
                  'serviceOrgName',
                  hint: FlowCtxMapper.servicePlaceholder,
                ),
              ]),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Expanded(
                    child: Column(
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
                    ),
                  ),
                  ProposalStatusChip(
                    label: '实时串联',
                    icon: Icons.circle,
                    kind: ProposalChipKind.purple,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _sourceCard(
                    '市场部',
                    ctx.proposal,
                    '${ctx.sector} · ${ctx.project} · ${ctx.channels.join('、')}',
                  ),
                  _sourceCard(
                    '采购 / 销售合同',
                    '${ctx.purchaseNo} ↔ ${ctx.salesNo}',
                    '${ctx.purchaseTheirs} → ${ctx.salesTheirs}',
                  ),
                  _sourceCard(
                    '科技部',
                    ctx.tau1,
                    '${ctx.tau2.join('、')} · ${ctx.outputs.join('、')}',
                  ),
                  _sourceCard(
                    '财务部',
                    ctx.financeSourceTitle,
                    ctx.financeSourceMeta,
                  ),
                ],
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

  Widget _sourceCard(String label, String value, String meta) => Container(
    width: 250,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ProposalPalette.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          meta.isEmpty ? '—' : meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ProposalPalette.text3, fontSize: 9),
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
            child: Row(
              children: [
                Container(
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
                ),
                const SizedBox(width: 10),
                Expanded(
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
                ),
                const ProposalStatusChip(
                  label: '负责人填写',
                  kind: ProposalChipKind.purple,
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
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
              reviewLabel: _contractReviewLabel,
              onSelected: (value) => _setContractMode(prefix, value),
            ),
            _personField(
              '行政负责人（合同审核）',
              'contractAdmin',
              positionIncludes: '行政',
              badge: '指定审核人 · 无需复核',
              required: true,
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
              reviewLabel: _contractReviewLabel,
            ),
            if (unsigned) _unsignedFileField(prefix),
            _textField(
              '合同名称',
              '${prefix}Name',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Name',
              reviewLabel: _contractReviewLabel,
            ),
            _textField(
              '签署时间',
              '${prefix}SignDate',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.SignDate',
              reviewLabel: _contractReviewLabel,
            ),
            _textField(
              '我方签约主体',
              '${prefix}OurParty',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.OurParty',
              reviewLabel: _contractReviewLabel,
            ),
            _textField(
              '对方签约主体',
              '${prefix}Counterparty',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Counterparty',
              reviewLabel: _contractReviewLabel,
            ),
            _textField(
              '有效期',
              '${prefix}ValidPeriod',
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.ValidPeriod',
              reviewLabel: _contractReviewLabel,
            ),
            _textField(
              '核心条款',
              '${prefix}CoreTerms',
              maxLines: 3,
              source: '合同抓取 · 可修改',
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.CoreTerms',
              reviewLabel: _contractReviewLabel,
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
            title: '$title行政审核',
            description: [
              _isOwner('contractAdmin')
                  ? '你就是本单行政负责人（可与填写人同一人），点各字段右侧「行政复核」即可。行政负责人姓名本身不用复核。'
                  : '由行政负责人逐条点「行政复核」。填写人若不是行政负责人，请等对方审核。',
              if (pending.isNotEmpty) '还差：${pending.join('、')}。',
            ].join(),
            keyName: flag,
            buttonLabel: '合同字段审核通过',
            compact: true,
            locked: !_itemsReviewed('contractItem', keys),
            progress:
                '行政复核 ${_reviewedCount('contractItem', keys)}/${keys.length}',
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
      final contractItems = _review['contractItems'] is Map
          ? Map<String, dynamic>.from(_review['contractItems'] as Map)
          : <String, dynamic>{};
      contractItems.removeWhere((key, _) => key.startsWith('$prefix.'));
      final review = Map<String, dynamic>.from(_review)
        ..['contractsCompleted'] = false
        ..['${prefix}ContractCompleted'] = false
        ..['contractItems'] = contractItems
        ..['marketCompleted'] = false
        ..['financeCompleted'] = false;
      if (!mounted) return;
      setState(() {
        _dirty = true;
        _fieldEpoch++;
        _row = _row.copyWith(form: form, review: review, status: 'filling');
      });
      widget.onChanged(_row);
      showProposalCenterToast(context, '已从合同归集带入可修改字段');
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
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
      final flag = '${prefix}ContractCompleted';
      final form = Map<String, dynamic>.from(_form)
        ..['${prefix}FileName'] = uploaded.fileName
        ..['${prefix}ObjectKey'] = uploaded.objectKey
        ..['${prefix}FileUrl'] = uploaded.url
        ..['${prefix}FileSize'] = uploaded.sizeBytes
        ..['${prefix}No'] = uploaded.fileName;
      final review = Map<String, dynamic>.from(_review)
        ..[flag] = false
        ..['marketCompleted'] = false;
      setState(() {
        _dirty = true;
        _fieldEpoch++;
        _row = _row.copyWith(form: form, review: review, status: 'filling');
      });
      widget.onChanged(_row);
      showProposalCenterToast(context, '已上传「${uploaded.fileName}」');
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingContractPrefix = null);
    }
  }

  void _clearUnsignedFile(String prefix) {
    if (!_canEditMarket) return;
    final flag = '${prefix}ContractCompleted';
    final form = Map<String, dynamic>.from(_form)
      ..['${prefix}FileName'] = ''
      ..['${prefix}ObjectKey'] = ''
      ..['${prefix}FileUrl'] = ''
      ..['${prefix}FileSize'] = null
      ..['${prefix}No'] = '';
    final review = Map<String, dynamic>.from(_review)..[flag] = false;
    setState(() {
      _dirty = true;
      _fieldEpoch++;
      _row = _row.copyWith(form: form, review: review, status: 'filling');
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
    if (_openingContractPrefix != null) return;
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

  Widget _unsignedFileField(String prefix) {
    final enabled = _canEditMarket;
    final uploading = _uploadingContractPrefix == prefix;
    final opening = _openingContractPrefix == prefix;
    final name = _text('${prefix}FileName');
    final canOpen = name.isNotEmpty;
    return _FullWidthField(
      child: ProposalField(
        label: '上传合同文件',
        required: true,
        source: canOpen ? '未签合同 · 可查看' : '未签合同',
        trailing: canOpen
            ? TextButton.icon(
                onPressed: opening
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
              )
            : null,
        child: name.isEmpty
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
                    uploading ? '上传中…' : '点击选择未签合同 PDF / Word',
                    style: const TextStyle(
                      fontSize: 13,
                      color: ProposalPalette.text3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
            : InkWell(
                onTap: opening
                    ? null
                    : () => unawaited(_openUnsignedFile(prefix)),
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
          final canAct = !locked && _moduleReviewEnabled(keyName);
          final action = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: !canAct || done
                    ? null
                    : () => unawaited(_setReview(keyName, true)),
                child: Text(
                  done ? '已复核' : buttonLabel,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              if (canAct)
                OutlinedButton(
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

  Widget _fieldGrid(bool wide, List<Widget> fields) => LayoutBuilder(
    builder: (_, constraints) {
      final columns = !wide
          ? 1
          : constraints.maxWidth >= 1080
          ? 3
          : constraints.maxWidth >= 660
          ? 2
          : 1;
      final rows = _groupFields(fields, columns);
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: ProposalPalette.borderSoft),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var row = 0; row < rows.length; row++)
              _gridRow(rows[row], columns, lastRow: row == rows.length - 1),
          ],
        ),
      );
    },
  );

  Widget _gridRow(List<Widget> cells, int columns, {required bool lastRow}) {
    final fullWidth = cells.length == 1 && cells.first is _FullWidthField;
    final filler = !fullWidth && cells.length < columns;
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
  }) => Container(
    constraints: const BoxConstraints(minHeight: 90),
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
    const purple = ProposalPalette.purple;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: purple,
          onPrimary: Colors.white,
          secondary: purple,
          onSecondary: Colors.white,
          secondaryContainer: ProposalPalette.purpleSoft,
          onSecondaryContainer: ProposalPalette.purpleDeep,
          surface: Colors.white,
          onSurface: ProposalPalette.text,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          headerBackgroundColor: purple,
          headerForegroundColor: Colors.white,
          rangeSelectionBackgroundColor: ProposalPalette.purpleSoft,
          rangeSelectionOverlayColor: WidgetStatePropertyAll(
            purple.withValues(alpha: 0.08),
          ),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return purple;
            return null;
          }),
          dayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            if (states.contains(WidgetState.disabled)) {
              return ProposalPalette.text3;
            }
            return ProposalPalette.text;
          }),
          todayForegroundColor: const WidgetStatePropertyAll(purple),
          todayBorder: const BorderSide(color: purple),
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
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        source: source,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(empty ? '' : display),
      );
    }
    return ProposalField(
      label: label,
      source: source,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: InkWell(
        key: ValueKey('date-$fieldKey'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: proposalInputDecoration(hint: hint, readOnly: !enabled)
              .copyWith(
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
    if (_showSelectedAsText) {
      final field = ProposalField(
        label: label,
        required: required,
        source: source,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(_text(key)),
      );
      return maxLines > 1 ? _FullWidthField(child: field) : field;
    }
    final field = ProposalField(
      label: label,
      required: required,
      source: source,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: TextFormField(
        key: ValueKey('$key-${_row.id}-$_fieldEpoch'),
        initialValue: _text(key),
        maxLines: maxLines,
        enabled: enabled,
        readOnly: !enabled,
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
        decoration: proposalInputDecoration(hint: hint, readOnly: !enabled),
      ),
    );
    return maxLines > 1 ? _FullWidthField(child: field) : field;
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
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        source: source,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(_text(key)),
      );
    }
    return ProposalField(
      label: label,
      source: source,
      trailing: _rowReviewToggle(reviewSection, reviewLabel),
      child: TextFormField(
        key: ValueKey('$key-${_row.id}-$_fieldEpoch'),
        initialValue: _text(key),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        enabled: enabled,
        readOnly: !enabled,
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
        decoration: proposalInputDecoration(readOnly: !enabled),
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
    final current = _text(key);
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        required: required,
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

  Widget _currentUserField(String label, String key) {
    final name = _text(key).isNotEmpty ? _text(key) : _currentUserName;
    if (_showSelectedAsText) {
      return ProposalField(
        label: label,
        source: '当前用户',
        child: _readonlySelectedText(name),
      );
    }
    return ProposalField(
      label: label,
      source: '当前用户',
      child: TextFormField(
        key: ValueKey('$key-${_row.id}-$name'),
        readOnly: true,
        initialValue: name,
        style: const TextStyle(fontSize: 13, color: ProposalPalette.text),
        decoration: proposalInputDecoration(readOnly: true),
      ),
    );
  }

  Widget _configuredPresidentsField() {
    final names = widget.options.presidentDisplayNames(widget.people);
    return ProposalField(
      label: '最终确认人',
      source: '管理后台配置',
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
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(_text(key)),
      );
    }
    return ProposalField(
      label: label,
      required: required,
      source: badge,
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
                  _row = _row.copyWith(form: form, status: 'filling');
                });
                widget.onChanged(_row);
              }
            : null,
      ),
    );
  }

  Widget _multiField(
    String label,
    String key,
    List<String> options,
    String? addLabel, {
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    bool? writable,
  }) {
    final enabled = _fillEnabled(writable);
    final selected = _setOf(key);
    if (_showSelectedAsText) {
      return _FullWidthField(
        child: ProposalField(
          label: label,
          trailing: _rowReviewToggle(reviewSection, reviewLabel),
          child: _readonlySelectedText(selected.join('、')),
        ),
      );
    }
    return _FullWidthField(
      child: ProposalField(
        label: label,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: ProposalPills(
          options: [
            ...options,
            ..._setOf(key).where((v) => !options.contains(v)),
          ],
          selected: _setOf(key),
          enabled: enabled,
          onToggle: (value) {
            if (enabled) {
              _toggleList(key, value, resetReview: resetReview);
            }
          },
          onAdd: addLabel == null || !enabled
              ? null
              : () => _addOption(key, addLabel, resetReview: resetReview),
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
