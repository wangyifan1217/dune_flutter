import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import '../xflow/proposal_upload_config.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'native_approval_assistant_page.dart';

/// 审批助手选单：待我审批 / 我发起的（审批中）。
class NativeApprovalAssistantPendingPage extends StatefulWidget {
  const NativeApprovalAssistantPendingPage({
    super.key,
    required this.session,
    required this.mode,
    this.onBack,
    this.onOpenDetail,
    this.onActionDone,
  });

  final AuthSession session;
  final ApprovalAssistantPickMode mode;
  final VoidCallback? onBack;
  final Future<void> Function(String businessType, int businessId)? onOpenDetail;
  final VoidCallback? onActionDone;

  @override
  State<NativeApprovalAssistantPendingPage> createState() =>
      _NativeApprovalAssistantPendingPageState();
}

class _NativeApprovalAssistantPendingPageState
    extends State<NativeApprovalAssistantPendingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final XflowService _xflow;
  late final ConversationService _im;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<XflowProposalItem> _mine = const [];
  List<XflowProposalItem> _initiated = const [];
  String _query = '';
  bool _loading = true;
  String? _error;
  bool _acting = false;
  int _loadGen = 0;
  int _lastTabIndex = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.mode == ApprovalAssistantPickMode.urge ? 1 : 0;
    _lastTabIndex = initial;
    _tabs = TabController(length: 2, vsync: this, initialIndex: initial);
    _tabs.addListener(_onTabChanged);
    _xflow = XflowService(session: widget.session);
    _im = ConversationService(session: widget.session);
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q == _query) return;
      setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _search.dispose();
    _searchFocus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == _lastTabIndex) return;
    _lastTabIndex = _tabs.index;
    _load(silent: true);
  }

  List<XflowProposalItem> _filter(List<XflowProposalItem> src) {
    if (_query.isEmpty) return src;
    return src.where(_matchesQuery).toList(growable: false);
  }

  bool _matchesQuery(XflowProposalItem e) {
    final q = _query;
    if (q.isEmpty) return true;
    final kind = _kindLabel(e).toLowerCase();
    final status = _statusLabel(e.status).toLowerCase();
    final title = _displayTitle(e).toLowerCase();
    final type = _typeLabel(e, kind).toLowerCase();
    return title.contains(q) ||
        e.title.toLowerCase().contains(q) ||
        e.code.toLowerCase().contains(q) ||
        e.businessType.toLowerCase().contains(q) ||
        e.createdByName.toLowerCase().contains(q) ||
        e.status.toLowerCase().contains(q) ||
        kind.contains(q) ||
        status.contains(q) ||
        type.contains(q) ||
        '${e.id}'.contains(q);
  }

  Future<void> _load({bool silent = false}) async {
    final gen = ++_loadGen;
    final showSpinner = !silent || (_mine.isEmpty && _initiated.isEmpty);
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final results = await Future.wait([
        _xflow.fetchB1Approvals(),
        _xflow.fetchB14Initiated(),
      ]);
      final mine = results[0]
          // “待我审批”必须是当前用户尚未处理的 OPEN todo；整单仍在
          // PENDING 只代表流程未结束，不能说明仍等待当前用户审批。
          .where(_isMyOpenApproval)
          .toList(growable: false);
      final initiated = results[1]
          .where((e) {
            final s = e.status.toUpperCase();
            return s == 'PENDING' ||
                s == 'PENDING_INITIATE' ||
                s == 'IN_PROGRESS' ||
                s == 'OPEN';
          })
          .toList(growable: false);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _mine = mine;
        _initiated = initiated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  bool _isMyOpenApproval(XflowProposalItem item) {
    return item.todoHint?.status.trim().toUpperCase() == 'OPEN';
  }

  Future<void> _openItem(XflowProposalItem item) async {
    final open = widget.onOpenDetail;
    if (open == null) return;
    await open(item.businessType, item.id);
    if (!mounted) return;
    await _load(silent: true);
  }

  Future<void> _runExplain(XflowProposalItem item) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await _im.approvalAssistantExplain(
        businessType: item.businessType,
        businessId: item.id,
      );
      if (!mounted) return;
      showDunesToast(context, '已开始解释，完成后会推送到会话');
      widget.onActionDone?.call();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _runUrge(XflowProposalItem item) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await _im.approvalAssistantUrgeDraft(
        businessType: item.businessType,
        businessId: item.id,
      );
      if (!mounted) return;
      showDunesToast(context, '已开始生成催办话术，完成后会推送到会话');
      widget.onActionDone?.call();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.mode) {
      ApprovalAssistantPickMode.explain => '选择要解释的单据',
      ApprovalAssistantPickMode.urge => '选择要催办的单据',
      ApprovalAssistantPickMode.browse => '待审列表',
    };
    final mine = _filter(_mine);
    final initiated = _filter(_initiated);
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                    icon: const Icon(Icons.chevron_left_rounded, size: 28),
                    color: DunesColors.text2,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: DunesTypography.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  if (_acting)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: DunesColors.text,
                ),
                decoration: InputDecoration(
                  hintText: '搜索标题、单号、类型、发起人…',
                  hintStyle: DunesTypography.sans(
                    fontSize: 13.5,
                    color: DunesColors.text3,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: DunesColors.text3,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          onPressed: () {
                            _search.clear();
                            _searchFocus.requestFocus();
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: DunesColors.text3,
                          ),
                        ),
                  filled: true,
                  fillColor: DunesColors.brandPurpleSoft,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: DunesColors.brandPurpleLine,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: DunesColors.brandPurple,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: DunesColors.brandPurpleDeep,
              unselectedLabelColor: DunesColors.text3,
              indicatorColor: DunesColors.brandPurple,
              tabs: [
                Tab(text: '待我审批(${mine.length})'),
                Tab(text: '我发起进行中(${initiated.length})'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _ListPane(
                          items: mine,
                          mode: widget.mode,
                          empty: _query.isEmpty
                              ? '暂无待我审批'
                              : '未找到匹配的待审',
                          onOpen: _openItem,
                          onExplain: _runExplain,
                          onUrge: _runUrge,
                        ),
                        _ListPane(
                          items: initiated,
                          mode: widget.mode,
                          empty: _query.isEmpty
                              ? '暂无进行中的发起'
                              : '未找到匹配的发起',
                          preferUrge: true,
                          onOpen: _openItem,
                          onExplain: _runExplain,
                          onUrge: _runUrge,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.items,
    required this.mode,
    required this.empty,
    required this.onOpen,
    required this.onExplain,
    required this.onUrge,
    this.preferUrge = false,
  });

  final List<XflowProposalItem> items;
  final ApprovalAssistantPickMode mode;
  final String empty;
  final ValueChanged<XflowProposalItem> onOpen;
  final ValueChanged<XflowProposalItem> onExplain;
  final ValueChanged<XflowProposalItem> onUrge;
  final bool preferUrge;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          empty,
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final kind = _kindLabel(item);
        final type = _typeLabel(item, kind);
        final title = _displayTitle(item);
        final code = item.code.trim().isEmpty
            ? (item.id > 0 ? '#${item.id}' : '')
            : item.code.trim();
        final submitter = item.createdByName.trim();
        final timeText = item.createdAt != null
            ? _formatDateTime(item.createdAt!)
            : '';
        final stepText = item.totalSteps > 0
            ? '第 ${item.currentStep}/${item.totalSteps} 步'
            : '';
        final urgency = _urgencyLabel(item);
        final status = _statusLabel(item.status);
        return Material(
          color: DunesColors.bgApp,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => onOpen(item),
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DunesColors.brandPurpleLine),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.sans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(label: status, status: item.status),
                      if (urgency != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: DunesColors.coralSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            urgency,
                            style: DunesTypography.sans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.coral,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (code.isNotEmpty) ...[
                    _metaRow('编号', code),
                    const SizedBox(height: 4),
                  ],
                  _metaRow('种类', kind),
                  if (type.isNotEmpty && type != kind) ...[
                    const SizedBox(height: 4),
                    _metaRow('类型', type),
                  ],
                  if (submitter.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _metaRow('发起人', submitter),
                  ],
                  if (timeText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _metaRow('发起时间', timeText),
                  ],
                  if (stepText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _metaRow('审批进度', stepText),
                  ],
                  if (item.scaleWan != null &&
                      item.scaleWan!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _metaRow('金额', '¥${item.scaleWan!.trim()}万'),
                  ],
                  if (mode != ApprovalAssistantPickMode.browse) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (mode == ApprovalAssistantPickMode.explain ||
                            !preferUrge)
                          TextButton(
                            onPressed: () => onExplain(item),
                            child: const Text('解释'),
                          ),
                        if (mode == ApprovalAssistantPickMode.urge || preferUrge)
                          TextButton(
                            onPressed: () => onUrge(item),
                            child: const Text('催办'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text2,
            ),
          ),
        ),
      ],
    );
  }

  String? _urgencyLabel(XflowProposalItem item) {
    final at = item.createdAt;
    if (at == null) return null;
    final ageHours = DateTime.now().difference(at).inHours;
    if (ageHours >= 24 * 7) return '超1周';
    if (ageHours >= 24) return '超24h';
    return null;
  }
}

String _kindLabel(XflowProposalItem item) {
  final documentKind = item.documentKind?.trim() ?? '';
  if (documentKind.isNotEmpty && !_looksLikeEnglishCode(documentKind)) {
    return documentKind;
  }
  return proposalKindLabel(
    templateKey: item.templateKey,
    businessType: item.businessType,
  );
}

String _typeLabel(XflowProposalItem item, String kind) {
  final fromProposal = excelProposalTypeLabel(item.proposalType);
  if (fromProposal != '—') return fromProposal;
  final tx = (item.txType ?? '').trim();
  if (tx.isNotEmpty && !_looksLikeEnglishCode(tx)) return tx;
  final tag = (item.tag1 ?? '').trim();
  if (tag.isNotEmpty && !_looksLikeEnglishCode(tag)) return tag;
  return kind;
}

String _displayTitle(XflowProposalItem item) {
  final kind = _kindLabel(item);
  final raw = _normalizeApprovalAssistantTitle(item.title);
  final bt = item.businessType.trim();
  final generic = raw.isEmpty ||
      raw == bt ||
      raw.toUpperCase() == bt.toUpperCase() ||
      raw.startsWith('$bt #') ||
      _looksLikeEnglishCode(raw);
  final base = generic ? kind : raw;
  final submitter = item.createdByName.trim();
  if (submitter.isEmpty) return base.isEmpty ? '审批单' : base;
  if (base.startsWith('$submitter -') || base.startsWith('$submitter-')) {
    return base;
  }
  return '$submitter - $base';
}

String _normalizeApprovalAssistantTitle(String value) {
  final parts = value
      .split(' - ')
      .map((part) => part.trim())
      .toList(growable: false);
  if (parts.length >= 3 && parts[0].isNotEmpty && parts[0] == parts[1]) {
    return parts.skip(1).join(' - ');
  }
  return value.trim();
}

String _statusLabel(String status) {
  final raw = status.toUpperCase();
  if (raw == 'OPEN' || raw == 'PENDING') return '审批中';
  if (raw == 'APPROVED') return '已通过';
  if (raw == 'DONE') return '已完成';
  if (raw == 'LIVE') return '已上线';
  if (raw == 'REJECTED') return '已驳回';
  if (raw == 'DRAFT') return '草稿';
  if (raw == 'PENDING_INITIATE') return '待发起';
  if (raw == 'VOIDED') return '已作废';
  if (raw == 'SUPERSEDED') return '已替代';
  return raw.isEmpty ? '未知状态' : raw;
}

bool _looksLikeEnglishCode(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(t)) return true;
  if (RegExp(r'^[a-z0-9]+(-[a-z0-9]+)+$').hasMatch(t)) return true;
  return false;
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$m-$d $h:$min';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final st = status.toUpperCase();
    late final Color bg;
    late final Color fg;
    if (st == 'OPEN' || st == 'PENDING') {
      bg = DunesColors.amberSoft;
      fg = const Color(0xFF5D3508);
    } else if (st == 'APPROVED' || st == 'DONE' || st == 'LIVE') {
      bg = DunesColors.greenSoft;
      fg = const Color(0xFF085041);
    } else if (st == 'REJECTED') {
      bg = DunesColors.coralSoft;
      fg = const Color(0xFF993C1D);
    } else if (st == 'DRAFT' || st == 'PENDING_INITIATE') {
      bg = DunesColors.blueSoft;
      fg = DunesColors.blue;
    } else {
      bg = DunesColors.bgSoft;
      fg = DunesColors.text2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
