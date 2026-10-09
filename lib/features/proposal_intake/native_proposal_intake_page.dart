import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/dunes_defaults.dart';
import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import '../xflow/approval_chat_forward.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/proposal_import_template.dart';
import '../xflow/xflow_detail_comments.dart';
import '../contract_register/contract_kb_pdf_preview.dart';
import '../contract_register/contract_register_service.dart';
import '../xflow/xflow_file_open.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'flow_panorama/flow_ctx_mapper.dart';
import 'flow_panorama/flow_lane_section.dart';
import 'flow_panorama/flow_lanes.dart';
import 'proposal_cost_estimate.dart';
import 'proposal_estimate_summary.dart';
import 'proposal_view_style.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_unreviewed.dart';
import 'proposal_intake_select.dart';
import 'proposal_intake_service.dart';
import 'proposal_intake_ui.dart';
import 'settlement_catalog.dart';

enum _ProposalPage { list, form }

/// 「我的」里的销售/采购提案。列表返回「我的」；填写中的返回先回到列表。
class ProposalIntakeMyEntryPage extends StatefulWidget {
  const ProposalIntakeMyEntryPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.kind,
    required this.title,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String kind;
  final String title;

  @override
  State<ProposalIntakeMyEntryPage> createState() =>
      _ProposalIntakeMyEntryPageState();
}

class _ProposalIntakeMyEntryPageState extends State<ProposalIntakeMyEntryPage> {
  TaskShellChrome _chrome = const TaskShellChrome();

  @override
  void dispose() {
    if (widget.navigation.backInterceptor == _consumeFormBack) {
      widget.navigation.backInterceptor = null;
    }
    super.dispose();
  }

  bool _consumeFormBack() {
    final back = _chrome.onBack;
    if (back == null) return false;
    back();
    return true;
  }

  void _syncFormBack(TaskShellChrome chrome) {
    final nav = widget.navigation;
    if (chrome.onBack != null) {
      nav.backInterceptor = _consumeFormBack;
    } else if (nav.backInterceptor == _consumeFormBack) {
      nav.backInterceptor = null;
    }
  }

  void _onChrome(TaskShellChrome chrome) {
    _chrome = chrome;
    _syncFormBack(chrome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final inForm = _chrome.onBack != null;
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: inForm ? _chrome.onBack : widget.navigation.back,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text2,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            inForm ? '列表' : '我的',
                            style: TextStyle(
                              fontSize: 13,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xFF7B5CD8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: NativeProposalIntakePage(
              session: widget.session,
              kind: widget.kind,
              onChromeChanged: _onChrome,
            ),
          ),
        ],
      ),
    );
  }
}

const _proposalStatusFilters = <(String, String)>[
  ('', '全部'),
  ('draft', '草稿'),
  ('filling', '填写中'),
  ('reviewing', '复核中'),
  ('pending_president', '待最终确认'),
  ('done', '已完成'),
];

/// 总裁许正阳的列表视角，与后端写死的范围一致。
const _presidentDeskName = '许正阳';
const _presidentDeskStatuses = {'reviewing', 'pending_president', 'done'};
const _presidentDeskFilters = <(String, String)>[
  ('', '全部'),
  ('reviewing', '复核中'),
  ('pending_president', '待最终确认'),
  ('done', '已完成'),
];

const _showTechnologyHandoffRecords = false;

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

  /// `sales` / `purchase` 只列该类；空字符串表示全部。
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
  bool _formDirty = false;
  String? _error;
  String _statusFilter = '';

  bool get _presidentDesk =>
      (widget.session.displayName ?? '').trim() == _presidentDeskName;
  String _sectorFilter = '';
  String _periodFilter = '';
  ProposalIntakeLibraryStats _libraryStats = const ProposalIntakeLibraryStats();
  List<ProposalIntakeRow> _actionQueue = const [];
  double _listScrollOffset = 0;
  bool _didOpenInitial = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant NativeProposalIntakePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.assistantMode != widget.assistantMode) {
      _page = _ProposalPage.list;
      _editing = null;
      unawaited(_load(resetScroll: true));
    }
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
        _fetchListPages(),
        _service.fetchOptions(),
        _service.fetchPeople(),
      ]);
      if (!mounted) return;
      var list = result[0] as ProposalIntakeListResult;
      var items = _scopedKindRows(list.items);
      if (_presidentDesk) {
        items = items
            .where((row) => _presidentDeskStatuses.contains(row.status))
            .toList(growable: false);
      }
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
        _libraryStats = list.stats;
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

  /// 服务端单页最多 50 条。库内总数更大时继续翻页，避免列表只停在第一页。
  Future<ProposalIntakeListResult> _fetchListPages() async {
    const pageSize = 50;
    Future<ProposalIntakeListResult> pageOf(int page) {
      return _service.fetchList(
        page: page,
        pageSize: pageSize,
        keyword: widget.assistantMode ? '' : _search.text,
        status: widget.assistantMode ? '' : _statusFilter,
        kind: widget.kind,
        sector: widget.assistantMode ? '' : _sectorFilter,
        period: widget.assistantMode ? '' : _periodFilter,
        actionable: widget.assistantMode,
      );
    }

    final first = await pageOf(0);
    final items = [...first.items];
    final seen = {for (final row in items) row.id};
    var page = 1;
    while (items.length < first.total && page < 20) {
      final batch = await pageOf(page);
      var added = 0;
      for (final row in batch.items) {
        if (seen.add(row.id)) {
          items.add(row);
          added++;
        }
      }
      if (added == 0) break;
      page++;
    }
    return ProposalIntakeListResult(
      items: items,
      total: first.total,
      stats: first.stats,
    );
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

  Future<void> _setSectorFilter(String sector) async {
    if (_sectorFilter == sector) return;
    setState(() => _sectorFilter = sector);
    await _load(resetScroll: true);
  }

  Future<void> _setPeriodFilter(String period) async {
    final next = period.isNotEmpty && _periodFilter == period ? '' : period;
    if (next == _periodFilter) return;
    setState(() => _periodFilter = next);
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
                          style: TextStyle(
                            color: DunesColors.resolve(
                              ctx,
                              ProposalPalette.text3,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line.name,
                          style: TextStyle(
                            color: DunesColors.resolve(
                              ctx,
                              ProposalPalette.text,
                            ),
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

  Future<void> _duplicateRow(ProposalIntakeRow row) async {
    if (row.id <= 0 || _saving) return;
    final name = row.title.trim().isEmpty
        ? (row.code.trim().isEmpty ? '这份提案' : row.code.trim())
        : row.title.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('复制新建'),
        content: Text('将按「$name」生成一份内容相同的新提案。编号和审核进度会重新开始。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.resolve(
                ctx,
                ProposalPalette.purple,
                role: DunesColorRole.surface,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认新建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final created = await _service.duplicate(row.id);
      if (!mounted) return;
      _toast('已生成新提案${created.code.isEmpty ? '' : ' ${created.code}'}');
      await _load();
      if (!mounted) return;
      _openForm(created);
    } catch (error) {
      _toast(friendlyErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              backgroundColor: DunesColors.resolve(
                ctx,
                ProposalPalette.coral,
                role: DunesColorRole.surface,
              ),
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
    'financeInterfaces': proposalIntakeDefaultFinanceInterfaces(
      _options?.financeInterfaces ?? const [],
    ),
    'rollback': kProposalDefaultRollback,
  };

  Map<String, dynamic> _defaultReview({bool purchase = false}) => {
    'marketCompleted': false,
    'technologyCompleted': false,
    'financeInterfaceCompleted': false,
    'financeCompleted': purchase,
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

  List<ProposalIntakeRow> _scopedKindRows(List<ProposalIntakeRow> rows) {
    return proposalIntakeRowsOfKind(rows, widget.kind);
  }

  ProposalIntakeRow _withScopedKind(
    ProposalIntakeRow row, {
    String fallback = '',
  }) {
    if (widget.kind.trim().isNotEmpty) {
      return row.copyWith(kind: normalizeProposalIntakeKind(widget.kind));
    }
    if (fallback.trim().isNotEmpty) {
      return row.copyWith(kind: fallback);
    }
    return row;
  }

  Future<void> _openExisting(ProposalIntakeRow row) async {
    if (_opening) return;
    _rememberListScroll();
    setState(() => _opening = true);
    try {
      final detail = await _service.fetchDetail(row.id);
      await _refreshLookups();
      if (mounted) _openForm(_withScopedKind(detail, fallback: row.kind));
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
      _editing = _withScopedKind(row);
      _formDirty = false;
      _page = _ProposalPage.form;
    });
    widget.onChromeChanged?.call(
      TaskShellChrome(onBack: () => unawaited(_backToList())),
    );
    if (widget.assistantMode) unawaited(_refreshActionQueue());
  }

  Future<void> _refreshActionQueue() async {
    try {
      final result = await _service.fetchList(
        actionable: true,
        kind: widget.kind,
        pageSize: 100,
      );
      if (!mounted) return;
      setState(() => _actionQueue = _scopedKindRows(result.items));
    } catch (_) {}
  }

  Future<void> _goNext({
    required int fromId,
    required bool afterDecision,
  }) async {
    if (_nextBusy) return;
    setState(() => _nextBusy = true);
    try {
      final result = await _service.fetchList(
        actionable: true,
        kind: widget.kind,
        pageSize: 100,
      );
      if (!mounted) return;
      final items = _scopedKindRows(result.items);
      setState(() => _actionQueue = items);
      final next = ProposalSkipTail.pick(
        items: items,
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
        _formDirty &&
        proposalIntakeShouldAutoSaveOnBack(
          editing,
          userId: widget.session.userId,
          viewAll: widget.session.proposalIntakeViewAll,
        )) {
      try {
        final persistForm = proposalIntakeBuildPersistForm(
          editing.form,
          businessCatalog: _options?.businessCostItemOptions ?? const [],
          costCatalog: _options?.costItemOptions ?? const [],
          costNames: _options?.resolvedProjectCostItems ?? const [],
        );
        final fallbackForm = proposalIntakeJsonSafeForm(
          proposalIntakeConfirmContractEdits(editing.form),
        );
        Future<ProposalIntakeRow> persist(Map<String, dynamic> form) {
          final row = editing.copyWith(form: form);
          return row.id <= 0
              ? _service.create(
                  title: row.title,
                  kind: row.kind,
                  form: row.form,
                  review: row.review,
                )
              : _service.saveResolvingConflict(row);
        }

        ProposalIntakeRow saved;
        try {
          saved = await persist(persistForm);
        } catch (error) {
          if (proposalIntakeFormsEqual(persistForm, fallbackForm)) {
            rethrow;
          }
          saved = await persist(fallbackForm);
        }
        _editing = saved;
        if (mounted && proposalIntakeShowDraftSavedToast(saved)) {
          _toast('已保存草稿');
        }
      } catch (error) {
        final text = friendlyErrorText(error, fallback: '保存草稿失败');
        if (!proposalIntakeShouldLeaveDespiteSaveError(text)) {
          _toast(text, error: true);
          return;
        }
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

  Future<void> _backToListAfterDelete() async {
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
    final stack = IndexedStack(
      index: showForm ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        TickerMode(enabled: !showForm, child: _buildList()),
        if (showForm) _buildForm() else const SizedBox.shrink(),
      ],
    );
    // 列表和提案详情整体字号再小一点：手机 0.82 倍、PC 0.95 倍。
    final media = MediaQuery.of(context);
    final phone = ProposalLayout.isCompact(media.size.width);
    final system = (media.textScaler.scale(100) / 100).clamp(0.8, 1.3);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(
          system * (phone ? kProposalPhoneTextScale : kProposalDesktopTextScale),
        ),
      ),
      child: stack,
    );
  }

  /// 手机版整体字号倍数。
  static const kProposalPhoneTextScale = 0.82;

  /// PC 版整体字号倍数（1.0 = 不缩放）。
  static const kProposalDesktopTextScale = 0.95;

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
      onDirtyChanged: (dirty) => _formDirty = dirty,
      onSaved: (next) {
        _formDirty = false;
        setState(() => _editing = next);
      },
      onSubmit: (next) {
        setState(() => _editing = next);
      },
      onError: (message) => _toast(message, error: true),
      onDeleted: () => unawaited(_backToListAfterDelete()),
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

  ButtonStyle get _compactListButtonStyle => ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  Widget _filterChips({
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    // 手机：状态按钮一排小胶囊，左右滑，不再折成两行占地。
    final phone =
        _protoList && ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    final chips = [
        for (final item in items)
          ChoiceChip(
            visualDensity: phone ? VisualDensity.compact : null,
            materialTapTargetSize: phone
                ? MaterialTapTargetSize.shrinkWrap
                : null,
            labelPadding: phone
                ? const EdgeInsets.symmetric(horizontal: 6)
                : null,
            label: Text(item.$2),
            selected: value == item.$1,
            // 原型：选中浅紫底，未选白底细框，圆角 8，没有勾。
            showCheckmark: _protoList ? false : null,
            backgroundColor: _protoList
                ? DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  )
                : null,
            shape: _protoList
                ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                : null,
            padding: _protoList
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 0)
                : null,
            selectedColor: DunesColors.resolve(
              context,
              _protoList ? const Color(0xFFEDE8FB) : ProposalPalette.purpleSoft,
            ),
            labelStyle: TextStyle(
              color: value == item.$1
                  ? DunesColors.resolve(
                      context,
                      _protoList
                          ? const Color(0xFF3F2A9A)
                          : ProposalPalette.purpleDeep,
                    )
                  : DunesColors.resolve(
                      context,
                      _protoList
                          ? const Color(0xFF2A2638)
                          : ProposalPalette.text2,
                    ),
              fontSize: 12,
              fontWeight: value == item.$1 || !_protoList
                  ? (_protoList ? FontWeight.w700 : FontWeight.w600)
                  : FontWeight.w600,
            ),
            side: BorderSide(
              color: value == item.$1
                  ? (_protoList
                        ? Colors.transparent
                        : DunesColors.resolve(
                            context,
                            ProposalPalette.purpleLine,
                            role: DunesColorRole.border,
                          ))
                  : DunesColors.resolve(
                      context,
                      _protoList
                          ? const Color(0xFFE7E3F2)
                          : ProposalPalette.border,
                      role: DunesColorRole.border,
                    ),
            ),
            onSelected: _loading ? null : (_) => onChanged(item.$1),
          ),
    ];
    if (phone) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              chips[i],
            ],
          ],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _libraryStatsRow({required bool compact}) {
    Widget cell(String label, int value, String period) {
      final selected = _periodFilter == period;
      final id = period.isEmpty ? 'all' : period;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey(
              selected ? 'proposal-period-$id-selected' : 'proposal-period-$id',
            ),
            onTap: () => unawaited(_setPeriodFilter(period)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: compact ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? DunesColors.resolve(
                        context,
                        Colors.white,
                        role: DunesColorRole.surface,
                      )
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? DunesColors.resolve(
                          context,
                          const Color(0xFFD9D0EF),
                          role: DunesColorRole.border,
                        )
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? DunesColors.resolve(
                              context,
                              const Color(0xFF5B3FD0),
                            )
                          : DunesColors.resolve(
                              context,
                              const Color(0xFF5A5C56),
                            ),
                      fontSize: compact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$value',
                    style: TextStyle(
                      color: selected
                          ? DunesColors.resolve(
                              context,
                              const Color(0xFF5B3FD0),
                            )
                          : DunesColors.resolve(
                              context,
                              const Color(0xFF1F2421),
                            ),
                      fontSize: compact ? 15 : 16,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      fontFamily: kProposalProtoMono,
                      fontFamilyFallback: kProposalProtoMonoFallback,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final sectorRows = proposalIntakeSectorCountRows(
      catalog: _options?.sectors ?? const [],
      counts: _libraryStats.sectors,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('proposal-period-strip'),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                const Color(0xFFF0ECF6),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                for (final item in kProposalIntakePeriodFilters)
                  cell(item.$2, switch (item.$1) {
                    'day' => _libraryStats.day,
                    'week' => _libraryStats.week,
                    'month' => _libraryStats.month,
                    _ => _libraryStats.total,
                  }, item.$1),
              ],
            ),
          ),
          if (sectorRows.isNotEmpty) ...[
            SizedBox(height: compact ? 6 : 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final item in sectorRows)
                  _sectorCountChip(
                    name: item.$1,
                    count: item.$2,
                    compact: compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectorCountChip({
    required String name,
    required int count,
    required bool compact,
  }) {
    final filter = name == '未填写' ? kProposalIntakeSectorBlankFilter : name;
    final selected = _sectorFilter == filter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loading
            ? null
            : () => unawaited(
                _setSectorFilter(_sectorFilter == filter ? '' : filter),
              ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: compact ? 3 : 4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? DunesColors.resolve(
                    context,
                    ProposalPalette.purpleSoft,
                    role: DunesColorRole.surface,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.soft,
                    role: DunesColorRole.surface,
                  ),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.purpleLine,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      ProposalPalette.borderSoft,
                      role: DunesColorRole.border,
                    ),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: TextStyle(
                    color: selected
                        ? DunesColors.resolve(
                            context,
                            ProposalPalette.purpleDeep,
                          )
                        : DunesColors.resolve(context, const Color(0xFF3A3D37)),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: ' $count',
                  style: TextStyle(
                    color: selected
                        ? DunesColors.resolve(
                            context,
                            ProposalPalette.purpleDeep,
                          )
                        : DunesColors.resolve(context, ProposalPalette.text),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (context, constraints) => _buildListBody(
        compact: ProposalLayout.isCompact(constraints.maxWidth),
      ),
    );
  }

  Widget _buildListBody({required bool compact}) {
    final search = TextField(
      controller: _search,
      onSubmitted: (_) => unawaited(_load(resetScroll: true)),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: const TextStyle(fontSize: 13, height: 1.2),
      decoration: proposalInputDecoration(context: context, hint: '搜索提案编号或名称')
          .copyWith(
            prefixIcon: const Icon(Icons.search, size: 16),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
    );
    final refresh = OutlinedButton.icon(
      onPressed: _loading ? null : _load,
      style: _compactListButtonStyle,
      icon: const Icon(Icons.refresh, size: 15),
      label: const Text('刷新'),
    );
    final create = widget.showCreate
        ? FilledButton.icon(
            onPressed: _saving || _options == null ? null : _create,
            style: _compactListButtonStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(
                DunesColors.resolve(
                  context,
                  ProposalPalette.purple,
                  role: DunesColorRole.surface,
                ),
              ),
              foregroundColor: WidgetStatePropertyAll(
                DunesColors.resolve(context, Colors.white),
              ),
            ),
            icon: const Icon(Icons.add, size: 15),
            label: Text(
              proposalIntakeIsPurchase(widget.kind) ? '新建采购提案' : '新建提案',
            ),
          )
        : null;
    final statusFilter = _filterChips(
      value: _statusFilter,
      items: _presidentDesk ? _presidentDeskFilters : _proposalStatusFilters,
      onChanged: (value) => unawaited(_setStatusFilter(value)),
    );
    if (_protoList) {
      return _protoListBody(
        compact: compact,
        search: search,
        refresh: refresh,
        create: create,
        statusFilter: statusFilter,
      );
    }
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        color: DunesColors.resolve(
          context,
          ProposalPalette.page,
          role: DunesColorRole.surface,
        ),
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
                padding: EdgeInsets.all(compact ? 8 : 16),
                margin: EdgeInsets.only(bottom: compact ? 8 : 14),
                child: compact
                    ? Column(
                        children: [
                          if (!widget.assistantMode)
                            _libraryStatsRow(compact: true),
                          search,
                          if (!widget.assistantMode) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: statusFilter,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(child: refresh),
                              if (create != null) ...[
                                const SizedBox(width: 6),
                                Expanded(child: create),
                              ],
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!widget.assistantMode)
                            _libraryStatsRow(compact: false),
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

  /// 销售、采购共用一套灯塔式列表骨架，仅由 kind 区分数据和文案。
  bool get _protoList => kProposalPrototypeStyleEnabled;

  Widget _protoListBody({
    required bool compact,
    required Widget search,
    required Widget refresh,
    required Widget? create,
    required Widget statusFilter,
  }) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final kindLabel = proposalIntakeIsPurchase(widget.kind) ? '采购提案' : '销售提案';
    final toolbar = compact
        ? Column(
            children: [
              search,
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: refresh),
                  if (create != null) ...[
                    const SizedBox(width: 6),
                    Expanded(child: create),
                  ],
                ],
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              refresh,
              if (create != null) ...[const SizedBox(width: 10), create],
            ],
          );
    if (compact) {
      return _protoListPhone(
        kindLabel: kindLabel,
        toolbar: toolbar,
        statusFilter: statusFilter,
      );
    }
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        key: const ValueKey('proposal-lighthouse-list'),
        color: c(0xFFF4F1EA, DunesColorRole.surface),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: kProposalProtoSans,
            fontFamilyFallback: kProposalProtoSansFallback,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 16,
              compact ? 8 : 14,
              compact ? 10 : 16,
              compact ? 10 : 14,
            ),
            // PC 列表默认铺满整个内容区（和灯塔一样），不再限宽 1180 居中。
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: double.infinity),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.assistantMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                        child: Text(
                          '待我处理的$kindLabel',
                          style: TextStyle(
                            color: c(0xFF1F2421),
                            fontSize: compact ? 15 : 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else
                      Container(
                        key: const ValueKey('proposal-status-strip'),
                        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                        child: statusFilter,
                      ),
                    Expanded(
                      child: Container(
                        key: const ValueKey('proposal-proto-list-box'),
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 14,
                          compact ? 10 : 14,
                          compact ? 10 : 14,
                          compact ? 8 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: DunesColors.resolveNullable(
                            context,
                            const Color(0xFFFFFFFF).withValues(alpha: .88),
                            role: DunesColorRole.surface,
                          ),
                          border: Border.all(
                            color: c(0xFFE5E1D3, DunesColorRole.border),
                          ),
                          borderRadius: BorderRadius.circular(
                            compact ? 12 : 16,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x10000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            toolbar,
                            SizedBox(height: compact ? 9 : 12),
                            if (!widget.assistantMode)
                              _libraryStatsRow(compact: compact),
                            _protoListTiles(),
                            SizedBox(height: compact ? 9 : 12),
                            Row(
                              children: [
                                Container(
                                  width: 3,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: c(0xFF7B5CD8),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  '提案明细',
                                  style: TextStyle(
                                    color: c(0xFF1F2421),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  '${_rows.length} 份',
                                  style: TextStyle(
                                    color: c(0xFF5A5C56),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10.5,
                                    fontFamily: kProposalProtoMono,
                                    fontFamilyFallback:
                                        kProposalProtoMonoFallback,
                                  ),
                                ),
                                const Spacer(),
                                if (_sectorFilter.isNotEmpty ||
                                    _periodFilter.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: _loading
                                        ? null
                                        : () {
                                            setState(() {
                                              _sectorFilter = '';
                                              _periodFilter = '';
                                            });
                                            unawaited(_load(resetScroll: true));
                                          },
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.filter_alt_off,
                                      size: 13,
                                    ),
                                    label: const Text(
                                      '清除筛选',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Expanded(
                              child: _buildListContent(compact: compact),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 手机列表：整页一起滑（状态、搜索、统计、提案明细连在一起往上走），
  /// 不再只有下面的明细小框能滑。
  Widget _protoListPhone({
    required String kindLabel,
    required Widget toolbar,
    required Widget statusFilter,
  }) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final title = Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: c(0xFF7B5CD8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '提案明细',
          style: TextStyle(
            color: c(0xFF1F2421),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${_rows.length} 份',
          style: TextStyle(
            color: c(0xFF5A5C56),
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            fontFamily: kProposalProtoMono,
            fontFamilyFallback: kProposalProtoMonoFallback,
          ),
        ),
        const Spacer(),
        if (_sectorFilter.isNotEmpty || _periodFilter.isNotEmpty)
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _sectorFilter = '';
                      _periodFilter = '';
                    });
                    unawaited(_load(resetScroll: true));
                  },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: const Text('清除筛选', style: TextStyle(fontSize: 10)),
          ),
      ],
    );
    final Widget rowsBlock = _rows.isEmpty
        ? SizedBox(height: 260, child: _buildListContent(compact: true))
        : Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c(0xFFFFFFFF, DunesColorRole.surface),
              border: Border.all(color: c(0xFFE7E3F2, DunesColorRole.border)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in _rows) _protoListRow(row, compact: true),
              ],
            ),
          );
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        key: const ValueKey('proposal-lighthouse-list'),
        color: c(0xFFF4F1EA, DunesColorRole.surface),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: kProposalProtoSans,
            fontFamilyFallback: kProposalProtoSansFallback,
          ),
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                  key: const PageStorageKey('proposal-intake-list'),
                  controller: _listScroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
                  children: [
                    if (widget.assistantMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                        child: Text(
                          '待我处理的$kindLabel',
                          style: TextStyle(
                            color: c(0xFF1F2421),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else
                      Padding(
                        key: const ValueKey('proposal-status-strip'),
                        padding: const EdgeInsets.only(bottom: 6),
                        child: statusFilter,
                      ),
                    Container(
                      key: const ValueKey('proposal-proto-list-box'),
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: DunesColors.resolveNullable(
                          context,
                          const Color(0xFFFFFFFF).withValues(alpha: .88),
                          role: DunesColorRole.surface,
                        ),
                        border: Border.all(
                          color: c(0xFFE5E1D3, DunesColorRole.border),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          toolbar,
                          const SizedBox(height: 8),
                          if (!widget.assistantMode)
                            _libraryStatsRow(compact: true),
                          _protoListTiles(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                      child: title,
                    ),
                    rowsBlock,
                  ],
                ),
              ),
              if (_loading && _rows.isNotEmpty)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 灯塔式经营概览：一条内同时读完进行中、年化规模和超时风险。
  Widget _protoListTiles() {
    if (_rows.isEmpty) return const SizedBox.shrink();
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final active = [
      for (final row in _rows)
        if (row.status != 'done' && row.status != 'draft') row,
    ];
    var scaleSum = 0.0;
    for (final row in active) {
      final scale = double.tryParse(
        proposalEstimateListFigures(row.form).scale,
      );
      if (scale != null) scaleSum += scale;
    }
    final stuck = [
      for (final row in active)
        if (proposalIntakeDaysOpen(row) > 3) row,
    ];
    final longest = stuck.isEmpty
        ? null
        : stuck.reduce(
            (a, b) =>
                proposalIntakeDaysOpen(a) >= proposalIntakeDaysOpen(b) ? a : b,
          );
    Widget metric({
      required IconData icon,
      required String label,
      required String value,
      required String sub,
      bool warn = false,
    }) {
      final tone = c(warn ? 0xFFB07A2B : 0xFF7B5CD8);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 12, color: tone),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: c(0xFF3A3D37),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: c(warn ? 0xFFB4570F : 0xFF1F2421),
                  fontFamily: kProposalProtoMono,
                  fontFamilyFallback: kProposalProtoMonoFallback,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: c(0xFF5A5C56),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget divider() => Container(
      width: 1,
      height: 42,
      color: c(0xFFE5E1D3, DunesColorRole.border),
    );

    return Container(
      key: const ValueKey('proposal-overview-strip'),
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: c(0xFFFBFAF6, DunesColorRole.surface),
        border: Border.all(color: c(0xFFE5E1D3, DunesColorRole.border)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          metric(
            icon: Icons.pending_actions_outlined,
            label: '进行中',
            value: '${active.length}',
            sub: '待推进提案',
          ),
          divider(),
          metric(
            icon: Icons.stacked_line_chart,
            label: '进行中年化',
            value: proposalEstimateGrouped(proposalFormatWan(scaleSum)),
            sub: '万元',
          ),
          divider(),
          metric(
            icon: Icons.schedule_outlined,
            label: '超过 3 天',
            value: '${stuck.length}',
            sub: longest == null
                ? '暂无滞留'
                : '${proposalIntakeDaysOpen(longest)} 天 · ${longest.title.isEmpty ? proposalIntakeUntitledTitle(longest.kind) : longest.title}',
            warn: stuck.isNotEmpty,
          ),
        ],
      ),
    );
  }

  /// 原型表格：提案 | 项目 | 评级 | 年化规模 | 计划毛利率 | 状态 | 现在卡在谁 | 操作。
  Widget _protoListTable({required bool compact}) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    const flex = [20, 20, 5, 9, 8, 12, 14, 9];
    Widget headerCell(String text, int f, {bool right = false}) => Expanded(
      flex: f,
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          color: c(0xFF5A5C56),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final rows = _rows;
    final list = ListView.builder(
      key: const PageStorageKey('proposal-intake-list'),
      controller: _listScroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (_, index) => _protoListRow(rows[index], compact: compact),
    );
    final table = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c(0xFFE7E3F2, DunesColorRole.border)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: c(0xFFFAF9FD, DunesColorRole.surface),
                border: Border(
                  bottom: BorderSide(
                    color: c(0xFFEFECF6, DunesColorRole.border),
                  ),
                ),
              ),
              child: Row(
                children: [
                  headerCell('提案', flex[0]),
                  const SizedBox(width: 10),
                  headerCell('项目', flex[1]),
                  const SizedBox(width: 10),
                  headerCell('评级', flex[2]),
                  const SizedBox(width: 10),
                  headerCell('年化规模', flex[3], right: true),
                  const SizedBox(width: 10),
                  headerCell('计划毛利率', flex[4], right: true),
                  const SizedBox(width: 10),
                  headerCell('状态', flex[5]),
                  const SizedBox(width: 10),
                  headerCell('当前节点', flex[6]),
                  const SizedBox(width: 10),
                  headerCell('操作', flex[7], right: true),
                ],
              ),
            ),
          Expanded(child: list),
        ],
      ),
    );
    if (compact) return table;
    // 原型：表格最小宽 1080，窗口更窄时横向滚动。
    return LayoutBuilder(
      builder: (_, box) {
        if (box.maxWidth >= 1080) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: 1080, height: box.maxHeight, child: table),
        );
      },
    );
  }

  Widget _protoListRow(ProposalIntakeRow row, {required bool compact}) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    TextStyle mono(double size, {FontWeight? weight, int color = 0xFF1F2421}) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: c(color),
          fontFamily: kProposalProtoMono,
          fontFamilyFallback: kProposalProtoMonoFallback,
        );
    final name = row.title.isEmpty
        ? proposalIntakeUntitledTitle(row.kind)
        : row.title;
    final sub = [
      proposalIntakeSectorName(row),
      '${row.form['product'] ?? ''}'.trim(),
    ].where((item) => item.isNotEmpty).join(' · ');
    final project = '${row.form['projectName'] ?? ''}'.trim();
    final mainScale = proposalIntakeMainProductScale(row.form);
    final rating = mainScale == null ? null : _options?.ratingFor(mainScale);
    final figures = proposalEstimateListFigures(row.form);
    final scale = figures.scale.isEmpty
        ? '—'
        : proposalEstimateGrouped(
            (double.tryParse(figures.scale) ?? 0).toStringAsFixed(0),
          );
    final margin = figures.margin.isEmpty
        ? '—'
        : '${double.tryParse(figures.margin)?.toStringAsFixed(1) ?? figures.margin}%';
    final statusLabel = switch (row.status) {
      'done' => '已完成',
      'pending_president' => '待最终确认',
      'reviewing' => proposalIntakeStatusChipLabel(row),
      'filling' => '填写中',
      _ => '草稿',
    };
    final who = proposalIntakeListActionText(row, people: _people);
    final days = proposalIntakeDaysOpen(row);
    final wait = row.status == 'done'
        ? formatProposalIntakeDateTime(row.updatedAt)
        : proposalIntakeDaysOpenLabel(row);
    final canDelete = row.canDeleteBy(widget.session.userId);
    Widget iconBtn(
      String tip,
      IconData icon,
      VoidCallback onTap, {
      int color = 0xFF4F3488,
    }) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: c(color)),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (widget.showCreate)
          iconBtn(
            '复制新建',
            Icons.file_copy_outlined,
            () => unawaited(_duplicateRow(row)),
          ),
        iconBtn(
          '相关人员',
          Icons.people_alt_outlined,
          () => unawaited(_showStakeholders(row)),
        ),
        iconBtn(
          '转发',
          Icons.forward_outlined,
          () => unawaited(_forwardRow(row)),
        ),
        if (canDelete)
          iconBtn(
            '删除',
            Icons.delete_outline,
            () => unawaited(_confirmDelete(row)),
            color: 0xFFC0563F,
          ),
      ],
    );
    // 手机：四个操作收进「⋯」，卡片少一行。
    final moreMenu = PopupMenuButton<String>(
      key: ValueKey('proposal-proto-row-more-${row.id}'),
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 132),
      position: PopupMenuPosition.under,
      icon: Icon(Icons.more_horiz, size: 20, color: c(0xFF4F3488)),
      onSelected: (value) {
        switch (value) {
          case 'copy':
            unawaited(_duplicateRow(row));
          case 'people':
            unawaited(_showStakeholders(row));
          case 'forward':
            unawaited(_forwardRow(row));
          case 'delete':
            unawaited(_confirmDelete(row));
        }
      },
      itemBuilder: (_) {
        PopupMenuItem<String> item(
          String value,
          String label,
          IconData icon, {
          int color = 0xFF1F2421,
        }) => PopupMenuItem<String>(
          value: value,
          height: 40,
          child: Row(
            children: [
              Icon(icon, size: 17, color: c(color)),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c(color),
                ),
              ),
            ],
          ),
        );
        return [
          if (widget.showCreate)
            item('copy', '复制新建', Icons.file_copy_outlined),
          item('people', '相关人员', Icons.people_alt_outlined),
          item('forward', '转发', Icons.forward_outlined),
          if (canDelete)
            item('delete', '删除', Icons.delete_outline, color: 0xFFC0563F),
        ];
      },
    );
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 14 : 13.5,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: c(0xFF1F2421),
          ),
        ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: c(0xFF5A5C56),
              ),
            ),
          ),
      ],
    );
    final projectText = Text(
      project.isEmpty ? '—' : project,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c(project.isEmpty ? 0xFF5A5C56 : 0xFF3F2A9A),
      ),
    );
    final badge = (rating ?? '').isEmpty
        ? Text('—', style: TextStyle(fontSize: 12, color: c(0xFF5A5C56)))
        : ProposalRatingBadge(rating: rating!, size: 24);
    final pill = ProposalStatusPill(status: row.status, label: statusLabel);
    final done = row.status == 'done';
    final whoBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // 已完成的不再写「卡在谁」，直接写完成日期。
          done ? wait : (who.isEmpty ? '—' : who),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: c(0xFF1F2421),
          ),
        ),
        if (wait.isNotEmpty && !done)
          Text(
            wait,
            style: mono(
              10,
              weight: FontWeight.w600,
              // 超过 3 天标橙（与上面「超过 3 天」一致）。
              color: days > 3 && row.status != 'done'
                  ? 0xFFB4570F
                  : 0xFF5A5C56,
            ),
          ),
      ],
    );
    final border = BoxDecoration(
      border: Border(
        bottom: BorderSide(color: c(0xFFF3F0F8, DunesColorRole.border)),
      ),
    );
    if (compact) {
      Widget metricCell(String label, Widget value) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: c(0xFF5A5C56),
                ),
              ),
              const SizedBox(height: 3),
              value,
            ],
          ),
        ),
      );
      Widget divider() => Container(
        width: 1,
        height: 28,
        color: c(0xFFE5E1D3, DunesColorRole.border),
      );
      return InkWell(
        key: ValueKey('proposal-proto-row-${row.id}'),
        onTap: () => unawaited(_openExisting(row)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          decoration: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  badge,
                  const SizedBox(width: 8),
                  Expanded(child: nameBlock),
                  const SizedBox(width: 8),
                  pill,
                  SizedBox(width: 32, height: 32, child: moreMenu),
                ],
              ),
              if (project.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 12,
                      color: c(0xFF5B3FD0),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        project,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c(0xFF4F3488),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: c(0xFFFBFAF6, DunesColorRole.surface),
                  border: Border.all(
                    color: c(0xFFE5E1D3, DunesColorRole.border),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metricCell(
                      '年化规模',
                      Text.rich(
                        TextSpan(
                          text: scale,
                          style: mono(13.5, weight: FontWeight.w800),
                          children: [
                            if (scale != '—')
                              TextSpan(
                                text: ' 万',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w500,
                                  color: c(0xFF5A5C56),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    divider(),
                    metricCell(
                      '计划毛利率',
                      Text(margin, style: mono(13.5, weight: FontWeight.w800)),
                    ),
                    divider(),
                    metricCell(done ? '完成日期' : '当前节点', whoBlock),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    const flex = [20, 20, 5, 9, 8, 12, 14, 9];
    return InkWell(
      key: ValueKey('proposal-proto-row-${row.id}'),
      onTap: () => unawaited(_openExisting(row)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: border,
        child: Row(
          children: [
            Expanded(flex: flex[0], child: nameBlock),
            const SizedBox(width: 10),
            Expanded(flex: flex[1], child: projectText),
            const SizedBox(width: 10),
            Expanded(
              flex: flex[2],
              child: Align(alignment: Alignment.centerLeft, child: badge),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: flex[3],
              child: Text(
                scale,
                textAlign: TextAlign.right,
                style: mono(13.5, weight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: flex[4],
              child: Text(
                margin,
                textAlign: TextAlign.right,
                style: mono(13.5, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: flex[5],
              child: Align(alignment: Alignment.centerLeft, child: pill),
            ),
            const SizedBox(width: 10),
            Expanded(flex: flex[6], child: whoBlock),
            const SizedBox(width: 10),
            Expanded(
              flex: flex[7],
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: actions),
              ),
            ),
          ],
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
        message:
            (_statusFilter.isNotEmpty ||
                _sectorFilter.isNotEmpty ||
                _periodFilter.isNotEmpty)
            ? '没有符合当前筛选的提案'
            : widget.assistantMode
            ? (proposalIntakeIsPurchase(widget.kind)
                  ? '当前没有需要你处理的采购提案'
                  : '当前没有需要你处理的销售提案')
            : widget.showCreate
            ? (proposalIntakeIsPurchase(widget.kind)
                  ? '点击右上角「新建采购提案」开始录入'
                  : '点击右上角「新建提案」开始录入')
            : '当前没有需要你处理的提案',
      );
    }
    if (_protoList) {
      final table = _protoListTable(compact: compact);
      if (!_loading) return table;
      return Stack(
        children: [
          table,
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ],
      );
    }
    final entries = [
      for (final group in groupProposalIntakeRowsByDate(_rows)) ...[
        _ProposalListEntry.header(group.label),
        for (final row in group.rows) _ProposalListEntry.row(row),
      ],
    ];
    final list = ListView.separated(
      key: const PageStorageKey('proposal-intake-list'),
      controller: _listScroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: entries.length,
      separatorBuilder: (_, index) {
        final next = index + 1 < entries.length ? entries[index + 1] : null;
        if (next?.isHeader == true) return const SizedBox(height: 6);
        return const SizedBox(height: 10);
      },
      itemBuilder: (_, index) {
        final entry = entries[index];
        if (entry.isHeader) {
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 2 : 8, bottom: 2),
            child: Text(
              entry.label,
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text2),
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        final row = entry.row!;
        final mainScale = proposalIntakeMainProductScale(row.form);
        return _ProposalListTile(
          row: row,
          rating: mainScale == null ? null : _options?.ratingFor(mainScale),
          people: _people,
          initiatorName: row.initiatorDisplayName(_people),
          canDelete: row.canDeleteBy(widget.session.userId),
          canDuplicate: widget.showCreate,
          compact: compact,
          onTap: () => unawaited(_openExisting(row)),
          onPeople: () => unawaited(_showStakeholders(row)),
          onForward: () => unawaited(_forwardRow(row)),
          onDelete: () => unawaited(_confirmDelete(row)),
          onDuplicate: () => unawaited(_duplicateRow(row)),
        );
      },
    );
    final scrollable = Scrollbar(
      controller: _listScroll,
      thumbVisibility: true,
      child: list,
    );
    if (!_loading) return scrollable;
    return Stack(
      children: [
        scrollable,
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

class _ProposalListEntry {
  const _ProposalListEntry._({this.label = '', this.row});

  factory _ProposalListEntry.header(String label) =>
      _ProposalListEntry._(label: label);

  factory _ProposalListEntry.row(ProposalIntakeRow row) =>
      _ProposalListEntry._(row: row);

  final String label;
  final ProposalIntakeRow? row;

  bool get isHeader => row == null;
}

class _ProposalListTile extends StatelessWidget {
  const _ProposalListTile({
    required this.row,
    this.rating,
    required this.people,
    required this.initiatorName,
    required this.canDelete,
    required this.canDuplicate,
    required this.compact,
    required this.onTap,
    required this.onPeople,
    required this.onForward,
    required this.onDelete,
    required this.onDuplicate,
  });

  final ProposalIntakeRow row;

  /// 任务评级 S/A/B/C；没有年化规模或选项未加载时为空。
  final String? rating;
  final List<ProposalPerson> people;
  final String initiatorName;
  final bool canDelete;
  final bool canDuplicate;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onPeople;
  final VoidCallback onForward;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = switch (row.status) {
      'done' => ('已完成', ProposalChipKind.ok),
      'pending_president' => ('待最终确认', ProposalChipKind.purple),
      'reviewing' => (
        proposalIntakeStatusChipLabel(row),
        ProposalChipKind.purple,
      ),
      'filling' => ('填写中', ProposalChipKind.draft),
      _ => ('草稿', ProposalChipKind.draft),
    };
    final daysLabel = proposalIntakeDaysOpenLabel(row);
    final days = proposalIntakeDaysOpen(row);
    final updated = formatProposalIntakeDateTime(row.updatedAt);
    final sectorName = proposalIntakeSectorName(row);
    final fill = proposalIntakeFillProgress(row);
    // 与原型一致：销售提案显示年化规模、毛利率，代替「已填 X%」。
    final showFigures =
        kProposalListFiguresEnabled && !proposalIntakeIsPurchase(row.kind);
    final figures = showFigures
        ? proposalEstimateListFigures(row.form)
        : (scale: '', margin: '');
    final figureStyle = TextStyle(
      color: DunesColors.resolve(context, ProposalPalette.text),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final metaStyle = kProposalCaptionStyle;
    final agingStyle = TextStyle(
      color: days >= 7
          ? DunesColors.resolve(context, ProposalPalette.coral)
          : DunesColors.resolve(context, ProposalPalette.text3),
      fontSize: 11,
      fontWeight: days >= 7 ? FontWeight.w700 : FontWeight.w400,
    );
    final fillStyle = TextStyle(
      color: fill.filledPercent < 50
          ? DunesColors.resolve(context, ProposalPalette.coral)
          : DunesColors.resolve(context, ProposalPalette.text3),
      fontSize: 11,
      fontWeight: fill.filledPercent < 50 ? FontWeight.w700 : FontWeight.w400,
    );
    List<InlineSpan> fillSpans() => [
      if (!showFigures) ...[
        TextSpan(text: fill.label, style: fillStyle),
        TextSpan(text: '  ·  ', style: metaStyle),
      ] else ...[
        if (figures.scale.isNotEmpty) ...[
          TextSpan(text: '年化 ', style: metaStyle),
          TextSpan(
            text: proposalEstimateGrouped(figures.scale),
            style: figureStyle,
          ),
          TextSpan(text: ' 万  ·  ', style: metaStyle),
        ],
        if (figures.margin.isNotEmpty) ...[
          TextSpan(text: '毛利率 ', style: metaStyle),
          TextSpan(
            text:
                '${double.tryParse(figures.margin)?.toStringAsFixed(1) ?? figures.margin}%',
            style: figureStyle,
          ),
          TextSpan(text: '  ·  ', style: metaStyle),
        ],
      ],
    ];
    final actionText = proposalIntakeListActionText(row, people: people);
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: DunesColors.resolve(
                context,
                ProposalPalette.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 38 : 42,
                height: compact ? 38 : 42,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.purpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.assignment_outlined,
                  color: DunesColors.resolve(context, ProposalPalette.purple),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            row.title.isEmpty
                                ? proposalIntakeUntitledTitle(row.kind)
                                : row.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: DunesColors.resolve(
                                context,
                                ProposalPalette.text,
                              ),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (showFigures && (rating ?? '').isNotEmpty) ...[
                          const SizedBox(width: 6),
                          ProposalRatingBadge(rating: rating!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (compact) ...[
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: proposalIntakeKindShortLabel(row.kind),
                              style: metaStyle,
                            ),
                            TextSpan(text: '  ·  ', style: metaStyle),
                            if (sectorName.isNotEmpty) ...[
                              TextSpan(text: sectorName, style: metaStyle),
                              TextSpan(text: '  ·  ', style: metaStyle),
                            ],
                            ...fillSpans(),
                            TextSpan(
                              text: '发起人 $initiatorName',
                              style: metaStyle,
                            ),
                            if (daysLabel.isNotEmpty) ...[
                              TextSpan(text: '  ·  ', style: metaStyle),
                              TextSpan(text: daysLabel, style: agingStyle),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: proposalIntakeKindShortLabel(row.kind),
                              style: metaStyle,
                            ),
                            TextSpan(text: '  ·  ', style: metaStyle),
                            if (sectorName.isNotEmpty) ...[
                              TextSpan(text: sectorName, style: metaStyle),
                              TextSpan(text: '  ·  ', style: metaStyle),
                            ],
                            ...fillSpans(),
                            TextSpan(
                              text: '发起人 $initiatorName',
                              style: metaStyle,
                            ),
                            if (daysLabel.isNotEmpty) ...[
                              TextSpan(text: '  ·  ', style: metaStyle),
                              TextSpan(text: daysLabel, style: agingStyle),
                            ],
                            if (updated.isNotEmpty)
                              TextSpan(
                                text: '  ·  更新 $updated',
                                style: metaStyle,
                              ),
                          ],
                        ),
                      ),
                    if (actionText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        actionText,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.purpleDeep,
                          ),
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
                  if (kProposalPrototypeStyleEnabled)
                    ProposalStatusPill(status: row.status, label: label)
                  else
                    ProposalStatusChip(label: label, kind: kind),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canDuplicate)
                        IconButton(
                          tooltip: '复制新建',
                          visualDensity: VisualDensity.compact,
                          onPressed: onDuplicate,
                          icon: Icon(
                            Icons.file_copy_outlined,
                            color: DunesColors.resolve(
                              context,
                              ProposalPalette.purpleDeep,
                            ),
                            size: 20,
                          ),
                        ),
                      IconButton(
                        tooltip: '相关人员',
                        visualDensity: VisualDensity.compact,
                        onPressed: onPeople,
                        icon: Icon(
                          Icons.people_alt_outlined,
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.purpleDeep,
                          ),
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
                        icon: Icon(
                          Icons.forward_outlined,
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.purpleDeep,
                          ),
                          size: 24,
                        ),
                      ),
                      if (canDelete)
                        IconButton(
                          tooltip: '删除',
                          visualDensity: VisualDensity.compact,
                          onPressed: onDelete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: DunesColors.resolve(
                              context,
                              ProposalPalette.coral,
                            ),
                            size: 20,
                          ),
                        ),
                      Icon(
                        Icons.chevron_right,
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.text3,
                        ),
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
        Icon(
          icon,
          size: 44,
          color: DunesColors.resolve(context, ProposalPalette.purpleLine),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, ProposalPalette.text),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text3),
            fontSize: 12,
          ),
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
    this.onDirtyChanged,
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
  final ValueChanged<bool>? onDirtyChanged;
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

  /// 每次表单内容变化加一，只让顶部「年化测算」单独刷新；
  /// 打字时不重建整页的输入框也能边填边算。
  final _estimateTick = ValueNotifier<int>(0);
  final _scroll = ScrollController();
  final _tocKey = GlobalKey();
  final _marketKey = GlobalKey();
  final _techKey = GlobalKey();
  final _financeKey = GlobalKey();
  final _flowKey = GlobalKey();
  final _marketModuleReviewKey = GlobalKey();
  final _techModuleReviewKey = GlobalKey();
  final _financeModuleReviewKey = GlobalKey();
  String _activeChildProductId = '';
  final Map<String, GlobalKey> _fieldAnchorKeys = {};
  final Map<String, int> _anchorUseCount = {};
  final Set<String> _flashFieldKeys = {};
  Timer? _flashTimer;

  /// 财务板块「逐条复核」模式。关闭时每个字段只留一个复核状态圆点。
  bool _financeReviewMode = false;
  ProposalIntakeNavSection _visibleSection = ProposalIntakeNavSection.market;
  bool _progressOpen = false;
  static const _productFoldPreview = 3;
  static const _productFoldStep = 10;
  int _businessProductVisible = _productFoldPreview;
  int _financeSettleVisible = _productFoldPreview;
  bool _productMultiSelect = false;
  final Set<String> _selectedProductIds = {};
  bool _jumping = false;
  List<String> _issues = const [];
  bool _dirty = false;
  int _fieldEpoch = 0;
  final Map<String, int> _settleXorStamp = {};
  ProposalSkuDetailRow? _skuSettingsClipboard;
  ProposalSkuDetailRow? _businessProductClipboard;
  ProposalSkuDetailRow? _linkedProductClipboard;
  List<ProposalSkuSettleRow>? _skuSettlementsClipboard;
  final Map<String, int> _costAmountStamp = {};
  bool _deleting = false;
  bool _forwarding = false;
  List<ProposalContractChoice> _contractHits = const [];
  int _contractSearchSeq = 0;
  List<ProposalApprovedPurchaseHit> _purchaseProposalHits = const [];
  int _purchaseProposalSearchSeq = 0;
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
  late final SettlementCatalogService _catalog;
  bool _ownsCatalog = false;
  List<CatalogRef> _sectorCatalog = const [];
  List<CatalogRef> _productCatalogAll = const [];
  List<CatalogRef> _productL3CatalogAll = const [];
  List<CatalogRef> _productL3ForCurrent = const [];
  String _productL3LoadedKey = '';
  int _productL3Seq = 0;
  List<CatalogRef> _projectCatalog = const [];
  List<CatalogRef> _syncSourceCatalog = const [];
  List<CatalogRef> _channelCategoryL1 = const [];
  List<CatalogRef> _channelCategoryL2 = const [];
  final Map<String, _SettleCatalogBundle> _settleBundles = {};
  final Set<String> _settleLoading = {};
  final Map<String, Future<_SettleCatalogBundle>> _settleBundleLoads = {};
  final Map<String, List<ChannelProductHit>> _assetProductHits = {};
  final Map<String, int> _assetProductSearchSeq = {};
  final Set<String> _assetProductSearching = {};
  final Map<String, int> _assetProductSyncSeq = {};
  final Set<String> _assetProductSyncing = {};
  final Map<String, String> _assetProductSyncHint = {};

  static const _financeMetricFields = <(String, String)>[
    ('salesScale', '销售规模目标（年·万元）'),
    ('revenue', '收入（万元）'),
    ('couponProcurementCost', '电子券采购成本（万元）'),
    ('profit', '利润（万元）'),
    ('margin', '毛利率（%）'),
    ('turnoverCash', '预计周转资金（万元）'),
    ('turnoverTimes', '月周转次数'),
  ];

  static const _financeSupplyFields = <(String, String)>[
    ('supplySettleMode', '结算模式'),
    ('supplySettleCycle', '结算周期'),
    ('supplyPayer', '付款主体'),
    ('supplyPayAccount', '付款账户'),
  ];

  static const _financeChannelFields = <(String, String)>[
    ('channelSettleMode', '结算模式'),
    ('channelSettleCycle', '结算周期'),
    ('channelPayee', '收款主体'),
    ('channelReceiveAccount', '收款账户'),
  ];

  static const _financeAccountFields = <(String, String)>[
    ('generalBusinessAccount', '结算账户一'),
    ('prepaidAccount', '结算账户二'),
    ('financeRemark', '备注'),
  ];

  /// 与后端 proposalTechnologyReviewFields 保持一致。
  List<String> get _technologyReviewFields =>
      proposalIntakeTechnologyReviewItemKeys(_form);

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
    'InvoiceType': '发票种类',
    'InvoiceFlow': '发票流',
  };

  static const _techReviewLabel = '科技部负责人复核';
  static const _financeReviewLabel = '财务部负责人二复核';
  static const _subtitleFillLabel = '财务部负责人二填写';

  static const _kFinanceReviewKeys = <String>[
    'revenue',
    'couponProcurementCost',
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
    'generalBusinessAccount',
    'prepaidAccount',
    'financeRemark',
    'costItems',
    'operatingCost',
    'taxCost',
    'proposalSubtitle',
  ];

  late Map<String, dynamic> _serverForm;

  @override
  void initState() {
    super.initState();
    final form = proposalIntakeShouldDefaultFinanceInterfaces(widget.row)
        ? proposalIntakeFormWithDefaultFinanceInterfaces(
            widget.row.form,
            widget.options.financeInterfaces,
          )
        : widget.row.form;
    _row = identical(form, widget.row.form)
        ? widget.row
        : widget.row.copyWith(form: form);
    _serverForm = proposalIntakeCloneForm(_row.form);
    _visibleSection = _isPurchase && !_protoForm
        ? ProposalIntakeNavSection.toc
        : (_taskSection ?? ProposalIntakeNavSection.market);
    _ownsCatalog = widget.catalog == null;
    _catalog = widget.catalog ?? SettlementCatalogService();
    unawaited(_loadMarketCatalog());
    unawaited(_loadChannelCategories());
    if (_showProductTemplates) unawaited(_loadImportTemplates());
    _scroll.addListener(_syncVisibleSection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibleSection());
  }

  @override
  void didUpdateWidget(covariant ProposalIntakeForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) {
      _reviewFormMode = false;
      _visibleSection = _isPurchase && !_protoForm
          ? ProposalIntakeNavSection.toc
          : (_taskSection ?? ProposalIntakeNavSection.market);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncVisibleSection(),
      );
    }
  }

  @override
  void dispose() {
    _estimateTick.dispose();
    _flashTimer?.cancel();
    _scroll.removeListener(_syncVisibleSection);
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
  /// 复核中默认也只看已填结果（原型简单行），点「完整表单」才回到可改的表单。
  bool get _showSelectedAsText =>
      _row.status == 'pending_president' ||
      (_row.status == 'done' && !_row.isTechRevising) ||
      _reviewSimpleRows;

  /// 复核中是否切回了完整表单（默认 false = 原型简单行）。
  bool _reviewFormMode = false;

  /// 复核中能在「简单行 / 完整表单」之间切换。
  bool get _canToggleReviewForm =>
      _protoForm &&
      kProposalSimpleViewEnabled &&
      _isReviewing &&
      !_row.isTechRevising &&
      _row.status != 'pending_president' &&
      _row.status != 'done';

  /// 复核中默认原型简单行：一行一条、只读，复核人在行右侧点「通过 / 有问题」。
  bool get _reviewSimpleRows => _canToggleReviewForm && !_reviewFormMode;

  /// 当前字段不能改时只展示已填值，避免复核人看到锁住的大输入框。
  bool _readValuesOnly(bool enabled) => _showSelectedAsText || !enabled;

  bool get _isReviewing =>
      _stage == 'reviewing' ||
      _stage == 'awaiting_submit' ||
      _stage == 'tech_reviewing';

  /// 待最终确认或已完成后整单只读；复核中提交人仍可改未复核内容。
  bool get _isContentFrozen =>
      _row.status == 'pending_president' ||
      (_row.status == 'done' && !_row.isTechRevising) ||
      _isReviewing;

  int _ownerId(String key) => int.tryParse(_text('${key}UserId')) ?? 0;

  bool get _isSubmitter => _me > 0 && _row.createdBy == _me;

  /// 复核中还能改内容的人：提交人（未复核的部分）、财务部负责人二（财务未整板块通过前）、
  /// 市场部负责人一（业务成本）。规则和原来完整表单一样，这里只决定给不给「修改内容」入口。
  bool get _canEditDuringReview =>
      _canEditAsSubmitter ||
      _canEditUnreviewedFinance ||
      _canEditBusinessCost;

  bool _isOwner(String key) => _me > 0 && _ownerId(key) == _me;

  bool _moduleReviewed(String flag) => _review[flag] == true;

  String _itemParentFlag(String section) {
    if (section.startsWith('financeItem:')) return 'financeCompleted';
    if (section.startsWith('technologyItem:')) return 'technologyCompleted';
    if (section.startsWith('contractItem:purchase.')) {
      return 'purchaseContractCompleted';
    }
    if (section.startsWith('contractItem:sales.')) {
      return 'salesContractCompleted';
    }
    return '';
  }

  bool _reviewLocksField({String? resetReview, String? reviewSection}) {
    if (_row.isTechRevising) return false;
    final section = reviewSection?.trim() ?? '';
    if (section.isNotEmpty) {
      if (_itemReviewed(section)) return true;
      if (_itemRejectComment(section).isNotEmpty) return false;
      final parent = _itemParentFlag(section);
      if (parent.isNotEmpty && _moduleReviewed(parent)) return true;
    }
    final flag = resetReview?.trim() ?? '';
    return flag.isNotEmpty && _moduleReviewed(flag);
  }

  bool get _canEditAsSubmitter =>
      !_isLocked &&
      !_row.techRevisionOpen &&
      (_isSubmitter || widget.session.proposalIntakeViewAll);

  /// 科技板块复核人：已指定则只认科技部负责人；旧单未指定时回退提交人。
  bool get _isTechReviewer {
    if (_me <= 0) return false;
    final owner = _ownerId('technologyOwner');
    if (owner > 0) return owner == _me;
    return _row.createdBy == _me;
  }

  /// 科技逐条复核人：已指定则只认负责二；旧单未指定时回退提交人。
  bool get _isMarketOwner2 {
    if (_me <= 0) return false;
    final owner = _ownerId('marketOwner2');
    if (owner > 0) return owner == _me;
    return _row.createdBy == _me;
  }

  bool get _isTechFiller => _isTechReviewer;

  bool get _isPresident {
    if (proposalIntakeMockPresident(
      _me,
      enabled: kProposalLocalPresidentMock,
      localHost: DunesDefaults.localLighthouseAccessBypass,
    )) {
      return true;
    }
    if (_me <= 0) return false;
    if (widget.options.presidentUserIds.isNotEmpty) {
      return widget.options.isConfiguredPresident(_me);
    }
    return _isOwner('president');
  }

  String get _stage => _row.resolvedStage;

  bool get _canEditProposalSubtitle =>
      _isOwner('financeOwner2') &&
      !_isLocked &&
      !_showSelectedAsText &&
      !_row.techRevisionOpen;

  bool get _canEditMarket =>
      _canEditAsSubmitter && !_moduleReviewed('marketCompleted');

  bool get _canEditTech {
    if (_isLocked || _showSelectedAsText) return false;
    if (!(_isSubmitter || widget.session.proposalIntakeViewAll)) return false;
    if (_row.isTechRevising) return true;
    if (_row.techRevisionOpen) return false;
    return !_moduleReviewed('technologyCompleted');
  }

  bool get _canEditProducts {
    if (_isLocked || _showSelectedAsText) return false;
    if (!(_isSubmitter || widget.session.proposalIntakeViewAll)) return false;
    if (_row.isTechRevising) return true;
    if (_row.techRevisionOpen) return false;
    if (_itemReviewed('technologyItem:$kProposalSkuProductsReviewKey')) {
      return false;
    }
    return !_moduleReviewed('technologyCompleted');
  }

  bool get _canEditFinanceInterface =>
      _isOwner('financeOwner2') && (!_isContentFrozen || _row.isTechRevising);

  bool get _canEditProductFiles =>
      _canEditMarket ||
      (_row.isTechRevising && (_isTechFiller || _isSubmitter));

  bool get _canEditSkuSettlements {
    if (_showSelectedAsText || _isLocked || _row.techRevisionOpen) {
      return false;
    }
    if (!(_canEditAsSubmitter || _isOwner('financeOwner2'))) return false;
    if (!_moduleReviewed('financeCompleted')) return true;
    return _hasRejectedSkuSettlement;
  }

  bool get _hasRejectedSkuSettlement {
    for (final key in proposalIntakeSkuSettleReviewKeys(_form)) {
      final section = 'financeItem:$key';
      if (!_itemReviewed(section) && _itemRejectComment(section).isNotEmpty) {
        return true;
      }
    }
    for (final key in proposalIntakeLegacySkuSettleReviewKeys(_form)) {
      final section = 'financeItem:$key';
      if (!_itemReviewed(section) && _itemRejectComment(section).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _skuSettleItemLocked(
    String reviewPrefix,
    String skuId,
    String settleId,
  ) {
    return _reviewLocksField(
          resetReview: 'financeCompleted',
          reviewSection: 'financeItem:$kProposalSkuSettlementsReviewKey',
        ) ||
        _reviewLocksField(
          resetReview: 'financeCompleted',
          reviewSection: 'financeItem:$reviewPrefix:$skuId:$settleId',
        );
  }

  bool _skuSettleRowLocked(
    String reviewItemPrefix,
    String reviewPrefix,
    String skuId,
    String settleId,
  ) {
    if (reviewItemPrefix != 'financeItem') return false;
    return _skuSettleItemLocked(reviewPrefix, skuId, settleId);
  }

  List<String> get _financeReviewKeys => _isPurchase
      ? const []
      : [..._kFinanceReviewKeys, ...proposalIntakeSkuSettleReviewKeys(_form)];

  bool get _canSeeHun => _isMarketOwner1;

  bool get _canEditHun =>
      _canSeeHun &&
      !_isLocked &&
      !_showSelectedAsText &&
      !_row.techRevisionOpen &&
      !_moduleReviewed('marketCompleted');

  String get _submitterName {
    final named = _personNameById(_row.createdBy);
    if (named.isNotEmpty) return named;
    if (_isSubmitter) return (widget.session.displayName ?? '').trim();
    return _row.createdBy > 0 ? '用户${_row.createdBy}' : '';
  }

  bool get _isMarketOwner1 => _isOwner('marketOwner1');

  bool get _isAnyOwner2 =>
      _isOwner('financeOwner2') || _isOwner('marketOwner2');

  bool get _businessCostSealed =>
      _form['businessCostRedacted'] == true ||
      (_isAnyOwner2 && !_isMarketOwner1);

  bool get _canEditBusinessCost =>
      !_isLocked &&
      _isMarketOwner1 &&
      _stage == 'reviewing' &&
      !_moduleReviewed('financeCompleted');

  bool get _canSave {
    if (!proposalIntakeCanPatchDraft(
      _row,
      userId: _me,
      viewAll: widget.session.proposalIntakeViewAll,
    )) {
      return false;
    }
    return (_row.isTechRevising &&
            (_isSubmitter ||
                widget.session.proposalIntakeViewAll ||
                _isTechReviewer)) ||
        _canEditBusinessCost ||
        _canEditHun ||
        _canEditProposalSubtitle ||
        _canEditUnreviewedFinance ||
        _canEditFinanceInterface ||
        _canEditAsSubmitter;
  }

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
      _row.id > 0 && !_isLocked && _isSubmitter && _stage == 'awaiting_tech';

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

  String _submitterBannerName() {
    final name = _row.initiatorDisplayName(widget.people).trim();
    if (name.isEmpty || name == '未指定') return '提交人';
    return '提交人$name';
  }

  bool get _canRemind {
    if (_row.id <= 0) return false;
    return proposalIntakeRemindRecipients(
      row: _row,
      people: widget.people,
      options: widget.options,
    ).isNotEmpty;
  }

  bool get _canDelete => _row.id > 0 && _row.canDeleteBy(_me);

  void _markFormDirty([bool value = true]) {
    if (_dirty == value) return;
    _dirty = value;
    widget.onDirtyChanged?.call(value);
  }

  /// 提交人或财务部负责人二可改未复核的财务供给侧 / 渠道侧 / 账户字段。
  bool get _canEditUnreviewedFinance =>
      !_isLocked &&
      !_row.techRevisionOpen &&
      (_canEditAsSubmitter ||
          (_isOwner('financeOwner2') &&
              (_isReviewing ||
                  _stage == 'awaiting_tech' ||
                  _stage == 'tech_revising') &&
              !_moduleReviewed('financeCompleted')));

  /// 项目成本：填写中由填写人点选；提交后由财务部负责人二在进复核前填写。
  bool get _canEditProjectCostChips {
    if (_isLocked || _showSelectedAsText || _row.techRevisionOpen) {
      return false;
    }
    if (_moduleReviewed('financeCompleted')) return false;
    if (_isOwner('financeOwner2') &&
        (_stage == 'awaiting_tech' ||
            _stage == 'tech_revising' ||
            _isReviewing)) {
      return true;
    }
    return _canEditAsSubmitter &&
        (_stage == 'filling' || _stage == 'draft' || _stage.isEmpty);
  }

  List<String> get _projectCostItemNames =>
      widget.options.resolvedProjectCostItems;

  bool _fillEnabled(
    bool? writable, {
    String? resetReview,
    String? reviewSection,
  }) {
    final locked = _reviewLocksField(
      resetReview: resetReview,
      reviewSection: reviewSection,
    );
    if (writable != null) return writable && !locked;
    return _canEditAsSubmitter && !locked;
  }

  bool _canEditContractExtras(String prefix) =>
      _canEditAsSubmitter &&
      !_reviewLocksField(resetReview: '${prefix}ContractCompleted');

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Widget _readonlySelectedText(String value, {int? maxLines}) {
    final text = value.trim();
    final display = text.isEmpty ? '未填写' : text;
    final style = TextStyle(
      fontSize: 13,
      height: 1.35,
      fontWeight: _protoForm
          ? FontWeight.w400
          : (text.isEmpty ? FontWeight.w500 : FontWeight.w600),
      color: text.isEmpty
          ? DunesColors.resolve(context, ProposalPalette.text3)
          : DunesColors.resolve(context, ProposalPalette.text),
    );
    // 空值只占一行。大 maxLines 在 Flutter web 上会按 HTML rows 留白。
    final hug = text.isEmpty || maxLines == 1;
    final child = SizedBox(
      width: double.infinity,
      child: hug
          ? Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            )
          // 原型简单行：默认一行，放不下给「展开」。
          : _simpleView && maxLines == null
          ? ProposalOneLineText(display, style: style)
          : SelectableText(display, maxLines: maxLines, style: style),
    );
    if (_viewUnderline) return ProposalDashedUnderline(child: child);
    return child;
  }

  /// 查看/审批态（复核中、待最终确认、已完成）只读值画紫色虚线；填写态不变。
  bool get _viewUnderline => kProposalViewUnderlineEnabled && _isContentFrozen;

  bool _reviewEnabled(String? section) {
    if (section == null || _me <= 0) return false;
    if (section.startsWith('technologyItem:')) {
      if (!_isTechReviewer) return false;
      return _isReviewing || _stage == 'awaiting_tech';
    }
    if (!_isReviewing) return false;
    if (section.startsWith('financeItem:')) {
      return !_row.techRevisionOpen && _isOwner('financeOwner2');
    }
    if (section.startsWith('contractItem:')) {
      return !_row.techRevisionOpen && _isOwner('financeOwner2');
    }
    return false;
  }

  bool _moduleReviewEnabled(String keyName) {
    if (!_isReviewing || _me <= 0) return false;
    if (_row.techRevisionOpen) {
      return switch (keyName) {
        'marketCompleted' => _isOwner('marketOwner1'),
        'technologyCompleted' => _isTechReviewer,
        _ => false,
      };
    }
    return switch (keyName) {
      'marketCompleted' => _isOwner('marketOwner1'),
      'technologyCompleted' => _isTechReviewer,
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
      'technology' || 'technologyCompleted' => '科技部负责人',
      'financeInterface' || 'financeInterfaceCompleted' => '科技部负责人',
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
    if (_row.status == 'reviewing' || _isReviewing) return _row.status;
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
    if (key == 'financeInterfaces') {
      if (_moduleReviewed('technologyCompleted') ||
          _itemReviewed('technologyItem:financeInterfaces')) {
        return;
      }
    } else if (resetReview != null &&
        _moduleReviewed(resetReview) &&
        _review['reviewRejected'] != true) {
      return;
    }
    var form = Map<String, dynamic>.from(_form)..[key] = value;
    if (proposalIntakeIsProductFinanceField(key)) {
      form = proposalIntakeWriteProductFinance(
        form,
        owner: kProposalProductFinanceMain,
        finance: {
          ...proposalIntakeProductFinance(
            form,
            owner: kProposalProductFinanceMain,
          ),
          key: value,
        },
      );
    }
    var estimated = false;
    if (proposalIsFinanceEstimateInputKey(key)) {
      final before = Map<String, dynamic>.from(form);
      form = proposalApplyEstimatedFinanceCosts(
        form,
        businessCatalog: widget.options.businessCostItemOptions,
        costCatalog: widget.options.costItemOptions,
        costNames: _projectCostItemNames,
      );
      _bumpCostAmountStamps(before, form);
      estimated = true;
    }
    form = _keepUnreviewed(form);
    final review = Map<String, dynamic>.from(_review);
    if (key == 'financeInterfaces') {
      review['technologyCompleted'] = false;
      review['financeInterfaceCompleted'] = false;
      final items = review['technologyItems'];
      if (items is Map) {
        final nextItems = Map<String, dynamic>.from(items);
        nextItems.remove('financeInterfaces');
        review['technologyItems'] = nextItems;
      }
    } else if (resetReview != null) {
      review[resetReview] = false;
      if (key == 'rollback') {
        final items = review['technologyItems'];
        if (items is Map) {
          review['technologyItems'] = Map<String, dynamic>.from(items)
            ..remove(kProposalSkuProductsReviewKey);
        }
      }
    }
    _markFormDirty();
    _row = _row.copyWith(
      title: key == 'proposalName' ? '$value'.trim() : _row.title,
      status: _statusAfterEdit,
      form: form,
      review: review,
    );
    if ((rebuild || estimated) && mounted) setState(() {});
    _emitChanged(_row);
  }

  void _setTechSyncSource(CatalogRef? value) {
    if (_moduleReviewed('technologyCompleted') &&
        _review['reviewRejected'] != true) {
      return;
    }
    if (_itemReviewed('technologyItem:syncSourceRef')) return;
    var form = proposalIntakeApplyFormSyncSource(
      _form,
      value,
      overwriteSkus: !kProposalSkuChannelSettingsEnabled,
    );
    form = _keepUnreviewed(form);
    final review = Map<String, dynamic>.from(_review)
      ..['technologyCompleted'] = false;
    final items = review['technologyItems'];
    if (items is Map) {
      review['technologyItems'] = Map<String, dynamic>.from(items)
        ..remove('syncSourceRef');
    }
    _markFormDirty();
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (value != null && value.isNotEmpty) {
      _prefetchSettle(
        _boundSyncSourceCode(value.code, name: value.name),
        'CHANNEL',
      );
    }
    if (mounted) setState(() {});
    _emitChanged(_row);
  }

  void _bumpCostAmountStamps(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    const keys = [
      'operatingCostItemAmounts',
      'taxCostItemAmounts',
      'businessCostItemAmounts',
      'costItemAmounts',
    ];
    for (final amountsKey in keys) {
      final prev = proposalCostAmountMap(before[amountsKey]);
      final next = proposalCostAmountMap(after[amountsKey]);
      for (final entry in next.entries) {
        if (prev[entry.key] != entry.value) {
          void bump(String id) {
            if (id.isEmpty) return;
            final stampKey = '$amountsKey::$id';
            _costAmountStamp[stampKey] = (_costAmountStamp[stampKey] ?? 0) + 1;
          }

          bump(entry.key);
          bump(proposalProjectCostDisplayName(entry.key));
        }
      }
    }
  }

  Map<String, dynamic> _withEstimatedFinanceCosts(Map<String, dynamic> form) {
    final before = Map<String, dynamic>.from(form);
    final next = proposalApplyEstimatedFinanceCosts(
      form,
      businessCatalog: widget.options.businessCostItemOptions,
      costCatalog: widget.options.costItemOptions,
      costNames: _projectCostItemNames,
    );
    _bumpCostAmountStamps(before, next);
    return _keepUnreviewed(next);
  }

  Map<String, dynamic> _persistableForm(Map<String, dynamic> form) {
    return proposalIntakeBuildPersistForm(
      form,
      keepUnreviewed: _keepUnreviewed,
      businessCatalog: widget.options.businessCostItemOptions,
      costCatalog: widget.options.costItemOptions,
      costNames: _projectCostItemNames,
    );
  }

  Map<String, dynamic> _keepUnreviewed(Map<String, dynamic> form) {
    return proposalIntakeKeepUnreviewedForm(
      baseline: _serverForm,
      current: form,
      review: _review,
    );
  }

  Widget? _costFormulaHint(String name, {String? fallback}) {
    final help = proposalCostFormulaHelpOf(
      name: name,
      form: _form,
      businessCatalog: widget.options.businessCostItemOptions,
      costCatalog: widget.options.costItemOptions,
    );
    final formula = (help?.formula ?? fallback ?? '').trim();
    if (formula.isEmpty) return null;
    return ProposalFormulaHint(
      key: ValueKey('cost-formula-$name'),
      formula: formula,
      detail: help?.substitution ?? '',
    );
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
      _markFormDirty();
      _fieldEpoch++;
      _row = _row.copyWith(
        form: form,
        review: proposalIntakeClearContractReview(_review, prefix: prefix),
        status: _statusAfterEdit,
      );
    });
    _emitChanged(_row);
  }

  void _setHasExistingPurchaseProposal(bool enabled) {
    if (!_canEditContractExtras('purchase')) return;
    final form = Map<String, dynamic>.from(_form)
      ..addAll(proposalIntakeResetContractFields('purchase'))
      ..['purchaseMode'] = ''
      ..['hasExistingPurchaseProposal'] = enabled
      ..['linkedPurchaseProposalId'] = null
      ..['linkedPurchaseProposalCode'] = ''
      ..['linkedPurchaseProposalTitle'] = '';
    setState(() {
      _markFormDirty();
      _fieldEpoch++;
      _purchaseProposalHits = const [];
      _row = _row.copyWith(
        form: form,
        review: proposalIntakeClearContractReview(_review, prefix: 'purchase'),
        status: _statusAfterEdit,
      );
    });
    _emitChanged(_row);
  }

  Future<void> _searchApprovedPurchases(String keyword) async {
    final seq = ++_purchaseProposalSearchSeq;
    final needle = keyword.trim();
    if (needle.isEmpty) {
      if (mounted) setState(() => _purchaseProposalHits = const []);
      return;
    }
    try {
      final rows = await widget.service.fetchApprovedPurchases(keyword: needle);
      if (!mounted || seq != _purchaseProposalSearchSeq) return;
      setState(() => _purchaseProposalHits = rows);
    } catch (error) {
      if (!mounted || seq != _purchaseProposalSearchSeq) return;
      setState(() => _purchaseProposalHits = const []);
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _applyApprovedPurchase(ProposalApprovedPurchaseHit hit) async {
    if (!_canEditContractExtras('purchase')) return;
    final form = Map<String, dynamic>.from(_form)
      ..addAll(proposalIntakePatchFromApprovedPurchase(hit));
    final hasFile =
        '${form['purchaseFileName'] ?? ''}'.trim().isNotEmpty ||
        '${form['purchaseObjectKey'] ?? ''}'.trim().isNotEmpty;
    final contractId = hit.purchaseContractId;
    if (!hasFile && contractId != null && contractId > 0) {
      try {
        final detail = await widget.service.fetchContractDetail(contractId);
        form.addAll(
          proposalIntakeFilePatchFromContractDetail('purchase', detail),
        );
        form.addAll(proposalIntakeSyncContractCollections(form, 'purchase'));
      } catch (_) {
        // 合同字段仍可带入；源文件缺失时不阻断。
      }
    }
    if (!mounted) return;
    setState(() {
      _markFormDirty();
      _fieldEpoch++;
      _row = _row.copyWith(
        form: proposalIntakeRememberContractSnapshot(
          form: form,
          prefix: 'purchase',
        ),
        review: proposalIntakeClearContractReview(_review, prefix: 'purchase'),
        status: _statusAfterEdit,
      );
    });
    _emitChanged(_row);
    showProposalCenterToast(context, '已从采购提案带入合同内容，可再修改');
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

  Future<void> _showTechnologyOmissions(List<String> gaps) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('检查遗漏'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('科技板块还有未复核项，请先逐条点复核，再做整板块确认。'),
            const SizedBox(height: 10),
            for (final item in gaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $item'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('去复核'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmFinal({
    required String title,
    required String message,
    String confirmLabel = '确认',
    List<ProposalIntakeNotifyRecipient> recipients = const [],
    String recipientsHeading = '即将通知',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (recipients.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  recipientsHeading,
                  style: TextStyle(
                    color: DunesColors.resolve(ctx, ProposalPalette.text),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final item in recipients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· ${item.line}',
                      style: TextStyle(
                        color: DunesColors.resolve(ctx, ProposalPalette.text2),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.resolve(
                ctx,
                ProposalPalette.purpleDeep,
                role: DunesColorRole.surface,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _toastNotified(
    List<ProposalIntakeNotifyRecipient> notified, {
    String fallback = '',
  }) {
    final text = proposalIntakeNotifiedToast(notified);
    if (text.isNotEmpty) {
      showProposalCenterToast(context, text);
      return;
    }
    if (fallback.isNotEmpty) {
      showProposalCenterToast(context, fallback);
    }
  }

  Future<void> _setReview(String key, bool value) async {
    if (!value) return;
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return;
    }
    if (_isPurchase && key == 'marketCompleted') {
      final hun = proposalIntakePurchaseHunIssue(_form);
      if (hun != null) {
        widget.onError(hun);
        return;
      }
    }
    if (key == 'technologyCompleted') {
      final gaps = proposalIntakeTechnologyReviewGaps(_review, form: _form);
      if (gaps.isNotEmpty) {
        await _showTechnologyOmissions(gaps);
        return;
      }
    }
    final confirmed = await _confirmFinal(
      title: '确认本板块复核完成',
      message: '确认后该板块复核完成。这是本板块的最终确认，提交后不可直接撤回。',
      confirmLabel: '确认完成',
      recipients: proposalIntakeAfterReviewNotifyRecipients(
        row: _row,
        flag: key,
        approved: true,
        people: widget.people,
      ),
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
      setState(() => _row = saved.row);
      _emitChanged(saved.row);
      _toastNotified(saved.notified, fallback: '本板块已确认通过');
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _rejectReview(String key) async {
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return;
    }
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
        setState(() => _row = saved.row);
        _emitChanged(saved.row);
        _toastNotified(saved.notified, fallback: '已驳回');
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
      final beforeGaps = proposalIntakeTechnologyReviewGaps(
        _review,
        form: _form,
      );
      setState(() => _row = saved.row);
      _emitChanged(saved.row);
      final afterGaps = proposalIntakeTechnologyReviewGaps(
        _review,
        form: _form,
      );
      final techReady =
          beforeGaps.isNotEmpty &&
          afterGaps.isEmpty &&
          !_moduleReviewed('technologyCompleted');
      _toastNotified(
        saved.notified,
        fallback: techReady
            ? '逐条已完成，请到板块底部确认本板块。点保存不会结束复核。'
            : (value ? '已复核本条' : '已取消本条复核'),
      );
      if (techReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToTask();
        });
      } else if (value && section.startsWith('financeItem:skuSettle:')) {
        _advanceChildSettleReview(section);
      }
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

  int _technologyReviewedCount() => _technologyReviewFields
      .where(
        (key) =>
            proposalIntakeTechnologyItemReviewed(_review, key, form: _form),
      )
      .length;

  void _advanceChildSettleReview(String section) {
    final parts = section.split(':');
    if (parts.length < 4) return;
    final skuId = parts[2];
    if (!_isChildSkuId(skuId)) return;
    final sku = _sellableSkuById(skuId);
    if (sku == null) return;
    final done = proposalIntakeSkuSettlements(sku).every(
      (item) => _itemReviewed('financeItem:skuSettle:${sku.id}:${item.id}'),
    );
    if (!done) return;
    final children = proposalIntakeChildProducts(_form);
    final index = children.indexWhere((item) => item.id == skuId);
    for (var i = index + 1; i < children.length; i++) {
      final next = children[i];
      final pending = proposalIntakeSkuSettlements(next).any(
        (item) => !_itemReviewed('financeItem:skuSettle:${next.id}:${item.id}'),
      );
      if (pending) {
        _selectChildProduct(next.id);
        return;
      }
    }
  }

  bool _itemsReviewed(String prefix, List<String> keys) =>
      _reviewedCount(prefix, keys) == keys.length;

  List<String> _contractReviewFieldsOf(String prefix) => [
    ..._contractReviewFields,
    if (prefix == 'sales') ...['InvoiceType', 'InvoiceFlow'],
  ];

  List<String> _contractItemKeys(String prefix) =>
      _contractReviewFieldsOf(prefix).map((field) => '$prefix.$field').toList();

  List<String> _pendingContractReviewLabels(String prefix) =>
      _contractReviewFieldsOf(prefix)
          .where((field) => !_itemReviewed('contractItem:$prefix.$field'))
          .map((field) => _contractReviewFieldLabels[field] ?? field)
          .toList();

  /// 非复核模式下的复核状态指示：一个圆点代替整颗复核按钮。
  /// 已驳回时仍然把意见显示出来——那是必须看见的信息。
  Widget _financeReviewDot(String section, String pendingLabel) {
    final reviewed = _itemReviewed(section);
    final comment = _itemRejectComment(section);
    final rejected = comment.isNotEmpty && !reviewed;
    final color = reviewed
        ? DunesColors.resolve(context, ProposalPalette.green)
        : rejected
        ? DunesColors.resolve(context, const Color(0xFFB42318))
        : DunesColors.resolve(context, ProposalPalette.border);
    final dot = Tooltip(
      message: reviewed
          ? '已复核'
          : rejected
          ? '已驳回：$comment'
          : '待$pendingLabel',
      child: Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: DunesColors.resolveNullable(
            context,
            reviewed || rejected ? color : Colors.transparent,
            role: DunesColorRole.surface,
          ),
          border: Border.all(color: color, width: 1.4),
          shape: BoxShape.circle,
        ),
      ),
    );
    if (comment.isEmpty) return dot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        dot,
        const SizedBox(height: 4),
        Text(
          comment,
          style: TextStyle(
            color: DunesColors.resolveNullable(context, Color(0xFFB42318)),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget? _rowReviewToggle(String? section, String pendingLabel) {
    if (section == null) return null;
    // 子标题虽然也走 financeItem 复核键，但它长在市场部板块里，
    // 够不着财务板块的复核开关，保留完整按钮。
    // 原型简单行里直接给「有问题 / 通过」，不再先点「开始逐条复核」。
    if (!_financeReviewMode &&
        !_simpleView &&
        section.startsWith('financeItem:') &&
        section != 'financeItem:proposalSubtitle') {
      return _financeReviewDot(section, pendingLabel);
    }
    final reviewed = _itemReviewed(section);
    final comment = _itemRejectComment(section);
    final canAct = _reviewEnabled(section);
    final toggle = ProposalReviewToggle(
      reviewed: reviewed,
      rejected: comment.isNotEmpty && !reviewed,
      pendingLabel: pendingLabel,
      subtle: !_isPurchase,
      onPressed: canAct
          ? () => unawaited(_setItemReview(section, !reviewed))
          : null,
      onReject: canAct ? () => unawaited(_rejectItemReview(section)) : null,
    );
    if (comment.isEmpty) return toggle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        toggle,
        const SizedBox(height: 4),
        Text(
          comment,
          style: TextStyle(
            color: DunesColors.resolveNullable(context, Color(0xFFB42318)),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  String _itemRejectComment(String section) {
    final raw = _review['itemRejectComments'];
    if (raw is! Map) return '';
    return '${raw[section] ?? ''}'.trim();
  }

  Future<void> _rejectItemReview(String section) async {
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return;
    }
    final comment = await showProposalRejectDialog(
      context: context,
      title: '驳回本条',
      hint: '请填写这条字段的驳回意见。只退回本条，其他已复核字段仍保留。整板块仍可在底部直接驳回。',
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
        section,
        false,
        _row.version,
        comment: comment,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _row = saved.row);
        _emitChanged(saved.row);
        _toastNotified(saved.notified, fallback: '已驳回本条');
      });
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
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
    if (key == 'taxCostItems') {
      _setCostSelection(
        namesKey: 'taxCostItems',
        codesKey: 'taxCostItemCodes',
        amountsKey: 'taxCostItemAmounts',
        totalKey: 'taxCost',
        names: proposalToggleTaxCostItem(values, value),
        catalog: const [],
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
    final form = _withEstimatedFinanceCosts(
      proposalSyncCostSelection(
        form: _form,
        names: names,
        catalog: catalog,
        namesKey: namesKey,
        codesKey: codesKey,
        amountsKey: amountsKey,
        totalKey: totalKey,
        settleTermsKey: settleTermsKey,
      ),
    );
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
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
    var amounts = proposalCostAmountMap(_form[amountsKey]);
    if (value == null) {
      amounts.remove(id);
    } else {
      amounts[id] = value;
    }
    var form = Map<String, dynamic>.from(_form)
      ..[amountsKey] = {
        for (final entry in amounts.entries) entry.key: entry.value,
      }
      ..[totalKey] = proposalCostAmountTotal(amounts);
    form = proposalMarkCostAmountManual(form, amountsKey: amountsKey, id: id);
    form = _withEstimatedFinanceCosts(form);
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
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
    final form = _withEstimatedFinanceCosts(
      Map<String, dynamic>.from(_form)
        ..[settleTermsKey] = {
          for (final entry in map.entries) entry.key: entry.value.toJson(),
        },
    );
    final review = Map<String, dynamic>.from(_review)
      ..['financeCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
  }

  void _writeCostSettleRows({
    required String settleTermsKey,
    required String id,
    required List<ProposalFinanceSettleTerms> rows,
  }) {
    if (settleTermsKey == 'businessCostItemSettleTerms' &&
        !_canEditBusinessCost) {
      return;
    }
    final raw = _form[settleTermsKey];
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    map[id] = [for (final terms in rows) terms.toJson()];
    final form = _withEstimatedFinanceCosts(
      Map<String, dynamic>.from(_form)..[settleTermsKey] = map,
    );
    final review = Map<String, dynamic>.from(_review)
      ..['financeCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
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
    if (resetReview != null &&
        _moduleReviewed(resetReview) &&
        _review['reviewRejected'] != true) {
      return;
    }
    final form = Map<String, dynamic>.from(_form)..addAll(values);
    final review = Map<String, dynamic>.from(_review);
    if (resetReview != null) review[resetReview] = false;
    _markFormDirty();
    _row = _row.copyWith(
      title: values.containsKey('proposalName')
          ? '${values['proposalName'] ?? ''}'.trim()
          : _row.title,
      status: _statusAfterEdit,
      form: form,
      review: review,
    );
    if (rebuild && mounted) setState(() {});
    _emitChanged(_row);
  }

  Future<void> _loadMarketCatalog() async {
    final results = await Future.wait([
      _catalog.fetchProductCategoryL1(),
      _catalog.fetchProductCategoryL2(),
      _catalog.fetchProductCategoryL3(),
      _catalog.fetchProjects(),
      _catalog.fetchSyncSources(),
    ]);
    if (!mounted) return;
    setState(() {
      _sectorCatalog = results[0];
      _productCatalogAll = results[1];
      _productL3CatalogAll = results[2];
      _projectCatalog = results[3];
      _syncSourceCatalog = results[4];
    });
    unawaited(
      _loadProductL3(
        _formRef('productRef') ?? CatalogRef.fromName(_text('product')),
      ),
    );
  }

  Future<void> _loadProductL3(CatalogRef? product) async {
    final seq = ++_productL3Seq;
    if (product == null || product.isEmpty) {
      if (!mounted || seq != _productL3Seq) return;
      setState(() {
        _productL3ForCurrent = const [];
        _productL3LoadedKey = '';
      });
      return;
    }
    final cached = proposalIntakeProductL3ForProduct(
      _productL3CatalogAll,
      product: product,
    );
    if (mounted && seq == _productL3Seq) {
      setState(() {
        _productL3ForCurrent = cached;
        _productL3LoadedKey = product.identity;
      });
    }
    final parentCode = product.code.trim();
    final parentIdText = parentCode.isEmpty ? product.resolvedIdText : '';
    if (parentCode.isEmpty && parentIdText.isEmpty) return;
    final rows = await _catalog.fetchProductCategoryL3(
      parentCode: parentCode,
      parentIdText: parentIdText,
    );
    if (!mounted || seq != _productL3Seq) return;
    setState(() {
      _productL3ForCurrent = rows.isNotEmpty ? rows : cached;
      _productL3LoadedKey = product.identity;
    });
  }

  Future<void> _loadChannelCategories() async {
    final results = await Future.wait([
      _catalog.fetchChannelCategoryL1(),
      _catalog.fetchChannelCategoryL2(),
    ]);
    if (!mounted) return;
    setState(() {
      _channelCategoryL1 = results[0];
      _channelCategoryL2 = results[1];
    });
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

  Future<void> _searchSupplierProducts(
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
    final rows = await _catalog.fetchSupplierProducts(
      syncSource: source,
      keyword: query,
    );
    if (!mounted || _assetProductSearchSeq[rowId] != seq) return;
    setState(() {
      _assetProductSearching.remove(rowId);
      _assetProductHits[rowId] = rows;
    });
  }

  Future<void> _syncSupplierProductSettlement({
    required String rowId,
    required ChannelProductHit? hit,
  }) async {
    final seq = (_assetProductSyncSeq[rowId] ?? 0) + 1;
    _assetProductSyncSeq[rowId] = seq;
    if (hit == null || hit.id == null || hit.id! <= 0) {
      _assetProductSyncing.remove(rowId);
      _assetProductSyncHint.remove(rowId);
      if (mounted) setState(() {});
      return;
    }
    _assetProductSyncing.add(rowId);
    _assetProductSyncHint[rowId] = '正在同步结算规则…';
    if (mounted) setState(() {});
    final data = await _catalog.fetchSupplierProductSettlement(hit.id!);
    if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    if (data == null) {
      _assetProductSyncing.remove(rowId);
      _assetProductSyncHint[rowId] = '未查到该产品的结算规则，请手工填写';
      if (mounted) setState(() {});
      return;
    }
    final source = hit.syncSource.trim().isNotEmpty
        ? hit.syncSource.trim()
        : (proposalIntakeSupplyProducts(
                _form,
              ).where((item) => item.id == rowId).firstOrNull?.syncSourceCode ??
              '');
    final bundle = source.isEmpty
        ? const _SettleCatalogBundle()
        : await _ensureSettleBundle(
            syncSource: source,
            productSource: 'SUPPLIER',
          );
    if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    _assetProductSyncing.remove(rowId);
    final rows = proposalIntakeSettlementsFromChannelCatalog(
      data,
      fallbackChannel: hit.supplierRef,
      formulas: bundle.formulas,
      billTypes: bundle.billTypes,
    );
    _assetProductSyncHint[rowId] = data.items.isEmpty
        ? '该产品暂无结算行，请手工填写'
        : '已从资管同步 ${data.items.length} 条结算规则';
    _patchSupplyProduct(rowId, (current) {
      if (current.assetProduct?.id != hit.id) return current;
      return current.applyAssetProduct(hit, settlements: rows);
    });
  }

  Future<void> _syncAssetProductSettlement({
    required String rowId,
    required ChannelProductHit? hit,
  }) async {
    final seq = (_assetProductSyncSeq[rowId] ?? 0) + 1;
    _assetProductSyncSeq[rowId] = seq;
    if (hit == null || !hit.hasId) {
      _assetProductSyncing.remove(rowId);
      _assetProductSyncHint.remove(rowId);
      if (mounted) setState(() {});
      return;
    }
    _assetProductSyncing.add(rowId);
    _assetProductSyncHint[rowId] = '正在同步结算规则…';
    if (mounted) setState(() {});
    final isChild = _isChildSkuId(rowId);
    if (!isChild) {
      final packet = await _catalog.fetchChannelProductPacketItems(
        hit.id ?? 0,
        idText: hit.idText,
      );
      if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
      if (packet != null) {
        await _applyChannelPacket(
          rowId: rowId,
          hit: hit,
          packet: packet,
          seq: seq,
        );
        return;
      }
    }
    final data = await _catalog.fetchChannelProductSettlement(
      hit.id ?? 0,
      idText: hit.idText,
    );
    if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    if (data == null) {
      _assetProductSyncing.remove(rowId);
      _assetProductSyncHint[rowId] = '未查到该产品的结算规则，请财务手工填写';
      if (mounted) setState(() {});
      return;
    }
    final source = hit.syncSource.trim().isNotEmpty
        ? hit.syncSource.trim()
        : _assetRowSyncSource(rowId);
    final bundle = source.isEmpty
        ? const _SettleCatalogBundle()
        : await _ensureSettleBundle(
            syncSource: source,
            productSource: 'CHANNEL',
          );
    if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    _assetProductSyncing.remove(rowId);
    _assetProductSyncHint[rowId] = data.items.isEmpty
        ? '该产品暂无结算行，请财务手工填写'
        : '已从资管同步 ${data.items.length} 条结算规则';
    _patchSellableSku(rowId, (current) {
      if (current.assetProduct != hit) return current;
      if (data.items.isEmpty &&
          proposalIntakeSkuHasFilledSettlements(current)) {
        return current;
      }
      final rows = proposalIntakeSettlementsFromChannelCatalog(
        data,
        fallbackChannel: current.channelRef,
        formulas: bundle.formulas,
        billTypes: bundle.billTypes,
      );
      return current.applyAssetProduct(hit, settlements: rows);
    });
  }

  Future<ChannelProductPacket> _hydratePacketChildSettlements(
    ChannelProductPacket packet,
  ) async {
    if (packet.items.isEmpty) return packet;
    final items = await Future.wait([
      for (final item in packet.items) _hydratePacketItemSettlements(item),
    ]);
    return ChannelProductPacket(parent: packet.parent, items: items);
  }

  Future<ChannelProductPacketItem> _hydratePacketItemSettlements(
    ChannelProductPacketItem item,
  ) async {
    if (item.settlementItems.isNotEmpty) return item;
    if (!item.product.hasId) return item;
    final data = await _catalog.fetchChannelProductSettlement(
      item.product.id ?? 0,
      idText: item.product.idText,
    );
    return proposalIntakeHydratePacketItemSettlements(item, data);
  }

  Future<void> _applyChannelPacket({
    required String rowId,
    required ChannelProductHit hit,
    required ChannelProductPacket packet,
    required int seq,
  }) async {
    final source = hit.syncSource.trim().isNotEmpty
        ? hit.syncSource.trim()
        : _assetRowSyncSource(rowId);
    final parentBundle = source.isEmpty
        ? const _SettleCatalogBundle()
        : await _ensureSettleBundle(
            syncSource: source,
            productSource: 'CHANNEL',
          );
    if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    final hydrated = await _hydratePacketChildSettlements(packet);
    if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    final childSources = <String>{
      for (final item in hydrated.items)
        if (item.resolvedSyncSource.isNotEmpty) item.resolvedSyncSource,
    };
    final childBundles = <String, _SettleCatalogBundle>{};
    for (final childSource in childSources) {
      childBundles[childSource] = await _ensureSettleBundle(
        syncSource: childSource,
        productSource: 'CHANNEL',
      );
      if (!mounted || _assetProductSyncSeq[rowId] != seq) return;
    }
    final current = proposalIntakeSkuDetails(
      _form,
    ).where((item) => item.id == rowId).firstOrNull;
    if (current == null || current.assetProduct != hit) {
      _assetProductSyncing.remove(rowId);
      if (mounted) setState(() {});
      return;
    }
    final fill = proposalIntakeFillFromChannelPacket(
      hydrated,
      parentSkuId: rowId,
      parentChannel: current.channelRef,
      parentFormulas: parentBundle.formulas,
      parentBillTypes: parentBundle.billTypes,
      syncSourceOf: _syncSourceRefForCode,
      formulasOf: (code) => childBundles[code]?.formulas ?? const [],
      billTypesOf: (code) => childBundles[code]?.billTypes ?? const [],
    );
    _assetProductSyncing.remove(rowId);
    if (fill.hasChildren) {
      final childHint = fill.children.length == 1
          ? '1 个子产品'
          : '${fill.children.length} 个子产品';
      final childSettled = fill.children
          .where(proposalIntakeSkuHasFilledSettlements)
          .length;
      if (childSettled > 0) {
        _assetProductSyncHint[rowId] =
            '已从资管同步${packet.parent.items.isEmpty ? '' : ' ${packet.parent.items.length} 条'}结算规则，并带出$childHint及结算';
      } else if (packet.parent.items.isEmpty) {
        _assetProductSyncHint[rowId] = '已带出$childHint，结算请财务手工填写';
      } else {
        _assetProductSyncHint[rowId] =
            '已从资管同步 ${packet.parent.items.length} 条结算规则，并带出$childHint';
      }
    } else {
      _assetProductSyncHint[rowId] = packet.parent.items.isEmpty
          ? '该产品暂无结算行，请财务手工填写'
          : '已从资管同步 ${packet.parent.items.length} 条结算规则';
    }
    _writeExistingProductPacket(rowId: rowId, hit: hit, fill: fill);
    for (final child in fill.children) {
      if (proposalIntakeSkuHasFilledSettlements(child)) continue;
      final childHit = child.assetProduct;
      if (childHit == null || !childHit.hasId) continue;
      unawaited(_syncAssetProductSettlement(rowId: child.id, hit: childHit));
    }
  }

  CatalogRef? _syncSourceRefForCode(String code) {
    final key = code.trim();
    if (key.isEmpty) return null;
    for (final item in _syncSourceCatalog) {
      if (item.code.trim() == key) return item;
    }
    return CatalogRef(code: key, name: key);
  }

  List<CatalogRef> _businessPlatformOptions() =>
      widget.options.resolvedBusinessPlatforms;

  CatalogRef? _selectedBusinessPlatform(CatalogRef? current) {
    final options = _businessPlatformOptions();
    final hit = _selectedCatalog(current, options);
    if (hit != null) return hit;
    if (current == null || current.isEmpty) return null;
    final name = current.name.trim();
    final code = current.code.trim();
    for (final item in options) {
      final itemName = item.name.trim();
      final itemCode = item.code.trim();
      if (name.isNotEmpty &&
          (name == itemName ||
              name.startsWith(itemName) ||
              itemName.startsWith(name))) {
        return item;
      }
      if (code.isNotEmpty && (code == itemCode || itemCode == code)) {
        return item;
      }
    }
    return current;
  }

  String _boundSyncSourceCode(String code, {String name = ''}) {
    if (code.trim().isEmpty && name.trim().isEmpty) return '';
    final bound = proposalIntakeBindSyncSource(
      CatalogRef(
        code: code.trim().isEmpty ? name.trim() : code.trim(),
        name: name.trim().isEmpty ? code.trim() : name.trim(),
      ),
      _syncSourceCatalog,
    );
    final resolved = bound.code.trim();
    return resolved.isNotEmpty ? resolved : code.trim();
  }

  void _writeExistingProductPacket({
    required String rowId,
    required ChannelProductHit hit,
    required ProposalChannelPacketFill fill,
  }) {
    var form = Map<String, dynamic>.from(_form);
    final skus = [
      for (final row in proposalIntakeSkuDetails(form))
        if (row.id == rowId && row.assetProduct == hit)
          row.applyAssetProduct(hit, settlements: fill.parentSettlements)
        else
          row,
    ];
    form['skuDetails'] = [for (final row in skus) row.toJson()];
    if (fill.hasChildren) {
      final children = proposalIntakeReplacePacketChildren(
        current: proposalIntakeChildProducts(form),
        parentSkuId: rowId,
        packetChildren: fill.children,
      );
      form['childProducts'] = [for (final row in children) row.toJson()];
      form['childIsExistingBuilt'] = true;
      final quantities = <String, int>{
        for (final child in children)
          if (!fill.childQuantities.containsKey(child.id))
            child.id: proposalIntakeChildProductQuantity(form, child.id),
        ...fill.childQuantities,
      };
      final benefit = form['benefitProduct'] is Map
          ? Map<String, dynamic>.from(form['benefitProduct'] as Map)
          : <String, dynamic>{};
      benefit['skuQuantities'] = quantities;
      form['benefitProduct'] = benefit;
      if (fill.children.isNotEmpty) {
        _activeChildProductId = fill.children.first.id;
      }
    }
    form = proposalIntakeSyncChildProductMeta(form);
    form = _withEstimatedFinanceCosts(form);
    final review = Map<String, dynamic>.from(_review)
      ..['marketCompleted'] = false
      ..['financeCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (mounted) setState(() {});
    _emitChanged(_row);
  }

  String _settleCacheKey(String syncSource, String productSource) =>
      '${syncSource.trim()}|${productSource.trim().toUpperCase()}';

  String _assetRowSyncSource(String rowId) {
    return proposalIntakeAllSellableSkus(
          _form,
        ).where((item) => item.id == rowId).firstOrNull?.syncSourceCode ??
        '';
  }

  Future<_SettleCatalogBundle> _ensureSettleBundle({
    required String syncSource,
    required String productSource,
  }) async {
    final source = syncSource.trim();
    final side = productSource.trim().toUpperCase();
    final key = _settleCacheKey(source, side);
    final cached = _settleBundles[key];
    if (cached != null) return cached;
    if (source.isEmpty) return const _SettleCatalogBundle();
    final inflight = _settleBundleLoads[key];
    if (inflight != null) return inflight;
    final future = _loadSettleBundle(key: key, source: source, side: side);
    _settleBundleLoads[key] = future;
    try {
      return await future;
    } finally {
      _settleBundleLoads.remove(key);
    }
  }

  Future<_SettleCatalogBundle> _loadSettleBundle({
    required String key,
    required String source,
    required String side,
  }) async {
    _settleLoading.add(key);
    try {
      final results = await Future.wait([
        side == 'SUPPLIER'
            ? _catalog.fetchSuppliers(syncSource: source)
            : _catalog.fetchChannels(syncSource: source),
        _catalog.fetchBillTypes(syncSource: source, productSource: side),
        _catalog.fetchSettleMethods(syncSource: source, productSource: side),
        _catalog.fetchFormulas(syncSource: source, productSource: side),
      ]);
      final bundle = _SettleCatalogBundle(
        channels: side == 'SUPPLIER' ? const [] : results[0],
        suppliers: side == 'SUPPLIER' ? results[0] : const [],
        billTypes: results[1],
        settleMethods: results[2],
        formulas: results[3],
      );
      _settleBundles[key] = bundle;
      return bundle;
    } catch (_) {
      return _settleBundles[key] ?? const _SettleCatalogBundle();
    } finally {
      _settleLoading.remove(key);
      if (mounted) setState(() {});
    }
  }

  void _prefetchSettle(String syncSource, String productSource) {
    if (syncSource.trim().isEmpty) return;
    unawaited(
      _ensureSettleBundle(syncSource: syncSource, productSource: productSource),
    );
  }

  List<CatalogRef> _sectorOptions() {
    if (_sectorCatalog.isNotEmpty) return _sectorCatalog;
    return [
      for (final item in widget.options.sectors) CatalogRef.fromName(item),
    ];
  }

  List<CatalogRef> _productOptions() {
    final filtered = proposalIntakeProductL2ForSector(
      _productCatalogAll,
      sector: _formRef('sectorRef') ?? CatalogRef.fromName(_text('sector')),
    );
    if (filtered.isNotEmpty || _productCatalogAll.isNotEmpty) return filtered;
    return [
      for (final item in widget.options.products)
        CatalogRef.fromName(item.value),
    ];
  }

  CatalogRef _selectedProduct() {
    return _formRef('productRef') ?? CatalogRef.fromName(_text('product'));
  }

  List<CatalogRef> _productL3Options() {
    final product = _selectedProduct();
    if (product.isEmpty) return const [];
    if (_productL3LoadedKey == product.identity) return _productL3ForCurrent;
    return proposalIntakeProductL3ForProduct(
      _productL3CatalogAll,
      product: product,
    );
  }

  String _productL3LoadingEmptyText() {
    if (_selectedProduct().isEmpty) return '请先选择产品（标签一）';
    if (_productL3CatalogAll.isEmpty && _productL3ForCurrent.isEmpty) {
      return '字典加载中或暂无子分类';
    }
    return '该产品暂无子分类';
  }

  List<CatalogRef> _projectOptions() {
    if (_projectCatalog.isNotEmpty) return _projectCatalog;
    return [
      for (final item in widget.options.products)
        if (item.value == _text('product'))
          for (final child in item.children) CatalogRef.fromName(child),
    ];
  }

  CatalogRef? _selectedCatalog(CatalogRef? current, List<CatalogRef> options) {
    if (current == null || current.isEmpty) return null;
    for (final item in options) {
      if (item == current) return item;
    }
    return catalogMatchByCode(current, options);
  }

  bool _formulaMatchesSettleXor(
    CatalogRef item, {
    required bool hasRatio,
    required bool hasPrice,
  }) {
    if (hasRatio == hasPrice) return true;
    final method = item.settleMethod.trim();
    if (method.isEmpty) return true;
    if (hasPrice) return method == '2' || method == '5';
    return method == '1' || method == '5';
  }

  List<CatalogRef> _withCurrent(List<CatalogRef> options, CatalogRef? current) {
    if (current == null || current.isEmpty) return options;
    if (options.any((item) => item == current)) return options;
    return [current, ...options];
  }

  /// 顶部「年化测算」格子的数据：只读汇总财务部同一套测算，不写回表单。
  /// 采购提案、或规模与收入利润都还没有时不显示。
  ProposalEstimateSummaryData? get _estimateSummaryData {
    if (!kProposalEstimateSummaryEnabled || _isPurchase) return null;
    final scope = proposalIntakeProductFinanceScope(
      _form,
      owner: kProposalProductFinanceMain,
    );
    // 与财务部字段同一套取数：_financeComputedMetric 给出的显示值。
    double? metric(String key) {
      final text = _financeComputedMetric(key, formOverride: scope)?.display;
      return text == null ? null : double.tryParse(text.trim());
    }

    double? stored(String key) => proposalIntakeFormHasText(scope, key)
        ? proposalFinanceAmount(scope, key)
        : null;

    final scaleValue = proposalEffectiveSalesScale(scope);
    final scale = scaleValue > 0 ? scaleValue : null;
    final revenue = proposalRevenueIsManual(scope)
        ? double.tryParse(_looseAmountText(scope['revenue']))
        : metric('revenue');
    final procurement =
        metric(kProposalCouponProcurementCostKey) ??
        stored(kProposalCouponProcurementCostKey);
    final profit = metric('profit');
    if (scale == null && revenue == null && profit == null) return null;
    final skus = proposalIntakeSkuDetails(scope);
    final faces = [
      for (final sku in skus)
        if (double.tryParse(sku.faceValue.trim()) case final v? when v > 0) v,
    ]..sort();
    final faceRange = faces.isEmpty
        ? ''
        : (faces.first == faces.last
              ? '面值 ${proposalFormatWan(faces.first)} 元'
              : '面值 ${proposalFormatWan(faces.first)}–${proposalFormatWan(faces.last)} 元');
    final rating = _rating;
    final o = widget.options;
    String wan(double v) => proposalEstimateGrouped(proposalFormatWan(v));
    final ratingRule = switch (rating) {
      'S' => '≥ ${wan(o.ratingS)}万',
      'A' => '${wan(o.ratingA)}–${wan(o.ratingS)}万',
      'B' => '${wan(o.ratingB)}–${wan(o.ratingA)}万',
      'C' => '< ${wan(o.ratingB)}万',
      _ => '',
    };
    return ProposalEstimateSummaryData(
      rating: rating,
      ratingRule: ratingRule,
      scale: scale,
      revenue: revenue,
      procurement: procurement,
      projectCost: stored('projectCost'),
      businessCost: stored('businessCost'),
      operatingCost: stored('operatingCost'),
      profit: profit,
      margin: metric('margin'),
      turnoverCash: metric(kProposalTurnoverCashKey),
      turnoverTimes: stored(kProposalTurnoverTimesKey),
      skuCount: skus.length,
      faceRange: faceRange,
      product: _text('product').trim(),
      channel: _estimateChannelText(skus),
      channelFromSku: _setOf('channels').isEmpty,
      channelKey: _skuCommonFields(skus).containsKey('channelCategory')
          ? 'skuCommon'
          : 'skuDetails',
      platform: _platformShortName,
    );
  }

  /// 科技部「τ-标签一」简称：去掉括号说明和空格后面的部分（如「三桶油（中石油…）」→「三桶油」）。
  String get _platformShortName {
    final raw = _text('technologyPlatform').trim();
    if (raw.isEmpty) return '';
    // 能源一律只写「三桶油」三个字。
    if (raw.contains('三桶油')) return '三桶油';
    final cut = raw.split(RegExp(r'[（(\s]')).first.trim();
    return cut.isEmpty ? raw : cut;
  }

  /// 顶部年化利润卡的「渠道」：市场部渠道；没有时取各产品的渠道分类（标签三），再没有取渠道名。
  String _estimateChannelText(List<ProposalSkuDetailRow> skus) {
    final channels = _setOf('channels');
    if (channels.isNotEmpty) return channels.join('、');
    final categories = <String>{
      for (final sku in skus)
        if ([
          proposalIntakeCategoryLabel(
            sku.resolvedChannelCategoryL1,
            sku.channelCategoryL1,
          ),
          proposalIntakeCategoryLabel(
            sku.resolvedChannelCategoryL2,
            sku.channelCategoryL2,
          ),
        ].where((item) => item.isNotEmpty).join(' / ') case final text
            when text.isNotEmpty)
          text,
    };
    if (categories.isNotEmpty) return categories.join('、');
    return {
      for (final sku in skus)
        if (sku.channelName.trim().isNotEmpty) sku.channelName.trim(),
    }.join('、');
  }

  /// 所有表单改动都经这里通知外层；顺带让顶部测算刷新。
  void _emitChanged(ProposalIntakeRow row) {
    _estimateTick.value++;
    widget.onChanged(row);
  }

  void _openEstimateSection(ProposalIntakeNavSection section) {
    setState(() {
      _visibleSection = section;
      _commentsTab = false;
      _contentOpenOverride = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToContentBox();
    });
  }

  /// 顶部测算里点「来自 xx ›」：打开对应板块，滚到那一行并闪一下；
  /// 那一行不在当前视图里（比如完整表单没有同名锚点）就停在「填报内容」框头。
  void _openEstimateField(ProposalIntakeNavSection section, String fieldKey) {
    setState(() {
      // 跳到 SKU 清单时把清单展开；只有一个产品时连它的明细（含渠道分类）也展开。
      if (fieldKey == 'skuDetails') {
        _simpleSkuListShown.add('tech');
        final skus = proposalIntakeSkuDetails(_form);
        if (skus.length == 1) {
          _simpleOpen.add(
            'sku:tech:${skus.first.id.isEmpty ? 0 : skus.first.id}',
          );
        }
      }
      _visibleSection = section;
      _commentsTab = false;
      _contentOpenOverride = true;
      _flashFieldKeys
        ..clear()
        ..add(fieldKey);
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _flashFieldKeys.clear());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _fieldAnchorKeys[fieldKey];
      final target = key?.currentContext?.findRenderObject();
      if (key != null && target != null && target.attached) {
        _jumpToKey(key, section);
      } else {
        _scrollToContentBox();
      }
    });
  }

  /// 把「填报内容」框头滚到视野顶部。
  void _scrollToContentBox() {
    final target = _contentBoxKey.currentContext?.findRenderObject();
    if (target == null || !target.attached || !_scroll.hasClients) return;
    unawaited(
      _scroll.position.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: .02,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      ),
    );
  }

  /// 原型「填报内容」简单行：待最终确认、已完成，以及复核中（默认）都用简单行。
  /// 复核中点「完整表单」可切回原表单：提交人改未复核的内容、财务填写都在那里。
  bool get _simpleView =>
      _protoForm && kProposalSimpleViewEnabled && _showSelectedAsText;

  /// 销售、采购提案的填写、复核、查看都用原型样式：名称在左、值在右的行，
  /// 虚线输入框，「有问题 / 通过」复核按钮。
  bool get _protoForm => kProposalPrototypeFormEnabled;

  /// 原型 .box：整页内容放进一个白色大框（最宽 1180，圆角 16）；手机上去掉外框。
  Widget _protoPageBox(Widget child, {required bool wide}) {
    if (!_protoForm) return child;
    final phone = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Container(
          key: const ValueKey('proposal-proto-page-box'),
          // 手机：白框贴边，上下左右只留 8，标题不再离顶栏那么远。
          padding: phone
              ? const EdgeInsets.fromLTRB(8, 8, 8, 10)
              : const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            border: phone
                ? null
                : Border.all(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFE7E3F2),
                      role: DunesColorRole.border,
                    ),
                  ),
            borderRadius: phone ? null : BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }

  /// 原型标题：紫色图标 + 「提案 · 名称 · 板块」+ 评级 + 状态，下面一行「供给 → 渠道 · 产品」。
  Widget _protoTitleBlock(bool wide) {
    final phone = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final sector = _text('sector').trim();
    final titleStyle = TextStyle(
      color: c(0xFF2A2638),
      fontSize: phone ? 16 : 18,
      fontWeight: FontWeight.w700,
    );
    final status = _protoStatusLabel;
    final rating = _headerRating;
    // 第一行：图标 + 「提案 · 名称 · 板块」+ 评级，始终同一行（名称放不下就省略）；
    // 第二行：状态、路线、进度说明，放不下再折行。
    return Padding(
      key: const ValueKey('proposal-proto-title'),
      padding: EdgeInsets.only(bottom: phone ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 抠图版图标：不要方块底，紫→蓝渐变的文件夹图标直接贴在标题前。
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7B5CF0), Color(0xFF4A83C4)],
                ).createShader(bounds),
                child: Icon(
                  Icons.assignment_rounded,
                  size: phone ? 20 : 24,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: phone ? 4 : 6),
              Text('提案 · ', style: titleStyle),
              Flexible(
                child: Text(
                  _headerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              if (sector.isNotEmpty) Text(' · $sector', style: titleStyle),
              if (rating != null) ...[
                SizedBox(width: phone ? 6 : 10),
                Tooltip(
                  message: '任务评级 $rating，按年化规模自动',
                  child: Container(
                    key: const ValueKey('proposal-top-rating'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: c(0xFF3F2A9A, DunesColorRole.surface),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      rating,
                      style: TextStyle(
                        color: c(0xFFFFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: kProposalProtoMono,
                        fontFamilyFallback: kProposalProtoMonoFallback,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: phone ? 4 : 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ProposalStatusPill(
                status: _protoStatusTone,
                label: status,
                dot: false,
              ),
              if (_topStatusLine.isNotEmpty)
                Text(
                  _topStatusLine,
                  style: TextStyle(color: c(0xFF8A8499), fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 被驳回的板块（market / tech / finance），没有驳回时为 null。
  ProposalIntakeNavSection? get _rejectedSection {
    if (_review['presidentRejected'] == true) return null;
    if (_review['reviewRejected'] != true) return null;
    final raw = '${_review['reviewRejectSection'] ?? ''}'.trim();
    if (raw.startsWith('market')) return ProposalIntakeNavSection.market;
    if (raw.startsWith('technology') || raw.startsWith('financeInterface')) {
      return ProposalIntakeNavSection.tech;
    }
    if (raw.isNotEmpty) return ProposalIntakeNavSection.finance;
    return null;
  }

  /// 原型标题旁的状态：比列表更细，写清卡在哪一步。
  String get _protoStatusLabel {
    if (_row.status == 'done') {
      return _row.techRevisionOpen ? '已完成 · 科技变更中' : '已完成';
    }
    if (_row.status == 'pending_president') return '待最终确认';
    if (_review['presidentRejected'] == true) return '总裁已驳回';
    final rejected = _rejectedSection;
    if (rejected != null) {
      return '${proposalIntakeNavSectionLabel(rejected)}已驳回';
    }
    return switch (_stage) {
      'awaiting_tech' || 'tech_revising' => '待财务填写',
      'awaiting_start_review' => '待提交复核',
      'reviewing' || 'tech_reviewing' => '复核中',
      'awaiting_submit' => '待通知最终人',
      _ => _row.status == 'draft' ? '草稿' : '填写中',
    };
  }

  /// 状态标签配色：驳回、待财务填写用橙色，复核类用橙色，确认类紫色，完成绿色。
  String get _protoStatusTone {
    if (_row.status == 'done') return 'done';
    if (_row.status == 'pending_president' || _stage == 'awaiting_submit') {
      return 'pending_president';
    }
    if (_review['presidentRejected'] == true ||
        _rejectedSection != null ||
        _stage == 'awaiting_tech' ||
        _stage == 'tech_revising' ||
        _isReviewing) {
      return 'reviewing';
    }
    return 'filling';
  }

  /// 原型「填报内容」标签下面那行：这一块谁填、谁复核。
  String get _protoTabWho {
    String owner(String prefix) {
      final name = proposalIntakeOwnerDisplayName(
        _form,
        prefix,
        people: widget.people,
      ).trim();
      return name.isEmpty ? '未指定' : name;
    }

    final submitter = _row.initiatorDisplayName(widget.people).trim();
    final sub = submitter.isEmpty ? '提交人' : '提交人 $submitter';
    if (_commentsTab) return '所有人可见，可 @ 相关人';
    if (_isPurchase) {
      return switch (_visibleSection) {
        ProposalIntakeNavSection.tech =>
          '$sub 填 · 科技部负责人 ${owner('technologyOwner')} 逐条复核',
        ProposalIntakeNavSection.finance =>
          '财务部负责人一 ${owner('financeOwner1')} · 财务部负责人二 ${owner('financeOwner2')} 复核采购合同 · 财务板块暂不复核',
        _ => '$sub 填 · 市场部负责人一 ${owner('marketOwner1')} 整板块复核 · 采购合同由财务部负责人二复核',
      };
    }
    return switch (_visibleSection) {
      ProposalIntakeNavSection.tech =>
        '$sub 填（含业务平台产品）· 科技部负责人 ${owner('technologyOwner')} 复核 · 财务技术接口由财务部负责人二填',
      ProposalIntakeNavSection.finance =>
        '$sub 填产品结算 · 财务部负责人二 ${owner('financeOwner2')} 填项目成本并逐条复核 · 财务部负责人一 ${owner('financeOwner1')} 整板块复核',
      ProposalIntakeNavSection.flow => '四流不用填：由市场、科技、财务三部分自动串联，只读',
      _ => '$sub 填 · 市场部负责人一 ${owner('marketOwner1')} 整板块复核',
    };
  }

  /// 原型字体：中文 Noto Sans SC（真粗体）、输入框同字体。只在原型样式下套。
  Widget _protoFonts(Widget child) {
    if (!_protoForm) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: kProposalProtoSans,
          fontFamilyFallback: kProposalProtoSansFallback,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: kProposalProtoSans,
          fontFamilyFallback: kProposalProtoSansFallback,
        ),
        child: child,
      ),
    );
  }

  /// 原型的白色内容框（填报内容 / 填写页的 box）。
  BoxDecoration get _protoBoxDecoration => BoxDecoration(
    color: DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    ),
    border: Border.all(
      color: DunesColors.resolve(
        context,
        const Color(0xFFE7E3F2),
        role: DunesColorRole.border,
      ),
    ),
    borderRadius: BorderRadius.circular(12),
  );

  /// 「填报内容」是否展开。原型：复核中、待最终确认、已完成默认收起，
  /// 但轮到你处理（有待办）时默认展开；填写中始终展开。
  bool? _contentOpenOverride;

  bool get _contentCollapsible => _protoForm && _isContentFrozen;

  bool get _contentOpen =>
      !_contentCollapsible ||
      (_contentOpenOverride ?? _taskAction.trim().isNotEmpty);

  /// 「评论」标签：原型把评论放在填报内容的标签里。
  bool _commentsTab = false;

  Widget _simpleContentBox(Widget panes) {
    if (!_protoForm) return panes;
    final open = _contentOpen;
    final frozen = _isContentFrozen;
    final showComments = widget.enableComments && _row.id > 0;
    final scoped = ProposalSimpleViewScope(
      readOnly: frozen,
      textRows: _simpleView,
      child: panes,
    );
    return KeyedSubtree(
      key: _contentBoxKey,
      child: Container(
        key: ValueKey(
          _simpleView ? 'proposal-simple-content' : 'proposal-proto-content',
        ),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: _protoBoxDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 原型：「填报内容」+ 板块标签（带 ✓ / 进度 / 只读 / 待办），按钮靠右。
            // 手机：全部塞进一行，放不下左右滑。
            _contentHeaderRow(open: open, showComments: showComments),
            if (open) ...[
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: _protoTabWho),
                    if (!frozen)
                      TextSpan(
                        text: ' · 紫色虚线下划线 = 你可以改',
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFF5B3FD0),
                          ),
                        ),
                      ),
                  ],
                ),
                style: TextStyle(
                  color: DunesColors.resolve(context, const Color(0xFF5B556A)),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Divider(
                height: 1,
                thickness: 1,
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFF3F0F8),
                  role: DunesColorRole.border,
                ),
              ),
              if (_commentsTab && showComments) ...[
                _commentsSection(),
                // 评论时各板块仍在树里（不显示），定位、跳转逻辑不受影响。
                Offstage(child: TickerMode(enabled: false, child: scoped)),
              ] else
                scoped,
            ] else
              // 收起时仍保留各板块（不显示），定位、四流跳转等逻辑不受影响。
              Offstage(child: TickerMode(enabled: false, child: scoped)),
          ],
        ),
      ),
    );
  }

  bool get _phoneWidth =>
      ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);

  Widget _contentHeaderRow({required bool open, required bool showComments}) {
    final phone = _phoneWidth;
    final title = Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        '填报内容',
        style: TextStyle(
          color: DunesColors.resolve(context, const Color(0xFF2A2638)),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final pills = <Widget>[
      for (final section in [
        ProposalIntakeNavSection.market,
        ProposalIntakeNavSection.tech,
        ProposalIntakeNavSection.finance,
        if (!_isPurchase) ProposalIntakeNavSection.flow,
      ])
        _protoSectionPill(
          section,
          selected: open && !_commentsTab && _visibleSection == section,
        ),
      if (showComments)
        _protoPill(
          key: const ValueKey('proposal-nav-comments'),
          label: '评论',
          selected: open && _commentsTab,
          onTap: () => setState(() {
            _commentsTab = true;
            _contentOpenOverride = true;
          }),
        ),
    ];
    final actions = <Widget>[
      // 简单版只读；能改内容的人（提交人、财务负责人二、市场部负责人一等）
      // 复核中给「修改内容」切到完整表单，改完点「回到简单版」。
      if (_canToggleReviewForm &&
          (_reviewFormMode || _canEditDuringReview) &&
          open &&
          !_commentsTab)
        _reviewFormToggleButton(),
      if (_contentCollapsible)
        OutlinedButton(
          key: const ValueKey('proposal-simple-content-toggle'),
          onPressed: () => setState(() => _contentOpenOverride = !open),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, phone ? 28 : 32),
            padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: DunesColors.resolve(
              context,
              const Color(0xFF3F2A9A),
            ),
            backgroundColor: DunesColors.resolve(
              context,
              const Color(0xFFFBFAFF),
              role: DunesColorRole.surface,
            ),
            side: BorderSide(
              color: DunesColors.resolve(
                context,
                const Color(0xFFCFC2F5),
                role: DunesColorRole.border,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(
            phone ? (open ? '收起' : '展开') : (open ? '收起 ▴' : '展开 ▾'),
          ),
        ),
    ];
    if (phone) {
      // 标签那段左右滑；「修改 / 收起」钉在右边，展开后也随手能收起。
      final tabs = [title, ...pills];
      return Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    tabs[i],
                  ],
                ],
              ),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 5), action],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [title, ...pills],
          ),
        ),
        for (final action in actions) ...[const SizedBox(width: 6), action],
      ],
    );
  }

  /// 复核中「简单行 / 完整表单」切换按钮。
  Widget _reviewFormToggleButton() {
    final simple = !_reviewFormMode;
    return Tooltip(
      message: simple ? '切回完整表单：改内容、看合同和结算的全部字段' : '回到原型简单行',
      child: OutlinedButton(
        key: const ValueKey('proposal-review-form-toggle'),
        onPressed: () => setState(() => _reviewFormMode = simple),
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, _phoneWidth ? 28 : 32),
          padding: EdgeInsets.symmetric(horizontal: _phoneWidth ? 8 : 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: DunesColors.resolve(
            context,
            const Color(0xFF5B556A),
          ),
          backgroundColor: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          side: BorderSide(
            color: DunesColors.resolve(
              context,
              const Color(0xFFE7E3F2),
              role: DunesColorRole.border,
            ),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        child: Text(
          simple
              ? (_phoneWidth ? '修改' : '修改内容')
              : (_phoneWidth ? '简单版' : '回到简单版'),
        ),
      ),
    );
  }

  // ── 原型简单行（复核中、待最终确认、已完成）──────────────────────────
  // 字段一行一条；负责人、合同、盈利模式、研发等合成一行；没填的选填项不显示。

  /// 简单行里的一行文字：名称在左，值在右，复核标记在最右。
  Widget _simpleLine(
    String label,
    String value, {
    String? anchorKey,
    bool required = false,
    bool fullWidth = false,
    Widget? trailing,
    String detail = '',
    List<Widget> extras = const [],
    List<(String, Widget)> sub = const [],
    String subKey = '',
  }) {
    // 主值一行；合并进来的次要字段用一行灰色小字跟在下面，不再各占一行。
    // 有 sub 时主值后面给「详情 ▾」，点开是一张小字段表（合同等）。
    final open = sub.isNotEmpty && _simpleOpen.contains(subKey);
    final Widget main = sub.isEmpty
        ? _readonlySelectedText(value)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _readonlySelectedText(value)),
                  _simpleTextButton(
                    open ? '收起 ▴' : '详情 ▾',
                    () => setState(() {
                      if (!_simpleOpen.remove(subKey)) _simpleOpen.add(subKey);
                    }),
                  ),
                ],
              ),
              if (open) _simpleKvTable(sub),
            ],
          );
    final field = ProposalField(
      label: label,
      required: required,
      trailing: trailing,
      child: detail.trim().isEmpty && extras.isEmpty
          ? main
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                main,
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _simpleDetailText(detail),
                ],
                if (extras.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Wrap(spacing: 10, runSpacing: 2, children: extras),
                ],
              ],
            ),
    );
    final Widget child = fullWidth ? _FullWidthField(child: field) : field;
    return anchorKey == null ? child : _anchor(anchorKey, child);
  }

  /// 简单行里点开的「详情」、产品：key 形如 contract:purchase、sku:tech:<id>。
  final Set<String> _simpleOpen = {};

  /// 原型里紫色小字按钮（详情 ▾ / 全部展开）。
  Widget _simpleTextButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, const Color(0xFF5B3FD0)),
          ),
        ),
      ),
    );
  }

  /// 小字段表：浅紫底、细框，每格「名称 值」，长值占整行（原型 .sub / .kv）。
  Widget _simpleKvTable(List<(String, Widget)> items, {Color? background}) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    Widget cell((String, Widget) item) => Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: c(0xFFF3F0F8, DunesColorRole.border)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              item.$1,
              style: TextStyle(fontSize: 12, height: 1.6, color: c(0xFF8A8499)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, height: 1.6, color: c(0xFF2A2638)),
              child: item.$2,
            ),
          ),
        ],
      ),
    );
    bool isWide((String, Widget) item) {
      final w = item.$2;
      return w is! Text || (w.data ?? '').runes.length > 28;
    }

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? c(0xFFFBFAFF, DunesColorRole.surface),
        border: Border.all(color: c(0xFFE7E3F2, DunesColorRole.border)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (_, box) {
          final columns = math.max(
            1,
            ((box.maxWidth + 18) / (260 + 18)).floor(),
          );
          final rows = <List<(String, Widget)>>[];
          var current = <(String, Widget)>[];
          for (final item in items) {
            if (isWide(item)) {
              if (current.isNotEmpty) rows.add(current);
              current = [];
              rows.add([item]);
              continue;
            }
            current.add(item);
            if (current.length == columns) {
              rows.add(current);
              current = [];
            }
          }
          if (current.isNotEmpty) rows.add(current);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows)
                row.length == 1 && isWide(row.first)
                    ? cell(row.first)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < columns; i++) ...[
                            if (i > 0) const SizedBox(width: 18),
                            Expanded(
                              child: i < row.length
                                  ? cell(row[i])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
            ],
          );
        },
      ),
    );
  }

  /// 小字段表里的一格文字。
  Widget _kvText(String value) =>
      Text(value.trim().isEmpty ? '—' : value.trim());

  /// 合并行下面那行灰色小字。
  Widget _simpleDetailText(String text) => SelectableText(
    text,
    style: TextStyle(
      fontSize: 11,
      height: 1.45,
      color: DunesColors.resolve(context, const Color(0xFF6E6880)),
    ),
  );

  /// 简单行里的小链接（合同文件、查看合同）。
  Widget _simpleLink(String text, VoidCallback? onTap, {IconData? icon}) {
    final color = DunesColors.resolve(context, const Color(0xFF5B3FD0));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「市场二 周宁 · 市场一 王一凡 · 运营 吴昊」：没指定的人不写。
  String _simplePeopleText(List<(String, String)> roles, {String extra = ''}) {
    return [
      for (final (role, key) in roles)
        if (_text(key).trim().isNotEmpty) '$role ${_text(key).trim()}',
      if (extra.trim().isNotEmpty) extra.trim(),
    ].join(' · ');
  }

  /// 最终确认人（管理后台配置），用于合并后的「负责人」一行。
  String get _simplePresidentText {
    final names = widget.options.presidentDisplayNames(widget.people).trim();
    return names.isEmpty ? '' : '最终确认 $names';
  }

  /// 合同合成一行：「编号 名称 · 对方签约主体 … · 有效期 … · 已签署」。
  /// 对方和有效期始终保留，没填写「未填写」。
  String _contractSimpleText(String prefix) {
    // 只写填了的部分，未填的不再逐项写「未填写」（点「详情」能看全部字段）。
    String t(String field) => _text('$prefix$field').trim();
    final mode = switch (t('Mode')) {
      '已签署合同' => '已签署',
      '未签署合同' => '未签署',
      final other => other,
    };
    final parts = [
      [t('No'), t('Name')].where((item) => item.isNotEmpty).join(' '),
      t('Counterparty'),
      t('ValidPeriod'),
      mode,
    ].where((item) => item.isNotEmpty).toList();
    return parts.isEmpty ? '未填写' : parts.join(' · ');
  }

  /// 合同一行：「编号 名称 · 对方 · 有效期 · 已签署」+「详情 ▾」，
  /// 点开是全部合同字段（签约主体、签署时间、发票、采购产品、源文件等）。
  /// 核心条款单独一行（见 [_contractTermsLine]）。
  Widget _contractSimpleLine(String title, String prefix) {
    String t(String key) => _text(key).trim();
    final files = _contractFiles(prefix);
    final opening = _openingContractPrefix == prefix;
    final hasSelected = proposalIntakeSelectedContractIds(
      _form,
      prefix,
    ).isNotEmpty;
    final fromProposal =
        !_isPurchase &&
        prefix == 'purchase' &&
        proposalIntakeHasExistingPurchaseProposal(_form);
    final links = [
      // 合同源文件：点文件名打开；已签合同没有文件时给「查看合同」。
      for (final file in files)
        _simpleLink(
          '${file['fileName'] ?? ''}'.trim().isEmpty
              ? '合同源文件'
              : '${file['fileName']}'.trim(),
          opening
              ? null
              : () => unawaited(_openContractSourceFile(prefix, file)),
          icon: Icons.description_outlined,
        ),
      if (files.isEmpty && hasSelected)
        _simpleLink(
          '查看合同',
          opening ? null : () => unawaited(_previewSelectedContract(prefix)),
          icon: Icons.open_in_new_rounded,
        ),
    ];
    return _simpleLine(
      title,
      _contractSimpleText(prefix),
      anchorKey: '${prefix}No',
      required: true,
      fullWidth: true,
      trailing: _contractSimpleToggle(prefix),
      subKey: 'contract:$prefix',
      sub: [
        if (fromProposal) ('来源', _kvText('已通过的采购提案带入')),
        ('合同状态', _kvText(t('${prefix}Mode'))),
        ('合同编号', _kvText(t('${prefix}No'))),
        ('合同名称', _kvText(t('${prefix}Name'))),
        ('签署时间', _kvText(t('${prefix}SignDate'))),
        ('我方签约主体', _kvText(t('${prefix}OurParty'))),
        ('对方签约主体', _kvText(t('${prefix}Counterparty'))),
        ('有效期', _kvText(t('${prefix}ValidPeriod'))),
        if (prefix == 'purchase')
          ('采购产品', _kvText(_setOf('purchaseProducts').join('、'))),
        if (prefix == 'sales') ...[
          ('发票种类', _kvText(t('salesInvoiceType'))),
          ('发票流', _kvText(t('salesInvoiceFlow'))),
        ],
        (
          '合同源文件',
          links.isEmpty
              ? _kvText('')
              : Wrap(spacing: 10, runSpacing: 2, children: links),
        ),
      ],
    );
  }

  /// 合同核心条款单独一行：默认一行，放不下给「展开」。
  Widget _contractTermsLine(String title, String prefix) => _simpleLine(
    title,
    _text('${prefix}CoreTerms'),
    anchorKey: '${prefix}CoreTerms',
    required: true,
    fullWidth: true,
  );

  /// 驳回意见（一行合并了几条字段时拼在一起）。
  List<String> _rowRejectComments(List<String> sections) => [
    for (final section in sections)
      if (!_itemReviewed(section) && _itemRejectComment(section).isNotEmpty)
        _itemRejectComment(section),
  ];

  Widget _withRejectComments(Widget toggle, List<String> comments) {
    if (comments.isEmpty) return toggle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        toggle,
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            comments.toSet().join('；'),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: DunesColors.resolveNullable(
                context,
                const Color(0xFFB42318),
              ),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  /// 合并行的复核：通过 = 这一行包含的字段逐条都通过；有问题 = 一起驳回。
  Widget? _mergedReviewToggle(
    List<String> sections, {
    String pendingLabel = '待复核',
  }) {
    final items = [
      for (final section in sections)
        if (section.trim().isNotEmpty) section,
    ];
    if (items.isEmpty) return null;
    if (items.length == 1) return _rowReviewToggle(items.first, pendingLabel);
    // 财务逐条复核没打开时，与其他财务字段一样只显示圆点。
    if (!_financeReviewMode &&
        !_simpleView &&
        items.every((item) => item.startsWith('financeItem:'))) {
      return _financeReviewDot(
        items.firstWhere(
          (item) => !_itemReviewed(item),
          orElse: () => items.first,
        ),
        pendingLabel,
      );
    }
    final reviewed = items.every(_itemReviewed);
    final comments = _rowRejectComments(items);
    final canAct = items.every(_reviewEnabled);
    return _withRejectComments(
      ProposalReviewToggle(
        reviewed: reviewed,
        rejected: comments.isNotEmpty && !reviewed,
        pendingLabel: pendingLabel,
        subtle: true,
        onPressed: canAct
            ? () => unawaited(_setItemsReview(items, !reviewed))
            : null,
        onReject: canAct ? () => unawaited(_rejectItemsReview(items)) : null,
      ),
      comments,
    );
  }

  /// 合同一行的复核：通过 = 全部合同字段通过并确认合同（会弹最终确认）。
  Widget? _contractSimpleToggle(String prefix) {
    final flag = '${prefix}ContractCompleted';
    final sections = [
      for (final key in _contractItemKeys(prefix)) 'contractItem:$key',
    ];
    final done = _review[flag] == true;
    final comments = _rowRejectComments(sections);
    final canAct =
        !done && _moduleReviewEnabled(flag) && sections.every(_reviewEnabled);
    return _withRejectComments(
      ProposalReviewToggle(
        reviewed: done,
        rejected: comments.isNotEmpty && !done,
        pendingLabel: '待复核',
        subtle: true,
        onPressed: canAct
            ? () => unawaited(_approveContractSimple(prefix))
            : null,
        onReject: canAct ? () => unawaited(_rejectItemsReview(sections)) : null,
      ),
      comments,
    );
  }

  Future<void> _approveContractSimple(String prefix) async {
    final sections = [
      for (final key in _contractItemKeys(prefix)) 'contractItem:$key',
    ];
    final ok = await _setItemsReview(sections, true, toast: false);
    if (!ok || !mounted) return;
    await _setReview('${prefix}ContractCompleted', true);
  }

  /// 一次复核几条字段（后端一次只收一条通过，逐条发）。
  Future<bool> _setItemsReview(
    List<String> sections,
    bool value, {
    bool toast = true,
  }) async {
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return false;
    }
    final pending = [
      for (final section in sections)
        if (_itemReviewed(section) != value) section,
    ];
    if (pending.isEmpty) return true;
    try {
      ProposalIntakeWriteResult? last;
      for (final section in pending) {
        final saved = await widget.service.saveReview(
          _row.id,
          section,
          value,
          _row.version,
        );
        if (!mounted) return false;
        setState(() => _row = saved.row);
        last = saved;
      }
      if (last != null) {
        _emitChanged(last.row);
        if (toast) {
          _toastNotified(
            last.notified,
            fallback: value ? '已复核这一行' : '已取消这一行的复核',
          );
        }
      }
      return true;
    } catch (error) {
      widget.onError(friendlyErrorText(error));
      return false;
    }
  }

  /// 合并行一起驳回：同一条意见挂在这一行的每个字段上。
  Future<void> _rejectItemsReview(List<String> sections) async {
    if (sections.isEmpty) return;
    if (sections.length == 1) return _rejectItemReview(sections.first);
    if (_dirty) {
      widget.onError('请先保存最新修改后再复核');
      return;
    }
    final comment = await showProposalRejectDialog(
      context: context,
      title: '驳回这一行',
      hint: '请填写驳回意见。这一行的几项会一起退回填写人，其他已复核字段仍保留。',
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
        sections.first,
        false,
        _row.version,
        comment: comment,
        sections: sections,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _row = saved.row);
        _emitChanged(saved.row);
        _toastNotified(saved.notified, fallback: '已驳回');
      });
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  /// 财务供给侧 / 渠道侧合成一行：「按核销 · 月结 · 付款 广州宇天 · 工商银行 ****0457」。
  /// 只读展示时，账号类字段（结算账户、付款账户、收款账户）中间的数字打码。
  String _maskIfAccount(String key, String value) =>
      key.contains('Account') ? proposalMaskAccount(value) : value;

  Widget _financeSideSimpleLine(String title, List<(String, String)> fields) {
    final value = [
      for (final (key, label) in fields)
        if (_text(key).trim().isNotEmpty)
          key.contains('Payer') || key.contains('Payee')
              ? '${label.replaceAll('主体', '')} ${_text(key).trim()}'
              : _maskIfAccount(key, _text(key).trim()),
    ].join(' · ');
    return _simpleLine(
      title,
      value,
      anchorKey: fields.first.$1,
      required: true,
      fullWidth: true,
      trailing: _mergedReviewToggle([
        for (final (key, _) in fields) 'financeItem:$key',
      ], pendingLabel: _financeReviewLabel),
    );
  }

  /// 简单行里「产品结算」清单是否展开。
  bool _simpleSkuOpen = false;

  /// 产品结算收成一行（有子产品时用）：「30 个产品 · 共 30 条结算」+ 复核 + 展开。
  Widget _skuSettleSimpleLine() {
    final rows = proposalIntakeSkuDetails(_form);
    final settleCount = rows.fold<int>(
      0,
      (sum, row) => sum + proposalIntakeSkuSettlements(row).length,
    );
    final toggle =
        proposalIntakeSkuSettleReviewKeys(_form).isEmpty || _simpleSkuOpen
        ? null
        : _rowReviewToggle(
            'financeItem:$kProposalSkuSettlementsReviewKey',
            '待复核',
          );
    return _simpleLine(
      proposalIntakeHasChildProducts(_form)
          ? '$kProposalMainProductLabel结算'
          : '产品结算',
      rows.isEmpty
          ? ''
          : [
              '${rows.length} 个产品 · 共 $settleCount 条结算',
              if (proposalIntakeChildProducts(_form).isNotEmpty)
                '关联产品 ${proposalIntakeChildProducts(_form).length} 个',
            ].join(' · '),
      required: true,
      fullWidth: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rows.isNotEmpty) _simpleSkuToggleButton(rows.length),
          if (toggle != null) ...[const SizedBox(width: 8), toggle],
        ],
      ),
    );
  }

  /// 原型「展开 30 个 ▾ / 收起清单 ▴」：科技 SKU 清单、财务产品结算共用一个开关。
  Widget _simpleSkuToggleButton(int count) {
    final open = _simpleSkuOpen;
    return _simplePillButton(
      open ? '收起清单 ▴' : '展开 $count 个 ▾',
      () => setState(() => _simpleSkuOpen = !open),
    );
  }

  /// 展开了的产品清单（tech / finance）。默认都收起，点「展开 N 个」才一行一个产品列出来。
  final Set<String> _simpleSkuListShown = {};

  bool _simpleSkuListHidden(String scope) =>
      !_simpleSkuListShown.contains(scope);

  /// 产品清单的「收起清单 ▴ / 展开 30 个 ▾」。
  Widget _simpleSkuListButton(String scope, int count) {
    final hidden = _simpleSkuListHidden(scope);
    return _simplePillButton(
      hidden ? '展开 $count 个 ▾' : '收起清单 ▴',
      () => setState(() {
        if (!_simpleSkuListShown.remove(scope)) _simpleSkuListShown.add(scope);
      }),
    );
  }

  /// 原型的紫色细框小按钮（同「填报内容」右上角的「收起 ▴」）。
  Widget _simplePillButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        foregroundColor: DunesColors.resolve(context, const Color(0xFF3F2A9A)),
        backgroundColor: DunesColors.resolve(
          context,
          const Color(0xFFFBFAFF),
          role: DunesColorRole.surface,
        ),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            const Color(0xFFCFC2F5),
            role: DunesColorRole.border,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  /// 财务部简单行里，业务产品下面直接列出关联产品。不放进「展开 N 个」里，
  /// 那一层只展开业务产品自己的结算。
  Widget _simpleRelatedProductsSummary() {
    final lines = [
      for (final parent in proposalIntakeSkuDetails(_form))
        if (proposalIntakeChildProducts(
          _form,
        ).any((item) => item.parentSkuId == parent.id))
          _simpleRelatedProductLines(parent),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
    );
  }

  Widget _simpleRelatedProductLines(ProposalSkuDetailRow parent) {
    if (parent.id.isEmpty) return const SizedBox.shrink();
    final children = [
      for (final item in proposalIntakeChildProducts(_form))
        if (item.parentSkuId == parent.id) item,
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    final parentName = parent.displayName.trim().isEmpty
        ? kProposalMainProductLabel
        : parent.displayName.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$parentName 的关联产品',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final child in children)
            Text(
              [
                child.displayName.trim().isEmpty
                    ? '未命名关联产品'
                    : child.displayName.trim(),
                if (child.faceValue.trim().isNotEmpty)
                  '面值 ${child.faceValue.trim()}',
                '数量 ${proposalIntakeChildProductQuantity(_form, child.id)}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text),
                fontSize: 12,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }

  /// 一条结算写成一句：「比例 0.9805 · （销售 − 退款）× 结算比例 · 专票 · 13%」。
  String _settleTermsText(
    ProposalFinanceSettleTerms terms, {
    bool withBillType = true,
  }) {
    final ratio = terms.displayRatio.trim();
    final unit = terms.displayUnitPrice.trim();
    final tax = terms.taxRate.trim();
    final from = terms.effectiveTime.trim();
    final to = terms.expireTime.trim();
    return [
      if (withBillType) _settleBillName(terms),
      terms.settleMode.trim(),
      if (ratio.isNotEmpty) '比例 $ratio' else if (unit.isNotEmpty) '单价 $unit',
      terms.displayFormula.trim(),
      terms.invoiceType.trim(),
      if (tax.isNotEmpty) tax.endsWith('%') ? tax : '$tax%',
      if (from.isNotEmpty || to.isNotEmpty) '$from–$to',
      if (terms.ourParty.trim().isNotEmpty) '我方 ${terms.ourParty.trim()}',
      if (terms.counterparty.trim().isNotEmpty)
        '对方 ${terms.counterparty.trim()}',
    ].where((item) => item.isNotEmpty).join(' · ');
  }

  /// SKU 每个字段写成一小段（key 用来比对是不是所有产品都一样）。
  List<(String, String)> _skuFieldTexts(ProposalSkuDetailRow sku) {
    String t(String value) => value.trim();
    final face = t(sku.faceValue);
    final from = t(sku.effectiveDate);
    final to = t(sku.expireDate);
    final productCategory = [
      t(sku.productCategoryL1),
      t(sku.productCategoryL2),
    ].where((item) => item.isNotEmpty).join(' / ');
    final channelCategory = [
      proposalIntakeCategoryLabel(
        sku.resolvedChannelCategoryL1,
        sku.channelCategoryL1,
      ),
      proposalIntakeCategoryLabel(
        sku.resolvedChannelCategoryL2,
        sku.channelCategoryL2,
      ),
    ].where((item) => item.isNotEmpty).join(' / ');
    final platform = proposalIntakeCategoryLabel(sku.syncSourceRef, '');
    final sync = switch (t(sku.syncZhongyouHaoke)) {
      '是' => '同步中油好客',
      '否' => '不同步中油好客',
      '' => '',
      final other => '中油好客 $other',
    };
    final asset = (sku.assetProduct?.label ?? '').trim();
    return [
      ('face', face.isEmpty ? '' : '面值 $face 元'),
      ('coupon', t(sku.couponKind).isEmpty ? '' : '券种 ${t(sku.couponKind)}'),
      (
        'productCategory',
        productCategory.isEmpty ? '' : '产品分类 $productCategory',
      ),
      (
        'channelCategory',
        channelCategory.isEmpty ? '' : '渠道分类 $channelCategory',
      ),
      ('channel', sku.channelName.isEmpty ? '' : '渠道 ${sku.channelName}'),
      (
        'institution',
        sku.institutionName.isEmpty ? '' : '机构 ${sku.institutionName}',
      ),
      ('platform', platform.isEmpty ? '' : '业务平台 $platform'),
      ('valid', from.isEmpty && to.isEmpty ? '' : '有效期 $from–$to'),
      ('stock', t(sku.inventoryQty).isEmpty ? '' : '库存 ${t(sku.inventoryQty)}'),
      ('sync', sync),
      (
        'supplier',
        t(sku.supplierCodes).isEmpty ? '' : '供应商编码 ${t(sku.supplierCodes)}',
      ),
      ('rollback', t(sku.rollback).isEmpty ? '' : '回滚 ${t(sku.rollback)}'),
      (
        'existing',
        sku.isExistingBuilt ? (asset.isEmpty ? '已有产品' : '已有产品 $asset') : '',
      ),
      (
        'code',
        t(sku.partnerProductCode).isEmpty
            ? ''
            : '平台编码 ${t(sku.partnerProductCode)}',
      ),
      (
        'message',
        t(sku.platformMessage).isEmpty ? '' : '平台说明 ${t(sku.platformMessage)}',
      ),
      ('remark', t(sku.remark).isEmpty ? '' : '备注 ${t(sku.remark)}'),
    ];
  }

  /// 所有产品都一样的字段（至少两个产品时才算「共同项」）。
  Map<String, String> _skuCommonFields(List<ProposalSkuDetailRow> rows) {
    if (rows.length < 2) return const {};
    final first = {
      for (final (key, text) in _skuFieldTexts(rows.first))
        if (text.isNotEmpty) key: text,
    };
    for (final row in rows.skip(1)) {
      final mine = {for (final (key, text) in _skuFieldTexts(row)) key: text};
      first.removeWhere((key, text) => mine[key] != text);
    }
    return first;
  }

  /// 账单类型的末级名（「应收 / 销售回款 / 渠道结算」→「渠道结算」）。
  String _settleBillName(ProposalFinanceSettleTerms terms) {
    final raw = (terms.billTypeRef?.name ?? '').trim().isNotEmpty
        ? terms.billTypeRef!.name.trim()
        : terms.billType.trim();
    return raw.split('/').last.trim();
  }

  /// 一条结算的叫法，与原来的设计一致：「应收 · 渠道结算」「应付 · 采购结算」；
  /// 没选账单类型时写「应收一」「应付一」。同名的后面补序号。
  List<String> _settleRowLabels(List<ProposalSkuSettleRow> items) {
    final base = <String>[];
    final countBySide = <bool, int>{};
    for (final item in items) {
      final side = item.isCost ? '应付' : '应收';
      final name = _settleBillName(item.terms);
      final n = countBySide[item.isCost] ?? 0;
      countBySide[item.isCost] = n + 1;
      base.add(
        name.isEmpty
            ? proposalIntakeSettleLabel(n, kind: side)
            : '$side · $name',
      );
    }
    final seen = <String, int>{};
    return [
      for (final label in base)
        base.where((item) => item == label).length > 1
            ? '$label ${seen[label] = (seen[label] ?? 0) + 1}'
            : label,
    ];
  }

  /// 收入一的比例（没有比例时写单价），用于 SKU 清单每行。
  String _skuFirstIncomeRatio(ProposalSkuDetailRow sku) {
    for (final item in proposalIntakeSkuSettlements(sku)) {
      if (item.isCost) continue;
      final ratio = item.terms.displayRatio.trim();
      if (ratio.isNotEmpty) return ratio;
      final unit = item.terms.displayUnitPrice.trim();
      if (unit.isNotEmpty) return '单价 $unit';
    }
    return '—';
  }

  /// 一个产品整套结算的指纹：收入在前、成本在后，逐条写成一句。
  String _skuSettleSignature(ProposalSkuDetailRow sku) {
    final items = proposalIntakeSkuSettlements(sku);
    return [
      for (final item in items)
        if (!item.isCost) '收入:${_settleTermsText(item.terms)}',
      for (final item in items)
        if (item.isCost) '成本:${_settleTermsText(item.terms)}',
    ].join('|');
  }

  /// 最多产品共用的那套结算的指纹（「同上」的那一组）。
  String _commonSkuSettleSignature(List<ProposalSkuDetailRow> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      final key = _skuSettleSignature(row);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    var best = '';
    var bestCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  /// 「4 个：收入一 0.9755 · 3 个：收入一 0.9855；其余 22 个同上」。
  String _settleDiffText(
    List<ProposalSkuDetailRow> rows,
    ProposalSkuDetailRow commonSku,
  ) {
    final common = proposalIntakeSkuSettlements(commonSku);
    final commonSig = _skuSettleSignature(commonSku);
    String describe(ProposalSkuDetailRow sku) {
      final mine = proposalIntakeSkuSettlements(sku);
      final parts = <String>[];
      for (final cost in const [false, true]) {
        final a = [
          for (final item in common)
            if (item.isCost == cost) item,
        ];
        final b = [
          for (final item in mine)
            if (item.isCost == cost) item,
        ];
        final aLabels = _settleRowLabels(a);
        final bLabels = _settleRowLabels(b);
        for (var i = 0; i < math.max(a.length, b.length); i++) {
          final label = i < a.length ? aLabels[i] : bLabels[i];
          if (i >= b.length) {
            parts.add('无$label');
            continue;
          }
          final mineText = _settleTermsText(b[i].terms);
          if (i >= a.length) {
            parts.add('$label $mineText');
            continue;
          }
          if (mineText == _settleTermsText(a[i].terms)) continue;
          final ratioA = a[i].terms.displayRatio.trim();
          final ratioB = b[i].terms.displayRatio.trim();
          final onlyRatio =
              ratioA != ratioB &&
              _settleTermsText(a[i].terms).replaceFirst(ratioA, '') ==
                  mineText.replaceFirst(ratioB, '');
          parts.add(
            '$label ${onlyRatio && ratioB.isNotEmpty ? ratioB : mineText}',
          );
        }
      }
      return parts.join('、');
    }

    final groups = <String, int>{};
    var same = 0;
    for (final row in rows) {
      if (_skuSettleSignature(row) == commonSig) {
        same++;
        continue;
      }
      final text = describe(row);
      groups[text] = (groups[text] ?? 0) + 1;
    }
    if (groups.isEmpty) return '';
    return '${[for (final entry in groups.entries) '${entry.value} 个：${entry.key}'].join(' · ')}；其余 $same 个同上';
  }

  /// 「业务平台状态 待配置 30」或「业务平台状态 已创建 28 · 待配置 2」。
  String _skuPlatformSummary(List<ProposalSkuDetailRow> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      final label = proposalSkuPlatformStatusLabel(row.platformStatus);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    return '业务平台状态 ${[for (final entry in counts.entries) '${entry.key} ${entry.value}'].join(' · ')}';
  }

  /// 原型「产品 30 个」清单：默认一行一个产品（序号 · 名称 · 结算条数和收入一比例 · 业务平台状态），
  /// 比例和多数不同的标紫；点某个产品才展开它的全部字段和每条结算。
  Widget _simpleSkuList(
    List<ProposalSkuDetailRow> rows, {
    required String scope,
  }) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final commonSig = _commonSkuSettleSignature(rows);
    String keyOf(int index, ProposalSkuDetailRow sku) =>
        'sku:$scope:${sku.id.isEmpty ? index : sku.id}';
    final keys = [for (var i = 0; i < rows.length; i++) keyOf(i, rows[i])];
    final allOpen = keys.isNotEmpty && keys.every(_simpleOpen.contains);
    TextStyle mono(double size, int color, {FontWeight? weight}) => TextStyle(
      fontFamily: kProposalProtoMono,
      fontFamilyFallback: kProposalProtoMonoFallback,
      fontSize: size,
      fontWeight: weight,
      color: c(color),
    );

    Widget settleTable(ProposalSkuDetailRow sku, bool differs) {
      final items = proposalIntakeSkuSettlements(sku);
      if (items.isEmpty) return const SizedBox.shrink();
      final income = [
        for (final item in items)
          if (!item.isCost) item,
      ];
      final cost = [
        for (final item in items)
          if (item.isCost) item,
      ];
      final labels = _settleRowLabels([...income, ...cost]);
      final ordered = [
        for (var i = 0; i < income.length + cost.length; i++)
          (
            labels[i],
            (i < income.length ? income[i] : cost[i - income.length]).terms,
            i < income.length,
          ),
      ];
      TableRow tr(
        List<String> cells, {
        bool head = false,
        bool hiRatio = false,
      }) => TableRow(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: c(0xFFF3F0F8, DunesColorRole.border)),
          ),
        ),
        children: [
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                cells[i].isEmpty ? '—' : cells[i],
                style: i == 3 && !head
                    ? mono(
                        11,
                        hiRatio ? 0xFF3F2A9A : 0xFF2A2638,
                        weight: hiRatio ? FontWeight.w700 : null,
                      )
                    : TextStyle(
                        fontSize: head ? 11 : 12,
                        color: c(head ? 0xFF8A8499 : 0xFF2A2638),
                      ),
              ),
            ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              tr(const [
                '结算',
                '账单类型',
                '模式',
                '比例/单价',
                '公式',
                '发票',
                '税率',
                '起止',
                '规模',
                '我方 → 对方',
              ], head: true),
              for (final (label, t, isIncome) in ordered)
                tr([
                  label,
                  t.billType,
                  t.settleMode,
                  t.displayRatio.isNotEmpty
                      ? t.displayRatio
                      : (t.displayUnitPrice.isEmpty
                            ? ''
                            : '单价 ${t.displayUnitPrice}'),
                  t.displayFormula,
                  t.invoiceType,
                  t.taxRate.isEmpty || t.taxRate.endsWith('%')
                      ? t.taxRate
                      : '${t.taxRate}%',
                  t.effectiveTime.isEmpty && t.expireTime.isEmpty
                      ? ''
                      : '${t.effectiveTime}–${t.expireTime}',
                  t.scale.isEmpty
                      ? ''
                      : '${t.scale} 万${t.scalePeriod == '月' ? '/月' : ''}',
                  [
                    t.ourParty,
                    t.counterparty,
                  ].where((item) => item.trim().isNotEmpty).join(' → '),
                ], hiRatio: differs && isIncome),
            ],
          ),
        ),
      );
    }

    Widget item(int index, ProposalSkuDetailRow sku) {
      final key = keyOf(index, sku);
      final open = _simpleOpen.contains(key);
      final status = normalizeProposalSkuPlatformStatus(sku.platformStatus);
      final (int bg, int fg) = switch (status) {
        kProposalSkuPlatformStatusCreated => (0xFFE6F3EB, 0xFF2D6E47),
        kProposalSkuPlatformStatusCreating => (0xFFEDE8FB, 0xFF3F2A9A),
        kProposalSkuPlatformStatusFailed => (0xFFFBE9E7, 0xFFB42318),
        _ => (0xFFFDF2E6, 0xFF9A4A0C),
      };
      final differs = _skuSettleSignature(sku) != commonSig;
      final settleCount = proposalIntakeSkuSettlements(sku).length;
      // 关联产品（权益包下的子产品）：收起时只写个数，展开后逐个列出名称和结算。
      final related = proposalIntakeChildProducts(_form)
          .where((child) => child.parentSkuId == sku.id)
          .toList(growable: false);
      final scale = proposalIntakeSkuScaleTotal(sku);
      final fields = <(String, Widget)>[
        ('产品名称', _kvText(sku.displayName)),
        for (final (label, value) in _skuFieldKv(sku)) (label, _kvText(value)),
        if (scale > 0) ('规模', _kvText('${proposalFormatWan(scale)} 万（年）')),
        ('业务平台状态', _kvText(proposalSkuPlatformStatusChipLabel(sku))),
      ];
      return Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: c(0xFFF1EEF8, DunesColorRole.border)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('proposal-simple-sku-$key'),
              onTap: () => setState(() {
                if (!_simpleOpen.remove(key)) _simpleOpen.add(key);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${index + 1}', style: mono(10, 0xFF8A8499)),
                    ),
                    Expanded(
                      child: Text(
                        sku.displayName.isEmpty ? '未填写产品名称' : sku.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c(0xFF2A2638)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$settleCount 条 · ${_skuFirstIncomeRatio(sku)}${related.isEmpty ? '' : ' · 关联 ${related.length}'}',
                      style: mono(10, differs ? 0xFF3F2A9A : 0xFF8A8499),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: c(bg, DunesColorRole.surface),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        proposalSkuPlatformStatusLabel(sku.platformStatus),
                        style: TextStyle(fontSize: 10, color: c(fg)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: open ? .25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        '▸',
                        style: TextStyle(fontSize: 10, color: c(0xFF8A8499)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.only(left: 22, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _simpleKvTable(
                      fields,
                      background: c(0xFFFFFFFF, DunesColorRole.surface),
                    ),
                    settleTable(sku, differs),
                    for (var r = 0; r < related.length; r++)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: c(0xFFCFC2F5, DunesColorRole.border),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              [
                                '关联产品 ${r + 1}',
                                if (related[r].displayName.trim().isNotEmpty)
                                  related[r].displayName.trim(),
                                if (related[r].faceValue.trim().isNotEmpty)
                                  '面值 ${related[r].faceValue.trim()}',
                                '数量 ${proposalIntakeChildProductQuantity(_form, related[r].id)}',
                                '${proposalIntakeSkuSettlements(related[r]).length} 条结算',
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: c(0xFF2A2638),
                              ),
                            ),
                            settleTable(related[r], false),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            _simpleRelatedProductLines(sku),
          ],
        ),
      );
    }

    return Container(
      key: ValueKey('proposal-simple-sku-list-$scope'),
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: c(0xFFFBFAFF, DunesColorRole.surface),
        border: Border.all(color: c(0xFFE7E3F2, DunesColorRole.border)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '产品 ${rows.length} 个',
                          style: TextStyle(
                            color: c(0xFF2A2638),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 11, color: c(0xFF5B556A)),
                  ),
                ),
                _simplePillButton(
                  allOpen ? '全部收起 ▴' : '全部展开 ▾',
                  () => setState(() {
                    if (allOpen) {
                      _simpleOpen.removeAll(keys);
                    } else {
                      _simpleOpen.addAll(keys);
                    }
                  }),
                ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) item(i, rows[i]),
        ],
      ),
    );
  }

  /// SKU 字段拆成「名称、值」，给展开后的小字段表用。
  List<(String, String)> _skuFieldKv(ProposalSkuDetailRow sku) {
    final asset = (sku.assetProduct?.label ?? '').trim();
    return [
      for (final (key, text) in _skuFieldTexts(sku))
        if (text.isNotEmpty)
          switch (key) {
            'sync' => ('中油好客', text.replaceAll('中油好客', '').trim()),
            'existing' => ('已有产品', asset.isEmpty ? '是' : asset),
            _ =>
              text.contains(' ')
                  ? (
                      text.substring(0, text.indexOf(' ')),
                      text.substring(text.indexOf(' ') + 1),
                    )
                  : (text, ''),
          },
    ];
  }

  /// 原型「填报内容 · 财务部」（无子产品时）：产品结算、收入/成本各条、结算不同的产品、
  /// 项目成本、其他成本、周转、供给侧、渠道侧、结算账户、备注，一行一条。
  Widget _financeSimpleRows(bool wide) {
    final rows = proposalIntakeSkuDetails(_form);
    final commonSig = _commonSkuSettleSignature(rows);
    final commonSku = rows
        .where((row) => _skuSettleSignature(row) == commonSig)
        .firstOrNull;
    final common = commonSku == null
        ? const <ProposalSkuSettleRow>[]
        : proposalIntakeSkuSettlements(commonSku);
    final income = [
      for (final item in common)
        if (!item.isCost) item,
    ];
    final cost = [
      for (final item in common)
        if (item.isCost) item,
    ];
    // 应收在前、应付在后；每行叫「应收 · 渠道结算」这类名字。
    final commonOrdered = [...income, ...cost];
    final commonLabels = _settleRowLabels(commonOrdered);
    final diff = commonSku == null ? '' : _settleDiffText(rows, commonSku);
    final shared = kProposalSharedSettleEnabled
        ? proposalIntakeSharedSettlements(_form)
        : const <ProposalSharedSettleRow>[];
    final settleReview = proposalIntakeSkuSettleReviewKeys(_form).isEmpty
        ? null
        : _rowReviewToggle(
            'financeItem:$kProposalSkuSettlementsReviewKey',
            '待复核',
          );

    final scope = proposalIntakeProductFinanceScope(
      _form,
      owner: kProposalProductFinanceMain,
    );
    final catalog = widget.options.costItemOptions;
    // 成本一行：「合计 9.65 万元 · 印花税 0.24 万元 · 增值税及附加 9.41 万元」，不再列公式。
    String costText(
      String totalKey,
      String namesKey,
      String amountsKey, {
      List<ProposalCostItemOption> options = const [],
      bool project = false,
    }) {
      final items = _form[namesKey] is List
          ? [
              for (final item in _form[namesKey] as List)
                if ('$item'.trim().isNotEmpty) '$item'.trim(),
            ]
          : const <String>[];
      final map = proposalCostAmountMap(_form[amountsKey]);
      double amountOf(String name) =>
          map[proposalCostAmountId(name, options)] ?? map[name] ?? 0;
      final rawTotal = double.tryParse(_text(totalKey).trim());
      if (items.isEmpty && rawTotal == null) return '';
      final total =
          rawTotal ??
          items.fold<double>(0, (sum, name) => sum + amountOf(name));
      return [
        '合计 ${_money(total)}',
        for (final name in items)
          '${project ? proposalProjectCostDisplayName(name) : name} ${_money(amountOf(name))}',
      ].join(' · ');
    }

    final accounts = [
      if (_text('generalBusinessAccount').trim().isNotEmpty)
        '一：${proposalMaskAccount(_text('generalBusinessAccount').trim())}',
      if (_text('prepaidAccount').trim().isNotEmpty)
        '二：${proposalMaskAccount(_text('prepaidAccount').trim())}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldGrid(wide, [
          _simpleLine(
            '产品结算',
            rows.isEmpty
                ? ''
                : [
                    '${rows.length} 个产品',
                    if (proposalIntakeHasChildProducts(_form))
                      '关联产品 ${proposalIntakeChildProducts(_form).length} 个',
                    if (shared.isEmpty)
                      '每个一套结算'
                    else
                      '含共用结算 ${shared.length} 组',
                    _skuPlatformSummary(rows),
                  ].where((item) => item.isNotEmpty).join(' · '),
            anchorKey: 'productSalesSettle',
            required: true,
            fullWidth: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rows.isNotEmpty)
                  _simpleSkuListButton('finance', rows.length),
                if (settleReview != null) ...[
                  const SizedBox(width: 8),
                  settleReview,
                ],
              ],
            ),
          ),
        ]),
        if (rows.isNotEmpty && !_simpleSkuListHidden('finance'))
          _simpleSkuList(rows, scope: 'finance'),
        _fieldGrid(wide, [
          for (var i = 0; i < commonOrdered.length; i++)
            _simpleLine(
              commonLabels[i],
              _settleTermsText(commonOrdered[i].terms, withBillType: false),
              required: i == 0,
              fullWidth: true,
            ),
          if (diff.isNotEmpty) _simpleLine('结算不同的产品', diff, fullWidth: true),
          for (var i = 0; i < shared.length; i++)
            _simpleLine(
              proposalIntakeSettleLabel(i, kind: '共用结算'),
              '${shared[i].skuIds.length} 个产品 · ${_settleTermsText(shared[i].terms)}',
              fullWidth: true,
            ),
          // 测算各项一行一条（收入、电子券采购成本、利润、毛利率、周转资金、月周转次数），
          // 各自复核；规模在顶部测算里，不再重复。
          for (final field in _financeMetricFields)
            if (field.$1 != 'salesScale')
              _anchor(
                field.$1,
                _scopedFinanceField(
                  field,
                  owner: kProposalProductFinanceMain,
                  scope: scope,
                ),
              ),
          _simpleLine(
            '项目成本',
            costText(
              'projectCost',
              'costItems',
              'costItemAmounts',
              options: catalog,
              project: true,
            ),
            anchorKey: 'costItems',
            required: true,
            trailing: _rowReviewToggle('financeItem:costItems', '待复核'),
          ),
          _simpleLine(
            '业务成本',
            _businessCostSealed
                ? '仅市场部负责人一可见'
                : costText(
                    'businessCost',
                    'businessCostItems',
                    'businessCostItemAmounts',
                  ),
            anchorKey: 'businessCost',
          ),
          _simpleLine(
            '经营成本',
            costText(
              'operatingCost',
              'operatingCostItems',
              'operatingCostItemAmounts',
            ),
            anchorKey: 'operatingCost',
            trailing: _rowReviewToggle('financeItem:operatingCost', '待复核'),
          ),
          _simpleLine(
            '税务成本',
            costText('taxCost', 'taxCostItems', 'taxCostItemAmounts'),
            anchorKey: 'taxCost',
            trailing: _rowReviewToggle('financeItem:taxCost', '待复核'),
          ),
          _financeSideSimpleLine('供给侧', _financeSupplyFields),
          _financeSideSimpleLine('渠道侧', _financeChannelFields),
          _simpleLine(
            '结算账户',
            accounts,
            anchorKey: 'generalBusinessAccount',
            required: true,
            fullWidth: true,
            trailing: _mergedReviewToggle(const [
              'financeItem:generalBusinessAccount',
              'financeItem:prepaidAccount',
            ]),
          ),
          _simpleLine(
            '财务备注',
            _text('financeRemark'),
            anchorKey: 'financeRemark',
            fullWidth: true,
            trailing: _rowReviewToggle('financeItem:financeRemark', '待复核'),
          ),
        ]),
      ],
    );
  }

  /// 原型「填报内容 · 科技部」的产品部分：SKU 共同项一行，SKU 清单一行（可展开）。
  Widget _techSkuSimple(bool wide) {
    final rows = proposalIntakeSkuDetails(_form);
    // 所有产品都一样的字段收进「SKU 共同项」，其余写在清单每个产品下面。
    final common = _skuCommonFields(rows).values.join(' · ');
    final faces = [
      for (final row in rows)
        if (double.tryParse(row.faceValue.trim()) case final v? when v > 0) v,
    ]..sort();
    final faceText = faces.isEmpty
        ? ''
        : (faces.first == faces.last
              ? '面值 ${proposalFormatWan(faces.first)} 元'
              : '面值 ${proposalFormatWan(faces.first)}–${proposalFormatWan(faces.last)} 元');
    final review = _rowReviewToggle(
      'technologyItem:$kProposalSkuProductsReviewKey',
      _techReviewLabel,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldGrid(wide, [
          if (common.isNotEmpty)
            _simpleLine(
              'SKU 共同项',
              common,
              anchorKey: 'skuCommon',
              fullWidth: true,
            ),
          _simpleLine(
            'SKU 清单',
            rows.isEmpty
                ? ''
                : [
                    '${rows.length} 个',
                    faceText,
                    if (!_isPurchase) '结算和业务平台状态在财务部「产品结算」',
                  ].where((item) => item.isNotEmpty).join(' · '),
            anchorKey: 'skuDetails',
            required: true,
            fullWidth: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rows.isNotEmpty) _simpleSkuListButton('tech', rows.length),
                if (review != null) ...[const SizedBox(width: 8), review],
              ],
            ),
          ),
        ]),
        if (rows.isNotEmpty && !_simpleSkuListHidden('tech'))
          _simpleSkuList(rows, scope: 'tech'),
      ],
    );
  }

  /// 研发三项合成一行：「标准接口对接 · 无研发费用」。
  Widget _rdSimpleLine() {
    final types = _setOf('developmentTypes').join('、');
    final has = _text('hasRdCost').trim();
    final amount = _text('rdAmount').trim();
    final cost = switch (has) {
      '是' => amount.isEmpty ? '有研发费用' : '研发费用 $amount 万元',
      '否' => '无研发费用',
      _ => '',
    };
    return _simpleLine(
      '研发',
      [types, cost].where((item) => item.isNotEmpty).join(' · '),
      anchorKey: 'developmentTypes',
      required: true,
      trailing: _mergedReviewToggle(const [
        'technologyItem:developmentTypes',
        'technologyItem:hasRdCost',
        'technologyItem:rdAmount',
      ], pendingLabel: _techReviewLabel),
    );
  }

  /// 盈利模式与计算说明合成一行：「利差：收入比例 0.9905 − 采购比例 0.9685 = 2.2%」。
  Widget _profitSimpleLine() {
    final modes = _setOf('profitModes').join('、');
    final formula = _text('profitFormula').trim();
    final value = modes.isEmpty
        ? formula
        : (formula.isEmpty ? modes : '$modes：$formula');
    return _simpleLine(
      '盈利模式',
      value,
      anchorKey: 'profitModes',
      required: true,
      fullWidth: true,
    );
  }

  /// 原型的板块标签：选中浅紫底，未选白底细框；后面跟 ✓ / 进度 / 只读 / 待办。
  Widget _protoPill({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    List<Widget> trailing = const [],
  }) {
    return Material(
      color: DunesColors.resolve(
        context,
        selected ? const Color(0xFFEDE8FB) : Colors.white,
        role: DunesColorRole.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: selected
            ? BorderSide.none
            : BorderSide(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFE7E3F2),
                  role: DunesColorRole.border,
                ),
              ),
      ),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _phoneWidth ? 28 : 32),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _phoneWidth ? 8 : 12,
              vertical: _phoneWidth ? 4 : 5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: DunesColors.resolve(
                      context,
                      selected
                          ? const Color(0xFF3F2A9A)
                          : const Color(0xFF2A2638),
                    ),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                ...trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _protoSectionPill(
    ProposalIntakeNavSection section, {
    required bool selected,
  }) {
    final done = proposalIntakeNavSectionComplete(row: _row, section: section);
    final todoBadge = proposalIntakeNavTodoBadge(_taskAction);
    final todo = _taskSection == section && !done && todoBadge.isNotEmpty;
    TextStyle mono(int color) => TextStyle(
      color: DunesColors.resolve(context, Color(color)),
      fontSize: 11,
      fontWeight: FontWeight.w500,
      fontFamily: kProposalProtoMono,
      fontFamilyFallback: kProposalProtoMonoFallback,
    );
    final techProgress =
        section == ProposalIntakeNavSection.tech && _isReviewing && !done
        ? '${_technologyReviewedCount()}/${_technologyReviewFields.length}'
        : '';
    return _protoPill(
      key: ValueKey('proposal-nav-${section.name}'),
      label: proposalIntakeNavSectionLabel(section),
      selected: selected,
      onTap: () => _jumpToSection(section),
      trailing: [
        if (_rejectedSection == section) ...[
          const SizedBox(width: 4),
          Text('已驳回', style: mono(0xFFC0563F)),
        ] else if (_row.techRevisionOpen &&
            section == ProposalIntakeNavSection.tech) ...[
          const SizedBox(width: 4),
          Text('变更中', style: mono(0xFFB4570F)),
        ] else if (done) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.check_rounded,
            key: ValueKey('proposal-nav-done-${section.name}'),
            size: 13,
            color: DunesColors.resolve(context, const Color(0xFF3B8B5A)),
          ),
        ] else if (section == ProposalIntakeNavSection.flow) ...[
          const SizedBox(width: 4),
          Text('只读', style: mono(0xFF8A8499)),
        ] else if (techProgress.isNotEmpty) ...[
          const SizedBox(width: 4),
          // 没核完的进度（如 7/9）用紫色，和「待核」一致。
          Text(techProgress, style: mono(0xFF6B4FD8)),
        ],
        if (todo) ...[
          const SizedBox(width: 4),
          Container(
            key: ValueKey('proposal-nav-todo-${section.name}'),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                const Color(0xFFB4570F),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              todoBadge,
              style: TextStyle(
                color: DunesColors.resolve(context, Colors.white),
                fontSize: 9,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String get _rating {
    final scale = proposalIntakeMainProductScale(_form);
    if (scale == null) return '—';
    return widget.options.ratingFor(scale);
  }

  /// 标题旁只放 S/A/B/C，没有年化规模时不占位。
  String? get _headerRating {
    final rating = _rating;
    if (rating == '—' || rating.isEmpty) return null;
    return rating;
  }

  /// 原型标题旁的状态标签；填写中、草稿不显示（与原有设计一致）。
  Widget? get _headerStatusPill {
    final label = switch (_row.status) {
      'reviewing' => '复核中',
      'pending_president' => '待最终确认',
      'done' => '已完成',
      _ => '',
    };
    if (label.isEmpty) return null;
    return ProposalStatusPill(status: _row.status, label: label);
  }

  Widget _ratingChip(String rating) {
    if (kProposalPrototypeStyleEnabled) {
      return Tooltip(
        message: '任务评级 $rating，按年化规模自动',
        child: KeyedSubtree(
          key: const ValueKey('proposal-top-rating'),
          child: ProposalRatingBadge(rating: rating),
        ),
      );
    }
    final (Color bg, Color fg) = switch (rating) {
      'S' => (
        DunesColors.resolve(context, ProposalPalette.purpleSoft),
        DunesColors.resolve(context, ProposalPalette.purpleDeep),
      ),
      'A' => (
        DunesColors.resolve(context, ProposalPalette.greenSoft),
        DunesColors.resolve(context, ProposalPalette.green),
      ),
      'B' => (
        DunesColors.resolve(context, ProposalPalette.amberSoft),
        DunesColors.resolve(context, ProposalPalette.amber),
      ),
      _ => (
        DunesColors.resolve(context, const Color(0xFFF0ECF4)),
        DunesColors.resolve(context, ProposalPalette.text2),
      ),
    };
    return Tooltip(
      message: '任务评级 $rating，按年化规模自动',
      child: Container(
        key: const ValueKey('proposal-top-rating'),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DunesColors.resolveNullable(
            context,
            bg,
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$rating级',
          style: TextStyle(
            color: DunesColors.resolveNullable(context, fg),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
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
          decoration: proposalInputDecoration(context: context),
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
          decoration: proposalInputDecoration(context: context),
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

  bool _jumpToSection(ProposalIntakeNavSection section) {
    if (_protoForm && (!_contentOpen || _commentsTab)) {
      setState(() {
        _contentOpenOverride = true;
        _commentsTab = false;
      });
    }
    if (_isPurchase && !_protoForm) {
      return _jumpToKey(_keyForNavSection(section), section);
    }
    final target = section == ProposalIntakeNavSection.toc
        ? ProposalIntakeNavSection.market
        : section;
    if (_visibleSection != target) {
      setState(() => _visibleSection = target);
    }
    if (_protoForm) {
      // 原型标签页：切换板块不回到页面顶部，只保证「填报内容」框头在视野里。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keepContentBoxInView();
      });
      return true;
    }
    if (_scroll.hasClients && _scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
    return true;
  }

  /// 「填报内容」框（标签所在的框）。
  final GlobalKey _contentBoxKey = GlobalKey();

  /// 框头已经在视野里（或在下方）就不动；滚过头了才回到框头，而不是页面最上面。
  void _keepContentBoxInView() {
    final ctx = _contentBoxKey.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final box = ctx.findRenderObject();
    final viewport = _scroll.position.context.notificationContext
        ?.findRenderObject();
    if (box is! RenderBox ||
        viewport is! RenderBox ||
        !box.attached ||
        !viewport.attached ||
        !box.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final top =
        box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
    if (top >= 0) return;
    final destination = (_scroll.offset + top - 8).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(destination);
  }

  bool _jumpToTask() {
    // 复核中的简单行只读；轮到你填写时先切回完整表单再定位。
    if (_reviewSimpleRows && proposalIntakeActionIsWrite(_taskAction)) {
      setState(() => _reviewFormMode = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToTask();
      });
      return true;
    }
    if (_taskAction == 'president_confirm') {
      if (!_scroll.hasClients) return false;
      _jumping = true;
      unawaited(
        _scroll
            .animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              if (!mounted) return;
              _jumping = false;
            }),
      );
      return true;
    }
    final section = _taskSection;
    if (section == null) return false;
    final key = switch (_taskAction) {
      'review_market' => _marketModuleReviewKey,
      'review_finance_module' => _financeModuleReviewKey,
      'review_tech' when _awaitingTechModuleConfirm => _techModuleReviewKey,
      _ => _keyForNavSection(section),
    };
    if (key.currentContext == null) return _jumpToSection(section);
    return _jumpToKey(key, section);
  }

  bool _jumpToKey(GlobalKey key, ProposalIntakeNavSection section) {
    if (_isPurchase && !_protoForm) {
      final targetContext = key.currentContext;
      if (targetContext == null || !_scroll.hasClients) return false;
      final target = targetContext.findRenderObject();
      final viewport = _scroll.position.context.notificationContext
          ?.findRenderObject();
      if (target is! RenderBox ||
          viewport is! RenderBox ||
          !target.hasSize ||
          !viewport.hasSize) {
        return false;
      }
      final destination =
          (_scroll.offset +
                  target.localToGlobal(Offset.zero).dy -
                  viewport.localToGlobal(Offset.zero).dy)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      _jumping = true;
      setState(() => _visibleSection = section);
      unawaited(
        _scroll
            .animateTo(
              destination,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              if (!mounted) return;
              _jumping = false;
              if (_visibleSection != section) {
                setState(() => _visibleSection = section);
              }
            }),
      );
      return true;
    }
    if (_visibleSection != section) {
      setState(() => _visibleSection = section);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToKey(key, section);
      });
      return true;
    }
    final targetContext = key.currentContext;
    if (targetContext == null || !_scroll.hasClients) return false;
    final target = targetContext.findRenderObject();
    if (target == null || !target.attached) return false;
    _jumping = true;
    setState(() => _visibleSection = section);
    unawaited(
      _scroll.position
          .ensureVisible(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            alignment: .04,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          )
          .whenComplete(() {
            if (!mounted) return;
            _jumping = false;
            if (_visibleSection != section) {
              setState(() => _visibleSection = section);
            }
          }),
    );
    return true;
  }

  Widget _anchor(String key, Widget child) {
    // LayoutBuilder / 栅格会在一次 build 里把同一字段挂两次。
    // putIfAbsent 复用同一把 GlobalKey 时，Column 会直接红屏。
    final n = _anchorUseCount.update(
      key,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    final slot = n == 0 ? key : '$key#$n';
    final gk = _fieldAnchorKeys.putIfAbsent(slot, GlobalKey.new);
    return KeyedSubtree(
      key: gk,
      child: _FlowFieldFlash(
        flashKey: key,
        active: _flashFieldKeys.contains(key),
        child: child,
      ),
    );
  }

  void _jumpToFlowSource(String id) {
    final jump = kFlowFieldJumps[id];
    if (jump == null) return;
    setState(() {
      _flashFieldKeys
        ..clear()
        ..addAll(jump.fieldKeys);
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _flashFieldKeys.clear());
    });
    for (final key in jump.fieldKeys) {
      final gk = _fieldAnchorKeys[key];
      if (gk?.currentContext != null) {
        _jumpToKey(gk!, jump.section);
        return;
      }
    }
    _jumpToSection(jump.section);
  }

  String get _taskAction {
    final fromRow = _row.myAction.trim();
    if (fromRow.isNotEmpty) return fromRow;
    if (!_isReviewing) return '';
    if (_moduleReviewEnabled('marketCompleted') &&
        !_moduleReviewed('marketCompleted')) {
      return 'review_market';
    }
    if (_moduleReviewEnabled('technologyCompleted') &&
        !_moduleReviewed('technologyCompleted')) {
      return 'review_tech';
    }
    if (_isOwner('financeOwner2') &&
        (_review['purchaseContractCompleted'] != true ||
            (!_isPurchase && _review['salesContractCompleted'] != true))) {
      return 'review_contract';
    }
    if (_isOwner('financeOwner2') && !_allFinanceItemsReviewed) {
      return 'review_finance';
    }
    if (_moduleReviewEnabled('financeCompleted') &&
        !_moduleReviewed('financeCompleted')) {
      return 'review_finance_module';
    }
    return '';
  }

  bool get _awaitingTechModuleConfirm {
    if (_moduleReviewed('technologyCompleted')) return false;
    if (_taskAction != 'review_tech' &&
        !_moduleReviewEnabled('technologyCompleted')) {
      return false;
    }
    return proposalIntakeTechnologyReviewGaps(_review, form: _form).isEmpty;
  }

  ProposalIntakeNavSection? get _taskSection {
    // 原型标签页：合同放在市场部标签里，复核合同要落到市场部。
    if (_protoForm && _taskAction == 'review_contract') {
      return ProposalIntakeNavSection.market;
    }
    return proposalIntakeNavSectionForAction(_taskAction);
  }

  GlobalKey _keyForNavSection(ProposalIntakeNavSection section) {
    return switch (section) {
      ProposalIntakeNavSection.toc => _tocKey,
      ProposalIntakeNavSection.market => _marketKey,
      ProposalIntakeNavSection.tech => _techKey,
      ProposalIntakeNavSection.finance => _financeKey,
      ProposalIntakeNavSection.flow => _flowKey,
    };
  }

  void _syncVisibleSection() {
    if (!mounted || !_scroll.hasClients || _jumping) return;
    final next = _sectionAtViewport();
    if (next == null || next == _visibleSection) return;
    setState(() => _visibleSection = next);
  }

  ProposalIntakeNavSection? _sectionAtViewport() {
    if (!_isPurchase || _protoForm) return _visibleSection;
    final viewport = _scroll.position.context.notificationContext
        ?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    var visible = ProposalIntakeNavSection.toc;
    void consider(ProposalIntakeNavSection section, GlobalKey key) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if (box.localToGlobal(Offset.zero).dy <= top + 80) {
        visible = section;
      }
    }

    consider(ProposalIntakeNavSection.toc, _tocKey);
    consider(ProposalIntakeNavSection.market, _marketKey);
    consider(ProposalIntakeNavSection.tech, _techKey);
    consider(ProposalIntakeNavSection.finance, _financeKey);
    return visible;
  }

  List<String> _validate() {
    final issues = <String>[];
    if (_row.title.trim().isEmpty) issues.add('产品提案名称不能为空');
    if (!_isPurchase) {
      if (proposalIntakeFormHasText(_form, 'salesScale') &&
          _number('salesScale') < widget.options.minimumScale) {
        issues.add('销售规模低于 ${_money(widget.options.minimumScale)}');
      }
      if (proposalIntakeFormHasText(_form, 'margin') &&
          _number('margin') < widget.options.minimumMargin) {
        issues.add('毛利率低于 ${widget.options.minimumMargin}%');
      }
    }
    final missing = _missingRequiredFinanceInterfaces();
    if (missing.isNotEmpty) issues.add('财务技术接口缺少：${missing.join('、')}');
    if (_text('hasRdCost') == '是' && _number('rdAmount') <= 0) {
      issues.add('已选择涉及研发费用，金额必须大于 0');
    }
    if (widget.options.presidentUserIds.isEmpty && _ownerId('president') <= 0) {
      issues.add('请在管理后台「提案录入选项」中配置最终确认人');
    }
    for (final name in missingProposalReviewAssignees(
      _form,
      purchase: _isPurchase,
    )) {
      issues.add('请指定$name');
    }
    if (_isPurchase) {
      issues.addAll(proposalIntakePurchaseMarketIssues(_form));
      issues.addAll(proposalIntakePurchaseTechIssues(_form));
      if (_canSeeHun) {
        final hun = proposalIntakePurchaseHunIssue(_form);
        if (hun != null) issues.add(hun);
      }
    } else {
      issues.addAll(proposalIntakeSalesMarketIssues(_form));
      issues.addAll(proposalIntakeTechFillIssues(_form, purchase: false));
      issues.addAll(proposalIntakeChildTechFillIssues(_form));
      issues.addAll(proposalIntakeSalesFinanceFillIssues(_form));
      issues.addAll(proposalIntakeSkuSettleIssues(_form));
    }
    final reviewFlags = <String, String>{
      'marketCompleted': '市场部',
      'technologyCompleted': '科技部',
      'financeInterfaceCompleted': '财务技术接口',
      if (!_isPurchase) 'financeCompleted': '财务部',
      'purchaseContractCompleted': '采购合同',
      if (!_isPurchase) 'salesContractCompleted': '销售合同',
    };
    for (final entry in reviewFlags.entries) {
      if (_review[entry.key] != true) issues.add('${entry.value}尚未完成复核');
    }
    return issues;
  }

  List<String> _missingRequiredFinanceInterfaces() {
    final missing = <String>[];
    void collect(Map<String, dynamic> values, String prefix) {
      for (final item in widget.options.financeInterfaces) {
        if (item.required && values[item.key] != true) {
          missing.add('$prefix${item.label}');
        }
      }
    }

    final interfaceValues = _form['financeInterfaces'] is Map
        ? Map<String, dynamic>.from(_form['financeInterfaces'])
        : <String, dynamic>{};
    collect(interfaceValues, '');
    if (kProposalChildTechEnabled && proposalIntakeHasChildProducts(_form)) {
      final child = proposalIntakeChildTechnology(_form)['financeInterfaces'];
      collect(
        child is Map ? Map<String, dynamic>.from(child) : <String, dynamic>{},
        kProposalChildProductLabel,
      );
    }
    return missing;
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
    final recipients = proposalIntakeNotifyRecipients(
      action: 'submit_president',
      row: _row,
      people: widget.people,
      options: widget.options,
    );
    final confirmed = await _confirmFinal(
      title: '确认通知最终人',
      message: '确认后提案将交给最终人，内容锁定，不可再改。这是通知最终人的最终确认。',
      confirmLabel: '确认通知',
      recipients: recipients,
    );
    if (!confirmed) return;
    try {
      final submitted = await widget.service.submit(_row.id);
      if (!mounted) return;
      setState(() => _row = submitted.row);
      widget.onSubmit(submitted.row);
      _toastNotified(submitted.notified, fallback: '已通知最终人');
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _handoff(String action) async {
    if (_dirty) {
      widget.onError('请先保存最新修改，再通知下一位');
      return;
    }
    if (action != 'remind') {
      final missing = missingProposalReviewAssignees(
        _form,
        includeTech: action == 'notify_tech',
        purchase: _isPurchase,
      );
      if (missing.isNotEmpty) {
        final issues = [for (final name in missing) '请指定$name'];
        setState(() => _issues = issues);
        _scrollToTop();
        widget.onError('请先指定：${missing.join('、')}');
        return;
      }
    }
    if (action != 'remind' && _isPurchase && action == 'notify_tech') {
      final issues = proposalIntakePurchaseMarketIssues(_form);
      if (issues.isNotEmpty) {
        setState(() => _issues = issues);
        _scrollToTop();
        widget.onError(issues.first);
        return;
      }
    }
    if (!_isPurchase && action == 'notify_tech') {
      final issues = [
        ...proposalIntakeSalesMarketIssues(_form),
        ...proposalIntakeSkuSettleIssues(_form, includeSettlements: false),
      ];
      if (issues.isNotEmpty) {
        setState(() => _issues = issues);
        _scrollToTop();
        widget.onError(issues.first);
        return;
      }
    }
    if (action == 'notify_market2') {
      final missingInterfaces = _missingRequiredFinanceInterfaces();
      if (missingInterfaces.isNotEmpty) {
        final issues = ['财务技术接口缺少：${missingInterfaces.join('、')}'];
        setState(() => _issues = issues);
        _scrollToTop();
        widget.onError(issues.first);
        return;
      }
      if (_isPurchase) {
        final issues = proposalIntakePurchaseTechIssues(_form);
        if (issues.isNotEmpty) {
          setState(() => _issues = issues);
          _scrollToTop();
          widget.onError(issues.first);
          return;
        }
      } else {
        final issues = [
          ...proposalIntakeTechFillIssues(_form, purchase: false),
          ...proposalIntakeChildTechFillIssues(_form),
        ];
        if (issues.isNotEmpty) {
          setState(() => _issues = issues);
          _scrollToTop();
          widget.onError(issues.first);
          return;
        }
      }
    }
    final (title, message, confirmLabel) = switch (action) {
      'notify_tech' => (
        '确认通知财务填写',
        '确认后将通知财务部负责人二填写财务技术接口和项目成本。科技部内容由填写人填写，科技部负责人稍后复核。这是本步骤的最终确认。',
        '确认通知',
      ),
      'notify_market2' => (
        '确认提交复核',
        '确认后提案进入复核。请确认财务部负责人二已填完财务技术接口和项目成本。未复核内容提交人仍可修改，已复核部分锁定。这是填写完成的最终确认。',
        '确认提交',
      ),
      'start_review' => (
        '确认重新提交复核',
        '确认后将通知${_rejectSectionRole('${_review['reviewRejectSection'] ?? ''}'.trim())}重新复核本板块，其他已通过板块保持不变。这是本步骤的最终确认。',
        '确认提交',
      ),
      'start_tech_revision' => (
        '确认发起科技变更',
        '确认后可修改科技部内容。市场将按先科技后市场重新打勾。财务技术接口由财务部负责人二填写，并随科技板块由科技部负责人重审。',
        '确认发起',
      ),
      'confirm_tech_revision' => (
        '确认提交本轮科技变更',
        '确认后由科技部负责人复核科技（含财务技术接口），再由市场部负责人一复核市场。底部确认前会检查遗漏。',
        '确认提交',
      ),
      'remind' => ('确认催当前待办人', '不会改变提案阶段，只把当前待办再发一次到审批助手。', '确认催办'),
      _ => ('', '', ''),
    };
    final recipients = proposalIntakeNotifyRecipients(
      action: action,
      row: _row,
      people: widget.people,
      options: widget.options,
    );
    if (action == 'remind' && recipients.isEmpty) {
      widget.onError('当前没有可通知的人');
      return;
    }
    if (title.isNotEmpty) {
      final confirmed = await _confirmFinal(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        recipients: recipients,
      );
      if (!confirmed) return;
    }
    try {
      final next = await widget.service.handoff(_row.id, action, _row.version);
      if (!mounted) return;
      setState(() {
        _row = next.row;
        _markFormDirty(false);
      });
      widget.onSaved(next.row);
      _toastNotified(
        next.notified,
        fallback: action == 'remind' ? '已催办' : '已通知',
      );
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
      final submitter = proposalIntakeSubmitterNotifyRecipient(
        _row,
        task: '最终人已确认通过',
        people: widget.people,
      );
      final confirmed = await _confirmFinal(
        title: '确认通过提案',
        message: '确认后提案完成。这是最终人的最终确认，通过后不可再改。',
        confirmLabel: '确认通过',
        recipients: [if (submitter != null) submitter],
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
        setState(() => _row = next.row);
        widget.onSubmit(next.row);
        widget.onAfterFinalDecision?.call(next.row.id);
        _toastNotified(next.notified, fallback: approved ? '提案已通过' : '已驳回提交人');
      });
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<ProposalIntakeRow> _persistDraft(ProposalIntakeRow row) {
    if (row.id <= 0) {
      return widget.service.create(
        title: row.title,
        kind: row.kind,
        form: row.form,
        review: row.review,
      );
    }
    return widget.service.saveResolvingConflict(row);
  }

  Future<void> _saveDraft() async {
    if (!proposalIntakeHasMeaningfulContent(_row)) {
      widget.onError('请先填写提案信息后再保存草稿');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      final prepared = _row.copyWith(form: _persistableForm(_form));
      final fallback = _row.copyWith(
        form: proposalIntakeJsonSafeForm(
          proposalIntakePreserveUserFinanceEdits(
            original: _form,
            persist: proposalIntakeConfirmContractEdits(_form),
          ),
        ),
      );
      var sent = prepared.form;
      ProposalIntakeRow saved;
      try {
        saved = await _persistDraft(prepared);
      } catch (error) {
        if (proposalIntakeFormsEqual(prepared.form, fallback.form)) {
          rethrow;
        }
        sent = fallback.form;
        saved = await _persistDraft(fallback);
      }
      saved = saved.copyWith(
        form: proposalIntakePreserveUserFinanceEdits(
          original: sent,
          persist: saved.form,
        ),
      );
      if (!mounted) return;
      setState(() {
        _row = saved;
        _serverForm = proposalIntakeCloneForm(saved.form);
        _fieldEpoch++;
        _markFormDirty(false);
      });
      widget.onSaved(saved);
      final awaitingTech = _awaitingTechModuleConfirm;
      showProposalCenterToast(
        context,
        awaitingTech ? '已保存。逐条已完成，请点底部「确认本板块通过」，保存不会结束复核。' : '已保存',
      );
      if (awaitingTech) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToTask();
        });
      }
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
              backgroundColor: DunesColors.resolve(
                ctx,
                ProposalPalette.coral,
                role: DunesColorRole.surface,
              ),
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
          _anchorUseCount.clear();
          final wide = !ProposalLayout.isMedium(constraints.maxWidth);
          final compact = ProposalLayout.isCompact(constraints.maxWidth);
          return _protoFonts(
            ColoredBox(
              color: DunesColors.resolve(
                context,
                ProposalPalette.page,
                role: DunesColorRole.surface,
              ),
              child: Column(
                children: [
                  _topbar(compact: compact),
                  _progressPanel(compact: compact),
                  // 原型：板块标签放进下面的「填报内容」框里。
                  if (!_protoForm) _sectionNav(compact: compact),
                  _taskBanner(compact: compact),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            DunesColors.resolve(
                              context,
                              ProposalPalette.app,
                              role: DunesColorRole.surface,
                            ),
                            DunesColors.resolve(
                              context,
                              ProposalPalette.page,
                              role: DunesColorRole.surface,
                            ),
                          ],
                        ),
                      ),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.depth == 0) _syncVisibleSection();
                          return false;
                        },
                        child: CustomScrollView(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          cacheExtent: 480,
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                wide ? 28 : (_phoneWidth ? 4 : 14),
                                wide ? 22 : (_phoneWidth ? 4 : 14),
                                wide ? 28 : (_phoneWidth ? 4 : 14),
                                _canDecidePresident ||
                                        _awaitingTechModuleConfirm ||
                                        _protoActionBarVisible
                                    ? 120
                                    : 80,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: _protoPageBox(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_protoForm) _protoTitleBlock(wide),
                                      if (_issues.isNotEmpty) _issueBanner(),
                                      if (_review['presidentRejected'] ==
                                              true ||
                                          _review['reviewRejected'] == true)
                                        _rejectBanner(),
                                      if (_stage == 'awaiting_submit')
                                        _awaitingSubmitBanner(),
                                      // 填写中、复核中、待最终确认、已完成都放同一套测算图和「流程」格子。
                                      if (kProposalEstimateSummaryEnabled &&
                                          !_isPurchase)
                                        ValueListenableBuilder<int>(
                                          valueListenable: _estimateTick,
                                          builder: (context, _, _) {
                                            final summary =
                                                _estimateSummaryData;
                                            final card = summary == null
                                                ? null
                                                : ProposalEstimateSummary(
                                                    data: summary,
                                                    onOpenSection:
                                                        _openEstimateSection,
                                                    onOpenField:
                                                        _openEstimateField,
                                                  );
                                            if (!kProposalPrototypeStyleEnabled) {
                                              return card ??
                                                  const SizedBox.shrink();
                                            }
                                            // 原型：测算下面是「流程」格子。
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                ?card,
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 14,
                                                      ),
                                                  child: ProposalFlowCard(
                                                    steps:
                                                        proposalIntakeProgressSteps(
                                                          row: _row,
                                                          people: widget.people,
                                                          options:
                                                              widget.options,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      // 采购提案没有测算，各阶段都放原型「流程」格子。
                                      if (_isPurchase &&
                                          _protoForm &&
                                          kProposalPrototypeStyleEnabled)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
                                          child: ProposalFlowCard(
                                            steps: proposalIntakeProgressSteps(
                                              row: _row,
                                              people: widget.people,
                                              options: widget.options,
                                            ),
                                          ),
                                        ),
                                      if (_isPurchase && !_protoForm) ...[
                                        KeyedSubtree(
                                          key: _tocKey,
                                          child: _proposalToc(wide),
                                        ),
                                        _marketSection(wide),
                                        _techSection(wide),
                                        _financeSection(wide),
                                      ] else
                                        _simpleContentBox(
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _sectionPane(
                                                ProposalIntakeNavSection.market,
                                                _marketSection(wide),
                                              ),
                                              _sectionPane(
                                                ProposalIntakeNavSection.tech,
                                                _techSection(wide),
                                              ),
                                              _sectionPane(
                                                ProposalIntakeNavSection
                                                    .finance,
                                                _financeSection(wide),
                                              ),
                                              // 四流只有销售提案有。
                                              if (!_isPurchase)
                                                _sectionPane(
                                                  ProposalIntakeNavSection.flow,
                                                  _flowSection(wide),
                                                ),
                                            ],
                                          ),
                                        ),
                                      if (widget.enableComments &&
                                          _row.id > 0 &&
                                          !_protoForm)
                                        _commentsSection(),
                                    ],
                                  ),
                                  wide: wide,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_awaitingTechModuleConfirm)
                    ProposalModuleConfirmBar(
                      prototype: _protoForm,
                      onConfirm: () =>
                          unawaited(_setReview('technologyCompleted', true)),
                    ),
                  if (_protoActionBarVisible) _protoActionBar(),
                  if (_canDecidePresident)
                    ProposalPresidentDecisionBar(
                      prototype: _protoForm,
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
            ),
          );
        },
      ),
    );
  }

  Widget _sectionPane(ProposalIntakeNavSection section, Widget child) {
    final visible = _visibleSection == section;
    return Offstage(
      offstage: !visible,
      child: TickerMode(enabled: visible, child: child),
    );
  }

  String get _headerTitle {
    final name = _row.title.trim();
    if (name.isNotEmpty) return name;
    final fromForm = _text('proposalName').trim();
    if (fromForm.isNotEmpty) return fromForm;
    return proposalIntakeUntitledTitle(_row.kind);
  }

  String get _topStatusLine {
    final parts = <String>[
      if (_row.id <= 0 || _row.code.isEmpty) '未保存',
      if (_row.techRevisionOpen) '科技变更中',
    ];
    return parts.join(' · ');
  }

  Widget _topbar({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        widget.onClose != null ? 4 : (compact ? 12 : 16),
        8,
        compact ? 8 : 12,
        8,
      ),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          ProposalPalette.app,
          role: DunesColorRole.surface,
        ),
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              ProposalPalette.borderSoft,
              role: DunesColorRole.border,
            ),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.onClose != null) _closeButton(),
          Expanded(
            child: _protoForm
                // 原型：标题、评级、状态放在页面白框顶部，顶栏只留操作按钮。
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      Flexible(
                        child: Text(
                          _headerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: DunesColors.resolve(
                              context,
                              ProposalPalette.text,
                            ),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (_headerRating != null) ...[
                        const SizedBox(width: 6),
                        _ratingChip(_headerRating!),
                      ],
                      if (kProposalPrototypeStyleEnabled &&
                          !compact &&
                          _headerStatusPill != null) ...[
                        const SizedBox(width: 6),
                        _headerStatusPill!,
                      ],
                      if (_topStatusLine.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _topStatusLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: DunesColors.resolve(
                                context,
                                ProposalPalette.text3,
                              ),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          _progressToggle(compact: compact),
          const SizedBox(width: 6),
          _topPrimaryTools(),
          if (_topOverflowItems().isNotEmpty) ...[
            const SizedBox(width: 6),
            _topMoreButton(),
          ],
          ProposalIntakeProcessHelpButton(compact: true, purchase: _isPurchase),
        ],
      ),
    );
  }

  static const _topToolH = 28.0;

  BoxDecoration get _topToolDecoration => BoxDecoration(
    color: DunesColors.resolve(
      context,
      const Color(0xFFF3EFFA),
      role: DunesColorRole.surface,
    ),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: DunesColors.resolve(
        context,
        ProposalPalette.borderStrong,
        role: DunesColorRole.border,
      ),
      width: 0.8,
    ),
  );

  Widget _progressToggle({required bool compact}) {
    return Tooltip(
      message: _progressOpen ? '收起进度' : '进度',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('proposal-progress-toggle'),
          onTap: () => setState(() => _progressOpen = !_progressOpen),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: _topToolH,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '进度',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      color: _progressOpen
                          ? DunesColors.resolve(
                              context,
                              ProposalPalette.purpleDeep,
                            )
                          : DunesColors.resolve(context, ProposalPalette.text2),
                    ),
                  ),
                  Icon(
                    _progressOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: _progressOpen
                        ? DunesColors.resolve(
                            context,
                            ProposalPalette.purpleDeep,
                          )
                        : DunesColors.resolve(context, ProposalPalette.text3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressPanel({required bool compact}) {
    if (!_progressOpen) return const SizedBox.shrink();
    final maxHeight =
        (MediaQuery.sizeOf(context).height * (compact ? 0.62 : 0.52))
            .clamp(260.0, 560.0)
            .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        primary: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 18,
            0,
            compact ? 12 : 18,
            4,
          ),
          child: ProposalIntakeProgressTimeline(
            compact: compact,
            initiallyExpanded: true,
            steps: proposalIntakeProgressSteps(
              row: _row,
              people: widget.people,
              options: widget.options,
            ),
          ),
        ),
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
    if (_isPurchase) return _purchaseSectionNav(compact: compact);
    const navH = 40.0;
    final task = _taskSection;
    final sections = [
      ProposalIntakeNavSection.market,
      ProposalIntakeNavSection.tech,
      ProposalIntakeNavSection.finance,
      if (!_isPurchase) ProposalIntakeNavSection.flow,
    ];
    Widget chip(ProposalIntakeNavSection section, {bool expand = false}) {
      final active = _visibleSection == section;
      final mine = task == section;
      final done = proposalIntakeNavSectionComplete(
        row: _row,
        section: section,
      );
      final todoBadge = proposalIntakeNavTodoBadge(_taskAction);
      final todo = mine && !done && todoBadge.isNotEmpty;
      final button = TextButton(
        key: ValueKey('proposal-nav-${section.name}'),
        onPressed: () => _jumpToSection(section),
        style: TextButton.styleFrom(
          foregroundColor: active
              ? DunesColors.resolve(context, ProposalPalette.purpleDeep)
              : DunesColors.resolve(context, ProposalPalette.text2),
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: expand ? 8 : (compact ? 10 : 12),
          ),
          minimumSize: Size(expand ? double.infinity : 0, navH),
          maximumSize: Size(double.infinity, navH),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: expand
              ? VisualDensity.standard
              : VisualDensity.compact,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            fontSize: 12,
            height: 1.1,
            fontWeight: active || mine ? FontWeight.w700 : FontWeight.w600,
            color: active
                ? DunesColors.resolve(context, ProposalPalette.purpleDeep)
                : DunesColors.resolve(context, ProposalPalette.text2),
          ),
          child: kProposalPrototypeFormEnabled
              // 原型：「市场部 ✓」写在标签后面，不再用会被裁掉的角标。
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        proposalIntakeNavSectionLabel(section),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (done) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_rounded,
                        key: ValueKey('proposal-nav-done-${section.name}'),
                        size: 14,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFF3B8B5A),
                        ),
                      ),
                    ] else if (todo) ...[
                      const SizedBox(width: 4),
                      Container(
                        key: ValueKey('proposal-nav-todo-${section.name}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFFB4570F),
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          todoBadge,
                          style: TextStyle(
                            color: DunesColors.resolve(context, Colors.white),
                            fontSize: 9,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : Text(
                  proposalIntakeNavSectionLabel(section),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
        ),
      );
      if (kProposalPrototypeFormEnabled) {
        if (expand) {
          return SizedBox(width: double.infinity, height: navH, child: button);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: button,
        );
      }
      final marked = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (done)
            Positioned(
              right: expand ? 2 : -2,
              top: -5,
              child: Icon(
                Icons.check_circle,
                key: ValueKey('proposal-nav-done-${section.name}'),
                size: 14,
                color: DunesColors.resolve(context, ProposalPalette.green),
              ),
            )
          else if (todo)
            Positioned(
              right: expand ? 2 : -4,
              top: -6,
              child: Container(
                key: ValueKey('proposal-nav-todo-${section.name}'),
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.amber,
                    role: DunesColorRole.surface,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  todoBadge,
                  style: TextStyle(
                    color: DunesColors.resolve(context, Colors.white),
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      );
      if (expand) {
        return SizedBox(width: double.infinity, height: navH, child: marked);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: marked,
      );
    }

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        ProposalPalette.app,
        role: DunesColorRole.surface,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 18,
          9,
          compact ? 12 : 18,
          10,
        ),
        child: Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              const Color(0xFFF1ECF7),
              role: DunesColorRole.surface,
            ),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                ProposalPalette.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final index = sections
                  .indexOf(_visibleSection)
                  .clamp(0, sections.length - 1);
              final tabWidth = constraints.maxWidth / sections.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: tabWidth * index,
                    top: 0,
                    width: tabWidth,
                    height: navH,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          Colors.white,
                          role: DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x144F3488),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final section in sections)
                        Expanded(child: chip(section, expand: true)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _purchaseSectionNav({required bool compact}) {
    const navH = 32.0;
    final task = _taskSection;
    const sections = [
      ProposalIntakeNavSection.toc,
      ProposalIntakeNavSection.market,
      ProposalIntakeNavSection.tech,
      ProposalIntakeNavSection.finance,
    ];
    Widget chip(ProposalIntakeNavSection section) {
      final active = _visibleSection == section;
      final mine = task == section;
      final done = proposalIntakeNavSectionComplete(
        row: _row,
        section: section,
      );
      final todoBadge = proposalIntakeNavTodoBadge(_taskAction);
      final todo = mine && !done && todoBadge.isNotEmpty;
      final button = OutlinedButton(
        key: ValueKey('proposal-nav-${section.name}'),
        onPressed: () => _jumpToSection(section),
        style: OutlinedButton.styleFrom(
          foregroundColor: active
              ? DunesColors.resolve(context, Colors.white)
              : DunesColors.resolve(context, ProposalPalette.purpleDeep),
          backgroundColor: active
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.purple,
                  role: DunesColorRole.surface,
                )
              : mine
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.purpleSoft,
                  role: DunesColorRole.surface,
                )
              : DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ),
          side: BorderSide(
            color: active || mine
                ? DunesColors.resolve(
                    context,
                    ProposalPalette.purple,
                    role: DunesColorRole.border,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.borderStrong,
                    role: DunesColorRole.border,
                  ),
            width: active || mine ? 1.4 : 1,
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          minimumSize: const Size(0, navH),
          maximumSize: const Size(double.infinity, navH),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          proposalIntakeNavSectionLabel(section),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.1,
            fontWeight: active || mine ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            button,
            if (done)
              Positioned(
                right: -2,
                top: -5,
                child: Icon(
                  Icons.check_circle,
                  size: 14,
                  color: DunesColors.resolve(context, ProposalPalette.green),
                ),
              )
            else if (todo)
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      ProposalPalette.amber,
                      role: DunesColorRole.surface,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    todoBadge,
                    style: TextStyle(
                      color: DunesColors.resolve(context, Colors.white),
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          ProposalPalette.app,
          role: DunesColorRole.surface,
        ),
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              ProposalPalette.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: navH,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_outlined,
                  size: 15,
                  color: DunesColors.resolve(context, ProposalPalette.purple),
                ),
                SizedBox(width: 6),
                Text(
                  '定位',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.1,
                    color: DunesColors.resolve(context, ProposalPalette.text3),
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
                children: [for (final section in sections) chip(section)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskBanner({required bool compact}) {
    final action = _taskAction;
    final awaitingModule = action == 'review_tech'
        ? _awaitingTechModuleConfirm
        : proposalIntakeAwaitingModuleConfirm(action, _review);
    final title = proposalIntakeTaskBannerTitle(
      action,
      awaitingModuleConfirm: awaitingModule,
    );
    if (title.isEmpty) return const SizedBox.shrink();
    final body = proposalIntakeTaskBannerBody(
      action,
      awaitingModuleConfirm: awaitingModule,
    );
    final remaining = awaitingModule
        ? 0
        : proposalIntakeTaskRemainingCount(action, _review, form: _form);
    final bodyWithLeft = remaining > 0 ? '还剩 $remaining 条未复核。$body' : body;
    final jump = proposalIntakeNavJumpLabel(
      action,
      awaitingModuleConfirm: awaitingModule,
    );
    final button = jump.isEmpty
        ? null
        : SizedBox(
            height: 32,
            child: FilledButton(
              key: const ValueKey('proposal-task-jump'),
              onPressed: _jumpToTask,
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.resolve(
                  context,
                  ProposalPalette.purple,
                  role: DunesColorRole.surface,
                ),
                foregroundColor: DunesColors.resolve(context, Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
                maximumSize: const Size(double.infinity, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                jump,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
    if (_protoForm) {
      return _protoTaskBanner(
        compact: compact,
        title: title,
        body: body,
        remaining: remaining,
        awaitingModule: awaitingModule,
        button: button,
      );
    }
    final titleText = Text(
      title,
      style: TextStyle(
        color: awaitingModule
            ? DunesColors.resolve(context, ProposalPalette.green)
            : DunesColors.resolve(context, ProposalPalette.purpleDeep),
        fontSize: 13,
        fontWeight: FontWeight.w800,
        height: 1.25,
      ),
    );
    final bodyText = bodyWithLeft.isEmpty
        ? null
        : Text(
            bodyWithLeft,
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text2),
              fontSize: 11,
              height: 1.4,
            ),
          );
    return Container(
      key: const ValueKey('proposal-task-banner'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        compact ? 10 : 10,
        compact ? 12 : 18,
        compact ? 10 : 10,
      ),
      decoration: BoxDecoration(
        color: awaitingModule
            ? DunesColors.resolve(
                context,
                const Color(0xFFECF8EE),
                role: DunesColorRole.surface,
              )
            : DunesColors.resolve(
                context,
                ProposalPalette.soft,
                role: DunesColorRole.surface,
              ),
        border: Border(
          bottom: BorderSide(
            color: awaitingModule
                ? DunesColors.resolve(
                    context,
                    const Color(0xFFB9DDBE),
                    role: DunesColorRole.border,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.borderStrong,
                    role: DunesColorRole.border,
                  ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!compact) ...[
                Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 18,
                  color: awaitingModule
                      ? DunesColors.resolve(context, ProposalPalette.green)
                      : DunesColors.resolve(context, ProposalPalette.purple),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: titleText),
              if (button != null) ...[const SizedBox(width: 10), button],
            ],
          ),
          if (bodyText != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: compact ? 0 : 28),
              child: bodyText,
            ),
          ],
        ],
      ),
    );
  }

  /// 原型底部操作条里的主按钮：当前这一步要做的交接动作。
  /// 与「更多」菜单里的同名动作完全一样，只是按原型放到底部显眼位置。
  ({String label, VoidCallback onPressed, String hint})?
  get _protoPrimaryAction {
    if (_canNotifyTech) {
      return (
        label: '通知财务填写',
        onPressed: () => unawaited(_handoff('notify_tech')),
        hint: '财务技术接口和项目成本由财务部负责人二填',
      );
    }
    if (_canNotifyMarket2) {
      return (
        label: '确认并提交复核',
        onPressed: () => unawaited(_handoff('notify_market2')),
        hint: '提交后各板块负责人开始复核',
      );
    }
    if (_canStartReview) {
      return (
        label: '重新提交并通知审核人',
        onPressed: () => unawaited(_handoff('start_review')),
        hint: '只重新复核被驳回的板块，其他板块保持不变',
      );
    }
    if (_canConfirmTechRevision) {
      return (
        label: '确认本轮科技变更',
        onPressed: () => unawaited(_handoff('confirm_tech_revision')),
        hint: '先科技复核，再市场复核',
      );
    }
    if (_stage == 'awaiting_submit' && _row.id > 0 && _canSubmit) {
      return (
        label: '通知最终人',
        onPressed: () => unawaited(_submit()),
        hint: '确认后内容锁定，交总裁在提案详情页确认',
      );
    }
    return null;
  }

  /// 复核人有待办但不是最后一步确认时，底部给一个「去本板块确认」。
  bool get _protoReviewTask =>
      _taskAction.startsWith('review') && !_awaitingTechModuleConfirm;

  bool get _protoActionBarVisible =>
      _protoForm &&
      !_canDecidePresident &&
      !_awaitingTechModuleConfirm &&
      (_protoPrimaryAction != null || _protoReviewTask);

  /// 原型 .bar：白底、顶部细线和投影；左边一句提示，右边「保存」和主按钮。
  Widget _protoActionBar() {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final primary = _protoPrimaryAction;
    final review = primary == null && _protoReviewTask;
    String hint;
    int hintColor;
    if (review) {
      final left = proposalIntakeTaskRemainingCount(
        _taskAction,
        _review,
        form: _form,
      );
      hint = left > 0 ? '还剩 $left 条没复核 · 有问题可直接驳回本板块' : '逐条已完成，到本板块底部确认通过';
      hintColor = left > 0 ? 0xFFB4570F : 0xFF5B556A;
    } else {
      final missing = _validate();
      if (missing.isEmpty || _stage == 'awaiting_submit') {
        hint = primary!.hint;
        hintColor = 0xFF5B556A;
      } else {
        hint =
            '还差 ${missing.length} 项：${missing.take(2).join('、')}${missing.length > 2 ? '…' : ''}';
        hintColor = 0xFFB4570F;
      }
    }
    ButtonStyle base(int bg, int fg, {int? border}) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      backgroundColor: WidgetStatePropertyAll(c(bg, DunesColorRole.surface)),
      foregroundColor: WidgetStatePropertyAll(c(fg)),
      side: border == null
          ? null
          : WidgetStatePropertyAll(
              BorderSide(color: c(border, DunesColorRole.border)),
            ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
    final buttons = <Widget>[
      if (!review && _canSave)
        OutlinedButton(
          key: const ValueKey('proposal-proto-bar-save'),
          onPressed: widget.saving ? null : () => unawaited(_saveDraft()),
          style: base(0xFFFFFFFF, 0xFF2A2638, border: 0xFFDCD6EA),
          child: const Text('保存'),
        ),
      if (primary != null)
        FilledButton(
          key: const ValueKey('proposal-proto-bar-primary'),
          onPressed: primary.onPressed,
          style: base(0xFF6B4FD8, 0xFFFFFFFF),
          child: Text(primary.label),
        ),
      if (review)
        FilledButton(
          key: const ValueKey('proposal-proto-bar-jump'),
          onPressed: _jumpToTask,
          style: base(0xFF6B4FD8, 0xFFFFFFFF),
          child: const Text('去本板块确认 ↓'),
        ),
    ];
    final hintText = Text(
      hint,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: c(hintColor), fontSize: 12),
    );
    return SafeArea(
      top: false,
      child: DecoratedBox(
        key: const ValueKey('proposal-proto-action-bar'),
        decoration: BoxDecoration(
          color: c(0xFFFFFFFF, DunesColorRole.surface),
          border: Border(
            top: BorderSide(color: c(0xFFE7E3F2, DunesColorRole.border)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F3C2878),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (context, box) {
                  final row = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        buttons[i],
                      ],
                    ],
                  );
                  if (box.maxWidth >= 640) {
                    return Row(
                      children: [
                        Expanded(child: hintText),
                        const SizedBox(width: 10),
                        row,
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hintText,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (var i = 0; i < buttons.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              flex: i == buttons.length - 1 ? 2 : 1,
                              child: buttons[i],
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 原型的待办横幅：标签（待你填写 / 待你复核 / 待你处理）+ 标题 + 说明 + 剩余条数。
  Widget _protoTaskBanner({
    required bool compact,
    required String title,
    required String body,
    required int remaining,
    required bool awaitingModule,
    required Widget? button,
  }) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final action = _taskAction;
    final write = proposalIntakeActionIsWrite(action);
    final review = action.startsWith('review');
    final tag = awaitingModule
        ? '待你确认'
        : (write ? '待你填写' : (review ? '待你复核' : '待你处理'));
    final tagBg = awaitingModule
        ? 0xFF3B8B5A
        : (write ? 0xFFB4570F : (review ? 0xFF6B4FD8 : 0xFF3F2A9A));
    final bg = awaitingModule ? 0xFFEEF6F1 : (write ? 0xFFFDF7F0 : 0xFFF7F5FC);
    final bd = awaitingModule ? 0xFFB9DDBE : (write ? 0xFFF0C9A0 : 0xFFE7E3F2);
    final fg = awaitingModule ? 0xFF2D6E47 : (write ? 0xFF9A4A0C : 0xFF3F2A9A);
    return Padding(
      key: const ValueKey('proposal-task-banner'),
      padding: EdgeInsets.fromLTRB(compact ? 10 : 18, 8, compact ? 10 : 18, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: c(bg, DunesColorRole.surface),
              border: Border.all(color: c(bd, DunesColorRole.border)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c(tagBg, DunesColorRole.surface),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: c(0xFFFFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: c(fg),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (body.isNotEmpty)
                  Text(
                    body,
                    style: TextStyle(color: c(0xFF5B556A), fontSize: 12),
                  ),
                if (remaining > 0)
                  Text(
                    '还剩 $remaining 条',
                    style: TextStyle(
                      color: c(0xFFB4570F),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: kProposalProtoMono,
                      fontFamilyFallback: kProposalProtoMonoFallback,
                    ),
                  ),
                ?button,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskCue(ProposalIntakeNavSection section) {
    if (_taskSection != section) return const SizedBox.shrink();
    final cue = proposalIntakeSectionTaskCue(_taskAction);
    if (cue.isEmpty) return const SizedBox.shrink();
    final remaining = proposalIntakeTaskRemainingCount(
      _taskAction,
      _review,
      form: _form,
    );
    final write = proposalIntakeActionIsWrite(_taskAction);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: write
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.amberSoft,
                  role: DunesColorRole.surface,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.purpleSoft,
                  role: DunesColorRole.surface,
                ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: write
                ? DunesColors.resolve(
                    context,
                    ProposalPalette.amber,
                    role: DunesColorRole.border,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.purple,
                    role: DunesColorRole.border,
                  ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              write ? Icons.edit_outlined : Icons.task_alt_rounded,
              size: 16,
              color: write
                  ? DunesColors.resolve(context, ProposalPalette.amber)
                  : DunesColors.resolve(context, ProposalPalette.purpleDeep),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                remaining > 0 ? '$cue · 还剩 $remaining 条' : cue,
                style: TextStyle(
                  color: write
                      ? DunesColors.resolve(context, ProposalPalette.amber)
                      : DunesColors.resolve(
                          context,
                          ProposalPalette.purpleDeep,
                        ),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topToolSlot({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
    bool loading = false,
  }) {
    final enabled = onPressed != null && !loading;
    return Tooltip(
      message: label,
      child: InkWell(
        key: key,
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          height: _topToolH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        color: enabled
                            ? DunesColors.resolve(
                                context,
                                ProposalPalette.purpleDeep,
                              )
                            : DunesColors.resolve(
                                context,
                                ProposalPalette.text4,
                              ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topPrimaryTools() {
    return DecoratedBox(
      decoration: _topToolDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _topToolSlot(
            key: const ValueKey('proposal-top-save'),
            label: '保存',
            onPressed: widget.saving || !_canSave
                ? null
                : () => unawaited(_saveDraft()),
          ),
          Container(
            width: 0.8,
            height: 14,
            color: DunesColors.resolve(
              context,
              ProposalPalette.borderStrong,
              role: DunesColorRole.surface,
            ),
          ),
          _topToolSlot(
            key: const ValueKey('proposal-top-forward'),
            label: _forwarding ? '转发中…' : '转发',
            loading: _forwarding,
            onPressed: _forwarding || _row.id <= 0
                ? null
                : () => unawaited(_forwardToChat()),
          ),
        ],
      ),
    );
  }

  List<({String label, VoidCallback? onPressed, bool danger})>
  _topOverflowItems() {
    return [
      if (_canRemind)
        (
          label: '催办',
          onPressed: _forwarding ? null : () => unawaited(_handoff('remind')),
          danger: false,
        ),
      if (_canNotifyTech)
        (
          label: '通知财务填写',
          onPressed: () => unawaited(_handoff('notify_tech')),
          danger: false,
        ),
      if (_canNotifyMarket2)
        (
          label: '确认并提交复核',
          onPressed: () => unawaited(_handoff('notify_market2')),
          danger: false,
        ),
      if (_canStartTechRevision)
        (
          label: '发起科技变更',
          onPressed: () => unawaited(_handoff('start_tech_revision')),
          danger: false,
        ),
      if (_canConfirmTechRevision)
        (
          label: '确认本轮科技变更',
          onPressed: () => unawaited(_handoff('confirm_tech_revision')),
          danger: false,
        ),
      if (_canStartReview)
        (
          label: '重新提交并通知审核人',
          onPressed: () => unawaited(_handoff('start_review')),
          danger: false,
        ),
      if (_stage == 'awaiting_submit' && _row.id > 0)
        (
          label: '通知最终人',
          onPressed: _canSubmit ? () => unawaited(_submit()) : null,
          danger: false,
        ),
      if (_canDecidePresident) ...[
        (
          label: '确认通过',
          onPressed: () => unawaited(_decidePresident(approved: true)),
          danger: false,
        ),
        (
          label: '驳回',
          onPressed: () => unawaited(_decidePresident(approved: false)),
          danger: true,
        ),
      ],
      if (_canDelete)
        (
          label: _deleting ? '删除中…' : '删除',
          onPressed: _deleting
              ? null
              : () => unawaited(_confirmDeleteProposal()),
          danger: true,
        ),
    ];
  }

  Widget _topMoreButton() {
    final items = _topOverflowItems();
    final compact = MediaQuery.sizeOf(context).width < ProposalLayout.compact;
    return PopupMenuButton<int>(
      key: const ValueKey('proposal-top-more'),
      tooltip: '更多',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: DunesColors.resolve(context, ProposalPalette.card),
      surfaceTintColor: Colors.transparent,
      elevation: compact ? 0 : 8,
      shadowColor: const Color(0x1A292530),
      constraints: BoxConstraints(
        minWidth: compact ? 220 : 196,
        maxWidth: compact ? 320 : 280,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      onSelected: (index) => items[index].onPressed?.call(),
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<int>>[];
        var dangerStarted = false;
        for (final (i, item) in items.indexed) {
          if (item.danger && !dangerStarted && entries.isNotEmpty) {
            dangerStarted = true;
            entries.add(const PopupMenuDivider(height: 8));
          } else if (item.danger) {
            dangerStarted = true;
          }
          final enabled = item.onPressed != null;
          entries.add(
            PopupMenuItem<int>(
              value: i,
              enabled: enabled,
              height: compact ? 44 : 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: compact ? 8 : 6,
                ),
                decoration: BoxDecoration(
                  color: item.danger
                      ? DunesColors.resolve(
                          context,
                          ProposalPalette.coralSoft,
                          role: DunesColorRole.surface,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: !enabled
                        ? DunesColors.resolve(context, ProposalPalette.text4)
                        : item.danger
                        ? DunesColors.resolve(context, ProposalPalette.coral)
                        : DunesColors.resolve(context, ProposalPalette.text),
                    fontSize: compact ? 14 : 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          );
        }
        return entries;
      },
      child: DecoratedBox(
        decoration: _topToolDecoration,
        child: SizedBox(
          height: _topToolH,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Text(
                '更多',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.purpleDeep,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
              ? '$who 已驳回，请修改后重新通知财务填写，全部流程重新开始。'
              : techRound
              ? '$who 已驳回本轮科技变更。请修改后点右上角「确认本轮科技变更」。'
              : '$who 已驳回本板块。填写人修改后请点右上角「重新提交并通知审核人」，将通知$role再次审核。其他板块复核仍保留。')
        : (president
              ? '$who 驳回意见：$comment。请修改后重新通知财务填写，全部流程重新开始。'
              : techRound
              ? '$who 驳回意见：$comment。请修改后重新提交本轮科技变更。'
              : '$who 驳回意见：$comment。填写人修改后请点右上角「重新提交并通知审核人」，将通知$role再次审核。其他板块复核仍保留。');
    if (_protoForm) {
      // 原型填写页「被驳回」横幅：橙色标签 + 谁驳回了哪个板块 + 意见；按钮在底部操作条。
      Color c(int v, [DunesColorRole r = DunesColorRole.foreground]) =>
          DunesColors.resolve(context, Color(v), role: r);
      final boardName = president
          ? '提案'
          : (_rejectedSection == null
                ? '板块'
                : proposalIntakeNavSectionLabel(_rejectedSection!));
      final next = president
          ? '请修改后重新通知财务填写，全部流程重新开始。'
          : techRound
          ? '请修改后点底部「确认本轮科技变更」。'
          : '只改$boardName，改完点底部「重新提交并通知审核人」，其他板块复核保留。';
      return Container(
        key: const ValueKey('proposal-proto-reject-banner'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: c(0xFFFDF2E6, DunesColorRole.surface),
          border: Border.all(color: c(0xFFF0C9A0, DunesColorRole.border)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c(0xFFB4570F, DunesColorRole.surface),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '被驳回',
                style: TextStyle(
                  color: c(0xFFFFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$boardName被 $who 驳回',
              style: TextStyle(
                color: c(0xFF9A4A0C),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              comment.isEmpty ? next : '意见：$comment。$next',
              style: TextStyle(color: c(0xFF5B556A), fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          ProposalPalette.coralSoft,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE7C2B0),
            role: DunesColorRole.border,
          ),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: DunesColors.resolve(context, ProposalPalette.coral),
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
        color: DunesColors.resolve(
          context,
          ProposalPalette.greenSoft,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFB9DDBE),
            role: DunesColorRole.border,
          ),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _canSubmit
            ? '单条复核和板块复核都已完成。请点击右上角「通知最终人」。已复核内容不可再改；如需改已复核部分请驳回。'
            : '各环节已复核完成。右上角「通知最终人」由${_submitterBannerName()}操作。已复核内容不可再改；如需改已复核部分请驳回。',
        style: TextStyle(
          color: DunesColors.resolve(context, ProposalPalette.green),
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
        // 原型配色：紫色按钮、浅紫底；不开原型样式时与原来一样。
        palette: _protoForm
            ? const XfCommentsPalette(
                accent: Color(0xFF6B4FD8),
                accentSoft: Color(0xFFEDE8FB),
                accentDeep: Color(0xFF3F2A9A),
                soft: Color(0xFFF7F5FC),
              )
            : null,
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
      color: DunesColors.resolve(
        context,
        ProposalPalette.coralSoft,
        role: DunesColorRole.surface,
      ),
      border: Border.all(
        color: DunesColors.resolve(
          context,
          const Color(0xFFE7C2B0),
          role: DunesColorRole.border,
        ),
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '规则校验未通过，禁止提交',
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.coral),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final issue in _issues)
          Text(
            '• $issue',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.coral),
              fontSize: 11,
            ),
          ),
      ],
    ),
  );

  /// 提案目录。
  ///
  /// 定位条只有板块名字。这里放在审批进度下面、市场部上面：名字、里面有什么、当前状态。
  /// 点定位条「目录」滚回来；点这一行跳到对应板块。
  Widget _proposalToc(bool wide) {
    final task = _taskSection;
    final entries =
        <
          ({
            ProposalIntakeNavSection section,
            String no,
            String desc,
            String? flag,
          })
        >[
          (
            section: ProposalIntakeNavSection.market,
            no: '一',
            desc: '选业务板块与标签、挂采购与销售合同、写政策与风险',
            flag: 'marketCompleted',
          ),
          (
            section: ProposalIntakeNavSection.tech,
            no: '二',
            desc: '选平台与能力、定输出形式、勾财务对账字段、报研发费用与交付',
            flag: 'technologyCompleted',
          ),
          (
            section: ProposalIntakeNavSection.finance,
            no: '三',
            desc: '填产品结算、报四组成本、填收付款主体与账户、逐条复核',
            flag: 'financeCompleted',
          ),
          if (!_isPurchase)
            (
              section: ProposalIntakeNavSection.flow,
              no: '四',
              desc: '看货 / 资金 / 发票 / 信息四条链路卡在哪一段',
              flag: null,
            ),
        ];

    Widget statusChip(String? flag, ProposalIntakeNavSection section) {
      final mine = task == section;
      if (mine &&
          (flag == null || !_moduleReviewed(flag)) &&
          proposalIntakeSectionTaskCue(_taskAction).isNotEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              ProposalPalette.amberSoft,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            proposalIntakeSectionTaskCue(_taskAction),
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.amber),
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
      if (flag == null) {
        return Text(
          '自动生成',
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text3),
            fontSize: 11,
          ),
        );
      }
      final done = _moduleReviewed(flag);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: done
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.greenSoft,
                  role: DunesColorRole.surface,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.soft,
                  role: DunesColorRole.surface,
                ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          done ? '已复核' : '未完成',
          style: TextStyle(
            color: done
                ? DunesColors.resolve(context, ProposalPalette.green)
                : DunesColors.resolve(context, ProposalPalette.text3),
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final active = _visibleSection == e.section;
      final title = Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              e.no,
              style: TextStyle(
                color: active
                    ? DunesColors.resolve(context, ProposalPalette.purple)
                    : DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            proposalIntakeNavSectionLabel(e.section),
            style: TextStyle(
              color: active
                  ? DunesColors.resolve(context, ProposalPalette.purpleDeep)
                  : DunesColors.resolve(context, ProposalPalette.text),
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
      final desc = Text(
        e.desc,
        maxLines: wide ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: DunesColors.resolve(context, ProposalPalette.text3),
          fontSize: 11.5,
          height: 1.4,
        ),
      );
      rows.add(
        InkWell(
          key: ValueKey('proposal-toc-${e.section.name}'),
          onTap: () => _jumpToSection(e.section),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.soft,
                      role: DunesColorRole.surface,
                    )
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: i == entries.length - 1
                      ? Colors.transparent
                      : DunesColors.resolve(
                          context,
                          ProposalPalette.borderSoft,
                          role: DunesColorRole.border,
                        ),
                ),
              ),
            ),
            child: wide
                ? Row(
                    children: [
                      SizedBox(width: 92, child: title),
                      const SizedBox(width: 12),
                      Expanded(child: desc),
                      const SizedBox(width: 12),
                      statusChip(e.flag, e.section),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: title),
                          statusChip(e.flag, e.section),
                        ],
                      ),
                      const SizedBox(height: 4),
                      desc,
                    ],
                  ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            ProposalPalette.card,
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: DunesColors.resolve(
              context,
              ProposalPalette.border,
              role: DunesColorRole.border,
            ),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.app,
                  role: DunesColorRole.surface,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: DunesColors.resolve(
                      context,
                      ProposalPalette.borderSoft,
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '目录',
                    style: TextStyle(
                      color: DunesColors.resolve(context, ProposalPalette.text),
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '点一行跳到对应板块',
                    style: TextStyle(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.text3,
                      ),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _marketSheetGroup({
    required String label,
    required String description,
    required Widget child,
    bool first = false,
  }) {
    // 原型简单行：不要「身份 / 产品 / 人」这类分组标题，字段直接一行一条。
    if (_simpleView) return child;
    if (_protoForm) {
      // 原型分组标题：紫色小标题 + 一条细线，下面直接是字段行。
      return Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(0, first ? 2 : 10, 0, 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFEDE8F6),
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFF3F2A9A),
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kProposalCaptionStyle,
                    ),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(10, first ? 10 : 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!first)
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Divider(
                height: 1,
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Row(
              children: [
                Text(label, style: kProposalEyebrowStyle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kProposalCaptionStyle,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _collapsedMarketMultiField(
    String label,
    String key,
    List<String> options,
    String addLabel, {
    bool required = false,
    String? resetReview,
  }) {
    final enabled = _fillEnabled(null, resetReview: resetReview);
    final selected = _setOf(key);
    final preview = selected.take(3).join('、');
    final summary = selected.isEmpty
        ? '请选择'
        : '已选 ${selected.length}${preview.isEmpty ? '' : ' · $preview${selected.length > 3 ? '…' : ''}'}';
    return _anchor(
      key,
      _FullWidthField(
        child: ProposalField(
          label: label,
          required: required,
          child: ExpansionTile(
            key: PageStorageKey('proposal-market-$key'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 6, bottom: 4),
            minTileHeight: 34,
            dense: true,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected.isEmpty
                    ? DunesColors.resolve(context, ProposalPalette.text3)
                    : DunesColors.resolve(context, ProposalPalette.text),
                fontSize: 13,
                fontWeight: selected.isEmpty
                    ? FontWeight.w400
                    : FontWeight.w600,
              ),
            ),
            trailing: Text(
              '展开',
              style: TextStyle(
                color: enabled
                    ? DunesColors.resolve(context, ProposalPalette.purpleDeep)
                    : DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ProposalPills(
                  options: [
                    ...options,
                    ...selected.where((value) => !options.contains(value)),
                  ],
                  selected: selected,
                  enabled: enabled,
                  onToggle: (value) =>
                      _toggleList(key, value, resetReview: resetReview),
                  onAdd: enabled
                      ? () =>
                            _addOption(key, addLabel, resetReview: resetReview)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _salesMarketSheet(bool wide) {
    return ProposalCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _marketSheetGroup(
            first: true,
            label: '身份',
            description: '提案所属与规模',
            child: _fieldGrid(
              wide,
              [
                _catalogDropdownField(
                  '业务板块',
                  current:
                      _formRef('sectorRef') ??
                      CatalogRef.fromName(_text('sector')),
                  options: _sectorOptions(),
                  required: true,
                  resetReview: 'marketCompleted',
                  hint: _sectorCatalog.isEmpty ? '请选择业务板块' : '请选择资管产品一级分类',
                  onSelected: (value) {
                    _setMany({
                      'sector': value?.name ?? '',
                      'sectorRef': catalogRefToJson(value),
                      'product': '',
                      'productRef': null,
                      'productL3': '',
                      'productL3Ref': null,
                    }, resetReview: 'marketCompleted');
                    unawaited(_loadProductL3(null));
                  },
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
                _textField(
                  '规模（万元）',
                  'salesScale',
                  required: true,
                  hint: '年化规模，单位万元',
                  resetReview: 'marketCompleted',
                ),
                _textField(
                  '子标题（在财务部填写）',
                  'proposalSubtitle',
                  hint: '由财务部负责人二填写（选填）',
                  writable: _canEditProposalSubtitle,
                  resetReview: 'financeCompleted',
                  reviewSection: 'financeItem:proposalSubtitle',
                  reviewLabel: _subtitleFillLabel,
                ),
              ],
              columns: 4,
              flat: true,
            ),
          ),
          _marketSheetGroup(
            label: '产品',
            description: '产品、子分类、项目与供给',
            child: _fieldGrid(
              wide,
              [
                _catalogDropdownField(
                  '产品（标签一）',
                  current:
                      _formRef('productRef') ??
                      CatalogRef.fromName(_text('product')),
                  options: _productOptions(),
                  required: true,
                  resetReview: 'marketCompleted',
                  enabled:
                      (_formRef('sectorRef') ??
                              CatalogRef.fromName(_text('sector')))
                          .isNotEmpty ||
                      _productOptions().isNotEmpty,
                  hint:
                      (_formRef('sectorRef') ??
                              CatalogRef.fromName(_text('sector')))
                          .isEmpty
                      ? '请先选择业务板块'
                      : '请选择产品二级分类',
                  onSelected: (value) {
                    _setMany({
                      'product': value?.name ?? '',
                      'productRef': catalogRefToJson(value),
                      'productL3': '',
                      'productL3Ref': null,
                    }, resetReview: 'marketCompleted');
                    unawaited(_loadProductL3(value));
                  },
                ),
                _catalogDropdownField(
                  '子分类',
                  current:
                      _formRef('productL3Ref') ??
                      CatalogRef.fromName(_text('productL3')),
                  options: _productL3Options(),
                  required: false,
                  resetReview: 'marketCompleted',
                  enabled: _selectedProduct().isNotEmpty,
                  hint: _selectedProduct().isEmpty
                      ? '请先选择产品（标签一）'
                      : '请选择子分类（选填）',
                  emptyText: _productL3LoadingEmptyText(),
                  onSelected: (value) => _setMany({
                    'productL3': value?.name ?? '',
                    'productL3Ref': catalogRefToJson(value),
                  }, resetReview: 'marketCompleted'),
                ),
                _catalogDropdownField(
                  '项目名称（标签一二级）',
                  current:
                      _formRef('projectRef') ??
                      CatalogRef.fromName(_text('projectName')),
                  options: _projectOptions(),
                  required: true,
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
                _collapsedMarketMultiField(
                  '供给（标签二）',
                  'supplies',
                  widget.options.supplies,
                  '新增供给',
                  required: true,
                  resetReview: 'marketCompleted',
                ),
              ],
              columns: 3,
              flat: true,
            ),
          ),
          _marketSheetGroup(
            label: '人',
            description: '填写、复核、运营与最终确认',
            child: _fieldGrid(
              wide,
              [
                _personField(
                  '市场部负责人二（科技审核）',
                  'marketOwner2',
                  positionIncludes: '市场部负责人二',
                  required: true,
                ),
                _personField(
                  '市场部负责人一（整板块复核）',
                  'marketOwner1',
                  positionIncludes: '市场部负责人一',
                  required: true,
                ),
                _personField(
                  '运营',
                  'operator',
                  positionIncludes: '运营',
                  required: true,
                ),
                _configuredPresidentsField(),
              ],
              columns: 4,
              flat: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 市场部板块统一复核（销售、采购同一个），简单行和完整表单都用。
  Widget _marketModuleReviewCard({bool plain = true}) => _moduleReview(
    key: _marketModuleReviewKey,
    title: '市场部板块统一复核',
    description: proposalIntakeMarketReviewBlocked(_review)
        ? '请先完成科技部复核，再复核市场（先科技后市场）。'
        : '市场部负责人一确认提交人填写的全部业务内容',
    keyName: 'marketCompleted',
    buttonLabel: '整个板块复核通过',
    locked: proposalIntakeMarketReviewBlocked(_review),
    plain: plain,
  );

  /// 原型「填报内容 · 市场部」（销售）：一行一条。名称、规模已在标题和测算里，不再重复；
  /// 负责人、合同、盈利模式各合成一行；子分类、子标题没填就不显示。
  Widget _salesMarketSimple(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldGrid(wide, [
          _simpleLine(
            '产品提案名称',
            _text('proposalName'),
            anchorKey: 'proposalName',
            required: true,
          ),
          _simpleLine(
            '业务板块',
            _text('sector'),
            anchorKey: 'sector',
            required: true,
          ),
          _simpleLine(
            '提案类型',
            _text('proposalType'),
            anchorKey: 'proposalType',
            required: true,
          ),
          // 顶部测算「年化规模 · 来自 市场部」点过来要落在这一行。
          _simpleLine(
            '规模（万元）',
            _text('salesScale'),
            anchorKey: 'salesScale',
            required: true,
          ),
          _simpleLine(
            '产品（标签一）',
            _text('product'),
            anchorKey: 'product',
            required: true,
          ),
          _simpleLine('子分类', _text('productL3'), anchorKey: 'productL3'),
          _simpleLine(
            '项目（标签一二级）',
            _text('projectName'),
            anchorKey: 'projectName',
            required: true,
          ),
          _simpleLine(
            '供给（标签二）',
            _setOf('supplies').join('、'),
            anchorKey: 'supplies',
            required: true,
          ),
          _textField(
            '子标题',
            'proposalSubtitle',
            writable: _canEditProposalSubtitle,
            resetReview: 'financeCompleted',
            reviewSection: 'financeItem:proposalSubtitle',
            reviewLabel: _subtitleFillLabel,
          ),
          _simpleLine(
            '负责人',
            _simplePeopleText(const [
              ('市场二', 'marketOwner2'),
              ('市场一', 'marketOwner1'),
              ('运营', 'operator'),
            ], extra: _simplePresidentText),
            anchorKey: 'marketOwner1',
            required: true,
            fullWidth: true,
          ),
          _contractSimpleLine('采购合同', 'purchase'),
          _contractTermsLine('采购合同核心条款', 'purchase'),
          _contractSimpleLine('销售合同', 'sales'),
          _contractTermsLine('销售合同核心条款', 'sales'),
          _textField(
            '供货商政策',
            'supplierPolicy',
            maxLines: 3,
            fullWidth: true,
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '渠道政策',
            'channelPolicy',
            maxLines: 3,
            fullWidth: true,
            required: true,
            resetReview: 'marketCompleted',
          ),
          _profitSimpleLine(),
          _textField(
            '执行计划',
            'executionPlan',
            maxLines: 4,
            fullWidth: false,
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '风险点',
            'riskPoints',
            maxLines: 4,
            fullWidth: false,
            required: true,
            resetReview: 'marketCompleted',
          ),
        ]),
        _marketModuleReviewCard(),
      ],
    );
  }

  Widget _marketSection(bool wide) {
    if (_isPurchase) return _purchaseMarketSection(wide);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _marketKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ProposalSectionTitle(
                title: '市场部',
                tag: 'Market',
                description: '定义提案身份、产品、负责人及合同执行信息。',
                lighthouse: true,
              ),
              _taskCue(ProposalIntakeNavSection.market),
            ],
          ),
        ),
        if (_simpleView)
          _salesMarketSimple(wide)
        else
          ..._salesMarketForm(wide),
      ],
    );
  }

  List<Widget> _salesMarketForm(bool wide) {
    return [
      _salesMarketSheet(wide),
      _contractCard('03', '采购合同', 'purchase', wide),
      if (!_isPurchase) _contractCard('04', '销售合同', 'sales', wide),
      _stepCard(
        _isPurchase ? '04' : '05',
        '政策与执行',
        _isPurchase ? '供货商政策、合作计划与风险点' : '合同政策、合作计划与盈利方式',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldGrid(wide, [
              _textField(
                '供货商政策',
                'supplierPolicy',
                maxLines: 3,
                minLines: 1,
                required: true,
                source: '合同抓取 · 可修改',
                resetReview: 'marketCompleted',
              ),
              if (!_isPurchase)
                _textField(
                  '渠道政策',
                  'channelPolicy',
                  maxLines: 3,
                  minLines: 1,
                  required: true,
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
                required: true,
                resetReview: 'marketCompleted',
              ),
              _textField(
                '合作风险点',
                'riskPoints',
                maxLines: 4,
                required: true,
                resetReview: 'marketCompleted',
              ),
              if (!_isPurchase) ...[
                _multiField(
                  '盈利模式 · 需写明计算方式',
                  'profitModes',
                  widget.options.profitModes,
                  '新增盈利模式',
                  required: true,
                  resetReview: 'marketCompleted',
                ),
                _textField(
                  '盈利计算说明',
                  'profitFormula',
                  maxLines: 3,
                  required: true,
                  resetReview: 'marketCompleted',
                ),
              ],
            ]),
          ],
        ),
      ),
      _marketModuleReviewCard(),
    ];
  }

  void _appendTechnologyRecord() {
    if (!_canEditTech) return;
    final next = proposalIntakeAppendTechnologyRecord(_form);
    final review = Map<String, dynamic>.from(_review)
      ..['technologyCompleted'] = false;
    setState(() {
      _markFormDirty();
      _row = _row.copyWith(
        form: next,
        review: review,
        status: _statusAfterEdit,
      );
    });
    _emitChanged(_row);
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, ProposalPalette.text),
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
        color: DunesColors.resolve(
          context,
          ProposalPalette.soft,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, style: kProposalCaptionStyle),
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
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: DunesColors.resolve(context, ProposalPalette.text),
              ),
            ),
          if (summary.isNotEmpty)
            Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, ProposalPalette.text2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _techSection(bool wide) {
    final interfaces = proposalIntakeShouldDefaultFinanceInterfaces(_row)
        ? proposalIntakeResolvedFinanceInterfaces(
            _form['financeInterfaces'] is Map
                ? Map<String, dynamic>.from(_form['financeInterfaces'])
                : <String, dynamic>{},
            widget.options.financeInterfaces,
          )
        : (_form['financeInterfaces'] is Map
              ? Map<String, dynamic>.from(_form['financeInterfaces'])
              : <String, dynamic>{});
    if (!_isPurchase) return _salesTechSection(wide, interfaces);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _techKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 与销售提案一致的板块标题（复核、查看时由简单行隐藏）。
              if (_protoForm)
                const ProposalSectionTitle(
                  title: '科技部',
                  tag: 'Technology',
                  description: '配置平台、能力输入、财务接口、研发费用与交付时间。',
                  lighthouse: true,
                ),
              _taskCue(ProposalIntakeNavSection.tech),
            ],
          ),
        ),
        ProposalCard(
          child: Column(
            children: [
              _fieldGrid(wide, [
                _personField(
                  '科技部负责人',
                  'technologyOwner',
                  positionIncludes: '科技部负责人',
                  required: true,
                ),
                _dropdownField(
                  'τ-标签一',
                  'technologyPlatform',
                  widget.options.platforms.map((item) => item.value).toList(),
                  required: true,
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:technologyPlatform',
                  reviewLabel: _techReviewLabel,
                  addLabel: '新增标签一',
                ),
                _multiField(
                  _isPurchase ? '能力输入形式' : '能力输出形式',
                  'outputForms',
                  proposalIntakeOutputFormOptions(widget.options.outputForms),
                  _isPurchase ? '新增形式' : null,
                  required: true,
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:outputForms',
                  reviewLabel: _techReviewLabel,
                ),
              ]),
              const SizedBox(height: 10),
              _fieldGrid(wide, [_techSyncSourceField()]),
              if (_simpleView)
                _fieldGrid(wide, [
                  _simpleLine(
                    '财务技术接口',
                    widget.options.financeInterfaces
                        .where((item) => interfaces[item.key] == true)
                        .map((item) => item.label)
                        .join('、'),
                    anchorKey: 'financeInterfaces',
                    required: true,
                    fullWidth: true,
                    trailing: _rowReviewToggle(
                      'technologyItem:financeInterfaces',
                      _techReviewLabel,
                    ),
                  ),
                ])
              else
                _anchor(
                  'financeInterfaces',
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.app,
                        role: DunesColorRole.surface,
                      ),
                      border: Border.all(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.border,
                          role: DunesColorRole.border,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '财务技术接口 · 根据项目成本动态生成',
                                    style: TextStyle(
                                      color: DunesColors.resolve(
                                        context,
                                        ProposalPalette.text,
                                      ),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '由财务部负责人二填写，科技部负责人随科技板块复核',
                                    style: TextStyle(
                                      color: DunesColors.resolve(
                                        context,
                                        ProposalPalette.text3,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_rowReviewToggle(
                                  'technologyItem:financeInterfaces',
                                  _techReviewLabel,
                                )
                                case final toggle?)
                              toggle,
                          ],
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
                            ignoring: !_canEditFinanceInterface,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item
                                    in widget.options.financeInterfaces)
                                  ProposalChoiceChip(
                                    label:
                                        '${item.label}${item.required ? ' *' : ''}',
                                    selected: interfaces[item.key] == true,
                                    enabled: _canEditFinanceInterface,
                                    onSelected: (selected) {
                                      if (!_canEditFinanceInterface) return;
                                      final next = Map<String, dynamic>.from(
                                        interfaces,
                                      )..[item.key] = selected;
                                      _set(
                                        'financeInterfaces',
                                        next,
                                        resetReview: 'technologyCompleted',
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              _fieldGrid(wide, [
                if (_simpleView)
                  _rdSimpleLine()
                else ...[
                  _multiField(
                    '研发类型',
                    'developmentTypes',
                    _isPurchase
                        ? kPurchaseDevelopmentTypes
                        : widget.options.developmentTypes,
                    _isPurchase ? '新增类型' : null,
                    required: true,
                    writable: _canEditTech,
                    resetReview: 'technologyCompleted',
                    reviewSection: 'technologyItem:developmentTypes',
                    reviewLabel: _techReviewLabel,
                  ),
                  _dropdownField(
                    '是否涉及研发费用',
                    'hasRdCost',
                    const ['是', '否'],
                    required: true,
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
                ],
                _dateField(
                  '交付时间',
                  'deliveryDate',
                  required: true,
                  writable: _canEditTech,
                  resetReview: 'technologyCompleted',
                  reviewSection: 'technologyItem:deliveryDate',
                  reviewLabel: _techReviewLabel,
                ),
              ]),
              if (_showTechnologyHandoffRecords && _canEditTech) ...[
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
              if (_showTechnologyHandoffRecords) ...[
                ..._technologyRecordCards(),
                ..._technologyHistoryCards(),
              ],
            ],
          ),
        ),
        if (kProposalChildTechEnabled &&
            proposalIntakeHasChildProducts(_form)) ...[
          const SizedBox(height: 12),
          _childTechCard(wide),
        ],
        if (!_isPurchase) ProposalCard(child: _skuDetailsBlock(wide)),
        _moduleReview(
          key: _techModuleReviewKey,
          title: '科技部板块审核',
          description:
              '填写人填写，科技部负责人复核科技字段（含财务技术接口）并对业务平台产品整板块复核后统一确认。确认前会检查遗漏。发现问题可直接整板块驳回。',
          keyName: 'technologyCompleted',
          buttonLabel:
              proposalIntakeTechnologyReviewGaps(_review, form: _form).isEmpty
              ? '确认本板块通过'
              : '科技部字段全部复核',
          locked: false,
          progress:
              '逐条复核 ${_technologyReviewedCount()}/${_technologyReviewFields.length}',
          omissions: proposalIntakeTechnologyReviewGaps(_review, form: _form),
          onCheckOmissions: _showTechnologyOmissions,
        ),
      ],
    );
  }

  Widget _salesTechSection(bool wide, Map<String, dynamic> interfaces) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _techKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ProposalSectionTitle(
                title: '科技部',
                tag: 'Technology',
                description: '配置平台、能力输出、财务接口、研发费用与交付时间。',
                lighthouse: true,
              ),
              _taskCue(ProposalIntakeNavSection.tech),
            ],
          ),
        ),
        ProposalCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _marketSheetGroup(
                first: true,
                label: '配置',
                description: '负责人、平台与能力输出',
                child: _fieldGrid(
                  wide,
                  [
                    _personField(
                      '科技部负责人',
                      'technologyOwner',
                      positionIncludes: '科技部负责人',
                      required: true,
                    ),
                    _dropdownField(
                      'τ-标签一',
                      'technologyPlatform',
                      widget.options.platforms
                          .map((item) => item.value)
                          .toList(),
                      required: true,
                      writable: _canEditTech,
                      resetReview: 'technologyCompleted',
                      reviewSection: 'technologyItem:technologyPlatform',
                      reviewLabel: _techReviewLabel,
                      addLabel: '新增标签一',
                    ),
                    _multiField(
                      '能力输出形式',
                      'outputForms',
                      proposalIntakeOutputFormOptions(
                        widget.options.outputForms,
                      ),
                      null,
                      required: true,
                      writable: _canEditTech,
                      resetReview: 'technologyCompleted',
                      reviewSection: 'technologyItem:outputForms',
                      reviewLabel: _techReviewLabel,
                    ),
                  ],
                  columns: 3,
                  flat: true,
                ),
              ),
              _marketSheetGroup(
                label: '接口',
                description: '业务平台与财务技术接口',
                child: _fieldGrid(
                  wide,
                  [
                    _techSyncSourceField(),
                    _salesFinanceInterfaceField(interfaces),
                  ],
                  columns: 3,
                  flat: true,
                ),
              ),
              _marketSheetGroup(
                label: '研发',
                description: '研发类型、费用与交付',
                child: _fieldGrid(
                  wide,
                  [
                    if (_simpleView)
                      _rdSimpleLine()
                    else ...[
                      _multiField(
                        '研发类型',
                        'developmentTypes',
                        widget.options.developmentTypes,
                        null,
                        required: true,
                        writable: _canEditTech,
                        resetReview: 'technologyCompleted',
                        reviewSection: 'technologyItem:developmentTypes',
                        reviewLabel: _techReviewLabel,
                      ),
                      _dropdownField(
                        '是否涉及研发费用',
                        'hasRdCost',
                        const ['是', '否'],
                        required: true,
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
                    ],
                    _dateField(
                      '交付时间',
                      'deliveryDate',
                      required: true,
                      writable: _canEditTech,
                      resetReview: 'technologyCompleted',
                      reviewSection: 'technologyItem:deliveryDate',
                      reviewLabel: _techReviewLabel,
                    ),
                  ],
                  columns: 3,
                  flat: true,
                ),
              ),
            ],
          ),
        ),
        if (_showTechnologyHandoffRecords && _canEditTech) ...[
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
        if (_showTechnologyHandoffRecords) ...[
          ..._technologyRecordCards(),
          ..._technologyHistoryCards(),
        ],
        if (kProposalChildTechEnabled &&
            proposalIntakeHasChildProducts(_form)) ...[
          const SizedBox(height: 12),
          _childTechCard(wide),
        ],
        if (_simpleView)
          _techSkuSimple(wide)
        else
          ProposalCard(child: _skuDetailsBlock(wide)),
        _moduleReview(
          key: _techModuleReviewKey,
          title: '科技部板块审核',
          description:
              '填写人填写，科技部负责人复核科技字段（含财务技术接口）并对业务平台产品整板块复核后统一确认。确认前会检查遗漏。发现问题可直接整板块驳回。',
          keyName: 'technologyCompleted',
          buttonLabel:
              proposalIntakeTechnologyReviewGaps(_review, form: _form).isEmpty
              ? '确认本板块通过'
              : '科技部字段全部复核',
          locked: false,
          progress:
              '逐条复核 ${_technologyReviewedCount()}/${_technologyReviewFields.length}',
          omissions: proposalIntakeTechnologyReviewGaps(_review, form: _form),
          onCheckOmissions: _showTechnologyOmissions,
          plain: true,
        ),
      ],
    );
  }

  Widget _salesFinanceInterfaceField(Map<String, dynamic> interfaces) {
    return _anchor(
      'financeInterfaces',
      _FullWidthField(
        child: ProposalField(
          label: '财务技术接口 · 根据项目成本动态生成',
          source: '财务部负责人二填写',
          trailing: _rowReviewToggle(
            'technologyItem:financeInterfaces',
            _techReviewLabel,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '科技部负责人随科技板块复核',
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text3),
                    fontSize: 11,
                  ),
                ),
              ),
              if (_showSelectedAsText)
                _readonlySelectedText(
                  widget.options.financeInterfaces
                      .where((item) => interfaces[item.key] == true)
                      .map((item) => item.label)
                      .join('、'),
                )
              else
                IgnorePointer(
                  ignoring: !_canEditFinanceInterface,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in widget.options.financeInterfaces)
                        ProposalChoiceChip(
                          label: '${item.label}${item.required ? ' *' : ''}',
                          selected: interfaces[item.key] == true,
                          enabled: _canEditFinanceInterface,
                          onSelected: (selected) {
                            if (!_canEditFinanceInterface) return;
                            final next = Map<String, dynamic>.from(interfaces)
                              ..[item.key] = selected;
                            _set(
                              'financeInterfaces',
                              next,
                              resetReview: 'technologyCompleted',
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _productScopeNames(
    List<ProposalSkuDetailRow> products, {
    required String fallback,
  }) {
    final names = [
      for (var i = 0; i < products.length; i++)
        products[i].displayName.isEmpty
            ? '$fallback ${i + 1}'
            : products[i].displayName,
    ];
    return names.isEmpty ? fallback : names.join('、');
  }

  Widget _childTechCard(bool wide) {
    final snap = proposalIntakeChildTechnology(_form);
    final platformName = '${snap['technologyPlatform'] ?? ''}'.trim();
    final storedInterfaces = snap['financeInterfaces'] is Map
        ? Map<String, dynamic>.from(snap['financeInterfaces'] as Map)
        : <String, dynamic>{};
    final interfaces = proposalIntakeShouldDefaultFinanceInterfaces(_row)
        ? proposalIntakeResolvedFinanceInterfaces(
            storedInterfaces,
            widget.options.financeInterfaces,
          )
        : storedInterfaces;
    Set<String> selectedOf(String key) {
      final value = snap[key];
      return value is List ? value.map((item) => '$item').toSet() : <String>{};
    }

    String reviewOf(String field) =>
        'technologyItem:$kProposalChildTechReviewPrefix$field';

    return ProposalCard(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$kProposalChildProductLabel科技',
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.green),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '对应$kProposalChildProductLabel：${_productScopeNames(proposalIntakeChildProducts(_form), fallback: '未命名$kProposalChildProductLabel')}',
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.green),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$kProposalChildProductLabel合并共用这一套科技字段，不按$kProposalChildProductLabel切换。',
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _fieldGrid(wide, [
            _dropdownField(
              'τ-标签一',
              'technologyPlatform',
              widget.options.platforms.map((item) => item.value).toList(),
              required: true,
              writable: _canEditTech,
              resetReview: 'technologyCompleted',
              reviewSection: reviewOf('technologyPlatform'),
              reviewLabel: _techReviewLabel,
              valueOverride: platformName,
              fieldKey: 'child-technologyPlatform',
              onSelected: (value) =>
                  _setChildTech('technologyPlatform', value ?? ''),
            ),
            _multiField(
              '能力输出形式',
              'outputForms',
              proposalIntakeOutputFormOptions(widget.options.outputForms),
              null,
              required: true,
              writable: _canEditTech,
              resetReview: 'technologyCompleted',
              reviewSection: reviewOf('outputForms'),
              reviewLabel: _techReviewLabel,
              selectedOverride: selectedOf('outputForms'),
              fieldKey: 'child-outputForms',
              onToggleOverride: (value) =>
                  _toggleChildTechList('outputForms', value),
            ),
          ]),
          const SizedBox(height: 10),
          _fieldGrid(wide, [
            _techSyncSourceField(
              fieldKey: 'child-syncSourceRef',
              valueOverride: proposalIntakeFormSyncSourceRef(snap),
              reviewSection: reviewOf('syncSourceRef'),
              onSelected: (value) =>
                  _setChildTech('syncSourceRef', catalogRefToJson(value)),
            ),
          ]),
          _anchor(
            'child-financeInterfaces',
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.app,
                  role: DunesColorRole.surface,
                ),
                border: Border.all(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.border,
                    role: DunesColorRole.border,
                  ),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$kProposalChildProductLabel财务技术接口',
                              style: TextStyle(
                                color: DunesColors.resolve(
                                  context,
                                  ProposalPalette.text,
                                ),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '由财务部负责人二填写，科技部负责人随科技板块复核',
                              style: TextStyle(
                                color: DunesColors.resolve(
                                  context,
                                  ProposalPalette.text3,
                                ),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_rowReviewToggle(
                            reviewOf('financeInterfaces'),
                            _techReviewLabel,
                          )
                          case final toggle?)
                        toggle,
                    ],
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
                      ignoring: !_canEditFinanceInterface,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in widget.options.financeInterfaces)
                            ProposalChoiceChip(
                              label:
                                  '${item.label}${item.required ? ' *' : ''}',
                              selected: interfaces[item.key] == true,
                              enabled: _canEditFinanceInterface,
                              onSelected: (selected) {
                                if (!_canEditFinanceInterface) return;
                                final next = Map<String, dynamic>.from(
                                  interfaces,
                                )..[item.key] = selected;
                                _setChildTech('financeInterfaces', next);
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _fieldGrid(wide, [
            _multiField(
              '研发类型',
              'developmentTypes',
              widget.options.developmentTypes,
              null,
              required: true,
              writable: _canEditTech,
              resetReview: 'technologyCompleted',
              reviewSection: reviewOf('developmentTypes'),
              reviewLabel: _techReviewLabel,
              selectedOverride: selectedOf('developmentTypes'),
              fieldKey: 'child-developmentTypes',
              onToggleOverride: (value) =>
                  _toggleChildTechList('developmentTypes', value),
            ),
            _dropdownField(
              '是否涉及研发费用',
              'hasRdCost',
              const ['是', '否'],
              required: true,
              writable: _canEditTech,
              resetReview: 'technologyCompleted',
              reviewSection: reviewOf('hasRdCost'),
              reviewLabel: _techReviewLabel,
              valueOverride: '${snap['hasRdCost'] ?? ''}',
              fieldKey: 'child-hasRdCost',
              onSelected: (value) => _setChildTech('hasRdCost', value ?? ''),
            ),
            _numberField(
              '研发费用金额（万元）',
              'rdAmount',
              writable: _canEditTech,
              resetReview: 'technologyCompleted',
              reviewSection: reviewOf('rdAmount'),
              reviewLabel: _techReviewLabel,
              valueOverride: '${snap['rdAmount'] ?? ''}',
              fieldKey: 'child-rdAmount',
              onWrite: (value) => _setChildTech(
                'rdAmount',
                value.trim().isEmpty ? null : double.tryParse(value) ?? 0,
                rebuild: false,
              ),
            ),
            _dateField(
              '交付时间',
              'deliveryDate',
              required: true,
              writable: _canEditTech,
              resetReview: 'technologyCompleted',
              reviewSection: reviewOf('deliveryDate'),
              reviewLabel: _techReviewLabel,
              valueOverride: '${snap['deliveryDate'] ?? ''}',
              fieldKey: 'child-deliveryDate',
              onWrite: (value) => _setChildTech('deliveryDate', value),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _financeSection(bool wide) {
    if (_isPurchase) return _purchaseFinanceSection(wide);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _financeKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ProposalSectionTitle(
                title: '财务部',
                tag: 'Finance',
                description: '统一填写结算、成本、收付款与账户信息。',
                lighthouse: true,
              ),
              _taskCue(ProposalIntakeNavSection.finance),
            ],
          ),
        ),
        ProposalCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _marketSheetGroup(
                first: true,
                label: '人',
                description: '填写、逐条复核与整板块确认',
                child: _simpleView
                    ? _fieldGrid(wide, [
                        _simpleLine(
                          '负责人',
                          _simplePeopleText(const [
                            ('财务一', 'financeOwner1'),
                            ('财务二', 'financeOwner2'),
                          ]),
                          anchorKey: 'financeOwner1',
                          required: true,
                          fullWidth: true,
                        ),
                      ])
                    : _fieldGrid(wide, [
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
                            child: Text(
                              _rating,
                              style: TextStyle(
                                color: DunesColors.resolve(
                                  context,
                                  ProposalPalette.purpleDeep,
                                ),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                height: 1.8,
                              ),
                            ),
                          ),
                        ),
                      ], flat: true),
              ),
              _marketSheetGroup(
                label: '产品结算',
                description: '收入、成本、结算、账户与周转资金',
                // 简单行：结算、测算、成本、账户各一行（有子产品时也一样，按业务产品这一组）。
                child: _simpleView
                    ? _financeSimpleRows(wide)
                    : _financeProductContent(
                        wide,
                        owner: kProposalProductFinanceMain,
                      ),
              ),
            ],
          ),
        ),
        _moduleReview(
          key: _financeModuleReviewKey,
          title: '财务部负责人一 · 整板块复核',
          description: '仅当财务部负责人二逐条复核完成后才能通过。发现问题可直接驳回本板块。',
          keyName: 'financeCompleted',
          buttonLabel: '整个财务部板块复核通过',
          locked: !_allFinanceItemsReviewed,
          plain: true,
        ),
      ],
    );
  }

  bool get _allFinanceItemsReviewed =>
      _itemsReviewed('financeItem', _financeReviewKeys);

  Widget _financeProductContent(bool wide, {required String owner}) {
    final children = owner == kProposalProductFinanceChildren;
    final scope = proposalIntakeProductFinanceScope(_form, owner: owner);
    // 简单行：只有分主/子产品时才写组名；逐条复核开关只给财务部负责人二。
    final simple = _simpleView;
    final showGroupTitle = !simple || proposalIntakeHasChildProducts(_form);
    final showToolbar =
        !simple ||
        (_reviewEnabled('financeItem:revenue') &&
            _review['financeCompleted'] != true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGroupTitle) ...[
          _financeProductGroupTitle(
            children
                ? '$kProposalChildProductLabel合计'
                : '$kProposalMainProductLabel合计',
            children: children,
            description: children
                ? '本组独立核算，不与$kProposalMainProductLabel合并。'
                : '本组独立核算，不与其他产品组合并。',
          ),
          const SizedBox(height: 12),
        ],
        if (showToolbar) ...[
          _financeReviewToolbar(children: children),
          const SizedBox(height: 12),
        ],
        if (children)
          _childSettlementsBlock(wide)
        else ...[
          // 简单行：产品结算先收成一行「30 个产品 · 共 30 条结算」，点展开再看每个产品。
          if (simple) _skuSettleSimpleLine(),
          if (simple) _simpleRelatedProductsSummary(),
          if (!simple || _simpleSkuOpen) _skuSettlementsBlock(wide),
        ],
        if (!children)
          _mainFinanceDetails(wide)
        else ...[
          const SizedBox(height: 16),
          if (!simple)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                '收入默认按本组结算测算，填写人可改；其余自动测算。',
                style: kProposalCaptionStyle,
              ),
            ),
          LayoutBuilder(
            builder: (_, box) {
              final columns = ProposalLayout.isCompact(box.maxWidth) ? 1 : 2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _financeMetricSection(
                    owner: owner,
                    scope: scope,
                    columns: columns,
                  ),
                  const SizedBox(height: 10),
                  _financeSideGroup(
                    title: '供给侧',
                    child: _scopedFinanceRows(
                      _financeSupplyFields,
                      columns,
                      owner: owner,
                      scope: scope,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _financeSideGroup(
                    title: '渠道侧',
                    child: _scopedFinanceRows(
                      _financeChannelFields,
                      columns,
                      owner: owner,
                      scope: scope,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _scopedFinanceRows(
                    _financeAccountFields,
                    columns,
                    owner: owner,
                    scope: scope,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _scopedCostField(
            label: '项目成本',
            owner: owner,
            namesKey: 'costItems',
            amountsKey: 'costItemAmounts',
            totalKey: 'projectCost',
            options: _projectCostItemNames,
            writable: _canEditProjectCostChips,
          ),
          const SizedBox(height: 10),
          _scopedCostField(
            label: '业务成本',
            owner: owner,
            namesKey: 'businessCostItems',
            amountsKey: 'businessCostItemAmounts',
            totalKey: 'businessCost',
            options: widget.options.businessCostItems,
            writable: _canEditBusinessCost,
          ),
          const SizedBox(height: 10),
          _scopedCostField(
            label: '经营成本',
            owner: owner,
            namesKey: 'operatingCostItems',
            amountsKey: 'operatingCostItemAmounts',
            totalKey: 'operatingCost',
            options: kProposalOperatingCostItems,
          ),
          const SizedBox(height: 10),
          _scopedCostField(
            label: '税务成本',
            owner: owner,
            namesKey: 'taxCostItems',
            amountsKey: 'taxCostItemAmounts',
            totalKey: 'taxCost',
            options: kProposalTaxCostItems,
          ),
        ],
      ],
    );
  }

  Widget _financeMetricSection({
    required String owner,
    required Map<String, dynamic> scope,
    required int columns,
  }) {
    return _scopedFinanceRows(
      // 简单行：规模已在顶部测算里，不再重复。
      _simpleView
          ? [
              for (final field in _financeMetricFields)
                if (field.$1 != 'salesScale') field,
            ]
          : _financeMetricFields,
      columns,
      owner: owner,
      scope: scope,
    );
  }

  Widget _mainFinanceDetails(bool wide) {
    const owner = kProposalProductFinanceMain;
    final scope = proposalIntakeProductFinanceScope(_form, owner: owner);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        if (!_simpleView)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '销售规模取市场部填报。收入默认按结算测算，填写人可改；其余自动测算。',
              style: kProposalCaptionStyle,
            ),
          ),
        LayoutBuilder(
          builder: (_, box) {
            final columns = ProposalLayout.isCompact(box.maxWidth) ? 1 : 2;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _financeMetricSection(
                  owner: owner,
                  scope: scope,
                  columns: columns,
                ),
                const SizedBox(height: 10),
                // 简单行：供给侧、渠道侧、结算账户各合成一行。
                // 账户不能再走 _financeFieldRows：那里用 IntrinsicHeight 包只读值，
                // 只读值内部是 LayoutBuilder，测量高度会直接失败，上面的产品结算和
                // 收入行就会叠在同一条线上。
                if (_simpleView) ...[
                  _financeSideSimpleLine('供给侧', _financeSupplyFields),
                  _financeSideSimpleLine('渠道侧', _financeChannelFields),
                  _simpleLine(
                    '结算账户',
                    [
                      if (_text('generalBusinessAccount').trim().isNotEmpty)
                        '一：${_text('generalBusinessAccount').trim()}',
                      if (_text('prepaidAccount').trim().isNotEmpty)
                        '二：${_text('prepaidAccount').trim()}',
                    ].join(' · '),
                    anchorKey: 'generalBusinessAccount',
                    required: true,
                    fullWidth: true,
                    trailing: _mergedReviewToggle(const [
                      'financeItem:generalBusinessAccount',
                      'financeItem:prepaidAccount',
                    ]),
                  ),
                  _simpleLine(
                    '财务备注',
                    _text('financeRemark'),
                    anchorKey: 'financeRemark',
                    fullWidth: true,
                    trailing: _rowReviewToggle(
                      'financeItem:financeRemark',
                      '待复核',
                    ),
                  ),
                ] else ...[
                  _financeSideGroup(
                    title: '供给侧',
                    child: _financeFieldRows(_financeSupplyFields, columns),
                  ),
                  const SizedBox(height: 10),
                  _financeSideGroup(
                    title: '渠道侧',
                    child: _financeFieldRows(_financeChannelFields, columns),
                  ),
                  const SizedBox(height: 10),
                  _financeFieldRows(_financeAccountFields, columns),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _costSelectField(
          label: '项目成本',
          namesKey: 'costItems',
          amountsKey: 'costItemAmounts',
          totalKey: 'projectCost',
          options: _projectCostItemNames,
          catalog: widget.options.costItemOptions,
          addLabel: widget.options.costItemSource == 'asset' ? null : '新增成本项',
          reviewSection: 'financeItem:costItems',
          writable: _canEditProjectCostChips,
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
      ],
    );
  }

  Widget _scopedFinanceRows(
    List<(String, String)> fields,
    int columns, {
    required String owner,
    required Map<String, dynamic> scope,
  }) {
    return LayoutBuilder(
      builder: (_, box) {
        final itemWidth = columns == 1
            ? box.maxWidth
            : math.max(240.0, (box.maxWidth - 12) / 2);
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final field in fields)
              SizedBox(
                width: itemWidth,
                child: _scopedFinanceField(field, owner: owner, scope: scope),
              ),
          ],
        );
      },
    );
  }

  Widget _scopedFinanceField(
    (String, String) field, {
    required String owner,
    required Map<String, dynamic> scope,
  }) {
    final key = field.$1;
    final reviewSection = owner == kProposalProductFinanceChildren
        ? 'financeItem:children:$key'
        : 'financeItem:$key';
    final computed = _financeComputedMetric(key, formOverride: scope);
    final revenueEditable = key == 'revenue';
    final revenueManual = revenueEditable && proposalRevenueIsManual(scope);
    final current = revenueEditable
        ? (revenueManual
              ? _looseAmountText(scope['revenue'])
              : (computed?.display ?? ''))
        : (computed?.display ?? '${scope[key] ?? ''}'.trim());
    final enabled =
        (computed == null || revenueEditable) &&
        _fillEnabled(
          _canEditUnreviewedFinance,
          resetReview: 'financeCompleted',
          reviewSection: reviewSection,
        );
    final options = switch (key) {
      'supplySettleMode' ||
      'channelSettleMode' => _settleFieldOptions(key, current),
      'supplySettleCycle' ||
      'channelSettleCycle' => _settleFieldOptions(key, current),
      'rollback' => widget.options.rollbackOptions,
      _ => const <String>[],
    };
    final addLabel = _settleAddLabel(key);
    final Widget input;
    if ((computed != null && !revenueEditable) ||
        _showSelectedAsText ||
        !enabled) {
      input = _readonlySelectedText(_maskIfAccount(key, current));
    } else if (options.isNotEmpty || addLabel != null) {
      input = ProposalSelectField<String>(
        value: current.isEmpty ? null : current,
        title: field.$2,
        hint: options.isEmpty && addLabel == null ? '请先在管理端配置选项' : '请选择',
        searchable: true,
        addLabel: addLabel,
        onAdd: addLabel == null || !enabled
            ? null
            : () async {
                final added = await _promptAddedOption(addLabel);
                if (added == null || added.isEmpty) return;
                _writeProductFinanceValue(owner, key, added);
              },
        options: [
          for (final value in options)
            ProposalSelectOption(value: value, label: value),
        ],
        onSelected: (value) =>
            _writeProductFinanceValue(owner, key, value ?? ''),
      );
    } else {
      input = TextFormField(
        key: ValueKey(
          revenueEditable
              ? 'finance-revenue-${owner == kProposalProductFinanceChildren ? 'children' : 'main'}-${revenueManual ? 'manual' : 'auto-$current'}-${_row.id}-$_fieldEpoch'
              : 'finance-${owner == kProposalProductFinanceChildren ? 'children' : 'main'}-$key-${_row.id}-$_fieldEpoch',
        ),
        initialValue: current,
        keyboardType: revenueEditable
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        maxLines: _isFinanceLongTextKey(key) ? 3 : 1,
        onChanged: (value) => revenueEditable
            ? _writeRevenue(owner, value)
            : _writeProductFinanceValue(owner, key, value, rebuild: false),
        decoration: proposalInputDecoration(
          context: context,
          hint: revenueEditable ? '默认按结算测算，可改' : null,
        ),
      );
    }
    final fieldWidget = ProposalField(
      label: field.$2,
      required: computed == null,
      formula: computed?.formula ?? _financeMetricFormula(key),
      tone: proposalFieldTone(enabled: enabled),
      trailing: key == 'salesScale'
          ? null
          : _rowReviewToggle(reviewSection, _financeReviewLabel),
      child: input,
    );
    if (computed == null || (revenueEditable && enabled) || _protoForm) {
      return fieldWidget;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF3F6FA),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: fieldWidget,
    );
  }

  String _looseAmountText(Object? raw) {
    if (raw == null) return '';
    if (raw is num) return proposalFormatWan(raw.toDouble());
    return '$raw'.trim();
  }

  void _writeRevenue(String owner, String raw) {
    final finance = Map<String, dynamic>.from(
      proposalIntakeProductFinance(_form, owner: owner),
    );
    final text = raw.trim();
    if (text.isEmpty) {
      finance.remove('revenue');
      finance[kProposalRevenueManualKey] = false;
    } else {
      finance['revenue'] = text;
      finance[kProposalRevenueManualKey] = true;
    }
    final form = _withEstimatedFinanceCosts(
      proposalIntakeWriteProductFinance(_form, owner: owner, finance: finance),
    );
    final review = Map<String, dynamic>.from(_review)
      ..['financeCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
  }

  void _writeProductFinanceValue(
    String owner,
    String key,
    Object? value, {
    bool rebuild = true,
  }) {
    final finance = proposalIntakeProductFinance(_form, owner: owner)
      ..[key] = value;
    final form = _withEstimatedFinanceCosts(
      proposalIntakeWriteProductFinance(_form, owner: owner, finance: finance),
    );
    final review = Map<String, dynamic>.from(_review)
      ..['financeCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
  }

  Widget _scopedCostField({
    required String label,
    required String owner,
    required String namesKey,
    required String amountsKey,
    required String totalKey,
    required List<String> options,
    bool? writable,
  }) {
    if (label == '业务成本' && _businessCostSealed) {
      return ProposalField(
        label: '业务成本',
        tone: ProposalFieldTone.locked,
        child: Text(
          '已加密上锁，负责人二不可查看。由市场部负责人一在财务复核时填写。',
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text2),
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final finance = proposalIntakeProductFinance(_form, owner: owner);
    final names = finance[namesKey] is List
        ? [
            for (final value in finance[namesKey] as List)
              if ('$value'.trim().isNotEmpty) '$value'.trim(),
          ]
        : <String>[];
    final amounts = proposalCostAmountMap(finance[amountsKey]);
    final enabled = _fillEnabled(writable, resetReview: 'financeCompleted');
    if (label == '业务成本' && !_canEditBusinessCost && names.isEmpty) {
      return ProposalField(
        label: '业务成本',
        tone: ProposalFieldTone.locked,
        child: Text(
          '由市场部负责人一在财务复核时填写',
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text3),
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    void write(List<String> nextNames, Map<String, double> nextAmounts) {
      final next = Map<String, dynamic>.from(finance)
        ..[namesKey] = nextNames
        ..[amountsKey] = nextAmounts
        ..[totalKey] = proposalCostAmountTotal(nextAmounts);
      final form = _keepUnreviewed(
        proposalIntakeWriteProductFinance(_form, owner: owner, finance: next),
      );
      final review = Map<String, dynamic>.from(_review)
        ..['financeCompleted'] = false;
      setState(() {
        _markFormDirty();
        _row = _row.copyWith(
          form: form,
          review: review,
          status: _statusAfterEdit,
        );
      });
      _emitChanged(_row);
    }

    return _FullWidthField(
      child: ProposalField(
        label: label,
        trailing: _rowReviewToggle(
          owner == kProposalProductFinanceChildren
              ? 'financeItem:children:$namesKey'
              : 'financeItem:$namesKey',
          _financeReviewLabel,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProposalPills(
              options: [
                ...options,
                ...names.where((value) => !options.contains(value)),
              ],
              selected: names.toSet(),
              enabled: enabled,
              onToggle: (name) {
                final nextNames = namesKey == 'taxCostItems'
                    ? proposalToggleTaxCostItem(names, name)
                    : ([...names]..remove(name));
                if (namesKey != 'taxCostItems' && !names.contains(name)) {
                  nextNames.add(name);
                }
                final nextAmounts = Map<String, double>.from(amounts)
                  ..removeWhere((id, _) => !nextNames.contains(id));
                write(nextNames, nextAmounts);
              },
            ),
            for (final name in names)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextFormField(
                  key: ValueKey(
                    'finance-$owner-$amountsKey-$name-$_fieldEpoch',
                  ),
                  initialValue: (amounts[name] ?? 0) == 0
                      ? ''
                      : _textFromAmount(amounts[name]!),
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: proposalInputDecoration(
                    context: context,
                    hint: '$name 金额（万元）',
                  ),
                  onChanged: (value) {
                    final nextAmounts = Map<String, double>.from(amounts);
                    final amount = double.tryParse(value);
                    amount == null
                        ? nextAmounts.remove(name)
                        : nextAmounts[name] = amount;
                    write(names, nextAmounts);
                  },
                ),
              ),
            if (names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '合计 ${_money(proposalCostAmountTotal(amounts))}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text2),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _financeProductGroupTitle(
    String title, {
    required bool children,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: kProposalBlockTitleStyle),
          // 新样式不再写「本组独立核算…」这类说明，版面更整齐。
          if (!_protoForm && description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(description, style: kProposalCaptionStyle),
          ],
        ],
      ),
    );
  }

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
            title: '四流',
            tag: '只读全景',
            description: '自动串联市场、合同、科技和财务数据，字段变化后实时重算四流。',
            lighthouse: true,
          ),
        ),
        ProposalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final stacked = ProposalLayout.isCompact(box.maxWidth);
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '提案全链路',
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.text,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '上游板块是数据源，下方四流展示业务如何穿过各板块。',
                        style: kProposalCaptionStyle,
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
                  final stacked = ProposalLayout.isCompact(box.maxWidth);
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
                child: FlowLaneSection(
                  ctx: ctx,
                  compact: !wide,
                  onSelect: _jumpToFlowSource,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
      color: DunesColors.resolve(
        context,
        ProposalPalette.app,
        role: DunesColorRole.surface,
      ),
      border: Border.all(
        color: DunesColors.resolve(
          context,
          ProposalPalette.border,
          role: DunesColorRole.border,
        ),
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text3),
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? '待填写' : value,
          maxLines: expanded ? 4 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        Text(
          meta.isEmpty ? '—' : meta,
          maxLines: expanded ? 4 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text3),
            fontSize: 9,
            height: 1.35,
          ),
        ),
      ],
    ),
  );

  Widget _stepCard(String step, String title, String subtitle, Widget child) {
    // 原型简单行：不要「01 基础信息」这类小卡片标题，字段直接一行一条。
    if (_simpleView) return child;
    if (_isPurchase && !_protoForm) {
      return _purchaseStepCard(step, title, subtitle, child);
    }
    return ProposalCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.borderSoft,
                    role: DunesColorRole.border,
                  ),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.navTop),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: kProposalCaptionStyle),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(
              ProposalLayout.isCompact(MediaQuery.sizeOf(context).width)
                  ? 8
                  : 10,
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _purchaseStepCard(
    String step,
    String title,
    String subtitle,
    Widget child,
  ) {
    return ProposalCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  DunesColors.resolve(
                    context,
                    ProposalPalette.soft,
                    role: DunesColorRole.surface,
                  ),
                  DunesColors.resolve(
                    context,
                    ProposalPalette.app,
                    role: DunesColorRole.surface,
                  ),
                  DunesColors.resolve(
                    context,
                    ProposalPalette.soft,
                    role: DunesColorRole.surface,
                  ),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.borderSoft,
                    role: DunesColorRole.border,
                  ),
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final stacked = ProposalLayout.isTight(box.maxWidth);
                final badge = Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      Colors.white,
                      role: DunesColorRole.surface,
                    ),
                    border: Border.all(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.borderStrong,
                        role: DunesColorRole.border,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      step,
                      style: TextStyle(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.purpleMid,
                        ),
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
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.navTop,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(subtitle, style: kProposalCaptionStyle),
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
              ProposalLayout.isCompact(MediaQuery.sizeOf(context).width)
                  ? 8
                  : 10,
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
    final usePurchaseProposal =
        !_isPurchase &&
        prefix == 'purchase' &&
        proposalIntakeHasExistingPurchaseProposal(_form);
    final linkedPurchaseId = proposalIntakeLinkedPurchaseProposalId(_form);
    final fromProposal = usePurchaseProposal && linkedPurchaseId > 0;
    final grabSource = fromProposal ? '采购提案带入 · 可修改' : '合同抓取 · 可修改';
    return _stepCard(
      step,
      title,
      usePurchaseProposal
          ? '选中已通过的采购提案后，合同编号、名称、主体、源文件等内容会自动带出'
          : '已签可多选，字段取第一份 · 未签可上传多份',
      Column(
        children: [
          if (!_isPurchase && prefix == 'purchase') ...[
            _existingPurchaseProposalToggle(),
            const SizedBox(height: 8),
          ],
          if (usePurchaseProposal) ...[
            _approvedPurchaseSelector(),
            const SizedBox(height: 8),
          ],
          _fieldGrid(wide, [
            _dropdownField(
              '合同状态',
              '${prefix}Mode',
              const ['已签署合同', '未签署合同'],
              required: true,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Mode',
              reviewLabel: _financeReviewLabel,
              onSelected: fromProposal
                  ? (value) => _set('${prefix}Mode', value, resetReview: flag)
                  : (value) => _setContractMode(prefix, value),
            ),
            if (signed && !usePurchaseProposal) _contractSelector(prefix),
            _textField(
              '合同编号',
              '${prefix}No',
              required: signed,
              maxLines: 3,
              minLines: 1,
              source: fromProposal
                  ? grabSource
                  : signed
                  ? grabSource
                  : unsigned
                  ? '未签合同'
                  : null,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.No',
              reviewLabel: _financeReviewLabel,
            ),
            if (unsigned)
              _contractSourceFileField(prefix, allowUpload: true)
            else if (signed &&
                (_hasContractSourceFile(prefix) ||
                    proposalIntakeSelectedContractIds(
                      _form,
                      prefix,
                    ).isNotEmpty))
              _contractSourceFileField(prefix, allowUpload: false),
            _textField(
              '合同名称',
              '${prefix}Name',
              required: true,
              maxLines: 3,
              minLines: 1,
              source: grabSource,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Name',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '签署时间',
              '${prefix}SignDate',
              required: true,
              maxLines: 3,
              minLines: 1,
              source: grabSource,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.SignDate',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '我方签约主体',
              '${prefix}OurParty',
              required: true,
              maxLines: 3,
              minLines: 1,
              source: grabSource,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.OurParty',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '对方签约主体',
              '${prefix}Counterparty',
              required: true,
              maxLines: 3,
              minLines: 1,
              source: grabSource,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.Counterparty',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '有效期',
              '${prefix}ValidPeriod',
              required: true,
              maxLines: 3,
              minLines: 1,
              source: grabSource,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.ValidPeriod',
              reviewLabel: _financeReviewLabel,
            ),
            _textField(
              '核心条款',
              '${prefix}CoreTerms',
              maxLines: 3,
              required: true,
              source: grabSource,
              resetReview: flag,
              reviewSection: 'contractItem:$prefix.CoreTerms',
              reviewLabel: _financeReviewLabel,
            ),
            if (prefix == 'sales') ...[
              _dropdownField(
                '发票种类',
                'salesInvoiceType',
                kProposalInvoiceTypes,
                source: grabSource,
                resetReview: flag,
                reviewSection: 'contractItem:sales.InvoiceType',
                reviewLabel: _financeReviewLabel,
              ),
              _textField(
                '发票流',
                'salesInvoiceFlow',
                hint: '抓不到也可手填，例如开票时点、开票方与收票方',
                source: grabSource,
                maxLines: 3,
                minLines: 1,
                resetReview: flag,
                reviewSection: 'contractItem:sales.InvoiceFlow',
                reviewLabel: _financeReviewLabel,
              ),
            ],
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
                  ? '由你逐条复核，或直接整板块驳回。'
                  : '由财务部负责人二逐条复核，或直接整板块驳回。',
              if (pending.isNotEmpty && pending.length <= 2)
                '还差：${pending.join('、')}。'
              else if (pending.isNotEmpty)
                '还差 ${pending.length} 项。',
            ].join(),
            keyName: flag,
            buttonLabel: '合同字段审核通过',
            compact: true,
            plain: true,
            locked: !_itemsReviewed('contractItem', keys),
            progress:
                '财务部负责人二复核 ${_reviewedCount('contractItem', keys)}/${keys.length}',
          ),
        ],
      ),
    );
  }

  Widget _existingPurchaseProposalToggle() {
    final enabled = proposalIntakeHasExistingPurchaseProposal(_form);
    final locked = _showSelectedAsText || !_canEditContractExtras('purchase');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: locked
              ? null
              : () => _setHasExistingPurchaseProposal(!enabled),
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
                      : (value) =>
                            _setHasExistingPurchaseProposal(value == true),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '是否已有采购提案',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '勾选后搜索并选择已审核通过的采购提案，合同状态、编号、名称、主体、源文件等内容会自动带出，可再修改。不勾选则按下方合同归集 / 上传填写。',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _approvedPurchaseSelector() {
    final currentId = proposalIntakeLinkedPurchaseProposalId(_form);
    final selectedTitle = _text('linkedPurchaseProposalTitle');
    final selectedCode = _text('linkedPurchaseProposalCode');
    final locked = _showSelectedAsText || !_canEditContractExtras('purchase');
    return ProposalField(
      label: '已通过的采购提案',
      required: true,
      source: '从采购提案带入合同',
      tone: proposalFieldTone(enabled: !locked, source: '从采购提案带入合同'),
      child: locked
          ? _readonlySelectedText(
              [
                if (selectedCode.isNotEmpty) selectedCode,
                if (selectedTitle.isNotEmpty) selectedTitle,
              ].join(' · '),
            )
          : ProposalSelectField<int>(
              key: ValueKey('linked-purchase-$currentId-$_fieldEpoch'),
              value: currentId > 0 ? currentId : null,
              title: '选择已审核通过的采购提案',
              hint: '输入提案编号、名称或对方主体搜索',
              searchable: true,
              requireKeyword: true,
              remoteOptions: true,
              allowClear: false,
              onQueryChanged: _searchApprovedPurchases,
              options: [
                if (currentId > 0 &&
                    (selectedCode.isNotEmpty || selectedTitle.isNotEmpty))
                  ProposalSelectOption(
                    value: currentId,
                    label: selectedTitle.isEmpty
                        ? selectedCode
                        : selectedCode.isEmpty
                        ? selectedTitle
                        : '$selectedCode · $selectedTitle',
                    meta: _text('purchaseCounterparty'),
                  ),
                for (final hit in _purchaseProposalHits)
                  if (hit.id != currentId)
                    ProposalSelectOption(
                      value: hit.id,
                      label: hit.label,
                      meta: [
                        hit.purchaseNo,
                        hit.purchaseName,
                        hit.purchaseCounterparty,
                      ].where((item) => item.isNotEmpty).join(' · '),
                    ),
              ],
              onSelected: (id) {
                if (id == null) return;
                final hit = _purchaseProposalHits
                    .where((item) => item.id == id)
                    .firstOrNull;
                if (hit != null) {
                  unawaited(_applyApprovedPurchase(hit));
                }
              },
            ),
    );
  }

  Widget _contractSelector(String prefix) {
    final selectedIds = proposalIntakeSelectedContractIds(_form, prefix);
    final refs = proposalIntakeSelectedContractRefs(_form, prefix);
    final enabled = _canEditContractExtras(prefix);
    final source = '可多选，编号、主体等配置取第一份合同';
    final locked = _readValuesOnly(enabled);
    final opening = _openingContractPrefix == prefix;
    return ProposalField(
      label: '选择合同',
      required: true,
      source: source,
      tone: proposalFieldTone(enabled: enabled, source: source),
      trailing: refs.isEmpty
          ? null
          : TextButton.icon(
              onPressed: opening
                  ? null
                  : () => unawaited(_previewSelectedContract(prefix)),
              icon: Icon(
                opening
                    ? Icons.hourglass_top_rounded
                    : Icons.visibility_outlined,
                size: 16,
              ),
              label: Text(opening ? '打开中…' : '查看合同'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: DunesColors.resolve(
                  context,
                  ProposalPalette.purpleDeep,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refs.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < refs.length; i++)
                  InputChip(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.borderSoft,
                          role: DunesColorRole.border,
                        ),
                      ),
                    ),
                    avatar: i == 0
                        ? const Icon(Icons.flag_outlined, size: 14)
                        : null,
                    label: Text(
                      [
                        if (i == 0) '配置来源',
                        proposalIntakeContractRefLabel(refs[i]),
                      ].where((item) => item.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: opening
                        ? null
                        : () => unawaited(
                            _previewSelectedContract(prefix, refs[i]),
                          ),
                    onDeleted: locked
                        ? null
                        : () => unawaited(
                            _removeSelectedContract(
                              prefix,
                              _proposalContractRefId(refs[i]),
                            ),
                          ),
                  ),
              ],
            ),
            if (!locked) const SizedBox(height: 8),
          ],
          if (locked && refs.isEmpty)
            _readonlySelectedText('')
          else if (!locked)
            ProposalSelectField<int>(
              key: ValueKey(
                'contract-$prefix-${selectedIds.join('-')}-$_fieldEpoch',
              ),
              value: null,
              title: '选择合同归集中的合同（可多选）',
              hint: selectedIds.isEmpty ? '输入合同编号、名称或对方主体搜索' : '继续搜索添加合同',
              searchable: true,
              requireKeyword: true,
              remoteOptions: true,
              allowClear: false,
              onQueryChanged: _searchContracts,
              options: [
                for (final contract in _contractHits)
                  if (!selectedIds.contains(contract.id))
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
              onSelected: !enabled
                  ? null
                  : (id) {
                      if (id != null) {
                        unawaited(_applyContract(prefix, id));
                      }
                    },
            ),
        ],
      ),
    );
  }

  int _proposalContractRefId(Map<String, dynamic> ref) =>
      (ref['id'] as num?)?.toInt() ?? int.tryParse('${ref['id'] ?? ''}') ?? 0;

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
    if (!_canEditContractExtras(prefix)) return;
    final selectedIds = proposalIntakeSelectedContractIds(_form, prefix);
    if (selectedIds.contains(id)) {
      showProposalCenterToast(context, '该合同已选择');
      return;
    }
    try {
      final detail = await widget.service.fetchContractDetail(id);
      final appending = selectedIds.isNotEmpty;
      final form = appending
          ? proposalIntakeAppendSelectedContract(
              _form,
              prefix: prefix,
              detail: detail,
            )
          : (Map<String, dynamic>.from(_form)..addAll(
              proposalIntakePatchFromContract(prefix: prefix, detail: detail),
            ));
      if (!mounted) return;
      setState(() {
        _markFormDirty();
        _fieldEpoch++;
        _row = _row.copyWith(
          form: appending
              ? form
              : proposalIntakeRememberContractSnapshot(
                  form: form,
                  prefix: prefix,
                ),
          review: appending
              ? _review
              : proposalIntakeClearContractReview(_review, prefix: prefix),
          status: _statusAfterEdit,
        );
      });
      _emitChanged(_row);
      showProposalCenterToast(
        context,
        appending ? '已添加合同，配置内容仍以第一份为准' : '已从合同归集带入可修改字段',
      );
    } catch (error) {
      widget.onError(friendlyErrorText(error));
    }
  }

  Future<void> _removeSelectedContract(String prefix, int id) async {
    if (!_canEditContractExtras(prefix) || id <= 0) return;
    final ids = proposalIntakeSelectedContractIds(_form, prefix);
    if (!ids.contains(id)) return;
    final refs = proposalIntakeSelectedContractRefs(_form, prefix);
    final remainingIds = [
      for (final item in ids)
        if (item != id) item,
    ];
    final remainingRefs = [
      for (final ref in refs)
        if (_proposalContractRefId(ref) != id) ref,
    ];
    if (remainingIds.isEmpty) {
      final form = Map<String, dynamic>.from(_form)
        ..addAll(proposalIntakeResetContractFields(prefix))
        ..['${prefix}Mode'] = _text('${prefix}Mode');
      setState(() {
        _markFormDirty();
        _fieldEpoch++;
        _row = _row.copyWith(
          form: form,
          review: proposalIntakeClearContractReview(_review, prefix: prefix),
          status: _statusAfterEdit,
        );
      });
      _emitChanged(_row);
      return;
    }
    final removingFirst = ids.first == id;
    if (!removingFirst) {
      final form = proposalIntakeSyncSelectedContractFiles(
        proposalIntakeSetSelectedContracts(
          _form,
          prefix: prefix,
          ids: remainingIds,
          refs: remainingRefs,
        ),
        prefix: prefix,
      );
      setState(() {
        _markFormDirty();
        _fieldEpoch++;
        _row = _row.copyWith(form: form, status: _statusAfterEdit);
      });
      _emitChanged(_row);
      return;
    }
    try {
      final detail = await widget.service.fetchContractDetail(
        remainingIds.first,
      );
      var form = Map<String, dynamic>.from(_form)
        ..addAll(
          proposalIntakePatchFromContract(prefix: prefix, detail: detail),
        );
      final firstRef = proposalIntakeContractRefFromDetail(detail);
      final firstId = _proposalContractRefId(firstRef);
      form = proposalIntakeSetSelectedContracts(
        form,
        prefix: prefix,
        ids: remainingIds,
        refs: [
          firstRef,
          for (final ref in remainingRefs)
            if (_proposalContractRefId(ref) != firstId) ref,
        ],
      );
      form = proposalIntakeSyncSelectedContractFiles(form, prefix: prefix);
      if (!mounted) return;
      setState(() {
        _markFormDirty();
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
      _emitChanged(_row);
      showProposalCenterToast(context, '已改用下一份合同带出配置内容');
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
    // keep-alive 切走后提案仍全屏布局；不卸掉 DropTarget 会按屏幕坐标抢走 IM 拖放。
    if (!_supportsDesktopDrop || !enabled || !desktopDropLive(context)) {
      return child;
    }
    return DropTarget(
      onDragEntered: (_) {
        if (!desktopDropLive(context)) return;
        if (!dragging) onHover(true);
      },
      onDragExited: (_) => onHover(false),
      onDragDone: (detail) {
        if (!desktopDropLive(context)) return;
        unawaited(onDrop(detail));
      },
      child: child,
    );
  }

  Map<String, dynamic> _reviewAfterProductEdit(String resetReview) {
    final review = Map<String, dynamic>.from(_review)..[resetReview] = false;
    if (resetReview != 'technologyCompleted') return review;
    final items = review['technologyItems'];
    if (items is Map) {
      review['technologyItems'] = Map<String, dynamic>.from(items)
        ..remove(kProposalSkuProductsReviewKey);
    }
    return review;
  }

  void _writeSkuDetails(
    List<ProposalSkuDetailRow> rows, {
    String resetReview = 'technologyCompleted',
    bool? isExistingBuilt,
    bool rebuild = true,
  }) {
    var form = Map<String, dynamic>.from(_form)
      ..['skuDetails'] = [for (final row in rows) row.toJson()]
      ..['rollback'] = rows.isEmpty
          ? kProposalDefaultRollback
          : proposalIntakeSkuRollbackValue(rows.first, form: _form);
    form = proposalIntakeSyncChildProductMeta(form);
    if (isExistingBuilt != null) form['isExistingBuilt'] = isExistingBuilt;
    form = _withEstimatedFinanceCosts(form);
    final review = _reviewAfterProductEdit(resetReview);
    _markFormDirty();
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (rebuild && mounted) setState(() {});
    _emitChanged(_row);
  }

  ProposalSkuDetailRow _newSkuDetailRow({bool? existing}) =>
      ProposalSkuDetailRow(
        id: proposalIntakeNewSkuId(),
        existingBuilt: (existing ?? proposalIntakeIsExistingBuilt(_form))
            ? '是'
            : '否',
        rollback: kProposalDefaultRollback,
        syncSourceRef: proposalIntakeFormSyncSourceRef(_form),
        settlements: const [],
      );

  ProposalSkuDetailRow _newChildProductRow({bool? existing}) =>
      ProposalSkuDetailRow(
        id: proposalIntakeNewChildSkuId(),
        existingBuilt: (existing ?? proposalIntakeIsChildExistingBuilt(_form))
            ? '是'
            : '否',
        rollback: kProposalDefaultRollback,
        syncSourceRef: proposalIntakeFormSyncSourceRef(_form),
        settlements: const [],
      );

  String get _resolvedChildProductId {
    final children = proposalIntakeChildProducts(_form);
    if (children.isEmpty) return '';
    if (children.any((item) => item.id == _activeChildProductId)) {
      return _activeChildProductId;
    }
    return children.first.id;
  }

  ProposalSkuDetailRow? get _activeChildProduct {
    final id = _resolvedChildProductId;
    if (id.isEmpty) return null;
    return proposalIntakeChildProducts(
      _form,
    ).where((item) => item.id == id).firstOrNull;
  }

  void _selectChildProduct(String id) {
    if (_activeChildProductId == id) return;
    setState(() => _activeChildProductId = id);
  }

  void _writeChildProducts(
    List<ProposalSkuDetailRow> rows, {
    String resetReview = 'technologyCompleted',
    bool? isExistingBuilt,
    Map<String, int>? childQuantities,
    bool rebuild = true,
  }) {
    var form = Map<String, dynamic>.from(_form)
      ..['childProducts'] = [for (final row in rows) row.toJson()];
    if (isExistingBuilt != null) form['childIsExistingBuilt'] = isExistingBuilt;
    if (childQuantities != null) {
      final benefit = form['benefitProduct'] is Map
          ? Map<String, dynamic>.from(form['benefitProduct'] as Map)
          : <String, dynamic>{};
      benefit['skuQuantities'] = childQuantities;
      form['benefitProduct'] = benefit;
    }
    form = proposalIntakeSyncChildProductMeta(form);
    form = _withEstimatedFinanceCosts(form);
    final review = _reviewAfterProductEdit(resetReview);
    _markFormDirty();
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (rebuild && mounted) setState(() {});
    _emitChanged(_row);
  }

  Future<void> _addChildProduct({String? parentSkuId}) async {
    if (!_canEditProducts) return;
    final parent = (parentSkuId ?? '').trim();
    if (parent.isEmpty ||
        !proposalIntakeSkuDetails(_form).any((row) => row.id == parent)) {
      widget.onError('请先新增$kProposalMainProductLabel，并选择类型为权益');
      return;
    }
    await _openSkuProductDialog(child: true, parentSkuId: parent);
  }

  bool get _clipboardIsChild {
    final row = _skuSettingsClipboard;
    if (row == null) return false;
    return row.parentSkuId.isNotEmpty || row.resolvedCouponKind.isNotEmpty;
  }

  void _pasteSkuProductOnto(
    ProposalSkuDetailRow target, {
    required bool child,
  }) {
    final source = child ? _linkedProductClipboard : _businessProductClipboard;
    if (source == null || !_canEditProducts) return;
    var next = proposalIntakeCloneSkuProduct(
      source,
      id: target.id,
      parentSkuId: child ? target.parentSkuId : '',
    );
    if (!child) {
      next = next.copyWith(
        productName: proposalIntakeCopiedProductName(next.productName, [
          for (final row in proposalIntakeSkuDetails(_form))
            if (row.id != target.id) row,
        ]),
      );
      _patchSkuDetail(target.id, (_) => next);
      _showProductClipboardMessage(
        source.id == target.id ? '请粘贴到另一条业务产品' : '已粘贴到当前业务产品',
      );
      return;
    }
    final quantities = Map<String, int>.from(
      proposalIntakeBenefitProduct(_form).skuQuantities,
    )..[target.id] = proposalIntakeChildProductQuantity(_form, source.id);
    if (quantities[target.id]! < 1) quantities[target.id] = 1;
    _writeChildProducts([
      for (final row in proposalIntakeChildProducts(_form))
        if (row.id == target.id) next else row,
    ], childQuantities: quantities);
    _showProductClipboardMessage(
      source.id == target.id ? '请粘贴到另一条关联产品' : '已粘贴到当前关联产品',
    );
  }

  void _showProductClipboardMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _pasteSkuProductAsNew({required bool child}) {
    final source = _skuSettingsClipboard;
    if (source == null || !_canEditProducts) return;
    if (child) {
      final mains = proposalIntakeSkuDetails(_form);
      if (mains.isEmpty) {
        widget.onError('请先新增$kProposalMainProductLabel');
        return;
      }
      final parentId = mains.any((row) => row.id == source.parentSkuId)
          ? source.parentSkuId
          : mains.first.id;
      final next = proposalIntakeCloneSkuProduct(
        source,
        id: proposalIntakeNewChildSkuId(),
        parentSkuId: parentId,
      );
      final rows = proposalIntakeChildProducts(_form);
      final quantities = Map<String, int>.from(
        proposalIntakeBenefitProduct(_form).skuQuantities,
      )..[next.id] = proposalIntakeChildProductQuantity(_form, source.id);
      if (quantities[next.id]! < 1) quantities[next.id] = 1;
      _activeChildProductId = next.id;
      _writeChildProducts([...rows, next], childQuantities: quantities);
      return;
    }
    final rows = proposalIntakeSkuDetails(_form);
    final next = proposalIntakeCloneSkuProduct(
      source,
      id: proposalIntakeNewSkuId(),
      productName: proposalIntakeCopiedProductName(source.productName, rows),
      parentSkuId: '',
    );
    _writeSkuDetails([...rows, next]);
  }

  void _patchChildProduct(
    String id,
    ProposalSkuDetailRow Function(ProposalSkuDetailRow row) update, {
    bool rebuild = true,
  }) {
    _writeChildProducts([
      for (final row in proposalIntakeChildProducts(_form))
        if (row.id == id) update(row) else row,
    ], rebuild: rebuild);
  }

  Future<bool> _confirmRemove(String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认移除'),
        content: Text('确定移除「$label」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmRemoveLinked(ProposalSkuDetailRow row) async {
    final name = row.displayName.trim().isEmpty
        ? '关联产品'
        : row.displayName.trim();
    if (!await _confirmRemove(name)) return;
    _removeChildProduct(row.id);
    _selectedProductIds.remove(row.id);
  }

  Future<void> _confirmRemoveProduct(ProposalSkuDetailRow row) async {
    final name = row.displayName.trim().isEmpty
        ? kProposalMainProductLabel
        : row.displayName.trim();
    if (!await _confirmRemove(name)) return;
    _removeSkuDetail(row.id);
    _selectedProductIds.remove(row.id);
  }

  Set<String> get _liveSelectedProductIds {
    final ids = {
      for (final row in proposalIntakeSkuDetails(_form)) row.id,
      for (final row in proposalIntakeChildProducts(_form)) row.id,
    };
    return _selectedProductIds.intersection(ids);
  }

  void _toggleProductSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.add(id);
      } else {
        _selectedProductIds.remove(id);
      }
    });
  }

  void _toggleSelectAllProducts() {
    final mains = [for (final row in proposalIntakeSkuDetails(_form)) row.id];
    final selected = _liveSelectedProductIds;
    final allMainsSelected = mains.isNotEmpty && mains.every(selected.contains);
    setState(() {
      if (allMainsSelected) {
        _selectedProductIds.removeAll(mains);
      } else {
        _selectedProductIds.addAll(mains);
      }
    });
  }

  Future<void> _confirmRemoveSelectedProducts() async {
    final ids = _liveSelectedProductIds;
    if (ids.isEmpty) return;
    final mainCount = proposalIntakeSkuDetails(
      _form,
    ).where((row) => ids.contains(row.id)).length;
    final childCount = ids.length - mainCount;
    final parts = <String>[
      if (mainCount > 0) '$mainCount 个业务产品',
      if (childCount > 0) '$childCount 个关联产品',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除所选产品'),
        content: Text('确定删除已选的 ${parts.join('、')}吗？业务产品下的关联产品会一并删除，删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.resolve(
                ctx,
                ProposalPalette.coral,
                role: DunesColorRole.surface,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _removeSelectedProducts(ids);
    setState(() => _selectedProductIds.removeAll(ids));
  }

  void _removeSelectedProducts(Set<String> ids) {
    if (!_canEditProducts || ids.isEmpty) return;
    final mains = proposalIntakeSkuDetails(_form);
    final mainIds = {
      for (final row in mains)
        if (ids.contains(row.id)) row.id,
    };
    if (mainIds.isNotEmpty) {
      _writeSkuDetails([
        for (final row in mains)
          if (!mainIds.contains(row.id)) row,
      ], rebuild: false);
    }
    final quantities = Map<String, int>.from(
      proposalIntakeBenefitProduct(_form).skuQuantities,
    );
    final kept = <ProposalSkuDetailRow>[];
    for (final row in proposalIntakeChildProducts(_form)) {
      if (mainIds.contains(row.parentSkuId) || ids.contains(row.id)) {
        quantities.remove(row.id);
      } else {
        kept.add(row);
      }
    }
    _writeChildProducts(kept, childQuantities: quantities);
    if (_activeChildProductId.isNotEmpty &&
        !kept.any((row) => row.id == _activeChildProductId)) {
      _activeChildProductId = '';
    }
  }

  Widget? _productSelectBox(String id) {
    if (!_productMultiSelect || !_canEditProducts) return null;
    return SizedBox(
      width: 28,
      height: 28,
      child: Checkbox(
        value: _selectedProductIds.contains(id),
        activeColor: DunesColors.resolve(context, ProposalPalette.purple),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (value) => _toggleProductSelected(id, value == true),
      ),
    );
  }

  void _removeChildProduct(String id) {
    if (!_canEditProducts) return;
    _writeChildProducts([
      for (final row in proposalIntakeChildProducts(_form))
        if (row.id != id) row,
    ]);
    if (_activeChildProductId == id) _activeChildProductId = '';
  }

  void _setChildExistingBuiltEnabled(bool enabled) {
    if (!_canEditProducts) return;
    final label = enabled ? '是' : '否';
    var skus = [
      for (final row in proposalIntakeChildProducts(_form))
        row.copyWith(
          existingBuilt: label,
          assetProduct: enabled ? row.assetProduct : null,
        ),
    ];
    if (enabled && skus.isEmpty) {
      skus = [_newChildProductRow(existing: true)];
      _activeChildProductId = skus.first.id;
    }
    _writeChildProducts(skus, isExistingBuilt: enabled);
  }

  void _setChildProductQuantity(String childId, String value) {
    if (!_canEditProducts) return;
    final quantity = int.tryParse(value.trim()) ?? 1;
    final quantities = Map<String, int>.from(
      proposalIntakeBenefitProduct(_form).skuQuantities,
    )..[childId] = quantity < 1 ? 1 : quantity;
    _writeChildProducts(
      proposalIntakeChildProducts(_form),
      childQuantities: quantities,
      rebuild: false,
    );
  }

  void _setChildProductParent(String childId, String? parentSkuId) {
    if (!_canEditProducts) return;
    _patchChildProduct(
      childId,
      (current) => current.copyWith(parentSkuId: parentSkuId ?? ''),
    );
  }

  void _jumpToSkuSettlement(ProposalSkuDetailRow sku, {required bool child}) {
    unawaited(_openSkuSettleDialog(sku: sku, child: child));
  }

  Future<void> _openSkuSettleDialog({
    required ProposalSkuDetailRow sku,
    required bool child,
  }) async {
    if (child && _activeChildProductId != sku.id) {
      setState(() => _activeChildProductId = sku.id);
    }
    final enabled = _canEditSkuSettlements;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final current =
                (child
                        ? proposalIntakeChildProducts(_form)
                        : proposalIntakeSkuDetails(_form))
                    .where((row) => row.id == sku.id)
                    .firstOrNull;
            if (current == null) {
              return AlertDialog(
                title: const Text('结算'),
                content: const Text('产品已删除'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                ],
              );
            }
            final titleBits = [
              if (current.productName.trim().isNotEmpty)
                current.productName.trim(),
              if (current.faceValue.trim().isNotEmpty)
                '面值 ${current.faceValue.trim()}',
            ].join(' · ');
            final wide = !ProposalLayout.isCompact(
              MediaQuery.sizeOf(ctx).width,
            );
            void refresh() => setDialogState(() {});
            return AlertDialog(
              title: Text(
                '${child ? '关联产品' : proposalIntakeProductKindLabel(child: false)}结算${titleBits.isEmpty ? '' : ' · $titleBits'}',
              ),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: _skuSettleProductCard(
                    skuId: current.id,
                    childProduct: child,
                    product: current,
                    title: titleBits,
                    emptyTitle: child ? '未选择现金券或满减券' : '未填写产品名称',
                    reviewPrefix: 'skuSettle',
                    settlements: proposalIntakeSkuSettlements(current),
                    wide: wide,
                    enabled: enabled,
                    syncSource: _skuSyncSource(current),
                    productSource: 'CHANNEL',
                    compact: false,
                    showItemReview: false,
                    onAdd: () {
                      _addSkuSettle(current.id);
                      refresh();
                    },
                    onAddKind: (kind) {
                      _addSkuSettle(current.id, kind: kind);
                      refresh();
                    },
                    onRemove: (settleId) {
                      _removeSkuSettle(current.id, settleId);
                      refresh();
                    },
                    onPatch: (settleId, terms) {
                      _patchSkuSettle(current.id, settleId, terms);
                      refresh();
                    },
                    onReplace: (settlements) {
                      _writeSkuSettlements(current.id, settlements);
                      refresh();
                    },
                    onClipboardChanged: refresh,
                    includeScale: false,
                    scaleOnly: false,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _jumpToSkuProduct(ProposalSkuDetailRow sku, {required bool child}) {
    final anchor = child ? 'childDetail:${sku.id}' : 'skuDetail:${sku.id}';
    void jump() {
      final key = _fieldAnchorKeys[anchor];
      if (key != null && _jumpToKey(key, ProposalIntakeNavSection.tech)) {
        return;
      }
      _jumpToKey(_techKey, ProposalIntakeNavSection.tech);
    }

    final productIndex = proposalIntakeSkuDetails(
      _form,
    ).indexWhere((item) => item.id == sku.id);
    final hidden = !child && productIndex >= _businessProductVisible;
    if ((child && _activeChildProductId != sku.id) || hidden) {
      setState(() {
        if (child) _activeChildProductId = sku.id;
        if (hidden) _businessProductVisible = productIndex + 1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) jump();
      });
      return;
    }
    jump();
  }

  List<ProposalSkuSettleRow> _pasteSkuSettlements(
    List<ProposalSkuSettleRow> current,
  ) {
    final copied = _skuSettlementsClipboard;
    if (copied == null || copied.isEmpty) return current;
    return [
      for (var i = 0; i < copied.length; i++)
        ProposalSkuSettleRow(
          id: i < current.length
              ? current[i].id
              : proposalIntakeNewSkuSettleId(),
          kind: copied[i].kind,
          terms: copied[i].terms,
        ),
    ];
  }

  void _writeChildSettlements(
    String skuId,
    List<ProposalSkuSettleRow> settlements, {
    bool rebuild = true,
  }) {
    if (!_canEditSkuSettlements) return;
    _writeChildProducts(
      [
        for (final row in proposalIntakeChildProducts(_form))
          if (row.id == skuId) row.copyWith(settlements: settlements) else row,
      ],
      resetReview: 'financeCompleted',
      rebuild: rebuild,
    );
  }

  void _setChildTech(String key, Object? value, {bool rebuild = true}) {
    if (_moduleReviewed('technologyCompleted') ||
        _itemReviewed('technologyItem:$kProposalChildTechReviewPrefix$key')) {
      return;
    }
    final snap = proposalIntakeChildTechnology(_form)..[key] = value;
    var form = Map<String, dynamic>.from(_form)..['childTechnology'] = snap;
    form = _keepUnreviewed(form);
    final review = Map<String, dynamic>.from(_review)
      ..['technologyCompleted'] = false;
    if (key == 'financeInterfaces') {
      review['financeInterfaceCompleted'] = false;
    }
    final items = review['technologyItems'];
    if (items is Map) {
      final nextItems = Map<String, dynamic>.from(items)
        ..remove('$kProposalChildTechReviewPrefix$key');
      review['technologyItems'] = nextItems;
    }
    _markFormDirty();
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (rebuild && mounted) setState(() {});
    _emitChanged(_row);
  }

  void _toggleChildTechList(String key, String value, {bool single = false}) {
    final current = proposalIntakeChildTechnology(_form)[key];
    final values = current is List
        ? current.map((item) => '$item').toSet()
        : <String>{};
    if (single) {
      final next = (values.length == 1 && values.contains(value))
          ? <String>[]
          : <String>[value];
      _setChildTech(key, next);
      return;
    }
    values.contains(value) ? values.remove(value) : values.add(value);
    _setChildTech(key, values.toList());
  }

  void _setExistingBuiltEnabled(bool enabled) {
    if (!_canEditProducts) return;
    final label = enabled ? '是' : '否';
    var skus = [
      for (final row in proposalIntakeSkuDetails(_form))
        row.copyWith(
          existingBuilt: label,
          assetProduct: enabled ? row.assetProduct : null,
        ),
    ];
    if (enabled && skus.isEmpty) {
      skus = [_newSkuDetailRow(existing: true)];
    }
    _writeSkuDetails(skus, isExistingBuilt: enabled);
  }

  Future<void> _addSkuDetail() async {
    if (!_canEditProducts) return;
    await _openSkuProductDialog(child: false);
  }

  Future<void> _duplicateBusinessProduct(ProposalSkuDetailRow source) async {
    if (!_canEditProducts) return;
    final count = await _promptProductCopyCount(source);
    if (count == null || !mounted || !_canEditProducts) return;
    final copied = proposalIntakeCopyBusinessProducts(
      source: source,
      count: count,
      mains: proposalIntakeSkuDetails(_form),
      children: proposalIntakeChildProducts(_form),
      quantities: proposalIntakeBenefitProduct(_form).skuQuantities,
      idSeed: DateTime.now().microsecondsSinceEpoch,
    );
    var form = Map<String, dynamic>.from(_form)
      ..['skuDetails'] = [for (final row in copied.mains) row.toJson()]
      ..['childProducts'] = [for (final row in copied.children) row.toJson()]
      ..['rollback'] = copied.mains.isEmpty
          ? kProposalDefaultRollback
          : proposalIntakeSkuRollbackValue(copied.mains.first, form: _form);
    final benefit = form['benefitProduct'] is Map
        ? Map<String, dynamic>.from(form['benefitProduct'] as Map)
        : <String, dynamic>{};
    benefit['skuQuantities'] = copied.quantities;
    form['benefitProduct'] = benefit;
    form = proposalIntakeSyncChildProductMeta(form);
    form = _withEstimatedFinanceCosts(form);
    final review = _reviewAfterProductEdit('technologyCompleted');
    setState(() {
      _markFormDirty();
      _businessProductVisible = copied.mains.length;
      _financeSettleVisible = copied.mains.length;
      _row = _row.copyWith(
        status: _statusAfterEdit,
        form: form,
        review: review,
      );
    });
    _emitChanged(_row);
    if (!mounted) return;
    showProposalCenterToast(context, '已复制新增 $count 条业务产品');
  }

  Future<int?> _promptProductCopyCount(ProposalSkuDetailRow source) async {
    final controller = TextEditingController(text: '1');
    final name = source.displayName.trim().isEmpty
        ? '当前业务产品'
        : source.displayName.trim();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('复制新增'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将复制「$name」，关联产品和结算会一起新增。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: proposalInputDecoration(
                context: context,
                hint: '新增数量',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) return null;
    final count = int.tryParse(raw) ?? 0;
    if (count < 1) {
      widget.onError('请填写大于 0 的数量');
      return null;
    }
    if (count > 50) {
      widget.onError('一次最多复制 50 条');
      return null;
    }
    return count;
  }

  Future<void> _openSkuProductDialog({
    required bool child,
    ProposalSkuDetailRow? existing,
    String parentSkuId = '',
  }) async {
    if (!_canEditProducts && existing == null) return;
    final mains = proposalIntakeSkuDetails(_form);
    final seed =
        existing ?? (child ? _newChildProductRow() : _newSkuDetailRow());
    final boundParent = child
        ? (existing?.parentSkuId.trim().isNotEmpty == true
              ? existing!.parentSkuId
              : parentSkuId)
        : '';
    final initial = seed.copyWith(
      rollback: proposalIntakeSkuRollbackValue(seed, form: _form),
      parentSkuId: child ? boundParent : seed.parentSkuId,
    );
    final result = await showDialog<_SkuProductDraft>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SkuProductEditorDialog(
        childProduct: child,
        creating: existing == null,
        initial: initial,
        quantity: child
            ? proposalIntakeChildProductQuantity(_form, initial.id)
            : 1,
        mainProducts: mains,
        rollbackOptions: widget.options.rollbackOptions,
        readOnly: !_canEditProducts,
        proposalTitle: _row.title,
        initialLinked: child
            ? const []
            : [
                for (final item in proposalIntakeChildProducts(_form))
                  if (item.parentSkuId == initial.id)
                    _SkuProductDraft(
                      row: item,
                      quantity: proposalIntakeChildProductQuantity(
                        _form,
                        item.id,
                      ),
                    ),
              ],
      ),
    );
    if (result == null || !mounted || !_canEditProducts) return;
    if (child && _childCouponInUse(result.row)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同一业务产品下类型和面值不能重复')));
      return;
    }
    if (child) {
      final rows = proposalIntakeChildProducts(_form);
      final quantities = Map<String, int>.from(
        proposalIntakeBenefitProduct(_form).skuQuantities,
      )..[result.row.id] = result.quantity;
      if (existing == null) {
        _activeChildProductId = result.row.id;
        _writeChildProducts([...rows, result.row], childQuantities: quantities);
      } else {
        _writeChildProducts([
          for (final row in rows)
            if (row.id == result.row.id) result.row else row,
        ], childQuantities: quantities);
      }
      return;
    }
    final rows = proposalIntakeSkuDetails(_form);
    if (existing == null) {
      if (rows.length >= _productFoldPreview) {
        _businessProductVisible = rows.length + 1;
        _financeSettleVisible = rows.length + 1;
      }
      _writeSkuDetails([...rows, result.row], rebuild: false);
    } else {
      _patchSkuDetail(existing.id, (_) => result.row, rebuild: false);
    }
    final children = proposalIntakeChildProducts(_form);
    final quantities = Map<String, int>.from(
      proposalIntakeBenefitProduct(_form).skuQuantities,
    );
    final kept = [
      for (final row in children)
        if (row.parentSkuId != result.row.id) row,
    ];
    final next = <ProposalSkuDetailRow>[...kept];
    for (final item in result.linked) {
      final row = item.row.copyWith(parentSkuId: result.row.id);
      if (_childCouponInUse(row) &&
          !children.any((item) => item.id == row.id)) {
        continue;
      }
      quantities[row.id] = item.quantity;
      next.add(row);
    }
    for (final row in children) {
      if (row.parentSkuId == result.row.id &&
          !next.any((item) => item.id == row.id)) {
        quantities.remove(row.id);
      }
    }
    _writeChildProducts(next, childQuantities: quantities);
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

  void _patchSellableSku(
    String id,
    ProposalSkuDetailRow Function(ProposalSkuDetailRow row) update, {
    bool rebuild = true,
  }) {
    if (proposalIntakeChildProducts(_form).any((row) => row.id == id)) {
      _patchChildProduct(id, update, rebuild: rebuild);
      return;
    }
    _patchSkuDetail(id, update, rebuild: rebuild);
  }

  void _removeSkuDetail(String id) {
    if (!_canEditProducts) return;
    _writeSkuDetails([
      for (final row in proposalIntakeSkuDetails(_form))
        if (row.id != id) row,
    ], rebuild: false);
    final quantities = Map<String, int>.from(
      proposalIntakeBenefitProduct(_form).skuQuantities,
    );
    final children = [
      for (final row in proposalIntakeChildProducts(_form))
        if (row.parentSkuId == id) null else row,
    ].whereType<ProposalSkuDetailRow>().toList();
    for (final row in proposalIntakeChildProducts(_form)) {
      if (row.parentSkuId == id) quantities.remove(row.id);
    }
    _writeChildProducts(children, childQuantities: quantities);
  }

  void _writeSkuSettlements(
    String skuId,
    List<ProposalSkuSettleRow> settlements, {
    bool rebuild = true,
  }) {
    if (!_canEditSkuSettlements) return;
    if (_isChildSkuId(skuId)) {
      _writeChildSettlements(skuId, settlements, rebuild: rebuild);
      return;
    }
    _writeSkuDetails(
      [
        for (final row in proposalIntakeSkuDetails(_form))
          if (row.id == skuId) row.copyWith(settlements: settlements) else row,
      ],
      resetReview: 'financeCompleted',
      rebuild: rebuild,
    );
  }

  bool _isChildSkuId(String id) =>
      proposalIntakeChildProducts(_form).any((item) => item.id == id);

  ProposalSkuDetailRow? _sellableSkuById(String id) {
    return proposalIntakeAllSellableSkus(
      _form,
    ).where((item) => item.id == id).firstOrNull;
  }

  void _addSkuSettle(
    String skuId, {
    String kind = kProposalSkuSettleKindIncome,
  }) {
    if (!_canEditSkuSettlements) return;
    final row = _sellableSkuById(skuId);
    if (row == null) return;
    _writeSkuSettlements(skuId, [
      ...proposalIntakeSkuSettlements(row),
      ProposalSkuSettleRow(
        id: proposalIntakeNewSkuSettleId(),
        kind: proposalIntakeNormalizeSkuSettleKind(kind),
        terms: ProposalFinanceSettleTerms(channelRef: row.channelRef),
      ),
    ]);
  }

  void _removeSkuSettle(String skuId, String settleId) {
    if (!_canEditSkuSettlements) return;
    if (_skuSettleItemLocked('skuSettle', skuId, settleId)) return;
    final row = _sellableSkuById(skuId);
    if (row == null) return;
    final next = [
      for (final item in proposalIntakeSkuSettlements(row))
        if (item.id != settleId) item,
    ];
    _writeSkuSettlements(skuId, next);
  }

  void _patchSkuSettle(
    String skuId,
    String settleId,
    ProposalFinanceSettleTerms terms,
  ) {
    if (!_canEditSkuSettlements) return;
    if (_skuSettleItemLocked('skuSettle', skuId, settleId)) return;
    final row = _sellableSkuById(skuId);
    if (row == null) return;
    _writeSkuSettlements(skuId, [
      for (final item in proposalIntakeSkuSettlements(row))
        if (item.id == settleId) item.copyWith(terms: terms) else item,
    ]);
  }

  void _writeSharedSettlements(List<ProposalSharedSettleRow> rows) {
    if (!_canEditSkuSettlements) return;
    final form = _withEstimatedFinanceCosts(
      Map<String, dynamic>.from(_form)
        ..['sharedSettlements'] = [for (final row in rows) row.toJson()],
    );
    final review = Map<String, dynamic>.from(_review)
      ..['financeCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(form: form, review: review, status: _statusAfterEdit);
    if (mounted) setState(() {});
    _emitChanged(_row);
  }

  void _addSharedSettle() {
    if (!kProposalSharedSettleEnabled) return;
    _writeSharedSettlements([
      ...proposalIntakeSharedSettlements(_form),
      ProposalSharedSettleRow(id: proposalIntakeNewSharedSettleId()),
    ]);
  }

  void _removeSharedSettle(String id) {
    if (_skuSettleItemLocked('sharedSettle', id, id)) return;
    _writeSharedSettlements([
      for (final row in proposalIntakeSharedSettlements(_form))
        if (row.id != id) row,
    ]);
  }

  void _patchSharedSettle(String id, ProposalSharedSettleRow row) {
    if (_skuSettleItemLocked('sharedSettle', id, id)) return;
    _writeSharedSettlements([
      for (final item in proposalIntakeSharedSettlements(_form))
        if (item.id == id) row else item,
    ]);
  }

  Widget _sharedSettleCard(
    ProposalSharedSettleRow group, {
    required bool wide,
    required bool enabled,
  }) {
    final locked = _skuSettleItemLocked('sharedSettle', group.id, group.id);
    final canEdit = enabled && !locked;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          ProposalPalette.app,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '销售收入 · 共用结算',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, ProposalPalette.text),
                  ),
                ),
              ),
              if (canEdit)
                TextButton(
                  onPressed: () => _removeSharedSettle(group.id),
                  child: const Text('删除'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '勾选适用的$kProposalMainProductLabel。这是销售收入比例，不是项目成本。',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sku in proposalIntakeAllSellableSkus(_form))
                ProposalChoiceChip(
                  label: [
                    if (sku.productName.trim().isNotEmpty)
                      sku.productName.trim()
                    else
                      '未填写产品名称',
                    if (sku.faceValue.trim().isNotEmpty) sku.faceValue.trim(),
                  ].join(' · '),
                  selected: group.skuIds.contains(sku.id),
                  enabled: canEdit,
                  onSelected: canEdit
                      ? (_) {
                          final next = [...group.skuIds];
                          next.contains(sku.id)
                              ? next.remove(sku.id)
                              : next.add(sku.id);
                          _patchSharedSettle(
                            group.id,
                            group.copyWith(skuIds: next),
                          );
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _settleTermsGrid(
            wide: wide,
            keyPrefix: 'sharedSettle-${group.id}',
            terms: group.terms,
            enabled: canEdit,
            includeParties: false,
            includeChannel: false,
            includeScale: false,
            syncSource: _primarySyncSource(),
            productSource: 'CHANNEL',
            onChanged: (terms) =>
                _patchSharedSettle(group.id, group.copyWith(terms: terms)),
          ),
        ],
      ),
    );
  }

  int _foldedCount(int total, int visible) {
    if (total <= _productFoldPreview) return total;
    if (visible < _productFoldPreview) return _productFoldPreview;
    if (visible > total) return total;
    return visible;
  }

  Widget _foldedListActions({
    required int total,
    required int visible,
    required ValueChanged<int> onVisible,
  }) {
    if (total <= _productFoldPreview) return const SizedBox.shrink();
    final shown = _foldedCount(total, visible);
    final expanded = shown > _productFoldPreview;
    final rest = total - shown;
    final more = shown + _productFoldStep;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (shown < total)
            TextButton.icon(
              onPressed: () => onVisible(more > total ? total : more),
              icon: const Icon(Icons.expand_more, size: 16),
              label: const Text('显示更多'),
            ),
          if (shown < total)
            TextButton(
              onPressed: () => onVisible(total),
              child: Text('显示全部（还有 $rest 个）'),
            ),
          if (expanded)
            TextButton.icon(
              onPressed: () => onVisible(_productFoldPreview),
              icon: const Icon(Icons.expand_less, size: 16),
              label: const Text('收起'),
            ),
        ],
      ),
    );
  }

  /// 原型填写页的「业务平台产品」：标题、数量、说明、新增 / 多选在同一行，下面一行一个产品。
  Widget _protoSkuDetailsBlock(
    List<ProposalSkuDetailRow> rows,
    int visibleCount,
  ) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final allSelected =
        rows.isNotEmpty &&
        rows.every((row) => _selectedProductIds.contains(row.id));
    final dim = _protoLinkStyle.copyWith(
      foregroundColor: WidgetStatePropertyAll(c(0xFF8A8499)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 4, top: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: c(0xFFEDE8F6, DunesColorRole.border)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '业务平台产品',
                      style: TextStyle(
                        color: c(0xFF3F2A9A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '共 ${rows.length} 个 · 填写人填写，科技部负责人对本板块整块复核',
                      style: TextStyle(color: c(0xFF8A8499), fontSize: 11),
                    ),
                    if (_canEditProducts) ...[
                      TextButton(
                        onPressed: _addSkuDetail,
                        style: _protoLinkStyle,
                        child: const Text('+ 新增'),
                      ),
                      TextButton(
                        style: dim,
                        onPressed: () => setState(() {
                          _productMultiSelect = !_productMultiSelect;
                          if (!_productMultiSelect) _selectedProductIds.clear();
                        }),
                        child: Text(_productMultiSelect ? '取消多选' : '多选'),
                      ),
                      if (_productMultiSelect) ...[
                        TextButton(
                          style: dim,
                          onPressed: rows.isEmpty
                              ? null
                              : _toggleSelectAllProducts,
                          child: Text(allSelected ? '取消全选' : '全选'),
                        ),
                        TextButton(
                          style: _protoLinkStyle.copyWith(
                            foregroundColor: WidgetStatePropertyAll(
                              c(0xFFC0563F),
                            ),
                          ),
                          onPressed: _liveSelectedProductIds.isEmpty
                              ? null
                              : () =>
                                    unawaited(_confirmRemoveSelectedProducts()),
                          child: Text(
                            _liveSelectedProductIds.isEmpty
                                ? '删除所选'
                                : '删除所选（${_liveSelectedProductIds.length}）',
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (_rowReviewToggle(
                    'technologyItem:$kProposalSkuProductsReviewKey',
                    _techReviewLabel,
                  )
                  case final toggle?) ...[
                const SizedBox(width: 8),
                toggle,
              ],
            ],
          ),
        ),
        if (rows.isNotEmpty) ...[
          if (kProposalExistingBuiltEnabled) ...[
            const SizedBox(height: 8),
            _existingBuiltToggle(
              locked: _showSelectedAsText || !_canEditProducts,
            ),
          ],
          for (var i = 0; i < visibleCount; i++)
            _anchor(
              'skuDetail:${rows[i].id}',
              _skuProductSummaryRow(rows[i], i + 1, child: false),
            ),
          _foldedListActions(
            total: rows.length,
            visible: _businessProductVisible,
            onVisible: (next) => setState(() => _businessProductVisible = next),
          ),
        ],
      ],
    );
  }

  /// 原型 .lk：紫色粗体小字按钮。
  ButtonStyle get _protoLinkStyle => TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(0, 28),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    foregroundColor: DunesColors.resolve(context, const Color(0xFF5B3FD0)),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  );

  Widget _skuDetailsBlock(bool wide) {
    final rows = proposalIntakeSkuDetails(_form);
    final visibleCount = _foldedCount(rows.length, _businessProductVisible);
    if (_protoForm) return _protoSkuDetailsBlock(rows, visibleCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '业务平台产品',
                    style: TextStyle(
                      color: DunesColors.resolve(context, ProposalPalette.text),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _reviewEnabled(
                          'technologyItem:$kProposalSkuProductsReviewKey',
                        )
                        ? '填写人填写业务平台产品基础。科技部负责人对本板块整块复核：到本行点「点此复核」。'
                        : '填写人填写业务平台产品基础。由科技部负责人在待科技复核阶段点此复核，不是每条业务平台产品各审一次。',
                    style: kProposalCaptionStyle,
                  ),
                ],
              ),
            ),
            if (_rowReviewToggle(
                  'technologyItem:$kProposalSkuProductsReviewKey',
                  _techReviewLabel,
                )
                case final toggle?)
              toggle,
          ],
        ),
        const SizedBox(height: 10),
        if (_canEditProducts)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _addSkuDetail,
                  style: _protoForm ? _protoLinkStyle : null,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增'),
                ),
                TextButton(
                  style: _protoForm ? _protoLinkStyle : null,
                  onPressed: () => setState(() {
                    _productMultiSelect = !_productMultiSelect;
                    if (!_productMultiSelect) _selectedProductIds.clear();
                  }),
                  child: Text(_productMultiSelect ? '取消多选' : '多选'),
                ),
                if (_productMultiSelect) ...[
                  TextButton(
                    onPressed: proposalIntakeSkuDetails(_form).isEmpty
                        ? null
                        : _toggleSelectAllProducts,
                    child: Text(
                      proposalIntakeSkuDetails(_form).isNotEmpty &&
                              proposalIntakeSkuDetails(_form).every(
                                (row) => _selectedProductIds.contains(row.id),
                              )
                          ? '取消全选'
                          : '全选',
                    ),
                  ),
                  TextButton(
                    onPressed: _liveSelectedProductIds.isEmpty
                        ? null
                        : () => unawaited(_confirmRemoveSelectedProducts()),
                    style: TextButton.styleFrom(
                      foregroundColor: DunesColors.resolve(
                        context,
                        ProposalPalette.coral,
                      ),
                    ),
                    child: Text(
                      _liveSelectedProductIds.isEmpty
                          ? '删除所选'
                          : '删除所选（${_liveSelectedProductIds.length}）',
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (rows.isNotEmpty) ...[
          if (kProposalExistingBuiltEnabled) ...[
            const SizedBox(height: 8),
            _existingBuiltToggle(
              locked: _showSelectedAsText || !_canEditProducts,
            ),
          ],
          SizedBox(height: _protoForm ? 2 : 10),
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0 && !_protoForm) const SizedBox(height: 8),
            _anchor(
              'skuDetail:${rows[i].id}',
              _skuProductSummaryRow(rows[i], i + 1, child: false),
            ),
          ],
          _foldedListActions(
            total: rows.length,
            visible: _businessProductVisible,
            onVisible: (next) => setState(() => _businessProductVisible = next),
          ),
        ],
      ],
    );
  }

  Widget _relatedProductsBox(ProposalSkuDetailRow parent) {
    final children = proposalIntakeChildProducts(
      _form,
    ).where((item) => item.parentSkuId == parent.id).toList(growable: false);
    if (children.isEmpty) return const SizedBox.shrink();
    if (parent.resolvedCouponKind != kProposalCouponKindBenefit) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: _protoForm
          // 原型：缩进到名称下面，左边一条紫色细竖线。
          ? const EdgeInsets.only(top: 4, left: 74)
          : const EdgeInsets.only(top: 8),
      padding: _protoForm
          ? const EdgeInsets.fromLTRB(10, 4, 0, 2)
          : const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: _protoForm
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFCFC2F5),
                    role: DunesColorRole.border,
                  ),
                  width: 2,
                ),
              ),
            )
          : BoxDecoration(
              color: DunesColors.resolveNullable(
                context,
                Colors.white.withValues(alpha: 0.72),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.purpleLine,
                  role: DunesColorRole.border,
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联产品',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          for (var i = 0; i < children.length; i++)
            _relatedProductLine(children[i], i + 1),
        ],
      ),
    );
  }

  Widget _relatedProductLine(ProposalSkuDetailRow row, int index) {
    final name = row.displayName.trim();
    final title = name.isEmpty ? '关联产品 $index' : name;
    final bits = <String>[
      if (row.resolvedCouponKind.isNotEmpty && row.resolvedCouponKind != name)
        row.resolvedCouponKind,
      if (row.faceValue.trim().isNotEmpty) '面值 ${row.faceValue.trim()}',
      if (row.inventoryQty.trim().isNotEmpty) '库存 ${row.inventoryQty.trim()}',
      if (row.syncZhongyouHaoke.trim().isNotEmpty) row.syncZhongyouHaoke.trim(),
      proposalIntakeSkuRollbackValue(row, form: _form),
      '数量 ${proposalIntakeChildProductQuantity(_form, row.id)}',
      proposalIntakeSkuSettlements(row).any((item) => !item.terms.isBlank)
          ? '已填结算'
          : '未填结算',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_productSelectBox(row.id) case final box?) ...[
                box,
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            bits.join(' · '),
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          _skuRowActions(row, child: true),
        ],
      ),
    );
  }

  Widget _skuPlatformStatusChip(
    ProposalSkuDetailRow row, {
    String slot = 'product',
  }) {
    return ProposalStatusChip(
      key: ValueKey('proposal-sku-platform-status-${row.id}-$slot'),
      label: proposalSkuPlatformStatusChipLabel(row),
      kind: proposalSkuPlatformStatusChipKind(row.platformStatus),
    );
  }

  /// 原型填写页的业务平台产品行：名称、要点、状态、文字按钮，一行一条，细线分隔。
  Widget _protoSkuProductRow(
    ProposalSkuDetailRow row,
    String title,
    List<String> bits, {
    required bool child,
  }) {
    final narrow = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    // 原型：「业务产品 1」灰色小字在前，名称粗体。
    final cut = title.indexOf(' · ');
    final prefix = cut < 0 ? title : title.substring(0, cut);
    final name = cut < 0 ? '' : title.substring(cut + 3);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: name.isEmpty ? prefix : '$prefix  ',
                style: TextStyle(
                  color: DunesColors.resolve(context, const Color(0xFF8A8499)),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (name.isNotEmpty) TextSpan(text: name),
            ],
          ),
          style: TextStyle(
            color: DunesColors.resolve(context, const Color(0xFF2A2638)),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        if (bits.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            bits.join(' · '),
            style: TextStyle(
              color: DunesColors.resolve(context, const Color(0xFF5B556A)),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    final actions = _skuRowActions(row, child: child);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(child ? 12 : 0, 8, 0, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              const Color(0xFFF1EEF8),
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_productSelectBox(row.id) case final box?) ...[
                  box,
                  const SizedBox(width: 4),
                ],
                Expanded(child: info),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [_skuPlatformStatusChip(row), actions],
            ),
          ] else
            Row(
              children: [
                if (_productSelectBox(row.id) case final box?) ...[
                  box,
                  const SizedBox(width: 4),
                ],
                Expanded(child: info),
                const SizedBox(width: 10),
                _skuPlatformStatusChip(row),
                const SizedBox(width: 8),
                actions,
              ],
            ),
          if (!child) _relatedProductsBox(row),
        ],
      ),
    );
  }

  Widget _skuProductSummaryRow(
    ProposalSkuDetailRow row,
    int index, {
    required bool child,
  }) {
    final titleName = row.displayName;
    final title = titleName.isEmpty
        ? '${proposalIntakeProductKindLabel(child: child)} $index'
        : '${proposalIntakeProductKindLabel(child: child)} $index · $titleName';
    final parentName = child
        ? (proposalIntakeSkuDetails(_form)
                  .where((item) => item.id == row.parentSkuId)
                  .map((item) => item.displayName)
                  .where((name) => name.trim().isNotEmpty)
                  .firstOrNull ??
              '')
        : '';
    final bits = <String>[
      if (row.faceValue.trim().isNotEmpty) '面值 ${row.faceValue.trim()}',
      if (row.inventoryQty.trim().isNotEmpty) '库存 ${row.inventoryQty.trim()}',
      if (row.syncZhongyouHaoke.trim().isNotEmpty) row.syncZhongyouHaoke.trim(),
      proposalIntakeSkuRollbackValue(row, form: _form),
      if (child && parentName.isNotEmpty) '关联 $parentName',
      if (child) '数量 ${proposalIntakeChildProductQuantity(_form, row.id)}',
    ];
    if (_protoForm) {
      return _protoSkuProductRow(row, title, bits, child: child);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: child
            ? DunesColors.resolve(
                context,
                ProposalPalette.greenSoft,
                role: DunesColorRole.surface,
              ).withValues(alpha: 0.32)
            : DunesColors.resolve(
                context,
                ProposalPalette.purpleSoft,
                role: DunesColorRole.surface,
              ).withValues(alpha: 0.24),
        border: Border.all(
          color: child
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.green,
                  role: DunesColorRole.border,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.purpleLine,
                  role: DunesColorRole.border,
                ),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_productSelectBox(row.id) case final box?) ...[
                box,
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.text,
                        ),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if (bits.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bits.join(' · '),
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.text,
                          ),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _skuPlatformStatusChip(row),
          ),
          const SizedBox(height: 4),
          if (!child) ...[
            Text(
              '业务产品',
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            _skuRowActions(row, child: false),
            _relatedProductsBox(row),
          ] else
            _skuRowActions(row, child: true),
        ],
      ),
    );
  }

  Widget _skuRowActions(ProposalSkuDetailRow row, {required bool child}) {
    final style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 28),
      padding: EdgeInsets.symmetric(horizontal: _protoForm ? 6 : 8),
      // 原型：紫色粗体文字按钮。
      foregroundColor: _protoForm
          ? DunesColors.resolve(context, const Color(0xFF5B3FD0))
          : null,
      textStyle: TextStyle(
        fontSize: 12,
        fontWeight: _protoForm ? FontWeight.w700 : FontWeight.w600,
      ),
    );
    // 原型 .lk.dim：次要按钮灰色常规字重。
    final dim = _protoForm
        ? style.copyWith(
            foregroundColor: WidgetStatePropertyAll(
              DunesColors.resolve(context, const Color(0xFF8A8499)),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          )
        : style;
    return Wrap(
      spacing: 0,
      runSpacing: 0,
      children: [
        TextButton(
          style: style,
          onPressed: () =>
              unawaited(_openSkuProductDialog(child: child, existing: row)),
          child: Text(_canEditProducts ? '编辑' : '查看'),
        ),
        if (_canEditProducts && !child)
          TextButton(
            style: dim,
            onPressed: () => unawaited(_duplicateBusinessProduct(row)),
            child: const Text('复制新增'),
          ),
        if (_canEditProducts)
          TextButton(
            style: dim,
            onPressed: () => unawaited(
              child ? _confirmRemoveLinked(row) : _confirmRemoveProduct(row),
            ),
            child: const Text('删除'),
          ),
        TextButton(
          style: dim,
          onPressed: () =>
              unawaited(_openSkuSettleDialog(sku: row, child: child)),
          child: Text(_canEditSkuSettlements ? '填写结算' : '查看结算'),
        ),
      ],
    );
  }

  Widget _childProductSwitcher(List<ProposalSkuDetailRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final activeId = _resolvedChildProductId;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < rows.length; i++)
          ProposalChoiceChip(
            label: _childSwitcherLabel(rows[i], i + 1),
            selected: rows[i].id == activeId,
            onSelected: (_) => _selectChildProduct(rows[i].id),
          ),
      ],
    );
  }

  String _childSwitcherLabel(ProposalSkuDetailRow sku, int index) {
    final name = sku.displayName.trim();
    final title = name.isEmpty ? '$kProposalChildProductLabel $index' : name;
    final settlements = proposalIntakeSkuSettlements(sku);
    if (settlements.isEmpty) return title;
    if (_itemReviewed('financeItem:$kProposalSkuSettlementsReviewKey')) {
      return '$title · 结算已复核';
    }
    return title;
  }

  Widget _existingBuiltToggle({required bool locked, bool child = false}) {
    final enabled = child
        ? proposalIntakeIsChildExistingBuilt(_form)
        : proposalIntakeIsExistingBuilt(_form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: locked
              ? null
              : () => child
                    ? _setChildExistingBuiltEnabled(!enabled)
                    : _setExistingBuiltEnabled(!enabled),
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
                      : (value) => child
                            ? _setChildExistingBuiltEnabled(value == true)
                            : _setExistingBuiltEnabled(value == true),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                child ? '$kProposalChildProductLabel是否已经建产品' : '是否已经建产品',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 28),
          child: Text(
            child
                ? '不勾：手工填写产品信息。\n'
                      '勾选：先选业务平台，再搜索选中资管已建的产品。选中后会按资管结算规则同步账单类型、结算方式、税率，下面的字段不用再填。'
                : '不勾：手工填写产品信息。\n'
                      '勾选：先选业务平台，再搜索选中资管已建的产品。选中后会按资管结算规则同步账单类型、结算方式、税率；券包会带出子产品基础信息和对应结算，仍可继续增改。',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  /// 主产品卡片里的分组小标题。
  ///
  /// 十几个字段平铺成一张网格时，看不出哪些是归类、哪些是产品属性、
  /// 哪些是给外部系统用的。用小标题把它们切开。
  Widget _skuGroupLabel(String title, String? hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text2),
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          if (hint == null)
            Expanded(
              child: Divider(
                height: 1,
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 每条产品自己的渠道设置；可复制到另一条产品，但不会复制产品名称。
  Widget _skuSettingsEditor(
    ProposalSkuDetailRow row,
    bool wide, {
    required ValueChanged<ProposalSkuDetailRow Function(ProposalSkuDetailRow)>
    onPatch,
    bool child = false,
  }) {
    final locked = _showSelectedAsText || !_canEditMarket;
    final existing =
        kProposalExistingBuiltEnabled &&
        ((child
                ? proposalIntakeIsChildExistingBuilt(_form)
                : proposalIntakeIsExistingBuilt(_form)) ||
            row.isExistingBuilt);
    void patch(ProposalSkuDetailRow Function(ProposalSkuDetailRow row) update) {
      onPatch(update);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                child ? '$kProposalChildProductLabel渠道设置' : '渠道设置',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text2),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_canEditMarket) ...[
              TextButton(
                onPressed: () => setState(() => _skuSettingsClipboard = row),
                child: const Text('复制设置'),
              ),
              TextButton(
                onPressed: _skuSettingsClipboard == null
                    ? null
                    : () => patch(
                        (current) => _copySkuSettings(
                          target: current,
                          source: _skuSettingsClipboard!,
                        ),
                      ),
                child: const Text('粘贴设置'),
              ),
            ],
          ],
        ),
        _fieldGrid(wide, [
          _skuCatalogCell(
            label: '业务平台',
            current: row.syncSourceRef,
            options: _businessPlatformOptions(),
            locked: locked,
            required: existing,
            hint: _businessPlatformOptions().isEmpty ? '暂无业务平台' : '请选择业务平台',
            onSelected: (value) {
              patch((current) {
                final changed = current.syncSourceCode != (value?.code ?? '');
                var next = current.copyWith(
                  syncSourceRef: value,
                  channelRef: changed ? null : current.channelRef,
                  settlements: changed
                      ? [
                          for (final item in proposalIntakeSkuSettlements(
                            current,
                          ))
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
                  _assetProductSyncSeq[row.id] =
                      (_assetProductSyncSeq[row.id] ?? 0) + 1;
                  _assetProductSyncHint.remove(row.id);
                }
                return next;
              });
              if (value != null && value.isNotEmpty) {
                _prefetchSettle(
                  _boundSyncSourceCode(value.code, name: value.name),
                  'CHANNEL',
                );
              }
            },
          ),
          _skuChannelCell(
            current: row.channelRef,
            locked: locked,
            syncSource: _skuSyncSource(row),
            onSelected: (value) => patch(
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
          if (!existing) ...[
            _skuInstitutionCell(
              current: row.institutionRef,
              locked: locked,
              onSelected: (value) =>
                  patch((current) => current.copyWith(institutionRef: value)),
            ),
            _skuCatalogCell(
              label: '标签三-一级',
              current: row.resolvedChannelCategoryL1,
              options: _channelCategoryL1,
              locked: locked,
              hint: _channelCategoryL1.isEmpty ? '字典加载中或暂无分类' : '请选择标签三-一级',
              emptyText: _channelCategoryL1.isEmpty ? '字典加载中或暂无分类' : null,
              onSelected: (value) =>
                  patch((current) => _applyChannelCategoryL1(current, value)),
            ),
            _skuCatalogCell(
              label: '标签三-二级',
              current: row.resolvedChannelCategoryL2,
              options: _channelCategoryL2Of(row.resolvedChannelCategoryL1),
              locked: locked,
              hint:
                  (row.resolvedChannelCategoryL1 == null ||
                      row.resolvedChannelCategoryL1!.isEmpty)
                  ? '请先选择标签三-一级'
                  : (_channelCategoryL2Of(row.resolvedChannelCategoryL1).isEmpty
                        ? '字典加载中或暂无分类'
                        : '请选择标签三-二级'),
              emptyText:
                  (row.resolvedChannelCategoryL1 == null ||
                      row.resolvedChannelCategoryL1!.isEmpty)
                  ? '请先选择标签三-一级'
                  : '该一级分类暂无二级分类',
              onSelected: (value) => patch(
                (current) => current.copyWith(
                  channelCategoryL2Ref: value,
                  channelCategoryL2: proposalIntakeCategoryLabel(value, ''),
                ),
              ),
            ),
            _skuSyncZhongyouHaokeField(
              row: row,
              locked: locked,
              onPatch: patch,
            ),
          ],
        ], columns: 2),
      ],
    );
  }

  ProposalSkuDetailRow _copySkuSettings({
    required ProposalSkuDetailRow target,
    required ProposalSkuDetailRow source,
  }) {
    final platformChanged = target.syncSourceCode != source.syncSourceCode;
    return target.copyWith(
      syncSourceRef: source.syncSourceRef,
      channelRef: source.channelRef,
      institutionRef: source.institutionRef,
      channelCategoryL1: source.channelCategoryL1,
      channelCategoryL2: source.channelCategoryL2,
      channelCategoryL1Ref: source.channelCategoryL1Ref,
      channelCategoryL2Ref: source.channelCategoryL2Ref,
      syncZhongyouHaoke: source.syncZhongyouHaoke,
      faceValue: source.faceValue,
      productCategoryL1: source.productCategoryL1,
      productCategoryL2: source.productCategoryL2,
      effectiveDate: source.effectiveDate,
      expireDate: source.expireDate,
      supplierCodes: source.supplierCodes,
      inventoryQty: source.inventoryQty,
      rollback: proposalIntakeSkuRollbackValue(source),
      assetProduct: platformChanged ? null : target.assetProduct,
    );
  }

  bool _skuNameInUse(String name, String currentId) {
    final normalized = name.trim();
    if (normalized.isEmpty) return false;
    return proposalIntakeSkuDetails(_form).any(
      (item) => item.id != currentId && item.productName.trim() == normalized,
    );
  }

  bool _childCouponInUse(ProposalSkuDetailRow row) {
    final kind = row.resolvedCouponKind;
    if (kind.isEmpty) return false;
    final face = row.faceValue.trim();
    final parent = row.parentSkuId.trim();
    return proposalIntakeChildProducts(_form).any(
      (item) =>
          item.id != row.id &&
          item.resolvedCouponKind == kind &&
          item.faceValue.trim() == face &&
          item.parentSkuId.trim() == parent,
    );
  }

  void _changeSkuName({
    required String id,
    required String name,
    required bool child,
  }) {
    if (_skuNameInUse(name, id)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('产品名称不能与提案内其他产品重复')));
      return;
    }
    final update = (ProposalSkuDetailRow current) =>
        current.copyWith(productName: name);
    if (child) {
      _patchChildProduct(id, update, rebuild: false);
    } else {
      _patchSkuDetail(id, update, rebuild: false);
    }
  }

  Widget _skuDetailCard(
    ProposalSkuDetailRow row,
    int index,
    bool wide, {
    bool child = false,
  }) {
    final locked = _showSelectedAsText || !_canEditMarket;
    final existing =
        kProposalExistingBuiltEnabled &&
        ((child
                ? proposalIntakeIsChildExistingBuilt(_form)
                : proposalIntakeIsExistingBuilt(_form)) ||
            row.isExistingBuilt);
    void patch(
      String id,
      ProposalSkuDetailRow Function(ProposalSkuDetailRow row) update, {
      bool rebuild = true,
    }) {
      if (child) {
        _patchChildProduct(id, update, rebuild: rebuild);
      } else {
        _patchSkuDetail(id, update, rebuild: rebuild);
      }
    }

    final showManual =
        !existing || (locked && proposalIntakeSkuHasManualDetails(row));
    final titleName = row.displayName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: child
            ? DunesColors.resolve(
                context,
                ProposalPalette.greenSoft,
                role: DunesColorRole.surface,
              ).withValues(alpha: 0.32)
            : DunesColors.resolve(
                context,
                ProposalPalette.purpleSoft,
                role: DunesColorRole.surface,
              ).withValues(alpha: 0.24),
        border: Border.all(
          color: child
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.green,
                  role: DunesColorRole.border,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.purpleLine,
                  role: DunesColorRole.border,
                ),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titleName.isEmpty
                      ? '${proposalIntakeProductKindLabel(child: child)} $index'
                      : '${proposalIntakeProductKindLabel(child: child)} $index · $titleName',
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_canEditMarket)
                TextButton(
                  onPressed: () => unawaited(
                    child
                        ? _confirmRemoveLinked(row)
                        : _confirmRemoveProduct(row),
                  ),
                  child: const Text('删除'),
                ),
              TextButton.icon(
                onPressed: () => _jumpToSkuSettlement(row, child: child),
                icon: const Icon(Icons.keyboard_return_rounded, size: 15),
                label: const Text('填写结算'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (kProposalSkuChannelSettingsEnabled)
            _skuSettingsEditor(
              row,
              wide,
              child: child,
              onPatch: (update) => patch(row.id, update),
            ),
          if (child) ...[
            const SizedBox(height: 10),
            _childMainProductAssociationField(row, locked: locked),
            const SizedBox(height: 10),
            _skuTextCell(
              rowId: row.id,
              label: '$kProposalChildProductLabel数量',
              value: '${proposalIntakeChildProductQuantity(_form, row.id)}',
              fieldKey: 'association-quantity',
              hint: '至少为 1',
              locked: locked,
              required: true,
              keyboardType: TextInputType.number,
              onChanged: (value) => _setChildProductQuantity(row.id, value),
            ),
          ],
          if (existing)
            _fieldGrid(wide, [
              _assetProductSearchCell(
                rowId: row.id,
                current: row.assetProduct,
                syncSource: _skuSyncSource(row),
                locked: locked,
                label: '已建产品',
                fallbackLabel: row.displayName,
                onSelected: (value) {
                  patch(row.id, (current) => current.applyAssetProduct(value));
                  unawaited(
                    _syncAssetProductSettlement(rowId: row.id, hit: value),
                  );
                },
              ),
            ], columns: 1),
          if (showManual)
            _fieldGrid(wide, [
              _skuTextCell(
                rowId: row.id,
                label: '产品名称',
                value: row.productName,
                fieldKey: 'name',
                locked: locked,
                onChanged: (value) =>
                    _changeSkuName(id: row.id, name: value, child: child),
              ),
              _skuTextCell(
                rowId: row.id,
                label: '面值',
                value: row.faceValue,
                fieldKey: 'face',
                hint: '手填',
                locked: locked,
                onChanged: (value) => patch(
                  row.id,
                  (current) => current.copyWith(faceValue: value),
                  rebuild: false,
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
                onChanged: (value) => patch(
                  row.id,
                  (current) => current.copyWith(inventoryQty: value),
                  rebuild: false,
                ),
              ),
              if (kProposalSkuDateFieldsEnabled) ...[
                _skuDateCell(
                  rowId: row.id,
                  label: '产品生效日期',
                  value: row.effectiveDate,
                  fieldKey: 'effective',
                  locked: locked,
                  onPicked: (value) => patch(
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
                  onPicked: (value) => patch(
                    row.id,
                    (current) => current.copyWith(expireDate: value),
                  ),
                ),
              ],
              _skuTextCell(
                rowId: row.id,
                label: '供应商编码',
                value: row.supplierCodes,
                fieldKey: 'suppliers',
                hint: '多个用 | 分隔，越前面的排名越高，例如 A|B|C',
                locked: locked,
                onChanged: (value) => patch(
                  row.id,
                  (current) => current.copyWith(supplierCodes: value),
                  rebuild: false,
                ),
              ),
              if (!kProposalSkuChannelSettingsEnabled)
                _skuSyncZhongyouHaokeField(
                  row: row,
                  locked: locked,
                  onPatch: (update) => patch(row.id, update),
                ),
            ], columns: 2)
          else if (!kProposalSkuChannelSettingsEnabled)
            _fieldGrid(wide, [
              _skuSyncZhongyouHaokeField(
                row: row,
                locked: locked,
                onPatch: (update) => patch(row.id, update),
              ),
            ], columns: 2),
        ],
      ),
    );
  }

  Widget _skuSyncZhongyouHaokeField({
    required ProposalSkuDetailRow row,
    required bool locked,
    required ValueChanged<ProposalSkuDetailRow Function(ProposalSkuDetailRow)>
    onPatch,
  }) {
    return ProposalField(
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
              onSelected: (value) => onPatch(
                (current) => current.copyWith(syncZhongyouHaoke: value ?? ''),
              ),
            ),
    );
  }

  Widget _childMainProductAssociationField(
    ProposalSkuDetailRow child, {
    required bool locked,
  }) {
    final mainProducts = proposalIntakeSkuDetails(_form);
    return ProposalField(
      label: '关联$kProposalMainProductLabel',
      required: true,
      child: locked
          ? _readonlySelectedText(
              mainProducts
                      .where((item) => item.id == child.parentSkuId)
                      .map((item) => item.displayName)
                      .firstOrNull ??
                  '',
            )
          : ProposalSelectField<String>(
              value: child.parentSkuId.isEmpty ? null : child.parentSkuId,
              hint: mainProducts.isEmpty
                  ? '请先新增$kProposalMainProductLabel'
                  : '请选择关联$kProposalMainProductLabel',
              emptyText: mainProducts.isEmpty
                  ? '请先在上方新增$kProposalMainProductLabel'
                  : null,
              options: [
                for (var i = 0; i < mainProducts.length; i++)
                  ProposalSelectOption(
                    value: mainProducts[i].id,
                    label: mainProducts[i].displayName.isEmpty
                        ? '$kProposalMainProductLabel ${i + 1}'
                        : mainProducts[i].displayName,
                  ),
              ],
              onSelected: (value) => _setChildProductParent(child.id, value),
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
    bool supplier = false,
    String fallbackLabel = '',
  }) {
    final noPlatform = syncSource.trim().isEmpty;
    final searching = _assetProductSearching.contains(rowId);
    final syncing = _assetProductSyncing.contains(rowId);
    final hintText = _assetProductSyncHint[rowId] ?? '';
    final hits = _assetProductHits[rowId] ?? const <ChannelProductHit>[];
    final displayLabel = (current?.label ?? '').trim().isNotEmpty
        ? current!.label
        : fallbackLabel.trim();
    final resolved = (current != null && current.isNotEmpty)
        ? current
        : (displayLabel.isEmpty
              ? null
              : ChannelProductHit(productName: displayLabel));
    final values = [
      if (resolved != null && !hits.any((item) => item == resolved)) resolved,
      ...hits,
    ];
    return ProposalField(
      label: label,
      required: true,
      footer: hintText.isEmpty
          ? null
          : Text(
              hintText,
              style: TextStyle(
                fontSize: 11,
                color: syncing
                    ? DunesColors.resolve(context, ProposalPalette.amber)
                    : DunesColors.resolve(context, ProposalPalette.text3),
              ),
            ),
      child: locked
          ? _readonlySelectedText(displayLabel)
          : ProposalSelectField<ChannelProductHit>(
              value: resolved,
              title: label,
              hint: noPlatform ? '请先选择业务平台' : '输入产品名称关键字搜索',
              searchable: true,
              requireKeyword: true,
              remoteOptions: true,
              emptyText: noPlatform
                  ? '请先选择业务平台'
                  : (searching ? '搜索中…' : (supplier ? '未找到已建供给产品' : '未找到已建产品')),
              options: [
                for (final item in values)
                  ProposalSelectOption(
                    value: item,
                    label: item.label,
                    meta: [
                      if (item.productCode.isNotEmpty) item.productCode,
                      if (supplier) ...[
                        if (item.supplierName.isNotEmpty) item.supplierName,
                        if (item.supplierCode.isNotEmpty) item.supplierCode,
                      ] else if (item.channelName.isNotEmpty)
                        item.channelName,
                    ].join(' · '),
                  ),
              ],
              onQueryChanged: noPlatform
                  ? null
                  : (query) => unawaited(
                      supplier
                          ? _searchSupplierProducts(rowId, syncSource, query)
                          : _searchAssetProducts(rowId, syncSource, query),
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
      label: '我方供给',
      current: current,
      options: options,
      locked: locked,
      hint: options.isEmpty ? '请先在管理端配置我方供给' : '请选择我方供给',
      emptyText: options.isEmpty ? '请先在管理后台「提案录入选项」中配置我方供给' : null,
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
          : (options.isEmpty ? (loading ? '字典加载中…' : '该业务平台暂无渠道') : '请选择渠道'),
      emptyText: noPlatform ? '请先选择业务平台' : (loading ? '字典加载中…' : '该业务平台暂无渠道'),
      onSelected: onSelected,
    );
  }

  List<CatalogRef> _channelCategoryL2Of(CatalogRef? l1) {
    if (l1 == null || l1.isEmpty) return const [];
    return [
      for (final item in _channelCategoryL2)
        if (proposalIntakeChannelCategoryChildOf(item, l1)) item,
    ];
  }

  ProposalSkuDetailRow _applyChannelCategoryL1(
    ProposalSkuDetailRow current,
    CatalogRef? value,
  ) {
    final l2 = current.resolvedChannelCategoryL2;
    final keep =
        value != null &&
        value.isNotEmpty &&
        l2 != null &&
        proposalIntakeChannelCategoryChildOf(l2, value);
    return current.copyWith(
      channelCategoryL1Ref: value,
      channelCategoryL1: proposalIntakeCategoryLabel(value, ''),
      channelCategoryL2Ref: keep ? current.channelCategoryL2Ref : null,
      channelCategoryL2: keep ? current.channelCategoryL2 : '',
    );
  }

  Widget _techSyncSourceField({
    String? fieldKey,
    CatalogRef? valueOverride,
    String? reviewSection,
    ValueChanged<CatalogRef?>? onSelected,
  }) {
    final enabled = _fillEnabled(
      _canEditTech,
      resetReview: 'technologyCompleted',
      reviewSection: reviewSection ?? 'technologyItem:syncSourceRef',
    );
    final current = valueOverride ?? proposalIntakeFormSyncSourceRef(_form);
    final selected =
        _selectedBusinessPlatform(current) ??
        ((current != null && current.isNotEmpty) ? current : null);
    final values = _withCurrent(_businessPlatformOptions(), selected);
    final display = (selected?.label ?? current?.label ?? '').trim();
    final tone = proposalFieldTone(enabled: enabled);
    final emptyCatalog = _businessPlatformOptions().isEmpty;
    return _FullWidthField(
      child: _anchor(
        fieldKey ?? 'syncSourceRef',
        ProposalField(
          label: '业务平台',
          required: true,
          tone: tone,
          trailing: _rowReviewToggle(
            reviewSection ?? 'technologyItem:syncSourceRef',
            _techReviewLabel,
          ),
          child: !enabled || _showSelectedAsText
              ? _readonlySelectedText(display)
              : ProposalSelectField<CatalogRef>(
                  value: selected == null || selected.isEmpty ? null : selected,
                  title: '业务平台',
                  hint: emptyCatalog ? '暂无业务平台' : '请选择业务平台',
                  searchable: true,
                  emptyText: emptyCatalog ? '暂无业务平台' : '暂无业务平台',
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
                  onSelected: onSelected ?? _setTechSyncSource,
                ),
        ),
      ),
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
    bool required = false,
  }) {
    final selected =
        _selectedCatalog(current, options) ??
        ((current != null && current.isNotEmpty) ? current : null);
    final values = _withCurrent(options, selected);
    final display = (selected?.label ?? current?.label ?? '').trim();
    return ProposalField(
      label: label,
      required: required,
      child: locked || _showSelectedAsText
          ? _readonlySelectedText(display)
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
    bool required = false,
  }) {
    final tone = proposalFieldTone(enabled: !locked, source: source);
    final multiline = maxLines > 1;
    final field = ProposalField(
      label: label,
      required: required,
      tone: tone,
      child: locked
          ? _readonlySelectedText(value)
          : TextFormField(
              key: ValueKey('sku-$rowId-$fieldKey-$_fieldEpoch'),
              initialValue: value,
              minLines: multiline ? 3 : 1,
              maxLines: multiline ? null : 1,
              keyboardType:
                  keyboardType ?? (multiline ? TextInputType.multiline : null),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: onChanged,
              decoration: proposalInputDecoration(
                context: context,
                hint: hint,
                tone: tone,
              ),
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
    bool required = false,
  }) {
    final parsed = _parseDate(value);
    return _datePickerField(
      fieldKey: 'sku-$rowId-$fieldKey',
      label: label,
      display: parsed == null ? value : _fmtDate(parsed),
      empty: value.trim().isEmpty,
      enabled: !locked,
      required: required,
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
    bool required = false,
  }) {
    return ProposalField(
      label: label,
      required: required,
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

  Widget _skuStringSelectCell({
    required String rowId,
    required String label,
    required String value,
    required String fieldKey,
    required List<String> options,
    required bool locked,
    required ValueChanged<String> onChanged,
    String? addLabel,
    bool required = false,
  }) {
    final current = value.trim();
    final values = [
      if (current.isNotEmpty && !options.contains(current)) current,
      ...options,
    ];
    return ProposalField(
      label: label,
      required: required,
      child: locked
          ? _readonlySelectedText(current)
          : ProposalSelectField<String>(
              key: ValueKey('sku-$rowId-$fieldKey-$_fieldEpoch'),
              value: current.isEmpty ? null : current,
              title: label,
              hint: values.isEmpty && addLabel == null ? '请先在管理端配置选项' : '请选择',
              searchable: true,
              addLabel: addLabel,
              onAdd: addLabel == null
                  ? null
                  : () async {
                      final added = await _promptAddedOption(addLabel);
                      if (added == null || added.isEmpty) return;
                      onChanged(added);
                    },
              options: [
                for (final item in values)
                  ProposalSelectOption(value: item, label: item),
              ],
              onSelected: (next) => onChanged(next ?? ''),
            ),
    );
  }

  Future<String?> _promptAddedOption(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: proposalInputDecoration(context: context),
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
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Widget _skuSettlementsReviewHeader({
    required String title,
    required String hint,
  }) {
    final toggle = proposalIntakeSkuSettleReviewKeys(_form).isEmpty
        ? null
        : _rowReviewToggle(
            'financeItem:$kProposalSkuSettlementsReviewKey',
            _financeReviewLabel,
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: kProposalSubBlockTitleStyle),
              const SizedBox(height: 4),
              Text(hint, style: kProposalCaptionStyle),
            ],
          ),
        ),
        if (toggle != null) toggle,
      ],
    );
  }

  Widget _childSettlementsBlock(bool wide) {
    final rows = proposalIntakeChildProducts(_form);
    final enabled = _canEditSkuSettlements;
    final sku = _activeChildProduct;
    return _anchor(
      'childProductSalesSettle',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skuSettlementsReviewHeader(
            title: '$kProposalChildProductLabel结算',
            hint: '每个$kProposalChildProductLabel独立结算，用切换条查看；复核整块完成。',
          ),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '请先在市场部新增$kProposalChildProductLabel。',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            _childProductSwitcher(rows),
            if (sku != null) ...[
              const SizedBox(height: 8),
              _skuSettleProductCard(
                skuId: sku.id,
                childProduct: true,
                product: sku,
                title: [
                  if (sku.productName.trim().isNotEmpty) sku.productName.trim(),
                  if (sku.faceValue.trim().isNotEmpty)
                    '面值 ${sku.faceValue.trim()}',
                ].join(' · '),
                emptyTitle: '未选择现金券或满减券',
                reviewPrefix: 'skuSettle',
                settlements: proposalIntakeSkuSettlements(sku),
                wide: wide,
                enabled: enabled,
                syncSource: _skuSyncSource(sku),
                productSource: 'CHANNEL',
                onAdd: () => _addSkuSettle(sku.id),
                onAddKind: (kind) => _addSkuSettle(sku.id, kind: kind),
                onRemove: (settleId) => _removeSkuSettle(sku.id, settleId),
                onPatch: (settleId, terms) =>
                    _patchSkuSettle(sku.id, settleId, terms),
                onReplace: (settlements) =>
                    _writeSkuSettlements(sku.id, settlements),
                onJumpToProduct: () => _jumpToSkuProduct(sku, child: true),
                includeScale: false,
                compact: true,
                onOpenEditor: () =>
                    unawaited(_openSkuSettleDialog(sku: sku, child: true)),
                scaleOnly: false,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _skuSettlementsBlock(bool wide) {
    final channelRows = proposalIntakeSkuDetails(_form);
    final enabled = _canEditSkuSettlements;
    return _anchor(
      'productSalesSettle',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skuSettlementsReviewHeader(
            title: proposalIntakeHasChildProducts(_form)
                ? '$kProposalMainProductLabel结算'
                : '产品结算',
            hint: kProposalSharedSettleEnabled
                ? '比例相同可勾共用结算，各产品只填规模；不同则各卡单独填。'
                : '每个产品一套结算，可再加明细；复核整块完成。',
          ),
          if (channelRows.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '请先在科技部添加$kProposalMainProductLabel。',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontSize: 12,
                ),
              ),
            ),
          if (kProposalSharedSettleEnabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled ? _addSharedSettle : null,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('新增共用结算'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: DunesColors.resolve(
                    context,
                    ProposalPalette.purpleDeep,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            for (final group in proposalIntakeSharedSettlements(_form)) ...[
              const SizedBox(height: 8),
              _sharedSettleCard(group, wide: wide, enabled: enabled),
            ],
          ],
          for (
            var i = 0;
            i < _foldedCount(channelRows.length, _financeSettleVisible);
            i++
          ) ...[
            const SizedBox(height: 8),
            _skuSettleProductCard(
              skuId: channelRows[i].id,
              childProduct: false,
              product: channelRows[i],
              title: [
                if (channelRows[i].productName.trim().isNotEmpty)
                  channelRows[i].productName.trim(),
                if (channelRows[i].faceValue.trim().isNotEmpty)
                  '面值 ${channelRows[i].faceValue.trim()}',
              ].join(' · '),
              emptyTitle: '未填写产品名称',
              reviewPrefix: 'skuSettle',
              settlements: proposalIntakeSkuSettlements(channelRows[i]),
              wide: wide,
              enabled: enabled,
              syncSource: _skuSyncSource(channelRows[i]),
              productSource: 'CHANNEL',
              onAdd: () => _addSkuSettle(channelRows[i].id),
              onAddKind: (kind) => _addSkuSettle(channelRows[i].id, kind: kind),
              onRemove: (settleId) =>
                  _removeSkuSettle(channelRows[i].id, settleId),
              onPatch: (settleId, terms) =>
                  _patchSkuSettle(channelRows[i].id, settleId, terms),
              onReplace: (settlements) =>
                  _writeSkuSettlements(channelRows[i].id, settlements),
              onJumpToProduct: () =>
                  _jumpToSkuProduct(channelRows[i], child: false),
              includeScale: false,
              compact: true,
              onOpenEditor: () => unawaited(
                _openSkuSettleDialog(sku: channelRows[i], child: false),
              ),
              scaleOnly: false,
            ),
          ],
          _foldedListActions(
            total: channelRows.length,
            visible: _financeSettleVisible,
            onVisible: (next) => setState(() => _financeSettleVisible = next),
          ),
        ],
      ),
    );
  }

  String _primarySyncSource() {
    final ref = proposalIntakeFormSyncSourceRef(_form);
    final fromForm = proposalIntakeFormSyncSourceCode(_form);
    final bound = _boundSyncSourceCode(fromForm, name: ref?.name ?? '');
    if (bound.isNotEmpty) return bound;
    for (final sku in proposalIntakeAllSellableSkus(_form)) {
      if (sku.syncSourceCode.isNotEmpty) {
        return _boundSyncSourceCode(
          sku.syncSourceCode,
          name: sku.syncSourceRef?.name ?? '',
        );
      }
    }
    return '';
  }

  String _skuSyncSource(ProposalSkuDetailRow sku) {
    final raw = proposalIntakeResolvedSyncSourceCode(_form, sku);
    final name =
        sku.syncSourceRef?.name ??
        proposalIntakeFormSyncSourceRef(_form)?.name ??
        '';
    return _boundSyncSourceCode(raw, name: name);
  }

  Widget _skuSettleProductCard({
    required String skuId,
    bool childProduct = false,
    required String title,
    required String emptyTitle,
    required String reviewPrefix,
    required List<ProposalSkuSettleRow> settlements,
    required bool wide,
    required bool enabled,
    required String syncSource,
    required String productSource,
    required VoidCallback onAdd,
    void Function(String kind)? onAddKind,
    required ValueChanged<String> onRemove,
    required void Function(String settleId, ProposalFinanceSettleTerms terms)
    onPatch,
    ValueChanged<List<ProposalSkuSettleRow>>? onReplace,
    VoidCallback? onJumpToProduct,
    String reviewItemPrefix = 'financeItem',
    String? itemReviewLabel,
    bool showItemReview = true,
    bool requireSchedule = false,
    bool includeScale = false,
    bool scaleOnly = false,
    bool linkSkus = false,
    bool compact = false,
    VoidCallback? onOpenEditor,
    VoidCallback? onClipboardChanged,
    ProposalSkuDetailRow? product,
  }) {
    final summaryBits = <String>[
      if (settlements.isEmpty) '尚未填写',
      if (settlements.isNotEmpty) '结算 ${settlements.length} 条',
      if (settlements.isNotEmpty &&
          settlements.first.terms.scale.trim().isNotEmpty)
        '规模 ${settlements.first.terms.scale.trim()}',
      if (settlements.isNotEmpty &&
          settlements.first.terms.displayRatio.trim().isNotEmpty)
        '比例 ${settlements.first.terms.displayRatio.trim()}',
      if (settlements.isNotEmpty &&
          settlements.first.terms.displayUnitPrice.trim().isNotEmpty)
        '单价 ${settlements.first.terms.displayUnitPrice.trim()}',
    ];
    return Container(
      width: double.infinity,
      // 原型「产品结算」：一行一个产品，细线分隔，不再是紫框卡片。
      padding: _protoForm
          ? const EdgeInsets.symmetric(vertical: 7)
          : const EdgeInsets.all(12),
      decoration: _protoForm
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFF3F0F8),
                    role: DunesColorRole.border,
                  ),
                ),
              ),
            )
          : BoxDecoration(
              color: childProduct
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.greenSoft,
                      role: DunesColorRole.surface,
                    ).withValues(alpha: 0.26)
                  : DunesColors.resolve(
                      context,
                      ProposalPalette.purpleSoft,
                      role: DunesColorRole.surface,
                    ).withValues(alpha: 0.18),
              border: Border.all(
                color: childProduct
                    ? DunesColors.resolve(
                        context,
                        ProposalPalette.green,
                        role: DunesColorRole.border,
                      )
                    : DunesColors.resolve(
                        context,
                        ProposalPalette.purpleLine,
                        role: DunesColorRole.border,
                      ),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title.isEmpty ? emptyTitle : title,
                style: TextStyle(
                  fontSize: _protoForm ? 13 : 12.5,
                  fontWeight: _protoForm ? FontWeight.w700 : FontWeight.w600,
                  color: DunesColors.resolve(context, ProposalPalette.text),
                ),
              ),
              if (product != null)
                _skuPlatformStatusChip(product, slot: 'settle'),
              if (compact && summaryBits.isNotEmpty)
                Text(
                  summaryBits.join(' · '),
                  style: _protoForm
                      ? TextStyle(
                          fontSize: 12,
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFF5B556A),
                          ),
                          fontFamily: kProposalProtoMono,
                          fontFamilyFallback: kProposalProtoMonoFallback,
                        )
                      : kProposalCaptionStyle,
                ),
              if (enabled && !compact && productSource != 'CHANNEL')
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('新增明细'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.purpleDeep,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (onReplace != null) ...[
                TextButton(
                  onPressed: () {
                    setState(
                      () => _skuSettlementsClipboard = [
                        for (final item in settlements)
                          ProposalSkuSettleRow(
                            id: item.id,
                            kind: item.kind,
                            terms: item.terms,
                          ),
                      ],
                    );
                    onClipboardChanged?.call();
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.text2,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('复制结算'),
                ),
                TextButton(
                  onPressed: _skuSettlementsClipboard == null
                      ? null
                      : () => onReplace(_pasteSkuSettlements(settlements)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.text2,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('粘贴结算'),
                ),
              ],
              if (onJumpToProduct != null)
                TextButton.icon(
                  onPressed: onJumpToProduct,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                  label: const Text('产品信息'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.text2,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (compact && onOpenEditor != null)
                TextButton(
                  onPressed: onOpenEditor,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.purpleDeep,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(enabled ? '填写结算' : '查看结算'),
                ),
            ],
          ),
          if (!compact && scaleOnly)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '销售收入已走共用结算，这里只填规模。应付成本请新增明细。',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontSize: 11,
                ),
              ),
            ),
          if (!compact) ...[
            const SizedBox(height: 8),
            if (productSource == 'CHANNEL') ...[
              _skuSettleKindSection(
                label: '销售（收入）',
                kind: kProposalSkuSettleKindIncome,
                rows: [
                  for (final item in settlements)
                    if (!item.isCost) item,
                ],
                skuId: skuId,
                wide: wide,
                enabled: enabled,
                reviewPrefix: reviewPrefix,
                reviewItemPrefix: reviewItemPrefix,
                itemReviewLabel: itemReviewLabel,
                showItemReview: showItemReview,
                syncSource: syncSource,
                productSource: productSource,
                requireSchedule: false,
                linkSkus: linkSkus,
                onAdd: () => (onAddKind ?? ((_) => onAdd()))(
                  kProposalSkuSettleKindIncome,
                ),
                onRemove: onRemove,
                onPatch: onPatch,
              ),
              const SizedBox(height: 12),
              _skuSettleKindSection(
                label: '采购（成本）',
                kind: kProposalSkuSettleKindCost,
                rows: [
                  for (final item in settlements)
                    if (item.isCost) item,
                ],
                skuId: skuId,
                wide: wide,
                enabled: enabled,
                reviewPrefix: reviewPrefix,
                reviewItemPrefix: reviewItemPrefix,
                itemReviewLabel: itemReviewLabel,
                showItemReview: showItemReview,
                syncSource: syncSource,
                productSource: productSource,
                requireSchedule: false,
                linkSkus: linkSkus,
                onAdd: () =>
                    (onAddKind ?? ((_) => onAdd()))(kProposalSkuSettleKindCost),
                onRemove: onRemove,
                onPatch: onPatch,
              ),
            ] else ...[
              for (var i = 0; i < settlements.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _skuSettleTable(
                  skuId: skuId,
                  settle: settlements[i],
                  index: i,
                  wide: wide,
                  enabled:
                      enabled &&
                      !_skuSettleRowLocked(
                        reviewItemPrefix,
                        reviewPrefix,
                        skuId,
                        settlements[i].id,
                      ),
                  canRemove:
                      enabled &&
                      settlements.length > 1 &&
                      !_skuSettleRowLocked(
                        reviewItemPrefix,
                        reviewPrefix,
                        skuId,
                        settlements[i].id,
                      ),
                  reviewPrefix: reviewPrefix,
                  reviewItemPrefix: reviewItemPrefix,
                  itemReviewLabel: itemReviewLabel,
                  showItemReview: showItemReview,
                  syncSource: syncSource,
                  productSource: productSource,
                  requireSchedule: requireSchedule,
                  includeScale: includeScale,
                  scaleOnly: scaleOnly && i == 0,
                  linkSkus: linkSkus,
                  onRemove: () => onRemove(settlements[i].id),
                  onPatch: (terms) => onPatch(settlements[i].id, terms),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _settleSplitPair(Widget left, Widget right, {required bool stack}) {
    final line = DunesColors.resolve(context, ProposalPalette.borderSoft);
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          Container(
            height: 1,
            color: DunesColors.resolveNullable(
              context,
              line,
              role: DunesColorRole.surface,
            ),
          ),
          right,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          Container(
            width: 1,
            color: DunesColors.resolveNullable(
              context,
              line,
              role: DunesColorRole.surface,
            ),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _settleBlockCard({
    required int index,
    required bool wide,
    required Widget child,
    bool canRemove = false,
    VoidCallback? onRemove,
    Widget? headerTrailing,
    String labelKind = '结算',
  }) {
    final label = Text(
      proposalIntakeSettleLabel(index, kind: labelKind),
      textAlign: TextAlign.start,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: DunesColors.resolve(context, ProposalPalette.text),
        height: 1.25,
      ),
    );
    final deleteButton = canRemove && onRemove != null
        ? TextButton(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('删除', style: TextStyle(fontSize: 11)),
          )
        : null;
    final border = DunesColors.resolve(
      context,
      ProposalPalette.border,
      role: DunesColorRole.border,
    );
    if (!wide) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [label, ?deleteButton],
                  ),
                  ?headerTrailing,
                ],
              ),
            ),
            child,
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: DunesColors.resolve(
              context,
              ProposalPalette.soft,
              role: DunesColorRole.surface,
            ),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                Expanded(child: label),
                ?deleteButton,
                ?headerTrailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  /// 供给结算勾选适用的主产品，采购成本按「关联产品年化规模 × 该条比例」拆算。
  Widget _settleSkuPicker({
    required ProposalFinanceSettleTerms terms,
    required bool enabled,
    required ValueChanged<ProposalFinanceSettleTerms> onPatch,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '适用的$kProposalMainProductLabel：不勾则该条比例按全部产品规模计算采购成本。',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sku in proposalIntakeAllSellableSkus(_form))
                ProposalChoiceChip(
                  label: [
                    if (sku.productName.trim().isNotEmpty)
                      sku.productName.trim()
                    else
                      '未填写产品名称',
                    if (sku.faceValue.trim().isNotEmpty) sku.faceValue.trim(),
                  ].join(' · '),
                  selected: terms.skuIds.contains(sku.id),
                  enabled: enabled,
                  onSelected: enabled
                      ? (_) {
                          final next = [...terms.skuIds];
                          next.contains(sku.id)
                              ? next.remove(sku.id)
                              : next.add(sku.id);
                          onPatch(terms.copyWith(skuIds: next));
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skuSettleKindSection({
    required String label,
    required String kind,
    required List<ProposalSkuSettleRow> rows,
    required String skuId,
    required bool wide,
    required bool enabled,
    required String reviewPrefix,
    required String reviewItemPrefix,
    required String? itemReviewLabel,
    required bool showItemReview,
    required String syncSource,
    required String productSource,
    required bool requireSchedule,
    required bool linkSkus,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
    required void Function(String settleId, ProposalFinanceSettleTerms terms)
    onPatch,
  }) {
    return Column(
      key: ValueKey('sku-settle-kind-$skuId-$kind'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: DunesColors.resolve(context, ProposalPalette.text2),
                ),
              ),
            ),
            if (enabled)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: Text('新增$label'),
              ),
          ],
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '尚未填写$label',
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 12,
              ),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _skuSettleTable(
              skuId: skuId,
              settle: rows[i],
              index: i,
              wide: wide,
              enabled:
                  enabled &&
                  !_skuSettleRowLocked(
                    reviewItemPrefix,
                    reviewPrefix,
                    skuId,
                    rows[i].id,
                  ),
              canRemove:
                  enabled &&
                  !_skuSettleRowLocked(
                    reviewItemPrefix,
                    reviewPrefix,
                    skuId,
                    rows[i].id,
                  ),
              reviewPrefix: reviewPrefix,
              reviewItemPrefix: reviewItemPrefix,
              itemReviewLabel: itemReviewLabel,
              showItemReview: showItemReview,
              syncSource: syncSource,
              productSource: productSource,
              requireSchedule: requireSchedule,
              includeScale: false,
              scaleOnly: false,
              linkSkus: linkSkus,
              labelKind: label,
              simplified: true,
              onRemove: () => onRemove(rows[i].id),
              onPatch: (terms) => onPatch(rows[i].id, terms),
            ),
          ],
        ],
      ],
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
    String reviewItemPrefix = 'financeItem',
    String? itemReviewLabel,
    bool showItemReview = true,
    required String syncSource,
    required String productSource,
    required VoidCallback onRemove,
    required ValueChanged<ProposalFinanceSettleTerms> onPatch,
    bool requireSchedule = false,
    bool includeScale = false,
    bool scaleOnly = false,
    bool linkSkus = false,
    String labelKind = '结算',
    bool simplified = false,
  }) {
    final reviewToggle = showItemReview
        ? _rowReviewToggle(
            '$reviewItemPrefix:$reviewPrefix:$skuId:${settle.id}',
            itemReviewLabel ?? _financeReviewLabel,
          )
        : null;
    return _settleBlockCard(
      index: index,
      wide: wide,
      canRemove: canRemove,
      onRemove: onRemove,
      headerTrailing: reviewToggle,
      labelKind: labelKind,
      child: Builder(
        builder: (_) {
          final grid = _settleTermsGrid(
            wide: wide,
            keyPrefix: '$reviewPrefix-$skuId-${settle.id}',
            terms: settle.terms,
            enabled: enabled,
            includeParties: false,
            includeChannel: false,
            includeScale: simplified ? false : includeScale,
            scaleOnly: simplified ? false : scaleOnly,
            includeSalesFields: !simplified,
            includeSchedule: !simplified,
            includeCostType: simplified && settle.isCost,
            syncSource: syncSource,
            productSource: productSource,
            requireSchedule: simplified ? false : requireSchedule,
            onChanged: onPatch,
          );
          if (!linkSkus) return grid;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _settleSkuPicker(
                terms: settle.terms,
                enabled: enabled,
                onPatch: onPatch,
              ),
              grid,
            ],
          );
        },
      ),
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
    bool includeScale = false,
    bool includeSkuPick = false,
    bool includeSalesFields = true,
    bool includeInvoiceTax = true,
    bool includeFormula = true,
    bool includeSchedule = true,
    bool compactCostRules = false,
    bool scaleOnly = false,
    String syncSource = '',
    String productSource = 'CHANNEL',
    bool requireSchedule = false,
    bool includeCostType = false,
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
        ? '请先选择业务平台'
        : (loading ? '字典加载中…' : '该业务平台暂无选项');

    Widget field(
      String label,
      String value,
      ProposalFinanceSettleTerms Function(String) write, {
      String? hint,
      List<TextInputFormatter>? inputFormatters,
      TextInputType? keyboardType,
      bool fieldEnabled = true,
    }) {
      final interactive = enabled && fieldEnabled;
      final xorStamp = _settleXorStamp['$keyPrefix-$label'] ?? 0;
      return ProposalField(
        label: label,
        child: !interactive
            ? (!enabled
                  ? _readonlySelectedText(value)
                  : TextFormField(
                      key: ValueKey(
                        'settle-$keyPrefix-$label-locked-$_fieldEpoch-$xorStamp',
                      ),
                      initialValue: value,
                      enabled: false,
                      decoration: proposalInputDecoration(
                        context: context,
                        hint: hint ?? '已选另一项，此项不可填',
                        readOnly: true,
                      ),
                    ))
            : TextFormField(
                key: ValueKey(
                  'settle-$keyPrefix-$label-$_fieldEpoch-$xorStamp',
                ),
                initialValue: value,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onChanged: (next) => onChanged(write(next.trim())),
                decoration: proposalInputDecoration(
                  context: context,
                  hint: hint,
                ),
              ),
      );
    }

    Widget catalogField({
      required String label,
      required CatalogRef? current,
      required List<CatalogRef> options,
      required ProposalFinanceSettleTerms Function(CatalogRef?) write,
      String? Function(CatalogRef item)? metaOf,
      String? hint,
      String? emptyText,
    }) {
      final selected =
          _selectedCatalog(current, options) ??
          ((current != null && current.isNotEmpty) ? current : null);
      final values = _withCurrent(options, selected);
      return ProposalField(
        label: label,
        child: !enabled
            ? _readonlySelectedText(selected?.label ?? current?.label ?? '')
            : ProposalSelectField<CatalogRef>(
                key: ValueKey('settle-$keyPrefix-$label'),
                value: selected == null || selected.isEmpty ? null : selected,
                title: label,
                hint: hint ?? catalogHint,
                searchable: true,
                emptyText: emptyText ?? catalogEmptyText,
                options: [
                  for (final item in values)
                    ProposalSelectOption(
                      value: item,
                      label: item.label,
                      meta:
                          metaOf?.call(item) ??
                          (item.code.isEmpty || item.code == item.name
                              ? null
                              : item.code),
                    ),
                ],
                onSelected: (value) => onChanged(write(value)),
              ),
      );
    }

    final hasRatio = terms.displayRatio.trim().isNotEmpty;
    final hasPrice = terms.displayUnitPrice.trim().isNotEmpty;
    final useAdminFormulas = !includeSalesFields && includeFormula;
    final formulaOptions = useAdminFormulas
        ? widget.options.resolvedUnitPriceFormulas
        : [
            for (final item in bundle.formulas)
              if ((terms.settleModeRef == null ||
                      terms.settleModeRef!.isEmpty ||
                      item.settleMethod.isEmpty ||
                      item.settleMethod == terms.settleModeRef!.code) &&
                  _formulaMatchesSettleXor(
                    item,
                    hasRatio: hasRatio,
                    hasPrice: hasPrice,
                  ))
                item,
          ];

    Widget dateField(
      String label,
      String value,
      String fieldKey,
      ProposalFinanceSettleTerms Function(String) write,
    ) {
      final parsed = _parseDate(value);
      return _datePickerField(
        fieldKey: 'settle-$keyPrefix-$fieldKey',
        label: label,
        display: parsed == null ? value : _fmtDate(parsed),
        empty: value.trim().isEmpty,
        enabled: enabled,
        required: requireSchedule,
        onTap: !enabled
            ? null
            : () async {
                final picked = await _pickDate(parsed);
                if (picked != null) onChanged(write(_fmtDate(picked)));
              },
      );
    }

    Widget scalePeriodField() {
      final locked = kProposalScalePeriodLockedToYear;
      return ProposalField(
        label: '规模口径',
        child: locked || !enabled
            ? _readonlySelectedText(kProposalScalePeriodYear)
            : ProposalSelectField<String>(
                key: ValueKey('settle-$keyPrefix-scale-period'),
                value: terms.scalePeriod.isEmpty
                    ? kProposalScalePeriodYear
                    : terms.scalePeriod,
                title: '规模口径',
                hint: '请选择',
                options: [
                  for (final item in kProposalScalePeriods)
                    ProposalSelectOption(value: item, label: item),
                ],
                onSelected: (value) => onChanged(
                  terms.copyWith(
                    scalePeriod: value ?? kProposalScalePeriodYear,
                  ),
                ),
              ),
      );
    }

    if (scaleOnly) {
      return _fieldGrid(wide, [
        field(
          '规模（万元）',
          terms.scale,
          (value) => terms.copyWith(
            scale: value,
            scalePeriod: kProposalScalePeriodLockedToYear
                ? kProposalScalePeriodYear
                : terms.scalePeriod,
          ),
        ),
        scalePeriodField(),
      ], columns: wide ? 2 : 1);
    }

    final invoiceField = _settleStringSelectField(
      label: '发票类型',
      value: terms.invoiceType,
      options: kProposalInvoiceTypes,
      enabled: enabled,
      fieldKey: 'settle-$keyPrefix-invoice',
      onSelected: (value) =>
          onChanged(terms.copyWith(invoiceType: value ?? '')),
    );
    final taxField = _settleStringSelectField(
      label: '税率',
      value: terms.taxRate,
      options: kProposalTaxRates,
      enabled: enabled,
      fieldKey: 'settle-$keyPrefix-tax',
      onSelected: (value) => onChanged(terms.copyWith(taxRate: value ?? '')),
    );
    final effectiveField = dateField(
      '生效时间',
      terms.effectiveTime,
      'effective',
      (value) => terms.copyWith(effectiveTime: value),
    );
    final expireField = dateField(
      '失效时间',
      terms.expireTime,
      'expire',
      (value) => terms.copyWith(expireTime: value),
    );
    final ratioField = field(
      '结算比例',
      terms.displayRatio,
      (value) {
        final next = proposalIntakeApplySettleXor(terms, settleRatio: value);
        if (terms.displayUnitPrice.isNotEmpty &&
            next.displayUnitPrice.isEmpty) {
          final key = '$keyPrefix-结算单价';
          _settleXorStamp[key] = (_settleXorStamp[key] ?? 0) + 1;
        }
        return next;
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ProposalSettleRatioFormatter()],
      hint: hasPrice && !hasRatio ? '填写后将清空结算单价' : '填小数，如 0.08，不能填%',
    );
    final priceField = field('结算单价', terms.displayUnitPrice, (value) {
      final next = proposalIntakeApplySettleXor(terms, settleUnitPrice: value);
      if (terms.displayRatio.isNotEmpty && next.displayRatio.isEmpty) {
        final key = '$keyPrefix-结算比例';
        _settleXorStamp[key] = (_settleXorStamp[key] ?? 0) + 1;
      }
      return next;
    }, hint: hasRatio && !hasPrice ? '填写后将清空结算比例' : null);
    final costTypeField = _settleStringSelectField(
      label: '成本类型',
      value: terms.billType,
      options: _projectCostItemNames,
      enabled: enabled,
      fieldKey: 'settle-$keyPrefix-cost-type',
      onSelected: (value) => onChanged(
        terms.copyWith(
          billType: value ?? '',
          billTypeRef: value == null || value.trim().isEmpty
              ? null
              : CatalogRef.fromName(value),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (_, constraints) {
        final cols = math.min(
          columns ?? 4,
          _settleTermsColumnCount(constraints.maxWidth),
        );
        final stackPairs = cols <= 1;
        return _fieldGrid(wide, [
          if (includeChannel)
            catalogField(
              label: '渠道',
              current: terms.channelRef,
              options: bundle.channels,
              write: (value) => terms.copyWith(channelRef: value),
            ),
          if (includeSalesFields) ...[
            catalogField(
              label: '账单类型',
              current: terms.billTypeRef ?? CatalogRef.fromName(terms.billType),
              options: bundle.billTypes,
              write: (value) => terms.copyWith(
                billType: value?.name ?? '',
                billTypeRef: value,
              ),
            ),
            catalogField(
              label: '结算方式',
              current:
                  terms.settleModeRef ?? CatalogRef.fromName(terms.settleMode),
              options: bundle.settleMethods,
              write: (value) => terms.copyWith(
                settleMode: value?.name ?? '',
                settleModeRef: value,
                formula: '',
                formulaRef: null,
              ),
            ),
          ],
          if (includeCostType) costTypeField,
          if (compactCostRules)
            _FullWidthField(
              child: _settleSplitPair(
                ratioField,
                priceField,
                stack: stackPairs,
              ),
            )
          else ...[
            ratioField,
            priceField,
          ],
          if (includeScale) ...[
            field(
              '规模（万元）',
              terms.scale,
              (value) => terms.copyWith(
                scale: value,
                scalePeriod: kProposalScalePeriodLockedToYear
                    ? kProposalScalePeriodYear
                    : terms.scalePeriod,
              ),
            ),
            scalePeriodField(),
          ],
          if (includeFormula)
            catalogField(
              label: '计算公式',
              current: terms.formulaRef ?? CatalogRef.fromName(terms.formula),
              options: formulaOptions,
              hint: useAdminFormulas ? '请选择' : catalogHint,
              emptyText: useAdminFormulas ? '暂无计算公式' : catalogEmptyText,
              metaOf: (item) => item.formulaExpression.isEmpty
                  ? null
                  : item.formulaExpression,
              write: (value) => terms.copyWith(
                formula: value?.name ?? value?.formulaExpression ?? '',
                formulaRef: value,
              ),
            ),
          if (includeInvoiceTax) ...[invoiceField, taxField],
          if (includeSchedule)
            _FullWidthField(
              child: _settleSplitPair(
                effectiveField,
                expireField,
                stack: stackPairs,
              ),
            ),
          if (includeParties)
            _FullWidthField(
              child: _settleSplitPair(
                field(
                  '我方主体',
                  terms.ourParty,
                  (value) => terms.copyWith(ourParty: value),
                ),
                field(
                  '对方主体',
                  terms.counterparty,
                  (value) => terms.copyWith(counterparty: value),
                ),
                stack: stackPairs,
              ),
            ),
          if (proposalIntakeSettleIsTier(terms))
            _FullWidthField(
              child: field(
                '阶梯价格',
                terms.settleRule,
                (value) => terms.copyWith(settleRule: value),
                hint: '例如：0-100万 1.2%；100万以上 1.0%',
              ),
            ),
          if (includeSkuPick)
            _FullWidthField(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '关联$kProposalMainProductLabel',
                      style: TextStyle(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.text2,
                        ),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sku in proposalIntakeAllSellableSkus(_form))
                          ProposalChoiceChip(
                            label: [
                              if (sku.productName.trim().isNotEmpty)
                                sku.productName.trim()
                              else
                                '未填写产品名称',
                              if (sku.faceValue.trim().isNotEmpty)
                                sku.faceValue.trim(),
                            ].join(' · '),
                            selected: terms.skuIds.contains(sku.id),
                            enabled: enabled,
                            onSelected: enabled
                                ? (_) {
                                    final next = [...terms.skuIds];
                                    next.contains(sku.id)
                                        ? next.remove(sku.id)
                                        : next.add(sku.id);
                                    onChanged(terms.copyWith(skuIds: next));
                                  }
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ], columns: cols);
      },
    );
  }

  Widget _settleStringSelectField({
    required String label,
    required String value,
    required List<String> options,
    required bool enabled,
    required ValueChanged<String?> onSelected,
    String? fieldKey,
  }) {
    final current = value.trim();
    final values = [
      if (current.isNotEmpty && !options.contains(current)) current,
      ...options,
    ];
    return ProposalField(
      label: label,
      child: !enabled
          ? _readonlySelectedText(current)
          : ProposalSelectField<String>(
              key: ValueKey(fieldKey ?? 'settle-$label'),
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
              Text(
                '产品模板',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text),
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
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.purpleDeep,
                    ),
                  ),
                  child: const Text('刷新'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_importTemplatesError != null && _importTemplates.isEmpty)
            Text(
              _importTemplatesError!,
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.coral),
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
          Text(
            '与提案审批相同：数商 / 运营商 / 出行-订阅 / 出行-权益金 / 民营。',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
            ),
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
                    ? Border.all(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.purple,
                          role: DunesColorRole.border,
                        ),
                        width: 1.4,
                      )
                    : null,
                color: _draggingProduct
                    ? DunesColors.resolve(
                        context,
                        ProposalPalette.purpleSoft,
                        role: DunesColorRole.surface,
                      ).withValues(alpha: 0.35)
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
                                context: context,
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
                                      ? DunesColors.resolve(
                                          context,
                                          ProposalPalette.purple,
                                        )
                                      : DunesColors.resolve(
                                          context,
                                          ProposalPalette.text3,
                                        ),
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
                            style: TextStyle(
                              fontSize: 13,
                              color: DunesColors.resolve(
                                context,
                                ProposalPalette.text3,
                              ),
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
                      style: kProposalCaptionStyle,
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
    // 新样式不再显示「已改过抓取内容，点击对照合同原文」。
    if (_protoForm) return null;
    final edit = proposalIntakeContractEdit(_form, key);
    if (edit == null) return null;
    return InkWell(
      onTap: () => unawaited(_showContractDiff(key, edit)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.difference_outlined,
              size: 16,
              color: DunesColors.resolve(context, ProposalPalette.amber),
            ),
            const SizedBox(width: 6),
            Text(
              '已改过抓取内容，点击对照合同原文',
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolve(context, ProposalPalette.amber),
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
      builder: (ctx) => ProposalContractDiffDialog(
        label: label,
        original: edit.original,
        current: edit.current,
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
      'salesInvoiceType': '销售合同发票类型',
      'salesInvoiceFlow': '销售合同发票流',
    };
    return labels[key] ?? key;
  }

  static const _unsignedFileExts = <String>['pdf', 'doc', 'docx'];
  static const _maxUnsignedFileBytes = 20 * 1024 * 1024;
  static const _maxUnsignedFiles = 10;

  bool _allowedUnsignedFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return false;
    return _unsignedFileExts.contains(name.substring(dot + 1).toLowerCase());
  }

  bool _isPdfContractFile(String name) =>
      name.trim().toLowerCase().endsWith('.pdf');

  List<Map<String, dynamic>> _contractFiles(String prefix) =>
      proposalIntakeContractFiles(_form, prefix);

  bool _hasContractSourceFile(String prefix) =>
      _contractFiles(prefix).isNotEmpty;

  String _contractLabelForFile(String prefix, Map<String, dynamic> file) {
    final id = (file['contractId'] as num?)?.toInt() ?? 0;
    if (id <= 0) return '';
    for (final ref in proposalIntakeSelectedContractRefs(_form, prefix)) {
      if (_proposalContractRefId(ref) == id) {
        return proposalIntakeContractRefLabel(ref);
      }
    }
    return '';
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
    if (!_canEditContractExtras(prefix) || _uploadingContractPrefix != null) {
      return;
    }
    final room = _maxUnsignedFiles - _contractFiles(prefix).length;
    if (room <= 0) {
      widget.onError('最多上传 $_maxUnsignedFiles 个合同文件');
      return;
    }
    setState(() => _uploadingContractPrefix = prefix);
    try {
      final group = XTypeGroup(label: '合同文件', extensions: _unsignedFileExts);
      List<XFile> picked = const [];
      try {
        picked = await openFiles(acceptedTypeGroups: [group]);
      } catch (_) {
        picked = await openFiles();
      }
      if (picked.isEmpty) return;
      await _ingestUnsignedFiles(prefix, picked, room: room);
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
    if (!_canEditContractExtras(prefix) || _uploadingContractPrefix != null) {
      return;
    }
    final room = _maxUnsignedFiles - _contractFiles(prefix).length;
    if (room <= 0) {
      widget.onError('最多上传 $_maxUnsignedFiles 个合同文件');
      return;
    }
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
      await _ingestUnsignedFiles(prefix, picked, room: room);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '拖拽上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingContractPrefix = null);
    }
  }

  Future<void> _ingestUnsignedFiles(
    String prefix,
    List<XFile> picked, {
    required int room,
  }) async {
    final current = _contractFiles(prefix);
    final next = [...current];
    final names = <String>[];
    for (final file in picked.take(room)) {
      final name = file.name.isEmpty ? 'contract.pdf' : file.name;
      if (!_allowedUnsignedFile(name)) {
        widget.onError('请上传 PDF 或 Word 文件：$name');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUnsignedFileBytes) {
        widget.onError('$name 超过 20MB 限制');
        continue;
      }
      final uploaded = await widget.service.uploadFile(
        bytes: bytes,
        fileName: name,
        mimeType: _unsignedFileMime(name),
      );
      if (uploaded.objectKey.isEmpty && uploaded.url.isEmpty) {
        throw Exception('未返回文件地址');
      }
      next.add({
        'fileName': uploaded.fileName,
        'objectKey': uploaded.objectKey,
        'url': uploaded.url,
        'fileUrl': uploaded.url,
        'sizeBytes': uploaded.sizeBytes,
      });
      names.add(uploaded.fileName);
    }
    if (!mounted || names.isEmpty) return;
    var form = proposalIntakeSetContractFiles(
      _form,
      prefix: prefix,
      files: next,
    );
    if (_text('${prefix}No').isEmpty && names.isNotEmpty) {
      form['${prefix}No'] = names.first;
    }
    final review = proposalIntakeClearContractReview(_review, prefix: prefix);
    setState(() {
      _markFormDirty();
      _fieldEpoch++;
      _row = _row.copyWith(
        form: form,
        review: review,
        status: _statusAfterEdit,
      );
    });
    _emitChanged(_row);
    showProposalCenterToast(
      context,
      names.length == 1 ? '已上传「${names.first}」' : '已上传 ${names.length} 个合同文件',
    );
  }

  void _clearUnsignedFile(String prefix, [int? index]) {
    if (!_canEditContractExtras(prefix)) return;
    final current = _contractFiles(prefix);
    if (current.isEmpty) return;
    final next = [...current];
    final removeAt = index ?? 0;
    if (removeAt < 0 || removeAt >= next.length) return;
    final removed = next.removeAt(removeAt);
    var form = proposalIntakeSetContractFiles(
      _form,
      prefix: prefix,
      files: next,
    );
    final removedName = '${removed['fileName'] ?? ''}'.trim();
    if (next.isEmpty && _text('${prefix}No') == removedName) {
      form['${prefix}No'] = '';
    } else if (next.isNotEmpty &&
        removeAt == 0 &&
        _text('${prefix}No') == removedName) {
      form['${prefix}No'] = '${next.first['fileName'] ?? ''}'.trim();
    }
    final review = proposalIntakeClearContractReview(_review, prefix: prefix);
    setState(() {
      _markFormDirty();
      _fieldEpoch++;
      _row = _row.copyWith(
        form: form,
        review: review,
        status: _statusAfterEdit,
      );
    });
    _emitChanged(_row);
  }

  Map<String, dynamic>? _firstPreviewableContractFile(
    List<Map<String, dynamic>> files,
  ) {
    for (final file in files) {
      if (_isPdfContractFile('${file['fileName'] ?? ''}')) return file;
    }
    return files.firstOrNull;
  }

  List<Map<String, dynamic>> _filesForContractRef(
    String prefix,
    Map<String, dynamic> ref,
  ) {
    final owned = proposalIntakeFilesOfContractRef(ref);
    if (owned.isNotEmpty) return owned;
    final id = _proposalContractRefId(ref);
    final all = _contractFiles(prefix);
    if (id > 0) {
      final matched = [
        for (final file in all)
          if (id > 0 &&
              ((file['contractId'] as num?)?.toInt() ??
                      int.tryParse('${file['contractId'] ?? ''}') ??
                      0) ==
                  id)
            file,
      ];
      if (matched.isNotEmpty) return matched;
    }
    return all;
  }

  String get _contractPreviewWatermark {
    final viewer = (widget.session.displayName ?? '').trim();
    return [
      if (viewer.isNotEmpty) viewer,
      if (_row.code.trim().isNotEmpty) _row.code.trim(),
      '仅供内部查阅',
    ].join(' · ');
  }

  Future<void> _showContractPdf({
    required Uint8List bytes,
    required String fileName,
  }) {
    return showContractKbPdfPreview(
      context: context,
      fileName: fileName.isEmpty ? '合同文件.pdf' : fileName,
      bytes: bytes,
      watermark: _contractPreviewWatermark,
    );
  }

  /// PDF 内部预览；Word 等在 PC 用系统应用打开，APP 用其他软件打开。
  Future<void> _openContractAttachment({
    required String name,
    required String objectKey,
    required String url,
  }) async {
    final fileName = name.trim().isEmpty ? '合同文件.pdf' : name.trim();
    final item = <String, dynamic>{
      'fileName': fileName,
      'objectKey': objectKey,
      'url': url,
      'mimeType': _unsignedFileMime(fileName),
    };
    if (_isPdfContractFile(fileName)) {
      final bytes = await fetchXflowAttachmentBytes(
        service: XflowService(session: widget.session),
        item: item,
      );
      if (!mounted) return;
      await _showContractPdf(bytes: bytes, fileName: fileName);
      return;
    }
    await openXflowAttachment(
      context: context,
      service: XflowService(session: widget.session),
      item: item,
    );
  }

  /// 复核人也可预览：与合同归集「查看」相同，先拉知识库 PDF，没有再回退附件。
  Future<void> _previewSelectedContract(
    String prefix, [
    Map<String, dynamic>? ref,
  ]) async {
    final refs = proposalIntakeSelectedContractRefs(_form, prefix);
    final target = ref ?? refs.firstOrNull;
    final id = target == null ? 0 : _proposalContractRefId(target);
    if (_openingContractPrefix != null) return;
    setState(() => _openingContractPrefix = prefix);
    try {
      Object? kbError;
      if (id > 0) {
        try {
          final bytes = await ContractRegisterService(
            session: widget.session,
          ).previewKbFile(id);
          if (!mounted) return;
          final kbName = target == null
              ? ''
              : '${target['contractNo'] ?? ''}'.trim();
          await _showContractPdf(
            bytes: Uint8List.fromList(bytes),
            fileName: kbName.isEmpty ? '合同文件.pdf' : '$kbName.pdf',
          );
          return;
        } catch (error) {
          kbError = error;
        }
      }
      var files = target == null
          ? _contractFiles(prefix)
          : _filesForContractRef(prefix, target);
      if (files.isEmpty && id > 0) {
        final detail = await widget.service.fetchContractDetail(id);
        files = proposalIntakeFilesFromContractDetail(detail);
        if (files.isEmpty) {
          final fallback = proposalIntakeContractFileMap({
            'fileName': detail['fileName'],
            'objectKey': detail['objectKey'],
            'url': detail['fileUrl'] ?? detail['url'],
          });
          if (!proposalIntakeContractFileIsEmpty(fallback)) {
            files = [fallback];
          }
        }
      }
      if (files.isEmpty) {
        widget.onError(friendlyErrorText(kbError, fallback: '该合同还没有可预览的源文件'));
        return;
      }
      final file = _firstPreviewableContractFile(files);
      final name = '${file?['fileName'] ?? ''}'.trim();
      final objectKey = '${file?['objectKey'] ?? ''}'.trim();
      final url = '${file?['url'] ?? file?['fileUrl'] ?? ''}'.trim();
      if (objectKey.isEmpty && url.isEmpty) {
        widget.onError('该合同还没有可预览的源文件');
        return;
      }
      await _openContractAttachment(name: name, objectKey: objectKey, url: url);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '无法预览合同文件'));
    } finally {
      if (mounted && _openingContractPrefix == prefix) {
        setState(() => _openingContractPrefix = null);
      }
    }
  }

  Future<void> _openContractSourceFile(
    String prefix, [
    Map<String, dynamic>? file,
  ]) async {
    final target = file ?? _contractFiles(prefix).firstOrNull;
    final name = '${target?['fileName'] ?? _text('${prefix}FileName')}'.trim();
    final objectKey = '${target?['objectKey'] ?? _text('${prefix}ObjectKey')}'
        .trim();
    final url =
        '${target?['url'] ?? target?['fileUrl'] ?? _text('${prefix}FileUrl')}'
            .trim();
    if (name.isEmpty && objectKey.isEmpty && url.isEmpty) {
      widget.onError('还没有合同源文件');
      return;
    }
    if (_openingContractPrefix != null) return;
    setState(() => _openingContractPrefix = prefix);
    try {
      await _openContractAttachment(name: name, objectKey: objectKey, url: url);
    } catch (error) {
      widget.onError(friendlyErrorText(error, fallback: '无法预览合同文件'));
    } finally {
      if (mounted) setState(() => _openingContractPrefix = null);
    }
  }

  Widget _contractSourceFileField(String prefix, {required bool allowUpload}) {
    final enabled = _canEditContractExtras(prefix) && allowUpload;
    final uploading = _uploadingContractPrefix == prefix;
    final opening = _openingContractPrefix == prefix;
    final dragging = _draggingUnsignedPrefix == prefix;
    final files = _contractFiles(prefix);
    final canOpen = files.isNotEmpty;
    final canFetchSigned =
        !allowUpload &&
        proposalIntakeSelectedContractIds(_form, prefix).isNotEmpty;
    final signed = !allowUpload;
    final source = !canOpen
        ? (canFetchSigned ? '已签合同 · 点「查看合同」打开源文件' : '未签合同 · 可上传多份 PDF / Word')
        : (signed ? '已签合同 · 点击文件打开' : '未签合同 · 点击文件用系统应用打开');
    Widget fileRow(Map<String, dynamic> file, int index) {
      final fileName = '${file['fileName'] ?? ''}'.trim();
      final contractLabel = _contractLabelForFile(prefix, file);
      final previewable = fileName.isEmpty || _isPdfContractFile(fileName);
      final objectKey = '${file['objectKey'] ?? ''}'.trim();
      final url = '${file['url'] ?? file['fileUrl'] ?? ''}'.trim();
      final canPreviewThis = objectKey.isNotEmpty || url.isNotEmpty;
      return InkWell(
        onTap: opening || !canPreviewThis
            ? null
            : () => unawaited(_openContractSourceFile(prefix, file)),
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: proposalInputDecoration(context: context, readOnly: true),
          child: Row(
            children: [
              Icon(
                previewable
                    ? Icons.picture_as_pdf_outlined
                    : Icons.description_outlined,
                size: 16,
                color: DunesColors.resolve(context, ProposalPalette.purple),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.isEmpty ? '合同源文件' : fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: canPreviewThis
                            ? DunesColors.resolve(
                                context,
                                ProposalPalette.purpleDeep,
                              )
                            : DunesColors.resolve(
                                context,
                                ProposalPalette.text,
                              ),
                        fontWeight: FontWeight.w600,
                        decoration: canPreviewThis
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                    if (contractLabel.isNotEmpty)
                      Text(
                        contractLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kProposalCaptionStyle,
                      ),
                  ],
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
                  onPressed: () => _clearUnsignedFile(prefix, index),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                ),
            ],
          ),
        ),
      );
    }

    final picker = files.isEmpty && allowUpload
        ? InkWell(
            onTap: enabled && !uploading
                ? () => unawaited(_pickUnsignedFile(prefix))
                : null,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration:
                  proposalInputDecoration(
                    context: context,
                    hint: uploading ? '上传中…' : '选择 PDF / Word 文件',
                    readOnly: !enabled,
                  ).copyWith(
                    suffixIcon: Icon(
                      uploading
                          ? Icons.hourglass_top_rounded
                          : Icons.upload_file_outlined,
                      size: 18,
                      color: enabled
                          ? DunesColors.resolve(context, ProposalPalette.purple)
                          : DunesColors.resolve(context, ProposalPalette.text3),
                    ),
                  ),
              child: Text(
                uploading
                    ? '上传中…'
                    : (_supportsDesktopDrop
                          ? '点击选择或拖拽未签合同 PDF / Word'
                          : '点击选择未签合同 PDF / Word'),
                style: TextStyle(
                  fontSize: 13,
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        : files.isEmpty
        ? InputDecorator(
            decoration: proposalInputDecoration(
              context: context,
              readOnly: true,
            ),
            child: Text(
              canFetchSigned ? '点击「查看合同」预览合同归集中的源文件' : '还没有合同源文件',
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.resolve(context, ProposalPalette.text3),
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < files.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                fileRow(files[i], i),
              ],
              if (enabled) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: uploading
                      ? null
                      : () => unawaited(_pickUnsignedFile(prefix)),
                  icon: Icon(
                    uploading
                        ? Icons.hourglass_top_rounded
                        : Icons.upload_file_outlined,
                    size: 16,
                  ),
                  label: Text(uploading ? '上传中…' : '继续上传合同'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.purpleDeep,
                    ),
                  ),
                ),
              ],
            ],
          );
    return _FullWidthField(
      child: ProposalField(
        label: allowUpload ? '上传合同文件' : '合同源文件',
        required: allowUpload,
        source: source,
        tone: proposalFieldTone(
          enabled: enabled || canOpen || canFetchSigned,
          source: source,
        ),
        trailing: canOpen || canFetchSigned
            ? TextButton.icon(
                onPressed: opening
                    ? null
                    : () => unawaited(
                        canOpen
                            ? _openContractSourceFile(prefix, files.firstOrNull)
                            : _previewSelectedContract(prefix),
                      ),
                icon: Icon(
                  opening
                      ? Icons.hourglass_top_rounded
                      : Icons.visibility_outlined,
                  size: 16,
                ),
                label: Text(opening ? '打开中…' : '查看合同'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: DunesColors.resolve(
                    context,
                    ProposalPalette.purpleDeep,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              )
            : null,
        child: _dropTarget(
          enabled: enabled && !uploading,
          dragging: dragging,
          onHover: (hover) =>
              setState(() => _draggingUnsignedPrefix = hover ? prefix : null),
          onDrop: (detail) => _onUnsignedFileDropped(prefix, detail),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: dragging
                  ? Border.all(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.purple,
                        role: DunesColorRole.border,
                      ),
                      width: 1.4,
                    )
                  : null,
              color: dragging
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.purpleSoft,
                      role: DunesColorRole.surface,
                    ).withValues(alpha: 0.35)
                  : null,
            ),
            child: picker,
          ),
        ),
      ),
    );
  }

  Widget _moduleReview({
    Key? key,
    required String title,
    required String description,
    required String keyName,
    required String buttonLabel,
    bool locked = false,
    bool compact = false,
    String? progress,
    List<String> omissions = const [],
    Future<void> Function(List<String> gaps)? onCheckOmissions,
    bool plain = false,
  }) {
    final done = _review[keyName] == true;
    // 复制或新建的提案在填写阶段复核项全是空的，列出来会被误读成字段没填。
    final showOmissions =
        !done &&
        _isReviewing &&
        omissions.isNotEmpty &&
        onCheckOmissions != null;
    if (_protoForm) {
      return _protoModuleReview(
        key: key,
        title: title,
        description: description,
        keyName: keyName,
        buttonLabel: buttonLabel,
        locked: locked,
        compact: compact,
        progress: progress,
        omissions: omissions,
        onCheckOmissions: onCheckOmissions,
        done: done,
        showOmissions: showOmissions,
      );
    }
    return Container(
      key: key,
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 0 : 14, top: compact ? 4 : 0),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: plain
            ? DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              )
            : null,
        gradient: plain
            ? null
            : LinearGradient(
                colors: [
                  DunesColors.resolve(
                    context,
                    ProposalPalette.app,
                    role: DunesColorRole.surface,
                  ),
                  DunesColors.resolve(
                    context,
                    ProposalPalette.purpleSoft,
                    role: DunesColorRole.surface,
                  ),
                ],
              ),
        border: Border.all(
          color: plain
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                )
              : done
              ? DunesColors.resolve(
                  context,
                  const Color(0xFFB9DDBE),
                  role: DunesColorRole.border,
                )
              : locked
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.borderStrong,
                  role: DunesColorRole.border,
                ),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = ProposalLayout.isCompact(constraints.maxWidth);
          final reviewerCanAct = _moduleReviewEnabled(keyName);
          final canApprove = reviewerCanAct && !locked && !done;
          final canReject = reviewerCanAct;
          final approveChild = Text(
            done ? '已复核' : buttonLabel,
            style: TextStyle(
              fontSize: canApprove ? 12 : 10,
              fontWeight: canApprove ? FontWeight.w700 : FontWeight.w400,
            ),
          );
          final approveButton = canApprove
              ? FilledButton(
                  key: ValueKey('proposal-module-approve-$keyName'),
                  onPressed: () => unawaited(_setReview(keyName, true)),
                  style: FilledButton.styleFrom(
                    backgroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.purple,
                      role: DunesColorRole.surface,
                    ),
                    foregroundColor: DunesColors.resolve(context, Colors.white),
                  ),
                  child: approveChild,
                )
              : OutlinedButton(
                  key: ValueKey('proposal-module-approve-$keyName'),
                  onPressed: null,
                  child: approveChild,
                );
          final action = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              approveButton,
              if (showOmissions)
                OutlinedButton(
                  key: ValueKey('proposal-module-omissions-$keyName'),
                  onPressed: () => unawaited(onCheckOmissions(omissions)),
                  child: const Text('检查遗漏', style: TextStyle(fontSize: 10)),
                ),
              if (canReject)
                OutlinedButton(
                  key: ValueKey('proposal-module-reject-$keyName'),
                  onPressed: () => unawaited(_rejectReview(keyName)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.coral,
                    ),
                    side: BorderSide(
                      color: DunesColors.resolve(
                        context,
                        Color(0xFFE7C2B0),
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                  child: const Text('驳回', style: TextStyle(fontSize: 10)),
                ),
            ],
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: kProposalBlockTitleStyle),
              Text(description, style: kProposalCaptionStyle),
              if (showOmissions)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: () => unawaited(onCheckOmissions(omissions)),
                    child: Text(
                      '检查遗漏：还有 ${omissions.length} 项未复核（${omissions.join('、')}）',
                      style: kProposalCaptionStyle.copyWith(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.coral,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else if (!done &&
                  !locked &&
                  progress != null &&
                  omissions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '逐条复核已完成，点右侧确认本板块。点保存不会结束复核。',
                    style: kProposalCaptionStyle.copyWith(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.purpleDeep,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!done && locked && canReject)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '发现问题可直接点「驳回」；通过需先完成逐条复核。',
                    style: kProposalCaptionStyle.copyWith(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.coral,
                      ),
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
              color: done
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.greenSoft,
                      role: DunesColorRole.surface,
                    )
                  : (plain
                        ? DunesColors.resolve(
                            context,
                            ProposalPalette.soft,
                            role: DunesColorRole.surface,
                          )
                        : DunesColors.resolve(
                            context,
                            ProposalPalette.purpleSoft,
                            role: DunesColorRole.surface,
                          )),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check : Icons.fact_check_outlined,
              color: done
                  ? DunesColors.resolve(context, ProposalPalette.green)
                  : DunesColors.resolve(context, ProposalPalette.purpleDeep),
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
                    kind: _moduleReviewChipKind(done: done, plain: plain),
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
                  kind: _moduleReviewChipKind(done: done, plain: plain),
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

  /// 原型复核页的板块横幅：标签 + 标题 + 说明 + 进度，按钮在下面一行靠右。
  /// 按钮、逻辑与原卡片完全一样，只换样式。
  Widget _protoModuleReview({
    Key? key,
    required String title,
    required String description,
    required String keyName,
    required String buttonLabel,
    required bool locked,
    required bool compact,
    required String? progress,
    required List<String> omissions,
    required Future<void> Function(List<String> gaps)? onCheckOmissions,
    required bool done,
    required bool showOmissions,
  }) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final reviewerCanAct = _moduleReviewEnabled(keyName);
    final canApprove = reviewerCanAct && !locked && !done;
    final canReject = reviewerCanAct;
    final tag = done ? '已通过' : (reviewerCanAct ? '待你复核' : '待复核');
    final tagBg = done ? 0xFF3B8B5A : 0xFF6B4FD8;
    final hint = showOmissions
        ? '还有 ${omissions.length} 项未复核（${omissions.join('、')}）'
        : (!done && !locked && progress != null && omissions.isEmpty)
        ? '逐条复核已完成，点「$buttonLabel」确认本板块。点保存不会结束复核。'
        : (!done && locked && canReject)
        ? '发现问题可直接驳回本板块；通过需先完成逐条复核。'
        : '';
    ButtonStyle outline(int border, int fg) => OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      foregroundColor: c(fg),
      backgroundColor: c(0xFFFFFFFF, DunesColorRole.surface),
      side: BorderSide(color: c(border, DunesColorRole.border)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
    return Container(
      key: key,
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 0 : 14, top: compact ? 4 : 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c(done ? 0xFFEEF6F1 : 0xFFF7F5FC, DunesColorRole.surface),
        border: Border.all(
          color: c(done ? 0xFFB9DDBE : 0xFFE7E3F2, DunesColorRole.border),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c(tagBg, DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: c(0xFFFFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  color: c(done ? 0xFF2D6E47 : 0xFF3F2A9A),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (progress != null)
                Text(
                  done ? '板块审核完成' : progress,
                  style: TextStyle(
                    color: c(done ? 0xFF2D6E47 : 0xFFB4570F),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: kProposalProtoMono,
                    fontFamilyFallback: kProposalProtoMonoFallback,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(color: c(0xFF5B556A), fontSize: 12, height: 1.5),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: showOmissions
                  ? () => unawaited(onCheckOmissions!(omissions))
                  : null,
              child: Text(
                hint,
                style: TextStyle(
                  color: c(showOmissions || locked ? 0xFFB4570F : 0xFF3F2A9A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canReject)
                OutlinedButton(
                  key: ValueKey('proposal-module-reject-$keyName'),
                  onPressed: () => unawaited(_rejectReview(keyName)),
                  style: outline(0xFFF0C9A0, 0xFF9A3412),
                  child: const Text('驳回本板块'),
                ),
              if (showOmissions)
                OutlinedButton(
                  key: ValueKey('proposal-module-omissions-$keyName'),
                  onPressed: () => unawaited(onCheckOmissions!(omissions)),
                  style: outline(0xFFCFC2F5, 0xFF3F2A9A),
                  child: const Text('检查遗漏'),
                ),
              FilledButton(
                key: ValueKey('proposal-module-approve-$keyName'),
                onPressed: canApprove
                    ? () => unawaited(_setReview(keyName, true))
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: c(0xFF6B4FD8, DunesColorRole.surface),
                  foregroundColor: c(0xFFFFFFFF),
                  disabledBackgroundColor: c(
                    0xFFE7E3F2,
                    DunesColorRole.surface,
                  ),
                  disabledForegroundColor: c(0xFF8A8499),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(done ? '已复核' : buttonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 白底复核卡里的进度徽标走灰阶，紫色留给真正需要拉注意力的渐变卡。
  ProposalChipKind _moduleReviewChipKind({
    required bool done,
    required bool plain,
  }) {
    if (done) return ProposalChipKind.ok;
    return plain ? ProposalChipKind.normal : ProposalChipKind.purple;
  }

  bool _isFinanceLongTextKey(String key) => key == 'financeRemark';

  Widget _financeReviewToolbar({required bool children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                children
                    ? '$kProposalChildProductLabel财务复核'
                    : '$kProposalMainProductLabel财务复核',
                style: kProposalSubBlockTitleStyle,
              ),
            ),
            _financeReviewModeButton(),
            const SizedBox(width: 8),
            Text(
              _review['financeCompleted'] == true ? '财务部复核已完成' : '待财务部负责人二逐项复核',
              style: kProposalCaptionStyle,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('先核产品结算，再核合计收入成本。', style: kProposalCaptionStyle),
        ),
      ],
    );
  }

  /// 逐条复核的总开关：关掉时字段旁只留圆点，打开才显示复核 / 驳回按钮。
  Widget _financeReviewModeButton() {
    final on = _financeReviewMode;
    return InkWell(
      onTap: () => setState(() => _financeReviewMode = !on),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: on
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.purpleSoft,
                  role: DunesColorRole.surface,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.card,
                  role: DunesColorRole.surface,
                ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: on
                ? DunesColors.resolve(
                    context,
                    ProposalPalette.purpleLine,
                    role: DunesColorRole.border,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.border,
                    role: DunesColorRole.border,
                  ),
          ),
        ),
        child: Text(
          on ? '退出逐条复核' : '开始逐条复核',
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: on
                ? DunesColors.resolve(context, ProposalPalette.purpleDeep)
                : DunesColors.resolve(context, ProposalPalette.text2),
          ),
        ),
      ),
    );
  }

  Widget _financeFieldRows(List<(String, String)> fields, int columns) {
    final rows = <List<(String, String)>>[];
    var current = <(String, String)>[];
    for (final field in fields) {
      if (_isFinanceLongTextKey(field.$1)) {
        if (current.isNotEmpty) {
          rows.add(current);
          current = <(String, String)>[];
        }
        rows.add([field]);
        continue;
      }
      current.add(field);
      if (current.length == columns) {
        rows.add(current);
        current = <(String, String)>[];
      }
    }
    if (current.isNotEmpty) rows.add(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < row.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: _financeItem(row[index])),
              ],
              if (row.length < columns &&
                  (row.length != 1 || !_isFinanceLongTextKey(row.first.$1)))
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
      ],
    );
  }

  Widget _financeSideGroup({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 1,
            color: DunesColors.resolve(
              context,
              ProposalPalette.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text2),
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  String? _financeMetricFormula(String key) {
    return switch (key) {
      'salesScale' => kProposalSalesScaleFormula,
      'revenue' => kProposalRevenueFormula,
      'couponProcurementCost' => kProposalProcurementFormula,
      'profit' => kProposalProfitFormula,
      'margin' => kProposalMarginFormula,
      'turnoverCash' => kProposalTurnoverCashFormula,
      _ => null,
    };
  }

  ({String display, String formula})? _financeComputedMetric(
    String key, {
    Map<String, dynamic>? formOverride,
  }) {
    final form = formOverride ?? _form;
    switch (key) {
      case 'turnoverCash':
        final cash = proposalTurnoverCashAmount(form);
        return (
          display: cash == null ? '' : proposalFormatWan(cash),
          formula: kProposalTurnoverCashFormula,
        );
      case 'couponProcurementCost':
        final estimated = proposalEstimatedProcurementCost(form);
        if (estimated == null) return null;
        return (
          display: proposalFormatWan(estimated),
          formula: kProposalProcurementFormula,
        );
      case 'salesScale':
        final rollup = proposalProductScaleRollup(form);
        return (
          display: rollup == null ? '' : proposalFormatWan(rollup.salesScale),
          formula: kProposalSalesScaleFormula,
        );
      case 'revenue':
        final rollup = proposalProductScaleRollup(form);
        return (
          display: rollup == null ? '' : proposalFormatWan(rollup.revenue),
          formula: kProposalRevenueFormula,
        );
      case 'profit':
        final rollup = proposalProductScaleRollup(form);
        final procurement =
            proposalEstimatedProcurementCost(form) ??
            proposalFinanceAmount(form, kProposalCouponProcurementCostKey);
        final revenue = proposalEffectiveRevenue(form);
        return (
          display: rollup == null && !proposalRevenueIsManual(form)
              ? ''
              : proposalFormatWan(
                  proposalRoundWan(
                    revenue -
                        procurement -
                        proposalFinanceAmount(form, 'projectCost'),
                  ),
                ),
          formula: kProposalProfitFormula,
        );
      case 'margin':
        final rollup = proposalProductScaleRollup(form);
        final scale = rollup?.salesScale ?? proposalEffectiveSalesScale(form);
        if ((rollup == null && !proposalRevenueIsManual(form)) || scale == 0) {
          return (
            display: rollup == null && !proposalRevenueIsManual(form)
                ? ''
                : '0',
            formula: kProposalMarginFormula,
          );
        }
        final procurement =
            proposalEstimatedProcurementCost(form) ??
            proposalFinanceAmount(form, kProposalCouponProcurementCostKey);
        final profit = proposalRoundWan(
          proposalEffectiveRevenue(form) -
              procurement -
              proposalFinanceAmount(form, 'projectCost'),
        );
        return (
          display: proposalFormatWan(
            proposalEstimatedMarginAmount(
              form,
              salesScale: scale,
              profit: profit,
            ),
          ),
          formula: kProposalMarginFormula,
        );
      default:
        return null;
    }
  }

  Widget _financeItem((String, String) field) {
    final key = field.$1;
    final computed = _financeComputedMetric(key);
    if (computed != null) {
      return _anchor(
        key,
        Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                ),
              ),
            ),
          ),
          child: ProposalField(
            label: field.$2,
            formula: computed.formula ?? _financeMetricFormula(key),
            tone: proposalFieldTone(enabled: false),
            trailing: _rowReviewToggle('financeItem:$key', _financeReviewLabel),
            child: _readonlySelectedText(computed.display),
          ),
        ),
      );
    }
    if (key == 'supplySettleMode' || key == 'channelSettleMode') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: DunesColors.resolve(
                context,
                ProposalPalette.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        child: _dropdownField(
          field.$2,
          key,
          widget.options.resolvedSettleModes,
          required: true,
          addLabel: '新增结算模式',
          writable: _canEditUnreviewedFinance,
          resetReview: 'financeCompleted',
          reviewSection: 'financeItem:$key',
          reviewLabel: _financeReviewLabel,
        ),
      );
    }
    if (key == 'supplySettleCycle' || key == 'channelSettleCycle') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: DunesColors.resolve(
                context,
                ProposalPalette.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        child: _dropdownField(
          field.$2,
          key,
          widget.options.resolvedSettleCycles,
          required: true,
          addLabel: '新增结算周期',
          writable: _canEditUnreviewedFinance,
          resetReview: 'financeCompleted',
          reviewSection: 'financeItem:$key',
          reviewLabel: _financeReviewLabel,
        ),
      );
    }
    final textual =
        key == 'financeRemark' ||
        key.contains('Payer') ||
        key.contains('Payee') ||
        key.contains('Account');
    final longText = _isFinanceLongTextKey(key);
    final source = switch (key) {
      'revenue' => '已确认收入',
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              ProposalPalette.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: textual
          ? _textField(
              field.$2,
              key,
              required: true,
              maxLines: longText ? 12 : 3,
              minLines: longText ? 2 : 1,
              fullWidth: longText,
              writable: _canEditUnreviewedFinance,
              resetReview: 'financeCompleted',
              reviewSection: 'financeItem:$key',
              reviewLabel: _financeReviewLabel,
            )
          : _numberField(
              field.$2,
              key,
              required: true,
              source: source,
              writable: _canEditUnreviewedFinance,
              resetReview: 'financeCompleted',
              reviewSection: 'financeItem:$key',
              reviewLabel: _financeReviewLabel,
            ),
    );
  }

  /// 栅格宽度上限：与 ProposalLayout 同一阶梯，不再各写各的阈值。
  int _maxGridColumnsForWidth(double width) => ProposalLayout.columnsFor(width);

  /// 结算条款网格：同一阶梯，最多四列。
  int _settleTermsColumnCount(double width) =>
      math.min(4, ProposalLayout.columnsFor(width));

  Widget _fieldGrid(
    bool wide,
    List<Widget> fields, {
    int? columns,
    bool flat = false,
  }) => LayoutBuilder(
    builder: (gridContext, constraints) {
      final simple = ProposalSimpleViewScope.of(gridContext);
      final requested = simple
          // 原型：auto-fit minmax(340px, 1fr)。只读简单行最多两列，
          // 三列会把「提案类型 / 子标题」这类成对字段拆开，宽屏上看着错位。
          ? (_simpleView
                ? ((constraints.maxWidth + 22) / (340 + 22))
                      .floor()
                      .clamp(1, 2)
                      .toInt()
                : (constraints.maxWidth >= 700 ? 2 : 1))
          : columns ??
                (!wide
                    ? 1
                    : math.min(
                        3,
                        ProposalLayout.columnsFor(constraints.maxWidth),
                      ));
      final resolved = math.max(
        1,
        math.min(requested, _maxGridColumnsForWidth(constraints.maxWidth)),
      );
      final rows = _groupFields(fields, resolved);
      if (simple) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              row.length == 1 &&
                      (resolved <= 1 || _isFullWidthWidget(row.first))
                  ? row.first
                  // 多列一排：分隔线由整排统一画，几格高度不一样时线也对齐成一条。
                  : Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: DunesColors.resolve(
                              gridContext,
                              const Color(0xFFF3F0F8),
                              role: DunesColorRole.border,
                            ),
                          ),
                        ),
                      ),
                      child: ProposalGridRowScope(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < resolved; i++) ...[
                              if (i > 0) const SizedBox(width: 24),
                              Expanded(
                                child: i < row.length
                                    ? row[i]
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
          ],
        );
      }
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: flat
              ? null
              : Border.all(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.borderSoft,
                    role: DunesColorRole.border,
                  ),
                ),
          borderRadius: flat ? null : BorderRadius.circular(10),
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
        ),
        clipBehavior: flat ? Clip.none : Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows.length; row++)
              _gridRow(rows[row], resolved, lastRow: row == rows.length - 1),
          ],
        ),
      );
    },
  );

  Widget _gridRow(List<Widget> cells, int columns, {required bool lastRow}) {
    final spanAll =
        cells.length == 1 && (columns <= 1 || _isFullWidthWidget(cells.first));
    if (spanAll) {
      return _gridCell(
        child: cells.first,
        lastInRow: true,
        lastRow: lastRow,
        compact: columns == 1,
      );
    }
    final filler = cells.length < columns;
    // 同一行的格子必须等高：否则列分隔线长短不一、行底线在每个格子各自的底部
    // 断开，整张表看起来是错位的。IntrinsicHeight + stretch 让一行只有一条底线。
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

  /// [_FullWidthField] 常被 [_anchor] 包在 KeyedSubtree 里，类型检查要往里看一层。
  bool _isFullWidthWidget(Widget field) {
    Widget current = field;
    for (var i = 0; i < 4; i++) {
      if (current is _FullWidthField) return true;
      if (current is KeyedSubtree) {
        current = current.child;
        continue;
      }
      if (current is _FlowFieldFlash) {
        current = current.child;
        continue;
      }
      return false;
    }
    return false;
  }

  /// 按列数切分字段，[_FullWidthField] 独占一行。
  List<List<Widget>> _groupFields(List<Widget> fields, int columns) {
    final rows = <List<Widget>>[];
    var current = <Widget>[];
    for (final field in fields) {
      if (_isFullWidthWidget(field)) {
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
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: lastInRow
              ? BorderSide.none
              : BorderSide(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.borderSoft,
                    role: DunesColorRole.border,
                  ),
                ),
          bottom: lastRow
              ? BorderSide.none
              : BorderSide(
                  color: DunesColors.resolve(
                    context,
                    ProposalPalette.borderSoft,
                    role: DunesColorRole.border,
                  ),
                ),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
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
    final accent = DunesColors.resolve(context, ProposalPalette.purple);
    final accentSoft = DunesColors.resolve(context, ProposalPalette.purpleSoft);
    final dayColor = DunesColors.resolve(context, ProposalPalette.text2);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: accent,
          onPrimary: DunesColors.resolve(context, Colors.white),
          secondary: accent,
          onSecondary: DunesColors.resolve(context, Colors.white),
          secondaryContainer: accentSoft,
          onSecondaryContainer: accent,
          surface: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          onSurface: dayColor,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          headerBackgroundColor: accentSoft,
          headerForegroundColor: accent,
          rangeSelectionBackgroundColor: accentSoft,
          rangeSelectionOverlayColor: WidgetStatePropertyAll(
            accent.withValues(alpha: 0.08),
          ),
          weekdayStyle: TextStyle(
            color: DunesColors.resolveNullable(context, dayColor),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return null;
          }),
          dayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return DunesColors.resolve(context, Colors.white);
            }
            if (states.contains(WidgetState.disabled)) {
              return DunesColors.resolve(context, ProposalPalette.text3);
            }
            return dayColor;
          }),
          todayForegroundColor: WidgetStatePropertyAll(accent),
          todayBackgroundColor: WidgetStatePropertyAll(accentSoft),
          todayBorder: BorderSide(
            color: DunesColors.resolve(
              context,
              accent,
              role: DunesColorRole.border,
            ),
          ),
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
    bool required = false,
  }) {
    final tone = proposalFieldTone(enabled: enabled, source: source);
    if (_readValuesOnly(enabled)) {
      return ProposalField(
        label: label,
        required: required,
        source: source,
        tone: tone,
        footer: _contractEditFooter(fieldKey),
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(empty ? '' : display),
      );
    }
    return ProposalField(
      label: label,
      required: required,
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
                context: context,
                hint: hint,
                readOnly: !enabled,
                tone: tone,
              ).copyWith(
                suffixIcon: Icon(
                  enabled
                      ? Icons.calendar_today_outlined
                      : Icons.lock_outline_rounded,
                  size: 16,
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                ),
              ),
          child: Text(
            empty ? hint : display,
            style: TextStyle(
              fontSize: 13,
              color: empty || !enabled
                  ? DunesColors.resolve(context, ProposalPalette.text3)
                  : DunesColors.resolve(context, ProposalPalette.text),
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
    bool required = false,
    String? valueOverride,
    ValueChanged<String>? onWrite,
    String? fieldKey,
  }) {
    final enabled = _fillEnabled(
      writable,
      resetReview: resetReview,
      reviewSection: reviewSection,
    );
    final raw = (valueOverride ?? _text(key)).trim();
    final parsed = _parseDate(raw);
    return _datePickerField(
      fieldKey: fieldKey ?? key,
      label: label,
      display: parsed == null ? raw : _fmtDate(parsed),
      empty: raw.isEmpty,
      enabled: enabled,
      source: source,
      required: required,
      reviewSection: reviewSection,
      reviewLabel: reviewLabel,
      onTap: enabled
          ? () async {
              final picked = await _pickDate(parsed);
              if (picked != null) {
                final text = _fmtDate(picked);
                if (onWrite != null) {
                  onWrite(text);
                } else {
                  _set(key, text, resetReview: resetReview);
                }
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
    int? minLines,
    bool? fullWidth,
    String? source,
    String? hint,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    bool? writable,
  }) {
    final enabled = _fillEnabled(
      writable,
      resetReview: resetReview,
      reviewSection: reviewSection,
    );
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final footer = _contractEditFooter(key);
    final multiline = maxLines > 1;
    final compact = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    final resolvedMinLines = multiline
        ? math.min(minLines ?? 3, compact ? 3 : (minLines ?? 3))
        : 1;
    final Widget input = (_showSelectedAsText || !enabled)
        ? _readonlySelectedText(_maskIfAccount(key, _text(key)))
        : TextFormField(
            key: ValueKey('$key-${_row.id}-$_fieldEpoch'),
            initialValue: _text(key),
            minLines: resolvedMinLines,
            maxLines: multiline ? null : 1,
            keyboardType: multiline ? TextInputType.multiline : null,
            enabled: enabled,
            readOnly: !enabled,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: enabled
                  ? DunesColors.resolve(context, ProposalPalette.text)
                  : DunesColors.resolve(context, ProposalPalette.text3),
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
              context: context,
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
    return _anchor(
      key,
      (fullWidth ?? multiline) ? _FullWidthField(child: field) : field,
    );
  }

  Widget _numberField(
    String label,
    String key, {
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    String? source,
    bool? writable,
    bool required = false,
    String? valueOverride,
    ValueChanged<String>? onWrite,
    String? fieldKey,
  }) {
    final enabled = _fillEnabled(
      writable,
      resetReview: resetReview,
      reviewSection: reviewSection,
    );
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final footer = _contractEditFooter(key);
    final trailing = _rowReviewToggle(reviewSection, reviewLabel);
    final current = valueOverride ?? _text(key);
    final anchorKey = fieldKey ?? key;
    if (_readValuesOnly(enabled)) {
      return _anchor(
        anchorKey,
        ProposalField(
          label: label,
          required: required,
          source: source,
          tone: tone,
          footer: footer,
          trailing: trailing,
          child: _readonlySelectedText(current),
        ),
      );
    }
    return _anchor(
      anchorKey,
      ProposalField(
        label: label,
        required: required,
        source: source,
        tone: tone,
        footer: footer,
        trailing: trailing,
        child: TextFormField(
          key: ValueKey('$anchorKey-${_row.id}-$_fieldEpoch'),
          initialValue: current,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: enabled,
          readOnly: !enabled,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: enabled
                ? DunesColors.resolve(context, ProposalPalette.text)
                : DunesColors.resolve(context, ProposalPalette.text3),
          ),
          onChanged: enabled
              ? (value) {
                  if (onWrite != null) {
                    onWrite(value);
                    return;
                  }
                  _set(
                    key,
                    value.trim().isEmpty ? null : double.tryParse(value) ?? 0,
                    resetReview: resetReview,
                    rebuild: false,
                  );
                }
              : null,
          decoration: proposalInputDecoration(
            context: context,
            readOnly: !enabled,
            tone: tone,
          ),
        ),
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
    final canEdit =
        _fillEnabled(
          null,
          resetReview: resetReview,
          reviewSection: reviewSection,
        ) &&
        enabled;
    final tone = proposalFieldTone(enabled: canEdit);
    final selected =
        _selectedCatalog(current, options) ??
        ((current != null && current.isNotEmpty) ? current : null);
    final values = _withCurrent(options, selected);
    if (_readValuesOnly(canEdit)) {
      return ProposalField(
        label: label,
        required: required,
        tone: tone,
        trailing: _rowReviewToggle(reviewSection, reviewLabel),
        child: _readonlySelectedText(selected?.label ?? current?.label ?? ''),
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

  List<String> _settleFieldOptions(String key, String current) {
    final base = switch (key) {
      'supplySettleMode' ||
      'channelSettleMode' => widget.options.resolvedSettleModes,
      'supplySettleCycle' ||
      'channelSettleCycle' => widget.options.resolvedSettleCycles,
      _ => const <String>[],
    };
    if (current.isNotEmpty && !base.contains(current)) {
      return [current, ...base];
    }
    return base;
  }

  String? _settleAddLabel(String key) => switch (key) {
    'supplySettleMode' || 'channelSettleMode' => '新增结算模式',
    'supplySettleCycle' || 'channelSettleCycle' => '新增结算周期',
    _ => null,
  };

  Widget _dropdownField(
    String label,
    String key,
    List<String> options, {
    bool required = false,
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    String? addLabel,
    String? source,
    bool? writable,
    ValueChanged<String?>? onSelected,
    String? valueOverride,
    String? fieldKey,
  }) {
    final enabled = _fillEnabled(
      writable,
      resetReview: resetReview,
      reviewSection: reviewSection,
    );
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final current = valueOverride ?? _text(key);
    final anchorKey = fieldKey ?? key;
    if (_readValuesOnly(enabled)) {
      return _anchor(
        anchorKey,
        ProposalField(
          label: label,
          required: required,
          source: source,
          tone: tone,
          trailing: _rowReviewToggle(reviewSection, reviewLabel),
          child: _readonlySelectedText(current),
        ),
      );
    }
    final values = [...options];
    if (current.isNotEmpty && !values.contains(current)) {
      values.insert(0, current);
    }
    return _anchor(
      anchorKey,
      ProposalField(
        label: label,
        required: required,
        source: source,
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
      ),
    );
  }

  Widget _configuredPresidentsField() {
    final names = widget.options.presidentDisplayNames(widget.people);
    return ProposalField(
      label: '最终确认人',
      tone: _isPurchase ? ProposalFieldTone.auto : ProposalFieldTone.fill,
      child: Text(
        names.isEmpty ? '请在管理后台「提案录入选项」中配置最终确认人' : names,
        style: TextStyle(
          color: names.isEmpty
              ? DunesColors.resolve(context, ProposalPalette.coral)
              : DunesColors.resolve(context, ProposalPalette.text),
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
    String? resetReview,
    String? reviewSection,
    String reviewLabel = '复核',
    String? badge,
    bool? writable,
    bool required = false,
  }) {
    final enabled = _fillEnabled(
      writable,
      resetReview: resetReview ?? (writable == null ? 'marketCompleted' : null),
      reviewSection: reviewSection,
    );
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
    if (_readValuesOnly(enabled)) {
      return _anchor(
        key,
        ProposalField(
          label: label,
          required: required,
          source: badge,
          tone: tone,
          trailing: _rowReviewToggle(reviewSection, reviewLabel),
          child: _readonlySelectedText(_text(key)),
        ),
      );
    }
    return _anchor(
      key,
      ProposalField(
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
                    _markFormDirty();
                    _row = _row.copyWith(form: form, status: _statusAfterEdit);
                  });
                  _emitChanged(_row);
                }
              : null,
        ),
      ),
    );
  }

  Widget _businessCostField({bool wide = true}) {
    if (_businessCostSealed) {
      return ProposalField(
        label: '业务成本',
        tone: ProposalFieldTone.locked,
        child: Text(
          '已加密上锁，负责人二不可查看。由市场部负责人一在财务复核时填写。',
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text2),
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
      return ProposalField(
        label: '业务成本',
        tone: ProposalFieldTone.locked,
        child: Text(
          '由市场部负责人一在财务复核时填写',
          style: TextStyle(
            color: DunesColors.resolve(context, ProposalPalette.text3),
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
        ? (!_isLocked &&
              (writable ?? false) &&
              !_reviewLocksField(resetReview: 'financeCompleted'))
        : _fillEnabled(
            writable,
            resetReview: 'financeCompleted',
            reviewSection: reviewSection,
          );
    final tone = proposalFieldTone(enabled: enabled);
    final selectedRaw = _setOf(namesKey);
    final selected = namesKey == 'costItems'
        ? {for (final item in selectedRaw) proposalProjectCostDisplayName(item)}
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
    final chipOptions = options;
    final amounts = proposalCostAmountMap(_form[amountsKey]);
    final total = proposalCostAmountTotal(amounts);
    final settleMap = settleTermsKey.isEmpty
        ? const <String, ProposalFinanceSettleTerms>{}
        : proposalCostSettleTermsMap(_form[settleTermsKey]);
    Widget settleFields(String name) {
      if (settleTermsKey.isEmpty) return const SizedBox.shrink();
      final id = proposalCostAmountId(name, catalog);
      final project = namesKey == 'costItems';
      var rows = proposalCostSettleTermsList(
        _form[settleTermsKey],
        name: name,
        id: id,
      );
      if (rows.isEmpty) {
        rows = [
          proposalCostSettleTermsOf(terms: settleMap, name: name, id: id),
        ];
      }
      final estimated = project
          ? proposalEstimateProjectCostAmount(
              _form,
              name,
              catalog: catalog,
              costNames: namesKey == 'costItems'
                  ? _projectCostItemNames
                  : const [],
            )
          : null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              if (project && rows.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        '第 ${i + 1} 条',
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.text2,
                          ),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (enabled)
                        TextButton(
                          onPressed: () {
                            final next = [...rows]..removeAt(i);
                            _writeCostSettleRows(
                              settleTermsKey: settleTermsKey,
                              id: id,
                              rows: next,
                            );
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(36, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '删除',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              if (project)
                _settleTermsGrid(
                  wide: wide,
                  keyPrefix: '$settleTermsKey-$id-$i',
                  terms: rows[i],
                  enabled: enabled,
                  includeChannel: false,
                  includeSkuPick: true,
                  includeSalesFields: false,
                  includeInvoiceTax: false,
                  includeParties: false,
                  includeFormula: false,
                  includeSchedule: false,
                  compactCostRules: true,
                  syncSource: _primarySyncSource(),
                  productSource: 'SUPPLIER',
                  onChanged: (terms) {
                    final next = [...rows];
                    next[i] = terms;
                    _writeCostSettleRows(
                      settleTermsKey: settleTermsKey,
                      id: id,
                      rows: next,
                    );
                  },
                )
              else
                _settleBlockCard(
                  index: i,
                  wide: wide,
                  canRemove: enabled && rows.length > 1,
                  onRemove: enabled && rows.length > 1
                      ? () {
                          final next = [...rows]..removeAt(i);
                          _writeCostSettleRows(
                            settleTermsKey: settleTermsKey,
                            id: id,
                            rows: next,
                          );
                        }
                      : null,
                  child: _settleTermsGrid(
                    wide: wide,
                    keyPrefix: '$settleTermsKey-$id-$i',
                    terms: rows[i],
                    enabled: enabled,
                    includeChannel: true,
                    includeSkuPick: false,
                    includeSalesFields: true,
                    includeParties: true,
                    syncSource: _primarySyncSource(),
                    productSource: 'SUPPLIER',
                    onChanged: (terms) {
                      _setCostSettleTerms(
                        settleTermsKey: settleTermsKey,
                        id: id,
                        terms: terms,
                      );
                    },
                  ),
                ),
            ],
            if (project && enabled)
              TextButton.icon(
                onPressed: () => _writeCostSettleRows(
                  settleTermsKey: settleTermsKey,
                  id: id,
                  rows: [...rows, const ProposalFinanceSettleTerms()],
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('再加一条'),
              ),
            if (project)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  estimated == null ? '填比例或单价后自动加总' : '合计 ${_money(estimated)}',
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text2),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: DunesColors.resolve(
                              context,
                              ProposalPalette.text,
                            ),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (namesKey != 'costItems') ?_costFormulaHint(name),
                      ],
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
                    style: TextStyle(
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.text2,
                      ),
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

    // 只读（查看、复核、或这一项已锁）：一行写完「合计 · 各项金额」，和其他行一样整齐，
    // 不再一项一个大字、下面挂公式。
    if ((_showSelectedAsText || !enabled) && settleTermsKey.isEmpty) {
      final summary = names.isEmpty
          ? ''
          : [
              '合计 ${_money(total)}',
              for (final name in names)
                '$name ${_money(amounts[proposalCostAmountId(name, catalog)] ?? amounts[name] ?? 0)}',
            ].join(' · ');
      return _FullWidthField(
        child: ProposalField(
          label: label,
          formula: namesKey == 'costItems' ? '成本明细各项之和' : null,
          tone: tone,
          trailing: _rowReviewToggle(reviewSection, _financeReviewLabel),
          child: _readonlySelectedText(summary, maxLines: 2),
        ),
      );
    }
    if (_showSelectedAsText) {
      return _FullWidthField(
        child: ProposalField(
          label: label,
          formula: namesKey == 'costItems' ? '成本明细各项之和' : null,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settleTermsKey.isEmpty
                                  ? '$name  ${_money(amounts[proposalCostAmountId(name, catalog)] ?? amounts[name] ?? 0)}'
                                  : name,
                              style: TextStyle(
                                color: DunesColors.resolve(
                                  context,
                                  ProposalPalette.text,
                                ),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (namesKey != 'costItems')
                              ?_costFormulaHint(name),
                          ],
                        ),
                      ),
                      settleFields(name),
                    ],
                    if (settleTermsKey.isEmpty)
                      Text(
                        '合计 ${_money(total)}',
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.text2,
                          ),
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
        formula: namesKey == 'costItems' ? '成本明细各项之和' : null,
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
            if (namesKey == 'costItems')
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '从产品成本结算的「成本类型」匹配；金额可改。',
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text3),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            if (namesKey == 'taxCostItems')
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '增值税及附加两种口径只选一种，后点的生效；印花税、所得税可另选。',
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text3),
                    fontSize: 11,
                    height: 1.35,
                  ),
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
    final stamp = math.max(
      _costAmountStamp['$amountsKey::$id'] ?? 0,
      _costAmountStamp['$amountsKey::$name'] ?? 0,
    );
    final formulaHint = _costFormulaHint(name);
    final estimated = proposalCostHasEstimateFormula(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          ?formulaHint,
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 148,
              child: TextFormField(
                key: ValueKey('$amountsKey-$id-${_row.id}-$_fieldEpoch-$stamp'),
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
                  color: enabled
                      ? DunesColors.resolve(context, ProposalPalette.text)
                      : DunesColors.resolve(context, ProposalPalette.text3),
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
                  context: context,
                  hint: estimated ? '测算（万元）' : '预计（万元）',
                  readOnly: !enabled,
                  tone: tone,
                ),
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
    bool required = false,
    Set<String>? selectedOverride,
    ValueChanged<String>? onToggleOverride,
    String? fieldKey,
  }) {
    final enabled = _fillEnabled(
      writable,
      resetReview: resetReview,
      reviewSection: reviewSection,
    );
    final tone = proposalFieldTone(enabled: enabled, source: source);
    final selected = selectedOverride ?? _setOf(key);
    final anchorKey = fieldKey ?? key;
    if (_readValuesOnly(enabled)) {
      return _anchor(
        anchorKey,
        _FullWidthField(
          child: ProposalField(
            label: label,
            required: required,
            source: source,
            tone: tone,
            trailing: _rowReviewToggle(reviewSection, reviewLabel),
            child: _readonlySelectedText(selected.join('、')),
          ),
        ),
      );
    }
    return _anchor(
      anchorKey,
      _FullWidthField(
        child: ProposalField(
          label: label,
          required: required,
          source: source,
          tone: tone,
          trailing: _rowReviewToggle(reviewSection, reviewLabel),
          child: ProposalPills(
            options: [
              ...options,
              ...selected.where((v) => !options.contains(v)),
            ],
            selected: selected,
            enabled: enabled,
            single: single,
            onToggle: (value) {
              if (!enabled) return;
              if (onToggleOverride != null) {
                onToggleOverride(value);
                return;
              }
              _toggleList(key, value, resetReview: resetReview, single: single);
            },
            onAdd: addLabel == null || !enabled || onToggleOverride != null
                ? null
                : () => _addOption(
                    key,
                    addLabel,
                    resetReview: resetReview,
                    single: single,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _purchaseMarketSection(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _marketKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProposalSectionTitle(
                title: _protoForm ? '市场部' : '一、市场部内容',
                tag: 'Market',
                description: '提交人填写供给侧信息；市场部负责人一复核市场整板块，采购合同由财务部负责人二复核。',
                lighthouse: _protoForm,
              ),
              _taskCue(ProposalIntakeNavSection.market),
            ],
          ),
        ),
        if (_simpleView)
          _purchaseMarketSimple(wide)
        else
          ..._purchaseMarketForm(wide),
      ],
    );
  }

  /// 原型「填报内容 · 市场部」（采购）：一行一条。负责人、采购合同、采购对接人各合成一行；
  /// 名称已在标题里不再重复，子标题没填就不显示。
  Widget _purchaseMarketSimple(bool wide) {
    final contacts = [
      if (_text('bizContact').trim().isNotEmpty)
        '业务 ${_text('bizContact').trim()}',
      if (_text('financeContact').trim().isNotEmpty)
        '财务 ${_text('financeContact').trim()}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldGrid(wide, [
          _simpleLine(
            '产品提案名称',
            _text('proposalName'),
            anchorKey: 'proposalName',
            required: true,
          ),
          _simpleLine('提报人', _submitterName),
          _simpleLine(
            '提案类型',
            _text('proposalType'),
            anchorKey: 'proposalType',
            required: true,
          ),
          _textField(
            '子标题',
            'proposalSubtitle',
            writable: _canEditProposalSubtitle,
            resetReview: 'financeCompleted',
            reviewSection: 'financeItem:proposalSubtitle',
            reviewLabel: _subtitleFillLabel,
          ),
          _simpleLine(
            '供给（标签二）',
            _setOf('supplies').join('、'),
            anchorKey: 'supplies',
            required: true,
          ),
          _simpleLine(
            '供给侧品牌',
            _text('supplyBrand'),
            anchorKey: 'supplyBrand',
            required: true,
          ),
          _simpleLine(
            '负责人',
            _simplePeopleText(const [
              ('市场一', 'marketOwner1'),
              ('市场二', 'marketOwner2'),
              ('运营', 'operator'),
            ], extra: _simplePresidentText),
            anchorKey: 'marketOwner1',
            required: true,
            fullWidth: true,
          ),
          _contractSimpleLine('采购合同', 'purchase'),
          _contractTermsLine('采购合同核心条款', 'purchase'),
          _simpleLine(
            '采购对接人',
            contacts,
            anchorKey: 'bizContact',
            required: true,
          ),
          _simpleLine(
            'HUN ID',
            _canSeeHun ? _text('hunId') : '已加密，仅市场部负责人一可见',
            anchorKey: 'hunId',
            required: true,
          ),
          _simpleLine(
            '发票种类',
            _setOf('invoiceTypes').join('、'),
            anchorKey: 'invoiceTypes',
            required: true,
          ),
          _textField(
            '供给政策',
            'supplierPolicy',
            maxLines: 6,
            fullWidth: true,
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '销售政策',
            'salesPolicy',
            maxLines: 6,
            fullWidth: true,
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '执行计划',
            'executionPlan',
            maxLines: 4,
            fullWidth: false,
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '风险点',
            'riskPoints',
            maxLines: 4,
            fullWidth: false,
            required: true,
            resetReview: 'marketCompleted',
          ),
        ]),
        const SizedBox(height: 8),
        _purchaseSupplyProductsBlock(wide),
        const SizedBox(height: 8),
        _marketModuleReviewCard(plain: false),
      ],
    );
  }

  List<Widget> _purchaseMarketForm(bool wide) {
    return [
      _stepCard(
        '01',
        '基础信息',
        '提案身份与类型',
        _fieldGrid(wide, [
          ProposalField(
            label: '提报人',
            tone: ProposalFieldTone.auto,
            child: Text(
              _submitterName.isEmpty ? '—' : _submitterName,
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _textField(
            '产品提案名称',
            'proposalName',
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '子标题（由财务部负责人二填写）',
            'proposalSubtitle',
            hint: '由财务部负责人二填写（选填）',
            writable: _canEditProposalSubtitle,
            resetReview: 'financeCompleted',
            reviewSection: 'financeItem:proposalSubtitle',
            reviewLabel: _subtitleFillLabel,
          ),
          _dropdownField(
            '提案类型',
            'proposalType',
            kPurchaseProposalTypes,
            required: true,
            resetReview: 'marketCompleted',
          ),
        ]),
      ),
      _stepCard(
        '02',
        '供给基础与人员',
        '供给标签、品牌与责任人',
        _fieldGrid(wide, [
          _multiField(
            '供给（标签二）',
            'supplies',
            widget.options.supplies,
            '新增供给',
            resetReview: 'marketCompleted',
            required: true,
          ),
          _dropdownField(
            '供给侧品牌',
            'supplyBrand',
            widget.options.supplyBrands,
            addLabel: '新增品牌',
            required: true,
            resetReview: 'marketCompleted',
          ),
          _personField(
            '市场部负责人一（整板块复核）',
            'marketOwner1',
            positionIncludes: '市场部负责人一',
            required: true,
          ),
          _personField(
            '市场部负责人二（科技审核）',
            'marketOwner2',
            positionIncludes: '市场部负责人二',
            required: true,
          ),
          _personField(
            '运营',
            'operator',
            positionIncludes: '运营',
            required: true,
          ),
          _configuredPresidentsField(),
        ]),
      ),
      _contractCard('03', '采购合同', 'purchase', wide),
      _stepCard(
        '04',
        '对接与合规',
        '对接人、HUN 与发票',
        _fieldGrid(wide, [
          _textField(
            '采购对接人（业务）',
            'bizContact',
            required: true,
            resetReview: 'marketCompleted',
          ),
          _textField(
            '采购对接人（财务）',
            'financeContact',
            required: true,
            resetReview: 'marketCompleted',
          ),
          if (_canSeeHun)
            _textField(
              'HUN ID',
              'hunId',
              source: '加密处理，仅市场部负责人一填写、可见',
              hint: '由市场部负责人一在复核时填写',
              required: true,
              writable: _canEditHun,
              resetReview: 'marketCompleted',
            )
          else
            ProposalField(
              label: 'HUN ID',
              source: '加密处理，仅市场部负责人一填写、可见',
              child: Text(
                '已加密',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _multiField(
            '发票种类',
            'invoiceTypes',
            kProposalInvoiceTypes,
            null,
            required: true,
            resetReview: 'marketCompleted',
          ),
        ]),
      ),
      _stepCard(
        '05',
        '供给产品',
        '默认一条结算，可再新增明细。无需科技复核',
        _purchaseSupplyProductsBlock(wide),
      ),
      _stepCard(
        '06',
        '政策与执行',
        '供给政策可从采购合同供货商政策带入',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldGrid(wide, [
              _textField(
                '供给政策',
                'supplierPolicy',
                maxLines: 6,
                minLines: 6,
                required: true,
                source: '合同抓取 · 可修改',
                hint: '选择已签署采购合同后自动带入供货商政策，也可手改',
                resetReview: 'marketCompleted',
              ),
              _textField(
                '销售政策',
                'salesPolicy',
                maxLines: 6,
                minLines: 6,
                required: true,
                resetReview: 'marketCompleted',
              ),
              _textField(
                '提案执行计划',
                'executionPlan',
                maxLines: 4,
                required: true,
                hint: '合作思路与合作逻辑，不涉及财务数据',
                resetReview: 'marketCompleted',
              ),
              _textField(
                '合作风险点',
                'riskPoints',
                maxLines: 4,
                required: true,
                resetReview: 'marketCompleted',
              ),
            ]),
          ],
        ),
      ),
      _marketModuleReviewCard(plain: false),
    ];
  }

  Widget _purchaseFinanceSection(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _financeKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProposalSectionTitle(
                title: _protoForm ? '财务部' : '三、财务部内容',
                tag: 'Finance',
                description: '财务板块暂不复核。请指定财务部负责人一、二；负责人二仍复核采购合同。',
                lighthouse: _protoForm,
              ),
              _taskCue(ProposalIntakeNavSection.finance),
            ],
          ),
        ),
        if (_simpleView)
          _fieldGrid(wide, [
            _simpleLine(
              '负责人',
              _simplePeopleText(const [
                ('财务一', 'financeOwner1'),
                ('财务二（复核采购合同）', 'financeOwner2'),
              ]),
              anchorKey: 'financeOwner1',
              required: true,
              fullWidth: true,
            ),
            _textField(
              '备注',
              'financeRemark',
              maxLines: 3,
              fullWidth: true,
              required: true,
              resetReview: 'marketCompleted',
            ),
          ])
        else
          ProposalCard(
            child: Column(
              children: [
                _fieldGrid(wide, [
                  _personField(
                    '财务部负责人一',
                    'financeOwner1',
                    positionIncludes: '财务部负责人一',
                    required: true,
                  ),
                  _personField(
                    '财务部负责人二（采购合同复核）',
                    'financeOwner2',
                    positionIncludes: '财务部负责人二',
                    required: true,
                  ),
                  _textField(
                    '备注',
                    'financeRemark',
                    maxLines: 3,
                    required: true,
                    resetReview: 'marketCompleted',
                  ),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _purchaseSupplyProductsBlock(bool wide) {
    final rows = proposalIntakeSupplyProducts(_form);
    final locked = _showSelectedAsText || !_canEditMarket;
    return _anchor(
      'supplyProducts',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '供给产品',
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_canEditMarket)
                TextButton.icon(
                  onPressed: _addSupplyProduct,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增供给产品'),
                ),
            ],
          ),
          if (!_simpleView) ...[
            Text(
              '只填供给侧。未开始填写的卡片可不填。勾选「是否已有供给产品」后必须搜索选择已建供应商产品，选中后同步资管结算规则。新建时请先选供应商。',
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _existingSupplyToggle(locked: locked),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '尚未添加供给产品',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontSize: 12,
                ),
              ),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            const SizedBox(height: 10),
            _purchaseSupplyProductCard(rows[i], i + 1, wide),
          ],
        ],
      ),
    );
  }

  Widget _existingSupplyToggle({required bool locked}) {
    final enabled = proposalIntakeIsExistingSupplyProduct(_form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: locked ? null : () => _setExistingSupplyEnabled(!enabled),
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
                      : (value) => _setExistingSupplyEnabled(value == true),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '是否已有供给产品',
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.text),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '勾选后先选业务平台，再搜索并选择已建供给产品（必填）。选中后会按资管供应商产品结算规则同步账单类型、结算方式、税率等。',
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _supplySupplierCell({
    required CatalogRef? current,
    required bool locked,
    required String syncSource,
    required ValueChanged<CatalogRef?> onSelected,
  }) {
    if (syncSource.trim().isNotEmpty) {
      _prefetchSettle(syncSource, 'SUPPLIER');
    }
    final settleKey = _settleCacheKey(syncSource, 'SUPPLIER');
    final loading = _settleLoading.contains(settleKey);
    final options =
        (_settleBundles[settleKey] ?? const _SettleCatalogBundle()).suppliers;
    final noPlatform = syncSource.trim().isEmpty;
    return _skuCatalogCell(
      label: '供应商',
      current: current,
      options: options,
      locked: locked,
      required: true,
      hint: noPlatform
          ? '请先选择业务平台'
          : (options.isEmpty ? (loading ? '字典加载中…' : '该业务平台暂无供应商') : '请选择供应商'),
      emptyText: noPlatform ? '请先选择业务平台' : (loading ? '字典加载中…' : '该业务平台暂无供应商'),
      onSelected: onSelected,
    );
  }

  Widget _purchaseSupplyProductCard(
    ProposalSupplyProductRow row,
    int index,
    bool wide,
  ) {
    final locked = _showSelectedAsText || !_canEditMarket;
    final existing =
        proposalIntakeIsExistingSupplyProduct(_form) || row.isExistingBuilt;
    final title =
        existing && row.assetProduct != null && row.assetProduct!.isNotEmpty
        ? '供给产品 $index · ${row.assetProduct!.label}'
        : (row.supplierLabel.isEmpty
              ? '供给产品 $index'
              : '供给产品 $index · ${row.supplierLabel}');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          ProposalPalette.app,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: DunesColors.resolve(context, ProposalPalette.text),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_canEditMarket)
                TextButton(
                  onPressed: () => _removeSupplyProduct(row.id),
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
              required: existing,
              hint: _syncSourceCatalog.isEmpty ? '字典加载中或暂无平台' : '请选择业务平台',
              onSelected: (value) {
                _patchSupplyProduct(row.id, (current) {
                  final changed = current.syncSourceCode != (value?.code ?? '');
                  var next = current.copyWith(
                    syncSourceRef: value,
                    supplierRef: changed ? null : current.supplierRef,
                    supplierCode: changed ? '' : current.supplierCode,
                    settlements: changed
                        ? [
                            for (final item in proposalIntakeSupplySettlements(
                              current,
                            ))
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
                    _assetProductSyncSeq[row.id] =
                        (_assetProductSyncSeq[row.id] ?? 0) + 1;
                    _assetProductSyncHint.remove(row.id);
                  }
                  return next;
                });
                if (value != null && value.isNotEmpty) {
                  _prefetchSettle(value.code, 'SUPPLIER');
                }
              },
            ),
            if (existing)
              _assetProductSearchCell(
                rowId: row.id,
                current: row.assetProduct,
                syncSource: row.syncSourceCode,
                locked: locked,
                label: '已建供给产品',
                supplier: true,
                fallbackLabel: row.productCode,
                onSelected: (value) {
                  _patchSupplyProduct(
                    row.id,
                    (current) => current.applyAssetProduct(value),
                  );
                  unawaited(
                    _syncSupplierProductSettlement(rowId: row.id, hit: value),
                  );
                },
              )
            else
              _supplySupplierCell(
                current:
                    row.supplierRef ??
                    (row.supplierCode.trim().isEmpty
                        ? null
                        : CatalogRef(
                            code: row.supplierCode,
                            name: row.supplierCode,
                          )),
                locked: locked,
                syncSource: row.syncSourceCode,
                onSelected: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(
                    supplierRef: value,
                    supplierCode: value?.code ?? '',
                  ),
                ),
              ),
            if (!existing) ...[
              _skuTextCell(
                rowId: row.id,
                label: '产品编码',
                value: row.productCode,
                fieldKey: 'productCode',
                hint: '请填写产品编码',
                locked: locked,
                required: true,
                onChanged: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(productCode: value),
                  rebuild: false,
                ),
              ),
              _skuTextCell(
                rowId: row.id,
                label: '门槛金额',
                value: row.thresholdAmount,
                fieldKey: 'threshold',
                hint: '数字',
                locked: locked,
                required: true,
                keyboardType: TextInputType.number,
                onChanged: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(thresholdAmount: value),
                  rebuild: false,
                ),
              ),
              _skuYesNoCell(
                rowId: row.id,
                label: '是否元通券',
                value: row.isYuantongCoupon,
                fieldKey: 'yuantong',
                locked: locked,
                required: true,
                onChanged: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(isYuantongCoupon: value),
                ),
              ),
              _skuYesNoCell(
                rowId: row.id,
                label: '是否单独返利制券',
                value: row.isStandaloneRebate,
                fieldKey: 'standalone',
                locked: locked,
                required: true,
                onChanged: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(isStandaloneRebate: value),
                ),
              ),
              _skuYesNoCell(
                rowId: row.id,
                label: '是否低折扣券',
                value: row.isLowDiscountCoupon,
                fieldKey: 'lowDiscount',
                locked: locked,
                required: true,
                onChanged: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(isLowDiscountCoupon: value),
                ),
              ),
              _skuStringSelectCell(
                rowId: row.id,
                label: '返利模式',
                value: row.rebateMode,
                fieldKey: 'rebate',
                options: widget.options.rebateModes,
                locked: locked,
                required: true,
                addLabel: '新增返利模式',
                onChanged: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(rebateMode: value),
                ),
              ),
              _skuCatalogCell(
                label: '油品分类',
                current:
                    row.oilCategoryRef ?? CatalogRef.fromName(row.oilCategory),
                options: _sectorCatalog,
                locked: locked,
                required: true,
                hint: _sectorCatalog.isEmpty ? '请选择或稍后手填' : '请选择油品分类',
                onSelected: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(
                    oilCategory: value?.name ?? '',
                    oilCategoryRef: value,
                  ),
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
                required: true,
                onPicked: (value) => _patchSupplyProduct(
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
                required: true,
                onPicked: (value) => _patchSupplyProduct(
                  row.id,
                  (current) => current.copyWith(expireDate: value),
                ),
              ),
            ], columns: 2),
          ],
          const SizedBox(height: 10),
          _skuSettleProductCard(
            skuId: row.id,
            title: '供给规则',
            emptyTitle: '尚未添加结算规则',
            reviewPrefix: 'supplySettle',
            linkSkus: true,
            reviewItemPrefix: 'technologyItem',
            itemReviewLabel: _techReviewLabel,
            showItemReview: false,
            requireSchedule: true,
            settlements: proposalIntakeSupplySettlements(row),
            wide: wide,
            enabled: _canEditMarket && !_showSelectedAsText,
            syncSource: row.syncSourceCode,
            productSource: 'SUPPLIER',
            onAdd: () => _addSupplySettle(row.id),
            onRemove: (settleId) => _removeSupplySettle(row.id, settleId),
            onPatch: (settleId, terms) =>
                _patchSupplySettle(row.id, settleId, terms),
          ),
        ],
      ),
    );
  }

  void _writeSupplyProducts(
    List<ProposalSupplyProductRow> rows, {
    bool rebuild = true,
    bool? isExistingSupplyProduct,
  }) {
    final form = Map<String, dynamic>.from(_form)
      ..['supplyProducts'] = [for (final row in rows) row.toJson()];
    if (isExistingSupplyProduct != null) {
      form['isExistingSupplyProduct'] = isExistingSupplyProduct;
    }
    final review = Map<String, dynamic>.from(_review)
      ..['marketCompleted'] = false;
    _markFormDirty();
    _row = _row.copyWith(status: _statusAfterEdit, form: form, review: review);
    if (rebuild && mounted) setState(() {});
    _emitChanged(_row);
  }

  void _setExistingSupplyEnabled(bool enabled) {
    if (!_canEditMarket) return;
    final label = enabled ? '是' : '否';
    var rows = [
      for (final row in proposalIntakeSupplyProducts(_form))
        row.copyWith(
          existingBuilt: label,
          assetProduct: enabled ? row.assetProduct : null,
        ),
    ];
    if (enabled && rows.isEmpty) {
      rows = [proposalIntakeNewSupplyProduct(existing: true)];
    }
    _writeSupplyProducts(rows, isExistingSupplyProduct: enabled);
  }

  void _addSupplyProduct() {
    if (!_canEditMarket) return;
    _writeSupplyProducts([
      ...proposalIntakeSupplyProducts(_form),
      proposalIntakeNewSupplyProduct(
        existing: proposalIntakeIsExistingSupplyProduct(_form),
      ),
    ]);
  }

  void _removeSupplyProduct(String id) {
    if (!_canEditMarket) return;
    _writeSupplyProducts([
      for (final row in proposalIntakeSupplyProducts(_form))
        if (row.id != id) row,
    ]);
  }

  void _patchSupplyProduct(
    String id,
    ProposalSupplyProductRow Function(ProposalSupplyProductRow row) update, {
    bool rebuild = true,
  }) {
    if (!_canEditMarket) return;
    _writeSupplyProducts([
      for (final row in proposalIntakeSupplyProducts(_form))
        if (row.id == id) update(row) else row,
    ], rebuild: rebuild);
  }

  void _addSupplySettle(String productId) {
    if (!_canEditMarket) return;
    _patchSupplyProduct(productId, (row) {
      return row.copyWith(
        settlements: [
          ...proposalIntakeSupplySettlements(row),
          ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId()),
        ],
      );
    });
  }

  void _removeSupplySettle(String productId, String settleId) {
    if (!_canEditMarket) return;
    _patchSupplyProduct(productId, (row) {
      final next = [
        for (final item in proposalIntakeSupplySettlements(row))
          if (item.id != settleId) item,
      ];
      return row.copyWith(
        settlements: next.isEmpty
            ? [ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId())]
            : next,
      );
    });
  }

  void _patchSupplySettle(
    String productId,
    String settleId,
    ProposalFinanceSettleTerms terms,
  ) {
    if (!_canEditMarket) return;
    _patchSupplyProduct(productId, (row) {
      return row.copyWith(
        settlements: [
          for (final item in proposalIntakeSupplySettlements(row))
            if (item.id == settleId) item.copyWith(terms: terms) else item,
        ],
      );
    }, rebuild: true);
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
            color: enabled
                ? DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.soft,
                    role: DunesColorRole.surface,
                  ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.borderStrong,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      ProposalPalette.borderSoft,
                      role: DunesColorRole.border,
                    ),
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
                color: enabled
                    ? DunesColors.resolve(context, ProposalPalette.purple)
                    : DunesColors.resolve(context, ProposalPalette.text3),
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
                          ? DunesColors.resolve(context, ProposalPalette.text)
                          : DunesColors.resolve(context, ProposalPalette.text3),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.text3,
                      ),
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
        color: DunesColors.resolve(
          context,
          ProposalPalette.app,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          onTap: busy ? null : onOpen,
          leading: Icon(
            busy
                ? Icons.hourglass_top_rounded
                : Icons.insert_drive_file_outlined,
            color: DunesColors.resolve(context, ProposalPalette.purple),
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
            style: TextStyle(
              fontSize: 11,
              color: DunesColors.resolve(context, ProposalPalette.text3),
            ),
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

class _FlowFieldFlash extends StatelessWidget {
  const _FlowFieldFlash({
    required this.flashKey,
    required this.active,
    required this.child,
  });

  final String flashKey;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: ValueKey('proposal-flash-$flashKey'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? DunesColors.resolve(
                context,
                const Color(0xFFF1ECFF),
                role: DunesColorRole.surface,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? DunesColors.resolve(
                  context,
                  const Color(0xFFB9ABEB),
                  role: DunesColorRole.border,
                )
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}

class _SkuProductDraft {
  const _SkuProductDraft({
    required this.row,
    this.quantity = 1,
    this.linked = const [],
  });

  final ProposalSkuDetailRow row;
  final int quantity;
  final List<_SkuProductDraft> linked;
}

class _SkuProductEditorDialog extends StatefulWidget {
  const _SkuProductEditorDialog({
    required this.childProduct,
    required this.creating,
    required this.initial,
    required this.quantity,
    required this.mainProducts,
    required this.rollbackOptions,
    required this.readOnly,
    this.proposalTitle = '',
    this.initialLinked = const [],
  });

  final bool childProduct;
  final bool creating;
  final ProposalSkuDetailRow initial;
  final int quantity;
  final List<ProposalSkuDetailRow> mainProducts;
  final List<String> rollbackOptions;
  final bool readOnly;
  final String proposalTitle;
  final List<_SkuProductDraft> initialLinked;

  @override
  State<_SkuProductEditorDialog> createState() =>
      _SkuProductEditorDialogState();
}

class _SkuProductEditorDialogState extends State<_SkuProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _remark;
  late final TextEditingController _face;
  late final TextEditingController _faceThreshold;
  late final TextEditingController _faceOff;
  late final TextEditingController _qty;
  late final TextEditingController _suppliers;
  late final TextEditingController _quantity;
  late String _syncZhongyouHaoke;
  late String _parentSkuId;
  late String _rollback;
  late String _couponKind;
  final List<_SkuProductDraft> _linked = [];
  _SkuProductDraft? _linkedClipboard;

  @override
  void initState() {
    super.initState();
    final seededName = widget.childProduct
        ? widget.initial.productName
        : (widget.initial.productName.trim().isNotEmpty
              ? widget.initial.productName
              : widget.proposalTitle.trim());
    _name = TextEditingController(text: seededName);
    _remark = TextEditingController(text: widget.initial.remark);
    _linked.addAll(widget.initialLinked);
    _face = TextEditingController(text: widget.initial.faceValue);
    final split = proposalIntakeSplitDiscountFace(widget.initial.faceValue);
    _faceThreshold = TextEditingController(text: split.$1);
    _faceOff = TextEditingController(text: split.$2);
    _qty = TextEditingController(text: widget.initial.inventoryQty);
    _suppliers = TextEditingController(text: widget.initial.supplierCodes);
    _quantity = TextEditingController(text: '${widget.quantity}');
    _syncZhongyouHaoke = widget.initial.syncZhongyouHaoke;
    _parentSkuId = widget.initial.parentSkuId;
    _rollback = proposalIntakeSkuRollbackValue(widget.initial);
    _couponKind = widget.initial.resolvedCouponKind;
  }

  @override
  void dispose() {
    _name.dispose();
    _remark.dispose();
    _face.dispose();
    _faceThreshold.dispose();
    _faceOff.dispose();
    _qty.dispose();
    _suppliers.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.readOnly) {
      Navigator.pop(context);
      return;
    }
    if (_couponKind.trim().isEmpty) return;
    if (!widget.childProduct && _name.text.trim().isEmpty) return;
    if (widget.childProduct && _parentSkuId.trim().isEmpty) return;
    final quantity = int.tryParse(_quantity.text.trim()) ?? 1;
    final couponKind = proposalIntakeNormalizeCouponKind(_couponKind);
    final faceValue = couponKind == kProposalCouponKindDiscount
        ? proposalIntakeJoinDiscountFace(_faceThreshold.text, _faceOff.text)
        : _face.text.trim();
    final productName = widget.childProduct
        ? (_name.text.trim().isEmpty ? couponKind : _name.text.trim())
        : _name.text.trim();
    Navigator.pop(
      context,
      _SkuProductDraft(
        row: widget.initial.copyWith(
          productName: productName,
          couponKind: couponKind,
          faceValue: faceValue,
          inventoryQty: _qty.text.trim(),
          supplierCodes: _suppliers.text.trim(),
          syncZhongyouHaoke: _syncZhongyouHaoke,
          parentSkuId: widget.childProduct ? _parentSkuId : '',
          rollback: _rollback,
          remark: _remark.text.trim(),
        ),
        quantity: quantity < 1 ? 1 : quantity,
        linked: couponKind == kProposalCouponKindBenefit
            ? [for (final item in _linked) item]
            : const [],
      ),
    );
  }

  Future<void> _addLinked() async {
    final result = await showDialog<_SkuProductDraft>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SkuProductEditorDialog(
        childProduct: true,
        creating: true,
        initial: ProposalSkuDetailRow(
          id: proposalIntakeNewChildSkuId(),
          existingBuilt: widget.initial.existingBuilt,
          rollback: kProposalDefaultRollback,
          syncSourceRef: widget.initial.syncSourceRef,
          parentSkuId: widget.initial.id,
          settlements: const [],
        ),
        quantity: 1,
        mainProducts: widget.mainProducts,
        rollbackOptions: widget.rollbackOptions,
        readOnly: widget.readOnly,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _linked.add(result));
  }

  Future<void> _removeLinked(int index) async {
    final item = _linked[index];
    final name = item.row.productName.trim().isNotEmpty
        ? item.row.productName.trim()
        : (item.row.resolvedCouponKind.isEmpty
              ? '关联产品 ${index + 1}'
              : item.row.resolvedCouponKind);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认移除'),
        content: Text('确定移除「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _linked.removeAt(index));
  }

  void _pasteLinked(int index) {
    final source = _linkedClipboard;
    if (source == null) return;
    final target = _linked[index];
    setState(() {
      _linked[index] = _SkuProductDraft(
        row: proposalIntakeCloneSkuProduct(
          source.row,
          id: target.row.id,
          parentSkuId: target.row.parentSkuId,
        ),
        quantity: source.quantity,
      );
    });
  }

  Widget _linkedPreview(int index) {
    final item = _linked[index];
    final row = item.row;
    final name = row.productName.trim().isNotEmpty
        ? row.productName.trim()
        : row.resolvedCouponKind;
    final bits = <String>[
      if (row.resolvedCouponKind.isNotEmpty && row.resolvedCouponKind != name)
        row.resolvedCouponKind,
      if (row.faceValue.trim().isNotEmpty) '面值 ${row.faceValue.trim()}',
      if (row.inventoryQty.trim().isNotEmpty) '库存 ${row.inventoryQty.trim()}',
      if (row.supplierCodes.trim().isNotEmpty)
        '供应商 ${row.supplierCodes.trim()}',
      if (row.syncZhongyouHaoke.trim().isNotEmpty) row.syncZhongyouHaoke.trim(),
      if (row.rollback.trim().isNotEmpty) row.rollback.trim(),
      '数量 ${item.quantity}',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          ProposalPalette.soft,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? '关联产品 ${index + 1}' : '关联产品 ${index + 1} · $name',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: DunesColors.resolve(context, ProposalPalette.text),
            ),
          ),
          if (bits.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              bits.join(' · '),
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => unawaited(_removeLinked(index)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('移除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _discountFaceField() {
    final display = proposalIntakeJoinDiscountFace(
      _faceThreshold.text,
      _faceOff.text,
    );
    return ProposalField(
      label: '面值',
      child: widget.readOnly
          ? Text(
              display.isEmpty ? '未填写' : display,
              style: TextStyle(
                fontSize: 13,
                color: display.isEmpty
                    ? DunesColors.resolve(context, ProposalPalette.text3)
                    : DunesColors.resolve(context, ProposalPalette.text),
                fontWeight: FontWeight.w600,
              ),
            )
          : Row(
              children: [
                Text(
                  '满',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, ProposalPalette.text2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _faceThreshold,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: proposalInputDecoration(
                      context: context,
                      hint: '门槛',
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '减',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(
                        context,
                        ProposalPalette.text2,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _faceOff,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: proposalInputDecoration(
                      context: context,
                      hint: '优惠',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return ProposalField(
      label: label,
      required: required,
      child: widget.readOnly
          ? Text(
              controller.text.trim().isEmpty ? '未填写' : controller.text.trim(),
              style: TextStyle(
                fontSize: 13,
                color: controller.text.trim().isEmpty
                    ? DunesColors.resolve(context, ProposalPalette.text3)
                    : DunesColors.resolve(context, ProposalPalette.text),
                fontWeight: FontWeight.w600,
              ),
            )
          : TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: proposalInputDecoration(context: context, hint: hint),
            ),
    );
  }

  Widget _pair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.childProduct
        ? (widget.creating ? '新增关联' : '编辑关联')
        : '业务产品信息填写';
    final face = _couponKind == kProposalCouponKindDiscount
        ? _discountFaceField()
        : _textField(label: '面值', controller: _face, hint: '手填');
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.childProduct) ...[
                _pair(
                  _textField(
                    label: '业务产品名称',
                    controller: _name,
                    hint: '默认提案名称，可修改',
                    required: true,
                  ),
                  _textField(label: '业务产品说明', controller: _remark, hint: '选填'),
                ),
                const SizedBox(height: 10),
              ],
              _pair(
                ProposalField(
                  label: '类型',
                  required: true,
                  child: widget.readOnly
                      ? Text(
                          _couponKind.trim().isEmpty ? '未填写' : _couponKind,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : ProposalSelectField<String>(
                          value: _couponKind.isEmpty ? null : _couponKind,
                          title: '类型',
                          hint: '请选择现金券、满减券或权益',
                          options: [
                            for (final value in kProposalCouponKinds)
                              ProposalSelectOption(value: value, label: value),
                          ],
                          onSelected: (value) => setState(() {
                            _couponKind = proposalIntakeNormalizeCouponKind(
                              value ?? '',
                            );
                            if (_couponKind == kProposalCouponKindDiscount &&
                                _faceThreshold.text.trim().isEmpty &&
                                _faceOff.text.trim().isEmpty &&
                                _face.text.trim().isNotEmpty &&
                                !proposalIntakeIsDiscountFace(_face.text)) {
                              _faceThreshold.text = _face.text.trim();
                            }
                          }),
                        ),
                ),
                face,
              ),
              const SizedBox(height: 10),
              _pair(
                _textField(
                  label: '库存数量',
                  controller: _qty,
                  hint: '数字',
                  keyboardType: TextInputType.number,
                ),
                _textField(
                  label: '供应商编码',
                  controller: _suppliers,
                  hint: '多个用 | 分隔，越前面的排名越高，例如 A|B|C',
                ),
              ),
              const SizedBox(height: 10),
              _pair(
                ProposalField(
                  label: '是否回滚',
                  required: true,
                  child: widget.readOnly
                      ? Text(
                          _rollback.trim().isEmpty
                              ? kProposalDefaultRollback
                              : _rollback,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : ProposalSelectField<String>(
                          value: _rollback.isEmpty ? null : _rollback,
                          title: '是否回滚',
                          hint: '请选择',
                          options: [
                            for (final value in widget.rollbackOptions)
                              ProposalSelectOption(value: value, label: value),
                          ],
                          onSelected: (value) => setState(
                            () => _rollback =
                                (value ?? kProposalDefaultRollback).trim(),
                          ),
                        ),
                ),
                ProposalField(
                  label: '是否同步中油好客',
                  child: widget.readOnly
                      ? Text(
                          _syncZhongyouHaoke.trim().isEmpty
                              ? '未填写'
                              : _syncZhongyouHaoke,
                          style: TextStyle(
                            fontSize: 13,
                            color: _syncZhongyouHaoke.trim().isEmpty
                                ? DunesColors.resolve(
                                    context,
                                    ProposalPalette.text3,
                                  )
                                : DunesColors.resolve(
                                    context,
                                    ProposalPalette.text,
                                  ),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : ProposalSelectField<String>(
                          value: _syncZhongyouHaoke.isEmpty
                              ? null
                              : _syncZhongyouHaoke,
                          title: '是否同步中油好客',
                          hint: '请选择',
                          options: const [
                            ProposalSelectOption(value: '同步', label: '同步'),
                            ProposalSelectOption(value: '不同步', label: '不同步'),
                          ],
                          onSelected: (value) =>
                              setState(() => _syncZhongyouHaoke = value ?? ''),
                        ),
                ),
              ),
              if (widget.childProduct) ...[
                const SizedBox(height: 10),
                _textField(
                  label: '关联产品数量',
                  controller: _quantity,
                  hint: '至少为 1',
                  required: true,
                  keyboardType: TextInputType.number,
                ),
              ],
              if (!widget.childProduct &&
                  _couponKind == kProposalCouponKindBenefit) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: widget.readOnly ? null : _addLinked,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增关联'),
                  ),
                ),
                for (var i = 0; i < _linked.length; i++) _linkedPreview(i),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.readOnly ? '关闭' : '取消'),
        ),
        if (!widget.readOnly)
          FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

class _SettleCatalogBundle {
  const _SettleCatalogBundle({
    this.channels = const [],
    this.suppliers = const [],
    this.billTypes = const [],
    this.settleMethods = const [],
    this.formulas = const [],
  });

  final List<CatalogRef> channels;
  final List<CatalogRef> suppliers;
  final List<CatalogRef> billTypes;
  final List<CatalogRef> settleMethods;
  final List<CatalogRef> formulas;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
