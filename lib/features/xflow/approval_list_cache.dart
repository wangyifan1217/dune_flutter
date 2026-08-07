import 'xflow_models.dart';

/// 我的审批相关列表（B1/B14/P1/B13）快照：进详情再返回时恢复数据与滚动位置。
class ApprovalListSnapshot {
  const ApprovalListSnapshot({
    required this.rows,
    required this.statusFilter,
    required this.searchQuery,
  });

  final List<XflowProposalItem> rows;
  final String statusFilter;
  final String searchQuery;
}

class ApprovalListCache {
  ApprovalListCache._();

  static final ApprovalListCache instance = ApprovalListCache._();

  final Map<String, ApprovalListSnapshot> _snapshots = {};
  final Map<String, double> _scrollOffsets = {};

  static String _key(int userId, String listType) => '$userId|$listType';

  ApprovalListSnapshot? peek({
    required int userId,
    required String listType,
  }) {
    if (userId <= 0 || listType.isEmpty) return null;
    final snap = _snapshots[_key(userId, listType)];
    if (snap == null || snap.rows.isEmpty) return null;
    return ApprovalListSnapshot(
      rows: List<XflowProposalItem>.unmodifiable(snap.rows),
      statusFilter: snap.statusFilter,
      searchQuery: snap.searchQuery,
    );
  }

  double peekScrollOffset({
    required int userId,
    required String listType,
  }) {
    if (userId <= 0 || listType.isEmpty) return 0;
    return _scrollOffsets[_key(userId, listType)] ?? 0;
  }

  void saveScrollOffset({
    required int userId,
    required String listType,
    required double offset,
  }) {
    if (userId <= 0 || listType.isEmpty) return;
    _scrollOffsets[_key(userId, listType)] = offset < 0 ? 0 : offset;
  }

  void put({
    required int userId,
    required String listType,
    required List<XflowProposalItem> rows,
    required String statusFilter,
    required String searchQuery,
  }) {
    if (userId <= 0 || listType.isEmpty) return;
    _snapshots[_key(userId, listType)] = ApprovalListSnapshot(
      rows: List<XflowProposalItem>.unmodifiable(rows),
      statusFilter: statusFilter,
      searchQuery: searchQuery,
    );
  }

  void invalidate({
    required int userId,
    required String listType,
  }) {
    if (userId <= 0 || listType.isEmpty) return;
    final key = _key(userId, listType);
    _snapshots.remove(key);
    _scrollOffsets.remove(key);
  }
}
