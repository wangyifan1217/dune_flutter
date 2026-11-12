import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'native_funding_proposal_page.dart';

/// 从聊天名片或业务审批打开资金提案。电脑上用和销售提案一样的窗口，手机上整页打开。
Future<void> showFundingProposalOverlay({
  required BuildContext context,
  required AuthSession session,
  required int proposalId,
}) {
  Widget page() => NativeFundingProposalPage(
    session: session,
    openId: proposalId,
    linkedFromApproval: true,
  );

  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 36,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: size.height * 0.9,
              minWidth: 560,
              minHeight: 480,
            ),
            child: Material(
              color: DunesColors.resolve(
                ctx,
                DunesColors.bgApp,
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: page(),
            ),
          ),
        );
      },
    );
  }

  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => page()),
  );
}
