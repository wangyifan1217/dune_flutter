import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'attendance_models.dart';
import 'attendance_service.dart';

const _historyPurple = Color(0xFF7052D9);
const _historyInk = Color(0xFF27223A);

class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  static const _pageSize = 20;

  final List<AttendanceHistoryItem> _items = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_loadFirst());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 280) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AttendanceService(
        widget.session,
      ).fetchHistory(page: 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await AttendanceService(
        widget.session,
      ).fetchHistory(page: _page + 1, size: _pageSize);
      if (!mounted) return;
      final seen = _items.map((item) => item.id).toSet();
      setState(() {
        for (final item in page.items) {
          if (seen.add(item.id)) _items.add(item);
        }
        _page = page.page;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = _message(error);
      });
    }
  }

  String _message(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? '打卡历史加载失败' : text;
  }

  @override
  Widget build(BuildContext context) {
    final surface = DunesColors.resolve(
      context,
      const Color(0xFFF7F5FA),
      role: DunesColorRole.surface,
    );
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: const Text(
          '打卡历史',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(surface),
    );
  }

  Widget _buildBody(Color surface) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadFirst, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '还没有打卡记录',
          style: TextStyle(fontSize: 14, color: Color(0xFF8C8798)),
        ),
      );
    }
    final groups = _groups(_items);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      itemCount: groups.length + 1,
      itemBuilder: (context, index) {
        if (index == groups.length) return _footer();
        final group = groups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _HistoryDay(date: group.date, items: group.items),
        );
      },
    );
  }

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton(onPressed: _loadMore, child: Text(_error!)),
        ),
      );
    }
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(fontSize: 12, color: Color(0xFF9A95A6)),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

class _DayGroup {
  const _DayGroup(this.date, this.items);
  final String date;
  final List<AttendanceHistoryItem> items;
}

List<_DayGroup> _groups(List<AttendanceHistoryItem> items) {
  final out = <_DayGroup>[];
  for (final item in items) {
    final date = item.localDate.isEmpty ? _ymd(item.punchedAt) : item.localDate;
    if (out.isNotEmpty && out.last.date == date) {
      out.last.items.add(item);
    } else {
      out.add(_DayGroup(date, [item]));
    }
  }
  return out;
}

class _HistoryDay extends StatelessWidget {
  const _HistoryDay({required this.date, required this.items});

  final String date;
  final List<AttendanceHistoryItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFECE8F1),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayLabel(date),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, _historyInk),
            ),
          ),
          const SizedBox(height: 6),
          for (final item in items) _HistoryRow(item: item),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final AttendanceHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final checkIn = item.isCheckIn;
    final accent = checkIn ? const Color(0xFFE5A74A) : _historyPurple;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              checkIn ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkIn ? '上班' : '下班',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, _historyInk),
                  ),
                ),
                if (item.siteName.isNotEmpty)
                  Text(
                    item.siteName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8C8798),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _hm(item.punchedAt),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, _historyInk),
            ),
          ),
        ],
      ),
    );
  }
}

String _ymd(DateTime time) {
  final local = time.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}

String _dayLabel(String ymd) {
  final parsed = DateTime.tryParse(ymd);
  if (parsed == null) return ymd;
  const weeks = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${parsed.month}月${parsed.day}日 ${weeks[parsed.weekday - 1]}';
}

String _hm(DateTime time) {
  final local = time.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
