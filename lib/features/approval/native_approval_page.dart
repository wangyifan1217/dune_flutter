import 'package:flutter/widgets.dart';

import '../auth/auth_session.dart';
import '../workbench/workbench_badge_notifier.dart';
import '../xflow/native_b1_page.dart';
import '../xflow/xflow_models.dart';

class NativeApprovalPage extends StatefulWidget {
  const NativeApprovalPage({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  State<NativeApprovalPage> createState() => _NativeApprovalPageState();
}

class _NativeApprovalPageState extends State<NativeApprovalPage> {
  @override
  Widget build(BuildContext context) {
    return NativeB13Page(
      session: widget.session,
      onOpenProposal: widget.onOpenProposal,
      onBack: widget.onBack,
      workbenchRefresh: widget.workbenchRefresh,
    );
  }
}
