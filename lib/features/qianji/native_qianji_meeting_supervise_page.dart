import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 千机 · 会议纪要监管：关键词搜索 + 部门筛选（范围由后端控制）。
class NativeQianjiMeetingSupervisePage extends StatefulWidget {
  const NativeQianjiMeetingSupervisePage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenDetail,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenDetail;

  @override
  State<NativeQianjiMeetingSupervisePage> createState() =>
      _NativeQianjiMeetingSupervisePageState();
}

class _NativeQianjiMeetingSupervisePageState
    extends State<NativeQianjiMeetingSupervisePage> {
  late final NativeMeetingService _service = NativeMeetingService(
    session: widget.session,
  );
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<NativeMeetingSummary> _rows = const [];
  List<NativeSuperviseDeptStat> _deptStats = const [];
  /// null = 全部；-1 = 未分配部门；>0 = 指定部门
  int? _selectedDepartmentId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _superviseAll = false;
  int _page = 0;
  int _totalMeetings = 0;
  static const int _pageSize = 20;
  String? _error;
  Timer? _keywordDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _keywordCtrl.addListener(_onKeywordChanged);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _scrollController.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

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
      final listFuture = _service.fetchSuperviseListPage(
        page: 0,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
      );
      final statsFuture = _service.fetchSuperviseDeptStats();
      final result = await listFuture;
      NativeSuperviseDeptStatsResult? stats;
      try {
        stats = await statsFuture;
      } catch (_) {
        stats = null;
      }
      if (!mounted) return;
      setState(() {
        _rows = result.items;
        _page = 0;
        _hasMore = result.items.length >= _pageSize &&
            result.items.length < result.totalCount;
        if (stats != null) {
          _deptStats = stats.departments;
          _totalMeetings = stats.totalMeetings;
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
      final result = await _service.fetchSuperviseListPage(
        page: nextPage,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
      );
      if (!mounted) return;
      setState(() {
        _rows = <NativeMeetingSummary>[..._rows, ...result.items];
        _page = nextPage;
        _hasMore = result.items.length >= _pageSize;
      });
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
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
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildKeywordSearch(),
            _buildDeptFilter(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                    '千机',
                    style: TextStyle(fontSize: 13, color: DunesColors.text2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '会议纪要监管',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          if (_totalMeetings > 0)
            Text(
              '合计 $_totalMeetings',
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

  Widget _buildKeywordSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _keywordCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => unawaited(_load(reset: true)),
        decoration: InputDecoration(
          hintText: '搜索人名、会议名称',
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

  Widget _buildDeptFilter() {
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _DeptChip(
                  label: '全部',
                  count: _totalMeetings,
                  selected: _selectedDepartmentId == null,
                  onTap: () => _selectDepartment(null),
                ),
                const SizedBox(width: 8),
                for (final d in _deptStats) ...[
                  _DeptChip(
                    label: d.departmentName,
                    count: d.meetingCount,
                    selected: _selectedDepartmentId ==
                        (d.departmentId ?? -1),
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

  Widget _buildBody() {
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
        children: const [
          SizedBox(height: 120),
          Center(
            child: Text(
              '暂无会议纪要',
              style: TextStyle(color: DunesColors.text3, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      itemCount: _rows.length + (_loadingMore ? 1 : 0),
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
        return _MeetingCard(
          row: _rows[index],
          statusLabel: _statusLabel(_rows[index].status),
          statusColor: _statusColor(_rows[index].status),
          onTap: () => widget.onOpenDetail(_rows[index].meetingId),
        );
      },
    );
  }
}

class _DeptChip extends StatelessWidget {
  const _DeptChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({
    required this.row,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
  });

  final NativeMeetingSummary row;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = row.title.trim().isEmpty ? '未命名会议' : row.title.trim();
    final person = row.organizerLabel;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 14,
                    color: DunesColors.text3,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    row.displayTime,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                  if (person.isNotEmpty) ...[
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.person_outline,
                      size: 14,
                      color: DunesColors.text3,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        person,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
