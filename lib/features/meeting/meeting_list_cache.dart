import 'native_meeting_models.dart';

/// 会议纪要列表内存快照：进详情再返回时恢复数据与滚动位置。
class MeetingListSnapshot {
  const MeetingListSnapshot({
    required this.rows,
    required this.page,
    required this.hasMore,
    this.totalCount = 0,
  });

  final List<NativeMeetingSummary> rows;
  final int page;
  final bool hasMore;
  final int totalCount;
}

class MeetingListCache {
  MeetingListCache._();

  static final MeetingListCache instance = MeetingListCache._();

  int? _userId;
  MeetingListSnapshot? _snapshot;
  double _scrollOffset = 0;
  /// 新建/删除等变更后置位；peek 返回 null 直到下一次成功 put。
  bool _stale = false;

  MeetingListSnapshot? peek(int userId) {
    if (userId <= 0 || _userId != userId || _stale) return null;
    final snap = _snapshot;
    if (snap == null || snap.rows.isEmpty) return null;
    return MeetingListSnapshot(
      rows: List<NativeMeetingSummary>.unmodifiable(snap.rows),
      page: snap.page,
      hasMore: snap.hasMore,
      totalCount: snap.totalCount,
    );
  }

  double peekScrollOffset(int userId) {
    if (userId <= 0 || _userId != userId || _stale) return 0;
    return _scrollOffset;
  }

  void saveScrollOffset({required int userId, required double offset}) {
    if (userId <= 0) return;
    if (_userId != null && _userId != userId) return;
    _userId ??= userId;
    _scrollOffset = offset < 0 ? 0 : offset;
  }

  void put({
    required int userId,
    required List<NativeMeetingSummary> rows,
    required int page,
    required bool hasMore,
    int totalCount = 0,
  }) {
    if (userId <= 0) return;
    if (_userId != null && _userId != userId) {
      _scrollOffset = 0;
    }
    _userId = userId;
    _stale = false;
    _snapshot = MeetingListSnapshot(
      rows: List<NativeMeetingSummary>.unmodifiable(rows),
      page: page,
      hasMore: hasMore,
      totalCount: totalCount,
    );
  }

  /// 列表成员可能变化（新建/删除）：下次进入强制重新拉取。
  void invalidate() {
    _stale = true;
    _snapshot = null;
    _scrollOffset = 0;
  }

  /// 详情删除后从快照去掉该行；若快照空则视为失效。
  void removeMeeting(int meetingId) {
    if (meetingId <= 0) return;
    final snap = _snapshot;
    if (snap == null) {
      invalidate();
      return;
    }
    final next = snap.rows.where((e) => e.meetingId != meetingId).toList();
    if (next.length == snap.rows.length) return;
    if (next.isEmpty) {
      invalidate();
      return;
    }
    _stale = false;
    _snapshot = MeetingListSnapshot(
      rows: List<NativeMeetingSummary>.unmodifiable(next),
      page: snap.page,
      hasMore: snap.hasMore,
      totalCount: snap.totalCount > 0 ? snap.totalCount - 1 : next.length,
    );
  }

  void clear() {
    _userId = null;
    _snapshot = null;
    _scrollOffset = 0;
    _stale = false;
  }
}
