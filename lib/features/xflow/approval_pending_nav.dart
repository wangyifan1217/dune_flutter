import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'xflow_form_styles.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

/// 当前用户 OPEN 待审批队列（轻量，不含历史已办）。
class MyOpenApprovalQueue {
  const MyOpenApprovalQueue({required this.items});

  final List<XflowProposalItem> items;

  int get total => items.length;

  bool _sameBusiness(XflowProposalItem item, String businessType, int businessId) {
    final bt = businessType.toUpperCase();
    final bid = item.todoHint?.businessId ?? item.id;
    return item.businessType.toUpperCase() == bt && bid == businessId;
  }

  /// 列表中「当前单」的下一条；已是最后一条则返回 null（不循环）。
  XflowProposalItem? nextAfter({
    required String businessType,
    required int businessId,
  }) {
    if (items.length <= 1) return null;
    final idx = items.indexWhere(
      (e) => _sameBusiness(e, businessType, businessId),
    );
    if (idx < 0) return items.first;
    if (idx + 1 >= items.length) return null;
    return items[idx + 1];
  }

  /// 审批完成后当前单已离开 OPEN；取队列第一条作为下一条。
  XflowProposalItem? get firstOrNull => items.isEmpty ? null : items.first;
}

Future<MyOpenApprovalQueue> loadMyOpenApprovalQueue(XflowService service) async {
  final items = await service.fetchMyOpenApprovalInbox();
  return MyOpenApprovalQueue(items: items);
}

/// 详情页底部：「下一个未审批（N）」
class XfDetNextPendingBar extends StatelessWidget {
  const XfDetNextPendingBar({
    super.key,
    required this.totalCount,
    required this.onPressed,
    this.loading = false,
  });

  final int totalCount;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final label = totalCount > 0 ? '下一个($totalCount)' : '下一个';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Material(
          color: Colors.transparent,
          child: XflowApprovalSubmitButton(
            onPressed: onPressed,
            loading: loading,
            enabled: onPressed != null && !loading,
            label: label,
            icon: Icons.arrow_forward_rounded,
          ),
        ),
      ),
    );
  }
}

/// 底部条上方的浅分隔（与页面背景衔接）。
class XfDetNextPendingFooter extends StatelessWidget {
  const XfDetNextPendingFooter({
    super.key,
    required this.totalCount,
    required this.onPressed,
    this.loading = false,
  });

  final int totalCount;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(
          top: BorderSide(color: DunesColors.borderSoft.withValues(alpha: 0.9)),
        ),
      ),
      child: XfDetNextPendingBar(
        totalCount: totalCount,
        onPressed: onPressed,
        loading: loading,
      ),
    );
  }
}
