import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'cursor_supervise_models.dart';
import 'cursor_supervise_service.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 千机 · Cursor 账号监管：关键词（人名/账号）+ 部门筛选。
class NativeQianjiCursorAccountPage extends StatefulWidget {
  const NativeQianjiCursorAccountPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenDetail,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenDetail;

  @override
  State<NativeQianjiCursorAccountPage> createState() =>
      _NativeQianjiCursorAccountPageState();
}

class _NativeQianjiCursorAccountPageState
    extends State<NativeQianjiCursorAccountPage> {
  late final CursorSuperviseService _service =
      CursorSuperviseService(session: widget.session);
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<CursorSuperviseRow> _rows = const [];
  List<CursorSuperviseDeptStat> _deptStats = const [];
  int? _selectedDepartmentId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _superviseAll = false;
  int _page = 0;
  int _totalAccounts = 0;
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
      final listFuture = _service.fetchListPage(
        page: 0,
        size: _pageSize,
        keyword: _keywordCtrl.text,
        departmentId: _selectedDepartmentId,
      );
      final statsFuture = _service.fetchDeptStats();
      final result = await listFuture;
      CursorSuperviseDeptStatsResult? stats;
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
          _totalAccounts = stats.totalAccounts;
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
      setState(() {
        _rows = <CursorSuperviseRow>[..._rows, ...result.items];
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

  String _pct(int? v) => v == null ? '—' : '$v%';

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
              'Cursor账号监管',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          if (_totalAccounts > 0)
            Text(
              '合计 $_totalAccounts',
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
          hintText: '搜索人名、账号',
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
                  count: _totalAccounts,
                  selected: _selectedDepartmentId == null,
                  onTap: () => _selectDepartment(null),
                ),
                const SizedBox(width: 8),
                for (final d in _deptStats) ...[
                  _DeptChip(
                    label: d.departmentName,
                    count: d.accountCount,
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
              '暂无 Cursor 账号',
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
        final row = _rows[index];
        return _AccountCard(
          row: row,
          remainingLabel:
              row.remainingDays == null ? '—' : '${row.remainingDays}天',
          autoLabel: _pct(row.autoUsagePercent),
          apiLabel: _pct(row.apiUsagePercent),
          totalLabel: _pct(row.totalUsagePercent),
          onTap: () => widget.onOpenDetail(row.bindingId),
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.row,
    required this.remainingLabel,
    required this.autoLabel,
    required this.apiLabel,
    required this.totalLabel,
    required this.onTap,
  });

  final CursorSuperviseRow row;
  final String remainingLabel;
  final String autoLabel;
  final String apiLabel;
  final String totalLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(width: 8),
                  Text(
                    row.membershipLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _themePurple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                row.accountText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _Meta(label: '剩余', value: remainingLabel),
                  _Meta(label: 'Auto', value: autoLabel),
                  _Meta(label: 'API', value: apiLabel),
                  _Meta(label: '总用量', value: totalLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          TextSpan(
            text: value,
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
}
