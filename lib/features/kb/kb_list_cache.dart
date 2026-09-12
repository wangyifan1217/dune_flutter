import '../../core/widgets/org_folder_bar.dart';
import 'native_kb_models.dart';

/// 知识库列表内存快照：进文档/会话再返回时恢复筛选与列表。
class KbListSnapshot {
  const KbListSnapshot({
    required this.docs,
    required this.page,
    required this.hasMore,
    this.total = 0,
    this.keyword = '',
    this.folderKind = OrgFolderKind.all,
    this.folderId,
    this.folders = const [],
    this.summary,
  });

  final List<NativeKbDocument> docs;
  final int page;
  final bool hasMore;
  final int total;
  final String keyword;
  final OrgFolderKind folderKind;
  final int? folderId;
  final List<OrgFolderItem> folders;
  final NativeKbSummary? summary;

  OrgFolderFilter get folderFilter => switch (folderKind) {
    OrgFolderKind.all => const OrgFolderFilter.all(),
    OrgFolderKind.uncategorized => const OrgFolderFilter.uncategorized(),
    OrgFolderKind.folder => OrgFolderFilter.folder(folderId ?? 0),
  };

  bool get hasViewState =>
      docs.isNotEmpty ||
      keyword.trim().isNotEmpty ||
      folderKind != OrgFolderKind.all ||
      folders.isNotEmpty ||
      summary != null;
}

class KbListCache {
  KbListCache._();

  static final KbListCache instance = KbListCache._();

  int? _userId;
  KbListSnapshot? _snapshot;
  double _scrollOffset = 0;

  KbListSnapshot? peek(int userId) {
    if (userId <= 0 || _userId != userId) return null;
    final snap = _snapshot;
    if (snap == null || !snap.hasViewState) return null;
    return KbListSnapshot(
      docs: List<NativeKbDocument>.unmodifiable(snap.docs),
      page: snap.page,
      hasMore: snap.hasMore,
      total: snap.total,
      keyword: snap.keyword,
      folderKind: snap.folderKind,
      folderId: snap.folderId,
      folders: List<OrgFolderItem>.unmodifiable(snap.folders),
      summary: snap.summary,
    );
  }

  double peekScrollOffset(int userId) {
    if (userId <= 0 || _userId != userId) return 0;
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
    required List<NativeKbDocument> docs,
    required int page,
    required bool hasMore,
    int total = 0,
    String keyword = '',
    OrgFolderFilter folderFilter = const OrgFolderFilter.all(),
    List<OrgFolderItem> folders = const [],
    NativeKbSummary? summary,
  }) {
    if (userId <= 0) return;
    if (_userId != null && _userId != userId) {
      _scrollOffset = 0;
    }
    _userId = userId;
    _snapshot = KbListSnapshot(
      docs: List<NativeKbDocument>.unmodifiable(docs),
      page: page,
      hasMore: hasMore,
      total: total,
      keyword: keyword.trim(),
      folderKind: folderFilter.kind,
      folderId: folderFilter.folderId,
      folders: List<OrgFolderItem>.unmodifiable(folders),
      summary: summary,
    );
  }

  void clear() {
    _userId = null;
    _snapshot = null;
    _scrollOffset = 0;
  }
}
