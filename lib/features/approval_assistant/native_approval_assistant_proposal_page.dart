import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../proposal_intake/native_proposal_intake_page.dart';
import '../proposal_intake/proposal_intake_ui.dart';
import '../tasks/native_task_home_pane.dart';

/// 审批助手「提案审核」：只显示当前用户待处理的提案，不含草稿和已完成。
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
  TaskShellChrome _chrome = const TaskShellChrome();

  @override
  Widget build(BuildContext context) {
    final inForm = _chrome.onBack != null;
    return Scaffold(
      backgroundColor: ProposalPalette.page,
      appBar: AppBar(
        title: Text(inForm ? '销售业务提案' : '提案审核'),
        leading: widget.onBack == null && !inForm
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: _chrome.onBack ?? widget.onBack,
              ),
      ),
      body: NativeProposalIntakePage(
        session: widget.session,
        showCreate: false,
        assistantMode: true,
        onChromeChanged: (chrome) {
          if (!mounted) return;
          setState(() => _chrome = chrome);
        },
      ),
    );
  }
}
