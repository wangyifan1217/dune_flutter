import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../proposal_intake/proposal_intake_models.dart';
import '../proposal_intake/proposal_intake_overlay.dart';
import '../proposal_intake/proposal_intake_service.dart';

/// 审批助手「提案审核」：只列出当前用户需要操作的协作提案。
class NativeApprovalAssistantProposalPage extends StatefulWidget {
  const NativeApprovalAssistantProposalPage({
    super.key,
    required this.session,
    this.onBack,
  });

  final AuthSession session;
  final VoidCallback? onBack;

  @override
  State<NativeApprovalAssistantProposalPage> createState() =>
      _NativeApprovalAssistantProposalPageState();
}

class _NativeApprovalAssistantProposalPageState
    extends State<NativeApprovalAssistantProposalPage> {
  late final ProposalIntakeService _service = ProposalIntakeService(
    session: widget.session,
  );
  List<ProposalIntakeRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchList(actionable: true, pageSize: 100);
      if (!mounted) return;
      setState(() => _rows = result.items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ProposalIntakeRow row) async {
    await showProposalIntakeOverlay(
      context: context,
      session: widget.session,
      proposalId: row.id,
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        title: const Text('提案审核'),
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: widget.onBack,
              ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
          ? Center(child: Text(_error!))
          : _rows.isEmpty
          ? const Center(child: Text('暂无需要你处理的提案'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final row = _rows[index];
                final action = proposalIntakeActionLabel(row.myAction);
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => unawaited(_open(row)),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title.isEmpty ? '未命名提案' : row.title,
                            style: DunesTypography.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              row.code,
                              proposalIntakeStatusLabel(row.status),
                              if (action.isNotEmpty) action,
                            ].where((item) => item.isNotEmpty).join(' · '),
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
