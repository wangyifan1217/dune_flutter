import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import 'qianji_monthly_bill_api.dart';
import 'qianji_monthly_bill_demo.dart';

const _themePurple = Color(0xFF7B5CD8);
const _cardBorder = Color(0xFFE8EAED);
const _pageBg = Color(0xFFF5F6F8);

enum _BillFilter { all, channel, supply, overdue }

/// τ管理 · 月结老板看板。取数走 qianji-go → sel-mg。
class NativeQianjiMonthlyBillPage extends StatefulWidget {
  const NativeQianjiMonthlyBillPage({
    super.key,
    required this.onBack,
    this.session,
    this.loader,
  });

  final VoidCallback onBack;
  final AuthSession? session;
  final Future<MonthlyBillBoard> Function(String month)? loader;

  @override
  State<NativeQianjiMonthlyBillPage> createState() =>
      _NativeQianjiMonthlyBillPageState();
}

class _NativeQianjiMonthlyBillPageState
    extends State<NativeQianjiMonthlyBillPage> {
  late final List<String> _months;
  late String _month;
  String _side = 'receivable';
  _BillFilter _filter = _BillFilter.all;
  MonthlyBillBoard? _board;
  List<MonthlyBillRow> _items = const [];
  int _itemTotal = 0;
  bool _loading = true;
  bool _itemsLoading = false;
  String? _error;
  int _loadSeq = 0;
  int _itemSeq = 0;

  @override
  void initState() {
    super.initState();
    _months = monthlyBillMonthOptions();
    _month = monthlyBillDefaultMonth();
    if (!_months.contains(_month) && _months.isNotEmpty) {
      _month = _months.last;
    }
    _reload();
  }

  MonthlyBillBoard get _safeBoard =>
      _board ??
      MonthlyBillBoard(
        month: _month,
        from: '',
        to: '',
        receivable: monthlyBillKpiEmpty,
        payable: monthlyBillKpiEmpty,
      );

  List<MonthlyBillRow> get _visibleRows => _items;

  Future<void> _reload() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = widget.loader != null
          ? await widget.loader!(_month)
          : widget.session != null
          ? await QianjiMonthlyBillApi(widget.session!).board(month: _month)
          : monthlyBillDemoBoard(_month);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _board = board;
        _loading = false;
      });
      await _reloadItems();
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _reloadItems() async {
    final seq = ++_itemSeq;
    setState(() => _itemsLoading = true);
    try {
      if (widget.loader != null || widget.session == null) {
        final demo = monthlyBillDemoBoard(_month);
        final rows = [
          for (final r in demo.rows)
            if (r.side == _side)
              if (_filter == _BillFilter.all ||
                  (_filter == _BillFilter.channel && r.kind == 'channel') ||
                  (_filter == _BillFilter.supply && r.kind == 'supply') ||
                  (_filter == _BillFilter.overdue && r.isOverdue))
                r,
        ]..sort((a, b) {
          final od = b.overdueDays.compareTo(a.overdueDays);
          if (od != 0) return od;
          return b.unpaidYuan.compareTo(a.unpaidYuan);
        });
        if (!mounted || seq != _itemSeq) return;
        setState(() {
          _items = rows;
          _itemTotal = rows.length;
          _itemsLoading = false;
        });
        return;
      }
      final kind = switch (_filter) {
        _BillFilter.channel => 'channel',
        _BillFilter.supply => 'supply',
        _ => '',
      };
      final page = await QianjiMonthlyBillApi(widget.session!).items(
        month: _month,
        side: _side,
        kind: kind,
        overdue: _filter == _BillFilter.overdue,
      );
      if (!mounted || seq != _itemSeq) return;
      setState(() {
        _items = page.items;
        _itemTotal = page.total;
        _itemsLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _itemSeq) return;
      setState(() {
        _itemsLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _shiftMonth(int delta) {
    final i = _months.indexOf(_month);
    final next = (i + delta).clamp(0, _months.length - 1);
    if (next == i) return;
    setState(() {
      _month = _months[next];
      _filter = _BillFilter.all;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final board = _safeBoard;
    final kpi = _side == 'payable' ? board.payable : board.receivable;
    final payable = _side == 'payable';
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            if (_loading || _itemsLoading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  if (_error != null) ...[
                    _buildError(),
                    const SizedBox(height: 12),
                  ],
                  _buildMonthBar(board),
                  const SizedBox(height: 12),
                  _buildSideTabs(),
                  const SizedBox(height: 12),
                  _buildKpis(kpi, payable: payable),
                  const SizedBox(height: 12),
                  _buildSplit(kpi, payable: payable),
                  const SizedBox(height: 14),
                  _buildListHeader(kpi, payable: payable),
                  const SizedBox(height: 8),
                  _buildFilterChips(payable: payable),
                  const SizedBox(height: 8),
                  if (_loading && _visibleRows.isEmpty)
                    const SizedBox(height: 24)
                  else if (_visibleRows.isEmpty)
                    _emptyHint()
                  else ...[
                    for (final row in _visibleRows) ...[
                      _BillCard(
                        row: row,
                        payable: payable,
                        onTap: () => _openDetail(row),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_itemTotal > _items.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '仅列出前 ${_items.length} 张，其余 ${_itemTotal - _items.length} 张按逾期靠前省略。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DunesColors.text3,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final back = Material(
      color: Colors.transparent,
      child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onBack,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_ios_new, size: 14, color: DunesColors.text2),
            SizedBox(width: 2),
            Text(
              '饕',
              style: TextStyle(fontSize: 13, color: DunesColors.text2),
            ),
          ],
        ),
      ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
      child: Row(
        children: [
          back,
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '月结',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _themePurple,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.session == null
                  ? DunesColors.amberSoft
                  : const Color(0xFFF0EEF7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _loading ? '加载中' : (widget.session == null ? '样例' : '资管'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.session == null ? DunesColors.amber : _themePurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Material(
      color: DunesColors.coralSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _reload,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.coral.withValues(alpha: 0.35)),
          ),
          child: Text(
            '月结加载失败：$_error  点此重试',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: DunesColors.coral,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthBar(MonthlyBillBoard board) {
    final i = _months.indexOf(_month);
    final label = '${_month.substring(0, 4)}年${int.parse(_month.substring(5))}月';
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上一月',
                onPressed: i <= 0 ? null : () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一月',
                onPressed: i >= _months.length - 1 ? null : () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '窗口 ${board.from} ~ ${board.to}，周期重叠即计入。渠道应收、全部应付仅含已出账单；供给返利可跨月末。',
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: DunesColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideTabs() {
    return Row(
      children: [
        Expanded(child: _sideTab('receivable', '应收')),
        const SizedBox(width: 8),
        Expanded(child: _sideTab('payable', '应付')),
      ],
    );
  }

  Widget _sideTab(String side, String label) {
    final on = _side == side;
    return Material(
      color: on ? _themePurple : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            _side = side;
            _filter = _BillFilter.all;
          });
          _reloadItems();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? _themePurple : _cardBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : DunesColors.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpis(MonthlyBillKpi kpi, {required bool payable}) {
    final paidLabel = payable ? '已付' : '已回';
    final unpaidLabel = payable ? '未付' : '未回';
    final cells = [
      _KpiCell(label: '账单金额', value: monthlyBillFmtYuan(kpi.amountYuan)),
      _KpiCell(
        label: paidLabel,
        value: monthlyBillFmtYuan(kpi.paidYuan),
        valueColor: DunesColors.green,
      ),
      _KpiCell(
        label: unpaidLabel,
        value: monthlyBillFmtYuan(kpi.unpaidYuan),
        valueColor: kpi.unpaidYuan > 0 ? DunesColors.coral : DunesColors.green,
      ),
      _KpiCell(
        label: '逾期',
        value: '${kpi.overdueCount} 笔',
        sub: kpi.overdueCount > 0
            ? monthlyBillFmtYuan(kpi.overdueAmountYuan)
            : '无超期',
        valueColor: kpi.overdueCount > 0 ? DunesColors.amber : DunesColors.green,
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              payable ? '应付总览' : '应收总览',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DunesColors.text,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 560) {
                return Column(
                  children: [
                    Row(children: [cells[0], cells[1]]),
                    Row(children: [cells[2], cells[3]]),
                  ],
                );
              }
              return Row(children: cells);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Text(
              '对账 ${monthlyBillFmtYuan(kpi.reconcileYuan)} · 差异 ${monthlyBillFmtYuan(kpi.payDiffYuan)} · ${kpi.count} 张账单',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplit(MonthlyBillKpi kpi, {required bool payable}) {
    final total = kpi.channelYuan + kpi.supplyYuan;
    final channelPct = total <= 0 ? 0.0 : kpi.channelYuan / total;
    final supplyLabel = payable ? '供应商' : '供给';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            payable ? '渠道 / 供应商' : '渠道 / 供给',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: (channelPct * 1000).round().clamp(1, 999),
                    child: const ColoredBox(color: _themePurple),
                  ),
                  Expanded(
                    flex: ((1 - channelPct) * 1000).round().clamp(1, 999),
                    child: const ColoredBox(color: Color(0xFFC4B5FD)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SplitStat(
                  label: '渠道',
                  value: monthlyBillFmtYuan(kpi.channelYuan),
                ),
              ),
              Expanded(
                child: _SplitStat(
                  label: supplyLabel,
                  value: monthlyBillFmtYuan(kpi.supplyYuan),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(MonthlyBillKpi kpi, {required bool payable}) {
    return Row(
      children: [
        Text(
          payable ? '应付账单' : '应收账单',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DunesColors.text,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _itemTotal > 0 ? '共 $_itemTotal 张 · 逾期靠前 · 点开看 14 列' : '逾期靠前 · 点开看 14 列',
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
      ],
    );
  }

  Widget _buildFilterChips({required bool payable}) {
    final supply = payable ? '供应商' : '供给';
    return HorizontalDragScrollView(
      child: Row(
        children: [
          _chip(_BillFilter.all, '全部'),
          const SizedBox(width: 6),
          _chip(_BillFilter.channel, '渠道'),
          const SizedBox(width: 6),
          _chip(_BillFilter.supply, supply),
          const SizedBox(width: 6),
          _chip(_BillFilter.overdue, '逾期', key: const Key('monthly-bill-overdue')),
        ],
      ),
    );
  }

  Widget _chip(_BillFilter value, String label, {Key? key}) {
    final on = _filter == value;
    return Material(
      key: key,
      color: on ? _themePurple : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          setState(() => _filter = value);
          _reloadItems();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? _themePurple : _cardBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              color: on ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyHint() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: const Text(
        '这一筛选项下没有账单。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: DunesColors.text3),
      ),
    );
  }

  void _openDetail(MonthlyBillRow row) {
    final payable = row.side == 'payable';
    final paidLabel = payable ? '实际付款' : '实际回款';
    final diffLabel = payable ? '付款差异' : '回款差异';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final fields = <(String, String)>[
          ('账单周期', row.period),
          ('账单类型', row.typeName),
          ('账单金额', monthlyBillFmtYuan(row.amountYuan)),
          ('对账金额', monthlyBillFmtYuan(row.reconcileYuan)),
          ('对方主体', row.counterparty),
          ('我方主体', row.ourEntity),
          ('渠道/供给', monthlyBillKindLabel(row.kind, payable: payable)),
          ('应收/应付', monthlyBillSideLabel(row.side)),
          ('项目名称', row.projectName.isEmpty ? '—' : row.projectName),
          ('省份', row.province.isEmpty ? '—' : row.province),
          ('账期', '${row.termDays} 天'),
          ('逾期天数', '${row.overdueDays}'),
          (paidLabel, monthlyBillFmtYuan(row.paidYuan)),
          (diffLabel, monthlyBillFmtYuan(row.payDiffYuan)),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    row.billNo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final f in fields)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              f.$1,
                              style: const TextStyle(
                                fontSize: 12,
                                color: DunesColors.text3,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              f.$2,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: DunesColors.text,
                              ),
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
      },
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: valueColor ?? DunesColors.text,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(
                sub!,
                style: const TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitStat extends StatelessWidget {
  const _SplitStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DunesColors.text,
          ),
        ),
      ],
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.row,
    required this.payable,
    required this.onTap,
  });

  final MonthlyBillRow row;
  final bool payable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = monthlyBillKindLabel(row.kind, payable: payable);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EEF7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      kind,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _themePurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.typeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  if (row.isOverdue)
                    Text(
                      '逾期 ${row.overdueDays} 天',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.coral,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                row.counterparty,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: DunesColors.text2),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    monthlyBillFmtYuan(row.amountYuan),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${payable ? '已付' : '已回'} ${monthlyBillFmtYuan(row.paidYuan)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    row.billNo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
