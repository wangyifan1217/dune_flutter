import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../proposal_intake/proposal_intake_service.dart';
import 'approval_chat_share.dart';

/// 协作提案转发名片。历史消息标题可能只剩「协作提案」，打开时补上提案名称。
class ProposalIntakeShareCard extends StatefulWidget {
  const ProposalIntakeShareCard({
    super.key,
    required this.share,
    required this.onTap,
    this.session,
    this.loadTitle,
    this.onSecondaryTapDown,
  });

  final ApprovalChatShare share;
  final VoidCallback onTap;
  final AuthSession? session;
  final Future<String?> Function(int id)? loadTitle;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<ProposalIntakeShareCard> createState() => _ProposalIntakeShareCardState();
}

class _ProposalIntakeShareCardState extends State<ProposalIntakeShareCard> {
  static final Map<int, String> _cache = {};
  String? _fetched;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProposalIntakeShareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.share.businessId != widget.share.businessId ||
        oldWidget.share.title != widget.share.title) {
      _fetched = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.share.proposalTitleNeedsLookup) return;
    final id = widget.share.businessId;
    final cached = _cache[id];
    if (cached != null && cached.isNotEmpty) {
      if (mounted) setState(() => _fetched = cached);
      return;
    }
    try {
      final title = widget.loadTitle != null
          ? await widget.loadTitle!(id)
          : await _loadFromService(id);
      final resolved = (title ?? '').trim();
      if (resolved.isEmpty || !mounted) return;
      _cache[id] = resolved;
      setState(() => _fetched = resolved);
    } catch (_) {}
  }

  Future<String?> _loadFromService(int id) async {
    final session = widget.session;
    if (session == null || id <= 0) return null;
    final row = await ProposalIntakeService(session: session).fetchDetail(id);
    final title = row.title.trim();
    if (title.isNotEmpty && !approvalCardTitleIsWeak(title)) return title;
    final name = '${row.form['proposalName'] ?? ''}'.trim();
    if (name.isNotEmpty && !approvalCardTitleIsWeak(name)) return name;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.share;
    return ChatApprovalCard(
      title: proposalIntakeCardTitle(
        storedTitle: share.title,
        fetchedTitle: _fetched,
      ),
      statusLabel: '',
      subtitle: share.proposalCardLine,
      brandLabel: '协作提案',
      subtitleMaxLines: 2,
      onTap: widget.onTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
    );
  }
}
