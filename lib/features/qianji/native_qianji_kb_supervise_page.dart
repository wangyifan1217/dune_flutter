import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import 'kb_supervise_models.dart';
import 'kb_supervise_service.dart';

const _themePurple = Color(0xFF7B5CD8);

/// NOVA · 知识库统计：按人统计知识库数量，部门筛选逻辑与会议监管一致。
class NativeQianjiKbSupervisePage extends StatefulWidget {
  const NativeQianjiKbSupervisePage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeQianjiKbSupervisePage> createState() =>
      _NativeQianjiKbSupervisePageState();
}

class _NativeQianjiKbSupervisePageState
    extends State<NativeQianjiKbSupervisePage> {
  late final KbSuperviseService _service =
      KbSuperviseService(session: widget.session);
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<KbSuperviseRow> _rows = const [];
  List<KbSuperviseDeptStat> _deptStats = const [];
  int? _selectedDepartmentId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _superviseAll = false;
  int _page = 0;
  int _totalFolders = 0;
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
      KbSuperviseDeptStatsResult? stats;
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
          _totalFolders = stats.totalFolders;
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
        _rows = <KbSuperviseRow>[..._rows, ...result.items];
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
              '知识库',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          if (_totalFolders > 0)
            Text(
              '合计 $_totalFolders',
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
                  count: _totalFolders,
                  selected: _selectedDepartmentId == null,
                  onTap: () => _selectDepartment(null),
                ),
                const SizedBox(width: 8),
                for (final d in _deptStats) ...[
                  _DeptChip(
                    label: d.departmentName,
                    count: d.folderCount,
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
              '暂无知识库数据',
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

  final KbSuperviseRow row;

  @override
  Widget build(BuildContext context) {
    final dept = row.departmentName.trim().isEmpty
        ? '未分配部门'
        : row.departmentName.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
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
                Text(
                  '${row.folderCount} 知识库',
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
              '$dept · ${row.documentCount} 文档',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}
