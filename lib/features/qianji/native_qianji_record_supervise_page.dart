import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import '../tasks/task_api.dart';
import '../tasks/task_avatar.dart';
import '../tasks/task_models.dart';
import 'qianji_record_supervise_service.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 千机业务查阅：关键词 + 部门筛选，数据走后端监管接口。
class NativeQianjiRecordSupervisePage extends StatefulWidget {
  const NativeQianjiRecordSupervisePage({
    super.key,
    required this.session,
    required this.kind,
    required this.onBack,
  });

  final AuthSession session;
  final QianjiRecordSuperviseKind kind;
  final VoidCallback onBack;

  @override
  State<NativeQianjiRecordSupervisePage> createState() =>
      _NativeQianjiRecordSupervisePageState();
}

class _NativeQianjiRecordSupervisePageState
    extends State<NativeQianjiRecordSupervisePage> {
  late final QianjiRecordSuperviseService _service =
      QianjiRecordSuperviseService(session: widget.session, kind: widget.kind);
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<QianjiRecordSuperviseHit> _rows = const [];
  Map<int, TaskAssignee> _avatarsById = const {};
  Map<String, TaskAssignee> _avatarsByName = const {};
  List<QianjiRecordDeptStat> _deptStats = const [];
  int? _selectedDepartmentId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _superviseAll = false;
  int _page = 0;
  int _total = 0;
  int _listTotal = 0;
  static const int _pageSize = 20;
  String? _error;
  Timer? _keywordDebounce;

  bool get _canView => switch (widget.kind) {
    QianjiRecordSuperviseKind.task => widget.session.taskLookupAccess,
    QianjiRecordSuperviseKind.dailyReport =>
      widget.session.dailyReportLookupAccess,
    QianjiRecordSuperviseKind.groupReply =>
      widget.session.groupReplyLookupAccess,
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _keywordCtrl.addListener(_onKeywordChanged);
    if (!_canView) {
      _loading = false;
      _error = '没有查看权限';
      return;
    }
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _scrollController.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    QianjiRecordSuperviseKind.task => '任务',
    QianjiRecordSuperviseKind.dailyReport => '日报',
    QianjiRecordSuperviseKind.groupReply => '群响应',
  };

  String get _hint => switch (widget.kind) {
    QianjiRecordSuperviseKind.task => '搜索人名、任务名称',
    QianjiRecordSuperviseKind.dailyReport => '搜索人名、日报内容',
    QianjiRecordSuperviseKind.groupReply => '搜索人名、群名称',
  };

  String get _empty => switch (widget.kind) {
    QianjiRecordSuperviseKind.task => '暂无任务',
    QianjiRecordSuperviseKind.dailyReport => '暂无日报',
    QianjiRecordSuperviseKind.groupReply => '暂无群响应',
  };

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMore());
    }
  }

  void _onKeywordChanged() {
    setState(() {});
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_load(reset: true));
    });
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _service.fetchListPage(
        page: 0,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
      );
      QianjiRecordDeptStatsResult? stats;
      try {
        stats = await _service.fetchDeptStats();
      } catch (_) {
        stats = null;
      }
      if (!mounted) return;
      await _ensureAvatars();
      if (!mounted) return;
      final rows = _withUserAvatars(result.items);
      setState(() {
        _rows = rows;
        _page = 0;
        _listTotal = result.totalCount < result.items.length
            ? result.items.length
            : result.totalCount;
        _hasMore = result.items.length < _listTotal;
        if (stats != null) {
          _deptStats = stats.departments;
          _total = stats.total;
          _superviseAll = stats.superviseAll;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _service.fetchListPage(
        page: nextPage,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
      );
      if (!mounted) return;
      final existing = _rows.map((e) => e.id).toSet();
      final appended = result.items
          .where((e) => e.id.isEmpty || !existing.contains(e.id))
          .toList(growable: false);
      setState(() {
        _rows = <QianjiRecordSuperviseHit>[..._rows, ..._withUserAvatars(appended)];
        _page = nextPage;
        if (result.totalCount > _listTotal) _listTotal = result.totalCount;
        if (_listTotal < _rows.length) _listTotal = _rows.length;
        _hasMore =
            appended.isNotEmpty &&
            result.items.length >= _pageSize &&
            _rows.length < _listTotal;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _ensureAvatars() async {
    if (_avatarsById.isNotEmpty) return;
    try {
      final users = await TaskApi(widget.session).listAssignees(scope: 'reports');
      if (!mounted) return;
      setState(() {
        _avatarsById = {for (final user in users) user.id: user};
        _avatarsByName = {
          for (final user in users)
            if (user.displayName.trim().isNotEmpty) user.displayName.trim(): user,
        };
      });
    } catch (_) {}
  }

  List<QianjiRecordSuperviseHit> _withUserAvatars(List<QianjiRecordSuperviseHit> rows) {
    return [
      for (final row in rows)
        if (row.avatarUrl.isNotEmpty || row.avatarPreset.isNotEmpty || row.avatarObjectKey.isNotEmpty)
          row
        else
          _applyAssigneeAvatar(row),
    ];
  }

  QianjiRecordSuperviseHit _applyAssigneeAvatar(QianjiRecordSuperviseHit row) {
    final byId = row.userId > 0 ? _avatarsById[row.userId] : null;
    final byName = row.personName.trim().isEmpty
        ? null
        : _avatarsByName[row.personName.trim()];
    final user = byId ?? byName;
    if (user == null) return row;
    return row.copyWithAvatar(
      userId: row.userId > 0 ? row.userId : user.id,
      personName: row.personName.trim().isNotEmpty ? row.personName : user.displayName,
      avatarPreset: user.avatarPreset,
      avatarObjectKey: user.avatarObjectKey,
      avatarUrl: user.avatarUrl,
    );
  }

  void _selectDepartment(int? departmentId) {
    if (_selectedDepartmentId == departmentId) return;
    setState(() => _selectedDepartmentId = departmentId);
    unawaited(_load(reset: true));
  }

  void _clearKeyword() {
    if (_keywordCtrl.text.isEmpty) return;
    _keywordCtrl.clear();
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _search(),
            _deptFilter(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onBack,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new,
                    size: 14,
                    color: DunesColors.text2,
                  ),
                  SizedBox(width: 2),
                  Text(
                    '饕',
                    style: TextStyle(fontSize: 13, color: DunesColors.text2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          if (_listTotal > 0 || _total > 0)
            Text(
              '合计 ${_listTotal > 0 ? _listTotal : _total}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.text2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _keywordCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => unawaited(_load(reset: true)),
        decoration: InputDecoration(
          hintText: _hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _keywordCtrl.text.isNotEmpty
              ? IconButton(
                  onPressed: _clearKeyword,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: '清除',
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _themePurple),
          ),
        ),
      ),
    );
  }

  Widget _deptFilter() {
    if (_deptStats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '部门筛选',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _superviseAll ? '全部门' : '管辖范围',
                style: const TextStyle(
                  fontSize: 11,
                  color: _themePurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          HorizontalDragScrollView(
            child: Row(
              children: [
                _chip(
                  label: '全部',
                  count: _total,
                  selected: _selectedDepartmentId == null,
                  onTap: () => _selectDepartment(null),
                ),
                const SizedBox(width: 8),
                for (final d in _deptStats) ...[
                  _chip(
                    label: d.departmentName,
                    count: d.count,
                    selected: _selectedDepartmentId == (d.departmentId ?? -1),
                    onTap: () => _selectDepartment(d.departmentId ?? -1),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFFF0EEF7) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _themePurple : const Color(0xFFE8EAED),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _themePurple : DunesColors.text2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? _themePurple : DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text2),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load(reset: true)),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    if (_rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              _empty,
              style: const TextStyle(color: DunesColors.text3, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 4, 16, isDesktopCommOnly ? 48 : 40),
      itemCount: _rows.length + ((_loadingMore || _hasMore) ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _rows.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final row = _rows[index];
        final title = row.title.isEmpty ? _title : row.title;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildTaskUserAvatar(
                  session: widget.session,
                  name: row.personName.isNotEmpty ? row.personName : title,
                  userId: row.userId,
                  avatarPreset: row.avatarPreset,
                  avatarObjectKey: row.avatarObjectKey,
                  avatarUrl: row.avatarUrl,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.text,
                              ),
                            ),
                          ),
                          if (row.status.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              row.status,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.text2,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (row.personName.isNotEmpty ||
                          row.subtitle.isNotEmpty ||
                          row.time.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (row.personName.isNotEmpty && row.personName != title)
                              row.personName,
                            row.subtitle,
                            row.time,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
