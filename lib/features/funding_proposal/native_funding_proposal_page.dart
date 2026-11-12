import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../proposal_intake/proposal_business_approvals.dart';
import '../proposal_intake/proposal_estimate_summary.dart';
import '../proposal_intake/proposal_intake_models.dart';
import '../proposal_intake/proposal_intake_select.dart';
import '../proposal_intake/proposal_intake_service.dart';
import '../proposal_intake/proposal_intake_ui.dart';
import '../proposal_intake/proposal_list_card.dart';
import '../proposal_intake/settlement_catalog.dart';
import '../shell/dunes_toast.dart';
import '../xflow/approval_chat_forward.dart';
import '../xflow/approval_chat_share.dart';
import 'funding_proposal_models.dart';
import 'funding_proposal_opener.dart';
import 'funding_proposal_service.dart';

// 分段条三色：净收益 / 利息 / 服务费+杂费。跑过色弱校验，相邻两段可区分。
const _kListAccent = Color(0xFF4A3A9A);
const _kListPage = Color(0xFFF7F6FB);
const _kPhoneTextScale = 0.82;
const _kDesktopTextScale = 0.95;

const _kNetColor = Color(0xFF3F8F5A);
const _kInterestColor = Color(0xFF7B5CD8);
const _kFeeColor = Color(0xFFC9842A);
const _kBufferColor = Color(0xFFCDBEF2);

Color _c(
  BuildContext context,
  Color light, {
  DunesColorRole role = DunesColorRole.foreground,
}) => DunesColors.resolve(context, light, role: role);

/// 手机触摸点到输入框外默认不收键盘，这里点空白、点别的控件都收起。
void _dismissKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
}

/// 工作台加载时接上，审批里的「查看提案」才能打开资金提案。
void ensureFundingProposalOpener() {
  openFundingProposalFromApproval ??=
      ({
        required BuildContext context,
        required AuthSession session,
        required int proposalId,
      }) {
        return Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => NativeFundingProposalPage(
              session: session,
              openId: proposalId,
              linkedFromApproval: true,
            ),
          ),
        );
      };
}

/// 工作台「资金提案」：融资立项申请的填写、提交和四级审批。
///
/// 所有下拉、测算、校验都来自后端；本页只负责收集输入和展示结果。
class NativeFundingProposalPage extends StatefulWidget {
  const NativeFundingProposalPage({
    super.key,
    required this.session,
    this.openId,
    this.linkedFromApproval = false,
  });

  final AuthSession session;

  /// 从业务审批打开某一条资金提案。
  final int? openId;

  /// 返回时关掉这一层，不再落到资金提案列表。
  final bool linkedFromApproval;

  @override
  State<NativeFundingProposalPage> createState() =>
      _NativeFundingProposalPageState();
}

class _NativeFundingProposalPageState extends State<NativeFundingProposalPage> {
  final http.Client _http = http.Client();
  late final FundingProposalService _service = FundingProposalService(
    session: widget.session,
    client: _http,
  );
  late final ProposalIntakeService _intake = ProposalIntakeService(
    session: widget.session,
  );
  final SettlementCatalogService _catalog = SettlementCatalogService();
  final _keyword = TextEditingController();
  Timer? _searchDebounce;
  bool _disposed = false;
  bool _lookupsStarted = false;

  FundingAccess _access = const FundingAccess();
  FundingOptions _options = const FundingOptions();
  List<ProposalPerson> _people = const [];
  List<CatalogRef> _ourEntities = const [];
  List<CatalogRef> _counterparties = const [];

  String _scope = 'mine';
  FundingListResult _list = const FundingListResult();
  bool _booting = true;
  bool _loading = false;
  bool _creating = false;
  String? _error;
  FundingProposal? _open;

  @override
  void initState() {
    super.initState();
    ensureFundingProposalOpener();
    unawaited(_bootstrap());
  }

  bool get _alive => mounted && !_disposed;

  /// 离开页面前先丢掉焦点。键盘连接留着的话，返回后整个界面还会跟着刷新。
  void _releaseFocus() {
    final focus = FocusManager.instance.primaryFocus;
    final nodeContext = focus?.context;
    if (nodeContext is! Element || !nodeContext.mounted) return;
    if (nodeContext
            .findAncestorStateOfType<_NativeFundingProposalPageState>() ==
        this) {
      focus?.unfocus();
    }
  }

  @override
  void deactivate() {
    _releaseFocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _http.close();
    _keyword.dispose();
    _catalog.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait<Object>([
        _service.fetchAccess(),
        _service.fetchOptions(),
      ]);
      if (!_alive) return;
      setState(() {
        _access = results[0] as FundingAccess;
        _options = results[1] as FundingOptions;
      });
      await _reload();
      final openId = widget.openId;
      if (_alive && openId != null && openId > 0) {
        try {
          _ensureLookups();
          final full = await _service.fetch(openId);
          if (_alive) setState(() => _open = full);
        } catch (error) {
          if (_alive) {
            setState(() => _error = friendlyErrorText(error, fallback: '打开失败'));
          }
        }
      } else if (_alive && _list.todoCount > 0 && _list.items.isEmpty) {
        setState(() => _scope = 'todo');
        await _reload();
      }
    } catch (error) {
      if (_alive) {
        setState(() => _error = friendlyErrorText(error, fallback: '资金提案加载失败'));
      }
    } finally {
      if (_alive) setState(() => _booting = false);
    }
  }

  /// 人员和主体字典只在填写时用，加载失败不挡列表。
  Future<void> _loadLookups() async {
    Future<T> safe<T>(Future<T> Function() run, T fallback) async {
      try {
        return await run();
      } catch (_) {
        return fallback;
      }
    }

    final people = await safe(
      () => _intake.fetchPeople(client: _http),
      const <ProposalPerson>[],
    );
    final ours = await safe(_catalog.fetchOurEntities, const <CatalogRef>[]);
    final theirs = await safe(
      _catalog.fetchCounterpartyEntities,
      const <CatalogRef>[],
    );
    if (!_alive) return;
    setState(() {
      _people = people;
      _ourEntities = ours;
      _counterparties = theirs;
    });
  }

  /// 人员和组织字典只在打开某一条提案时用，列表页不拉，避免返回后还在解析。
  void _ensureLookups() {
    if (_lookupsStarted || _disposed) return;
    _lookupsStarted = true;
    unawaited(_loadLookups());
  }

  Future<void> _reload() async {
    if (!_alive) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchList(
        scope: _scope,
        keyword: _keyword.text,
      );
      if (!_alive) return;
      setState(() => _list = list);
    } catch (error) {
      if (_alive) {
        setState(() => _error = friendlyErrorText(error, fallback: '列表加载失败'));
      }
    } finally {
      if (_alive) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final row = await _service.create(const {});
      if (!_alive) return;
      _ensureLookups();
      setState(() => _open = row);
    } catch (error) {
      if (mounted && !_disposed) {
        showDunesToast(context, friendlyErrorText(error, fallback: '新建失败'));
      }
    } finally {
      if (_alive) setState(() => _creating = false);
    }
  }

  Future<void> _openRow(FundingProposal row) async {
    try {
      _ensureLookups();
      final full = await _service.fetch(row.id);
      if (!_alive) return;
      setState(() => _open = full);
    } catch (error) {
      if (mounted && !_disposed) {
        showDunesToast(context, friendlyErrorText(error, fallback: '打开失败'));
      }
    }
  }

  void _closeEditor() {
    if (widget.linkedFromApproval && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _open = null);
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final phone = ProposalLayout.isCompact(media.size.width);
    final system = (media.textScaler.scale(100) / 100).clamp(0.8, 1.3);
    final open = _open;
    final Widget page;
    if (widget.openId != null && open == null) {
      page = _booting
          ? const Center(child: CircularProgressIndicator())
          : _openFailed();
    } else {
      page = open != null ? _editor(open) : _listPage();
    }
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(
          system * (phone ? _kPhoneTextScale : _kDesktopTextScale),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: kProposalProtoSans,
          fontFamilyFallback: kProposalProtoSansFallback,
        ),
        child: page,
      ),
    );
  }

  Widget _openFailed() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? '打开失败'),
          const SizedBox(height: 8),
          TextButton(onPressed: _closeEditor, child: const Text('返回')),
        ],
      ),
    );
  }

  Widget _editor(FundingProposal open) {
    return RepaintBoundary(
      child: _FundingEditor(
        key: ValueKey('funding-${open.id}'),
        initial: open,
        service: _service,
        intake: _intake,
        options: _options,
        people: _people,
        ourEntities: _ourEntities,
        counterparties: _counterparties,
        onBack: _closeEditor,
      ),
    );
  }

  Widget _listPage() {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Material(
          color: _c(context, _kListPage, role: DunesColorRole.surface),
          child: _buildList(context),
        ),
      ),
    );
  }

  List<(String, String)> get _scopes => [
    ('mine', '我发起的'),
    ('todo', _list.todoCount > 0 ? '待我审批 ${_list.todoCount}' : '待我审批'),
    ('all', _access.viewAll ? '全部' : '与我相关'),
  ];

  void _setScope(String key) {
    if (_scope == key) return;
    setState(() => _scope = key);
    unawaited(_reload());
  }

  List<ProposalListStep> _fundingSteps(FundingProposal row) {
    const nodes = [
      ('funding', '资金'),
      ('finance', '财务'),
      ('risk', '风控'),
      ('gm', '总经理'),
    ];
    if (row.status == kFundingStatusApproved) {
      return [
        for (final node in nodes)
          ProposalListStep(node.$2, ProposalListStepState.done),
      ];
    }
    if (row.status != kFundingStatusReviewing) {
      return [
        for (final node in nodes)
          ProposalListStep(node.$2, ProposalListStepState.todo),
      ];
    }
    final current = nodes.indexWhere((node) => node.$1 == row.currentNode);
    return [
      for (var i = 0; i < nodes.length; i++)
        ProposalListStep(
          nodes[i].$2,
          current < 0
              ? ProposalListStepState.todo
              : i < current
              ? ProposalListStepState.done
              : i == current
              ? ProposalListStepState.now
              : ProposalListStepState.todo,
        ),
    ];
  }

  ProposalListCardData _fundingCard(FundingProposal row, int index) {
    final form = row.form;
    final party = '${form['counterpartyName'] ?? ''}'.trim();
    final ours = '${form['ourPartyName'] ?? ''}'.trim();
    final financing = _grouped('${form['financingAmount'] ?? ''}');
    final net = row.estimate.text('netProfit', fallback: '');
    final title = row.title.isEmpty ? '资金提案' : row.title;
    final now = switch (row.status) {
      kFundingStatusReviewing =>
        '待${row.currentNodeLabel}${row.currentApproverName.isEmpty ? '' : ' ${row.currentApproverName}'}审批',
      kFundingStatusRejected => '已驳回，修改后可重新提交',
      kFundingStatusApproved => '已通过',
      _ => '草稿',
    };
    return ProposalListCardData(
      index: index,
      tag1: party.isEmpty ? title : party,
      name: title,
      nameLabel: '提案名称',
      chips: [if (row.code.isNotEmpty) row.code, if (ours.isNotEmpty) ours],
      proposalType: '资金',
      scale: financing.isEmpty ? '—' : financing,
      mid: [
        ProposalListCardMetric(
          label: '融资需求',
          value: financing.isEmpty ? '—' : financing,
          mono: true,
        ),
        ProposalListCardMetric(
          label: '对方主体',
          value: party.isEmpty ? '—' : party,
          wrap: true,
        ),
      ],
      right: [
        ProposalListCardMetric(
          label: '净收益',
          value: net.isEmpty || net == '—' ? '—' : net,
          mono: true,
        ),
        ProposalListCardMetric(
          label: '申请人',
          value: row.createdByName.isEmpty ? '—' : row.createdByName,
          wrap: true,
        ),
      ],
      steps: _fundingSteps(row),
      nowText: now,
      days: fundingStatusLabel(row.status),
      daysWarn: row.status == kFundingStatusRejected,
    );
  }

  Widget _listHeader({required bool compact, required Widget search}) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _c(context, _kListAccent, role: DunesColorRole.surface),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.description_outlined,
            size: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '资金提案',
          style: TextStyle(
            fontSize: compact ? 17 : 19,
            fontWeight: FontWeight.w800,
            color: _c(context, _kListAccent),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            'FUNDING',
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 2,
              color: _c(context, const Color(0xFF8A85A0)),
            ),
          ),
        ),
      ],
    );
    final refresh = IconButton(
      tooltip: '刷新',
      onPressed: _loading ? null : _reload,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: _c(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        side: BorderSide(
          color: _c(
            context,
            const Color(0xFFE4E1EE),
            role: DunesColorRole.border,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        fixedSize: const Size(36, 36),
      ),
      icon: Icon(
        Icons.refresh_rounded,
        size: 18,
        color: _c(context, _kListAccent),
      ),
    );
    final create = _access.fill
        ? FilledButton.icon(
            onPressed: _creating ? null : _create,
            style: FilledButton.styleFrom(
              backgroundColor: _c(
                context,
                _kListAccent,
                role: DunesColorRole.surface,
              ),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: Text(_creating ? '新建中…' : (compact ? '新建' : '新建资金提案')),
          )
        : null;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(child: title),
              const Spacer(),
              refresh,
              if (create != null) ...[const SizedBox(width: 6), create],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(height: 38, child: search),
        ],
      );
    }
    return Row(
      children: [
        title,
        const Spacer(),
        SizedBox(width: 300, height: 38, child: search),
        const SizedBox(width: 8),
        refresh,
        if (create != null) ...[const SizedBox(width: 8), create],
      ],
    );
  }

  Widget _summaryTiles({required bool compact}) {
    if (_list.items.isEmpty) return const SizedBox.shrink();
    final reviewing = _list.items
        .where((row) => row.status == kFundingStatusReviewing)
        .length;
    final approved = _list.items
        .where((row) => row.status == kFundingStatusApproved)
        .length;
    var financing = 0.0;
    for (final row in _list.items) {
      final raw = '${row.form['financingAmount'] ?? ''}'.replaceAll(',', '');
      financing += double.tryParse(raw) ?? 0;
    }
    final text = financing == financing.roundToDouble()
        ? _grouped(financing.toStringAsFixed(0))
        : _grouped(financing.toStringAsFixed(2));
    Widget tile(String label, String value, String unit) => Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 14,
          vertical: compact ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: _c(context, Colors.white, role: DunesColorRole.surface),
          border: Border.all(
            color: _c(
              context,
              const Color(0xFFE8E5F1),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: _c(context, const Color(0xFF6B6680)),
              ),
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: compact ? 15 : 20,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: _c(context, const Color(0xFF1F1B2E)),
                  fontFamily: kProposalProtoMono,
                  fontFamilyFallback: kProposalProtoMonoFallback,
                ),
                children: [
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      fontSize: compact ? 10.5 : 12,
                      fontWeight: FontWeight.w400,
                      color: _c(context, const Color(0xFF6B6680)),
                      fontFamily: kProposalProtoSans,
                      fontFamilyFallback: kProposalProtoSansFallback,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        tile('审批中', '$reviewing', ' 份'),
        SizedBox(width: compact ? 6 : 10),
        tile('融资需求', text.isEmpty ? '0' : text, ' 元'),
        SizedBox(width: compact ? 6 : 10),
        tile('已通过', '$approved', ' 份'),
      ],
    );
  }

  Widget _scopeTabs({required bool compact}) {
    return Container(
      decoration: BoxDecoration(
        color: _c(context, Colors.white, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(
            context,
            const Color(0xFFE8E5F1),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (key, label) in _scopes)
              InkWell(
                onTap: () => _setScope(key),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 11 : 16,
                    10,
                    compact ? 11 : 16,
                    8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _scope == key
                            ? _c(context, _kListAccent)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _scope == key
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _c(
                        context,
                        _scope == key ? _kListAccent : const Color(0xFF6B6680),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_booting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_access.view) {
      return Center(
        child: Text(
          _error ?? '你还没有资金提案权限，请联系管理员开通「提案」权限',
          style: TextStyle(color: _c(context, ProposalPalette.text2)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = ProposalLayout.isCompact(constraints.maxWidth);
        final search = TextField(
          controller: _keyword,
          onTapOutside: (_) => _dismissKeyboard(),
          style: const TextStyle(fontSize: 13, height: 1.2),
          decoration:
              proposalInputDecoration(
                context: context,
                hint: '搜索名称、编号、对方主体',
              ).copyWith(
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
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(
              const Duration(milliseconds: 350),
              () => unawaited(_reload()),
            );
          },
        );
        final List<Widget> cards = [
          for (var i = 0; i < _list.items.length; i++)
            ProposalListCard(
              data: _fundingCard(_list.items[i], i),
              onTap: () => unawaited(_openRow(_list.items[i])),
            ),
        ];
        final empty = Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              _error ?? (_scope == 'todo' ? '没有待你审批的资金提案' : '还没有资金提案'),
              style: TextStyle(color: _c(context, ProposalPalette.text2)),
            ),
          ),
        );
        final List<Widget> rows = _loading && _list.items.isEmpty
            ? const <Widget>[
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ]
            : _list.items.isEmpty
            ? <Widget>[empty]
            : cards;
        final header = _listHeader(compact: compact, search: search);
        final tiles = _summaryTiles(compact: compact);
        final tabs = _scopeTabs(compact: compact);
        if (compact) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              primary: false,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                header,
                if (_list.items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  tiles,
                ],
                const SizedBox(height: 10),
                tabs,
                const SizedBox(height: 8),
                ...rows,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (_list.items.isNotEmpty) ...[
                const SizedBox(height: 12),
                tiles,
              ],
              const SizedBox(height: 12),
              tabs,
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    primary: false,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: rows,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _fmtTime(DateTime? t) {
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 只给展示用的千分位，不参与任何计算。
String _grouped(String raw) {
  final text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return '';
  if (double.tryParse(text) == null) return raw;
  final neg = text.startsWith('-');
  final body = neg ? text.substring(1) : text;
  final parts = body.split('.');
  final intPart = parts.first;
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final frac = parts.length > 1 ? '.${parts[1]}' : '';
  return '${neg ? '-' : ''}$buf$frac';
}

// ======================================================================
// 填写 / 审批
// ======================================================================

class _FundingEditor extends StatefulWidget {
  const _FundingEditor({
    super.key,
    required this.initial,
    required this.service,
    required this.intake,
    required this.options,
    required this.people,
    required this.ourEntities,
    required this.counterparties,
    required this.onBack,
  });

  final FundingProposal initial;
  final FundingProposalService service;
  final ProposalIntakeService intake;
  final FundingOptions options;
  final List<ProposalPerson> people;
  final List<CatalogRef> ourEntities;
  final List<CatalogRef> counterparties;
  final VoidCallback onBack;

  @override
  State<_FundingEditor> createState() => _FundingEditorState();
}

class _FundingEditorState extends State<_FundingEditor> {
  late FundingProposal _row = widget.initial;
  late Map<String, dynamic> _form = _clone(widget.initial.form);
  late FundingEstimate _est = widget.initial.estimate;
  final Map<String, TextEditingController> _ctls = {};
  final _decisionComment = TextEditingController();
  Timer? _estimateDebounce;
  bool _dirty = false;
  bool _busy = false;
  bool _estimating = false;
  bool _uploading = false;
  bool _progressOpen = true;
  bool _forwarding = false;
  int _estimateSeq = 0;
  final _bizKey = GlobalKey();

  FundingOptions get _opts => widget.options;
  FundingPermissions get _perm => _row.permissions;
  bool get _editable => _perm.canEdit;

  /// 业务审批面板沿用销售提案那一块，这里只换来源和「已通过」状态。
  ProposalIntakeRow _asIntake() {
    final form = Map<String, dynamic>.from(_form);
    final project = '${form['projectName'] ?? ''}'.trim();
    final party = '${form['counterpartyName'] ?? ''}'.trim();
    if (project.isEmpty && party.isNotEmpty) form['projectName'] = party;
    return ProposalIntakeRow(
      id: _row.id,
      code: _row.code,
      title: _row.title.isEmpty ? '资金提案' : _row.title,
      status: _row.status,
      kind: 'funding',
      form: form,
      review: const {},
      createdBy: _row.createdBy,
      createdAt: _row.createdAt?.toIso8601String() ?? '',
      updatedAt: _row.updatedAt?.toIso8601String() ?? '',
      version: _row.version,
    );
  }

  static Map<String, dynamic> _clone(Map<String, dynamic> raw) {
    final decoded = jsonDecode(jsonEncode(raw));
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    for (final c in _ctls.values) {
      c.dispose();
    }
    _decisionComment.dispose();
    super.dispose();
  }

  // ---- 表单读写 ----

  String _text(String key) => '${_form[key] ?? ''}'.trim();

  List<Map<String, dynamic>> get _funders {
    final raw = _form['funders'];
    if (raw is List) {
      final list = [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      _form['funders'] = list;
      return list;
    }
    final list = <Map<String, dynamic>>[];
    _form['funders'] = list;
    return list;
  }

  Map<String, dynamic> get _approvers {
    final raw = _form['approvers'];
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    _form['approvers'] = map;
    return map;
  }

  Map<String, dynamic> get _materials {
    final raw = _form['materials'];
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    _form['materials'] = map;
    return map;
  }

  List<Map<String, dynamic>> _filesOf(String key) {
    final raw = _materials[key];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  TextEditingController _ctl(String id, String initial) =>
      _ctls.putIfAbsent(id, () => TextEditingController(text: initial));

  void _changed() {
    _dirty = true;
    _scheduleEstimate();
    setState(() {});
  }

  void _set(String key, String value) {
    _form[key] = value;
    _changed();
  }

  void _setFunder(String rowId, String key, String value) {
    final list = _funders;
    for (final row in list) {
      if ('${row['rowId']}' == rowId) row[key] = value;
    }
    _form['funders'] = list;
    _changed();
  }

  void _addFunder() {
    final list = _funders;
    list.add({
      'rowId': 'r${DateTime.now().microsecondsSinceEpoch}',
      'type': '',
      'party': '',
      'partyName': '',
      'amount': '',
      'drawDate': _text('prepayDate'),
      'termDays': '',
      'annualRate': '',
      'serviceFeeRate': '',
    });
    _form['funders'] = list;
    _changed();
  }

  void _removeFunder(String rowId) {
    final list = _funders..removeWhere((row) => '${row['rowId']}' == rowId);
    _form['funders'] = list;
    _changed();
  }

  void _scheduleEstimate() {
    if (!_editable) return;
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 400), _runEstimate);
  }

  Future<void> _runEstimate() async {
    final seq = ++_estimateSeq;
    setState(() => _estimating = true);
    try {
      final est = await widget.service.estimate(_clone(_form));
      if (!mounted || seq != _estimateSeq) return;
      setState(() => _est = est);
    } catch (_) {
      // 测算失败保留上一次结果，提交时后端还会再算。
    } finally {
      if (mounted && seq == _estimateSeq) setState(() => _estimating = false);
    }
  }

  void _adopt(FundingProposal row) {
    setState(() {
      _row = row;
      _form = _clone(row.form);
      _est = row.estimate;
      _dirty = false;
    });
  }

  Future<void> _guard(Future<void> Function() run, String fallback) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
    } catch (error) {
      if (mounted)
        showDunesToast(context, friendlyErrorText(error, fallback: fallback));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _guard(() async {
    final row = await widget.service.save(
      _row.id,
      _clone(_form),
      version: _row.version,
    );
    if (!mounted) return;
    _adopt(row);
    showDunesToast(context, '已保存');
  }, '保存失败');

  Future<void> _submit() => _guard(() async {
    final row = await widget.service.submit(
      _row.id,
      _clone(_form),
      version: _row.version,
    );
    if (!mounted) return;
    _adopt(row);
    showDunesToast(context, '已提交，等待${row.currentNodeLabel}审批');
  }, '提交失败');

  Future<void> _withdraw() async {
    final ok = await _confirm('撤回资金提案', '撤回后回到草稿，可修改后重新提交。');
    if (!ok) return;
    await _guard(() async {
      final row = await widget.service.withdraw(_row.id, version: _row.version);
      if (!mounted) return;
      _adopt(row);
      showDunesToast(context, '已撤回');
    }, '撤回失败');
  }

  Future<void> _delete() async {
    final ok = await _confirm('删除草稿', '删除后不能恢复。');
    if (!ok) return;
    await _guard(() async {
      await widget.service.delete(_row.id, version: _row.version);
      if (!mounted) return;
      showDunesToast(context, '已删除');
      widget.onBack();
    }, '删除失败');
  }

  Future<void> _approve() => _guard(() async {
    final row = await widget.service.decide(
      _row.id,
      approved: true,
      version: _row.version,
      comment: _decisionComment.text.trim(),
    );
    if (!mounted) return;
    _decisionComment.clear();
    _adopt(row);
    showDunesToast(context, '已同意');
  }, '审批失败');

  Future<void> _reject() async {
    final reason = await showProposalRejectDialog(
      context: context,
      title: '驳回资金提案',
      hint: '写下驳回原因，申请人会收到',
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _guard(() async {
      final row = await widget.service.decide(
        _row.id,
        approved: false,
        version: _row.version,
        comment: reason.trim(),
      );
      if (!mounted) return;
      _adopt(row);
      showDunesToast(context, '已驳回');
    }, '驳回失败');
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _back() async {
    if (_dirty && _editable) {
      final leave = await _confirm('还没保存', '有改动还没保存，确定离开？');
      if (!leave) return;
    }
    widget.onBack();
  }

  Future<void> _forward() async {
    if (_forwarding || _row.id <= 0) return;
    setState(() => _forwarding = true);
    try {
      await forwardApprovalToConversation(
        context: context,
        session: widget.service.session,
        share: ApprovalChatShare.fromFundingProposal(
          id: _row.id,
          title: _row.title.isEmpty ? '资金提案' : _row.title,
          status: _row.status,
          code: _row.code,
          submitterName: _row.createdByName,
        ),
      );
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
  }

  void _scrollToBiz() {
    final target = _bizKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 280),
      alignment: 0.08,
    );
  }

  // ---- 材料 ----

  Future<void> _pickFiles(String key) async {
    if (_uploading) return;
    List<XFile> picked = const [];
    try {
      picked = await openFiles();
    } catch (_) {
      return;
    }
    if (picked.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final current = _filesOf(key);
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final up = await widget.intake.uploadFile(
          bytes: bytes,
          fileName: file.name,
          mimeType: file.mimeType ?? 'application/octet-stream',
        );
        current.add({
          'fileName': up.fileName,
          'objectKey': up.objectKey,
          'url': up.url,
          'sizeBytes': up.sizeBytes,
          'mimeType': up.mimeType,
        });
      }
      await _writeMaterials(key, current);
    } catch (error) {
      if (mounted)
        showDunesToast(context, friendlyErrorText(error, fallback: '上传失败'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeFile(String key, int index) async {
    final current = _filesOf(key);
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _writeMaterials(key, current);
  }

  /// 可编辑时跟着表单一起保存；审批中只单独存材料。
  Future<void> _writeMaterials(
    String key,
    List<Map<String, dynamic>> files,
  ) async {
    final materials = _materials..[key] = files;
    _form['materials'] = materials;
    if (_editable) {
      _changed();
      return;
    }
    final row = await widget.service.saveMaterials(
      _row.id,
      _clone(materials),
      version: _row.version,
    );
    if (mounted) _adopt(row);
  }

  Future<void> _openFile(Map<String, dynamic> file) async {
    final url = '${file['url'] ?? ''}'.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ---- 布局 ----

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: Material(
        color: _c(context, ProposalPalette.page, role: DunesColorRole.surface),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            final panel = _EstimatePanel(
              estimate: _est,
              loading: _estimating,
              live: _editable,
            );
            final form = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _businessSection(context),
                _financingSection(context),
                _materialsSection(context),
                _approversSection(context),
                _noteSection(context),
                if (_row.events.isNotEmpty || _perm.canDecide)
                  _historySection(context),
              ],
            );
            return Column(
              children: [
                _topBar(),
                if (_progressOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _ApprovalPath(row: _row, options: _opts),
                  ),
                Expanded(
                  child: ListView(
                    primary: false,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1360),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _titleBlock(context),
                              const SizedBox(height: 16),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: form),
                                    const SizedBox(width: 20),
                                    SizedBox(width: 360, child: panel),
                                  ],
                                )
                              else ...[
                                panel,
                                const SizedBox(height: 16),
                                form,
                              ],
                              const SizedBox(height: 16),
                              KeyedSubtree(
                                key: _bizKey,
                                child: ProposalBusinessApprovals(
                                  key: ValueKey('funding-business-${_row.id}'),
                                  session: widget.service.session,
                                  proposal: _asIntake(),
                                  funding: true,
                                  people: widget.people,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static const _topToolH = 28.0;

  BoxDecoration get _topToolDecoration => BoxDecoration(
    color: _c(context, const Color(0xFFF3EFFA), role: DunesColorRole.surface),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: _c(
        context,
        ProposalPalette.borderStrong,
        role: DunesColorRole.border,
      ),
      width: 0.8,
    ),
  );

  Widget _topBar() {
    final phone = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(4, 8, phone ? 8 : 12, 8),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.app, role: DunesColorRole.surface),
        border: Border(
          bottom: BorderSide(
            color: _c(
              context,
              ProposalPalette.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: _back,
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: _c(context, ProposalPalette.purpleDeep),
            ),
          ),
          const Spacer(),
          _progressToggle(),
          if (_row.id > 0) ...[
            const SizedBox(width: 6),
            DecoratedBox(
              decoration: _topToolDecoration,
              child: _topToolSlot(label: '业务审批', onPressed: _scrollToBiz),
            ),
          ],
          const SizedBox(width: 6),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _topToolCluster(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressToggle() {
    final color = _c(
      context,
      _progressOpen ? ProposalPalette.purpleDeep : ProposalPalette.text2,
    );
    return Tooltip(
      message: _progressOpen ? '收起进度' : '进度',
      child: InkWell(
        onTap: () => setState(() => _progressOpen = !_progressOpen),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: _topToolH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '进度',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: color,
                  ),
                ),
                Icon(
                  _progressOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topToolCluster() {
    final perm = _perm;
    final slots = <Widget>[];
    void add(String label, VoidCallback? onPressed, {bool loading = false}) {
      if (slots.isNotEmpty) slots.add(_topDivider());
      slots.add(
        _topToolSlot(label: label, onPressed: onPressed, loading: loading),
      );
    }

    if (perm.canEdit) add('保存', _busy ? null : _save);
    if (perm.canSubmit) {
      add(
        _row.status == kFundingStatusRejected ? '重新提交' : '提交',
        _busy ? null : _submit,
      );
    }
    if (perm.canWithdraw) add('撤回', _busy ? null : _withdraw);
    if (perm.canDelete) add('删除', _busy ? null : _delete);
    if (_row.id > 0) {
      add(
        '转发',
        _forwarding ? null : _forward,
        loading: _forwarding,
      );
    }
    if (slots.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: _topToolDecoration,
      child: Row(mainAxisSize: MainAxisSize.min, children: slots),
    );
  }

  Widget _topDivider() {
    return Container(
      width: 0.8,
      height: 14,
      color: _c(
        context,
        ProposalPalette.borderStrong,
        role: DunesColorRole.surface,
      ),
    );
  }

  Widget _topToolSlot({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    final enabled = onPressed != null && !loading;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          height: _topToolH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: _c(context, ProposalPalette.purpleDeep),
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1,
                        color: _c(
                          context,
                          enabled
                              ? ProposalPalette.purpleDeep
                              : ProposalPalette.text4,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  String get _pillTone => switch (_row.status) {
    kFundingStatusApproved => 'done',
    kFundingStatusReviewing || kFundingStatusRejected => 'reviewing',
    _ => 'draft',
  };

  Widget _titleBlock(BuildContext context) {
    final phone = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    final party = '${_form['counterpartyName'] ?? ''}'.trim();
    final title = _row.title.isEmpty ? '资金提案' : _row.title;
    final titleStyle = TextStyle(
      color: _c(context, const Color(0xFF2A2638)),
      fontSize: phone ? 16 : 18,
      fontWeight: FontWeight.w700,
    );
    final meta = [
      if (_row.code.isNotEmpty) _row.code,
      if (_row.createdByName.isNotEmpty) '申请人 ${_row.createdByName}',
      if (_row.createdAt != null) _fmtTime(_row.createdAt),
      if (_dirty && _editable) '未保存',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: phone ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              if (party.isNotEmpty)
                Flexible(
                  child: Text(
                    ' · $party',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
            ],
          ),
          SizedBox(height: phone ? 4 : 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ProposalStatusPill(
                status: _pillTone,
                label: fundingStatusLabel(_row.status),
                dot: false,
              ),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  style: TextStyle(
                    color: _c(context, const Color(0xFF8A8499)),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 各板块 ----

  Widget _businessSection(BuildContext context) {
    return _Section(
      index: '1',
      title: '主体与业务',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldGrid(
            children: [
              _Field(
                label: '我方主体',
                required: true,
                child: _entitySelect(
                  context,
                  catalog: widget.ourEntities,
                  code: _text('ourParty'),
                  name: _text('ourPartyName'),
                  hint: '选择我方主体',
                  onPick: (code, name) {
                    _form['ourParty'] = code;
                    _form['ourPartyName'] = name;
                    _changed();
                  },
                ),
              ),
              _Field(
                label: '对方主体（合作油企）',
                required: true,
                child: _entitySelect(
                  context,
                  catalog: widget.counterparties,
                  code: _text('counterparty'),
                  name: _text('counterpartyName'),
                  hint: '选择对方主体',
                  onPick: (code, name) {
                    _form['counterparty'] = code;
                    _form['counterpartyName'] = name;
                    _changed();
                  },
                ),
              ),
              _Field(
                label: '提案名称',
                hint: '不填按对方主体自动生成',
                child: _textInput(context, 'proposalName', hint: _row.title),
              ),
              _Field(
                label: '制券面值（元）',
                required: true,
                child: _textInput(context, 'faceAmount', number: true),
              ),
              _Field(
                label: '采购折扣率（%）',
                required: true,
                child: _textInput(
                  context,
                  'purchaseDiscount',
                  number: true,
                  hint: '如 97',
                ),
              ),
              _Field(
                label: '销售折扣率（%）',
                required: true,
                child: _textInput(
                  context,
                  'salesDiscount',
                  number: true,
                  hint: '如 98.8',
                ),
              ),
              _Field(
                label: '预付打款日',
                required: true,
                child: _dateInput(
                  context,
                  _text('prepayDate'),
                  (v) => _set('prepayDate', v),
                ),
              ),
              _Field(
                label: '客户回款日',
                required: true,
                child: _dateInput(
                  context,
                  _text('collectDate'),
                  (v) => _set('collectDate', v),
                ),
              ),
              _Field(
                label: '预付货款 · 业务毛利',
                computed: true,
                child: _computed(
                  context,
                  '${_est.text('prepayAmount')} · ${_est.text('grossProfit')}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Field(
            label: '申请说明',
            child: _textInput(
              context,
              'applyNote',
              hint: '为什么要这笔钱、时间窗口',
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financingSection(BuildContext context) {
    final funders = _funders;
    return _Section(
      index: '2',
      title: '融资',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldGrid(
            children: [
              _Field(
                label: '总融资需求（元）',
                required: true,
                child: _textInput(context, 'financingAmount', number: true),
              ),
              _Field(
                label: '还本付息方式',
                required: true,
                child: _optionSelect(
                  context,
                  'repayMethod',
                  _opts.repayMethods,
                ),
              ),
              _Field(
                label: '回款账户',
                required: true,
                child: _optionSelect(
                  context,
                  'collectionAccount',
                  _opts.collectionAccounts,
                ),
              ),
              _Field(
                label: '登记等杂费（元）',
                child: _textInput(
                  context,
                  'otherFee',
                  number: true,
                  hint: '没有可不填',
                ),
              ),
              _Field(
                label: '金额大写',
                computed: true,
                child: _computed(context, _est.text('amountUpper')),
              ),
              _Field(
                label: '自有资金投入',
                computed: true,
                child: _computed(context, _est.text('ownFunds')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '资金方',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _c(context, ProposalPalette.text),
            ),
          ),
          const SizedBox(height: 8),
          if (funders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '还没有资金方',
                style: TextStyle(
                  fontSize: 13,
                  color: _c(context, ProposalPalette.text2),
                ),
              ),
            ),
          for (var i = 0; i < funders.length; i++)
            _funderCard(context, i, funders[i]),
          if (_editable)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addFunder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加资金方'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _c(context, ProposalPalette.purpleDeep),
                  side: BorderSide(
                    color: _c(
                      context,
                      ProposalPalette.purpleLine,
                      role: DunesColorRole.border,
                    ),
                  ),
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '合计 ${_est.text('funderTotal', fallback: '0.00')}',
            style: TextStyle(
              fontSize: 12,
              color: _c(context, ProposalPalette.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _funderCard(
    BuildContext context,
    int index,
    Map<String, dynamic> row,
  ) {
    final rowId = '${row['rowId'] ?? ''}';
    String v(String key) => '${row[key] ?? ''}'.trim();
    final result = _est.funder(rowId);
    final summary = result == null
        ? ''
        : [
            if (result.interest.text.isNotEmpty) '利息 ${result.interest.text}',
            if (result.serviceFee.text.isNotEmpty)
              '服务费 ${result.serviceFee.text}',
            if (result.interestDays > 0) '计息 ${result.interestDays} 天',
            if (result.maturityDate.isNotEmpty) '到期 ${result.maturityDate}',
          ].join(' · ');
    Widget input(String key, {String? hint}) {
      if (!_editable) return _readText(context, _grouped(v(key)));
      return TextField(
        controller: _ctl('f:$rowId:$key', v(key)),
        onTapOutside: (_) => _dismissKeyboard(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: proposalInputDecoration(
          context: context,
          hint: hint,
          forceUnderline: true,
        ),
        onChanged: (text) => _setFunder(rowId, key, text.trim()),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.app, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _c(
            context,
            ProposalPalette.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '资金方 ${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _c(context, ProposalPalette.purpleDeep),
                ),
              ),
              const Spacer(),
              if (_editable)
                IconButton(
                  tooltip: '删除这个资金方',
                  onPressed: () => _removeFunder(rowId),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: _c(context, ProposalPalette.text2),
                  ),
                ),
            ],
          ),
          _FieldGrid(
            minColumnWidth: 180,
            children: [
              _Field(
                label: '类型',
                required: true,
                child: _editable
                    ? ProposalSelectField<String>(
                        value: v('type').isEmpty ? null : v('type'),
                        options: [
                          for (final o in _opts.funderTypes)
                            ProposalSelectOption(
                              value: o.value,
                              label: o.label,
                            ),
                        ],
                        onSelected: (value) =>
                            _setFunder(rowId, 'type', value ?? ''),
                      )
                    : _readText(
                        context,
                        _opts.labelOf(_opts.funderTypes, v('type')),
                      ),
              ),
              _Field(
                label: '机构',
                required: true,
                child: _entitySelect(
                  context,
                  catalog: widget.counterparties,
                  code: v('party'),
                  name: v('partyName'),
                  hint: '选择资金方机构',
                  onPick: (code, name) {
                    for (final r in _funders) {
                      if ('${r['rowId']}' == rowId) {
                        r['party'] = code;
                        r['partyName'] = name;
                      }
                    }
                    _changed();
                  },
                ),
              ),
              _Field(label: '额度（元）', required: true, child: input('amount')),
              _Field(
                label: '提款日',
                required: true,
                child: _dateInput(
                  context,
                  v('drawDate'),
                  (d) => _setFunder(rowId, 'drawDate', d),
                ),
              ),
              _Field(
                label: '期限（天）',
                required: true,
                child: input('termDays', hint: '如 60'),
              ),
              _Field(
                label: '年化利率（%）',
                required: true,
                child: input('annualRate', hint: '如 7.5'),
              ),
              _Field(
                label: '服务费率（%）',
                child: input('serviceFeeRate', hint: '没有填 0'),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text2),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _materialsSection(BuildContext context) {
    final canUpload = _perm.canEditMaterials;
    return _Section(
      index: '3',
      title: '材料',
      trailing: _uploading
          ? Text(
              '上传中…',
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text2),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in _opts.materials)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _c(
                      context,
                      ProposalPalette.borderSoft,
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: _c(context, ProposalPalette.text),
                      ),
                    ),
                  ),
                  ProposalStatusChip(
                    label: _filesOf(m.key).isNotEmpty
                        ? '已上传'
                        : (m.required ? '待补' : '选填'),
                    kind: _filesOf(m.key).isNotEmpty
                        ? ProposalChipKind.ok
                        : (m.required
                              ? ProposalChipKind.warn
                              : ProposalChipKind.normal),
                  ),
                  for (var i = 0; i < _filesOf(m.key).length; i++)
                    InputChip(
                      label: Text(
                        '${_filesOf(m.key)[i]['fileName'] ?? '文件'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => unawaited(_openFile(_filesOf(m.key)[i])),
                      onDeleted: canUpload
                          ? () => unawaited(_removeFile(m.key, i))
                          : null,
                    ),
                  if (canUpload)
                    TextButton.icon(
                      onPressed: _uploading
                          ? null
                          : () => unawaited(_pickFiles(m.key)),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('上传'),
                      style: TextButton.styleFrom(
                        foregroundColor: _c(
                          context,
                          ProposalPalette.purpleDeep,
                        ),
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '进入总经理审批前，必备材料须全部上传。审批中也可以补。',
            style: TextStyle(
              fontSize: 12,
              color: _c(context, ProposalPalette.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _approversSection(BuildContext context) {
    final approvers = _approvers;
    return _Section(
      index: '4',
      title: '审批人',
      child: _FieldGrid(
        minColumnWidth: 200,
        children: [
          for (final node in kFundingNodeOrder)
            _Field(
              label:
                  '${kFundingNodeOrder.indexOf(node) + 1} · ${_opts.nodeLabel(node)}',
              required: true,
              child: _personSelect(
                context,
                current: approvers[node] is Map
                    ? Map<String, dynamic>.from(approvers[node] as Map)
                    : const <String, dynamic>{},
                onPick: (person) {
                  final map = _approvers;
                  map[node] = person == null
                      ? <String, dynamic>{}
                      : {'userId': person.userId, 'name': person.name};
                  _form['approvers'] = map;
                  _changed();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _noteSection(BuildContext context) {
    return _Section(
      index: '5',
      title: '其他说明',
      child: _textInput(
        context,
        'otherNote',
        hint: '选填：担保、增信、特殊风险',
        maxLines: 3,
      ),
    );
  }

  Widget _historySection(BuildContext context) {
    final events = [..._row.events]..sort((a, b) => b.id.compareTo(a.id));
    return _Section(
      index: '6',
      title: '审批记录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_perm.canDecide) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _c(
                  context,
                  ProposalPalette.soft,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '待你以${_row.currentNodeLabel}身份审批',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _c(context, ProposalPalette.purpleDeep),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _decisionComment,
                    onTapOutside: (_) => _dismissKeyboard(),
                    maxLines: 3,
                    minLines: 2,
                    decoration: proposalInputDecoration(
                      context: context,
                      hint: '审批意见（同意可不填）',
                      forceUnderline: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ActionButton(
                        label: '有问题，驳回',
                        onPressed: _busy ? null : _reject,
                        tone: _ActionTone.danger,
                      ),
                      _ActionButton(
                        label: '同意',
                        onPressed: _busy ? null : _approve,
                        tone: _ActionTone.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final ev in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EventDot(action: ev.action),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            '第 ${ev.round} 轮',
                            if (ev.nodeLabel.isNotEmpty) ev.nodeLabel,
                            ev.actorName,
                            ev.actionLabel,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _c(context, ProposalPalette.text),
                          ),
                        ),
                        Text(
                          _fmtTime(ev.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: _c(context, ProposalPalette.text2),
                          ),
                        ),
                        if (ev.comment.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              ev.comment,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: _c(context, ProposalPalette.text),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- 输入控件 ----

  Widget _readText(BuildContext context, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        value.isEmpty ? '—' : value,
        style: TextStyle(
          fontSize: 14,
          color: _c(
            context,
            value.isEmpty ? ProposalPalette.text3 : ProposalPalette.text,
          ),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _computed(BuildContext context, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.soft, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _c(context, ProposalPalette.text),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _textInput(
    BuildContext context,
    String key, {
    String? hint,
    bool number = false,
    int maxLines = 1,
  }) {
    final value = _text(key);
    if (!_editable) return _readText(context, number ? _grouped(value) : value);
    return TextField(
      controller: _ctl('k:$key', value),
      onTapOutside: (_) => _dismissKeyboard(),
      maxLines: maxLines,
      minLines: 1,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: proposalInputDecoration(
        context: context,
        hint: hint,
        forceUnderline: true,
      ),
      onChanged: (text) => _set(key, text.trim()),
    );
  }

  Widget _dateInput(
    BuildContext context,
    String value,
    ValueChanged<String> onPick,
  ) {
    if (!_editable) return _readText(context, value);
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final initial = DateTime.tryParse(value) ?? now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(now.year - 3),
          lastDate: DateTime(now.year + 5),
        );
        if (picked == null) return;
        String two(int v) => v.toString().padLeft(2, '0');
        onPick('${picked.year}-${two(picked.month)}-${two(picked.day)}');
      },
      child: InputDecorator(
        decoration: proposalInputDecoration(
          context: context,
          hint: '选择日期',
          forceUnderline: true,
        ),
        isEmpty: value.isEmpty,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: _c(context, ProposalPalette.text),
          ),
        ),
      ),
    );
  }

  Widget _optionSelect(
    BuildContext context,
    String key,
    List<FundingOption> list,
  ) {
    final value = _text(key);
    if (!_editable) return _readText(context, _opts.labelOf(list, value));
    return ProposalSelectField<String>(
      value: value.isEmpty ? null : value,
      options: [
        for (final o in list)
          ProposalSelectOption(value: o.value, label: o.label),
      ],
      onSelected: (v) => _set(key, v ?? ''),
    );
  }

  /// 资管主体字典：存 code（我方存简称、对方存全称，与销售 / 采购提案一致），展示 label。
  Widget _entitySelect(
    BuildContext context, {
    required List<CatalogRef> catalog,
    required String code,
    required String name,
    required String hint,
    required void Function(String code, String name) onPick,
  }) {
    if (!_editable) return _readText(context, name.isNotEmpty ? name : code);
    String stored(CatalogRef ref) =>
        ref.code.trim().isNotEmpty ? ref.code.trim() : ref.name.trim();
    final options = <ProposalSelectOption<String>>[];
    final seen = <String>{};
    for (final ref in catalog) {
      final value = stored(ref);
      if (value.isEmpty || !seen.add(value)) continue;
      options.add(
        ProposalSelectOption(
          value: value,
          label: ref.label,
          meta: ref.label == value ? null : value,
        ),
      );
    }
    if (code.isNotEmpty && !seen.contains(code)) {
      options.insert(
        0,
        ProposalSelectOption(value: code, label: name.isNotEmpty ? name : code),
      );
    }
    return ProposalSelectField<String>(
      value: code.isEmpty ? null : code,
      options: options,
      hint: hint,
      searchable: true,
      emptyText: catalog.isEmpty ? '主体字典还没加载出来' : null,
      onSelected: (value) {
        if (value == null || value.isEmpty) {
          onPick('', '');
          return;
        }
        final match = options.firstWhere(
          (o) => o.value == value,
          orElse: () => ProposalSelectOption(value: value, label: value),
        );
        onPick(value, match.label);
      },
    );
  }

  Widget _personSelect(
    BuildContext context, {
    required Map<String, dynamic> current,
    required ValueChanged<ProposalPerson?> onPick,
  }) {
    final userId = current['userId'] is num
        ? (current['userId'] as num).toInt()
        : int.tryParse('${current['userId'] ?? ''}') ?? 0;
    final name = '${current['name'] ?? ''}'.trim();
    if (!_editable) return _readText(context, name);
    final options = <ProposalSelectOption<int>>[];
    var hasCurrent = false;
    for (final p in widget.people) {
      if (p.userId == userId) hasCurrent = true;
      final meta = [
        p.departmentName,
        p.positionName,
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      options.add(
        ProposalSelectOption(
          value: p.userId,
          label: p.name,
          meta: meta.isEmpty ? null : meta,
        ),
      );
    }
    if (userId > 0 && !hasCurrent) {
      options.insert(
        0,
        ProposalSelectOption(
          value: userId,
          label: name.isEmpty ? '#$userId' : name,
        ),
      );
    }
    return ProposalSelectField<int>(
      value: userId > 0 ? userId : null,
      options: options,
      hint: '输入姓名搜索',
      searchable: true,
      requireKeyword: true,
      onSelected: (value) {
        if (value == null) {
          onPick(null);
          return;
        }
        ProposalPerson? person;
        for (final p in widget.people) {
          if (p.userId == value) person = p;
        }
        onPick(
          person ?? ProposalPerson(userId: value, name: name, positionName: ''),
        );
      },
    );
  }
}

// ======================================================================
// 小部件
// ======================================================================

class _Section extends StatelessWidget {
  const _Section({
    required this.index,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String index;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.card, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _c(
                    context,
                    ProposalPalette.purpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  index,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _c(context, ProposalPalette.purpleDeep),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _c(context, ProposalPalette.text),
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// 字段自动排成 1～3 列。
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.children, this.minColumnWidth = 220});

  final List<Widget> children;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 24.0;
        final width = constraints.maxWidth;
        final cols = math.max(
          1,
          math.min(3, ((width + gap) / (minColumnWidth + gap)).floor()),
        );
        final itemWidth = (width - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.required = false,
    this.computed = false,
    this.hint,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool computed;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (required)
              Text(
                '*',
                style: TextStyle(
                  fontSize: 12,
                  color: _c(context, ProposalPalette.coral),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _c(context, ProposalPalette.text2),
              ),
            ),
            if (computed)
              Text(
                '后端计算',
                style: TextStyle(
                  fontSize: 11,
                  color: _c(context, ProposalPalette.green),
                ),
              ),
            if (hint != null)
              Text(
                hint!,
                style: TextStyle(
                  fontSize: 11,
                  color: _c(context, ProposalPalette.text3),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

enum _ActionTone { normal, primary, danger }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.tone = _ActionTone.normal,
  });

  final String label;
  final VoidCallback? onPressed;
  final _ActionTone tone;

  @override
  Widget build(BuildContext context) {
    if (tone == _ActionTone.primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _c(context, ProposalPalette.purple),
          minimumSize: const Size(96, 44),
        ),
        child: Text(label),
      );
    }
    final color = tone == _ActionTone.danger
        ? ProposalPalette.coral
        : ProposalPalette.purpleDeep;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _c(context, color),
        side: BorderSide(
          color: _c(
            context,
            ProposalPalette.borderStrong,
            role: DunesColorRole.border,
          ),
        ),
        minimumSize: const Size(88, 44),
      ),
      child: Text(label),
    );
  }
}

/// 页头的四个节点：已同意 / 当前 / 未到 / 驳回。
class _ApprovalPath extends StatelessWidget {
  const _ApprovalPath({required this.row, required this.options});

  final FundingProposal row;
  final FundingOptions options;

  @override
  Widget build(BuildContext context) {
    final approvers = row.form['approvers'] is Map
        ? Map<String, dynamic>.from(row.form['approvers'] as Map)
        : const <String, dynamic>{};
    final approvedNodes = <String>{
      for (final ev in row.events)
        if (ev.round == row.round && ev.action == 'approve') ev.node,
    };
    String? rejectedNode;
    if (row.status == kFundingStatusRejected) {
      for (final ev in row.events) {
        if (ev.round == row.round && ev.action == 'reject')
          rejectedNode = ev.node;
      }
    }
    final items = <Widget>[];
    for (var i = 0; i < kFundingNodeOrder.length; i++) {
      final node = kFundingNodeOrder[i];
      final ap = approvers[node] is Map
          ? Map<String, dynamic>.from(approvers[node] as Map)
          : const <String, dynamic>{};
      final name = '${ap['name'] ?? ''}'.trim();
      final done =
          row.status == kFundingStatusApproved || approvedNodes.contains(node);
      final current =
          row.status == kFundingStatusReviewing && row.currentNode == node;
      final rejected = rejectedNode == node;
      final (bg, fg) = rejected
          ? (ProposalPalette.coralSoft, ProposalPalette.coral)
          : current
          ? (ProposalPalette.purple, Colors.white)
          : done
          ? (ProposalPalette.greenSoft, ProposalPalette.green)
          : (ProposalPalette.borderSoft, ProposalPalette.text2);
      if (i > 0) {
        items.add(
          Icon(
            Icons.chevron_right,
            size: 18,
            color: _c(context, ProposalPalette.text3),
          ),
        );
      }
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: current ? bg : _c(context, bg, role: DunesColorRole.surface),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${options.nodeLabel(node)}${name.isEmpty ? '' : ' $name'}${done ? ' ✓' : ''}${rejected ? ' 驳回' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: current ? fg : _c(context, fg),
            ),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }
}

class _EventDot extends StatelessWidget {
  const _EventDot({required this.action});

  final String action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (action) {
      'approve' => (
        ProposalPalette.greenSoft,
        ProposalPalette.green,
        Icons.check,
      ),
      'reject' => (
        ProposalPalette.coralSoft,
        ProposalPalette.coral,
        Icons.close,
      ),
      'withdraw' => (
        ProposalPalette.amberSoft,
        ProposalPalette.amber,
        Icons.undo,
      ),
      _ => (ProposalPalette.purpleSoft, ProposalPalette.purpleDeep, Icons.send),
    };
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: _c(context, bg, role: DunesColorRole.surface),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: _c(context, fg)),
    );
  }
}

// ======================================================================
// 右侧测算栏：只展示后端结果
// ======================================================================

class _EstimatePanel extends StatelessWidget {
  const _EstimatePanel({
    required this.estimate,
    required this.loading,
    required this.live,
  });

  final FundingEstimate estimate;
  final bool loading;

  /// 草稿实时算；审批中 / 已通过展示提交时的快照。
  final bool live;

  @override
  Widget build(BuildContext context) {
    final est = estimate;
    final text = _c(context, ProposalPalette.text);
    final text2 = _c(context, ProposalPalette.text2);
    final updated = est.calculatedAt == null
        ? ''
        : '${est.calculatedAt!.hour.toString().padLeft(2, '0')}:${est.calculatedAt!.minute.toString().padLeft(2, '0')}';
    final status = loading
        ? '计算中…'
        : live
        ? (updated.isEmpty ? '后端测算' : '后端 · $updated 更新')
        : '提交时快照';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '测算结果',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _c(
                        context,
                        loading ? ProposalPalette.amber : _kNetColor,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(status, style: TextStyle(fontSize: 12, color: text2)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '融资净收益（元）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: text2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                est.text('netProfit'),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '毛利 ${est.text('grossProfit')} − 融资成本 ${est.text('financingCost')}',
                style: TextStyle(
                  fontSize: 12,
                  color: text2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              if (est.composition.isNotEmpty) ...[
                _CompositionBar(slices: est.composition),
                const SizedBox(height: 10),
                for (final s in est.composition)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        _Swatch(color: _sliceColor(s.key)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.label,
                            style: TextStyle(fontSize: 13, color: text),
                          ),
                        ),
                        Text(
                          s.amount,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            s.percent,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              color: text2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else
                Text(
                  '填完业务和资金方后显示毛利构成',
                  style: TextStyle(fontSize: 12, color: text2),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      label: '综合年化成本',
                      value: est.text('annualCostRate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      label: '融资到期日',
                      value: est.text('maturityDate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Line(label: '预付货款', value: est.text('prepayAmount')),
              _Line(label: '业务总收入', value: est.text('revenue')),
              _Line(label: '毛利率', value: est.text('grossMargin')),
              _Line(
                label: '利息 / 服务费',
                value:
                    '${est.text('interestTotal')} / ${est.text('serviceFeeTotal')}',
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: _c(
                  context,
                  ProposalPalette.borderSoft,
                  role: DunesColorRole.border,
                ),
              ),
              const SizedBox(height: 14),
              _TimelineView(timeline: est.timeline),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(child: _ChecksView(estimate: est)),
      ],
    );
  }

  static Color _sliceColor(String key) => switch (key) {
    'netProfit' => _kNetColor,
    'interest' => _kInterestColor,
    _ => _kFeeColor,
  };
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.card, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(
            context,
            ProposalPalette.border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.height = 10});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: height,
      decoration: BoxDecoration(
        color: _c(context, color),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _CompositionBar extends StatelessWidget {
  const _CompositionBar({required this.slices});

  final List<FundingSlice> slices;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final s in slices)
        if (s.weight > 0) s,
    ];
    return Semantics(
      label: '毛利构成：${slices.map((s) => '${s.label} ${s.percent}').join('，')}',
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: visible[i].weight,
                child: Container(
                  decoration: BoxDecoration(
                    color: _c(
                      context,
                      _EstimatePanel._sliceColor(visible[i].key),
                    ),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(i == 0 ? 4 : 0),
                      right: Radius.circular(i == visible.length - 1 ? 4 : 0),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _c(context, ProposalPalette.soft, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _c(context, ProposalPalette.text2),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _c(context, ProposalPalette.text),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: _c(context, ProposalPalette.text2),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _c(context, ProposalPalette.text),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间安全垫：0 → 回款 → 融资到期 → 盈亏平衡，单位天，从预付打款日起算。
class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.timeline});

  final FundingTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final turnover = timeline.turnoverDays;
    final maturity = timeline.maturityDays;
    final breakEven = timeline.breakEvenDays;
    final text = _c(context, ProposalPalette.text);
    final text2 = _c(context, ProposalPalette.text2);
    final title = Row(
      children: [
        Text(
          '时间安全垫',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: text,
          ),
        ),
        const Spacer(),
        Text('单位：天', style: TextStyle(fontSize: 12, color: text2)),
      ],
    );
    if (turnover == null || maturity == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 8),
          Text('填完日期和资金方期限后显示', style: TextStyle(fontSize: 12, color: text2)),
        ],
      );
    }
    final maxDay =
        math.max(1, [turnover, maturity, breakEven ?? 0].reduce(math.max)) *
        1.12;
    double at(int day) => (day / maxDay).clamp(0.0, 1.0);
    final buffer = timeline.bufferDays ?? (maturity - turnover);
    final room = breakEven == null ? null : breakEven - maturity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 10),
        Semantics(
          label:
              '第 $turnover 天回款，第 $maturity 天融资到期${breakEven == null ? '' : '，第 $breakEven 天盈亏平衡'}',
          child: SizedBox(
            height: 40,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                Widget tickLabel(int day, double x) => Positioned(
                  left: (x * w - 12).clamp(0.0, math.max(0.0, w - 24)),
                  top: 26,
                  width: 24,
                  child: Text(
                    '$day',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 10,
                      height: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _c(
                            context,
                            ProposalPalette.borderSoft,
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 10,
                      height: 10,
                      width: at(turnover) * w,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _c(context, _kInterestColor),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    if (maturity > turnover)
                      Positioned(
                        left: at(turnover) * w + 2,
                        top: 10,
                        height: 10,
                        width: math.max(
                          0.0,
                          (at(maturity) - at(turnover)) * w - 2,
                        ),
                        child: ColoredBox(color: _c(context, _kBufferColor)),
                      ),
                    Positioned(
                      left: at(maturity) * w - 1,
                      top: 4,
                      height: 22,
                      width: 2,
                      child: ColoredBox(
                        color: _c(context, ProposalPalette.purpleDeep),
                      ),
                    ),
                    if (breakEven != null)
                      Positioned(
                        left: at(breakEven) * w - 1,
                        top: 4,
                        height: 22,
                        width: 2,
                        child: ColoredBox(color: text),
                      ),
                    tickLabel(turnover, at(turnover)),
                    tickLabel(maturity, at(maturity)),
                    if (breakEven != null) tickLabel(breakEven, at(breakEven)),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        _legend(context, _kInterestColor, '资金占用 $turnover 天（打款 → 回款）'),
        _legend(
          context,
          _kBufferColor,
          '缓冲 $buffer 天，第 $maturity 天融资到期（要求 ≥ ${timeline.requiredBuffer}）',
        ),
        if (breakEven != null)
          _legend(
            context,
            ProposalPalette.text,
            room != null && room >= 0
                ? '第 $breakEven 天盈亏平衡，比到期多 $room 天'
                : '第 $breakEven 天盈亏平衡，早于融资到期',
            thin: true,
          ),
      ],
    );
  }

  Widget _legend(
    BuildContext context,
    Color color,
    String label, {
    bool thin = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          thin ? _Swatch(color: color, height: 2) : _Swatch(color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecksView extends StatelessWidget {
  const _ChecksView({required this.estimate});

  final FundingEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final checks = estimate.checks;
    final passed = checks.where((c) => c.pass).length;
    final failed = checks.length - passed;
    final text = _c(context, ProposalPalette.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '校验',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            const Spacer(),
            Text(
              estimate.blocking > 0
                  ? '$passed 通过 · ${estimate.blocking} 项挡提交'
                  : '$passed 通过 · $failed 提醒',
              style: TextStyle(
                fontSize: 12,
                color: _c(context, ProposalPalette.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (estimate.missing.isNotEmpty)
          _checkRow(
            context,
            _CheckState.block,
            '待填写：${estimate.missing.join('、')}',
          ),
        for (final c in checks)
          _checkRow(
            context,
            c.pass
                ? _CheckState.ok
                : (c.blocking ? _CheckState.block : _CheckState.warn),
            c.message,
          ),
      ],
    );
  }

  Widget _checkRow(BuildContext context, _CheckState state, String message) {
    final (bg, fg, icon) = switch (state) {
      _CheckState.ok => (
        ProposalPalette.greenSoft,
        ProposalPalette.green,
        Icons.check,
      ),
      _CheckState.warn => (
        ProposalPalette.amberSoft,
        ProposalPalette.amber,
        Icons.priority_high,
      ),
      _CheckState.block => (
        ProposalPalette.coralSoft,
        ProposalPalette.coral,
        Icons.close,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _c(context, bg, role: DunesColorRole.surface),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 12, color: _c(context, fg)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _c(context, ProposalPalette.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CheckState { ok, warn, block }
