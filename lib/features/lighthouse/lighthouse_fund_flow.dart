part of 'lighthouse_zg.dart';

// ════════════════════════════════════════════════════════════════════════
// 资管 · 资金流水（2026-11-04）
//
//   数据：资管 /out/lighthouse/flow-category（日 / 月快照）与 fund-transfer（按月现算 + 明细），
//   后端代理 /lighthouse/fund-flow/category | transfer | transfer-detail。金额是元。
//
//   两块：
//     · 流水分类：钱从哪来、到哪去。二级分类净额为正的进左边、为负的进右边，
//       中间是资金池；流出多于流入时左边补「动用存量」，反之右边补「净留存」。
//       石油项目行（OIL_PROJECT）只作「其中」，不进图、不往上加。没有快照 = 未生成，不当 0。
//     · 资金调动：钱在谁的户上（账号属性）→ 实际属于谁（资金属性）。两者不同 = 跨板块。
//       只统计两个属性都解析得出的子流水。
// ════════════════════════════════════════════════════════════════════════

const _kFlIn = Color(0xFF9C82E6);
const _kFlOut = Color(0xFFE0A877);
const _kFlCross = Color(0xFF7B5CD8);
const _kFlSelf = Color(0xFFDCD5EA);

class LhFlowNode {
  LhFlowNode.fromJson(Map<String, dynamic> j)
    : name = _fpStr(j['name']),
      net = _fpNum(j['netYuan']) ?? 0,
      kind = _fpStr(j['amountKind']),
      children = [for (final c in _fpList(j['children'])) LhFlowNode.fromJson(c)];

  final String name;
  final double net;
  final String kind;
  final List<LhFlowNode> children;

  bool get isOilSegment => kind == 'OIL_SEGMENT';
  bool get isOilProject => kind == 'OIL_PROJECT';
}

class LhFlowCategory {
  LhFlowCategory.fromJson(Map<String, dynamic> j)
    : restricted = j['restricted'] == true,
      unavailable = j['unavailable'] == true,
      fixture = j['fixture'] == true,
      period = _fpStr(j['period']),
      grain = _fpStr(j['grain']),
      generated = j['generated'] == true,
      net = _fpNum(j['netInflowYuan']) ?? 0,
      categories = [for (final c in _fpList(j['categories'])) LhFlowNode.fromJson(c)];

  final bool restricted;
  final bool unavailable;
  final bool fixture;
  final String period;
  final String grain;
  final bool generated;
  final double net;
  final List<LhFlowNode> categories;

  /// 进图的二级行：(一级分类, 行)。石油项目不进。
  List<(String, LhFlowNode)> get items => [
    for (final c in categories)
      for (final ch in c.children)
        if (!ch.isOilProject && ch.net.abs() >= 0.5) (c.name, ch),
  ];

  double get inflow => items.where((e) => e.$2.net > 0).fold<double>(0, (a, e) => a + e.$2.net);
  double get outflow => items.where((e) => e.$2.net < 0).fold<double>(0, (a, e) => a - e.$2.net);

  /// 流入覆盖流出（流入 ÷ 流出）。没有流出为 null。
  double? get coverage => outflow > 0 ? inflow / outflow : null;
}

class LhTransferRow {
  LhTransferRow.fromJson(Map<String, dynamic> j)
    : acct = _fpStr(j['accountAttr']),
      fund = _fpStr(j['fundAttr']),
      income = _fpNum(j['income']) ?? 0,
      expense = _fpNum(j['expense']) ?? 0,
      net = _fpNum(j['net']) ?? ((_fpNum(j['income']) ?? 0) - (_fpNum(j['expense']) ?? 0));

  final String acct;
  final String fund;
  final double income;
  final double expense;
  final double net;

  bool get cross => acct != fund;
  double get volume => income + expense;
}

class LhTransfer {
  LhTransfer.fromJson(Map<String, dynamic> j)
    : restricted = j['restricted'] == true,
      unavailable = j['unavailable'] == true,
      fixture = j['fixture'] == true,
      yearMonth = _fpStr(j['yearMonth']),
      rows = [for (final r in _fpList(j['rows'])) LhTransferRow.fromJson(r)],
      incomeTotal = _fpNum(j['incomeTotal']) ?? 0,
      expenseTotal = _fpNum(j['expenseTotal']) ?? 0;

  final bool restricted;
  final bool unavailable;
  final bool fixture;
  final String yearMonth;
  final List<LhTransferRow> rows;
  final double incomeTotal;
  final double expenseTotal;

  double get volume => rows.fold<double>(0, (a, r) => a + r.volume);
  double get crossVolume => rows.where((r) => r.cross).fold<double>(0, (a, r) => a + r.volume);
  double? get crossShare => volume > 0 ? crossVolume / volume : null;
}

/// 进图的一侧：小额（< 4%）合并成一条「其他 · n 项」，只有一条时保留原名，图上不挤。
List<(String, String, double)> _flowSide(List<(String, LhFlowNode)> items, bool positive) {
  final side = items.where((e) => positive ? e.$2.net > 0 : e.$2.net < 0).toList();
  final total = side.fold<double>(0, (a, e) => a + e.$2.net.abs());
  final big = <(String, String, double)>[];
  final small = <(String, String, double)>[];
  for (final e in side) {
    final v = e.$2.net.abs();
    final row = (e.$2.name, e.$1, v);
    if (total > 0 && v / total < 0.04 && side.length > 3) {
      small.add(row);
    } else {
      big.add(row);
    }
  }
  if (small.length == 1) {
    big.add(small.first);
  } else if (small.isNotEmpty) {
    final cats = small.map((e) => e.$2).toSet();
    big.add(('其他 ${small.length} 项', cats.length == 1 ? cats.first : '${cats.length} 类', small.fold<double>(0, (a, e) => a + e.$3)));
  }
  big.sort((a, b) => b.$3.compareTo(a.$3));
  return big;
}

Widget _flowSankey(BuildContext context, LhFlowCategory d, {required String pool}) {
  final ins = _flowSide(d.items, true);
  final outs = _flowSide(d.items, false);
  final left = <_SkNode>[
    for (var i = 0; i < ins.length; i++) _SkNode('i$i', ins[i].$1, _wu(ins[i].$3), ins[i].$3, _kDeep),
  ];
  final right = <_SkNode>[
    for (var i = 0; i < outs.length; i++) _SkNode('o$i', outs[i].$1, '${_wu(outs[i].$3)} · ${outs[i].$2}', outs[i].$3, _kDeep),
  ];
  final links = <_SkLink>[
    for (var i = 0; i < ins.length; i++) _SkLink('i$i', 'pool', ins[i].$3, _kFlIn, 0.55),
    for (var i = 0; i < outs.length; i++) _SkLink('pool', 'o$i', outs[i].$3, _kFlOut, 0.6),
  ];
  final gap = d.outflow - d.inflow;
  if (gap > 0.5) {
    left.add(_SkNode('bal', '动用存量', _wu(gap), gap, _kFpWarn, dashed: true));
    links.add(_SkLink('bal', 'pool', gap, _kFpWarn, 0.3));
  } else if (gap < -0.5) {
    right.add(_SkNode('bal', '净留存', _wu(-gap), -gap, _kFlCross, dashed: true));
    links.add(_SkLink('pool', 'bal', -gap, _kFlCross, 0.3));
  }
  if (left.isEmpty || right.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text('这一期没有收付', textAlign: TextAlign.center, style: _sans(context, size: 11.5, color: _kInk2)),
    );
  }
  final poolV = math.max(d.inflow, d.outflow);
  final n = math.max(left.length, right.length);
  return _SkChart(
    height: 64.0 + 38.0 * n,
    dataKey: Object.hashAll([d.period, for (final l in links) l.v]),
    builder: (t) => _SkPainter(
        t: t,
        cols: [
          left,
          [_SkNode('pool', pool, _wu(poolV), poolV, _kInk)],
          right,
        ],
        links: links,
        label: _sans(context, size: 11, weight: FontWeight.w600),
        sub: _mono(context, size: 9.5, color: _kMute),
        halo: _bg(context, Colors.white),
        resolve: (c) => _fg(context, c),
        midLabelTop: true,
      ),
  );
}

// ═════════════════════════════ 页面 ═════════════════════════════

class LighthouseFundFlowPage extends StatefulWidget {
  const LighthouseFundFlowPage({super.key, required this.service, required this.session, this.initialMonth, this.initialTransfer});

  final LighthouseService service;
  final AuthSession session;
  final LhFlowCategory? initialMonth;
  final LhTransfer? initialTransfer;

  @override
  State<LighthouseFundFlowPage> createState() => _FundFlowPageState();
}

class _FundFlowPageState extends State<LighthouseFundFlowPage> {
  late DateTime _month;
  int _tab = 0; // 0 流水分类 · 1 资金调动
  bool _byDay = false;
  late DateTime _day;
  LhFlowCategory? _flow;
  String? _flowError;
  bool _flowLoading = true;
  LhTransfer? _transfer;
  String? _transferError;
  bool _transferLoading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _day = DateTime(now.year, now.month, now.day);
    if (widget.initialMonth != null && widget.initialMonth!.period == _fpMonthParam(_month)) {
      _flow = widget.initialMonth;
      _flowLoading = false;
    }
    if (widget.initialTransfer != null && widget.initialTransfer!.yearMonth == _fpMonthParam(_month)) {
      _transfer = widget.initialTransfer;
      _transferLoading = false;
    }
    unawaited(_reload());
  }

  String get _period => _byDay
      ? '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}'
      : _fpMonthParam(_month);

  Future<void> _reload() async {
    await Future.wait([_fetchFlow(), _fetchTransfer()]);
  }

  Future<void> _fetchFlow() async {
    final p = _period;
    try {
      final data = await widget.service.fetchFlowCategory(period: p);
      if (!mounted || p != _period) return;
      setState(() {
        _flow = LhFlowCategory.fromJson(data);
        _flowError = null;
        _flowLoading = false;
      });
    } catch (e) {
      if (!mounted || p != _period) return;
      setState(() {
        _flowError = '$e'.replaceFirst('Exception: ', '');
        _flowLoading = false;
      });
    }
  }

  Future<void> _fetchTransfer() async {
    final m = _fpMonthParam(_month);
    try {
      final data = await widget.service.fetchFundTransfer(yearMonth: m);
      if (!mounted || m != _fpMonthParam(_month)) return;
      setState(() {
        _transfer = LhTransfer.fromJson(data);
        _transferError = null;
        _transferLoading = false;
      });
    } catch (e) {
      if (!mounted || m != _fpMonthParam(_month)) return;
      setState(() {
        _transferError = '$e'.replaceFirst('Exception: ', '');
        _transferLoading = false;
      });
    }
  }

  void _setPeriod({DateTime? month, bool? byDay, DateTime? day}) {
    setState(() {
      if (month != null) {
        _month = month;
        final now = DateTime.now();
        final last = DateTime(month.year, month.month + 1, 0);
        _day = month.year == now.year && month.month == now.month ? DateTime(now.year, now.month, now.day) : last;
        _transfer = null;
        _transferLoading = true;
      }
      if (byDay != null) _byDay = byDay;
      if (day != null) _day = day;
      _flow = null;
      _flowLoading = true;
    });
    unawaited(_fetchFlow());
    if (month != null) unawaited(_fetchTransfer());
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = [for (var i = 0; i >= -11; i--) DateTime(now.year, now.month + i)];
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: _bg(context, Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            for (final m in months)
              ListTile(
                dense: true,
                title: Text(
                  '${m.year} 年 ${m.month} 月',
                  style: _sans(ctx, size: 12.5, weight: m == _month ? FontWeight.w700 : FontWeight.w400, color: m == _month ? _kDeep : _kInk),
                ),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _month || !mounted) return;
    _setPeriod(month: picked);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Row(
        children: [
          _chip(context, '流水分类', _tab == 0, () => setState(() => _tab = 0)),
          const SizedBox(width: 6),
          _chip(context, '资金调动', _tab == 1, () => setState(() => _tab = 1)),
          const Spacer(),
          if ((_flow?.fixture ?? false) || (_transfer?.fixture ?? false)) _tag(context, '样例数据', _kFpWarn, _kFpWarnSoft),
        ],
      ),
      const SizedBox(height: 10),
      if (_tab == 0) ..._flowTab(context) else ..._transferTab(context),
    ];
    return _scaffold(
      context,
      onRefresh: _reload,
      header: _pageHeader(
        context,
        '资金流水',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _visButton(
              context,
              widget.service,
              'fund_flow',
              () => unawaited(
                _openVisibility(context, service: widget.service, session: widget.session, module: 'fund_flow', title: '资管 · 资金流水'),
              ),
            ),
            const SizedBox(width: 8),
            _dateIsland(context, '月份', _fpMonthParam(_month), _pickMonth),
          ],
        ),
      ),
      children: children,
    );
  }

  // ── 流水分类 ───────────────────────────────────────────────────────────

  List<Widget> _flowTab(BuildContext context) {
    final now = DateTime.now();
    final last = DateTime(_month.year, _month.month + 1, 0);
    final lastDay = _month.year == now.year && _month.month == now.month ? now.day : last.day;
    final days = [for (var d = lastDay; d >= 1; d--) DateTime(_month.year, _month.month, d)];
    final d = _flow;
    final out = <Widget>[
      Row(
        children: [
          _chip(context, '月', !_byDay, () => _setPeriod(byDay: false)),
          const SizedBox(width: 6),
          _chip(context, '日', _byDay, () => _setPeriod(byDay: true)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _byDay ? '单日快照；没生成的日子不当 0' : '该月每日快照相加',
              style: _sans(context, size: 10.5, color: _kInk2),
            ),
          ),
        ],
      ),
      if (_byDay) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final x in days) ...[
                _chip(context, _fpMd(x), x == _day, () => _setPeriod(day: x)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 10),
    ];
    if (_flowLoading && d == null) {
      out.add(_loadingBox(context));
      return out;
    }
    if (d == null) {
      out.add(_statusBox(context, _flowError ?? '暂无数据', onRetry: _fetchFlow));
      return out;
    }
    if (d.restricted) return out..add(_statusBox(context, '资金流水是全公司数据，当前账号暂无权限查看'));
    if (d.unavailable) return out..add(_statusBox(context, '资管资金流水接口未配置'));
    if (!d.generated) {
      return out
        ..add(_statusBox(context, _byDay ? '${_fpMd(_day)} 的流水分类快照还没生成（管理端补跑后才有）' : '该月还没有任何一天生成快照'));
    }
    out
      ..add(
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: _cardDeco(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHead(
                context,
                icon: Icons.waves_rounded,
                title: '钱从哪来，到哪去',
                chip: _byDay ? _fpMd(_day) : '${_month.month} 月',
                trailing: Text(
                  _swu(d.net),
                  style: _mono(context, size: 14, weight: FontWeight.w700, color: d.net < 0 ? _kFpOut : _kFpIn),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  '流入 ${_wu(d.inflow)} · 流出 ${_wu(d.outflow)}',
                  style: _sans(context, size: 10.5, color: _kInk2),
                ),
              ),
              const SizedBox(height: 8),
              _flowSankey(context, d, pool: _byDay ? '当日资金池' : '本月资金池'),
            ],
          ),
        ),
      )
      ..add(const SizedBox(height: 10))
      ..add(_treeCard(context, d));
    return out;
  }

  Widget _treeCard(BuildContext context, LhFlowCategory d) {
    final maxAbs = [
      for (final c in d.categories) ...[c.net.abs(), for (final ch in c.children) ch.net.abs()],
    ].fold<double>(1, (a, b) => b > a ? b : a);
    Widget bar(double v, {bool muted = false}) => LayoutBuilder(
      builder: (context, cons) {
        final half = cons.maxWidth / 2;
        final w = half * (v.abs() / maxAbs);
        final c = muted ? _kMute : (v >= 0 ? _kFpIn : _kFpOut);
        return SizedBox(
          height: 8,
          child: Stack(
            children: [
              Positioned(left: half - 0.5, top: -2, bottom: -2, child: Container(width: 1, color: _ln(context, _kEdge))),
              Positioned(
                left: v >= 0 ? half : half - w,
                top: 0,
                child: Container(
                  width: w,
                  height: 8,
                  decoration: BoxDecoration(color: _fg(context, c).withAlpha(muted ? 90 : 200), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ),
        );
      },
    );
    Widget row(String name, double v, {int depth = 0, String? tag, bool muted = false, bool bold = false}) => Padding(
      padding: EdgeInsets.fromLTRB(depth * 14.0, 6, 0, 6),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, size: bold ? 12 : 11, weight: bold ? FontWeight.w700 : FontWeight.w500, color: muted ? _kInk2 : _kInk),
                  ),
                ),
                if (tag != null) ...[const SizedBox(width: 5), _tag(context, tag, muted ? _kInk2 : _kFin, muted ? _kGreySoft : _kFinSoft)],
              ],
            ),
          ),
          Expanded(flex: 4, child: bar(v, muted: muted)),
          SizedBox(
            width: 78,
            child: Text(
              v.abs() < 0.5 ? '0.00万' : _swu(v),
              textAlign: TextAlign.right,
              style: _mono(context, size: 10.5, weight: bold ? FontWeight.w700 : FontWeight.w500, color: muted ? _kMute : (v < 0 ? _kFpOut : _kFpIn)),
            ),
          ),
        ],
      ),
    );
    final rows = <Widget>[];
    for (final c in d.categories) {
      rows.add(
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: _bg(context, _kMist), borderRadius: BorderRadius.circular(9)),
          child: row(c.name, c.net, bold: true),
        ),
      );
      if (c.children.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 0, 2),
          child: Text('没有明细', style: _sans(context, size: 10, color: _kMute)),
        ));
      }
      for (final ch in c.children) {
        rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: row(ch.name, ch.net, depth: 1, tag: ch.isOilSegment ? '石油板块' : null)));
        for (final p in ch.children) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: row('其中 · ${p.name}', p.net, depth: 2, tag: '不计入合计', muted: true),
          ));
        }
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(context, icon: Icons.account_tree_outlined, title: '分类明细'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text('一级固定 4 类 · 经营活动 = 普通项目 + 两个石油板块', style: _sans(context, size: 10.5, color: _kInk2)),
          ),
          ...rows,
        ],
      ),
    );
  }

  // ── 资金调动 ───────────────────────────────────────────────────────────

  List<Widget> _transferTab(BuildContext context) {
    final t = _transfer;
    if (_transferLoading && t == null) return [_loadingBox(context)];
    if (t == null) return [_statusBox(context, _transferError ?? '暂无数据', onRetry: _fetchTransfer)];
    if (t.restricted) return [_statusBox(context, '资金流水是全公司数据，当前账号暂无权限查看')];
    if (t.unavailable) return [_statusBox(context, '资管资金调动接口未配置')];
    if (t.rows.isEmpty) return [_statusBox(context, '${_month.month} 月还没有属性都解析得出的流水')];
    final accts = <String>[for (final r in t.rows) r.acct].toSet().toList();
    final funds = <String>[for (final r in t.rows) r.fund].toSet().toList();
    double sumA(String a) => t.rows.where((r) => r.acct == a).fold<double>(0, (x, r) => x + r.volume);
    double sumF(String f) => t.rows.where((r) => r.fund == f).fold<double>(0, (x, r) => x + r.volume);
    final left = [for (var i = 0; i < accts.length; i++) _SkNode('a$i', '${accts[i]}户', _wu(sumA(accts[i])), sumA(accts[i]), _kDeep)];
    final right = [for (var i = 0; i < funds.length; i++) _SkNode('f$i', funds[i], _wu(sumF(funds[i])), sumF(funds[i]), _kDeep)];
    final links = <_SkLink>[
      for (final r in t.rows)
        if (r.volume > 0)
          _SkLink('a${accts.indexOf(r.acct)}', 'f${funds.indexOf(r.fund)}', r.volume, r.cross ? _kFlCross : _kFlSelf, r.cross ? 0.75 : 0.6),
    ];
    final share = t.crossShare;
    final sorted = [...t.rows]..sort((a, b) {
      if (a.cross != b.cross) return a.cross ? -1 : 1;
      return b.volume.compareTo(a.volume);
    });
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: _cardDeco(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(
              context,
              icon: Icons.swap_calls_rounded,
              title: '钱在谁的户上 → 实际属于谁',
              trailing: Text(
                share == null ? '—' : '${(share * 100).toStringAsFixed(1)}%',
                style: _mono(context, size: 14, weight: FontWeight.w700, color: _kFlCross),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                '${_month.month} 月发生额（收 + 支）${_wu(t.volume)} · 跨板块 ${_wu(t.crossVolume)}',
                style: _sans(context, size: 10.5, color: _kInk2),
              ),
            ),
            const SizedBox(height: 8),
            _SkChart(
              height: 56.0 + 40.0 * math.max(left.length, right.length),
              dataKey: Object.hashAll([t.yearMonth, for (final l in links) l.v]),
              builder: (p) => _SkPainter(
                t: p,
                cols: [left, right],
                links: links,
                label: _sans(context, size: 11, weight: FontWeight.w600),
                sub: _mono(context, size: 9.5, color: _kMute),
                halo: _bg(context, Colors.white),
                resolve: (c) => _fg(context, c),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              children: [
                _flLegend(context, '本板块自用', _kFlSelf),
                _flLegend(context, '跨板块调动', _kFlCross),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: _cardDeco(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(context, icon: Icons.list_alt_rounded, title: '账号属性 × 资金属性', chip: '${t.rows.length} 组'),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text('跨板块在前 · 点一组看子流水', style: _sans(context, size: 10.5, color: _kInk2)),
            ),
            const SizedBox(height: 6),
            for (final r in sorted) _transferRow(context, r),
            const SizedBox(height: 6),
            Text(
              '只统计账号属性和资金属性都解析得出的子流水，行数会少于当月全部流水；资金属性取辅助备注 → 项目映射 → 三级分类映射。',
              style: _sans(context, size: 9.5, color: _kMute, height: 1.5),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _flLegend(BuildContext context, String text, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: 8, decoration: BoxDecoration(color: _fg(context, c), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(text, style: _sans(context, size: 10, color: _kInk2)),
    ],
  );

  Widget _transferRow(BuildContext context, LhTransferRow r) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_openDetail(r)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.6))),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.acct}户 → ${r.fund}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, size: 11.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  _tag(context, r.cross ? '跨板块' : '本板块', r.cross ? _kFlCross : _kInk2, r.cross ? _kLavender : _kGreySoft),
                ],
              ),
            ),
            Expanded(flex: 4, child: _flMini(context, '收入', _wu(r.income), _kFpIn)),
            Expanded(flex: 4, child: _flMini(context, '支出', _wu(r.expense), _kFpOut)),
            Expanded(flex: 4, child: _flMini(context, '净额', _swu(r.net), r.net < 0 ? _kFpOut : _kInk)),
            Icon(Icons.chevron_right_rounded, size: 16, color: _fg(context, _kMute)),
          ],
        ),
      ),
    );
  }

  Widget _flMini(BuildContext context, String label, String value, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: _sans(context, size: 9, color: _kMute)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(value, maxLines: 1, style: _mono(context, size: 10.5, weight: FontWeight.w600, color: c)),
      ),
    ],
  );

  Future<void> _openDetail(LhTransferRow r) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg(context, _kBg),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _TransferDetailSheet(service: widget.service, yearMonth: _fpMonthParam(_month), row: r),
      ),
    );
  }
}

class _TransferDetailSheet extends StatefulWidget {
  const _TransferDetailSheet({required this.service, required this.yearMonth, required this.row});

  final LighthouseService service;
  final String yearMonth;
  final LhTransferRow row;

  @override
  State<_TransferDetailSheet> createState() => _TransferDetailSheetState();
}

class _TransferDetailSheetState extends State<_TransferDetailSheet> {
  String _dir = 'ALL';
  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    final dir = _dir;
    setState(() => _loading = true);
    try {
      final data = await widget.service.fetchFundTransferDetail(
        yearMonth: widget.yearMonth,
        accountAttr: widget.row.acct,
        fundAttr: widget.row.fund,
        direction: dir,
      );
      if (!mounted || dir != _dir) return;
      setState(() {
        _rows = _fpList(data['rows']);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || dir != _dir) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final rows = _rows ?? const <Map<String, dynamic>>[];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.acct}户 → ${r.fund}', style: _sans(context, size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${widget.yearMonth} · 收入 ${_wu(r.income)} · 支出 ${_wu(r.expense)}',
                  style: _mono(context, size: 10.5, color: _kInk2),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final (code, label) in const [('ALL', '全部'), ('IN', '收入'), ('OUT', '支出')]) ...[
                      _chip(context, label, _dir == code, () {
                        if (_dir == code) return;
                        setState(() => _dir = code);
                        unawaited(_fetch());
                      }),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _rows == null
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : _error != null && _rows == null
                ? Center(child: Text(_error!, style: _sans(context, size: 12, color: _kInk2)))
                : rows.isEmpty
                ? Center(child: Text('没有子流水', style: _sans(context, size: 12, color: _kInk2)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => _detailCard(context, rows[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detailCard(BuildContext context, Map<String, dynamic> x) {
    final inc = _fpNum(x['income']) ?? 0;
    final exp = _fpNum(x['expense']) ?? 0;
    final isIn = inc > 0;
    final line2 = [_fpStr(x['project']), _fpStr(x['categoryLevelThree'])].where((e) => e.isNotEmpty).join(' · ');
    final line3 = [_fpStr(x['payeePayer']), _fpStr(x['summary'])].where((e) => e.isNotEmpty).join(' · ');
    final aux = _fpStr(x['auxRemark']);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDeco(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_fpStr(x['flowDate']), style: _mono(context, size: 11, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              _tag(context, isIn ? '收入' : '支出', isIn ? _kFpIn : _kFpOut, isIn ? _kLavender : _kFpOutSoft),
              const Spacer(),
              Text(
                isIn ? '+${_wu(inc)}' : '−${_wu(exp)}',
                style: _mono(context, size: 12, weight: FontWeight.w700, color: isIn ? _kFpIn : _kFpOut),
              ),
            ],
          ),
          if (line2.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 11, weight: FontWeight.w600)),
          ],
          if (line3.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(line3, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: _kInk2)),
          ],
          const SizedBox(height: 2),
          Text(
            [
              if (_fpStr(x['accountNo']).isNotEmpty) '本方 ${_fpStr(x['accountNo'])}',
              if (aux.isNotEmpty) aux,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 9.5, color: _kMute),
          ),
        ],
      ),
    );
  }
}
