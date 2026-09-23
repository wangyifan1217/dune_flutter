import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/analytics/usage_module_map.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'app_usage_models.dart';
import 'app_usage_service.dart';
import 'efficiency/efficiency_models.dart';
import 'efficiency/efficiency_service.dart';

const _themePurple = Color(0xFF7B5CD8);
const _deepPurple = Color(0xFF4A2FA0);
const _palePurple = Color(0xFFEEE8F8);

enum _UsageRangePreset { week, d7, d30, custom }

class NativeQianjiAppUsagePage extends StatefulWidget {
  const NativeQianjiAppUsagePage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenUser,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final void Function(AppUsageUserRow user, DateTime? from, DateTime? to)
  onOpenUser;

  @override
  State<NativeQianjiAppUsagePage> createState() =>
      _NativeQianjiAppUsagePageState();
}

class _NativeQianjiAppUsagePageState extends State<NativeQianjiAppUsagePage> {
  late final AppUsageService _service = AppUsageService(
    session: widget.session,
  );
  late final EfficiencyService _avatarLookup = EfficiencyService(
    session: widget.session,
  );
  late final ConversationService _avatarService = ConversationService(
    session: widget.session,
  );
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  AppUsageHeatmap? _heatmap;
  List<AppUsageUserRow> _users = const [];
  int? _selectedDepartmentId;
  String? _selectedModule;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _superviseAll = false;
  bool _moduleTotalsExpanded = false;
  int _page = 0;
  int _avatarLoadGeneration = 0;
  Map<int, WorkSituationAvatar> _userAvatars = const {};
  static const int _pageSize = 20;
  String? _error;
  Timer? _keywordDebounce;
  _UsageRangePreset _rangePreset = _UsageRangePreset.d7;
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
      case _UsageRangePreset.week:
        final monday = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        return (monday, DateTime(now.year, now.month, now.day));
      case _UsageRangePreset.d7:
        return (
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 6)),
          DateTime(now.year, now.month, now.day),
        );
      case _UsageRangePreset.d30:
        return (
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 29)),
          DateTime(now.year, now.month, now.day),
        );
      case _UsageRangePreset.custom:
        return (_customFrom, _customTo);
    }
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      unawaited(_loadMore());
    }
  }

  void _onKeywordChanged() {
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_load(reset: true));
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: _customFrom ?? now.subtract(const Duration(days: 6)),
        end: _customTo ?? DateTime(now.year, now.month, now.day),
      ),
      helpText: '选择范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
      builder: (ctx, child) {
        final light = ColorScheme.light(
          primary: _themePurple,
          onPrimary: Colors.white,
          secondary: _themePurple.withValues(alpha: 0.18),
          onSecondary: DunesColors.text,
          surface: Colors.white,
          onSurface: DunesColors.text,
        );
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorScheme: light,
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor: Colors.white,
              headerForegroundColor: DunesColors.text,
              rangeSelectionBackgroundColor: _themePurple.withValues(
                alpha: 0.14,
              ),
              rangeSelectionOverlayColor: WidgetStatePropertyAll(
                _themePurple.withValues(alpha: 0.08),
              ),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return _themePurple;
                return null;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                if (states.contains(WidgetState.disabled)) {
                  return DunesColors.text3;
                }
                return DunesColors.text;
              }),
              todayForegroundColor: const WidgetStatePropertyAll(_themePurple),
              todayBorder: const BorderSide(color: _themePurple),
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null) return;
    setState(() {
      _rangePreset = _UsageRangePreset.custom;
      _customFrom = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      _customTo = DateTime(range.end.year, range.end.month, range.end.day);
    });
    unawaited(_load(reset: true));
  }

  void _setRangePreset(_UsageRangePreset preset) {
    if (preset == _UsageRangePreset.custom) {
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

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 0;
        _hasMore = true;
      });
    }
    final (from, to) = _rangeBounds;
    try {
      final heatmap = await _service.fetchHeatmap(
        from: from,
        to: to,
        departmentId: _selectedDepartmentId,
        moduleKey: _selectedModule ?? '',
        q: _keywordCtrl.text,
      );
      final users = await _service.fetchUsers(
        from: from,
        to: to,
        departmentId: _selectedDepartmentId,
        q: _keywordCtrl.text,
        page: 0,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _heatmap = heatmap;
        _users = users.items;
        _superviseAll = heatmap.superviseAll || users.superviseAll;
        _hasMore = users.items.length >= _pageSize;
        _page = 1;
        _loading = false;
      });
      unawaited(_loadUserAvatars(users.items));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final (from, to) = _rangeBounds;
    try {
      final users = await _service.fetchUsers(
        from: from,
        to: to,
        departmentId: _selectedDepartmentId,
        q: _keywordCtrl.text,
        page: _page,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _users = [..._users, ...users.items];
        _hasMore = users.items.length >= _pageSize;
        _page += 1;
        _loadingMore = false;
      });
      unawaited(_loadUserAvatars(users.items));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadUserAvatars(Iterable<AppUsageUserRow> users) async {
    final ids = users.map((user) => user.userId).where((id) => id > 0).toSet();
    if (ids.isEmpty) return;
    final generation = ++_avatarLoadGeneration;
    final avatars = await _avatarLookup.fetchUserAvatars(ids);
    if (!mounted || generation != _avatarLoadGeneration || avatars.isEmpty) {
      return;
    }
    setState(() => _userAvatars = {..._userAvatars, ...avatars});
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
                color: _themePurple,
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
    final heatmap = _heatmap;
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
                    '饕',
                    style: TextStyle(fontSize: 13, color: DunesColors.text2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '沙丘使用热力',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          if (heatmap != null && heatmap.activeUsers > 0)
            Text(
              '活跃 ${heatmap.activeUsers} 人',
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
          hintText: '按姓名或账号筛选',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _keywordCtrl.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _keywordCtrl.clear();
                    unawaited(_load(reset: true));
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
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
            _Chip(
              label: '本周',
              selected: _rangePreset == _UsageRangePreset.week,
              onTap: () => _setRangePreset(_UsageRangePreset.week),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: '近7天',
              selected: _rangePreset == _UsageRangePreset.d7,
              onTap: () => _setRangePreset(_UsageRangePreset.d7),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: '近30天',
              selected: _rangePreset == _UsageRangePreset.d30,
              onTap: () => _setRangePreset(_UsageRangePreset.d30),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: _rangePreset == _UsageRangePreset.custom
                  ? _customRangeLabel
                  : '自定义',
              selected: _rangePreset == _UsageRangePreset.custom,
              onTap: () => _setRangePreset(_UsageRangePreset.custom),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptFilter() {
    final depts = _heatmap?.departments ?? const [];
    if (depts.isEmpty) return const SizedBox.shrink();
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
                _Chip(
                  label: '全部',
                  selected: _selectedDepartmentId == null,
                  onTap: () {
                    setState(() => _selectedDepartmentId = null);
                    unawaited(_load(reset: true));
                  },
                ),
                const SizedBox(width: 8),
                for (final d in depts) ...[
                  _Chip(
                    label: d.departmentName,
                    selected: _selectedDepartmentId == (d.departmentId ?? -1),
                    onTap: () {
                      setState(
                        () => _selectedDepartmentId = d.departmentId ?? -1,
                      );
                      unawaited(_load(reset: true));
                    },
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
          Center(child: CircularProgressIndicator(color: _themePurple)),
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
    final heatmap = _heatmap;
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        if (heatmap != null) _buildMetrics(heatmap),
        if (heatmap != null) ...[
          const SizedBox(height: 16),
          _buildModuleHeat(heatmap),
        ],
        const SizedBox(height: 18),
        const Text(
          '团队停留',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF261D38),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '点人可看每页停留',
          style: TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
        const SizedBox(height: 10),
        if (_users.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '暂无使用数据',
                style: TextStyle(color: DunesColors.text3, fontSize: 14),
              ),
            ),
          )
        else
          for (final row in _users) ...[
            _UserCard(
              row: row,
              maxDuration: _users.first.durationMs,
              avatar: _userAvatars[row.userId],
              avatarService: _avatarService,
              onTap: () {
                final (from, to) = _rangeBounds;
                widget.onOpenUser(row, from, to);
              },
            ),
            const SizedBox(height: 10),
          ],
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetrics(AppUsageHeatmap heatmap) {
    final avg = usageAvgMinutes(heatmap.durationMs, heatmap.activeUsers);
    return Row(
      children: [
        _MetricTile(label: '活跃', value: '${heatmap.activeUsers}人'),
        const SizedBox(width: 8),
        _MetricTile(
          label: '平均停留',
          value: avg <= 0 ? '0分' : formatUsageStay((avg * 60000).round()),
        ),
        const SizedBox(width: 8),
        _MetricTile(label: '会话', value: '${heatmap.sessionCount}'),
      ],
    );
  }

  Widget _buildModuleHeat(AppUsageHeatmap heatmap) {
    final modules = heatmap.modules.where((m) {
      if (m.moduleKey == '_session') return false;
      if (_selectedModule != null && m.moduleKey == _selectedModule) {
        return true;
      }
      return m.durationMs > 0;
    }).toList();
    final matrix = heatmap.matrix.where((row) {
      if (_selectedModule != null && row.moduleKey == _selectedModule) {
        return true;
      }
      return row.values.any((v) => v > 0);
    }).toList();
    final maxDur = modules.fold<int>(
      0,
      (m, e) => e.durationMs > m ? e.durationMs : m,
    );
    var maxCell = 0;
    for (final row in matrix) {
      for (final v in row.values) {
        if (v > maxCell) maxCell = v;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '模块 × 日期',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF261D38),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '格子越深，当天停得越久。携程、薪人薪事和各免登应用分开统计。',
          style: TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
        const SizedBox(height: 10),
        if (matrix.isEmpty)
          const Text('暂无模块数据', style: TextStyle(color: DunesColors.text3))
        else
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDE8F5)),
            ),
            child: _HeatMatrix(
              dates: heatmap.dates,
              rows: matrix,
              maxValue: maxCell,
              selectedModule: _selectedModule,
              onSelect: (key) {
                setState(() {
                  _selectedModule = _selectedModule == key ? null : key;
                });
                unawaited(_load(reset: true));
              },
            ),
          ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _moduleTotalsExpanded = !_moduleTotalsExpanded);
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '模块总停留',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF261D38),
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: DunesColors.text3),
              ],
            ),
          ),
        ),
        if (_moduleTotalsExpanded) ...[
          const SizedBox(height: 10),
          if (modules.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEDE8F5)),
              ),
              child: Column(
                children: [
                  for (final m in modules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ModuleBar(
                        module: m,
                        ratio: maxDur <= 0 ? 0 : m.durationMs / maxDur,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDE8F5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: DunesColors.text3),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _heatColor(int value, int maxValue) {
  if (value <= 0 || maxValue <= 0) return _palePurple;
  final t = (0.12 + (value / maxValue) * 0.88).clamp(0.0, 1.0);
  return Color.lerp(_palePurple, _deepPurple, t)!;
}

class _HeatMatrix extends StatelessWidget {
  const _HeatMatrix({
    required this.dates,
    required this.rows,
    required this.maxValue,
    required this.selectedModule,
    required this.onSelect,
  });

  final List<String> dates;
  final List<AppUsageHeatRow> rows;
  final int maxValue;
  final String? selectedModule;
  final ValueChanged<String> onSelect;

  String _dayLabel(String date) {
    if (date.length >= 10) return date.substring(8);
    return date;
  }

  static const _labelW = 56.0;
  static const _gap = 3.0;
  static const _maxCell = 18.0;
  static const _minCell = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = dates.length;
        if (cols <= 0) return const SizedBox.shrink();
        final available = (constraints.maxWidth - _labelW).clamp(0.0, 4000.0);
        final raw = (available - _gap * (cols - 1)) / cols;
        final cell = raw.clamp(_minCell, _maxCell);
        final gridW = _labelW + cols * cell + (cols - 1) * _gap;
        final grid = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: _labelW),
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  SizedBox(
                    width: cell,
                    child: Text(
                      _dayLabel(dates[i]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: InkWell(
                  onTap: () => onSelect(row.moduleKey),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _labelW,
                        child: Text(
                          usageModuleLabel(row.moduleKey, row.moduleName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: selectedModule == row.moduleKey
                                ? _themePurple
                                : const Color(0xFF261D38),
                          ),
                        ),
                      ),
                      for (var i = 0; i < cols; i++) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        SizedBox(
                          width: cell,
                          height: cell,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _heatColor(
                                i < row.values.length ? row.values[i] : 0,
                                maxValue,
                              ),
                              borderRadius: BorderRadius.circular(3),
                              border: selectedModule == row.moduleKey
                                  ? Border.all(color: _deepPurple)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '低 ',
                  style: TextStyle(fontSize: 10, color: DunesColors.text3),
                ),
                _LegendDot(color: Color(0xFFEEE8F8)),
                _LegendDot(color: Color(0xFFD4C4F4)),
                _LegendDot(color: Color(0xFF9B7EE8)),
                _LegendDot(color: Color(0xFF4A2FA0)),
                Text(
                  ' 高',
                  style: TextStyle(fontSize: 10, color: DunesColors.text3),
                ),
              ],
            ),
          ],
        );
        if (gridW > constraints.maxWidth + 0.5) {
          return HorizontalDragScrollView(
            child: SizedBox(width: gridW, child: grid),
          );
        }
        return grid;
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _ModuleBar extends StatelessWidget {
  const _ModuleBar({required this.module, required this.ratio});

  final AppUsageModule module;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            usageModuleLabel(module.moduleKey, module.moduleName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF261D38),
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.04, 1),
              minHeight: 10,
              backgroundColor: const Color(0xFFF1EBF9),
              color: _deepPurple,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            formatUsageStay(module.durationMs),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _themePurple,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.row,
    required this.maxDuration,
    required this.avatar,
    required this.avatarService,
    required this.onTap,
  });

  final AppUsageUserRow row;
  final int maxDuration;
  final WorkSituationAvatar? avatar;
  final ConversationService avatarService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = maxDuration <= 0 ? 0.0 : row.durationMs / maxDuration;
    final initial = row.displayName.isNotEmpty ? row.displayName[0] : '用';
    final lastSeen = formatUsageLastSeen(row.lastSeenAt);
    final modules = usageRowTopModules(row);
    final avgStay = usageAvgStayMs(row.durationMs, row.sessionCount);
    final stats = <(String, String)>[
      if (row.sessionCount > 0) ('会话', '${row.sessionCount}次'),
      if (avgStay > 0) ('次均', formatUsageStay(avgStay)),
      if (row.activeDays > 0) ('活跃', '${row.activeDays}天'),
      if (row.pv > 0) ('浏览', '${row.pv}次'),
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ImUserAvatar(
                  initial: initial,
                  seed: row.userId,
                  size: 40,
                  avatarPreset: avatar?.preset,
                  avatarObjectKey: avatar?.objectKey,
                  avatarUrl: avatar?.url,
                  avatarService: avatarService,
                  fallbackBackground: const Color(0xFFF1EBF9),
                  fallbackForeground: _themePurple,
                ),
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
                            row.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF261D38),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatUsageStay(row.durationMs),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _themePurple,
                          ),
                        ),
                      ],
                    ),
                    if (row.departmentName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        row.departmentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                    if (modules.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < modules.length; i++)
                            _UserFactChip(
                              label: '${i + 1}',
                              value: [
                                modules[i].label,
                                if (modules[i].durationMs > 0)
                                  formatUsageStay(modules[i].durationMs),
                              ].join(' '),
                            ),
                        ],
                      ),
                    ],
                    if (stats.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final stat in stats)
                            _UserFactChip(label: stat.$1, value: stat.$2),
                        ],
                      ),
                    ],
                    if (lastSeen != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '最近 $lastSeen',
                        style: const TextStyle(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0.04, 1),
                        minHeight: 4,
                        backgroundColor: const Color(0xFFF1EBF9),
                        color: _themePurple,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserFactChip extends StatelessWidget {
  const _UserFactChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3FB),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DunesColors.text3,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5B4A7A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
