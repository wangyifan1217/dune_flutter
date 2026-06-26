import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../workbench/workbench_badge_notifier.dart';
import '../xflow/native_b1_page.dart';
import '../xflow/xflow_models.dart';

class NativeMyApprovalWorkbenchPage extends StatelessWidget {
  const NativeMyApprovalWorkbenchPage({
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
  Widget build(BuildContext context) {
    return NativeB1Page(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      workbenchRefresh: workbenchRefresh,
    );
  }
}

class NativeMyInitiatedPage extends StatelessWidget {
  const NativeMyInitiatedPage({
    super.key,
    required this.session,
    required this.onOpenProposal,
    this.onBack,
    this.initialStatusFilter,
    this.workbenchRefresh,
  });

  final AuthSession session;
  final void Function(XflowProposalItem item) onOpenProposal;
  final VoidCallback? onBack;
  final String? initialStatusFilter;
  final WorkbenchDataRefreshNotifier? workbenchRefresh;

  @override
  Widget build(BuildContext context) {
    return NativeB14Page(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      initialStatusFilter: initialStatusFilter,
      workbenchRefresh: workbenchRefresh,
    );
  }
}

class NativeMyCcProposalPage extends StatelessWidget {
  const NativeMyCcProposalPage({
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
  Widget build(BuildContext context) {
    return NativeP1Page(
      session: session,
      onOpenProposal: onOpenProposal,
      onBack: onBack,
      workbenchRefresh: workbenchRefresh,
    );
  }
}
