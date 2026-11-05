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
//     · 资金调动：账号属性 → 资金属性（都按接口原值显示）。两者不同 = 跨板块。
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

Widget _flowSankey(
  BuildContext context,
  LhFlowCategory d, {
  required String pool,
  String? selected,
  ValueChanged<String?>? onSelect,
}) {
  final ins = _flowSide(d.items, true);
  final outs = _flowSide(d.items, false);
  final left = <_SkNode>[
    for (var i = 0; i < ins.length; i++)
      _SkNode('i$i', ins[i].$1, _wu(ins[i].$3), ins[i].$3, _kDeep, share: _skShare('本期流入', ins[i].$3, d.inflow)),
  ];
  final right = <_SkNode>[
    for (var i = 0; i < outs.length; i++)
      _SkNode('o$i', outs[i].$1, '${_wu(outs[i].$3)} · ${outs[i].$2}', outs[i].$3, _kDeep, share: _skShare('本期流出', outs[i].$3, d.outflow)),
  ];
  final links = <_SkLink>[
    for (var i = 0; i < ins.length; i++) _SkLink('i$i', 'pool', ins[i].$3, _kFlIn, 0.55),
    for (var i = 0; i < outs.length; i++) _SkLink('pool', 'o$i', outs[i].$3, _kFlOut, 0.6),
  ];
  final gap = d.outflow - d.inflow;
  if (gap > 0.5) {
    left.add(_SkNode('bal', '动用存量', _wu(gap), gap, _kFpWarn, dashed: true, share: _skShare('本期流出', gap, d.outflow)));
    links.add(_SkLink('bal', 'pool', gap, _kFpWarn, 0.3));
  } else if (gap < -0.5) {
    right.add(_SkNode('bal', '净留存', _wu(-gap), -gap, _kFlCross, dashed: true, share: _skShare('本期流入', -gap, d.inflow)));
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
  final cb = onSelect;
  final cols = [
    left,
    [_SkNode('pool', pool, _wu(poolV), poolV, _kInk)],
    right,
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SkChart(
        height: 64.0 + 38.0 * n,
        dataKey: Object.hashAll([d.period, for (final l in links) l.v]),
        selected: selected,
        onSelect: onSelect,
        builder: (t) => _SkPainter(
          t: t,
          cols: cols,
          links: links,
          selected: selected,
          label: _sans(context, size: 11, weight: FontWeight.w600),
          sub: _mono(context, size: 9.5, color: _kMute),
          halo: _bg(context, Colors.white),
          resolve: (c) => _fg(context, c),
          midLabelTop: true,
        ),
      ),
      if (cb != null) _skFocus(context, cols: cols, links: links, selected: selected, onClear: () => cb(null)),
    ],
  );
}

// ═════════════════════════════ 资金流水 · 页面 ═════════════════════════════

class LighthouseFundFlowPage extends StatefulWidget {
  const LighthouseFundFlowPage({super.key, required this.service, required this.session, this.initialMonth});

  final LighthouseService service;
  final AuthSession session;
  final LhFlowCategory? initialMonth;

  @override
  State<LighthouseFundFlowPage> createState() => _FundFlowPageState();
}

class _FundFlowPageState extends State<LighthouseFundFlowPage> {
  LhZgPeriod _period = const LhZgPeriod.month();
  LhFlowCategory? _flow;
  String? _flowError;
  bool _flowLoading = true;

  /// 流向图里点中的节点。
  String? _catSel;

  @override
  void initState() {
    super.initState();
    final init = widget.initialMonth;
    if (init != null && init.period == _period.param) {
      _flow = init;
      _flowLoading = false;
    }
    unawaited(_fetchFlow());
  }

  Future<void> _fetchFlow() async {
    final p = _period;
    try {
      final data = await widget.service.fetchFlowCategory(period: p.param);
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

  void _setPeriod(LhZgPeriod p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _flow = null;
      _flowError = null;
      _flowLoading = true;
      _catSel = null;
    });
    unawaited(_fetchFlow());
  }

  String get _periodLabel => _period.isDay
      ? '${_fpMd(_period.day)} 周${_kFpWeek[_period.day.weekday - 1]}'
      : '${_period.month.month} 月';

  @override
  Widget build(BuildContext context) {
    final d = _flow;
    final children = <Widget>[];
    if (_flowLoading && d == null) {
      children.add(_loadingBox(context));
    } else if (d == null) {
      children.add(_statusBox(context, _flowError ?? '暂无数据', onRetry: _fetchFlow));
    } else if (d.restricted) {
      children.add(_statusBox(context, '资金流水是全公司数据，当前账号暂无权限查看'));
    } else if (d.unavailable) {
      children.add(_statusBox(context, '资管资金流水接口未配置'));
    } else if (!d.generated) {
      children.add(_statusBox(context, _period.isDay ? '$_periodLabel 的流水分类快照还没生成（管理端补跑后才有）' : '该月还没有任何一天生成快照'));
    } else {
      children
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
                  chip: _periodLabel,
                  trailing: Text(
                    _swu(d.net),
                    style: _mono(context, size: 14, weight: FontWeight.w700, color: d.net < 0 ? _kFpOut : _kFpIn),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    '流入 ${_wu(d.inflow)} · 流出 ${_wu(d.outflow)}${_period.isDay ? ' · 单日快照' : ' · 该月每日快照相加'}${d.fixture ? ' · 样例数据' : ''}',
                    style: _sans(context, size: 10.5, color: _kInk2),
                  ),
                ),
                const SizedBox(height: 8),
                _flowSankey(
                  context,
                  d,
                  pool: _period.isDay ? '当日资金池' : '本月资金池',
                  selected: _catSel,
                  onSelect: (id) => setState(() => _catSel = id),
                ),
              ],
            ),
          ),
        )
        ..add(const SizedBox(height: 10))
        ..add(_treeCard(context, d));
    }
    return _scaffold(
      context,
      onRefresh: _fetchFlow,
      header: _pageHeader(
        context,
        '资金流水',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (d != null && d.generated && !d.restricted && !d.unavailable) ...[
              lhZgShareButton(context, session: widget.session, data: () => lhZgFlowShare(d, _period)),
              const SizedBox(width: 6),
            ],
            _visButton(
              context,
              widget.service,
              'fund_flow',
              () => unawaited(
                _openVisibility(context, service: widget.service, session: widget.session, module: 'fund_flow', title: '资管 · 资金流水'),
              ),
            ),
            const SizedBox(width: 8),
            LhZgPeriodIsland(value: _period, grains: const ['day', 'month'], onChanged: _setPeriod),
          ],
        ),
      ),
      children: children,
    );
  }

  Widget _treeCard(BuildContext context, LhFlowCategory d) {
    final cards = <Widget>[];
    for (var i = 0; i < d.categories.length; i++) {
      final c = d.categories[i];
      final kids = [for (final ch in c.children) if (!ch.isOilProject) ch];
      final inSum = kids.where((e) => e.net > 0).fold<double>(0, (a, e) => a + e.net);
      final outSum = kids.where((e) => e.net < 0).fold<double>(0, (a, e) => a - e.net);
      final top = [...kids]..sort((a, b) => b.net.abs().compareTo(a.net.abs()));
      String? share(double v, double total) => total > 0 && v > 0 ? '占${(v / total * 100).toStringAsFixed(0)}%' : null;
      if (i > 0) cards.add(const SizedBox(height: 8));
      cards.add(
        _LhRowCard(
          key: ValueKey('fl-cat-${d.period}-${c.name}'),
          index: i + 1,
          title: c.name,
          titleTag: kids.isEmpty ? _tag(context, '没有明细', _kInk2, _kGreySoft) : null,
          mainLabel: '净额',
          mainHint: '流入 − 流出',
          mainValue: c.net.abs() < 0.5 ? '0.00' : _signedWan(c.net),
          mainColor: c.net < 0 ? _kFpOut : _kFpIn,
          panels: [
            _panel(context, [
              _cell(context, label: '流入', value: lhBfWan(inSum), color: _kFpIn, badge: share(inSum, d.inflow), badgeColor: _kFpIn),
              _cell(context, label: '流出', value: lhBfWan(outSum), color: _kFpOut, badge: share(outSum, d.outflow), badgeColor: _kFpOut),
            ], title: '收付', titleColor: _kInk2),
            if (top.isNotEmpty)
              _panel(context, [
                for (final ch in top.take(2))
                  _cell(context, label: ch.name, value: _signedWan(ch.net), color: ch.net < 0 ? _kFpOut : _kFpIn),
              ], tint: _kPurple, title: '主要二级', titleColor: _kDeep),
          ],
          expandKicker: kids.isEmpty ? null : '二级 ${kids.length}',
          expandPreview: kids.map((e) => e.name).join('、'),
          expandBuilder: kids.isEmpty && c.children.isEmpty
              ? null
              : (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final ch in c.children) ...[
                      _lhSubRow(
                        context,
                        ch.name,
                        ch.net.abs() < 0.5 ? '0.00万' : _swu(ch.net),
                        color: ch.net < 0 ? _kFpOut : _kFpIn,
                        tag: ch.isOilSegment ? _tag(context, '石油板块', _kFin, _kFinSoft) : null,
                      ),
                      for (final p in ch.children)
                        _lhSubRow(context, '其中 · ${p.name}', _swu(p.net), muted: true, depth: 1, tag: _tag(context, '不计入合计', _kInk2, _kGreySoft)),
                    ],
                  ],
                ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(context, icon: Icons.account_tree_outlined, title: '分类明细', chip: '${d.categories.length} 类'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text('一级固定 4 类 · 经营活动 = 普通项目 + 两个石油板块', style: _sans(context, size: 10.5, color: _kInk2)),
          ),
          const SizedBox(height: 10),
          ...cards,
        ],
      ),
    );
  }

}


Widget _flLegend(BuildContext context, String text, Color c) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(width: 14, height: 8, decoration: BoxDecoration(color: _fg(context, c), borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text(text, style: _sans(context, size: 10, color: _kInk2)),
  ],
);

// ═════════════════════════════ 资金调动 · 页面（第五个板块）═════════════════════════════
//
//   数据：/lighthouse/fund-flow/transfer（按月现算）+ transfer-detail。只有月粒度。
//   每一组 = 账号属性（钱在哪个板块的账户上）→ 资金属性（这笔钱归哪个板块），两者不同 = 跨板块。
//   卡片画成一条会流动的通道：左边账户、右边归属，通道上写收 / 支，下面净额和发生额（占比只写在发生额上）。

class LighthouseFundTransferPage extends StatefulWidget {
  const LighthouseFundTransferPage({super.key, required this.service, required this.session, this.initial});

  final LighthouseService service;
  final AuthSession session;
  final LhTransfer? initial;

  @override
  State<LighthouseFundTransferPage> createState() => _FundTransferPageState();
}

class _FundTransferPageState extends State<LighthouseFundTransferPage> with SingleTickerProviderStateMixin {
  LhZgPeriod _period = const LhZgPeriod.month();
  LhTransfer? _transfer;
  String? _transferError;
  bool _transferLoading = true;
  String? _trSel;
  bool _showSelf = false;

  /// 通道里光点流动的节拍（2.4 秒一轮）；系统减弱动效时停住。
  late final AnimationController _flowTick = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  DateTime get _month => _period.month;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && init.yearMonth == _period.param) {
      _transfer = init;
      _transferLoading = false;
    }
    unawaited(_fetchTransfer());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) unawaited(_flowTick.repeat());
    });
  }

  @override
  void dispose() {
    _flowTick.dispose();
    super.dispose();
  }

  Future<void> _fetchTransfer() async {
    final p = _period;
    try {
      final data = await widget.service.fetchFundTransfer(yearMonth: p.param);
      if (!mounted || p != _period) return;
      setState(() {
        _transfer = LhTransfer.fromJson(data);
        _transferError = null;
        _transferLoading = false;
      });
    } catch (e) {
      if (!mounted || p != _period) return;
      setState(() {
        _transferError = '$e'.replaceFirst('Exception: ', '');
        _transferLoading = false;
      });
    }
  }

  void _setPeriod(LhZgPeriod p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _transfer = null;
      _transferError = null;
      _transferLoading = true;
      _trSel = null;
    });
    unawaited(_fetchTransfer());
  }

  @override
  Widget build(BuildContext context) {
    final t = _transfer;
    final ready = t != null && !t.restricted && !t.unavailable && t.rows.isNotEmpty;
    return _scaffold(
      context,
      onRefresh: _fetchTransfer,
      header: _pageHeader(
        context,
        '资金调动',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ready) ...[
              lhZgShareButton(context, session: widget.session, data: () => lhZgTransferShare(t!, _period)),
              const SizedBox(width: 6),
            ],
            _visButton(
              context,
              widget.service,
              'fund_transfer',
              () => unawaited(
                _openVisibility(context, service: widget.service, session: widget.session, module: 'fund_transfer', title: '资管 · 资金调动'),
              ),
            ),
            const SizedBox(width: 8),
            LhZgPeriodIsland(value: _period, grains: const ['month'], onChanged: _setPeriod),
          ],
        ),
      ),
      children: _transferTab(context),
    );
  }

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
    final left = [
      for (var i = 0; i < accts.length; i++)
        _SkNode('a$i', accts[i], _wu(sumA(accts[i])), sumA(accts[i]), _kDeep, share: _skShare('本月发生额', sumA(accts[i]), t.volume)),
    ];
    final right = [
      for (var i = 0; i < funds.length; i++)
        _SkNode('f$i', funds[i], _wu(sumF(funds[i])), sumF(funds[i]), _kDeep, share: _skShare('本月发生额', sumF(funds[i]), t.volume)),
    ];
    final links = <_SkLink>[
      for (final r in t.rows)
        if (r.volume > 0)
          _SkLink('a${accts.indexOf(r.acct)}', 'f${funds.indexOf(r.fund)}', r.volume, r.cross ? _kFlCross : _kFlSelf, r.cross ? 0.75 : 0.6),
    ];
    final share = t.crossShare;
    final cross = [...t.rows.where((r) => r.cross)]..sort((a, b) => b.volume.compareTo(a.volume));
    final self = [...t.rows.where((r) => !r.cross)]..sort((a, b) => b.volume.compareTo(a.volume));
    final cards = <Widget>[];
    var n = 0;
    for (final r in cross) {
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 8));
      cards.add(_transferCard(context, ++n, r, t.volume));
    }
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
              title: '账号属性 → 资金属性',
              trailing: Text(
                share == null ? '—' : '跨板块 ${(share * 100).toStringAsFixed(1)}%',
                style: _mono(context, size: 13, weight: FontWeight.w700, color: _kFlCross),
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
              selected: _trSel,
              onSelect: (id) => setState(() => _trSel = id),
              builder: (p) => _SkPainter(
                t: p,
                cols: [left, right],
                links: links,
                selected: _trSel,
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
            _skFocus(
              context,
              cols: [left, right],
              links: links,
              selected: _trSel,
              onClear: () => setState(() => _trSel = null),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: _cardDeco(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(context, icon: Icons.list_alt_rounded, title: '账号属性 × 资金属性', chip: '${t.rows.length} 组'),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text('跨板块 ${cross.length} 组在前 · 点一组看子流水', style: _sans(context, size: 10.5, color: _kInk2)),
            ),
            const SizedBox(height: 10),
            if (cards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('本月没有跨板块的流水', textAlign: TextAlign.center, style: _sans(context, size: 11, color: _kInk2)),
              ),
            ...cards,
            if (self.isNotEmpty) ...[
              const SizedBox(height: 10),
              _selfToggle(context, self),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _showSelf
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final r in self) ...[const SizedBox(height: 8), _transferCard(context, ++n, r, t.volume)],
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '只统计账号属性和资金属性都解析得出的子流水，行数会少于当月全部流水；资金属性取辅助备注 → 项目映射 → 三级分类映射。',
              style: _sans(context, size: 9.5, color: _kMute, height: 1.5),
            ),
          ],
        ),
      ),
    ];
  }

  /// 本板块自用的几组默认收起（跨板块才是要看的），同灯塔「细分 · 展开」条。
  Widget _selfToggle(BuildContext context, List<LhTransferRow> self) {
    final accent = _fg(context, _kPurple);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showSelf = !_showSelf),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        decoration: BoxDecoration(
          color: Color.alphaBlend(accent.withAlpha(_showSelf ? 18 : 0), _bg(context, const Color(0xFFFAF9FD))),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _ln(context, _kLine), width: 0.8),
        ),
        child: Row(
          children: [
            LhProductL3BranchMark(color: accent, size: 16),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(color: accent.withAlpha(26), borderRadius: BorderRadius.circular(4)),
              child: Text('本板块 ${self.length}', style: _sans(context, size: 10, weight: FontWeight.w700, color: _kDeep, height: 1.2)),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                self.map((r) => r.acct).toSet().join('、'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 11, weight: FontWeight.w500, color: _kInk2, height: 1.2),
              ),
            ),
            Text(_showSelf ? '收起' : '展开', style: _sans(context, size: 10.5, weight: FontWeight.w600, color: _kPurple, height: 1.2)),
            AnimatedRotation(
              turns: _showSelf ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transferCard(BuildContext context, int index, LhTransferRow r, double total) {
    final maxV = _transfer?.rows.fold<double>(0, (a, x) => math.max(a, x.volume)) ?? r.volume;
    return _FlowLaneCard(
      key: ValueKey('fl-tr-${_period.param}-${r.acct}-${r.fund}'),
      index: index,
      row: r,
      total: total,
      weight: maxV > 0 ? r.volume / maxV : 0,
      tick: _flowTick,
      onOpen: () => unawaited(_openDetail(r)),
    );
  }

  Future<void> _openDetail(LhTransferRow r) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg(context, _kBg),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _TransferDetailSheet(service: widget.service, yearMonth: _period.param, row: r),
      ),
    );
  }
}

/// 资金调动的一组：左边账户、右边归属，中间一条流动的通道（宽度按发生额，光点一直往右走）。
class _FlowLaneCard extends StatefulWidget {
  const _FlowLaneCard({
    super.key,
    required this.index,
    required this.row,
    required this.total,
    required this.weight,
    required this.tick,
    required this.onOpen,
  });

  final int index;
  final LhTransferRow row;
  final double total;
  final double weight;
  final Animation<double> tick;
  final VoidCallback onOpen;

  @override
  State<_FlowLaneCard> createState() => _FlowLaneCardState();
}

class _FlowLaneCardState extends State<_FlowLaneCard> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final accent = _fg(context, r.cross ? _kFlCross : const Color(0xFF9A92BA));
    Widget pill(String text, String caption, {required bool end}) => Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 112),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: end ? accent.withValues(alpha: r.cross ? 0.12 : 0.08) : _bg(context, _kNeutralPanel),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: end ? accent.withValues(alpha: 0.35) : _ln(context, _kEdge), width: 0.8),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 12, weight: FontWeight.w700, color: end && r.cross ? _kDeep : _kInk, height: 1.1),
          ),
        ),
        const SizedBox(height: 3),
        Text(caption, style: _sans(context, size: 9, color: _kMute, height: 1.1)),
      ],
    );
    final share = widget.total > 0 ? '占${(r.volume / widget.total * 100).toStringAsFixed(1)}%' : null;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hover ? accent.withValues(alpha: 0.45) : _ln(context, _kEdge), width: _hover ? 1 : 0.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C2878).withValues(alpha: _hover ? 0.09 : 0.04),
            blurRadius: _hover ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _indexBadge(context, widget.index),
              const SizedBox(width: 6),
              _tag(context, r.cross ? '跨板块' : '本板块', r.cross ? _kFlCross : _kInk2, r.cross ? _kLavender : _kGreySoft),
              const Spacer(),
              Text('发生额 ', style: _sans(context, size: 10, color: _kInk2)),
              _amount(context, lhBfWan(r.volume), size: 14),
              if (share != null) ...[
                const SizedBox(width: 5),
                Text(share, style: _mono(context, size: 9.5, weight: FontWeight.w700, color: _kDeep)),
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pill(r.acct, '账户', end: false),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 28,
                        child: AnimatedBuilder(
                          animation: widget.tick,
                          builder: (context, _) => CustomPaint(
                            size: Size.infinite,
                            painter: _FlowLanePainter(
                              phase: widget.tick.value,
                              weight: widget.weight,
                              color: accent,
                              idle: _ln(context, _kEdge),
                            ),
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '收 ', style: _sans(context, size: 9.5, color: _kInk2)),
                              TextSpan(text: lhBfWan(r.income), style: _mono(context, size: 10, weight: FontWeight.w700, color: _kFpIn)),
                              TextSpan(text: '  支 ', style: _sans(context, size: 9.5, color: _kInk2)),
                              TextSpan(text: lhBfWan(r.expense), style: _mono(context, size: 10, weight: FontWeight.w700, color: _kFpOut)),
                              TextSpan(text: ' 万', style: _sans(context, size: 9, color: _kMute)),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pill(r.fund, '归属', end: true),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
            decoration: BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Text('净额', style: _sans(context, size: 10, weight: FontWeight.w700, color: _kInk2)),
                const SizedBox(width: 4),
                Text('收入 − 支出', style: _sans(context, size: 9, color: _kMute)),
                const Spacer(),
                _amount(context, r.net.abs() < 0.5 ? '0.00' : _signedWan(r.net), size: 14, color: r.net < 0 ? _kFpOut : _kInk),
              ],
            ),
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onOpen,
        child: AnimatedScale(scale: _down ? 0.985 : 1, duration: const Duration(milliseconds: 120), child: card),
      ),
    );
  }
}

/// 通道：一条圆头底带（粗细按发生额 3–9），底带上光点从左往右流，右端一个小箭头。
class _FlowLanePainter extends CustomPainter {
  _FlowLanePainter({required this.phase, required this.weight, required this.color, required this.idle});

  final double phase;
  final double weight;
  final Color color;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    if (w < 24) return;
    final thick = 3 + 6 * weight.clamp(0.0, 1.0);
    final x0 = 4.0;
    final x1 = w - 10;
    final band = RRect.fromLTRBR(x0, cy - thick / 2, x1, cy + thick / 2, Radius.circular(thick / 2));
    canvas.drawRRect(
      band,
      Paint()
        ..shader = LinearGradient(colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.32)])
            .createShader(Rect.fromLTRB(x0, 0, x1, size.height)),
    );
    canvas.drawRRect(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = idle,
    );
    // 光点：一条带拖尾的小胶囊，3–6 颗，越大的组越密
    final n = 3 + (3 * weight.clamp(0.0, 1.0)).round();
    final len = (x1 - x0);
    for (var i = 0; i < n; i++) {
      final f = (phase + i / n) % 1.0;
      final x = x0 + len * f;
      final fade = math.sin(math.pi * f); // 两头淡、中间亮
      final dotW = math.max(6.0, thick * 1.8);
      final rect = RRect.fromLTRBR(
        x - dotW,
        cy - thick / 2 + 0.6,
        x,
        cy + thick / 2 - 0.6,
        Radius.circular(thick / 2),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.95 * fade)])
              .createShader(rect.outerRect),
      );
    }
    // 箭头
    final head = Path()
      ..moveTo(x1 + 1, cy - 4.5)
      ..lineTo(w - 2, cy)
      ..lineTo(x1 + 1, cy + 4.5)
      ..close();
    canvas.drawPath(head, Paint()..color = color.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant _FlowLanePainter old) =>
      old.phase != phase || old.weight != weight || old.color != color;
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
                Text('${r.acct} → ${r.fund}', style: _sans(context, size: 14, weight: FontWeight.w700)),
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

// ═════════════════════════════ 转发到 IM ═════════════════════════════

String _zgTone(double v) => v < 0 ? 'out' : 'in';

/// 资金流水卡片：净流入 + 流入 / 流出 / 覆盖 + 前几项二级分类。
LighthouseSharedCardData lhZgFlowShare(LhFlowCategory d, LhZgPeriod p) {
  final items = [...d.items]..sort((a, b) => b.$2.net.abs().compareTo(a.$2.net.abs()));
  final cov = d.coverage;
  return lhZgShareData(
    module: 'fund_flow',
    title: '资金流水',
    range: '${lhZgPeriodName(p)} ${lhZgPeriodRange(p)}',
    head: lhZgCell(p.isDay ? '当日净流入' : '本月净流入', _signedWan(d.net), tone: _zgTone(d.net)),
    cells: [
      lhZgCell('流入', lhBfWan(d.inflow), tone: 'in'),
      lhZgCell('流出', lhBfWan(d.outflow), tone: 'out'),
      if (cov != null) lhZgCell('流入覆盖流出', '${(cov * 100).round()}%', unit: ''),
    ],
    linesTitle: '金额最大的几项',
    lines: [
      for (final e in items.take(5)) lhZgCell('${e.$2.name} · ${e.$1}', _signedWan(e.$2.net), tone: _zgTone(e.$2.net)),
    ],
  );
}

/// 资金调动卡片：跨板块发生额（占比写在主数上）+ 合计 + 前几组跨板块。
LighthouseSharedCardData lhZgTransferShare(LhTransfer t, LhZgPeriod p) {
  final cross = [...t.rows.where((r) => r.cross)]..sort((a, b) => b.volume.compareTo(a.volume));
  final share = t.crossShare;
  return lhZgShareData(
    module: 'fund_transfer',
    title: '资金调动',
    range: '${lhZgPeriodName(p)} ${lhZgPeriodRange(p)}',
    head: {
      ...lhZgCell('跨板块发生额', lhBfWan(t.crossVolume), tone: 'in'),
      if (share != null) 'b': '占本月发生额 ${(share * 100).toStringAsFixed(1)}%',
    },
    cells: [
      lhZgCell('本月发生额', lhBfWan(t.volume)),
      lhZgCell('跨板块组数', '${cross.length}', unit: ' 组'),
      lhZgCell('收入合计', lhBfWan(t.incomeTotal), tone: 'in'),
      lhZgCell('支出合计', lhBfWan(t.expenseTotal), tone: 'out'),
    ],
    linesTitle: '账户 → 归属 · 净额',
    lines: [
      for (final r in cross.take(5)) lhZgCell('${r.acct} → ${r.fund}', _signedWan(r.net), tone: _zgTone(r.net)),
    ],
  );
}
