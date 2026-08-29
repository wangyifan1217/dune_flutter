import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/platform/desktop_features.dart';
import '../../../core/theme/dunes_theme.dart';
import '../../../core/widgets/horizontal_drag_scroll_view.dart';
import '../../auth/auth_session.dart';
import 'china_provinces.dart';
import 'travel_mock_data.dart';
import 'travel_service.dart';

const _themePurple = Color(0xFF7B5CD8);

enum _TravelView { list, map }

enum _MapMode { province, route }

enum _TravelRangePreset { week, d7, d30, all, custom }

String _deptKeyOf(TravelEmployee e) {
  final name = e.dept.trim();
  return name.isEmpty ? '未填部门' : name;
}

(DateTime?, DateTime?) _travelRangeBounds(
  _TravelRangePreset preset,
  DateTime? customFrom,
  DateTime? customTo,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (preset) {
    case _TravelRangePreset.week:
      final monday = today.subtract(Duration(days: now.weekday - 1));
      return (monday, today);
    case _TravelRangePreset.all:
      return (null, null);
    case _TravelRangePreset.d7:
      return (today.subtract(const Duration(days: 6)), today);
    case _TravelRangePreset.d30:
      return (today.subtract(const Duration(days: 29)), today);
    case _TravelRangePreset.custom:
      final from = customFrom;
      final to = customTo;
      if (from == null || to == null) return (null, null);
      return (
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day),
      );
  }
}

List<TravelEmployee> _visibleTravelPeople({
  required List<TravelEmployee> all,
  String? dept,
  String nameQuery = '',
  String personId = 'all',
}) {
  Iterable<TravelEmployee> list = all;
  if (dept != null) {
    list = list.where((e) => _deptKeyOf(e) == dept);
  }
  final q = nameQuery.trim();
  if (q.isNotEmpty) {
    list = list.where((e) => e.name.contains(q));
  }
  if (personId != 'all') {
    list = list.where((e) => e.id == personId);
  }
  final out = list.toList();
  out.sort((a, b) => b.cost.compareTo(a.cost));
  return out;
}

List<({String name, int trips})> _travelDeptStats(List<TravelEmployee> all) {
  final map = <String, int>{};
  for (final p in all) {
    final key = _deptKeyOf(p);
    map[key] = (map[key] ?? 0) + p.trips;
  }
  final list = [for (final e in map.entries) (name: e.key, trips: e.value)]
    ..sort((a, b) => b.trips.compareTo(a.trips));
  return list;
}

String _travelCustomRangeLabel(DateTime? from, DateTime? to) {
  if (from == null || to == null) return '自定义';
  String fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${fmt(from)}~${fmt(to)}';
}

Future<DateTimeRange?> _pickTravelDateRange(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
}) {
  final now = DateTime.now();
  final initialStart = from ?? now.subtract(const Duration(days: 7));
  final initialEnd = to ?? now;
  return showDateRangePicker(
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
}

void _showTravelKindCosts(BuildContext context, List<TravelEmployee> people) {
  final costs = travelKindCosts(people);
  final total = costs.values.fold<int>(0, (a, b) => a + b);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('出行成本构成'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              total == 0 ? '当前筛选下没有费用' : '合计 ${formatYuan(total)}',
              style: const TextStyle(
                fontSize: 13,
                color: DunesColors.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final kind in TravelKind.values)
              _KindCostLine(kind: kind, amount: costs[kind] ?? 0, total: total),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

void _showTravelCostHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('出行成本怎么算'),
      content: const Text(
        '统计当前时间和部门筛选下，已关联组织用户的订单金额合计。\n\n'
        '金额是导入时按出行人等额分摊后的费用；标了「分摊」的是分摊额，不是原单全额。\n\n'
        '机票、火车、酒店、用车都计入。未关联或重名未指定的订单不进地图，也不计入成本。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// τ管理 · 差旅管理
class NativeQianjiTravelPage extends StatefulWidget {
  const NativeQianjiTravelPage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeQianjiTravelPage> createState() => _NativeQianjiTravelPageState();
}

class _NativeQianjiTravelPageState extends State<NativeQianjiTravelPage> {
  _TravelView _view = _TravelView.map;
  _MapMode _mapMode = _MapMode.province;
  TravelKind? _kindFilter;
  String _personId = 'all';
  String? _selectedDept;
  _TravelRangePreset _rangePreset = _TravelRangePreset.week;
  DateTime? _customFrom;
  DateTime? _customTo;
  final _nameCtrl = TextEditingController();
  String _nameQuery = '';
  late final TravelService _service;
  List<TravelEmployee> _all = const [];
  bool _loading = true;
  String? _error;

  List<TravelEmployee> get _people => _visibleTravelPeople(
    all: _all,
    dept: _selectedDept,
    nameQuery: _nameQuery,
    personId: _personId,
  );

  bool get _hasPeopleFilter =>
      _personId != 'all' ||
      _selectedDept != null ||
      _nameQuery.trim().isNotEmpty;

  String? get _selectedPersonName {
    if (_personId == 'all') return null;
    for (final person in _all) {
      if (person.id == _personId) return person.name;
    }
    return null;
  }

  String _deptKey(TravelEmployee e) => _deptKeyOf(e);

  List<({String name, int trips})> get _deptStats => _travelDeptStats(_all);

  int get _totalTrips => _all.fold<int>(0, (s, p) => s + p.trips);

  (DateTime?, DateTime?) get _rangeBounds =>
      _travelRangeBounds(_rangePreset, _customFrom, _customTo);

  List<TravelLeg> get _visibleLegs {
    final legs = _people.expand((p) => p.legs);
    if (_kindFilter == null) return legs.toList();
    return legs.where((l) => l.kind == _kindFilter).toList();
  }

  @override
  void initState() {
    super.initState();
    _service = TravelService(session: widget.session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final bounds = _rangeBounds;
    try {
      final people = await _service.fetchSummary(
        from: bounds.$1,
        to: bounds.$2,
      );
      if (!mounted) return;
      setState(() {
        _all = people;
        _loading = false;
        if (_personId != 'all' && !people.any((e) => e.id == _personId)) {
          _personId = 'all';
        }
        if (_selectedDept != null &&
            !people.any((e) => _deptKey(e) == _selectedDept)) {
          _selectedDept = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _all = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final total = people.fold<int>(0, (s, p) => s + p.cost);
    final provinces = people.expand((p) => p.provinces).toSet().length;
    final legs = _visibleLegs.length;

    return Material(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: !isDesktopCommOnly,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildFilters(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _buildStats(
                total: total,
                peopleCount: people.length,
                provinces: provinces,
                legs: legs,
                people: people,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFB42318)),
                        ),
                      ),
                    )
                  : _view == _TravelView.list
                  ? (_people.isEmpty
                        ? Center(
                            child: Text(
                              _hasPeopleFilter ? '没有符合条件的人员' : '暂无导入的差旅数据',
                              style: const TextStyle(color: DunesColors.text3),
                            ),
                          )
                        : _EmployeeList(
                            people: people,
                            onOpen: (id) {
                              setState(() {
                                _personId = id;
                                _view = _TravelView.map;
                                _mapMode = _MapMode.province;
                              });
                            },
                          ))
                  : _ChinaTravelMap(
                      people: people,
                      mode: _mapMode,
                      kindFilter: _kindFilter,
                      onFullscreen: _openMapFullscreen,
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
                    'τ管理',
                    style: TextStyle(fontSize: 13, color: DunesColors.text2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '差旅管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          IconButton(
            tooltip: '出行成本怎么算',
            onPressed: () => _showTravelCostHelp(context),
            icon: const Icon(Icons.help_outline, color: _themePurple),
          ),
          if (_view == _TravelView.map)
            IconButton(
              tooltip: '全屏',
              onPressed: _openMapFullscreen,
              icon: const Icon(Icons.fullscreen, color: _themePurple),
            ),
        ],
      ),
    );
  }

  Future<void> _openMapFullscreen() async {
    final result = await Navigator.of(context, rootNavigator: true)
        .push<_MapFullscreenResult>(
          PageRouteBuilder(
            fullscreenDialog: true,
            pageBuilder: (ctx, animation, secondary) {
              return _TravelMapFullscreenPage(
                session: widget.session,
                mode: _mapMode,
                kindFilter: _kindFilter,
                nameQuery: _nameQuery,
                rangePreset: _rangePreset,
                customFrom: _customFrom,
                customTo: _customTo,
                selectedDept: _selectedDept,
                personId: _personId,
              );
            },
          ),
        );
    if (!mounted || result == null) return;
    setState(() {
      _mapMode = result.mode;
      _kindFilter = result.kindFilter;
      _nameQuery = result.nameQuery;
      _nameCtrl.text = result.nameQuery;
      _rangePreset = result.rangePreset;
      _customFrom = result.customFrom;
      _customTo = result.customTo;
      _selectedDept = result.selectedDept;
      _personId = result.personId;
    });
    unawaited(_reload());
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TravelSearchFilters(
          nameCtrl: _nameCtrl,
          onNameChanged: (v) {
            setState(() {
              _nameQuery = v;
              if (_personId != 'all' &&
                  !_all.any(
                    (e) => e.id == _personId && e.name.contains(v.trim()),
                  )) {
                _personId = 'all';
              }
            });
          },
          rangePreset: _rangePreset,
          customRangeLabel: _travelCustomRangeLabel(_customFrom, _customTo),
          onRangePreset: _setRangePreset,
          viewAllDepts: widget.session.travelViewAll,
          deptStats: _deptStats,
          totalTrips: _totalTrips,
          selectedDept: _selectedDept,
          onSelectDept: _selectDepartment,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Segmented(
                value: _view,
                items: const [
                  (value: _TravelView.map, label: '中国地图'),
                  (value: _TravelView.list, label: '列表'),
                ],
                onChanged: (v) => setState(() {
                  _view = v;
                  if (v == _TravelView.list) _personId = 'all';
                }),
              ),
              if (_view == _TravelView.map)
                _Segmented(
                  value: _mapMode,
                  items: const [
                    (value: _MapMode.province, label: '点亮省份'),
                    (value: _MapMode.route, label: '出行轨迹'),
                  ],
                  onChanged: (v) => setState(() => _mapMode = v),
                ),
              if (_view == _TravelView.map && _mapMode == _MapMode.route)
                _Segmented(
                  value: _kindFilter,
                  items: const [
                    (value: null, label: '全部'),
                    (value: TravelKind.flight, label: '飞机'),
                    (value: TravelKind.train, label: '火车'),
                    (value: TravelKind.hotel, label: '酒店'),
                    (value: TravelKind.ground, label: '用车'),
                  ],
                  onChanged: (v) => setState(() => _kindFilter = v),
                ),
            ],
          ),
        ),
        if (_selectedPersonName case final name?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.person_outline_rounded, size: 16),
                label: Text('当前查看：$name'),
                onPressed: () => setState(() => _personId = 'all'),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                onDeleted: () => setState(() => _personId = 'all'),
                tooltip: '清除人员筛选',
              ),
            ),
          ),
      ],
    );
  }

  void _selectDepartment(String? dept) {
    if (_selectedDept == dept) return;
    setState(() {
      _selectedDept = dept;
      _personId = 'all';
    });
  }

  void _setRangePreset(_TravelRangePreset preset) {
    if (preset == _TravelRangePreset.custom) {
      unawaited(_pickCustomRange());
      return;
    }
    if (_rangePreset == preset) return;
    setState(() => _rangePreset = preset);
    unawaited(_reload());
  }

  Future<void> _pickCustomRange() async {
    final range = await _pickTravelDateRange(
      context,
      from: _customFrom,
      to: _customTo,
    );
    if (range == null || !mounted) return;
    setState(() {
      _rangePreset = _TravelRangePreset.custom;
      _customFrom = range.start;
      _customTo = range.end;
      _selectedDept = null;
      _personId = 'all';
    });
    unawaited(_reload());
  }

  Widget _buildStats({
    required int total,
    required int peopleCount,
    required int provinces,
    required int legs,
    required List<TravelEmployee> people,
  }) {
    final chips = [
      _StatChip(
        label: '出行成本',
        value: formatYuan(total),
        onInfo: () => _showTravelKindCosts(context, people),
      ),
      _StatChip(label: '员工', value: '$peopleCount'),
      _StatChip(label: '省份', value: '$provinces'),
      _StatChip(label: '行程', value: '$legs'),
    ];
    final compact = MediaQuery.sizeOf(context).width < 520;
    if (!compact) {
      return Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      );
    }
    return Column(
      children: [
        Row(children: [chips[0], const SizedBox(width: 8), chips[1]]),
        const SizedBox(height: 8),
        Row(children: [chips[2], const SizedBox(width: 8), chips[3]]),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.onInfo});
  final String label;
  final String value;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ),
              if (onInfo != null)
                const Icon(Icons.info_outline, size: 14, color: _themePurple),
            ],
          ),
        ],
      ),
    );
    return Expanded(
      child: onInfo == null
          ? body
          : Tooltip(
              message: '各板块费用',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onInfo,
                  borderRadius: BorderRadius.circular(10),
                  child: body,
                ),
              ),
            ),
    );
  }
}

class _KindCostLine extends StatelessWidget {
  const _KindCostLine({
    required this.kind,
    required this.amount,
    required this.total,
  });

  final TravelKind kind;
  final int amount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(kind);
    final ratio = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    final pct = (ratio * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                kind.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const Spacer(),
              Text(
                formatYuan(amount),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  '$pct%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              color: color,
              backgroundColor: const Color(0xFFF0EEF7),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final List<({T value, String label})> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0F3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            GestureDetector(
              onTap: () => onChanged(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: value == item.value
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    color: value == item.value
                        ? _themePurple
                        : DunesColors.text2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TravelSearchFilters extends StatelessWidget {
  const _TravelSearchFilters({
    required this.nameCtrl,
    required this.onNameChanged,
    required this.rangePreset,
    required this.customRangeLabel,
    required this.onRangePreset,
    required this.viewAllDepts,
    required this.deptStats,
    required this.totalTrips,
    required this.selectedDept,
    required this.onSelectDept,
  });

  final TextEditingController nameCtrl;
  final ValueChanged<String> onNameChanged;
  final _TravelRangePreset rangePreset;
  final String customRangeLabel;
  final ValueChanged<_TravelRangePreset> onRangePreset;
  final bool viewAllDepts;
  final List<({String name, int trips})> deptStats;
  final int totalTrips;
  final String? selectedDept;
  final ValueChanged<String?> onSelectDept;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _PersonSearchField(
            controller: nameCtrl,
            onChanged: onNameChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: HorizontalDragScrollView(
            child: Row(
              children: [
                _RangeChip(
                  label: '本周',
                  selected: rangePreset == _TravelRangePreset.week,
                  onTap: () => onRangePreset(_TravelRangePreset.week),
                ),
                const SizedBox(width: 8),
                _RangeChip(
                  label: '近7天',
                  selected: rangePreset == _TravelRangePreset.d7,
                  onTap: () => onRangePreset(_TravelRangePreset.d7),
                ),
                const SizedBox(width: 8),
                _RangeChip(
                  label: '近30天',
                  selected: rangePreset == _TravelRangePreset.d30,
                  onTap: () => onRangePreset(_TravelRangePreset.d30),
                ),
                const SizedBox(width: 8),
                _RangeChip(
                  label: '全部',
                  selected: rangePreset == _TravelRangePreset.all,
                  onTap: () => onRangePreset(_TravelRangePreset.all),
                ),
                const SizedBox(width: 8),
                _RangeChip(
                  label: rangePreset == _TravelRangePreset.custom
                      ? customRangeLabel
                      : '自定义',
                  selected: rangePreset == _TravelRangePreset.custom,
                  onTap: () => onRangePreset(_TravelRangePreset.custom),
                ),
              ],
            ),
          ),
        ),
        if (deptStats.isNotEmpty)
          Padding(
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
                      viewAllDepts ? '全部部门' : '本人及下属',
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
                        count: totalTrips,
                        selected: selectedDept == null,
                        onTap: () => onSelectDept(null),
                      ),
                      const SizedBox(width: 8),
                      for (final d in deptStats) ...[
                        _DeptChip(
                          label: d.name,
                          count: d.trips,
                          selected: selectedDept == d.name,
                          onTap: () => onSelectDept(d.name),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PersonSearchField extends StatelessWidget {
  const _PersonSearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13, color: DunesColors.text),
        decoration: InputDecoration(
          hintText: '搜索人员',
          hintStyle: const TextStyle(fontSize: 13, color: DunesColors.text3),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: DunesColors.text3,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: DunesColors.text3,
                  ),
                ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
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

Color _kindColor(TravelKind kind) => switch (kind) {
  TravelKind.flight => const Color(0xFF7B5CD8),
  TravelKind.train => const Color(0xFF0F766E),
  TravelKind.hotel => const Color(0xFFB54708),
  TravelKind.ground => const Color(0xFFC2410C),
};

class _EmployeeList extends StatelessWidget {
  const _EmployeeList({required this.people, required this.onOpen});
  final List<TravelEmployee> people;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = people[i];
        final kinds = p.legs.map((l) => l.kind).toSet();
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpen(p.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text,
                          ),
                        ),
                      ),
                      Text(
                        formatYuan(p.cost),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _themePurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${p.dept.trim().isEmpty ? '' : '${p.dept} · '}${p.trips} 段行程',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final kind in kinds)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _kindColor(kind).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            kind.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: _kindColor(kind),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      for (final name in p.provinces)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EEF7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            p.provinceChip(name),
                            style: const TextStyle(
                              fontSize: 11,
                              color: _themePurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MapPick {
  const _MapPick({
    required this.title,
    required this.subtitle,
    required this.total,
    required this.lines,
    this.province,
    this.routeKey,
  });

  final String title;
  final String subtitle;
  final int total;
  final List<_PickLine> lines;
  final String? province;
  final String? routeKey;
}

class _PickLine {
  const _PickLine({
    required this.title,
    required this.meta,
    required this.amount,
    this.shared = false,
  });
  final String title;
  final String meta;
  final int amount;
  final bool shared;
}

class _RouteBundle {
  _RouteBundle({
    required this.key,
    required this.from,
    required this.to,
    required this.kind,
    required this.items,
  });
  final String key;
  final String from;
  final String to;
  final TravelKind kind;
  final List<TaggedLeg> items;

  int get total => items.fold(0, (s, e) => s + e.leg.amount);
}

List<_RouteBundle> _routeBundles(
  List<TravelEmployee> people,
  TravelKind? kindFilter,
) {
  final map = <String, _RouteBundle>{};
  for (final item in taggedLegs(people, kind: kindFilter)) {
    var from = item.leg.from;
    var to = item.leg.to;
    if (item.leg.kind == TravelKind.ground) {
      final city = travelCityOf(from);
      if (city != null) {
        from = city.name;
        to = city.name;
      } else if (from.isEmpty) {
        from = to = to;
      } else {
        to = from;
      }
    }
    final key = '$from|$to|${item.leg.kind.name}';
    final cur = map[key];
    if (cur == null) {
      map[key] = _RouteBundle(
        key: key,
        from: from,
        to: to,
        kind: item.leg.kind,
        items: [item],
      );
    } else {
      cur.items.add(item);
    }
  }
  return map.values.toList();
}

Path _arcPath(Offset a, Offset b, double bulgeFactor) {
  final mx = (a.dx + b.dx) / 2;
  final my = (a.dy + b.dy) / 2;
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  var nx = -dy;
  var ny = dx;
  final len = math.sqrt(nx * nx + ny * ny);
  if (len > 0) {
    nx /= len;
    ny /= len;
  }
  final dist = math.sqrt(dx * dx + dy * dy);
  final bulge = math.min(64.0, dist * bulgeFactor);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(mx + nx * bulge, my + ny * bulge, b.dx, b.dy);
}

/// 等比适配：手机宽屏矮容器里不再把中国地图纵向压扁。
class _MapFit {
  const _MapFit({required this.scale, required this.origin});
  final double scale;
  final Offset origin;

  static _MapFit of(Size size) {
    final scale = math.min(
      size.width / ChinaMapProj.vbW,
      size.height / ChinaMapProj.vbH,
    );
    return _MapFit(
      scale: scale <= 0 ? 1 : scale,
      origin: Offset(
        (size.width - ChinaMapProj.vbW * scale) / 2,
        (size.height - ChinaMapProj.vbH * scale) / 2,
      ),
    );
  }

  Offset toScreen(double x, double y) =>
      Offset(origin.dx + x * scale, origin.dy + y * scale);

  Offset toViewBox(Offset screen) =>
      Offset((screen.dx - origin.dx) / scale, (screen.dy - origin.dy) / scale);
}

double _pathDistance(Path path, Offset p) {
  var min = double.infinity;
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 5) {
      final t = metric.getTangentForOffset(d.clamp(0.0, metric.length));
      if (t == null) continue;
      final dist = (t.position - p).distance;
      if (dist < min) min = dist;
    }
  }
  return min;
}

class _MapFullscreenResult {
  const _MapFullscreenResult({
    required this.mode,
    required this.kindFilter,
    required this.nameQuery,
    required this.rangePreset,
    required this.customFrom,
    required this.customTo,
    required this.selectedDept,
    required this.personId,
  });
  final _MapMode mode;
  final TravelKind? kindFilter;
  final String nameQuery;
  final _TravelRangePreset rangePreset;
  final DateTime? customFrom;
  final DateTime? customTo;
  final String? selectedDept;
  final String personId;
}

class _TravelMapFullscreenPage extends StatefulWidget {
  const _TravelMapFullscreenPage({
    required this.session,
    required this.mode,
    required this.kindFilter,
    required this.nameQuery,
    required this.rangePreset,
    required this.customFrom,
    required this.customTo,
    required this.selectedDept,
    required this.personId,
  });
  final AuthSession session;
  final _MapMode mode;
  final TravelKind? kindFilter;
  final String nameQuery;
  final _TravelRangePreset rangePreset;
  final DateTime? customFrom;
  final DateTime? customTo;
  final String? selectedDept;
  final String personId;

  @override
  State<_TravelMapFullscreenPage> createState() =>
      _TravelMapFullscreenPageState();
}

class _TravelMapFullscreenPageState extends State<_TravelMapFullscreenPage> {
  late _MapMode _mode;
  late TravelKind? _kindFilter;
  late _TravelRangePreset _rangePreset;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _selectedDept;
  late String _personId;
  late final TextEditingController _nameCtrl;
  late String _nameQuery;
  late final TravelService _service;
  List<TravelEmployee> _all = const [];
  bool _loading = true;
  String? _error;

  List<TravelEmployee> get _people => _visibleTravelPeople(
    all: _all,
    dept: _selectedDept,
    nameQuery: _nameQuery,
    personId: _personId,
  );

  List<({String name, int trips})> get _deptStats => _travelDeptStats(_all);

  int get _totalTrips => _all.fold<int>(0, (s, p) => s + p.trips);

  String? get _selectedPersonName {
    if (_personId == 'all') return null;
    for (final person in _all) {
      if (person.id == _personId) return person.name;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _kindFilter = widget.kindFilter;
    _rangePreset = widget.rangePreset;
    _customFrom = widget.customFrom;
    _customTo = widget.customTo;
    _selectedDept = widget.selectedDept;
    _personId = widget.personId;
    _nameQuery = widget.nameQuery;
    _nameCtrl = TextEditingController(text: widget.nameQuery);
    _service = TravelService(session: widget.session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final bounds = _travelRangeBounds(_rangePreset, _customFrom, _customTo);
    try {
      final people = await _service.fetchSummary(
        from: bounds.$1,
        to: bounds.$2,
      );
      if (!mounted) return;
      setState(() {
        _all = people;
        _loading = false;
        if (_selectedDept != null &&
            !people.any((e) => _deptKeyOf(e) == _selectedDept)) {
          _selectedDept = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _all = const [];
      });
    }
  }

  void _selectDepartment(String? dept) {
    if (_selectedDept == dept) return;
    setState(() => _selectedDept = dept);
  }

  void _setRangePreset(_TravelRangePreset preset) {
    if (preset == _TravelRangePreset.custom) {
      unawaited(_pickCustomRange());
      return;
    }
    if (_rangePreset == preset) return;
    setState(() => _rangePreset = preset);
    unawaited(_reload());
  }

  Future<void> _pickCustomRange() async {
    final range = await _pickTravelDateRange(
      context,
      from: _customFrom,
      to: _customTo,
    );
    if (range == null || !mounted) return;
    setState(() {
      _rangePreset = _TravelRangePreset.custom;
      _customFrom = range.start;
      _customTo = range.end;
      _selectedDept = null;
    });
    unawaited(_reload());
  }

  void _close() {
    Navigator.of(context).pop(
      _MapFullscreenResult(
        mode: _mode,
        kindFilter: _kindFilter,
        nameQuery: _nameQuery,
        rangePreset: _rangePreset,
        customFrom: _customFrom,
        customTo: _customTo,
        selectedDept: _selectedDept,
        personId: _personId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _close();
      },
      child: Material(
        color: const Color(0xFFEEF1F6),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '退出全屏',
                      onPressed: _close,
                      icon: const Icon(Icons.close, color: DunesColors.text),
                    ),
                    const Expanded(
                      child: Text(
                        '差旅地图',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _themePurple,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '出行成本怎么算',
                      onPressed: () => _showTravelCostHelp(context),
                      icon: const Icon(Icons.help_outline, color: _themePurple),
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.white,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    _selectedPersonName == null
                        ? '筛选条件'
                        : '当前查看：$_selectedPersonName',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  subtitle: const Text(
                    '展开后可调整人员、时间和部门',
                    style: TextStyle(fontSize: 11, color: DunesColors.text3),
                  ),
                  children: [
                    _TravelSearchFilters(
                      nameCtrl: _nameCtrl,
                      onNameChanged: (v) => setState(() => _nameQuery = v),
                      rangePreset: _rangePreset,
                      customRangeLabel: _travelCustomRangeLabel(
                        _customFrom,
                        _customTo,
                      ),
                      onRangePreset: _setRangePreset,
                      viewAllDepts: widget.session.travelViewAll,
                      deptStats: _deptStats,
                      totalTrips: _totalTrips,
                      selectedDept: _selectedDept,
                      onSelectDept: _selectDepartment,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Segmented(
                      value: _mode,
                      items: const [
                        (value: _MapMode.province, label: '点亮省份'),
                        (value: _MapMode.route, label: '出行轨迹'),
                      ],
                      onChanged: (v) => setState(() => _mode = v),
                    ),
                    if (_mode == _MapMode.route)
                      _Segmented(
                        value: _kindFilter,
                        items: const [
                          (value: null, label: '全部'),
                          (value: TravelKind.flight, label: '飞机'),
                          (value: TravelKind.train, label: '火车'),
                          (value: TravelKind.hotel, label: '酒店'),
                          (value: TravelKind.ground, label: '用车'),
                        ],
                        onChanged: (v) => setState(() => _kindFilter = v),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ),
                      )
                    : _ChinaTravelMap(
                        people: _people,
                        mode: _mode,
                        kindFilter: _kindFilter,
                        edgeToEdge: true,
                        onFullscreen: _close,
                        fullscreen: true,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChinaTravelMap extends StatefulWidget {
  const _ChinaTravelMap({
    required this.people,
    required this.mode,
    required this.kindFilter,
    this.onFullscreen,
    this.fullscreen = false,
    this.edgeToEdge = false,
  });
  final List<TravelEmployee> people;
  final _MapMode mode;
  final TravelKind? kindFilter;
  final VoidCallback? onFullscreen;
  final bool fullscreen;
  final bool edgeToEdge;

  @override
  State<_ChinaTravelMap> createState() => _ChinaTravelMapState();
}

class _ChinaTravelMapState extends State<_ChinaTravelMap>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _flow;
  _MapPick? _pick;
  Offset? _pointerDown;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _flow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _ChinaTravelMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.kindFilter != widget.kindFilter ||
        oldWidget.people.length != widget.people.length) {
      _pick = null;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _flow.dispose();
    super.dispose();
  }

  void _onTap(Offset local, Size size) {
    final fit = _MapFit.of(size);
    final legs = taggedLegs(widget.people, kind: widget.kindFilter);

    if (widget.mode == _MapMode.route) {
      final bundles = _routeBundles(widget.people, widget.kindFilter);
      _RouteBundle? best;
      var bestDist = 14.0;
      for (final bundle in bundles) {
        final a = travelCityOf(bundle.from);
        final b = travelCityOf(bundle.to);
        final point =
            bundle.items.any((e) => routeIsPoint(e.leg)) ||
            bundle.from == bundle.to;
        double? dist;
        if (point) {
          final city = a ?? b;
          if (city == null) continue;
          final pt = ChinaMapProj.project(city.lon, city.lat);
          dist = (fit.toScreen(pt.x, pt.y) - local).distance;
        } else if (a != null && b != null) {
          final p1 = ChinaMapProj.project(a.lon, a.lat);
          final p2 = ChinaMapProj.project(b.lon, b.lat);
          final path = _arcPath(
            fit.toScreen(p1.x, p1.y),
            fit.toScreen(p2.x, p2.y),
            _KindVisual.of(bundle.kind).bulge,
          );
          dist = _pathDistance(path, local);
        }
        if (dist != null && dist < bestDist) {
          bestDist = dist;
          best = bundle;
        }
      }
      if (best != null) {
        final bundle = best;
        setState(() {
          _pick = _MapPick(
            title: bundle.from == bundle.to
                ? bundle.from
                : '${bundle.from} → ${bundle.to}',
            subtitle: '${bundle.kind.label} · ${bundle.items.length} 段',
            total: bundle.total,
            routeKey: bundle.key,
            lines: [
              for (final item in bundle.items)
                _PickLine(
                  title: '${item.person.name} · ${item.leg.kind.label}',
                  meta: item.leg.date,
                  amount: item.leg.amount,
                  shared: item.leg.shared,
                ),
            ],
          );
        });
        return;
      }
    }

    final vb = fit.toViewBox(local);
    ChinaProvince? hit;
    var bestArea = double.infinity;
    for (final p in chinaProvinces) {
      if (p.name.isEmpty) continue;
      final path = _parseProvincePath(p.d);
      if (!path.contains(vb)) continue;
      final b = path.getBounds();
      final area = b.width * b.height;
      if (area < bestArea) {
        bestArea = area;
        hit = p;
      }
    }
    if (hit == null) {
      setState(() => _pick = null);
      return;
    }

    final province = hit;
    final related = legs
        .where((e) => legTouchesProvince(e.leg, province.name))
        .toList();
    final byPerson = <String, _PickLine>{};
    for (final item in related) {
      final id = item.person.id;
      final prev = byPerson[id];
      final visits = item.person.visitCount(province.name);
      byPerson[id] = _PickLine(
        title: item.person.name,
        meta: visits > 0 ? '停留 $visits 次' : item.person.dept,
        amount: (prev?.amount ?? 0) + item.leg.amount,
        shared: (prev?.shared ?? false) || item.leg.shared,
      );
    }
    setState(() {
      _pick = _MapPick(
        title: province.name,
        subtitle: related.isEmpty
            ? '暂无行程'
            : '${byPerson.length} 人 · ${related.length} 段行程',
        total: provinceSpend(legs, province.name),
        province: province.name,
        lines: byPerson.values.toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.edgeToEdge
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEEF1F6),
          borderRadius: BorderRadius.circular(widget.edgeToEdge ? 0 : 12),
          border: widget.edgeToEdge
              ? null
              : Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.edgeToEdge ? 0 : 12),
          child: LayoutBuilder(
            builder: (context, outer) {
              final viewport = Size(outer.maxWidth, outer.maxHeight);
              return Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final size = Size(c.maxWidth, c.maxHeight);
                          return Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) =>
                                _pointerDown = e.localPosition,
                            onPointerCancel: (_) => _pointerDown = null,
                            onPointerUp: (e) {
                              final start = _pointerDown;
                              _pointerDown = null;
                              if (start == null) return;
                              if ((e.localPosition - start).distance > 14) {
                                return;
                              }
                              _onTap(e.localPosition, size);
                            },
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_pulse, _flow]),
                              builder: (context, _) {
                                return CustomPaint(
                                  painter: _TravelMapPainter(
                                    people: widget.people,
                                    mode: widget.mode,
                                    kindFilter: widget.kindFilter,
                                    pulse: _pulse.value,
                                    flow: _flow.value,
                                    selectedProvince: _pick?.province,
                                    selectedRouteKey: _pick?.routeKey,
                                  ),
                                  child: const SizedBox.expand(),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (widget.onFullscreen != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        elevation: 1,
                        child: IconButton(
                          tooltip: widget.fullscreen ? '退出全屏' : '全屏',
                          onPressed: widget.onFullscreen,
                          icon: Icon(
                            widget.fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: _themePurple,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: widget.mode == _MapMode.route
                          ? const _RouteLegend()
                          : const _HintChip(text: '点击省份查看费用'),
                    ),
                  ),
                  if (_pick != null)
                    Positioned.fill(
                      child: Material(
                        color: const Color(0x59000000),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _pick = null),
                          child: Center(
                            child: GestureDetector(
                              onTap: () {},
                              child: _CostCard(
                                pick: _pick!,
                                maxWidth: math.min(
                                  320.0,
                                  math.max(220.0, viewport.width - 40),
                                ),
                                maxHeight: math.min(
                                  420.0,
                                  math.max(180.0, viewport.height - 64),
                                ),
                                onClose: () => setState(() => _pick = null),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF4B5563),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({
    required this.pick,
    required this.onClose,
    required this.maxWidth,
    required this.maxHeight,
  });
  final _MapPick pick;
  final VoidCallback onClose;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    const headerH = 108.0;
    final listH = pick.lines.isEmpty
        ? 0.0
        : math.min(
            pick.lines.length * 50.0,
            math.max(0.0, maxHeight - headerH),
          );

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pick.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                pick.subtitle,
                style: const TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
              const SizedBox(height: 6),
              Text(
                formatYuan(pick.total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _themePurple,
                ),
              ),
              if (listH > 0) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: listH,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: pick.lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 10),
                    itemBuilder: (context, i) {
                      final line = pick.lines[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.title,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.text,
                                  ),
                                ),
                                Text(
                                  line.meta,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: DunesColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatYuan(line.amount),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _themePurple,
                                ),
                              ),
                              if (line.shared)
                                const Text(
                                  '分摊',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _themePurple,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteLegend extends StatelessWidget {
  const _RouteLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: const Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _LegendDot(color: Color(0xFF7B5CD8), label: '飞机'),
          _LegendDot(color: Color(0xFF0F766E), label: '火车'),
          _LegendDot(color: Color(0xFFB54708), label: '酒店'),
          _LegendDot(color: Color(0xFFC2410C), label: '用车'),
          Text(
            '点击线路看费用',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF4B5563),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF4B5563),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

final _provincePathCache = <String, Path>{};

Path _parseProvincePath(String d) {
  return _provincePathCache.putIfAbsent(d, () {
    final path = Path();
    for (final part in d.split(RegExp(r'(?=[Mm])'))) {
      if (part.trim().isEmpty) continue;
      final nums = RegExp(
        r'-?\d+\.?\d*',
      ).allMatches(part).map((m) => double.parse(m.group(0)!)).toList();
      if (nums.length < 2) continue;
      path.moveTo(nums[0], nums[1]);
      for (var i = 2; i + 1 < nums.length; i += 2) {
        path.lineTo(nums[i], nums[i + 1]);
      }
      path.close();
    }
    return path;
  });
}

class _KindVisual {
  const _KindVisual({
    required this.color,
    required this.bulge,
    required this.width,
    required this.dash,
    required this.gap,
    required this.speed,
    required this.dot,
  });
  final Color color;
  final double bulge;
  final double width;
  final double dash;
  final double gap;
  final double speed;
  final double dot;

  static _KindVisual of(TravelKind kind) => switch (kind) {
    TravelKind.flight => const _KindVisual(
      color: Color(0xFF7B5CD8),
      bulge: 0.28,
      width: 2.6,
      dash: 16,
      gap: 10,
      speed: 1.0,
      dot: 5.2,
    ),
    TravelKind.train => const _KindVisual(
      color: Color(0xFF0F766E),
      bulge: 0.12,
      width: 2.4,
      dash: 10,
      gap: 7,
      speed: 0.72,
      dot: 4.4,
    ),
    TravelKind.hotel => const _KindVisual(
      color: Color(0xFFB54708),
      bulge: 0.0,
      width: 2.0,
      dash: 5,
      gap: 4,
      speed: 0.5,
      dot: 4.0,
    ),
    TravelKind.ground => const _KindVisual(
      color: Color(0xFFC2410C),
      bulge: 0.06,
      width: 2.0,
      dash: 5,
      gap: 4,
      speed: 1.2,
      dot: 3.6,
    ),
  };
}

class _TravelMapPainter extends CustomPainter {
  _TravelMapPainter({
    required this.people,
    required this.mode,
    required this.kindFilter,
    required this.pulse,
    required this.flow,
    this.selectedProvince,
    this.selectedRouteKey,
  });

  final List<TravelEmployee> people;
  final _MapMode mode;
  final TravelKind? kindFilter;
  final double pulse;
  final double flow;
  final String? selectedProvince;
  final String? selectedRouteKey;

  List<TravelLeg> get _legs {
    final all = people.expand((p) => p.legs);
    if (kindFilter == null) return all.toList();
    return all.where((l) => l.kind == kindFilter).toList();
  }

  Set<String> get _lit {
    final s = <String>{};
    s.addAll(people.expand((p) => p.provinces));
    for (final leg in _legs) {
      if (leg.kind == TravelKind.ground) {
        if (leg.originProvince.isNotEmpty) s.add(leg.originProvince);
        final a = travelCityOf(leg.from);
        if (a != null) s.add(a.province);
        continue;
      }
      if (leg.originProvince.isNotEmpty) s.add(leg.originProvince);
      if (leg.destProvince.isNotEmpty) s.add(leg.destProvince);
      final a = travelCityOf(leg.from);
      final b = travelCityOf(leg.to);
      if (a != null) s.add(a.province);
      if (b != null) s.add(b.province);
    }
    return s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fit = _MapFit.of(size);
    canvas.save();
    canvas.translate(fit.origin.dx, fit.origin.dy);
    canvas.scale(fit.scale, fit.scale);

    final costs = provinceCostMap(people);
    final max = costs.values.fold<double>(0, math.max);
    final lit = _lit;

    final unlitFill = Paint()..color = const Color(0xFFB7BEC9);
    final unlitStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..color = Colors.white;

    for (final p in chinaProvinces) {
      if (p.name.isEmpty || lit.contains(p.name)) continue;
      final path = _parseProvincePath(p.d);
      canvas.drawPath(path, unlitFill);
      canvas.drawPath(path, unlitStroke);
    }

    for (final p in chinaProvinces) {
      if (!lit.contains(p.name)) continue;
      _paintLitProvince(
        canvas,
        p,
        intensity: max <= 0
            ? 0.7
            : ((costs[p.name] ?? 0) / max).clamp(0.55, 1.0),
        selected: p.name == selectedProvince,
      );
    }

    canvas.restore();

    _paintProvinceLabels(canvas, fit, lit);
    _paintRoutes(canvas, fit);
  }

  void _paintProvinceLabels(Canvas canvas, _MapFit fit, Set<String> lit) {
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (final p in chinaProvinces) {
      if (p.name.isEmpty) continue;
      final selected = p.name == selectedProvince;
      final on = lit.contains(p.name);
      tp.text = TextSpan(
        text: p.name,
        style: TextStyle(
          fontSize: selected ? 11 : 9.5,
          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
          color: selected
              ? const Color(0xFF4C1D95)
              : on
              ? const Color(0xFF3F2A7A)
              : const Color(0xFF4B5563),
          shadows: const [
            Shadow(
              color: Color(0xF7FFFFFF),
              blurRadius: 3,
              offset: Offset(0, 0.4),
            ),
          ],
        ),
      );
      tp.layout();
      final pos = fit.toScreen(p.cx, p.cy);
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
    }
  }

  void _paintLitProvince(
    Canvas canvas,
    ChinaProvince p, {
    required double intensity,
    required bool selected,
  }) {
    final path = _parseProvincePath(p.d);
    final bounds = path.getBounds();
    final top = Color.lerp(
      const Color(0xFF9B7CE8),
      const Color(0xFF7B5CD8),
      intensity,
    )!;
    final bottom = Color.lerp(
      const Color(0xFF7B5CD8),
      const Color(0xFF4C2FB0),
      intensity,
    )!;
    final fill = Paint()
      ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [
        top,
        bottom,
      ]);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 6 : 4
      ..color = _themePurple.withValues(alpha: 0.22 + pulse * 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    canvas.drawPath(path, glow);
    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.6 : 1.05
        ..color = selected ? _themePurple : const Color(0xFFF7F5FF),
    );
  }

  void _paintRoutes(Canvas canvas, _MapFit fit) {
    final bundles = _routeBundles(people, kindFilter);
    final cities = <String>{};
    var i = 0;
    for (final bundle in bundles) {
      final a = travelCityOf(bundle.from);
      final b = travelCityOf(bundle.to);
      final point =
          bundle.items.any((e) => routeIsPoint(e.leg)) ||
          bundle.from == bundle.to;
      if (point) {
        final city = a ?? b;
        if (city == null) continue;
        cities.add(city.name);
        i++;
        continue;
      }
      if (mode == _MapMode.province) continue;
      if (a == null || b == null) continue;
      cities.add(bundle.from);
      cities.add(bundle.to);
      final visual = _KindVisual.of(bundle.kind);
      final p1 = ChinaMapProj.project(a.lon, a.lat);
      final p2 = ChinaMapProj.project(b.lon, b.lat);
      final path = _arcPath(
        fit.toScreen(p1.x, p1.y),
        fit.toScreen(p2.x, p2.y),
        visual.bulge,
      );
      final selected = bundle.key == selectedRouteKey;
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = visual.width + (selected ? 1.4 : 0)
        ..strokeCap = StrokeCap.round
        ..color = visual.color.withValues(alpha: selected ? 0.5 : 0.28);
      canvas.drawPath(path, base);
      final phase = (flow * visual.speed + i * 0.13) % 1.0;
      _drawDashes(canvas, path, visual, phase, selected: selected);
      _drawHead(canvas, path, visual, phase);
      i++;
    }
    _paintCityLabels(canvas, cities, fit);
  }

  void _paintCityLabels(Canvas canvas, Set<String> cities, _MapFit fit) {
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (final name in cities) {
      final city = travelCityOf(name);
      if (city == null) continue;
      final pt = ChinaMapProj.project(city.lon, city.lat);
      final pos = fit.toScreen(pt.x, pt.y);
      canvas.drawCircle(pos, 5.2, Paint()..color = Colors.white);
      canvas.drawCircle(pos, 3.6, Paint()..color = const Color(0xFF7B5CD8));
      tp.text = TextSpan(
        text: name,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(pos.dx + 7, pos.dy - 13));
    }
  }

  void _drawDashes(
    Canvas canvas,
    Path path,
    _KindVisual visual,
    double phase, {
    required bool selected,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = visual.width + (selected ? 1.2 : 0)
      ..strokeCap = StrokeCap.round
      ..color = visual.color;
    final cycle = visual.dash + visual.gap;
    for (final metric in path.computeMetrics()) {
      var d = -phase * cycle;
      while (d < metric.length) {
        final start = d.clamp(0.0, metric.length);
        final end = (d + visual.dash).clamp(0.0, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        d += cycle;
      }
    }
  }

  void _drawHead(Canvas canvas, Path path, _KindVisual visual, double phase) {
    for (final metric in path.computeMetrics()) {
      final dist = (metric.length * phase).clamp(0.0, metric.length);
      final tangent = metric.getTangentForOffset(dist);
      if (tangent == null) continue;
      final pos = tangent.position;
      canvas.drawCircle(
        pos,
        visual.dot + 2.4,
        Paint()
          ..color = visual.color.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(pos, visual.dot, Paint()..color = visual.color);
      canvas.drawCircle(pos, visual.dot * 0.42, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TravelMapPainter oldDelegate) =>
      oldDelegate.people != people ||
      oldDelegate.mode != mode ||
      oldDelegate.kindFilter != kindFilter ||
      oldDelegate.pulse != pulse ||
      oldDelegate.flow != flow ||
      oldDelegate.selectedProvince != selectedProvince ||
      oldDelegate.selectedRouteKey != selectedRouteKey;
}
