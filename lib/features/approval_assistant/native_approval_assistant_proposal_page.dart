import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../proposal_intake/native_proposal_intake_page.dart';
import '../proposal_intake/proposal_intake_models.dart';
import '../proposal_intake/proposal_intake_ui.dart';
import '../tasks/native_task_home_pane.dart';

/// 审批助手「销售提案 / 采购提案」：只显示当前用户待处理的该类提案。
class NativeApprovalAssistantProposalPage extends StatefulWidget {
  const NativeApprovalAssistantProposalPage({
    super.key,
    required this.session,
    this.kind = 'sales',
    this.onBack,
  });

  final AuthSession session;
  final String kind;
  final VoidCallback? onBack;

  @override
  State<NativeApprovalAssistantProposalPage> createState() =>
      _NativeApprovalAssistantProposalPageState();
}

class _NativeApprovalAssistantProposalPageState
    extends State<NativeApprovalAssistantProposalPage> {
  TaskShellChrome _chrome = const TaskShellChrome();

  String get _kindTitle => proposalIntakeKindEyebrow(widget.kind);

  @override
  Widget build(BuildContext context) {
    final inForm = _chrome.onBack != null;
    return Scaffold(
      backgroundColor: ProposalPalette.page,
      appBar: AppBar(
        title: Text(_kindTitle),
        leading: widget.onBack == null && !inForm
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: _chrome.onBack ?? widget.onBack,
              ),
      ),
      body: NativeProposalIntakePage(
        key: ValueKey('assistant-proposal-${widget.kind}'),
        session: widget.session,
        showCreate: false,
        assistantMode: true,
        kind: widget.kind,
        onChromeChanged: (chrome) {
          if (!mounted) return;
          setState(() => _chrome = chrome);
        },
      ),
    );
  }
}
