import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'fund_secondment_kanban.dart';
import 'fund_secondment_models.dart';
import 'fund_secondment_service.dart';

const _themePurple = Color(0xFF7B5CD8);

enum _SettledFilter { all, settled, open }

class NativeQianjiFundSecondmentPage extends StatefulWidget {
  const NativeQianjiFundSecondmentPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenDetail,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenDetail;

  @override
  State<NativeQianjiFundSecondmentPage> createState() =>
      _NativeQianjiFundSecondmentPageState();
}

class _NativeQianjiFundSecondmentPageState
    extends State<NativeQianjiFundSecondmentPage> {
  late final FundSecondmentService _service =
      FundSecondmentService(session: widget.session);
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<FundSecondmentRow> _rows = const [];
  FundSecondmentSummary _summary = const FundSecondmentSummary();
  _SettledFilter _filter = _SettledFilter.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _total = 0;
  static const int _pageSize = 20;
  String? _error;
  Timer? _keywordDebounce;

  bool? get _settledQuery {
    switch (_filter) {
      case _SettledFilter.all:
        return null;
      case _SettledFilter.settled:
        return true;
      case _SettledFilter.open:
        return false;
    }
  }

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

  Future<void> _setFilter(_SettledFilter next) async {
    if (_filter == next) return;
    setState(() => _filter = next);
    await _load(reset: true);
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
        settled: _settledQuery,
      );
      if (!mounted) return;
      setState(() {
        _rows = result.items;
        _summary = result.summary;
        _page = 0;
        _total = result.totalCount;
        _hasMore = result.items.length >= _pageSize &&
            result.items.length < result.totalCount;
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
        settled: _settledQuery,
      );
      if (!mounted) return;
      setState(() {
        _rows = <FundSecondmentRow>[..._rows, ...result.items];
        _page = nextPage;
        _hasMore = result.items.length >= _pageSize;
      });
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _amountText(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toStringAsFixed(2);
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
            if (!_loading && _error == null) ...[
              _buildSummaryBoard(),
              _buildFilterChips(),
            ],
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
              '资金借调',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextField(
        controller: _keywordCtrl,
        decoration: InputDecoration(
          hintText: '搜索主体 / 单据编号',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _keywordCtrl.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _keywordCtrl.clear();
                    unawaited(_load(reset: true));
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBoard() {
    return FundSecondmentKanban(
      summary: _summary,
      filterAll: _filter == _SettledFilter.all,
      filterSettled: _filter == _SettledFilter.settled,
      filterOpen: _filter == _SettledFilter.open,
      onFilterAll: () => unawaited(_setFilter(_SettledFilter.all)),
      onFilterSettled: () => unawaited(_setFilter(_SettledFilter.settled)),
      onFilterOpen: () => unawaited(_setFilter(_SettledFilter.open)),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _FilterChip(
            label: '全部',
            selected: _filter == _SettledFilter.all,
            onTap: () => unawaited(_setFilter(_SettledFilter.all)),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '已还清',
            selected: _filter == _SettledFilter.settled,
            onTap: () => unawaited(_setFilter(_SettledFilter.settled)),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '未还清',
            selected: _filter == _SettledFilter.open,
            onTap: () => unawaited(_setFilter(_SettledFilter.open)),
          ),
          const Spacer(),
          Text(
            '$_total 条',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
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
          SizedBox(height: 80),
          Center(
            child: Text(
              '暂无资金借调记录',
              style: TextStyle(color: DunesColors.text3, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      itemCount: _rows.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
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
        return _FundSecondmentCard(
          row: row,
          amountText: _amountText(row.borrowAmountWan),
          remainingText: row.isCleared ? '' : '剩 ${_amountText(row.remainingWan)}万',
          onTap: () => widget.onOpenDetail(row.id),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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

class _FundSecondmentCard extends StatelessWidget {
  const _FundSecondmentCard({
    required this.row,
    required this.amountText,
    required this.remainingText,
    required this.onTap,
  });

  final FundSecondmentRow row;
  final String amountText;
  final String remainingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(row);
    final borrow = row.borrowSubject.isEmpty ? '—' : row.borrowSubject;
    final pay = row.paySubject.isEmpty ? '—' : row.paySubject;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (row.code.isNotEmpty) ...[
                          Text(
                            row.code,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _themePurple,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: status.bg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            row.statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: status.fg,
                            ),
                          ),
                        ),
                        if (row.approvedAt.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              row.approvedAt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: DunesColors.text3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$borrow  →  $pay',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$amountText万',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: DunesColors.text,
                    ),
                  ),
                  if (remainingText.isNotEmpty)
                    Text(
                      remainingText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DunesColors.coral,
                      ),
                    ),
                ],
              ),
              const Icon(Icons.chevron_right, size: 18, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

({Color bg, Color fg}) _statusStyle(FundSecondmentRow row) {
  if (row.isCleared) {
    return (bg: DunesColors.greenSoft, fg: DunesColors.green);
  }
  if (row.repaidTotalWan > 0) {
    return (bg: DunesColors.amberSoft, fg: DunesColors.amber);
  }
  return (bg: DunesColors.coralSoft, fg: DunesColors.coral);
}
