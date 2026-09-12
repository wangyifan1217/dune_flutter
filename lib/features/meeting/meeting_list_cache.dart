import '../../core/widgets/org_folder_bar.dart';
import 'native_meeting_models.dart';

/// 会议纪要列表内存快照：进详情再返回时恢复数据、筛选与滚动位置。
class MeetingListSnapshot {
  const MeetingListSnapshot({
    required this.rows,
    required this.page,
    required this.hasMore,
    this.totalCount = 0,
    this.keyword = '',
    this.folderKind = OrgFolderKind.all,
    this.folderId,
    this.folders = const [],
  });

  final List<NativeMeetingSummary> rows;
  final int page;
  final bool hasMore;
  final int totalCount;
  final String keyword;
  final OrgFolderKind folderKind;
  final int? folderId;
  final List<OrgFolderItem> folders;

  OrgFolderFilter get folderFilter => switch (folderKind) {
    OrgFolderKind.all => const OrgFolderFilter.all(),
    OrgFolderKind.uncategorized => const OrgFolderFilter.uncategorized(),
    OrgFolderKind.folder => OrgFolderFilter.folder(folderId ?? 0),
  };

  bool get hasViewState =>
      rows.isNotEmpty ||
      keyword.trim().isNotEmpty ||
      folderKind != OrgFolderKind.all ||
      folders.isNotEmpty;
}

class MeetingListCache {
  MeetingListCache._();

  static final MeetingListCache instance = MeetingListCache._();

  int? _userId;
  MeetingListSnapshot? _snapshot;
  double _scrollOffset = 0;

  /// 新建/删除等变更后置位；peek 仍返回筛选条件，但行数据需重拉。
  bool _stale = false;

  bool get isStale => _stale;

  MeetingListSnapshot? peek(int userId) {
    if (userId <= 0 || _userId != userId) return null;
    final snap = _snapshot;
    if (snap == null || !snap.hasViewState) return null;
    return MeetingListSnapshot(
      rows: List<NativeMeetingSummary>.unmodifiable(snap.rows),
      page: snap.page,
      hasMore: snap.hasMore,
      totalCount: snap.totalCount,
      keyword: snap.keyword,
      folderKind: snap.folderKind,
      folderId: snap.folderId,
      folders: List<OrgFolderItem>.unmodifiable(snap.folders),
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
    String keyword = '',
    OrgFolderFilter folderFilter = const OrgFolderFilter.all(),
    List<OrgFolderItem> folders = const [],
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
      keyword: keyword.trim(),
      folderKind: folderFilter.kind,
      folderId: folderFilter.folderId,
      folders: List<OrgFolderItem>.unmodifiable(folders),
    );
  }

  /// 列表成员可能变化（新建/删除）：下次进入按原筛选重新拉取。
  void invalidate() {
    _stale = true;
    _scrollOffset = 0;
    final snap = _snapshot;
    if (snap == null) return;
    _snapshot = MeetingListSnapshot(
      rows: const [],
      page: 0,
      hasMore: true,
      totalCount: 0,
      keyword: snap.keyword,
      folderKind: snap.folderKind,
      folderId: snap.folderId,
      folders: snap.folders,
    );
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
    _stale = false;
    _snapshot = MeetingListSnapshot(
      rows: List<NativeMeetingSummary>.unmodifiable(next),
      page: snap.page,
      hasMore: snap.hasMore,
      totalCount: snap.totalCount > 0 ? snap.totalCount - 1 : next.length,
      keyword: snap.keyword,
      folderKind: snap.folderKind,
      folderId: snap.folderId,
      folders: snap.folders,
    );
  }

  void clear() {
    _userId = null;
    _snapshot = null;
    _scrollOffset = 0;
    _stale = false;
  }
}
