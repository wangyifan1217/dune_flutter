import 'package:flutter/widgets.dart';

import '../auth/auth_session.dart';

/// 审批表单打开资金提案。由资金提案页在加载时接上，避免表单和提案页互相引用。
typedef FundingProposalOpener =
    Future<void> Function({
      required BuildContext context,
      required AuthSession session,
      required int proposalId,
    });

FundingProposalOpener? openFundingProposalFromApproval;
