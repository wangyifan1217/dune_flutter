import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'approval_chat_share.dart';
import 'native_b10_page.dart';
import 'native_xflow_submission_page.dart';
import 'xflow_models.dart';

/// 从 IM 打开审批详情：
/// - PC：居中对话框
/// - APP：全屏推页（盖在当前会话上，返回不重建会话）
Future<void> showApprovalDetailOverlay({
  required BuildContext context,
  required AuthSession session,
  required ApprovalChatShare share,
  VoidCallback? onApprovalCompleted,
  void Function(XflowProposalItem item)? onEditSubmission,
  void Function(int proposalId)? onReeditProposal,
}) {
  Widget hostFor(VoidCallback close) {
    return _ApprovalDetailOverlayHost(
      session: session,
      initialShare: share,
      onClose: close,
      onApprovalCompleted: onApprovalCompleted,
      onEditSubmission: onEditSubmission,
      onReeditProposal: onReeditProposal,
    );
  }

  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        void close() {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).maybePop();
          }
        }
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: size.height * 0.9,
              minWidth: 560,
              minHeight: 480,
            ),
            child: Material(
              color: DunesColors.bgApp,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: hostFor(close),
            ),
          ),
        );
      },
    );
  }

  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => Material(
        color: DunesColors.bgApp,
        child: hostFor(() {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
        }),
      ),
    ),
  );
}

/// 兼容旧名。
Future<void> showApprovalDetailDialog({
  required BuildContext context,
  required AuthSession session,
  required ApprovalChatShare share,
  VoidCallback? onApprovalCompleted,
  void Function(XflowProposalItem item)? onEditSubmission,
  void Function(int proposalId)? onReeditProposal,
}) {
  return showApprovalDetailOverlay(
    context: context,
    session: session,
    share: share,
    onApprovalCompleted: onApprovalCompleted,
    onEditSubmission: onEditSubmission,
    onReeditProposal: onReeditProposal,
  );
}

/// 覆盖层内可切换下一条待审批，不关闭弹窗/路由。
class _ApprovalDetailOverlayHost extends StatefulWidget {
  const _ApprovalDetailOverlayHost({
    required this.session,
    required this.initialShare,
    required this.onClose,
    this.onApprovalCompleted,
    this.onEditSubmission,
    this.onReeditProposal,
  });

  final AuthSession session;
  final ApprovalChatShare initialShare;
  final VoidCallback onClose;
  final VoidCallback? onApprovalCompleted;
  final void Function(XflowProposalItem item)? onEditSubmission;
  final void Function(int proposalId)? onReeditProposal;

  @override
  State<_ApprovalDetailOverlayHost> createState() =>
      _ApprovalDetailOverlayHostState();
}

class _ApprovalDetailOverlayHostState
    extends State<_ApprovalDetailOverlayHost> {
  late XflowProposalItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.initialShare.toListItem();
  }

  void _openPending(XflowProposalItem next) {
    setState(() => _item = next);
  }

  @override
  Widget build(BuildContext context) {
    final isProposal = _item.businessType.toUpperCase() == 'PROPOSAL';
    final dialogNav = _DialogBackNav(onClose: widget.onClose, backScreen: 'IM');
    final key = ValueKey(
      '${_item.businessType}:${_item.todoHint?.businessId ?? _item.id}',
    );

    if (isProposal) {
      return NativeB10Page(
        key: key,
        session: widget.session,
        navigation: dialogNav,
        proposalId: _item.id,
        todoHint: _item.todoHint,
        backScreen: 'IM',
        onApprovalCompleted: () => widget.onApprovalCompleted?.call(),
        onOpenPendingItem: _openPending,
        onReedit: (proposalId) {
          widget.onClose();
          widget.onReeditProposal?.call(proposalId);
        },
      );
    }

    return NativeXflowSubmissionPage(
      key: key,
      session: widget.session,
      navigation: dialogNav,
      businessType: _item.businessType,
      businessId: _item.todoHint?.businessId ?? _item.id,
      todoHint: _item.todoHint,
      backScreen: 'IM',
      onApprovalCompleted: () => widget.onApprovalCompleted?.call(),
      onOpenPendingItem: _openPending,
      onEdit: () {
        widget.onClose();
        widget.onEditSubmission?.call(_item);
      },
    );
  }
}

/// 覆盖层内返回：关闭弹窗/路由，不改动宿主导航栈。
class _DialogBackNav extends DunesNavigationController {
  _DialogBackNav({
    required this.onClose,
    required String backScreen,
  }) : super(initialScreen: backScreen);

  final VoidCallback onClose;

  @override
  void popTo(String screenId) => onClose();

  @override
  void back() => onClose();

  @override
  void go(String screenId) => onClose();
}
