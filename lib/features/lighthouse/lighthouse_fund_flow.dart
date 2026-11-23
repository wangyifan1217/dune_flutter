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

// ═════════════════════════════ 钱从哪来，到哪去 ═════════════════════════════
//
//   2026-11-23 · 按原型重做（桑基 → 瀑布都被财务说看不懂）：
//     · 先一句话：进来多少、主要是哪两项；出去多少、主要是哪两项；账上多了 / 少了多少。
//     · 三个框：进来的钱 − 出去的钱 = 留在账上。
//     · 两根同一把尺的条：多的那一侧满格，少的那一侧剩下的部分画虚框（留在账上 / 账上少了）。
//     · 两张排行：钱从哪来 / 钱到哪去，带一级分类色点、金额、占比。
//     · 底下一行：期初 + 净流入 = 期末（资管还没给余额，先写「暂无」）。
//   资管只给二级净额：同一项有收有付取差额，正的算进来、负的算出去，所以成本类里的退款也可能在「进来」。

class _FlowMoneyItem {
  const _FlowMoneyItem(this.cat, this.name, this.v, this.oil);

  final String cat;
  final String name;
  final double v; // 元，正数
  final bool oil;
}

/// 元 → 万，千分位，[digits] 位小数；负数用全角减号。
String _flWan(double yuan, {int digits = 2}) {
  final fixed = (yuan.abs() / 10000).toStringAsFixed(digits);
  final parts = fixed.split('.');
  final head = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  final s = parts.length > 1 ? '$head.${parts[1]}' : head;
  final zero = s.replaceAll(RegExp(r'[0.,]'), '').isEmpty;
  return yuan < 0 && !zero ? '−$s' : s;
}

String _flPct(double v, double total) => total > 0 ? '${(v / total * 100).toStringAsFixed(1)}%' : '—';

const _kFlowMoneyShown = 8;
const _kFlowFadeAlpha = [255, 204, 153, 119];

class _LhFlowMoneyCard extends StatefulWidget {
  const _LhFlowMoneyCard({required this.data, required this.periodLabel, required this.isDay});

  final LhFlowCategory data;
  final String periodLabel;
  final bool isDay;

  @override
  State<_LhFlowMoneyCard> createState() => _LhFlowMoneyCardState();
}

class _LhFlowMoneyCardState extends State<_LhFlowMoneyCard> {
  bool _allIn = false;
  bool _allOut = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final ins = [
      for (final e in d.items)
        if (e.$2.net > 0) _FlowMoneyItem(e.$1, e.$2.name, e.$2.net, e.$2.isOilSegment),
    ]..sort((a, b) => b.v.compareTo(a.v));
    final outs = [
      for (final e in d.items)
        if (e.$2.net < 0) _FlowMoneyItem(e.$1, e.$2.name, -e.$2.net, e.$2.isOilSegment),
    ]..sort((a, b) => b.v.compareTo(a.v));
    final inT = ins.fold<double>(0, (a, e) => a + e.v);
    final outT = outs.fold<double>(0, (a, e) => a + e.v);
    final net = inT - outT;
    final periodName = widget.periodLabel;

    String top2(List<_FlowMoneyItem> xs, double total) => xs
        .take(2)
        .map((e) => '${e.name}（${total > 0 ? (e.v / total * 100).toStringAsFixed(0) : '0'}%）')
        .join('、');
    // 2026-11-23 · 文案改正式（用户：说得正规一点）。
    final story = StringBuffer('$periodName资金流入 ${_flWan(inT)} 万元');
    if (ins.isNotEmpty) story.write('，主要来自${top2(ins, inT)}');
    story.write('；资金流出 ${_flWan(outT)} 万元');
    if (outs.isNotEmpty) story.write('，主要用于${top2(outs, outT)}');
    story.write(net >= 0
        ? '；收支相抵，净流入 ${_flWan(net)} 万元。'
        : '；收支相抵，净流出 ${_flWan(-net)} 万元。');

    final cats = <String>{for (final e in ins) e.cat, for (final e in outs) e.cat};

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(
            context,
            icon: Icons.waves_rounded,
            title: '资金来源与去向',
            chip: widget.periodLabel,
            trailing: Text(
              '${net < 0 ? '−' : '+'}${_flWan(net.abs())}万',
              style: _mono(context, size: 15, weight: FontWeight.w700, color: net < 0 ? _kFpOut : _kDeep),
            ),
          ),
          if (d.fixture) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text('样例数据', style: _sans(context, size: 10.5, color: _kCopper)),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(10)),
            child: Text(story.toString(), style: _sans(context, size: 12.5, height: 1.65)),
          ),
          const SizedBox(height: 12),
          _equation(context, inT, outT, net, ins.length, outs.length),
          const SizedBox(height: 14),
          _bars(context, ins, outs, inT, outT, net),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final c in cats)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: _fg(context, _flowSeriesColor(c)), borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 4),
                    Text(c, style: _sans(context, size: 10.5, color: _kInk2)),
                  ],
                ),
              Text('流入、流出按同一比例尺绘制', style: _sans(context, size: 10.5, color: _kMute)),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _ln(context, _kLine)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final left = _list(context, '资金来源', '占流入比例', _kFpIn, ins, inT, _allIn, () => setState(() => _allIn = !_allIn));
              final right = _list(context, '资金去向', '占流出比例', _kFpOut, outs, outT, _allOut, () => setState(() => _allOut = !_allOut));
              if (box.maxWidth >= 620) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: left), const SizedBox(width: 20), Expanded(child: right)],
                );
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 14), right]);
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _ln(context, _kEdge), width: 0.8),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('期初余额 暂无', style: _sans(context, size: 11.5, color: _kInk2)),
                Text('+ 本期净流入 ${net < 0 ? '−' : '+'}${_flWan(net.abs())}万', style: _sans(context, size: 11.5, weight: FontWeight.w600, color: _kDeep)),
                Text('= 期末余额 暂无', style: _sans(context, size: 11.5, color: _kInk2)),
                Text('待资管接口提供期初余额后自动衔接账户余额', style: _sans(context, size: 10, color: _kMute)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '口径说明：按二级分类净额统计，同一分类同时发生收付时以差额计列，差额为正计入流入、为负计入流出；'
            '因此成本类中的退款、返佣回收可能列入「资金来源」。'
            '${widget.isDay ? '数据为当日快照。' : '数据为当月每日快照汇总。'}',
            style: _sans(context, size: 10, color: _kMute, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _equation(BuildContext context, double inT, double outT, double net, int nIn, int nOut) {
    Widget box(String label, double v, String sub, Color color, {bool strong = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _bg(context, strong ? _kMist : Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ln(context, strong ? _kPurple : _kEdge), width: strong ? 1.2 : 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sans(context, size: 11, weight: strong ? FontWeight.w600 : FontWeight.w400, color: strong ? _kDeep : _kInk2)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${_flWan(v)}万', style: _mono(context, size: 16, weight: FontWeight.w700, color: color)),
          ),
          const SizedBox(height: 3),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10, color: _kMute)),
        ],
      ),
    );
    Widget op(String t) => SizedBox(
      width: 20,
      child: Text(t, textAlign: TextAlign.center, style: _sans(context, size: 17, color: _kMute)),
    );
    return Row(
      children: [
        Expanded(child: box('资金流入', inT, '$nIn 个来源', _kFpIn)),
        op('−'),
        Expanded(child: box('资金流出', outT, '$nOut 个去向', _kFpOut)),
        op('='),
        Expanded(child: box(net >= 0 ? '净流入' : '净流出', net.abs(), '流入 − 流出', net >= 0 ? _kDeep : _kFpOut, strong: true)),
      ],
    );
  }

  /// 进来 / 出去两根条，同一把尺（取两边大的那个当满格）。
  Widget _bars(BuildContext context, List<_FlowMoneyItem> ins, List<_FlowMoneyItem> outs, double inT, double outT, double net) {
    final scale = math.max(inT, outT);
    if (scale <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('这一期没有收付', textAlign: TextAlign.center, style: _sans(context, size: 11.5, color: _kInk2)),
      );
    }
    Widget bar(String label, List<_FlowMoneyItem> xs, double minShare, String? restLabel) => Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: _sans(context, size: 12, weight: FontWeight.w600))),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final segs = <(String, double, Color, bool)>[]; // 名称, 金额, 颜色, 浅底
              final seen = <String, int>{};
              var restV = 0.0;
              var restN = 0;
              for (final e in xs) {
                if (e.v / scale >= minShare) {
                  final k = seen[e.cat] ?? 0;
                  seen[e.cat] = k + 1;
                  final alpha = _kFlowFadeAlpha[math.min(k, _kFlowFadeAlpha.length - 1)];
                  segs.add((e.name, e.v, _fg(context, _flowSeriesColor(e.cat)).withAlpha(alpha), alpha < 160));
                } else {
                  restV += e.v;
                  restN += 1;
                }
              }
              if (restN > 0) segs.add(('其他 $restN 项', restV, _fg(context, const Color(0xFFC9C3D6)), true));
              final used = segs.fold<double>(0, (a, s) => a + s.$2);
              final rest = math.max(0.0, scale - used);
              int flex(double v) => math.max(1, (v / scale * 10000).round());
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in segs)
                        Expanded(
                          flex: flex(s.$2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: s.$3,
                              border: Border(right: BorderSide(color: _bg(context, Colors.white), width: 1.5)),
                            ),
                            child: s.$2 / scale * w >= 64
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _sans(context, size: 10.5, weight: FontWeight.w600, color: s.$4 ? _kInk : Colors.white),
                                      ),
                                      Text(
                                        '${_flWan(s.$2)}万',
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        softWrap: false,
                                        style: _mono(context, size: 9.5, color: s.$4 ? _kInk : Colors.white),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                      if (rest / scale * w >= 1)
                        Expanded(
                          flex: flex(rest),
                          child: restLabel == null
                              ? const SizedBox.shrink()
                              : Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _bg(context, _kMist),
                                    border: Border.all(color: _ln(context, _kFlIn), width: 1.2),
                                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                                  ),
                                  child: rest / scale * w >= 90
                                      ? Text(
                                          restLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _sans(context, size: 11, weight: FontWeight.w600, color: net >= 0 ? _kDeep : _kFpOut),
                                        )
                                      : null,
                                ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    final keep = '${net >= 0 ? '净流入' : '净流出'} ${_flWan(net.abs())}万 · ${_flPct(net.abs(), scale)}';
    return Column(
      children: [
        bar('流入', ins, 0.04, net < 0 ? keep : null),
        const SizedBox(height: 8),
        bar('流出', outs, 0.02, net >= 0 ? keep : null),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    String title,
    String hint,
    Color tone,
    List<_FlowMoneyItem> xs,
    double total,
    bool all,
    VoidCallback onToggle,
  ) {
    final shown = all ? xs : xs.take(_kFlowMoneyShown).toList();
    final first = xs.isEmpty ? 1.0 : xs.first.v;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title, style: _sans(context, size: 13.5, weight: FontWeight.w700, color: tone)),
            const SizedBox(width: 6),
            Text(hint, style: _sans(context, size: 10.5, color: _kMute)),
          ],
        ),
        const SizedBox(height: 4),
        if (xs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('这一期没有', style: _sans(context, size: 11, color: _kMute)),
          ),
        for (var i = 0; i < shown.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _ln(context, _kLine), width: 0.8))),
            child: Row(
              children: [
                SizedBox(width: 18, child: Text('${i + 1}', style: _mono(context, size: 10, color: _kMute))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              shown[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _sans(context, size: 12, weight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: _fg(context, _flowSeriesColor(shown[i].cat)), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 3),
                          Text(shown[i].cat, style: _sans(context, size: 10, color: _kInk2)),
                          if (shown[i].oil) ...[const SizedBox(width: 4), _tag(context, '石油板块', _kFin, _kFinSoft)],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 5,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(color: _bg(context, _kLine), borderRadius: BorderRadius.circular(3)),
                        child: FractionallySizedBox(
                          widthFactor: (shown[i].v / first).clamp(0.0, 1.0).toDouble(),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: _fg(context, _flowSeriesColor(shown[i].cat)), borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${_flWan(shown[i].v)}万', maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: _mono(context, size: 11.5, weight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(_flPct(shown[i].v, total), style: _mono(context, size: 9.5, color: _kMute)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (xs.length > _kFlowMoneyShown)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggle,
              child: Text(all ? '收起' : '展开全部 ${xs.length} 项', style: _sans(context, size: 11, weight: FontWeight.w600, color: _kDeep)),
            ),
          ),
      ],
    );
  }
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


  /// 四大类走势（按当前粒度：日 = 近 30 天，月 = 近 12 个月）。
  LhFlowSeries? _series;
  String? _seriesError;
  bool _seriesLoading = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initialMonth;
    if (init != null && init.period == _period.param) {
      _flow = init;
      _flowLoading = false;
    }
    unawaited(_fetchFlow());
    unawaited(_fetchSeries());
  }

  Future<void> _fetchSeries() async {
    final grain = _period.grain;
    try {
      final data = await widget.service.fetchFlowCategorySeries(grain: grain);
      if (!mounted || grain != _period.grain) return;
      setState(() {
        _series = LhFlowSeries.fromJson(data);
        _seriesError = null;
        _seriesLoading = false;
      });
    } catch (e) {
      if (!mounted || grain != _period.grain) return;
      setState(() {
        _seriesError = '$e'.replaceFirst('Exception: ', '');
        _seriesLoading = false;
      });
    }
  }

  /// 点走势上的柱子：下面的流向图和分类明细切到那一天 / 那个月。
  void _selectSeriesPoint(LhFlowSeriesPoint p) {
    final d = DateTime.tryParse(p.key.length == 7 ? '${p.key}-01' : p.key);
    if (d == null) return;
    final now = DateTime.now();
    if (_period.isDay) {
      final today = DateTime(now.year, now.month, now.day);
      final off = (DateTime(d.year, d.month, d.day).difference(today).inHours / 24).round();
      _setPeriod(LhZgPeriod.day(off));
    } else {
      _setPeriod(LhZgPeriod.month((d.year * 12 + d.month) - (now.year * 12 + now.month)));
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([_fetchFlow(), _fetchSeries()]);
  }

  Widget? _seriesCard(BuildContext context) {
    final s = _series;
    if (s == null) {
      if (_seriesLoading) {
        return Container(
          height: 64,
          alignment: Alignment.center,
          decoration: _cardDeco(context),
          child: Text('四大类走势加载中…', style: _sans(context, size: 11, color: _kInk2)),
        );
      }
      return _statusBox(context, '四大类走势：${_seriesError ?? '暂无数据'}', onRetry: _fetchSeries);
    }
    // 没权限 / 没配资管：下面主卡片会说明，这里不重复。
    if (s.restricted || s.unavailable) return null;
    return _LhFlowSeriesCard(series: s, selectedKey: _period.param, onSelect: _selectSeriesPoint);
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
        _flow = null; // 旧期数据不能冒充新期，报错时清掉，露出重试框。
        _flowError = '$e'.replaceFirst('Exception: ', '');
        _flowLoading = false;
      });
    }
  }

  void _setPeriod(LhZgPeriod p) {
    if (p == _period) return;
    final grainChanged = p.grain != _period.grain;
    setState(() {
      _period = p;
      // 2026-11-20 · 切期时不清空旧数据：清空会让流向图 + 分类明细整块换成 96 高的转圈，
      // 页面高度塌掉再撑回来，滚动位置跟着跳。旧数据淡显着等新数据到。
      _flowError = null;
      _flowLoading = true;
      if (grainChanged) {
        _series = null;
        _seriesError = null;
        _seriesLoading = true;
      }
    });
    unawaited(_fetchFlow());
    if (grainChanged) unawaited(_fetchSeries());
  }

  String get _periodLabel => _period.isDay
      ? '${_fpMd(_period.day)} 周${_kFpWeek[_period.day.weekday - 1]}'
      : '${_period.month.month} 月';

  @override
  Widget build(BuildContext context) {
    final d = _flow;
    final children = <Widget>[];
    final trend = _seriesCard(context);
    if (trend != null) {
      children
        ..add(trend)
        ..add(const SizedBox(height: 10));
    }
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
      // 切期加载中：旧数据淡显、不可点，高度不变，页面不跳。
      final stale = _flowLoading;
      Widget fade(Widget w) => IgnorePointer(
        ignoring: stale,
        child: AnimatedOpacity(opacity: stale ? 0.4 : 1, duration: const Duration(milliseconds: 160), child: w),
      );
      children
        ..add(
          fade(_LhFlowMoneyCard(data: d, periodLabel: _periodLabel, isDay: _period.isDay)),
        )
        ..add(const SizedBox(height: 10))
        ..add(fade(_treeCard(context, d)));
    }
    return _scaffold(
      context,
      onRefresh: _refreshAll,
      header: _pageHeader(
        context,
        '资金流水',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (d != null && !_flowLoading && d.generated && !d.restricted && !d.unavailable) ...[
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

// ═════════════════════════════ 四大类走势 ═════════════════════════════
//
//   只看一天或一个月，净流入忽高忽低看不出趋势，所以页面顶上放一条走势：
//   按日 = 近 30 天，按月 = 近 12 个月。每根柱子按四大类分段，流入往上、流出往下；
//   黑点是那一期的净流入。按月叠一条「近 3 月平均」；按日可切到「月内累计」看这个月攒下多少。
//   没快照的点画成灰色短横（断点，不当 0），取数失败的画成橙色。点柱子 = 下面切到那一期。
//   数据：/lighthouse/fund-flow/category-series（后端 fund_flow_series.go）。

class LhFlowSeriesPoint {
  LhFlowSeriesPoint.fromJson(Map<String, dynamic> j)
    : key = _fpStr(j['key']),
      label = _fpStr(j['label']),
      generated = j['generated'] == true,
      failed = j['failed'] == true,
      partial = j['partial'] == true,
      net = _fpNum(j['net']),
      running = _fpNum(j['running']),
      byCategory = _flowSeriesCats(j['byCategory']);

  final String key;
  final String label;
  final bool generated;
  final bool failed;
  final bool partial;
  final double? net;
  final double? running;
  final Map<String, double> byCategory;

  bool get hasData => generated && net != null;
}

Map<String, double> _flowSeriesCats(Object? v) {
  final out = <String, double>{};
  if (v is Map) {
    for (final e in v.entries) {
      final n = _fpNum(e.value);
      if (n != null) out[e.key.toString()] = n;
    }
  }
  return out;
}

class LhFlowSeries {
  LhFlowSeries.fromJson(Map<String, dynamic> j)
    : restricted = j['restricted'] == true,
      unavailable = j['unavailable'] == true,
      fixture = j['fixture'] == true,
      grain = _fpStr(j['grain']),
      runningLabel = _fpStr(j['runningLabel']),
      categories = [
        if (j['categories'] is List)
          for (final c in j['categories'] as List)
            if (c.toString().trim().isNotEmpty) c.toString().trim(),
      ],
      points = [for (final p in _fpList(j['points'])) LhFlowSeriesPoint.fromJson(p)];

  final bool restricted;
  final bool unavailable;
  final bool fixture;
  final String grain;
  final String runningLabel;
  final List<String> categories;
  final List<LhFlowSeriesPoint> points;

  bool get isDay => grain == 'day';
}

/// 四大类的固定配色：经营活动紫、筹资蓝、经营成本铜、项目成本淡紫、业务成本橙；接口多给的分类用灰。
/// 2026-11-23 · 分类配色：净流入橙（[_kFlowChart]），经营活动紫、筹资活动蓝、经营成本玫红、业务成本青、项目成本橄榄绿。
/// 走势卡片的小柱、主图的柱子都用分类色的浅色，选中那一期用实色。
Color _flowSeriesColor(String name) => switch (name) {
  '净流入' => _kFlowChart,
  '经营活动' => Color(0xFF7B5CD8),
  '筹资活动' => Color(0xFF3B82C4),
  '经营成本' => Color(0xFFC2577E),
  '项目成本' => Color(0xFF7F9A2E),
  '业务成本' => Color(0xFF2E9C8F),
  _ => _kMute,
};

// 2026-11-23 · 四大类走势按原型重做（财务：看不出单类升降起落）：
//   · 上面一排卡片：净流入 + 每个一级分类，各写这一期金额、比上一期 ▲▼ 多少 / 百分比、一条小柱走势；点卡片换分类。
//   · 中间一句话：这一期多少、比上期、月均、最高 / 最低、连续几期上升 / 下降。
//   · 主图：选中分类的柱图，带刻度、每根柱子的数、最高 / 最低标签、月均虚线，月份下面写环比 ▲▼。
//   · 底下明细表：分类 × 每一期，格子里数 + ▲▼。
//   成本类（整段以流出为主）一律按流出金额显示：▲ = 花出去的钱变多。涨红跌绿，同灯塔差额。
//   还在变的这一期（今天 / 本月）画淡、不算均值和最高最低；没快照 = 空，不当 0。

class _FlowTrendCat {
  const _FlowTrendCat(this.name, this.color, this.outflow, this.values);

  final String name;
  final Color color;
  final bool outflow;

  /// 展示口径（元）：流出类取反，流出金额为正。null = 没快照。
  final List<double?> values;

  String get word => name == '净流入' ? '净流入' : (outflow ? '流出' : '流入');
}

/// 这一期算不算有数：没快照不算；按月时一整月所有分类都是 0，也当没数
/// （窗口开头资管还没开始出快照的月份会这样，按 0 算会把月均拉低、下个月平白多一个 ▲）。
/// 按日不这样判断：周末确实可能一笔都没有。
bool _flowHasValue(LhFlowSeries s, LhFlowSeriesPoint p) {
  if (!p.hasData) return false;
  if (s.isDay) return true;
  if ((p.net ?? 0).abs() >= 0.5) return true;
  return p.byCategory.values.any((v) => v.abs() >= 0.5);
}

List<_FlowTrendCat> _flowTrendCats(LhFlowSeries s) {
  final pts = s.points;
  final ok = [for (final p in pts) _flowHasValue(s, p)];
  final out = <_FlowTrendCat>[
    _FlowTrendCat('净流入', _kFlowChart, false, [for (var i = 0; i < pts.length; i++) ok[i] ? pts[i].net : null]),
  ];
  final names = <String>{...s.categories, for (final p in pts) ...p.byCategory.keys};
  for (final n in names) {
    final raw = <double?>[for (var i = 0; i < pts.length; i++) ok[i] ? (pts[i].byCategory[n] ?? 0.0) : null];
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final v = raw[i];
      if (v != null && !pts[i].partial) sum += v;
    }
    final outflow = sum < 0;
    out.add(_FlowTrendCat(n, _flowSeriesColor(n), outflow, [for (final v in raw) v == null ? null : (outflow ? -v : v)]));
  }
  return out;
}

/// 这一期比上一期：(差额, 百分比)；上一期没数 → null。
(double, double?)? _flowDelta(List<double?> v, int i) {
  if (i <= 0 || i >= v.length) return null;
  final a = v[i];
  final b = v[i - 1];
  if (a == null || b == null) return null;
  return (a - b, b.abs() > 0.5 ? (a - b) / b.abs() * 100 : null);
}

String _flowPctText(double? p) => p == null ? '' : '${p >= 0 ? '+' : '−'}${p.abs().toStringAsFixed(1)}%';

/// 净流入的颜色（橙）。其他分类见 [_flowSeriesColor]。
const _kFlowChart = Color(0xFFD08A3C);

Color _flowUpDown(double d) => d > 0.5 ? LhColors.neg : (d < -0.5 ? LhColors.pos : _kInk2);

class _LhFlowSeriesCard extends StatefulWidget {
  const _LhFlowSeriesCard({required this.series, required this.selectedKey, required this.onSelect});

  final LhFlowSeries series;
  final String selectedKey;
  final ValueChanged<LhFlowSeriesPoint> onSelect;

  @override
  State<_LhFlowSeriesCard> createState() => _LhFlowSeriesCardState();
}

class _LhFlowSeriesCardState extends State<_LhFlowSeriesCard> {
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    final pts = s.points;
    if (pts.isEmpty) return _statusBox(context, '四大类走势：暂无数据');
    final cats = _flowTrendCats(s);
    final ci = math.min(math.max(_cat, 0), cats.length - 1);
    final cat = cats[ci];
    var sel = pts.indexWhere((p) => p.key == widget.selectedKey);
    if (sel < 0) {
      for (var i = pts.length - 1; i >= 0; i--) {
        if (pts[i].hasData && !pts[i].partial) {
          sel = i;
          break;
        }
      }
      if (sel < 0) sel = pts.length - 1;
    }
    final unit = s.isDay ? '天' : '月';
    final prevWord = s.isDay ? '前一天' : '上月';
    final span = s.isDay ? '近 ${pts.length} 天' : '近 ${pts.length} 个月';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('四大类走势', style: _sans(context, size: 13.5, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('$span · ${s.isDay ? '按日' : '按月'}', style: _sans(context, size: 10.5, color: _kMute)),
              if (s.fixture) ...[const SizedBox(width: 6), _tag(context, '样例', _kCopper, _kCopperSoft)],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                '${pts[sel].label}${pts[sel].partial ? '（统计中）' : ''}',
                style: _sans(context, size: 12.5, weight: FontWeight.w600),
              ),
              Text(
                sel > 0 ? '较 ${pts[sel - 1].label} · 点击卡片切换分类，点击柱形切换${unit == '天' ? '日期' : '月份'}' : '点击卡片切换分类，点击柱形切换${unit == '天' ? '日期' : '月份'}',
                style: _sans(context, size: 10.5, color: _kInk2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 6.0;
              final fit = (box.maxWidth - gap * (cats.length - 1)) / cats.length;
              final cards = [
                for (var k = 0; k < cats.length; k++)
                  _card(context, cats[k], sel, k == ci, prevWord, () => setState(() => _cat = k)),
              ];
              if (fit >= 120) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var k = 0; k < cards.length; k++) ...[
                        if (k > 0) const SizedBox(width: gap),
                        Expanded(child: cards[k]),
                      ],
                    ],
                  ),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var k = 0; k < cards.length; k++) ...[
                        if (k > 0) const SizedBox(width: gap),
                        SizedBox(width: 112, child: cards[k]),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _insight(context, s, cat, sel),
          const SizedBox(height: 12),
          _focusLegend(context, s, cat),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final painter = _FlowFocusPainter(
                values: cat.values,
                labels: [for (final p in pts) p.label],
                partial: [for (final p in pts) p.partial],
                selected: sel,
                color: _fg(context, cat.color),
                ink: _fg(context, _kInk),
                ink2: _fg(context, _kInk2),
                mute: _fg(context, _kMute),
                grid: _ln(context, _kLine),
                axis: _ln(context, _kEdge),
                highlight: _bg(context, _kMist),
                up: _fg(context, LhColors.neg),
                down: _fg(context, LhColors.pos),
                avgWord: s.isDay ? '日均' : '月均',
                textScale: MediaQuery.textScalerOf(context),
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final i = painter.indexAt(d.localPosition.dx, w);
                  if (i != null) widget.onSelect(pts[i]);
                },
                child: SizedBox(width: w, height: _FlowFocusPainter.height, child: CustomPaint(painter: painter)),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: _ln(context, _kLine)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(s.isDay ? '每日明细' : '月度明细', style: _sans(context, size: 13, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '单位：万元 · ▲▼ 为较$prevWord变动 · 点击行切换分类',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(context, size: 10.5, color: _kMute),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _table(context, s, cats, ci, sel),
          const SizedBox(height: 8),
          Text(
            '说明：▲▼ 均为较$prevWord变动。流入类 ▲ 表示流入增加；标注「流出」的分类按流出金额列示，▲ 表示流出增加。'
            '统计中的${s.isDay ? '当日' : '当月'}以浅色显示，不计入${s.isDay ? '日均' : '月均'}及最高 / 最低；无快照的${unit == '天' ? '日期' : '月份'}留空。',
            style: _sans(context, size: 10, color: _kMute, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 2026-11-23 · 手机上卡片要小：一行名称、一行金额、一行 ▲▼ 差额 + 百分比、一条小柱。
  /// 「比上月多流入 …」整句挪到下面那句话里，卡片里不再写。
  Widget _card(BuildContext context, _FlowTrendCat c, int sel, bool on, String prevWord, VoidCallback onTap) {
    final v = c.values[sel];
    final dl = _flowDelta(c.values, sel);
    var text = v == null ? '无快照' : '—';
    var tone = _kMute;
    if (dl != null) {
      if (dl.$1.abs() < 0.5) {
        text = '持平';
        tone = _kInk2;
      } else {
        final pct = _flowPctText(dl.$2);
        text = '${dl.$1 > 0 ? '▲' : '▼'} ${_flWan(dl.$1.abs(), digits: 1)}万${pct.isEmpty ? '' : '  $pct'}';
        tone = _flowUpDown(dl.$1);
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
        decoration: BoxDecoration(
          color: on ? _fg(context, c.color).withAlpha(22) : _bg(context, Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? _fg(context, c.color) : _ln(context, _kEdge), width: on ? 1.4 : 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: _fg(context, c.color), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, size: 11, weight: FontWeight.w600),
                  ),
                ),
                if (c.outflow) ...[
                  const SizedBox(width: 3),
                  Text('流出', style: _sans(context, size: 9, weight: FontWeight.w600, color: _kFpOut)),
                ],
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: v == null ? '—' : _flWan(v), style: _mono(context, size: 14.5, weight: FontWeight.w700)),
                    TextSpan(text: ' 万', style: _sans(context, size: 9.5, color: _kInk2)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(text, maxLines: 1, style: _mono(context, size: 9.5, weight: FontWeight.w600, color: tone)),
            ),
            const Spacer(),
            const SizedBox(height: 4),
            SizedBox(
              height: 16,
              child: CustomPaint(
                size: Size.infinite,
                painter: _FlowMiniBarsPainter(
                  values: c.values,
                  partial: [for (final p in widget.series.points) p.partial],
                  selected: sel,
                  on: _fg(context, c.color),
                  off: _fg(context, c.color).withAlpha(95),
                  faded: _fg(context, c.color).withAlpha(45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 主图图例：柱 = 每期金额，实线 = 走势，虚线 = 均值（均值数写在这里，不压在图上）。
  Widget _focusLegend(BuildContext context, LhFlowSeries s, _FlowTrendCat c) {
    final pts = s.points;
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i < c.values.length; i++) {
      final x = c.values[i];
      if (x == null || pts[i].partial) continue;
      sum += x;
      n += 1;
    }
    final color = _fg(context, c.color);
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [mark, const SizedBox(width: 4), Text(text, style: _sans(context, size: 10, color: _kInk2))],
    );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        item(
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color.withAlpha(110), borderRadius: BorderRadius.circular(2))),
          '${c.name}${c.outflow ? '（流出金额）' : ''}',
        ),
        item(
          SizedBox(
            width: 16,
            height: 9,
            child: CustomPaint(painter: _FlowLegendLinePainter(color: color, dashed: false)),
          ),
          '走势',
        ),
        if (n > 0)
          item(
            SizedBox(
              width: 16,
              height: 9,
              child: CustomPaint(painter: _FlowLegendLinePainter(color: color, dashed: true)),
            ),
            '${s.isDay ? '日均' : '月均'} ${_flWan(sum / n)}万',
          ),
      ],
    );
  }

  Widget _insight(BuildContext context, LhFlowSeries s, _FlowTrendCat c, int sel) {
    final pts = s.points;
    final v = c.values;
    final cur = v[sel];
    final prevWord = s.isDay ? '前一天' : '上月';
    final avgWord = s.isDay ? '日均' : '月均';
    var sum = 0.0;
    var n = 0;
    int? maxI;
    int? minI;
    for (var i = 0; i < v.length; i++) {
      final x = v[i];
      if (x == null || pts[i].partial) continue;
      sum += x;
      n += 1;
      if (maxI == null || x > v[maxI]!) maxI = i;
      if (minI == null || x < v[minI]!) minI = i;
    }
    final title = '${c.name}${c.outflow ? '（流出）' : ''} · ${pts[sel].label}：';
    final body = StringBuffer();
    if (cur == null) {
      body.write('本期暂无快照数据。');
    } else {
      body.write('${c.word} ${_flWan(cur)}万');
      final dl = _flowDelta(v, sel);
      if (dl != null) {
        final pct = _flowPctText(dl.$2);
        body.write('，较$prevWord${dl.$1 >= 0 ? '增加' : '减少'} ${_flWan(dl.$1.abs())}万${pct.isEmpty ? '' : '（$pct）'}');
      }
      if (n > 0 && maxI != null && minI != null) {
        final avg = sum / n;
        body.write('。近 ${pts.length} ${s.isDay ? '天' : '个月'}$avgWord ${_flWan(avg)}万，'
            '最高 ${pts[maxI].label} ${_flWan(v[maxI]!)}万，最低 ${pts[minI].label} ${_flWan(v[minI]!)}万');
        if (!pts[sel].partial) {
          body.write('；${pts[sel].label}${cur >= avg ? '高于' : '低于'}$avgWord ${_flWan((cur - avg).abs())}万');
        }
      }
      body.write('。');
    }
    // 连续几期同方向（还在变的这一期不算）。
    var streak = 0;
    var dir = 0;
    if (cur != null && !pts[sel].partial) {
      for (var i = sel; i > 0; i--) {
        final a = v[i];
        final b = v[i - 1];
        if (a == null || b == null) break;
        final d = a - b;
        final sg = d > 0.5 ? 1 : (d < -0.5 ? -1 : 0);
        if (sg == 0 || (dir != 0 && sg != dir)) break;
        dir = sg;
        streak += 1;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(10)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title, style: _sans(context, size: 12.5, weight: FontWeight.w700, color: c.name == '净流入' ? _kFpWarn : c.color)),
            TextSpan(text: body.toString(), style: _sans(context, size: 12.5, height: 1.65)),
            if (streak >= 2)
              TextSpan(
                text: '已连续 $streak ${s.isDay ? '天' : '个月'}${dir > 0 ? '上升' : '下降'}。',
                style: _sans(context, size: 12.5, weight: FontWeight.w600, color: dir > 0 ? LhColors.neg : LhColors.pos, height: 1.65),
              ),
          ],
        ),
      ),
    );
  }

  /// 明细表从最近一期往前排（2026-11-23）；▲▼ 仍是和它的上一期比。
  Widget _table(BuildContext context, LhFlowSeries s, List<_FlowTrendCat> cats, int ci, int sel) {
    final pts = s.points;
    const nameW = 104.0;
    const cellW = 66.0;
    const rowH = 42.0;
    Color colBg(int i) => i == sel ? _bg(context, _kLavender) : Colors.transparent;
    final header = Row(
      children: [
        SizedBox(width: nameW, child: Text('分类', style: _sans(context, size: 10.5, color: _kInk2))),
        for (var i = pts.length - 1; i >= 0; i--)
          Container(
            width: cellW,
            height: 28,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 6),
            color: colBg(i),
            child: Text(
              pts[i].partial ? '${pts[i].label}*' : pts[i].label,
              maxLines: 1,
              style: _sans(context, size: 10.5, weight: i == sel ? FontWeight.w700 : FontWeight.w400, color: _kInk),
            ),
          ),
      ],
    );
    Widget row(int k) {
      final c = cats[k];
      final strong = k == 0;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _cat = k),
        child: Container(
          decoration: BoxDecoration(
            color: k == ci ? _bg(context, _kMist) : null,
            border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.8)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: nameW,
                height: rowH,
                child: Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: _fg(context, c.color), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${c.name}${c.outflow ? '（流出）' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(context, size: 11.5, weight: strong ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = pts.length - 1; i >= 0; i--)
                Builder(
                  builder: (context) {
                    final x = c.values[i];
                    final dl = _flowDelta(c.values, i);
                    var a = '';
                    var aTone = _kInk2;
                    if (pts[i].partial) {
                      a = '统计中';
                    } else if (dl != null) {
                      a = dl.$1 > 0.5 ? '▲' : (dl.$1 < -0.5 ? '▼' : '–');
                      aTone = _flowUpDown(dl.$1);
                    }
                    return Container(
                      width: cellW,
                      height: rowH,
                      color: colBg(i),
                      padding: const EdgeInsets.only(right: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            x == null ? '—' : _flWan(x, digits: 1),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: _mono(
                              context,
                              size: 11,
                              weight: strong ? FontWeight.w700 : FontWeight.w500,
                              color: pts[i].partial ? _kInk2 : _kInk,
                            ),
                          ),
                          if (a.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(a, style: _sans(context, size: 9.5, color: aTone)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, for (var k = 0; k < cats.length; k++) row(k)],
      ),
    );
  }
}

/// 卡片底部的小柱：这一类每期的量（取绝对值），选中的一期上色，还在变的画淡，没快照不画。
class _FlowMiniBarsPainter extends CustomPainter {
  _FlowMiniBarsPainter({
    required this.values,
    required this.partial,
    required this.selected,
    required this.on,
    required this.off,
    required this.faded,
  });

  final List<double?> values;
  final List<bool> partial;
  final int selected;
  final Color on;
  final Color off;
  final Color faded;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    var mx = 0.0;
    for (final v in values) {
      if (v != null && v.abs() > mx) mx = v.abs();
    }
    if (mx <= 0) mx = 1;
    final slot = size.width / n;
    final bw = math.max(1.0, slot * (n > 20 ? 0.7 : 0.78));
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final h = math.max(2.0, v.abs() / mx * size.height);
      final c = i == selected ? on : (partial[i] ? faded : off);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(slot * i + (slot - bw) / 2, size.height - h, bw, h),
          topLeft: const Radius.circular(1.5),
          topRight: const Radius.circular(1.5),
        ),
        Paint()..color = c,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlowMiniBarsPainter old) => true;
}

class _FlowLegendLinePainter extends CustomPainter {
  _FlowLegendLinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final p = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1.3 : 2;
    if (dashed) {
      for (var x = 0.0; x < size.width; x += 5) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), p);
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      canvas.drawCircle(Offset(size.width / 2, y), 2.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowLegendLinePainter old) => old.color != color || old.dashed != dashed;
}

/// 主图：一类的柱图。左边刻度，柱顶写数，最高 / 最低贴标签，均值画虚线，底下写期名和环比。
class _FlowFocusPainter extends CustomPainter {
  _FlowFocusPainter({
    required this.values,
    required this.labels,
    required this.partial,
    required this.selected,
    required this.color,
    required this.ink,
    required this.ink2,
    required this.mute,
    required this.grid,
    required this.axis,
    required this.highlight,
    required this.up,
    required this.down,
    required this.avgWord,
    required this.textScale,
  });

  static const double height = 262;
  static const double _left = 50;
  static const double _top = 42;
  static const double _bottom = 40;
  static const double _negRoom = 34;

  final List<double?> values;
  final List<String> labels;
  final List<bool> partial;
  final int selected;
  final Color color;
  final Color ink;
  final Color ink2;
  final Color mute;
  final Color grid;
  final Color axis;
  final Color highlight;
  final Color up;
  final Color down;
  final String avgWord;
  final TextScaler textScale;

  int? indexAt(double dx, double width) {
    final n = values.length;
    if (n == 0 || dx < _left) return null;
    final slot = (width - _left) / n;
    return math.max(0, math.min(n - 1, ((dx - _left) / slot).floor()));
  }

  static double _niceStep(double x) {
    if (x <= 0) return 1;
    final pow = math.pow(10, (math.log(x) / math.ln10).floor()).toDouble();
    final m = x / pow;
    final k = m <= 1 ? 1.0 : (m <= 2 ? 2.0 : (m <= 2.5 ? 2.5 : (m <= 5 ? 5.0 : 10.0)));
    return k * pow;
  }

  TextPainter _tp(String text, double size, Color c, {FontWeight weight = FontWeight.w500, bool mono = false}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: c,
          fontWeight: weight,
          fontFamily: mono ? DunesTypography.monoFamily : null,
          fontFamilyFallback: mono ? DunesTypography.monoFallback : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScale,
      maxLines: 1,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final plotW = size.width - _left;
    final slot = plotW / n;

    var lo = 0.0, hi = 0.0, sum = 0.0;
    var cnt = 0;
    int? maxI;
    int? minI;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
      if (partial[i]) continue;
      sum += v;
      cnt += 1;
      if (maxI == null || v > values[maxI]!) maxI = i;
      if (minI == null || v < values[minI]!) minI = i;
    }
    final step = _niceStep((hi - lo) / 4);
    final top = (hi / step).ceil() * step;
    final bottom = (lo / step).floor() * step;
    final range = (top - bottom) <= 0 ? step : top - bottom;
    // 有负数时，图底下留一截给负数柱下面的数和「最低」标签，不压到月份上。
    final negRoom = lo < 0 ? _negRoom : 0.0;
    final plotH = size.height - _top - _bottom - negRoom;
    double y(double v) => _top + (top - v) / range * plotH;
    final zeroY = y(0);

    // 选中列底色
    if (selected >= 0 && selected < n) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(_left + slot * selected, _top - 26, slot, plotH + 26 + negRoom + _bottom), const Radius.circular(6)),
        Paint()..color = highlight,
      );
    }

    // 刻度 + 网格
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var t = bottom; t <= top + step / 2; t += step) {
      final ty = y(t);
      canvas.drawLine(Offset(_left, ty), Offset(size.width, ty), gridPaint);
      final tp = _tp(_flWan(t, digits: 0), 10, mute, mono: true);
      tp.paint(canvas, Offset(_left - 6 - tp.width, ty - tp.height / 2));
    }
    canvas.drawLine(Offset(_left, zeroY), Offset(size.width, zeroY), Paint()
      ..color = axis
      ..strokeWidth = 1.2);

    final roomy = slot >= 38;
    final labelEvery = math.max(1, (44 / slot).ceil());
    final bw = math.max(3.0, math.min(30.0, slot * 0.58));
    for (var i = 0; i < n; i++) {
      final v = values[i];
      final cx = _left + slot * (i + 0.5);
      final isSel = i == selected;
      if (v == null) {
        canvas.drawLine(Offset(cx - bw / 2, zeroY), Offset(cx + bw / 2, zeroY), Paint()
          ..color = mute
          ..strokeWidth = 2);
      } else {
        final y0 = math.min(zeroY, y(v));
        final h = math.max(2.0, (y(v) - zeroY).abs());
        final rect = Rect.fromLTWH(cx - bw / 2, y0, bw, h);
        final fill = Paint()
          ..color = isSel ? color : color.withAlpha(partial[i] ? 60 : 110);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), fill);
        if (partial[i]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()
              ..color = color.withAlpha(160)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
        // 柱顶的数
        var labelTop = v >= 0 ? y0 - 7 : y0 + h + 7;
        if (roomy || isSel) {
          final tp = _tp(_flWan(v, digits: 1), 10, isSel ? ink : ink2, weight: isSel ? FontWeight.w700 : FontWeight.w500, mono: true);
          final ly = v >= 0 ? labelTop - tp.height : labelTop;
          tp.paint(canvas, Offset(cx - tp.width / 2, ly));
          labelTop = v >= 0 ? ly - 2 : ly + tp.height + 2;
        }
        // 最高 / 最低
        if (i == maxI || i == minI) {
          final isMax = i == maxI;
          final tp = _tp(isMax ? '最高' : '最低', 9, isMax ? up : down, weight: FontWeight.w700);
          final ty = v >= 0 ? labelTop - tp.height - 2 : labelTop + 2;
          final r = Rect.fromLTWH(cx - tp.width / 2 - 3, ty - 1, tp.width + 6, tp.height + 2);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..color = (isMax ? up : down).withAlpha(30));
          tp.paint(canvas, Offset(cx - tp.width / 2, ty));
        }
      }
      // 底下：期名 + 环比
      // 窄屏隔 labelEvery 个写一个月份；选中的月份一定写，它左右 labelEvery 以内的让开，免得叠字。
      final nearSel = selected >= 0 && i != selected && (i - selected).abs() < labelEvery;
      final showLabel = isSel || (!nearSel && i % labelEvery == 0);
      if (showLabel) {
        final tp = _tp(labels[i], 10, isSel ? ink : ink2, weight: isSel ? FontWeight.w700 : FontWeight.w500);
        tp.paint(canvas, Offset(cx - tp.width / 2, size.height - _bottom + 6));
      }
      if (roomy || isSel) {
        String text;
        Color tone;
        if (partial[i]) {
          text = '统计中';
          tone = mute;
        } else {
          final dl = _flowDelta(values, i);
          if (dl == null || dl.$2 == null) {
            text = '—';
            tone = mute;
          } else {
            text = '${dl.$1 > 0.5 ? '▲' : (dl.$1 < -0.5 ? '▼' : '')}${dl.$2!.abs().toStringAsFixed(1)}%';
            tone = dl.$1 > 0.5 ? up : (dl.$1 < -0.5 ? down : mute);
          }
        }
        final tp = _tp(text, 9.5, tone, weight: FontWeight.w600, mono: true);
        tp.paint(canvas, Offset(cx - tp.width / 2, size.height - _bottom + 22));
      }
    }

    // 均值虚线 + 标签
    if (cnt > 0) {
      final avg = sum / cnt;
      final ay = y(avg);
      final dash = Paint()
        ..color = color
        ..strokeWidth = 1.3;
      for (var x = _left; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, ay), Offset(math.min(x + 4, size.width), ay), dash);
      }
    }
    // 走势线：连每根柱子的顶，没快照处断开；接到还在变的那一期画虚线。
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final lineFaded = Paint()
      ..color = color.withAlpha(130)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    Offset? prev;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) {
        prev = null;
        continue;
      }
      final o = Offset(_left + slot * (i + 0.5), y(v));
      if (prev != null) {
        if (partial[i]) {
          final d = o - prev;
          final len = d.distance;
          for (var t = 0.0; t < len; t += 6) {
            final a = prev + d * (t / len);
            final b = prev + d * (math.min(t + 3, len) / len);
            canvas.drawLine(a, b, lineFaded);
          }
        } else {
          canvas.drawLine(prev, o, line);
        }
      }
      prev = o;
    }
    final ring = Paint()..color = highlight;
    final dot = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final o = Offset(_left + slot * (i + 0.5), y(v));
      final r = i == selected ? 4.2 : 3.0;
      canvas.drawCircle(o, r + 1.4, ring);
      canvas.drawCircle(o, r, partial[i] ? (Paint()..color = color.withAlpha(130)) : dot);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowFocusPainter old) => true;
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
