import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/approval_detail_dialog.dart';
import '../xflow/xflow_approval_catalog.dart';
import '../xflow/native_xflow_form_page.dart';
import '../xflow/xflow_detail_logic.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'proposal_intake_models.dart';

/// A shared PC/mobile entry. The server independently enforces the policy.
class ProposalBusinessApprovals extends StatefulWidget {
  const ProposalBusinessApprovals({
    super.key,
    required this.session,
    required this.proposal,
    this.service,
    this.allowLaunch = true,
    this.people = const [],
  });
  final AuthSession session;
  final ProposalIntakeRow proposal;
  final XflowService? service;
  final bool allowLaunch;

  /// 选「可发起人」用的人员名单。
  final List<ProposalPerson> people;

  @override
  State<ProposalBusinessApprovals> createState() =>
      _ProposalBusinessApprovalsState();
}

/// 业务审批归入提案的口径，与后端 proposal_business_cost_collection.go 一致。
const Map<String, String> kProposalApprovalBucketLabels = {
  'contract-seal': '无金额',
  'finance-business-procurement': '项目成本',
  'finance-core-business-cost': '业务成本',
  'finance-equipment-rental': '项目成本',
  'finance-deposit': '周转资金',
  'finance-prepayment': '周转资金',
  'finance-contract-payment': '项目成本',
  'finance-promotion-payment': '项目成本',
  'finance-voucher-distribution': '项目成本',
  'finance-customer-complaint': '业务成本',
  'finance-voucher-refund': '冲减收入',
  'finance-customer-compensation': '业务成本',
  'finance-invoice-request': '税务成本',
  'finance-receipt-request': '收入',
  'finance-entertainment-expense': '经营成本',
  'finance-gift-request': '经营成本',
  'finance-travel-expense': '经营成本',
};

String proposalApprovalBucketLabel(String templateKey) =>
    kProposalApprovalBucketLabels[templateKey.trim()] ?? '项目成本';

const kProposalInvoiceTemplateKey = 'finance-invoice-request';

enum _BizTab { approvals, invoices, costs, funds }

const _kAccent = Color(0xFF5B3FD6);
const _kSoft = Color(0xFFF7F5FE);
const _kLine = Color(0xFFEEECF6);

class _ProposalBusinessApprovalsState extends State<ProposalBusinessApprovals> {
  late final _service = widget.service ?? XflowService(session: widget.session);
  Map<String, dynamic> _data = const {};
  Map<String, dynamic> _costs = const {};
  bool _busy = false, _launching = false;
  String? _error, _costError;
  int _page = 1, _request = 0;
  String _templateKey = '';
  List<XflowTemplateCard> _templates = const [];
  List<XflowApprovalGroup>? _catalog;
  _BizTab _tab = _BizTab.approvals;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadTemplates());
  }

  Future<void> _loadTemplates() async {
    final results = await Future.wait(['biz', 'adm'].map((category) async {
      try {
        return await _service.fetchTemplatesByCategory(category);
      } catch (_) {
        return <XflowTemplateCard>[];
      }
    }));
    List<XflowApprovalGroup>? catalog;
    try {
      catalog = await _service.fetchApprovalGroups();
    } catch (_) {
      catalog = null;
    }
    if (!mounted) return;
    final unique = <String, XflowTemplateCard>{};
    for (final template in results.expand((items) => items)) {
      if (template.templateKey != XflowService.salesTemplateKey) {
        unique[template.templateKey] = template;
      }
    }
    setState(() {
      _templates = unique.values.toList();
      _catalog = catalog;
    });
  }

  @override
  void didUpdateWidget(covariant ProposalBusinessApprovals oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.proposal.id != widget.proposal.id ||
        oldWidget.proposal.version != widget.proposal.version ||
        oldWidget.proposal.status != widget.proposal.status) {
      _page = 1;
      unawaited(_load());
    }
  }

  /// 只有已完成的销售、采购提案，且后端判定当前用户可引用（提案负责人、可发起人等）时，
  /// 才放开发起入口。提案内发起不等 11 月 1 日：生效日只用来拦截脱离提案的独立入口。
  bool get _canLaunch =>
      widget.allowLaunch &&
      _data['canLaunch'] == true &&
      widget.proposal.status == 'done' &&
      (widget.proposal.kind == 'sales' ||
          widget.proposal.kind == 'purchase' ||
          widget.proposal.kind.isEmpty);

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Independent reads: a cost-collection failure must not erase approval records.
    final costs = _service
        .fetchProposalCostCollection(widget.proposal.id)
        .then((value) {
          if (!mounted || request != _request) return;
          setState(() {
            _costs = value;
            _costError = null;
          });
        })
        .catchError((Object e) {
          if (!mounted || request != _request) return;
          setState(() => _costError = friendlyErrorText(e));
        });
    try {
      final data = await _service.fetchProposalRelatedApprovals(
        widget.proposal.id,
        page: _page,
        templateKey: _templateKey,
      );
      if (!mounted || request != _request) return;
      setState(() => _data = data);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _data = const {};
          _error = friendlyErrorText(e);
        });
      }
    }
    await costs;
    if (mounted && request == _request) setState(() => _busy = false);
  }

  /// 发起审批：不传模板时弹出分类选择；发票申请直接带模板。
  /// 两种方式都把当前提案作为关联提案带入，后端会再校验一次。
  Future<void> _launch({String? templateKey}) async {
    setState(() => _launching = true);
    try {
      final templates = (await _service.fetchTemplatesByCategory('biz'))
          .where(
            (t) => t.enabled && t.templateKey != XflowService.salesTemplateKey,
          )
          .toList();
      if (!mounted) return;
      XflowTemplateCard? selected;
      if (templateKey != null) {
        selected = templates
            .where((t) => t.templateKey == templateKey)
            .firstOrNull;
        if (selected == null) {
          setState(() => _error = '未找到可用的发票申请模板，请联系管理员启用');
          return;
        }
      } else {
        selected = await _pickTemplate(templates);
      }
      if (selected == null || !mounted) return;
      await showProposalBusinessForm(
        context: context,
        session: widget.session,
        templateKey: selected.templateKey,
        proposal: linkedProposalIntakePayload(
          id: widget.proposal.id,
          code: widget.proposal.code,
          title: widget.proposal.title,
          kind: widget.proposal.kind,
        ),
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<XflowTemplateCard?> _pickTemplate(List<XflowTemplateCard> templates) {
    final groups = xflowPopulatedApprovalGroups(
      templates,
      category: 'biz',
      catalog: _catalog,
    ).where((g) => g.templates.isNotEmpty && g.id != 'biz-initiative').toList();
    var index = groups.indexWhere((g) => g.id == 'biz-payment');
    if (index < 0) index = 0;
    return showDialog<XflowTemplateCard>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final group = groups.isEmpty ? null : groups[index];
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: MediaQuery.sizeOf(ctx).height * .86,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '发起审批',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        ctx,
                        const Color(0xFFF6F5FB),
                        role: DunesColorRole.surface,
                      ),
                      border: Border.all(
                        color: DunesColors.resolve(
                          ctx,
                          const Color(0xFFE6E3F2),
                          role: DunesColorRole.border,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '所属提案',
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolve(ctx, DunesColors.text3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            [
                              widget.proposal.code,
                              widget.proposal.title,
                            ].where((s) => s.trim().isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: DunesColors.resolve(ctx, DunesColors.text3),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '自动关联',
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolve(ctx, DunesColors.text3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (var i = 0; i < groups.length; i++)
                          _tabButton(
                            ctx,
                            label:
                                '${groups[i].title} ${groups[i].templates.length}',
                            selected: i == index,
                            onTap: () => setLocal(() => index = i),
                          ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: DunesColors.resolve(
                      ctx,
                      _kLine,
                      role: DunesColorRole.border,
                    ),
                  ),
                  Flexible(
                    child: group == null
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('暂无可用业务审批模板'),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            children: [
                              for (var i = 0; i < group.templates.length; i++)
                                ListTile(
                                  onTap: () =>
                                      Navigator.pop(ctx, group.templates[i]),
                                  leading: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: DunesColors.resolve(
                                        ctx,
                                        const Color(0xFFEEEBFB),
                                        role: DunesColorRole.surface,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      xflowApprovalIcon(
                                        group.templates[i].icon,
                                      ),
                                      size: 18,
                                      color: DunesColors.resolve(ctx, _kAccent),
                                    ),
                                  ),
                                  title: Text(
                                    group.templates[i].title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${(i + 1).toString().padLeft(2, '0')} · '
                                    '${group.templates[i].subtitle}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _bucketChip(
                                        ctx,
                                        proposalApprovalBucketLabel(
                                          group.templates[i].templateKey,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '审批通过后归入提案：',
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolve(ctx, DunesColors.text3),
                          ),
                        ),
                        for (final label in const ['收入', '项目成本', '周转资金', '无金额'])
                          _bucketChip(ctx, label),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final businessId = int.tryParse('${row['businessId']}');
    if (businessId == null) return;
    await showApprovalDetailOverlay(
      context: context,
      session: widget.session,
      share: ApprovalChatShare(
        businessType: '${row['businessType']}',
        businessId: businessId,
        title: '${row['title'] ?? ''}',
        templateKey: '${row['templateKey'] ?? ''}',
        code: '${row['code'] ?? ''}',
        status: '${row['status'] ?? ''}',
      ),
      onEditSubmission: (item) => unawaited(
        showProposalBusinessForm(
          context: context,
          session: widget.session,
          templateKey: item.templateKey ?? '',
          businessId: item.id,
          businessType: item.businessType,
        ).then((_) {
          if (mounted) unawaited(_load());
        }),
      ),
    );
    if (mounted) await _load();
  }

  List<Map<String, dynamic>> _maps(Object? raw) => (raw is List ? raw : const [])
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList();

  Map<String, dynamic>? _bucket(String code) {
    for (final b in _maps(_costs['buckets'])) {
      if (b['bucket'] == code) return b;
    }
    return null;
  }

  int _count(Map<String, dynamic>? bucket) =>
      (bucket?['count'] as num?)?.toInt() ?? 0;

  static const _costBuckets = [
    'projectCost',
    'businessCost',
    'taxCost',
    'operatingCost',
  ];

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data['items']);
    final total = (_data['total'] as num?)?.toInt() ?? 0;
    final stats = _data['stats'] as Map? ?? const {};
    final invoices = _maps(_costs['invoices']);
    final costCount = _costBuckets.fold<int>(
      0,
      (sum, code) => sum + _count(_bucket(code)),
    );
    final funds = _bucket('workingCapital');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFD9D3F7),
            role: DunesColorRole.border,
          ),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          _launcherBar(),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    _kLine,
                    role: DunesColorRole.border,
                  ),
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final (tab, label) in [
                    (_BizTab.approvals, '审批 $total'),
                    (_BizTab.invoices, '开票 ${invoices.length}'),
                    (_BizTab.costs, '成本归集 $costCount'),
                    (_BizTab.funds, '资金占用 ${_count(funds)}'),
                  ])
                    _tabButton(
                      context,
                      label: label,
                      selected: _tab == tab,
                      onTap: () => setState(() => _tab = tab),
                    ),
                ],
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: switch (_tab) {
              _BizTab.approvals => _approvalsTab(items, total, stats),
              _BizTab.invoices => _rowsTab(
                invoices,
                empty: '暂无发票申请',
                error: _costError,
              ),
              _BizTab.costs => _costsTab(),
              _BizTab.funds => _fundsTab(funds),
            },
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final done = widget.proposal.status == 'done';
    final subtitle = _canLaunch
        ? '业务类审批须从本提案发起，开票与经营类成本自动归入本提案'
        : !done
        ? '提案完成后才能发起业务审批'
        : _data['canLaunch'] == false
        ? '你暂无权限在此提案下发起业务审批'
        : '本提案关联的业务审批';
    return Container(
      color: DunesColors.resolve(context, _kSoft, role: DunesColorRole.surface),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '业务审批',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: '刷新',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              if (_canLaunch)
                TextButton(
                  key: const ValueKey('proposal-link-existing-approval'),
                  onPressed: _launching || _busy ? null : _linkExisting,
                  child: const Text('关联已有审批'),
                ),
              if (_canLaunch)
                FilledButton.icon(
                  key: const ValueKey('proposal-launch-business-approval'),
                  onPressed: _launching || _busy ? null : () => _launch(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_launching ? '正在打开…' : '发起审批'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _approvalsTab(
    List<Map<String, dynamic>> items,
    int total,
    Map stats,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _templateFilter(),
            Text(
              '仅展示你有权查看的审批 · 审批中 ${stats['PENDING'] ?? 0} · 已通过 ${stats['APPROVED'] ?? 0}',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_error != null) _notice(_error!, error: true),
        if (!_busy && _error == null && items.isEmpty)
          _empty(
            _canLaunch ? '还没有业务审批，点「发起审批」从本提案发起' : '暂无关联业务审批',
          ),
        for (final row in items) _row(row, history: true),
        if (total > 20 || _page > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('共 $total 条 · 第 $_page 页', style: const TextStyle(fontSize: 12)),
              IconButton(
                tooltip: '上一页',
                onPressed: _busy || _page <= 1
                    ? null
                    : () {
                        _page--;
                        unawaited(_load());
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: _busy || _page * 20 >= total
                    ? null
                    : () {
                        _page++;
                        unawaited(_load());
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  Widget _rowsTab(
    List<Map<String, dynamic>> rows, {
    required String empty,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) _notice(error, error: true),
        if (rows.isEmpty && error == null) _empty(empty),
        for (final row in rows) _row(row),
      ],
    );
  }

  Widget _costsTab() {
    final groups = [
      for (final code in _costBuckets)
        if (_bucket(code) case final bucket?) bucket,
    ];
    final any = groups.any((g) => _count(g) > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_costError != null) _notice(_costError!, error: true),
        if (!any && _costError == null)
          _empty('付款、费用、发票等审批通过后，会按来源单据自动归集到这里'),
        for (final group in groups)
          if (_count(group) > 0) _bucketSection(group),
      ],
    );
  }

  Widget _fundsTab(Map<String, dynamic>? funds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_costError != null) _notice(_costError!, error: true),
        if (_count(funds) == 0 && _costError == null)
          _empty('暂无保证金、预付款等资金占用'),
        if (_count(funds) > 0) _bucketSection(funds!),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '资金占用不计入成本，计入周转资金；预付款结算后转入成本归集。',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bucketSection(Map<String, dynamic> group) {
    final pending = (group['pending'] as num?)?.toDouble() ?? 0;
    final tax = group['bucket'] == 'taxCost';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${group['label']}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '已归集 ${_money(group['total'])}'
                '${pending > 0 ? ' · 审批中 ${_money(pending)}' : ''}'
                '${tax ? ' · 按发票税额计' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
            ],
          ),
          for (final row in _maps(group['items'])) _row(row, taxView: tax),
        ],
      ),
    );
  }

  /// 一行审批：类型、事项、金额、状态、更新时间；点击看审批详情，来源提案写在副标题。
  Widget _row(
    Map<String, dynamic> row, {
    bool history = false,
    bool taxView = false,
  }) {
    final status = '${row['status'] ?? ''}'.toUpperCase();
    final amountText = taxView && row['taxAmount'] != null
        ? '税额 ${_money(row['taxAmount'])}'
        : _money(row['amount']);
    final source = row['sourceProposal'] is Map
        ? '${(row['sourceProposal'] as Map)['code'] ?? ''}'
        : widget.proposal.code;
    final meta = [
      '${row['code'] ?? ''}',
      if ('${row['initiatorName'] ?? ''}'.isNotEmpty) '${row['initiatorName']}',
      if (source.trim().isNotEmpty) '来源提案 $source',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final type = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFEEEBFB),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${row['templateTitle'] ?? ''}',
        style: TextStyle(
          fontSize: 12,
          color: DunesColors.resolve(context, const Color(0xFF4128B5)),
        ),
      ),
    );
    final hasHistory = history && (row['history'] as List? ?? const []).isNotEmpty;
    return InkWell(
      onTap: () => _open(row),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: DunesColors.resolve(
                context,
                _kLine,
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 560;
            final title = Text(
              '${row['title'] ?? row['code'] ?? ''}',
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            );
            final metaText = Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            );
            final amount = Text(
              amountText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            );
            final date = Text(
              _shortDate(row['createdAt']),
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            );
            final historyButton = hasHistory
                ? IconButton(
                    tooltip: '查看审批发起历史',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.history, size: 18),
                    onPressed: () => _showHistory(row),
                  )
                : null;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: type),
                      const Spacer(),
                      _status(status),
                      ?historyButton,
                    ],
                  ),
                  const SizedBox(height: 4),
                  title,
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(child: metaText),
                      const SizedBox(width: 8),
                      amount,
                      const SizedBox(width: 8),
                      date,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: type,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 2), metaText],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 120, child: amount),
                const SizedBox(width: 16),
                SizedBox(width: 92, child: _status(status)),
                SizedBox(width: 52, child: date),
                SizedBox(width: 36, child: historyButton),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _status(String status) {
    final (dot, text) = switch (status) {
      'APPROVED' => (const Color(0xFF1E7A4E), const Color(0xFF1E6B45)),
      'REJECTED' => (const Color(0xFFB42318), const Color(0xFF9A1C12)),
      'PENDING' || 'RUNNING' => (const Color(0xFFC77700), const Color(0xFF8A4B00)),
      _ => (const Color(0xFF9A97AC), const Color(0xFF5F5D70)),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: DunesColors.resolve(context, dot),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            detailStatusLabel(status),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, text),
            ),
          ),
        ),
      ],
    );
  }

  Widget _templateFilter() {
    final bizTemplates = _templates.where((t) => t.category == 'biz').toList();
    return PopupMenuButton<String>(
      key: const ValueKey('related-approval-type-filter'),
      tooltip: '审批类型',
      enabled: !_busy,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        setState(() {
          _templateKey = value;
          _page = 1;
        });
        unawaited(_load());
      },
      itemBuilder: (context) => {
        '': '全部',
        for (final template in bizTemplates.isEmpty ? _templates : bizTemplates)
          template.templateKey: template.title,
      }.entries
          .map(
            (entry) => PopupMenuItem<String>(
              value: entry.key,
              height: 38,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: entry.key == _templateKey
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: DunesColors.resolve(context, _kAccent),
                          )
                        : null,
                  ),
                  Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: entry.key == _templateKey
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            _templateKey.isEmpty ? const Color(0xFFF1EFF8) : const Color(0xFFECE8FA),
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '类型 ',
              style: TextStyle(
                fontSize: 11.5,
                color: DunesColors.resolve(context, const Color(0xFF6B6680)),
              ),
            ),
            Text(
              _templateKey.isEmpty
                  ? '全部'
                  : _templates
                            .where((t) => t.templateKey == _templateKey)
                            .map((t) => t.title)
                            .firstOrNull ??
                        '全部',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, const Color(0xFF4A3A9A)),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: DunesColors.resolve(context, const Color(0xFF6B6680)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? DunesColors.resolve(context, _kAccent)
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: DunesColors.resolve(
              context,
              selected ? _kAccent : const Color(0xFF5F5D70),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bucketChip(BuildContext context, String label) {
    final (bg, fg) = switch (label) {
      '收入' || '冲减收入' => (const Color(0xFFEEEBFB), const Color(0xFF3B2E8F)),
      '周转资金' => (const Color(0xFFE6F0FB), const Color(0xFF1F4F8A)),
      '无金额' => (const Color(0xFFF1F0F6), const Color(0xFF4F4D60)),
      _ => (const Color(0xFFFBEDE6), const Color(0xFF7A3212)),
    };
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: DunesColors.resolve(context, fg)),
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: error ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: DunesColors.resolve(context, DunesColors.text3),
      ),
    ),
  );

  String _money(Object? raw) {
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? ''}'.replaceAll(RegExp(r'[,，¥￥元\s]'), ''));
    if (value == null) return '—';
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${value < 0 ? '−' : ''}¥$digits.${parts[1]}';
  }

  List<({int userId, String name})> get _launchers => [
    for (final item in _maps(_data['launchers']))
      (
        userId: (item['userId'] as num?)?.toInt() ?? 0,
        name: '${item['name'] ?? ''}'.trim(),
      ),
  ];

  /// 可发起人：提案负责人授权的额外同事，可在本提案内发起业务审批。
  Widget _launcherBar() {
    final launchers = _launchers;
    final canManage = _data['canManageLaunchers'] == true;
    if (launchers.isEmpty && !canManage) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: DunesColors.resolve(
              context,
              _kLine,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '可发起人',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          if (launchers.isEmpty)
            Text(
              '仅提案负责人',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          for (final item in launchers)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFF1F0F6),
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.name.isEmpty ? '用户 ${item.userId}' : item.name,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (canManage)
            TextButton(
              key: const ValueKey('proposal-approval-launchers-edit'),
              onPressed: _busy ? null : _editLaunchers,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(launchers.isEmpty ? '添加' : '设置'),
            ),
        ],
      ),
    );
  }

  Future<void> _editLaunchers() async {
    final selected = {for (final item in _launchers) item.userId};
    final people = widget.people.where((p) => p.userId > 0).toList();
    var query = '';
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = query.trim().toLowerCase();
          final shown = q.isEmpty
              ? people
              : people
                    .where(
                      (p) => '${p.name} ${p.username} ${p.departmentName} ${p.positionName}'
                          .toLowerCase()
                          .contains(q),
                    )
                    .toList();
          return AlertDialog(
            title: const Text('可发起人'),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '提案负责人默认可以发起。这里添加的同事也能在本提案内发起业务审批，并能查看本提案。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: DunesColors.resolve(ctx, DunesColors.text3),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: '搜索姓名、部门',
                    ),
                    onChanged: (v) => setLocal(() => query = v),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: people.isEmpty
                        ? const Center(child: Text('人员名单加载中或为空'))
                        : ListView(
                            children: [
                              for (final p in shown)
                                CheckboxListTile(
                                  dense: true,
                                  value: selected.contains(p.userId),
                                  title: Text(p.name),
                                  subtitle: Text(
                                    [p.departmentName, p.positionName]
                                        .where((s) => s.trim().isNotEmpty)
                                        .join(' · '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onChanged: (v) => setLocal(() {
                                    v == true
                                        ? selected.add(p.userId)
                                        : selected.remove(p.userId);
                                  }),
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
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: Text('保存（${selected.length}）'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _service.saveProposalApprovalLaunchers(
        widget.proposal.id,
        result.toList(),
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    }
  }

  /// 关联已有审批：把强制前单独发起、还没挂提案的业务审批补挂到本提案。
  Future<void> _linkExisting() async {
    var query = '';
    var loading = true;
    String? error;
    var rows = <Map<String, dynamic>>[];
    var started = false;
    Future<void> search(BuildContext ctx, StateSetter setLocal) async {
      if (!ctx.mounted) return;
      setLocal(() {
        loading = true;
        error = null;
      });
      try {
        final result = await _service.fetchProposalLinkableApprovals(
          widget.proposal.id,
          query: query,
        );
        if (!ctx.mounted) return;
        setLocal(() {
          rows = result;
          loading = false;
        });
      } catch (e) {
        if (!ctx.mounted) return;
        setLocal(() {
          error = friendlyErrorText(e);
          loading = false;
        });
      }
    }

    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (!started) {
            started = true;
            // 首次搜索放到下一帧，避免在 build 里 setState。
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => unawaited(search(ctx, setLocal)),
            );
          }
          return AlertDialog(
            title: const Text('关联已有审批'),
            content: SizedBox(
              width: 560,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '只列出你发起或参与、还没关联提案的业务审批。一张审批只能关联一个提案，关联后会记录操作人和时间。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: DunesColors.resolve(ctx, DunesColors.text3),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: '搜索审批编号、名称',
                    ),
                    onChanged: (v) => query = v,
                    onSubmitted: (_) => unawaited(search(ctx, setLocal)),
                  ),
                  const SizedBox(height: 6),
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: !loading && rows.isEmpty && error == null
                        ? const Center(child: Text('没有可以关联的业务审批'))
                        : ListView(
                            children: [
                              for (final row in rows)
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    '${row['templateTitle']} · ${row['title']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${row['code']} · ${_shortDate(row['createdAt'])} · '
                                    '${detailStatusLabel('${row['status']}')} · ${_money(row['amount'])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: _bucketChip(
                                    ctx,
                                    '${row['bucketLabel'] ?? proposalApprovalBucketLabel('${row['templateKey']}')}',
                                  ),
                                  onTap: () => Navigator.pop(ctx, row),
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
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认关联'),
        content: Text(
          '把「${picked['templateTitle']} · ${picked['code']}」关联到本提案？\n关联后不能改挂到其他提案。',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('关联'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.linkApprovalToProposal(
        widget.proposal.id,
        businessType: '${picked['businessType']}',
        businessId: '${picked['businessId']}',
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    }
  }

  String _shortDate(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '';
    return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showHistory(Map<String, dynamic> row) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('审批发起历史'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${row['templateTitle']} · ${row['code']}'),
              const SizedBox(height: 8),
              for (final attempt in (row['history'] as List).whereType<Map>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_date(attempt['createdAt'])} · ${detailStatusLabel('${attempt['status']}')}\n'
                    '审批 #${attempt['approvalId']} · 提案第 ${attempt['proposalVersion']} 版\n'
                    '${(attempt['proposalSnapshot'] as Map?)?['code'] ?? ''} '
                    '${(attempt['proposalSnapshot'] as Map?)?['title'] ?? ''}',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
            ],
          ),
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

  String _date(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    return date == null
        ? '$value'
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

Future<void> showProposalBusinessForm({
  required BuildContext context,
  required AuthSession session,
  required String templateKey,
  Map<String, dynamic>? proposal,
  int? businessId,
  String businessType = 'PROPOSAL',
}) {
  Widget host(VoidCallback close) => _ProposalBusinessFormHost(
    session: session,
    templateKey: templateKey,
    proposal: proposal,
    businessId: businessId,
    businessType: businessType,
    close: close,
  );
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 920,
          height: MediaQuery.sizeOf(ctx).height * .9,
          child: host(() => Navigator.pop(ctx)),
        ),
      ),
    );
  }
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (ctx) =>
          Scaffold(body: SafeArea(child: host(() => Navigator.pop(ctx)))),
    ),
  );
}

class _ProposalBusinessFormHost extends StatefulWidget {
  const _ProposalBusinessFormHost({
    required this.session,
    required this.templateKey,
    required this.businessType,
    required this.close,
    this.proposal,
    this.businessId,
  });
  final AuthSession session;
  final String templateKey, businessType;
  final Map<String, dynamic>? proposal;
  final int? businessId;
  final VoidCallback close;
  @override
  State<_ProposalBusinessFormHost> createState() =>
      _ProposalBusinessFormHostState();
}

class _ProposalBusinessFormHostState extends State<_ProposalBusinessFormHost> {
  late final _nav = _ProposalFormNavigation(widget.close);
  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NativeXflowFormPage(
    session: widget.session,
    navigation: _nav,
    templateKey: widget.templateKey,
    editProposalId: widget.businessId,
    editBusinessType: widget.businessType,
    initialLinkedProposal: widget.proposal,
    backScreen: 'proposal',
    onSubmitted: (_, _) => widget.close(),
  );
}

class _ProposalFormNavigation extends DunesNavigationController {
  _ProposalFormNavigation(this.close) : super(initialScreen: 'proposal');
  final VoidCallback close;
  @override
  void back() => close();
  @override
  void go(String screenId) => close();
  @override
  void popTo(String screenId) => close();
}
