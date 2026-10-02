import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/dunes_theme.dart';
import '../../../core/widgets/horizontal_drag_scroll_view.dart';
import '../../auth/auth_session.dart';
import 'travel_service.dart';

const _issuePurple = Color(0xFF7B5CD8);

enum _IssueRangePreset { week, d7, d30, all, custom }

/// 差旅问题分析独立页。时间段在本页选择，点开一条线索再看订单明细。
class TravelIssuesPage extends StatefulWidget {
  const TravelIssuesPage({super.key, required this.session, this.onBack});

  final AuthSession session;
  final VoidCallback? onBack;

  @override
  State<TravelIssuesPage> createState() => _TravelIssuesPageState();
}

class _TravelIssuesPageState extends State<TravelIssuesPage> {
  late final TravelService _service;
  final _nameCtrl = TextEditingController();
  _IssueRangePreset _preset = _IssueRangePreset.all;
  DateTime? _customFrom;
  DateTime? _customTo;
  String _type = '';
  String _status = 'PENDING';
  String _department = '';
  List<String> _departments = const [];
  TravelIssueSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TravelService(session: widget.session);
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) get _bounds {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _IssueRangePreset.week:
        return (today.subtract(Duration(days: today.weekday - 1)), today);
      case _IssueRangePreset.d7:
        return (today.subtract(const Duration(days: 6)), today);
      case _IssueRangePreset.d30:
        return (today.subtract(const Duration(days: 29)), today);
      case _IssueRangePreset.all:
        return (null, null);
      case _IssueRangePreset.custom:
        return (_customFrom, _customTo);
    }
  }

  String get _rangeText {
    final (from, to) = _bounds;
    if (from == null || to == null) return '全部时间';
    return '${_ymd(from)} 至 ${_ymd(to)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (from, to) = _bounds;
    try {
      final snapshot = await _service.fetchIssues(
        from: from,
        to: to,
        type: _type,
        status: _status,
        query: _nameCtrl.text,
        department: _department,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        if (_department.isEmpty) _departments = _departmentsOf(snapshot);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final (from, to) = _bounds;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: from ?? now.subtract(const Duration(days: 29)),
        end: to ?? now,
      ),
      helpText: '选择时间段',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: _issuePurple,
              onPrimary: DunesColors.resolve(ctx, Colors.white),
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;
    setState(() {
      _preset = _IssueRangePreset.custom;
      _customFrom = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      _customTo = DateTime(range.end.year, range.end.month, range.end.day);
    });
    unawaited(_load());
  }

  void _setPreset(_IssueRangePreset preset) {
    if (preset == _IssueRangePreset.custom) {
      unawaited(_pickRange());
      return;
    }
    if (_preset == preset) return;
    setState(() => _preset = preset);
    unawaited(_load());
  }

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final departments = _departments;
    return Material(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_load()),
                decoration: InputDecoration(
                  hintText: '搜索人员',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: DunesColors.resolve(
                        context,
                        Color(0xFFE8EAED),
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: DunesColors.resolve(
                        context,
                        Color(0xFFE8EAED),
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: HorizontalDragScrollView(
                child: Row(
                  children: [
                    _chip(
                      context,
                      '本周',
                      _preset == _IssueRangePreset.week,
                      () => _setPreset(_IssueRangePreset.week),
                    ),
                    _chip(
                      context,
                      '近7天',
                      _preset == _IssueRangePreset.d7,
                      () => _setPreset(_IssueRangePreset.d7),
                    ),
                    _chip(
                      context,
                      '近30天',
                      _preset == _IssueRangePreset.d30,
                      () => _setPreset(_IssueRangePreset.d30),
                    ),
                    _chip(
                      context,
                      '全部',
                      _preset == _IssueRangePreset.all,
                      () => _setPreset(_IssueRangePreset.all),
                    ),
                    _chip(
                      context,
                      '自定义',
                      _preset == _IssueRangePreset.custom,
                      () => _setPreset(_IssueRangePreset.custom),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickRange,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range_rounded,
                          size: 18,
                          color: DunesColors.resolveNullable(
                            context,
                            _issuePurple,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '时间段  $_rangeText',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: DunesColors.resolveNullable(
                                context,
                                Color(0xFF24212B),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '选择',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolveNullable(
                              context,
                              _issuePurple,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _menu(context, '问题类型', _typeLabel, _typeOptions, (
                      value,
                    ) {
                      setState(() => _type = value);
                      unawaited(_load());
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _menu(
                      context,
                      '复核状态',
                      _reviewFilterLabel,
                      _statusOptions,
                      (value) {
                        setState(() => _status = value);
                        unawaited(_load());
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (departments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: HorizontalDragScrollView(
                  child: Row(
                    children: [
                      _chip(context, '全部部门', _department.isEmpty, () {
                        setState(() => _department = '');
                        unawaited(_load());
                      }),
                      for (final name in departments)
                        _chip(context, name, _department == name, () {
                          setState(() => _department = name);
                          unawaited(_load());
                        }),
                    ],
                  ),
                ),
              ),
            Expanded(child: _body(snapshot)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _back,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new,
                    size: 14,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                  SizedBox(width: 2),
                  Text(
                    '返回',
                    style: TextStyle(
                      fontSize: 13,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '问题分析',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, _issuePurple),
              ),
            ),
          ),
          if (_snapshot != null)
            Text(
              '${_snapshot!.count} 条',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text2),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(TravelIssueSnapshot? snapshot) {
    if (_loading && snapshot == null) {
      return const Center(
        child: CircularProgressIndicator(color: _issuePurple),
      );
    }
    if (_error != null && snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('问题分析加载失败：$_error', textAlign: TextAlign.center),
        ),
      );
    }
    final issues = snapshot?.issues ?? const <TravelIssue>[];
    if (issues.isEmpty) {
      return const Center(child: Text('当前时间段内没有线索'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: issues.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return _IssueSummaryCard(
          issue: issue,
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => TravelIssueDetailPage(
                  session: widget.session,
                  issue: issue,
                ),
              ),
            );
            if (changed == true) unawaited(_load());
          },
        );
      },
    );
  }
}

class TravelIssueDetailPage extends StatefulWidget {
  const TravelIssueDetailPage({
    super.key,
    required this.session,
    required this.issue,
  });

  final AuthSession session;
  final TravelIssue issue;

  @override
  State<TravelIssueDetailPage> createState() => _TravelIssueDetailPageState();
}

class _TravelIssueDetailPageState extends State<TravelIssueDetailPage> {
  late final TravelService _service;
  late TravelIssue _issue;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _service = TravelService(session: widget.session);
    _issue = widget.issue;
    _from = _dateOnly(_parseStamp(widget.issue.startAt));
    _to = _dateOnly(_parseStamp(widget.issue.endAt));
    if (_from != null && _to != null && _to!.isBefore(_from!)) {
      final swap = _from;
      _from = _to;
      _to = swap;
    }
  }

  List<TravelIssueOrder> get _visibleOrders {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return _issue.orders;
    final end = to.add(const Duration(days: 1));
    return [
      for (final order in _issue.orders)
        if (_overlaps(order, from, end)) order,
    ];
  }

  bool _overlaps(TravelIssueOrder order, DateTime from, DateTime endExclusive) {
    final start = _parseStamp(order.startAt);
    final stop = _parseStamp(order.endAt.isEmpty ? order.startAt : order.endAt);
    if (start == null && stop == null) return true;
    final orderStart = start ?? stop!;
    final orderEnd = stop ?? start!;
    return orderStart.isBefore(endExclusive) && !orderEnd.isBefore(from);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _from ?? now.subtract(const Duration(days: 1)),
        end: _to ?? now,
      ),
      helpText: '选择这条线索的时间段',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(range.end.year, range.end.month, range.end.day);
    });
  }

  Future<void> _review(String status) async {
    final noteCtrl = TextEditingController(text: _issue.reviewNote);
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          status == 'CONFIRMED'
              ? '确认线索'
              : status == 'FALSE_POSITIVE'
              ? '标记为误报'
              : '恢复待核实',
        ),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '复核说明（可选）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, noteCtrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    noteCtrl.dispose();
    if (note == null) return;
    try {
      await _service.reviewIssue(
        fingerprint: _issue.fingerprint,
        status: status,
        note: note,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存复核结果失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _visibleOrders;
    final hidden = _issue.orders.length - orders.length;
    final rangeText = _from == null || _to == null
        ? '未选择'
        : '${_ymd(_from!)} 至 ${_ymd(_to!)}';
    return Scaffold(
      backgroundColor: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      appBar: AppBar(
        backgroundColor: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        foregroundColor: DunesColors.resolve(context, const Color(0xFF24212B)),
        elevation: 0,
        title: const Text(
          '线索详情',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            _issue.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolveNullable(context, Color(0xFF24212B)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(context, _severityLabel(_issue)),
              _pill(context, _statusLabel(_issue.reviewStatus)),
              if (_issue.location.isNotEmpty) _pill(context, _issue.location),
              _pill(context, '涉及 ${_money(_issue.amountFen)}'),
            ],
          ),
          const SizedBox(height: 14),
          _block('说明', _issue.explanation),
          const SizedBox(height: 10),
          _block('建议', _issue.suggestion),
          const SizedBox(height: 14),
          Material(
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickRange,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_rounded,
                      color: DunesColors.resolveNullable(context, _issuePurple),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '时间段',
                            style: TextStyle(
                              fontSize: 12,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rangeText,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '选择',
                      style: TextStyle(
                        color: DunesColors.resolveNullable(
                          context,
                          _issuePurple,
                        ),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '关联订单 ${orders.length}${hidden > 0 ? ' · 已隐藏 $hidden 笔不在此时段' : ''}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            Text(
              '所选时间段内没有关联订单',
              style: TextStyle(
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            )
          else
            for (final order in orders) ...[
              _OrderCard(
                order: order,
                selected: _matchesSelectedRange(order),
                onUseRange: () {
                  final start = _dateOnly(_parseStamp(order.startAt));
                  final end = _dateOnly(
                    _parseStamp(
                      order.endAt.isEmpty ? order.startAt : order.endAt,
                    ),
                  );
                  if (start == null && end == null) return;
                  setState(() {
                    _from = start ?? end;
                    _to = end ?? start;
                    if (_from != null && _to != null && _to!.isBefore(_from!)) {
                      final swap = _from;
                      _from = _to;
                      _to = swap;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _review('FALSE_POSITIVE'),
                  child: const Text('标记误报'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _issuePurple),
                  onPressed: () => _review('CONFIRMED'),
                  child: const Text('确认线索'),
                ),
              ),
            ],
          ),
          if (_issue.reviewStatus != 'PENDING')
            TextButton(
              onPressed: () => _review('PENDING'),
              child: const Text('恢复待核实'),
            ),
        ],
      ),
    );
  }

  bool _matchesSelectedRange(TravelIssueOrder order) {
    final start = _dateOnly(_parseStamp(order.startAt));
    final end = _dateOnly(
      _parseStamp(order.endAt.isEmpty ? order.startAt : order.endAt),
    );
    final from = start ?? end;
    var to = end ?? start;
    if (from != null && to != null && to.isBefore(from)) to = from;
    return from != null && from == _from && to == _to;
  }

  Widget _block(String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body.isEmpty ? '—' : body,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: DunesColors.resolveNullable(context, Color(0xFF24212B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueSummaryCard extends StatelessWidget {
  const _IssueSummaryCard({required this.issue, required this.onTap});

  final TravelIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = issue.orders
        .map((order) => order.traveler.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join('、');
    final when = issue.startAt.isEmpty
        ? '时间待补'
        : '${_formatStamp(issue.startAt)}${issue.endAt.isEmpty ? '' : ' 至 ${_formatStamp(issue.endAt)}'}';
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      issue.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _pill(context, _severityLabel(issue)),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF98A2B3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (names.isNotEmpty) names,
                  if (issue.location.isNotEmpty) issue.location,
                ].join(' · '),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF344054),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$when · ${_money(issue.amountFen)} · ${issue.orders.length} 笔订单',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.selected,
    required this.onUseRange,
  });

  final TravelIssueOrder order;
  final bool selected;
  final VoidCallback onUseRange;

  @override
  Widget build(BuildContext context) {
    final where = order.kind == 'hotel'
        ? (order.place.isEmpty ? order.destCity : order.place)
        : [
            order.originCity,
            order.destCity,
          ].where((part) => part.trim().isNotEmpty).join(' → ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? DunesColors.resolve(
                context,
                const Color(0xFFF7F3FF),
                role: DunesColorRole.surface,
              )
            : DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? DunesColors.resolve(
                  context,
                  _issuePurple,
                  role: DunesColorRole.border,
                )
              : DunesColors.resolve(
                  context,
                  const Color(0xFFE4E7EC),
                  role: DunesColorRole.border,
                ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.traveler.isEmpty ? '未匹配员工' : order.traveler,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _money(order.amountFen),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(context, _issuePurple),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (order.department.isNotEmpty) order.department,
              _kindLabel(order.kind),
              if (order.orderId.isNotEmpty) '订单 ${order.orderId}',
            ].join(' · '),
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatStamp(order.startAt)} 至 ${_formatStamp(order.endAt.isEmpty ? order.startAt : order.endAt)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (where.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              where,
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.resolveNullable(context, Color(0xFF344054)),
              ),
            ),
          ],
          if (order.shared)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '同单多人',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onUseRange, child: const Text('选此时段')),
          ),
        ],
      ),
    );
  }
}

Widget _chip(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap,
) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: DunesColors.resolve(
        context,
        selected ? const Color(0xFFF0EEF7) : Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                selected ? _issuePurple : const Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(
                context,
                selected ? _issuePurple : const Color(0xFF5C5566),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _pill(BuildContext context, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF2EDFC),
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: DunesColors.resolve(context, const Color(0xFF5B3FA0)),
      ),
    ),
  );
}

Widget _menu(
  BuildContext context,
  String label,
  String value,
  List<({String value, String label})> options,
  ValueChanged<String> onSelected,
) {
  return PopupMenuButton<String>(
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final option in options)
        PopupMenuItem(value: option.value, child: Text(option.label)),
    ],
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ],
      ),
    ),
  );
}

const _typeOptions = <({String value, String label})>[
  (value: '', label: '全部类型'),
  (value: 'HOTEL_OVERLAP', label: '同行住宿'),
  (value: 'HOTEL_DATE_MISMATCH', label: '住宿日期不匹配'),
  (value: 'HOTEL_CITY_MISMATCH', label: '住宿城市不匹配'),
  (value: 'TRAVEL_OVERLAP', label: '交通冲突'),
  (value: 'TIGHT_CONNECTION', label: '衔接时间较短'),
  (value: 'DUPLICATE_ROUTE', label: '疑似重复行程'),
  (value: 'REBOOK_FEE', label: '改签手续费'),
  (value: 'REBOOK_CLUSTER', label: '集中改签'),
  (value: 'DATA', label: '数据质量'),
];

const _statusOptions = <({String value, String label})>[
  (value: 'PENDING', label: '待核实'),
  (value: 'CONFIRMED', label: '已确认'),
  (value: 'FALSE_POSITIVE', label: '误报'),
  (value: 'ALL', label: '全部状态'),
];

extension on _TravelIssuesPageState {
  String get _typeLabel => _typeOptions
      .firstWhere(
        (item) => item.value == _type,
        orElse: () => _typeOptions.first,
      )
      .label;
  String get _reviewFilterLabel => _statusOptions
      .firstWhere(
        (item) => item.value == _status,
        orElse: () => _statusOptions.first,
      )
      .label;
}

List<String> _departmentsOf(TravelIssueSnapshot? snapshot) {
  final names = <String>{};
  for (final issue in snapshot?.issues ?? const <TravelIssue>[]) {
    for (final order in issue.orders) {
      final name = order.department.trim();
      if (name.isNotEmpty) names.add(name);
    }
  }
  final list = names.toList()..sort();
  return list;
}

String _severityLabel(TravelIssue issue) {
  return switch (issue.severity) {
    'HIGH' => '高关注',
    'MEDIUM' => '需复核',
    _ => _statusLabelOf(issue.reviewStatus),
  };
}

String _statusLabel(String status) => _statusLabelOf(status);

String _statusLabelOf(String status) {
  return switch (status) {
    'CONFIRMED' => '已确认',
    'FALSE_POSITIVE' => '误报',
    _ => '待核实',
  };
}

String _kindLabel(String kind) {
  return switch (kind) {
    'hotel' => '酒店',
    'flight' => '飞机',
    'train' => '火车',
    'ground' || 'car' => '用车',
    _ => kind.isEmpty ? '行程' : kind,
  };
}

String _money(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';

String _ymd(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

DateTime? _parseStamp(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T')) ??
      DateTime.tryParse(text.split(' ').first);
}

DateTime? _dateOnly(DateTime? value) {
  if (value == null) return null;
  return DateTime(value.year, value.month, value.day);
}

String _formatStamp(String raw) {
  final value = _parseStamp(raw);
  if (value == null) return raw.isEmpty ? '日期缺失' : raw;
  final date = _ymd(value);
  if (value.hour == 0 && value.minute == 0) return date;
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$date $hh:$mm';
}
