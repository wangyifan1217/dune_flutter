import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/org_folder_bar.dart';
import '../auth/auth_session.dart';
import 'meeting_list_cache.dart';
import 'meeting_upload_coordinator.dart';
import 'meeting_upload_storage.dart';
import 'native_meeting_models.dart';
import 'native_meeting_service.dart';

class NativeMeetingListPage extends StatefulWidget {
  const NativeMeetingListPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenDetail,
    this.onCreate,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onCreate;
  final ValueChanged<int> onOpenDetail;

  @override
  State<NativeMeetingListPage> createState() => _NativeMeetingListPageState();
}

class _NativeMeetingListPageState extends State<NativeMeetingListPage> {
  late final NativeMeetingService _service = NativeMeetingService(
    session: widget.session,
  );
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _search = TextEditingController();
  List<NativeMeetingSummary> _rows = const [];
  bool _loading = true;
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _totalCount = 0;
  static const int _pageSize = 20;
  String? _error;
  List<OrgFolderItem> _folders = const [];
  OrgFolderFilter _folderFilter = const OrgFolderFilter.all();
  bool _selecting = false;
  final Set<int> _selectedMeetingIds = <int>{};
  Timer? _scrollRestoreRetry;
  Timer? _searchDebounce;

  /// 新建等已 invalidate 时，dispose 勿再 put 旧快照把缓存「复活」。
  bool _suppressPersistOnDispose = false;

  @override
  void initState() {
    super.initState();
    MeetingUploadCoordinator.instance.attach(widget.session);
    MeetingUploadCoordinator.instance.addListener(_onUploadUpdate);
    unawaited(MeetingUploadCoordinator.instance.resumePending());
    _scrollController.addListener(_onScroll);
    final cached = MeetingListCache.instance.peek(widget.session.userId);
    if (cached != null) {
      _folderFilter = cached.folderFilter;
      _folders = cached.folders;
      if (cached.keyword.isNotEmpty) {
        _search.text = cached.keyword;
      }
      if (!MeetingListCache.instance.isStale && cached.rows.isNotEmpty) {
        _rows = cached.rows;
        _page = cached.page;
        _hasMore = cached.hasMore;
        _totalCount = cached.totalCount > 0
            ? cached.totalCount
            : cached.rows.length;
        _loading = false;
        _scheduleScrollRestore();
        _scheduleLoadMoreIfShort();
        unawaited(_refreshFolders());
      } else {
        unawaited(_load(reset: true));
      }
    } else {
      unawaited(_load(reset: true));
    }
  }

  @override
  void dispose() {
    if (!_suppressPersistOnDispose) {
      _persistScrollNow();
      _persistListSnapshot();
    }
    _scrollRestoreRetry?.cancel();
    _searchDebounce?.cancel();
    MeetingUploadCoordinator.instance.removeListener(_onUploadUpdate);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onUploadUpdate() {
    if (mounted) setState(() {});
  }

  void _persistScrollNow() {
    if (!_scrollController.hasClients) return;
    MeetingListCache.instance.saveScrollOffset(
      userId: widget.session.userId,
      offset: _scrollController.offset,
    );
  }

  void _persistListSnapshot() {
    MeetingListCache.instance.put(
      userId: widget.session.userId,
      rows: _rows,
      page: _page,
      hasMore: _hasMore,
      totalCount: _totalCount,
      keyword: _search.text,
      folderFilter: _folderFilter,
      folders: _folders,
    );
  }

  void _scheduleScrollRestore() {
    _scrollRestoreRetry?.cancel();
    void attempt() {
      if (!mounted) return;
      _applySavedScroll();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
    // 覆盖「返回后布局完成」竞态，连续多帧回写偏移。
    _scrollRestoreRetry = Timer.periodic(const Duration(milliseconds: 48), (t) {
      if (!mounted || t.tick > 12) {
        t.cancel();
        return;
      }
      attempt();
    });
  }

  void _applySavedScroll() {
    if (!mounted) return;
    final target = MeetingListCache.instance.peekScrollOffset(
      widget.session.userId,
    );
    if (target <= 0 || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final next = target.clamp(0.0, max);
    if ((_scrollController.offset - next).abs() < 0.5) return;
    _scrollController.jumpTo(next);
  }

  void _openDetail(int meetingId) {
    _persistScrollNow();
    _persistListSnapshot();
    widget.onOpenDetail(meetingId);
  }

  void _onCreatePressed() {
    // 新建后列表应重新拉取；suppress 防止 dispose 把旧快照写回。
    _suppressPersistOnDispose = true;
    MeetingListCache.instance.invalidate();
    widget.onCreate?.call();
  }

  void _onScroll() {
    _persistScrollNow();
    if (!_scrollController.hasClients ||
        _loading ||
        _searching ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMore());
    }
  }

  void _scheduleLoadMoreIfShort({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasMore || _loadingMore || _loading || _searching) {
        return;
      }
      if (!_scrollController.hasClients) {
        if (attempt < 8) _scheduleLoadMoreIfShort(attempt: attempt + 1);
        return;
      }
      if (_scrollController.position.maxScrollExtent <= 80) {
        unawaited(_loadMore());
      }
    });
  }

  Future<void> _refreshFolders({bool updateState = true}) async {
    try {
      final folders = await _service.listFolders();
      if (!mounted) return;
      if (updateState) {
        setState(() => _folders = folders);
      } else {
        _folders = folders;
      }
    } catch (_) {}
  }

  void _onKeywordChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) unawaited(_load(reset: true, silent: true));
    });
  }

  Future<void> _load({required bool reset, bool silent = false}) async {
    final keyword = _search.text.trim();
    if (reset) {
      setState(() {
        if (!silent && _rows.isEmpty) {
          _loading = true;
        } else {
          _searching = true;
        }
        _error = null;
      });
    }
    try {
      final result = await _service.fetchListPage(
        page: 0,
        size: _pageSize,
        keyword: keyword,
        folderId: _folderFilter.queryValue,
      );
      await _refreshFolders(updateState: false);
      if (!mounted) return;
      if (keyword != _search.text.trim()) return;
      final rows = result.items;
      setState(() {
        _rows = rows;
        _page = 0;
        _totalCount = result.totalCount < rows.length
            ? rows.length
            : result.totalCount;
        _hasMore = _rows.length < _totalCount;
      });
      _persistListSnapshot();
      _scheduleLoadMoreIfShort();
    } catch (e) {
      if (!mounted) return;
      if (keyword != _search.text.trim()) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && keyword == _search.text.trim()) {
        setState(() {
          _loading = false;
          _searching = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _searching || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _service.fetchListPage(
        page: nextPage,
        size: _pageSize,
        keyword: _search.text.trim(),
        folderId: _folderFilter.queryValue,
      );
      if (!mounted) return;
      final existing = _rows.map((e) => e.meetingId).toSet();
      final appended = result.items
          .where((e) => !existing.contains(e.meetingId))
          .toList(growable: false);
      setState(() {
        _rows = <NativeMeetingSummary>[..._rows, ...appended];
        _page = nextPage;
        if (result.totalCount > _totalCount) {
          _totalCount = result.totalCount;
        } else if (_totalCount < _rows.length) {
          _totalCount = _rows.length;
        }
        _hasMore = appended.isNotEmpty &&
            result.items.length >= _pageSize &&
            _rows.length < _totalCount;
      });
      _persistListSnapshot();
      _scheduleLoadMoreIfShort();
    } catch (_) {
      // Keep silent on auto load more to avoid frequent interruptions.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteMeeting(NativeMeetingSummary row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会议纪要'),
        content: Text(
          '确定删除「${row.title.isEmpty ? '未命名会议' : row.title}」吗？此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DunesColors.coral),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteMeeting(row.meetingId);
      if (!mounted) return;
      setState(
        () => _rows = _rows.where((e) => e.meetingId != row.meetingId).toList(),
      );
      _persistListSnapshot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '删除失败，请稍后重试'))),
      );
    }
  }

  Future<void> _createFolder() async {
    final name = await showOrgFolderNameDialog(context, title: '新建文件夹');
    if (name == null) return;
    try {
      final folder = await _service.createFolder(name);
      if (!mounted) return;
      setState(() => _folders = [..._folders, folder]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '创建文件夹失败'))),
      );
    }
  }

  Future<void> _renameFolder(OrgFolderItem folder) async {
    final name = await showOrgFolderNameDialog(
      context,
      title: '重命名文件夹',
      initial: folder.name,
    );
    if (name == null) return;
    try {
      final updated = await _service.renameFolder(folder.id, name);
      if (!mounted) return;
      setState(() {
        _folders = _folders
            .map((e) => e.id == folder.id ? updated : e)
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '重命名失败'))),
      );
    }
  }

  Future<void> _deleteFolder(OrgFolderItem folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('删除「${folder.name}」后，里面的会议会回到未分类，会议本身不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteFolder(folder.id);
      if (!mounted) return;
      setState(() {
        _folders = _folders.where((e) => e.id != folder.id).toList();
        if (_folderFilter.folderId == folder.id) {
          _folderFilter = const OrgFolderFilter.uncategorized();
        }
      });
      await _load(reset: true, silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '删除文件夹失败'))),
      );
    }
  }

  Future<void> _moveSelectedMeetings() async {
    final picked = await showOrgFolderPickDialog(context, folders: _folders);
    if (picked == null) return;
    try {
      await _service.moveMeetings(
        meetingIds: _selectedMeetingIds.toList(),
        folderId: picked.id > 0 ? picked.id : null,
      );
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _selectedMeetingIds.clear();
      });
      await _load(reset: true, silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '移动失败'))),
      );
    }
  }

  List<int> get _selectableMeetingIds => _visibleRows
      .where((e) => e.meetingId > 0)
      .map((e) => e.meetingId)
      .toList(growable: false);

  Future<void> _toggleSelectAllMeetings() async {
    final current = _selectableMeetingIds;
    final allSelected =
        current.isNotEmpty && current.every(_selectedMeetingIds.contains);
    if (allSelected) {
      setState(() => _selectedMeetingIds.clear());
      return;
    }
    var guard = 0;
    while (mounted && _hasMore && !_loadingMore && guard < 20) {
      guard++;
      await _loadMore();
    }
    if (!mounted) return;
    setState(() {
      _selecting = true;
      _selectedMeetingIds
        ..clear()
        ..addAll(_selectableMeetingIds);
    });
  }

  void _toggleMeetingSelected(int meetingId) {
    if (meetingId <= 0) return;
    setState(() {
      if (_selectedMeetingIds.contains(meetingId)) {
        _selectedMeetingIds.remove(meetingId);
      } else {
        _selectedMeetingIds.add(meetingId);
      }
      if (_selectedMeetingIds.isEmpty) _selecting = false;
    });
  }

  String _statusLabel(String status) {
    return switch (status.toUpperCase()) {
      'GENERATED' => '已生成',
      'TRANSCRIBING' => '转写中',
      'GENERATING' => '生成中',
      'FAILED' => '失败',
      'DRAFT' => '草稿',
      _ => status.isEmpty ? '未知' : status,
    };
  }

  List<NativeMeetingSummary> get _visibleRows {
    return _rows;
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _search,
      onChanged: _onKeywordChanged,
      decoration: InputDecoration(
        hintText: '搜索会议标题、摘要、组织人…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _search.clear();
                  _onKeywordChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DunesColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DunesColors.borderSoft),
        ),
      ),
    );
  }

  String _uploadStatusLabel(MeetingUploadJob job) {
    return switch (job.phase) {
      MeetingUploadPhase.pending =>
        job.error != null && job.error!.isNotEmpty ? '上传重试中' : '准备上传中',
      MeetingUploadPhase.uploading => job.uploadProgressPercent <= 0
          ? '正在准备上传'
          : '录音上传中 ${job.uploadProgressPercent}%',
      MeetingUploadPhase.attaching => '正在保存',
      MeetingUploadPhase.failed => '上传失败',
      MeetingUploadPhase.done => '草稿',
    };
  }

  Color _uploadStatusColor(MeetingUploadJob job) {
    return switch (job.phase) {
      MeetingUploadPhase.failed => DunesColors.coral,
      MeetingUploadPhase.attaching => DunesColors.amber,
      _ => DunesColors.brandPurple,
    };
  }

  Color _statusColor(String status) {
    return switch (status.toUpperCase()) {
      'GENERATED' => DunesColors.green,
      'TRANSCRIBING' || 'GENERATING' => DunesColors.amber,
      'FAILED' => DunesColors.coral,
      _ => DunesColors.text3,
    };
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.onCreate != null;
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('会议纪要'),
        actions: [
          if (_visibleRows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: OrgFolderMultiSelectButton(
                selecting: _selecting,
                onPressed: () {
                  setState(() {
                    if (_selecting) {
                      _selecting = false;
                      _selectedMeetingIds.clear();
                    } else {
                      _selecting = true;
                    }
                  });
                },
              ),
            ),
          if (canCreate)
            IconButton(
              onPressed: _onCreatePressed,
              icon: const Icon(Icons.add_rounded),
              tooltip: isDesktopCommOnly ? '上传会议纪要' : '新建会议',
            ),
        ],
      ),
      floatingActionButton: canCreate && !_selecting
          ? FloatingActionButton.large(
              onPressed: _onCreatePressed,
              backgroundColor: DunesColors.brandPurple,
              foregroundColor: Colors.white,
              child: Icon(
                isDesktopCommOnly
                    ? Icons.upload_file_rounded
                    : Icons.mic_rounded,
              ),
            )
          : null,
      bottomNavigationBar: _selecting
          ? OrgFolderSelectBar(
              count: _selectedMeetingIds.length,
              total: _selectableMeetingIds.length,
              onCancel: () => setState(() {
                _selecting = false;
                _selectedMeetingIds.clear();
              }),
              onMove: () => unawaited(_moveSelectedMeetings()),
              onToggleSelectAll: () => unawaited(_toggleSelectAllMeetings()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true, silent: true),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: isDesktopCommOnly,
          child: _buildBody(canCreate: canCreate),
        ),
      ),
    );
  }

  Widget _buildBody({required bool canCreate}) {
    final searching = _search.text.trim().isNotEmpty;
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, isDesktopCommOnly ? 148 : 100),
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSearchField(),
        const SizedBox(height: 10),
        OrgFolderBar(
          folders: _folders,
          selected: _folderFilter,
          onSelected: (filter) {
            if (_folderFilter.cacheKey == filter.cacheKey) return;
            setState(() {
              _folderFilter = filter;
              _selecting = false;
              _selectedMeetingIds.clear();
              _rows = const [];
              _loading = true;
            });
            unawaited(_load(reset: true));
          },
          onCreate: () => unawaited(_createFolder()),
          onRename: (folder) => unawaited(_renameFolder(folder)),
          onDelete: (folder) => unawaited(_deleteFolder(folder)),
        ),
        const SizedBox(height: 14),
        if (_loading && _rows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _rows.isEmpty)
          _buildMessageCard(
            icon: Icons.error_outline,
            title: '加载失败',
            message: _error!,
            actionLabel: '重试',
            onAction: () => _load(reset: true),
          )
        else if (_rows.isEmpty)
          _buildMessageCard(
            icon: searching ? Icons.search_off_rounded : Icons.history_rounded,
            title: searching ? '未找到匹配会议' : '暂无会议记录',
            message: searching
                ? '换一个关键词试试，支持搜索会议标题和摘要。'
                : (canCreate
                      ? (isDesktopCommOnly
                            ? '点击下方按钮，上传录音并开始 AI 转写'
                            : '点击下方麦克风按钮，上传录音并开始 AI 转写')
                      : '暂无会议纪要，请在手机端录制或上传后查看'),
            actionLabel: !searching && canCreate ? '新建会议' : null,
            onAction: !searching && canCreate ? _onCreatePressed : null,
          )
        else ...[
          Text(
            searching
                ? '搜索结果 · ${_visibleRows.length}${_totalCount > _visibleRows.length ? ' / $_totalCount' : ''} 场'
                : '我的会议 · ${_totalCount > _visibleRows.length ? _totalCount : _visibleRows.length} 场',
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 10),
          ..._visibleRows.map(_buildMeetingCard),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  isDesktopCommOnly ? '滚动加载更多' : '下滑加载更多',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ),
          if (!_hasMore && _rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  '没有更多会议记录了',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF7B5CD8), Color(0xFF6A4FA0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 会议纪要',
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '录音转写 · 智能摘要 · 待办提取',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: DunesColors.brandPurple),
          const SizedBox(height: 12),
          Text(
            title,
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.text2,
              height: 1.5,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.brandPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeetingCard(NativeMeetingSummary row) {
    final uploadJob = MeetingUploadCoordinator.instance.jobForMeeting(
      row.meetingId,
    );
    final status = uploadJob != null
        ? _uploadStatusLabel(uploadJob)
        : _statusLabel(row.status);
    final statusColor = uploadJob != null
        ? _uploadStatusColor(uploadJob)
        : _statusColor(row.status);
    final enabled = row.meetingId > 0;
    final showUploadProgressBar =
        uploadJob != null &&
        uploadJob.phase == MeetingUploadPhase.uploading &&
        uploadJob.uploadProgressPercent < 100;
    final deletingDisabled =
        uploadJob != null &&
        (uploadJob.phase == MeetingUploadPhase.pending ||
            uploadJob.phase == MeetingUploadPhase.uploading ||
            uploadJob.phase == MeetingUploadPhase.attaching);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () {
                  if (_selecting || desktopMultiSelectModifierHeld()) {
                    if (!_selecting) {
                      setState(() => _selecting = true);
                    }
                    _toggleMeetingSelected(row.meetingId);
                    return;
                  }
                  _openDetail(row.meetingId);
                }
              : null,
          onSecondaryTap: enabled
              ? () => setState(() {
                  _selecting = true;
                  _selectedMeetingIds.add(row.meetingId);
                })
              : null,
          onLongPress: enabled
              ? () => setState(() {
                  _selecting = true;
                  _selectedMeetingIds.add(row.meetingId);
                })
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Row(
              children: [
                if (_selecting) ...[
                  Icon(
                    _selectedMeetingIds.contains(row.meetingId)
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _selectedMeetingIds.contains(row.meetingId)
                        ? DunesColors.brandPurple
                        : DunesColors.text3,
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: DunesColors.brandPurpleSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: DunesColors.brandPurple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title.isEmpty ? '未命名会议' : row.title,
                        maxLines: isDesktopCommOnly ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.displayTime,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OrgFolderBadge(
                          label: orgFolderDisplayName(row.folderId, _folders),
                        ),
                      ),
                      if (showUploadProgressBar) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: uploadJob.uploadProgressPercent / 100,
                            minHeight: 4,
                            backgroundColor: DunesColors.borderSoft,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              DunesColors.brandPurple,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        style: DunesTypography.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (uploadJob == null && row.asrProgress > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${row.asrProgress}%',
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: enabled && !deletingDisabled
                      ? () => _deleteMeeting(row)
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: deletingDisabled
                      ? DunesColors.border
                      : DunesColors.text3,
                  tooltip: deletingDisabled ? '上传处理中，暂不可删除' : '删除',
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: enabled ? DunesColors.text3 : DunesColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
