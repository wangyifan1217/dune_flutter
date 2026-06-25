import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../xflow/native_b1_page.dart';
import '../xflow/xflow_models.dart';

class NativeMyApprovalWorkbenchPage extends StatelessWidget {
  const NativeMyApprovalWorkbenchPage({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return NativeB1Page(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
    );
  }
}

class NativeMyInitiatedPage extends StatelessWidget {
  const NativeMyInitiatedPage({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return NativeB14Page(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
    );
  }
}

class NativeMyCcProposalPage extends StatelessWidget {
  const NativeMyCcProposalPage({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return NativeP1Page(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
    );
  }
}
