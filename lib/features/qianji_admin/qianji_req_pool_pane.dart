import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'qianji_admin_api.dart';

const _themePurple = Color(0xFF7B5CD8);

const _statusPending = 'pending';
const _statusDone = 'done';
const _statusRejected = 'rejected';
const _statusVoided = 'voided';

const _priorityHigh = 'high';
const _priorityMid = 'mid';
const _priorityLow = 'low';

enum _ReqPoolPage { list, entry, detail }

/// 需求任务池：列表 / 录入 / 详情（后端 API）。
class QianjiReqPoolPane extends StatefulWidget {
  const QianjiReqPoolPane({super.key, required this.session});

  final AuthSession session;

  @override
  State<QianjiReqPoolPane> createState() => _QianjiReqPoolPaneState();
}

class _QianjiReqPoolPaneState extends State<QianjiReqPoolPane> {
  late final QianjiAdminApi _api = QianjiAdminApi(widget.session);

  _ReqPoolPage _page = _ReqPoolPage.list;
  String _tab = _statusPending;
  String? _priorityFilter;
  final _search = TextEditingController();
  String _appliedQuery = '';

  List<QianjiRequirement> _items = const [];
  QianjiRequirementStats _stats = QianjiRequirementStats.empty;
  QianjiRequirement? _selected;
  List<QianjiProduct> _products = const [];

  bool _loading = true;
  String? _error;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadProducts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final list = await _api.listProducts();
      if (!mounted) return;
      setState(() => _products = list);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _appliedQuery.trim().isEmpty ? null : _appliedQuery.trim();
      final priority = _priorityFilter;
      final results = await Future.wait([
        _api.requirementStats(priority: priority, q: q),
        _api.listRequirements(status: _tab, priority: priority, q: q),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as QianjiRequirementStats;
        _items = results[1] as List<QianjiRequirement>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _applySearch() {
    final next = _search.text.trim();
    if (next == _appliedQuery && !_loading) {
      _load();
      return;
    }
    setState(() => _appliedQuery = next);
    _load();
  }

  void _clearSearchAndRefresh() {
    _search.clear();
    setState(() {
      _appliedQuery = '';
      _priorityFilter = null;
    });
    _load();
  }

  void _setTab(String status) {
    if (_tab == status) return;
    setState(() {
      _tab = status;
      _appliedQuery = _search.text.trim();
    });
    _load();
  }

  void _setPriority(String? priority) {
    if (_priorityFilter == priority) return;
    setState(() {
      _priorityFilter = priority;
      _appliedQuery = _search.text.trim();
    });
    _load();
  }

  void _openList() => setState(() {
        _page = _ReqPoolPage.list;
        _selected = null;
      });

  void _openEntry() => setState(() => _page = _ReqPoolPage.entry);

  void _openDetail(QianjiRequirement item) => setState(() {
        _selected = item;
        _page = _ReqPoolPage.detail;
      });

  Future<void> _submitEntry(Map<String, dynamic> body) async {
    setState(() => _mutating = true);
    try {
      await _api.createRequirement(body);
      if (!mounted) return;
      setState(() {
        _mutating = false;
        _tab = _statusPending;
        _page = _ReqPoolPage.list;
        _selected = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交至需求池')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e')),
      );
    }
  }

  Future<void> _markStatus(QianjiRequirement item, String status, {String? note}) async {
    setState(() => _mutating = true);
    try {
      await _api.updateRequirement(item.id, {
        'status': status,
        'note': note ?? '',
      });
      if (!mounted) return;
      setState(() {
        _mutating = false;
        _page = _ReqPoolPage.list;
        _selected = null;
        _tab = status;
      });
      final label = switch (status) {
        _statusDone => '已标记为已处理',
        _statusRejected => '已拒绝',
        _statusVoided => '已作废',
        _ => '已更新',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_page) {
      _ReqPoolPage.list => _ReqPoolListView(
          stats: _stats,
          tab: _tab,
          priorityFilter: _priorityFilter,
          searchController: _search,
          items: _items,
          loading: _loading,
          error: _error,
          onTab: _setTab,
          onPriority: _setPriority,
          onSearchSubmit: _applySearch,
          onClear: _clearSearchAndRefresh,
          onRefresh: _load,
          onEntry: _openEntry,
          onOpen: _openDetail,
        ),
      _ReqPoolPage.entry => _ReqEntryView(
          products: _products,
          submitting: _mutating,
          defaultSubmitter: (widget.session.displayName ?? '').trim().isNotEmpty
              ? widget.session.displayName!.trim()
              : '当前用户',
          onCancel: _openList,
          onSubmit: _submitEntry,
        ),
      _ReqPoolPage.detail => _ReqDetailView(
          item: _selected!,
          mutating: _mutating,
          onBack: _openList,
          onMark: _markStatus,
        ),
    };
  }
}

class _ReqPoolListView extends StatelessWidget {
  const _ReqPoolListView({
    required this.stats,
    required this.tab,
    required this.priorityFilter,
    required this.searchController,
    required this.items,
    required this.loading,
    required this.error,
    required this.onTab,
    required this.onPriority,
    required this.onSearchSubmit,
    required this.onClear,
    required this.onRefresh,
    required this.onEntry,
    required this.onOpen,
  });

  final QianjiRequirementStats stats;
  final String tab;
  final String? priorityFilter;
  final TextEditingController searchController;
  final List<QianjiRequirement> items;
  final bool loading;
  final String? error;
  final ValueChanged<String> onTab;
  final ValueChanged<String?> onPriority;
  final VoidCallback onSearchSubmit;
  final VoidCallback onClear;
  final VoidCallback onRefresh;
  final VoidCallback onEntry;
  final ValueChanged<QianjiRequirement> onOpen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          const Text(
            '人员需求录入入口 · 待处理 / 已处理 / 已拒绝 / 作废 · 指派接收人处理',
            style: TextStyle(fontSize: 13, color: DunesColors.text3, height: 1.3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ReqStatCard(
                  icon: Icons.inbox_outlined,
                  title: '待处理',
                  value: '${stats.pending}',
                  valueColor: _themePurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReqStatCard(
                  icon: Icons.check_circle_outline,
                  title: '已处理',
                  value: '${stats.done}',
                  valueColor: const Color(0xFF3CBFA9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReqStatCard(
                  icon: Icons.cancel_outlined,
                  title: '已拒绝',
                  value: '${stats.rejected}',
                  valueColor: const Color(0xFFE35D6A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReqStatCard(
                  icon: Icons.delete_outline,
                  title: '作废',
                  value: '${stats.voided}',
                  valueColor: DunesColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: '搜索说明 / 编号 / 提出人 / 接收人 / 平台等',
                      hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 13),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF5F6F8),
                      prefixIcon: const Icon(Icons.search, size: 20, color: DunesColors.text3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => onSearchSubmit(),
                  ),
                ),
                const SizedBox(width: 10),
                _WorkbenchFormDropdownInline<String?>(
                  label: priorityFilter == null ? '全部优先级' : _priorityText(priorityFilter!),
                  value: priorityFilter,
                  items: const [
                    (null, '全部优先级'),
                    (_priorityHigh, '高'),
                    (_priorityMid, '中'),
                    (_priorityLow, '低'),
                  ],
                  onChanged: onPriority,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '清除筛选',
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_rounded, color: DunesColors.text2),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, color: DunesColors.text2),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: onEntry,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('人员需求录入'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _themePurple,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 14, 0),
                  child: Row(
                    children: [
                      _ReqTab(
                        label: '待处理',
                        count: stats.pending,
                        selected: tab == _statusPending,
                        onTap: () => onTab(_statusPending),
                      ),
                      _ReqTab(
                        label: '已处理',
                        count: stats.done,
                        selected: tab == _statusDone,
                        onTap: () => onTab(_statusDone),
                      ),
                      _ReqTab(
                        label: '已拒绝',
                        count: stats.rejected,
                        selected: tab == _statusRejected,
                        onTap: () => onTab(_statusRejected),
                      ),
                      _ReqTab(
                        label: '作废',
                        count: stats.voided,
                        selected: tab == _statusVoided,
                        onTap: () => onTab(_statusVoided),
                      ),
                      const Spacer(),
                      const Text(
                        '指派给我的 · 按提出时间正序',
                        style: TextStyle(fontSize: 12, color: DunesColors.text3),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE8EAED)),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 56),
                    child: Center(child: CircularProgressIndicator(color: _themePurple)),
                  )
                else if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                        TextButton(onPressed: onRefresh, child: const Text('重试')),
                      ],
                    ),
                  )
                else if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      '暂无需求',
                      style: TextStyle(fontSize: 14, color: DunesColors.text3),
                    ),
                  )
                else
                  ...items.map((item) => _ReqRow(item: item, onOpen: () => onOpen(item))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReqStatCard extends StatelessWidget {
  const _ReqStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: DunesColors.text3),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReqTab extends StatelessWidget {
  const _ReqTab({
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
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? _themePurple : DunesColors.text3,
                  ),
                ),
                if (count > 0 && selected) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _themePurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _themePurple,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 28,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? _themePurple : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReqRow extends StatelessWidget {
  const _ReqRow({required this.item, required this.onOpen});

  final QianjiRequirement item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.assignedToMe && item.status == _statusPending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin, size: 12, color: _themePurple.withValues(alpha: 0.85)),
                          const SizedBox(width: 4),
                          Text(
                            '指派给我',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _themePurple.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 132,
              child: Text(
                item.code,
                style: const TextStyle(fontSize: 11, color: DunesColors.text3, fontFamily: 'monospace'),
              ),
            ),
            SizedBox(
              width: 56,
              child: Align(alignment: Alignment.centerLeft, child: _PriorityChip(item.priority)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Align(alignment: Alignment.centerLeft, child: _StatusChip(item.status)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: Text(item.submitter, style: const TextStyle(fontSize: 12, color: DunesColors.text2)),
            ),
            SizedBox(
              width: 56,
              child: Text(
                item.receiver,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: item.assignedToMe ? FontWeight.w600 : FontWeight.w400,
                  color: item.assignedToMe ? _themePurple : DunesColors.text2,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                _fmtDue(item.dueDate),
                style: const TextStyle(fontSize: 11, color: DunesColors.text3, fontFamily: 'monospace'),
              ),
            ),
            IconButton(
              tooltip: '查看详情',
              onPressed: onOpen,
              icon: const Icon(Icons.visibility_outlined, size: 18, color: DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReqEntryView extends StatefulWidget {
  const _ReqEntryView({
    required this.products,
    required this.submitting,
    required this.defaultSubmitter,
    required this.onCancel,
    required this.onSubmit,
  });

  final List<QianjiProduct> products;
  final bool submitting;
  final String defaultSubmitter;
  final VoidCallback onCancel;
  final Future<void> Function(Map<String, dynamic> body) onSubmit;

  @override
  State<_ReqEntryView> createState() => _ReqEntryViewState();
}

class _ReqEntryViewState extends State<_ReqEntryView> {
  late final TextEditingController _receiver;
  late final TextEditingController _summary;
  late final TextEditingController _background;
  late final TextEditingController _due;
  String _platform = '千机平台';
  String _product = '不关联';
  String _capability = '不关联';
  String _priority = _priorityMid;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _receiver = TextEditingController(text: '杨静');
    _summary = TextEditingController();
    _background = TextEditingController();
    _due = TextEditingController(text: '2026-08-31');
    _summary.addListener(() {
      if (_summaryError != null && _summary.text.trim().isNotEmpty) {
        setState(() => _summaryError = null);
      }
    });
  }

  @override
  void dispose() {
    _receiver.dispose();
    _summary.dispose();
    _background.dispose();
    _due.dispose();
    super.dispose();
  }

  List<String> get _platformOptions {
    final names = widget.products
        .where((p) => p.kind == 'platform')
        .map((p) => p.name)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return const ['千机平台', '灯塔经营分析', '不关联'];
    return [...names, '不关联'];
  }

  List<String> get _productOptions {
    final names = widget.products
        .where((p) => p.kind == 'product')
        .map((p) => p.name)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    return ['不关联', ...names];
  }

  List<String> get _capabilityOptions {
    final names = widget.products
        .where((p) => p.kind == 'capability')
        .map((p) => p.name)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) {
      return const ['不关联', '提案与任务协同', '产品能力图谱'];
    }
    return ['不关联', ...names];
  }

  String _assocValue(String raw) => raw == '不关联' ? '' : raw;

  Future<void> _submit() async {
    if (widget.submitting) return;
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      setState(() => _summaryError = '请填写需求说明');
      return;
    }
    await widget.onSubmit({
      'summary': summary,
      'background': _background.text.trim(),
      'platform': _assocValue(_platform),
      'product': _assocValue(_product),
      'capability': _assocValue(_capability),
      'receiver': _receiver.text.trim().isEmpty ? '杨静' : _receiver.text.trim(),
      'submitter': widget.defaultSubmitter,
      'priority': _priority,
      'dueDate': _due.text.trim().isEmpty ? null : _due.text.trim(),
      'assignedToMe': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '人员需求录入',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: DunesColors.text),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '提交至需求任务池 · 关联平台 / 产品 / 能力 · 编号由系统生成',
                      style: TextStyle(fontSize: 13, color: DunesColors.text3),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.submitting ? null : widget.onCancel,
                child: const Text('取消', style: TextStyle(color: DunesColors.text2)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _themePurple,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: widget.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('提交至需求池'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxWidth: 760),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledSelect(
                        label: '关联平台',
                        value: _platform,
                        items: _platformOptions,
                        onChanged: (v) => setState(() => _platform = v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _LabeledSelect(
                        label: '关联产品',
                        value: _productOptions.contains(_product) ? _product : '不关联',
                        items: _productOptions,
                        onChanged: (v) => setState(() => _product = v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _LabeledSelect(
                        label: '关联能力',
                        value: _capabilityOptions.contains(_capability) ? _capability : '不关联',
                        items: _capabilityOptions,
                        onChanged: (v) => setState(() => _capability = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _LabeledField(label: '需求接收人', controller: _receiver, hint: '接收人姓名')),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _LabeledPrioritySelect(
                        label: '需求优先级',
                        value: _priority,
                        onChanged: (v) => setState(() => _priority = v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: _LabeledField(label: '期望上线时间', controller: _due, hint: 'YYYY-MM-DD')),
                  ],
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: '需求说明',
                  controller: _summary,
                  hint: '简明描述需求目标与范围',
                  maxLines: 3,
                  required: true,
                  errorText: _summaryError,
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: '需求背景',
                  controller: _background,
                  hint: '补充背景、来源与必要性',
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReqDetailView extends StatefulWidget {
  const _ReqDetailView({
    required this.item,
    required this.mutating,
    required this.onBack,
    required this.onMark,
  });

  final QianjiRequirement item;
  final bool mutating;
  final VoidCallback onBack;
  final Future<void> Function(QianjiRequirement item, String status, {String? note}) onMark;

  @override
  State<_ReqDetailView> createState() => _ReqDetailViewState();
}

class _ReqDetailViewState extends State<_ReqDetailView> {
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.item.note);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _displayAssoc(String value) => value.trim().isEmpty ? '—' : value;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canAct = item.status == _statusPending && !widget.mutating;
    final proposal = item.proposalLabel.trim();
    final task = item.taskLabel.trim();
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '需求详情',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: DunesColors.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.code} · ${item.submitter}提出 · ${_fmtDateTime(item.submittedAt)}',
                      style: const TextStyle(fontSize: 13, color: DunesColors.text3),
                    ),
                  ],
                ),
              ),
              _StatusChip(item.status),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: widget.mutating ? null : widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('返回'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DunesColors.text2,
                  side: const BorderSide(color: Color(0xFFE8EAED)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (item.status == _statusPending) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canAct
                      ? () => widget.onMark(item, _statusDone, note: _note.text.trim())
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _themePurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: widget.mutating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('标记已处理'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: canAct
                      ? () => widget.onMark(item, _statusRejected, note: _note.text.trim())
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('拒绝'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: canAct
                      ? () => widget.onMark(item, _statusVoided, note: _note.text.trim())
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DunesColors.text2,
                    side: const BorderSide(color: Color(0xFFE8EAED)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('作废'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _DetailCard(
                      title: '需求信息',
                      icon: Icons.info_outline,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _AssocCell(label: '关联平台', value: _displayAssoc(item.platform))),
                              const SizedBox(width: 10),
                              Expanded(child: _AssocCell(label: '关联产品', value: _displayAssoc(item.product))),
                              const SizedBox(width: 10),
                              Expanded(child: _AssocCell(label: '关联能力', value: _displayAssoc(item.capability))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _Kv(label: '需求接收人', value: item.receiver, accent: true),
                          _Kv(label: '需求优先级', valueWidget: _PriorityChip(item.priority)),
                          _Kv(label: '期望上线时间', value: _fmtDue(item.dueDate)),
                          _Kv(label: '提出人', value: item.submitter),
                          _Kv(label: '提出时间', value: _fmtDateTime(item.submittedAt), mono: true),
                          _Kv(label: '需求说明', value: item.summary, multiline: true),
                          _Kv(
                            label: '需求背景',
                            value: item.background.trim().isEmpty ? '—' : item.background,
                            multiline: true,
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: '处理记录',
                      icon: Icons.history,
                      child: Column(
                        children: [
                          _Kv(label: '当前状态', valueWidget: _StatusChip(item.status)),
                          _Kv(
                            label: '说明',
                            value: item.note.isNotEmpty
                                ? item.note
                                : '标记已处理 / 拒绝 / 作废后将记录操作人与操作时间',
                            multiline: true,
                            last: true,
                            muted: item.note.isEmpty,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: '处理备注',
                      icon: Icons.chat_bubble_outline,
                      child: TextField(
                        controller: _note,
                        maxLines: 4,
                        enabled: canAct,
                        style: const TextStyle(fontSize: 13, color: DunesColors.text),
                        decoration: InputDecoration(
                          hintText: '选填 · 拒绝或作废时说明原因',
                          hintStyle: TextStyle(color: DunesColors.text3.withValues(alpha: 0.85)),
                          filled: true,
                          fillColor: const Color(0xFFF5F6F8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _DetailCard(
                      title: '关联提案',
                      icon: Icons.description_outlined,
                      child: proposal.isEmpty
                          ? const Text('暂无关联提案', style: TextStyle(fontSize: 13, color: DunesColors.text3))
                          : _SideLinkCard(
                              code: proposal,
                              name: '审批通过后需求将同步至版本记录；关联任务全部上线后自动标记为已上线',
                              chip: '迭代审批',
                              meta: item.status == _statusPending ? '审批中' : '已归档',
                            ),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: '关联任务',
                      icon: Icons.checklist_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (task.isNotEmpty) ...[
                            Text(
                              task,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.text,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: _themePurple.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    item.code,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _themePurple,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('本需求', style: TextStyle(fontSize: 12, color: DunesColors.text2)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const Text(
                            '提案审批填写时，在任务内容下通过「从需求池选择」关联；详情页只读展示。',
                            style: TextStyle(fontSize: 12, color: DunesColors.text3, height: 1.55),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: DunesColors.text3),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DunesColors.text),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EAED)),
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: child),
        ],
      ),
    );
  }
}

class _AssocCell extends StatelessWidget {
  const _AssocCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: DunesColors.text3)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DunesColors.text),
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({
    required this.label,
    this.value,
    this.valueWidget,
    this.accent = false,
    this.mono = false,
    this.multiline = false,
    this.last = false,
    this.muted = false,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool accent;
  final bool mono;
  final bool multiline;
  final bool last;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: Row(
        crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
          ),
          Expanded(
            child: valueWidget ??
                Text(
                  value ?? '—',
                  style: TextStyle(
                    fontSize: multiline ? 12.5 : 13,
                    height: multiline ? 1.55 : 1.3,
                    fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                    color: muted
                        ? DunesColors.text3
                        : accent
                            ? _themePurple
                            : DunesColors.text,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _SideLinkCard extends StatelessWidget {
  const _SideLinkCard({
    required this.code,
    required this.name,
    required this.chip,
    required this.meta,
  });

  final String code;
  final String name;
  final String chip;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _themePurple,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontSize: 12, color: DunesColors.text2, height: 1.45)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _themePurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chip,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _themePurple),
                ),
              ),
              const SizedBox(width: 8),
              Text(meta, style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip(this.priority);
  final String priority;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = switch (priority) {
      _priorityHigh => ('高', const Color(0xFFFAECE7), const Color(0xFF993C1D)),
      _priorityLow => ('低', const Color(0xFFF0F1F3), DunesColors.text2),
      _ => ('中', const Color(0xFFFAEEDA), const Color(0xFF7A4E0F)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = switch (status) {
      _statusDone => ('已处理', const Color(0xFFE1F5EE), const Color(0xFF085041)),
      _statusRejected => ('已拒绝', const Color(0xFFFAECE7), const Color(0xFF993C1D)),
      _statusVoided => ('作废', const Color(0xFFF0F1F3), DunesColors.text3),
      _ => ('待处理', _themePurple.withValues(alpha: 0.12), _themePurple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.required = false,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final bool required;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DunesColors.text2)),
            if (required)
              const Text(' *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFE35D6A))),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14, color: DunesColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: DunesColors.text3.withValues(alpha: 0.85)),
            filled: true,
            fillColor: hasError ? const Color(0xFFFFF1F2) : const Color(0xFFF5F6F8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: hasError ? const BorderSide(color: Color(0xFFE35D6A)) : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError ? const Color(0xFFE35D6A) : _themePurple.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: const TextStyle(fontSize: 12, color: Color(0xFFE35D6A))),
        ],
      ],
    );
  }
}

class _LabeledSelect extends StatelessWidget {
  const _LabeledSelect({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DunesColors.text2)),
        const SizedBox(height: 8),
        _WorkbenchFormDropdownInline<String>(
          label: value,
          value: value,
          items: [for (final e in items) (e, e)],
          onChanged: onChanged,
          fullWidth: true,
        ),
      ],
    );
  }
}

class _LabeledPrioritySelect extends StatelessWidget {
  const _LabeledPrioritySelect({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DunesColors.text2)),
        const SizedBox(height: 8),
        _WorkbenchFormDropdownInline<String>(
          label: _priorityText(value),
          value: value,
          items: const [
            (_priorityHigh, '高'),
            (_priorityMid, '中'),
            (_priorityLow, '低'),
          ],
          onChanged: onChanged,
          fullWidth: true,
        ),
      ],
    );
  }
}

/// 紧凑 / 全宽下拉（与工作台筛选风格一致）。
class _WorkbenchFormDropdownInline<T> extends StatelessWidget {
  const _WorkbenchFormDropdownInline({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.fullWidth = false,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      builder: (context, controller, child) {
        final open = controller.isOpen;
        return Material(
          color: open ? _themePurple.withValues(alpha: 0.08) : const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => open ? controller.close() : controller.open(),
            child: Container(
              width: fullWidth ? double.infinity : null,
              height: fullWidth ? 44 : null,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: fullWidth ? 0 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: open ? _themePurple.withValues(alpha: 0.35) : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                        color: open ? _themePurple : DunesColors.text,
                      ),
                    ),
                  ),
                  Icon(
                    open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: open ? _themePurple : DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: () => onChanged(item.$1),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (item.$1 == value) return _themePurple.withValues(alpha: 0.1);
                if (states.contains(WidgetState.hovered)) return const Color(0xFFF5F6F8);
                return Colors.transparent;
              }),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              minimumSize: const WidgetStatePropertyAll(Size(140, 40)),
            ),
            trailingIcon: item.$1 == value
                ? const Icon(Icons.check_rounded, size: 16, color: _themePurple)
                : null,
            child: Text(
              item.$2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: item.$1 == value ? FontWeight.w600 : FontWeight.w400,
                color: item.$1 == value ? _themePurple : DunesColors.text,
              ),
            ),
          ),
      ],
    );
  }
}

String _priorityText(String p) => switch (p) {
      _priorityHigh => '高',
      _priorityLow => '低',
      _ => '中',
    };

String _fmtDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

String _fmtDue(String? d) {
  if (d == null || d.trim().isEmpty) return '—';
  final parsed = DateTime.tryParse(d.trim());
  if (parsed != null) return _fmtDate(parsed);
  final raw = d.trim();
  return raw.length >= 10 ? raw.substring(0, 10) : raw;
}

String _fmtDateTime(DateTime d) {
  return '${_fmtDate(d)} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
