import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import 'session_supervise_models.dart';
import 'session_supervise_service.dart';

const _themePurple = Color(0xFF7B5CD8);

enum _SessionRangePreset { week, d7, d30, all, custom }

/// NOVA · 会话监管：按人统计聊天条数，支持部门与时间范围筛选。
class NativeQianjiSessionSupervisePage extends StatefulWidget {
  const NativeQianjiSessionSupervisePage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeQianjiSessionSupervisePage> createState() =>
      _NativeQianjiSessionSupervisePageState();
}

class _NativeQianjiSessionSupervisePageState
    extends State<NativeQianjiSessionSupervisePage> {
  late final SessionSuperviseService _service =
      SessionSuperviseService(session: widget.session);
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<SessionSuperviseRow> _rows = const [];
  List<SessionSuperviseDeptStat> _deptStats = const [];
  int? _selectedDepartmentId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _superviseAll = false;
  int _page = 0;
  int _totalTurns = 0;
  static const int _pageSize = 20;
  String? _error;
  Timer? _keywordDebounce;

  _SessionRangePreset _rangePreset = _SessionRangePreset.week;
  DateTime? _customFrom;
  DateTime? _customTo;

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

  (DateTime?, DateTime?) get _rangeBounds {
    final now = DateTime.now();
    switch (_rangePreset) {
      case _SessionRangePreset.week:
        // 本周一 00:00 起
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case _SessionRangePreset.all:
        return (null, null);
      case _SessionRangePreset.d7:
        return (now.subtract(const Duration(days: 7)), now);
      case _SessionRangePreset.d30:
        return (now.subtract(const Duration(days: 30)), now);
      case _SessionRangePreset.custom:
        final from = _customFrom;
        final to = _customTo;
        if (from == null || to == null) return (null, null);
        return (
          DateTime(from.year, from.month, from.day),
          DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
        );
    }
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
    final bounds = _rangeBounds;
    try {
      final listFuture = _service.fetchListPage(
        page: 0,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
        from: bounds.$1,
        to: bounds.$2,
      );
      final statsFuture = _service.fetchDeptStats(
        from: bounds.$1,
        to: bounds.$2,
      );
      final result = await listFuture;
      SessionSuperviseDeptStatsResult? stats;
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
          _totalTurns = stats.totalRank;
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
    final bounds = _rangeBounds;
    try {
      final nextPage = _page + 1;
      final result = await _service.fetchListPage(
        page: nextPage,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
        from: bounds.$1,
        to: bounds.$2,
      );
      if (!mounted) return;
      setState(() {
        _rows = <SessionSuperviseRow>[..._rows, ...result.items];
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

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = _customFrom ?? now.subtract(const Duration(days: 7));
    final initialEnd = _customTo ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: '选择时间范围',
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: _themePurple,
              onPrimary: Colors.white,
              surfaceTint: Colors.transparent,
            ),
            datePickerTheme: base.datePickerTheme.copyWith(
              rangeSelectionBackgroundColor: const Color(0xFFEFEAFA),
              backgroundColor: Colors.white,
              headerBackgroundColor: Colors.white,
              headerForegroundColor: DunesColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;
    setState(() {
      _rangePreset = _SessionRangePreset.custom;
      _customFrom = range.start;
      _customTo = range.end;
    });
    unawaited(_load(reset: true));
  }

  void _setRangePreset(_SessionRangePreset preset) {
    if (preset == _SessionRangePreset.custom) {
      unawaited(_pickCustomRange());
      return;
    }
    if (_rangePreset == preset) return;
    setState(() => _rangePreset = preset);
    unawaited(_load(reset: true));
  }

  String get _customRangeLabel {
    final from = _customFrom;
    final to = _customTo;
    if (from == null || to == null) return '自定义';
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(from)}~${fmt(to)}';
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
            _buildRangeFilter(),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
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
                    'NOVA',
                    style: TextStyle(fontSize: 13, color: DunesColors.text2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'IM会话',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          if (_totalTurns > 0)
            Text(
              '合计 $_totalTurns 条',
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
          hintText: '搜索人名',
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

  Widget _buildRangeFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: HorizontalDragScrollView(
        child: Row(
          children: [
            _RangeChip(
              label: '本周',
              selected: _rangePreset == _SessionRangePreset.week,
              onTap: () => _setRangePreset(_SessionRangePreset.week),
            ),
            const SizedBox(width: 8),
            _RangeChip(
              label: '近7天',
              selected: _rangePreset == _SessionRangePreset.d7,
              onTap: () => _setRangePreset(_SessionRangePreset.d7),
            ),
            const SizedBox(width: 8),
            _RangeChip(
              label: '近30天',
              selected: _rangePreset == _SessionRangePreset.d30,
              onTap: () => _setRangePreset(_SessionRangePreset.d30),
            ),
            const SizedBox(width: 8),
            _RangeChip(
              label: '全部',
              selected: _rangePreset == _SessionRangePreset.all,
              onTap: () => _setRangePreset(_SessionRangePreset.all),
            ),
            const SizedBox(width: 8),
            _RangeChip(
              label: _rangePreset == _SessionRangePreset.custom
                  ? _customRangeLabel
                  : '自定义',
              selected: _rangePreset == _SessionRangePreset.custom,
              onTap: () => _setRangePreset(_SessionRangePreset.custom),
            ),
          ],
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
          HorizontalDragScrollView(
            child: Row(
              children: [
                _DeptChip(
                  label: '全部',
                  count: _totalTurns,
                  selected: _selectedDepartmentId == null,
                  onTap: () => _selectDepartment(null),
                ),
                const SizedBox(width: 8),
                for (final d in _deptStats) ...[
                  _DeptChip(
                    label: d.departmentName,
                    count: d.rankCount,
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
              '暂无会话数据',
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
        return _PersonCard(row: _rows[index]);
      },
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _themePurple : DunesColors.text2,
            ),
          ),
        ),
      ),
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

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.row});

  final SessionSuperviseRow row;

  @override
  Widget build(BuildContext context) {
    final dept = row.departmentName.trim().isEmpty
        ? '未分配部门'
        : row.departmentName.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  row.personLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              Text(
                '${row.turnCount} 条',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _themePurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$dept · ${row.sessionCount} 会话',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}
