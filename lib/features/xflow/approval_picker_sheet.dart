import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'approval_chat_share.dart';
import 'proposal_upload_config.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

/// 选择要转发到当前会话的审批单（我审批的 / 我发起的）。
Future<ApprovalChatShare?> showApprovalPickerSheet({
  required BuildContext context,
  required AuthSession session,
}) {
  return showModalBottomSheet<ApprovalChatShare>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ApprovalPickerSheet(session: session),
  );
}

class _ApprovalPickerSheet extends StatefulWidget {
  const _ApprovalPickerSheet({required this.session});

  final AuthSession session;

  @override
  State<_ApprovalPickerSheet> createState() => _ApprovalPickerSheetState();
}

class _ApprovalPickerSheetState extends State<_ApprovalPickerSheet>
    with SingleTickerProviderStateMixin {
  late final XflowService _service = XflowService(session: widget.session);
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<XflowProposalItem> _mineApprove = const [];
  List<XflowProposalItem> _mineInitiated = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchB1Approvals(),
        _service.fetchB14Initiated(),
      ]);
      if (!mounted) return;
      setState(() {
        _mineApprove = results[0]
            .where(_isForwardable)
            .toList(growable: false);
        _mineInitiated = results[1]
            .where(_isForwardable)
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  List<XflowProposalItem> _filtered(List<XflowProposalItem> rows) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where((e) {
          final kind = _kindLabel(e).toLowerCase();
          final hay =
              '${e.title} ${e.code} $kind ${e.status} ${e.createdByName}'
                  .toLowerCase();
          return hay.contains(q);
        })
        .toList(growable: false);
  }

  void _pick(XflowProposalItem item) {
    Navigator.of(context).pop(ApprovalChatShare.fromListItem(item));
  }

  /// 转发审批不展示草稿、已作废。
  bool _isForwardable(XflowProposalItem item) {
    final st = item.status.toUpperCase();
    return st != 'DRAFT' && st != 'VOIDED';
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: DunesColors.borderSoft,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '转发审批',
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索标题 / 编号…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: DunesColors.accentDeep,
            unselectedLabelColor: DunesColors.text3,
            indicatorColor: DunesColors.accentDeep,
            tabs: const [
              Tab(text: '我审批的'),
              Tab(text: '我发起的'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _list(_filtered(_mineApprove)),
                      _list(_filtered(_mineInitiated)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<XflowProposalItem> rows) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '暂无可转发的审批',
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final item = rows[i];
        final kind = _kindLabel(item);
        final code = item.code.trim().isEmpty
            ? (item.id > 0 ? '#${item.id}' : '')
            : item.code.trim();
        final timeText = item.createdAt != null
            ? _formatDateTime(item.createdAt!)
            : '—';
        final typeLabel = _typeLabel(item, kind);
        return Material(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pick(item),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _displayTitle(item, kind),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (code.isNotEmpty) ...[
                    _metaRow('编号', code),
                    const SizedBox(height: 4),
                  ],
                  _metaRow('种类', kind),
                  if (typeLabel.isNotEmpty && typeLabel != kind) ...[
                    const SizedBox(height: 4),
                    _metaRow('类型', typeLabel),
                  ],
                  const SizedBox(height: 4),
                  _metaRow('发起时间', timeText),
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

  String _kindLabel(XflowProposalItem item) {
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
    return kind;
  }

  String _displayTitle(XflowProposalItem item, String kind) {
    final raw = item.title.trim();
    final bt = item.businessType.trim();
    final generic = raw.isEmpty ||
        raw == bt ||
        raw.toUpperCase() == bt.toUpperCase() ||
        raw.startsWith('$bt #') ||
        _looksLikeEnglishCode(raw);
    final base = generic ? kind : raw;
    final submitter = item.createdByName.trim();
    if (submitter.isEmpty) return base;
    if (base.startsWith('$submitter -') || base.startsWith('$submitter-')) {
      return base;
    }
    return '$submitter - $base';
  }

  bool _looksLikeEnglishCode(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    // 全大写英文/下划线业务码，或 kebab-case 模板键
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final st = status.toUpperCase();
    late final Color bg;
    late final Color fg;
    late final String label;
    if (st == 'OPEN' || st == 'PENDING') {
      bg = DunesColors.amberSoft;
      fg = const Color(0xFF5D3508);
      label = '审批中';
    } else if (st == 'APPROVED' || st == 'DONE' || st == 'LIVE') {
      bg = DunesColors.greenSoft;
      fg = const Color(0xFF085041);
      label = '已通过';
    } else if (st == 'REJECTED') {
      bg = DunesColors.coralSoft;
      fg = const Color(0xFF993C1D);
      label = '已驳回';
    } else if (st == 'DRAFT' || st == 'PENDING_INITIATE') {
      bg = DunesColors.blueSoft;
      fg = DunesColors.blue;
      label = st == 'PENDING_INITIATE' ? '待发起' : '草稿';
    } else if (st == 'VOIDED') {
      bg = const Color(0xFFF0F0F0);
      fg = DunesColors.text3;
      label = '已作废';
    } else if (st == 'SUPERSEDED') {
      bg = DunesColors.bgSoft;
      fg = DunesColors.text2;
      label = '已替代';
    } else {
      bg = DunesColors.bgSoft;
      fg = DunesColors.text2;
      label = st.isEmpty ? '未知' : st;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
