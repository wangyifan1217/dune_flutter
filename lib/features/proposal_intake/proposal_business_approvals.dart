import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/approval_detail_dialog.dart';
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
  });
  final AuthSession session;
  final ProposalIntakeRow proposal;
  final XflowService? service;
  final bool allowLaunch;

  @override
  State<ProposalBusinessApprovals> createState() =>
      _ProposalBusinessApprovalsState();
}

class _ProposalBusinessApprovalsState extends State<ProposalBusinessApprovals> {
  late final _service = widget.service ?? XflowService(session: widget.session);
  Map<String, dynamic> _data = const {};
  bool _enabled = false, _busy = false, _launching = false;
  String? _error, _policyError;
  int _page = 1, _request = 0;
  String _templateKey = '';
  List<XflowTemplateCard> _templates = const [];

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
    if (!mounted) return;
    final unique = <String, XflowTemplateCard>{};
    for (final template in results.expand((items) => items)) {
      if (template.templateKey != XflowService.salesTemplateKey) {
        unique[template.templateKey] = template;
      }
    }
    setState(() => _templates = unique.values.toList());
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

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Independent reads: a configuration failure must not erase existing records.
    final policy = !widget.allowLaunch ? Future<void>.value() : _service
        .fetchProposalLinkEnabled()
        .then((enabled) {
          if (!mounted || request != _request) return;
          setState(() {
            _enabled = enabled;
            _policyError = null;
          });
        })
        .catchError((Object e) {
          if (!mounted || request != _request) return;
          setState(() {
            _enabled = false;
            _policyError = friendlyErrorText(e);
          });
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
    await policy;
    if (mounted && request == _request) setState(() => _busy = false);
  }

  Future<void> _launch() async {
    setState(() => _launching = true);
    try {
      if (!await _service.fetchProposalLinkEnabled()) {
        if (mounted) setState(() => _enabled = false);
        return;
      }
      final templates = (await _service.fetchTemplatesByCategory('biz'))
          .where(
            (t) => t.enabled && t.templateKey != XflowService.salesTemplateKey,
          )
          .toList();
      if (!mounted) return;
      final selected = await showDialog<XflowTemplateCard>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('发起业务审批'),
          children: [
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无可用业务审批模板'),
              ),
            for (final t in templates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(t.title),
                ),
              ),
          ],
        ),
      );
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

  Future<void> _open(Map<String, dynamic> row) async {
    await showApprovalDetailOverlay(
      context: context,
      session: widget.session,
      share: ApprovalChatShare(
        businessType: '${row['businessType']}',
        businessId: int.parse('${row['businessId']}'),
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

  @override
  Widget build(BuildContext context) {
    final items = (_data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final total = (_data['total'] as num?)?.toInt() ?? 0;
    final stats = _data['stats'] as Map? ?? const {};
    return Card(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text(
                  '关联业务审批',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '刷新关联审批',
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                    if (widget.allowLaunch && _enabled &&
                        _data['canLaunch'] == true &&
                        widget.proposal.status == 'done')
                      FilledButton.icon(
                        onPressed: _launching || _busy ? null : _launch,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(_launching ? '正在打开…' : '发起业务审批'),
                      ),
                  ],
                ),
              ],
            ),
            Text(
              '仅展示你有权查看的审批 · 审批中 ${stats['PENDING'] ?? 0} · 已通过 ${stats['APPROVED'] ?? 0}',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                key: const ValueKey('related-approval-type-filter'),
                tooltip: '审批类型',
                enabled: !_busy,
                position: PopupMenuPosition.under,
                onSelected: (value) {
                  setState(() { _templateKey = value; _page = 1; });
                  unawaited(_load());
                },
                itemBuilder: (context) => {
                  '': '全部',
                  for (final template in _templates) template.templateKey: template.title,
                }.entries.map((entry) => PopupMenuItem<String>(
                  value: entry.key,
                  height: 38,
                  child: Row(children: [
                    SizedBox(width: 20, child: entry.key == _templateKey
                        ? Icon(Icons.check_rounded, size: 16, color: DunesColors.resolve(context, const Color(0xFF4A3A9A))) : null),
                    Text(entry.value, style: TextStyle(fontSize: 13, fontWeight: entry.key == _templateKey ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                )).toList(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(context, _templateKey.isEmpty ? const Color(0xFFF1EFF8) : const Color(0xFFECE8FA), role: DunesColorRole.surface),
                    border: Border.all(color: DunesColors.resolve(context, _templateKey.isEmpty ? Colors.transparent : const Color(0xFFB9ACEB), role: DunesColorRole.border)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('类型 ', style: TextStyle(fontSize: 11.5, color: DunesColors.resolve(context, const Color(0xFF6B6680)))),
                    Text(_templateKey.isEmpty ? '全部' : _templates.where((t) => t.templateKey == _templateKey).map((t) => t.title).firstOrNull ?? '全部', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: DunesColors.resolve(context, const Color(0xFF4A3A9A)))),
                    Icon(Icons.arrow_drop_down_rounded, size: 18, color: DunesColors.resolve(context, const Color(0xFF6B6680))),
                  ]),
                ),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (_policyError != null)
              Text(
                '发起配置读取失败：$_policyError',
                style: const TextStyle(fontSize: 12),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!_busy && _error == null && items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无关联业务审批'),
              ),
            for (final row in items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${row['templateTitle']} · ${row['code']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${row['initiatorName']} · ${_date(row['createdAt'])}'
                  '${row['amount'] == null ? '' : ' · ¥${row['amount']}'}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      detailStatusLabel('${row['status']}'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if ((row['history'] as List? ?? const []).isNotEmpty)
                      IconButton(
                        tooltip: '查看审批发起历史',
                        icon: const Icon(Icons.history, size: 18),
                        onPressed: () => _showHistory(row),
                      ),
                  ],
                ),
                onTap: () => _open(row),
              ),
            if (total > 20 || _page > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '共 $total 条 · 第 $_page 页',
                    style: const TextStyle(fontSize: 12),
                  ),
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
        ),
      ),
    );
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
