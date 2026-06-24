import 'package:flutter/widgets.dart';

import '../auth/auth_session.dart';
import '../xflow/native_b1_page.dart';
import '../xflow/xflow_models.dart';

class NativeApprovalPage extends StatefulWidget {
  const NativeApprovalPage({
    super.key,
    required this.session,
    required this.onOpenProposal,
    required this.onFallback,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback onFallback;
  final VoidCallback? onBack;

  @override
  State<NativeApprovalPage> createState() => _NativeApprovalPageState();
}

class _NativeApprovalPageState extends State<NativeApprovalPage> {
  @override
  Widget build(BuildContext context) {
    return NativeB13Page(
      session: widget.session,
      onOpenProposal: widget.onOpenProposal,
      onFallback: widget.onFallback,
      onBack: widget.onBack,
    );
  }
}
