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

  bool _sameBusiness(
    XflowProposalItem item,
    String businessType,
    int businessId,
  ) {
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

/// 本会话里点过「下一个」略过的待审批。按略过先后排到队列末尾，
/// 避免批完下一条后又跳回优先级最前、还得再点一次略过。
class ApprovalSkipTail {
  ApprovalSkipTail._();

  static final List<String> _keys = <String>[];

  static String keyOf(String businessType, int businessId) =>
      '${businessType.trim().toUpperCase()}:$businessId';

  static String itemKey(XflowProposalItem item) {
    final businessId = item.todoHint?.businessId ?? item.id;
    return keyOf(item.businessType, businessId);
  }

  static void reset() => _keys.clear();

  static XflowProposalItem? pick({
    required List<XflowProposalItem> items,
    required String businessType,
    required int businessId,
    required bool afterDecision,
  }) {
    final key = _resolvedKey(items, businessType, businessId);
    if (afterDecision) {
      _keys.remove(key);
    }
    final ordered = orderOpenApprovalsBySkip(items, _keys);
    final next = afterDecision
        ? _firstExcept(ordered, key)
        : MyOpenApprovalQueue(items: ordered).nextAfter(
            businessType: businessType,
            businessId: businessId,
          );
    if (!afterDecision && next != null) {
      _keys.remove(key);
      _keys.add(key);
    }
    final live = items.map(itemKey).toSet();
    _keys.removeWhere((item) => !live.contains(item));
    return next;
  }

  static XflowProposalItem? _firstExcept(
    List<XflowProposalItem> items,
    String key,
  ) {
    for (final item in items) {
      if (itemKey(item) != key) return item;
    }
    return null;
  }

  static String _resolvedKey(
    List<XflowProposalItem> items,
    String businessType,
    int businessId,
  ) {
    final bt = businessType.trim().toUpperCase();
    for (final item in items) {
      final bid = item.todoHint?.businessId ?? item.id;
      if (item.businessType.toUpperCase() == bt && bid == businessId) {
        return itemKey(item);
      }
    }
    return keyOf(businessType, businessId);
  }
}

/// 未略过的保持原顺序；略过的按 [deferredKeys] 的先后接到末尾。
List<XflowProposalItem> orderOpenApprovalsBySkip(
  List<XflowProposalItem> items,
  List<String> deferredKeys,
) {
  if (deferredKeys.isEmpty || items.length < 2) return items;
  final rank = <String, int>{
    for (var i = 0; i < deferredKeys.length; i++) deferredKeys[i]: i,
  };
  final head = <XflowProposalItem>[];
  final tail = <XflowProposalItem>[];
  for (final item in items) {
    if (rank.containsKey(ApprovalSkipTail.itemKey(item))) {
      tail.add(item);
    } else {
      head.add(item);
    }
  }
  if (tail.length > 1) {
    tail.sort(
      (a, b) => rank[ApprovalSkipTail.itemKey(a)]!.compareTo(
        rank[ApprovalSkipTail.itemKey(b)]!,
      ),
    );
  }
  return [...head, ...tail];
}

Future<MyOpenApprovalQueue> loadMyOpenApprovalQueue(
  XflowService service,
) async {
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
    const label = '下一个';
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
        color: DunesColors.resolve(
          context,
          DunesColors.bgApp,
          role: DunesColorRole.surface,
        ),
        border: Border(
          top: BorderSide(
            color: DunesColors.resolve(
              context,
              DunesColors.borderSoft,
              role: DunesColorRole.border,
            ).withValues(alpha: 0.9),
          ),
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
