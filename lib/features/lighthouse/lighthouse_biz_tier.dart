part of 'lighthouse_biz.dart';

// ════════════════════════════════════════════════════════════════════════
// 业务 ↔ 灯塔 联动（2026-11-10）
//
//   · 供应商产品卡片底部一根淡紫细线：产品挂的阶梯规则本期进度（business-go ProductCard.tier），
//     右侧「灯塔 广东 ›」直接跳到灯塔供给方详情；
//   · /tier 阶梯详情页：一条规则的本期累计、分档细线、档位明细，加一块「灯塔经营」——
//     这家供应商本月在灯塔的销售额、利润，以及规则累计占灯塔销售的比例（规则覆盖）。
//   · 灯塔供给方卡片底边的折扣细条点进来也落到 /tier。
//   金额都是两边各自的原值：规则进度来自业务侧计算记录，经营数来自灯塔 /detail，互不重算。
// ════════════════════════════════════════════════════════════════════════

const Color _kThinFill = Color(0xFFB5AAD5);
const Color _kThinNear = Color(0xFF9C8CD0);
const Color _kThinCapped = Color(0xFFDCD5EC);

/// 业务页里能拿到的「跳回灯塔」入口；宿主（灯塔页）挂在 Navigator 外面。
class LhBizLinks extends InheritedWidget {
  const LhBizLinks({super.key, required this.openSupply, required super.child});

  /// [province] 是灯塔供给方行名（湖南省 / 内蒙古自治区），[group] 是中石油 / 中石化，可空。
  final void Function(String province, String group)? openSupply;

  static LhBizLinks? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<LhBizLinks>();

  @override
  bool updateShouldNotify(LhBizLinks oldWidget) => oldWidget.openSupply != openSupply;
}

const List<String> _kLhProvinces = [
  '内蒙古', '黑龙江', '宁夏', '广西', '新疆', '西藏',
  '北京', '天津', '上海', '重庆',
  '河北', '山西', '辽宁', '吉林', '江苏', '浙江', '安徽', '福建', '江西', '山东',
  '河南', '湖北', '湖南', '广东', '海南', '四川', '贵州', '云南', '陕西', '甘肃',
  '青海',
];

const Map<String, String> _kLhProvinceFull = {
  '北京': '北京市', '天津': '天津市', '上海': '上海市', '重庆': '重庆市',
  '内蒙古': '内蒙古自治区', '广西': '广西壮族自治区', '西藏': '西藏自治区',
  '宁夏': '宁夏回族自治区', '新疆': '新疆维吾尔自治区',
};

/// 从省份字段 / 供应商名里认出灯塔供给方：(行名「湖南省」, 简称「湖南」, 分类「中石油」)。
(String, String, String)? _lhSupplyOf(String provinceRaw, String supplierText) {
  String short = '';
  for (final source in [provinceRaw, supplierText]) {
    for (final p in _kLhProvinces) {
      if (source.contains(p)) {
        short = p;
        break;
      }
    }
    if (short.isNotEmpty) break;
  }
  if (short.isEmpty) return null;
  final t = '$supplierText $provinceRaw';
  final group = t.contains('中石油') || t.contains('中国石油') || t.contains('中油')
      ? '中石油'
      : (t.contains('中石化') || t.contains('中国石化') ? '中石化' : '');
  return (_kLhProvinceFull[short] ?? '$short省', short, group);
}

void _openLighthouseSupply(BuildContext context, (String, String, String) supply) {
  final open = LhBizLinks.maybeOf(context)?.openSupply;
  if (open == null) return;
  open(supply.$1, supply.$3);
}

/// 供应商产品卡片底部：一根细线 + 一行小字 + 右侧「灯塔 广东 ›」。没有阶梯规则时不出现。
Widget _bizProductTierLine(BuildContext context, Map<String, dynamic> p) {
  final t = _map(p['tier']);
  if (t.isEmpty) return const SizedBox.shrink();
  final level = _i(t['level']) ?? 0;
  final full = t['full'] == true;
  final stat = _hNum(t['stat']) ?? 0;
  final next = _hNum(t['next']);
  final gap = _hNum(t['gap']);
  final eta = _hDt(t['eta']);
  final reachable = t['reachable'] == true;
  final shared = _i(t['shared']) ?? 0;
  final more = _i(t['more']) ?? 0;
  final rel = _s(t['relType']);
  final ruleId = _s(t['ruleId']);
  final progress = full ? 1.0 : (next != null && next > 0 ? (stat / next).clamp(0.0, 1.0).toDouble() : 0.0);
  final state = full
      ? '已封顶 ${_rate(t['discount'])}'
      : '第$level档 · 差 ¥${_wan(gap)}${reachable && eta != null ? ' · 预计 ${_hMd(eta)}' : ''}';
  final relLabel = rel == '2' ? (shared > 1 ? ' · 共享进度' : ' · 计入核算') : (rel == '1' ? ' · 折扣取值' : '');
  final text = '阶梯 · ${_s(t['name'])} · $state$relLabel${more > 0 ? ' · +$more 条' : ''}';
  final color = full ? _kThinCapped : (progress >= 0.9 ? _kThinNear : _kThinFill);
  final supply = _lhSupplyOf(_s(p['provinceName']), '${_s(p['partner'])} ${_s(p['chainSupplier'])}');
  final canJump = supply != null && LhBizLinks.maybeOf(context)?.openSupply != null;
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            button: ruleId.isNotEmpty,
            label: '$text，查看阶梯详情',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: ruleId.isEmpty ? null : () => Navigator.of(context).pushNamed('/tier', arguments: {'ruleId': ruleId}),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LhThinProgressBar(progress: progress, color: color),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w400, color: _fg(context, _kMute)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (canJump) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: '在灯塔查看${supply.$1}${supply.$3}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openLighthouseSupply(context, supply),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('灯塔 ${supply.$2}', style: _sans(context, size: 11, color: _kDeep)),
                    Icon(Icons.chevron_right_rounded, size: 14, color: _fg(context, _kDeep)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// /tier：一条阶梯规则的本期进度 + 灯塔经营。规则数据取业务总览的 tierBoard（与跨档进度同一份）。
class LighthouseBizTierPage extends StatefulWidget {
  const LighthouseBizTierPage({super.key, required this.service, required this.ruleId});

  final LighthouseService service;
  final String ruleId;

  @override
  State<LighthouseBizTierPage> createState() => _BizTierState();
}

class _BizTierState extends State<LighthouseBizTierPage> {
  _TierRule? _rule;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _lh;
  bool _lhLoading = false;
  String? _lhError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await widget.service.fetchBizOverview();
      final rules = [for (final r in _list(_map(o['tierBoard'])['rules'])) _TierRule(r)];
      _TierRule? hit;
      for (final r in rules) {
        if (r.id == widget.ruleId) {
          hit = r;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _rule = hit;
        _loading = false;
        if (hit == null) _error = '这条规则本期还没有计算记录，或不是阶梯计费规则。';
      });
      if (hit != null) unawaited(_loadLighthouse(hit));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  (String, String, String)? get _supply {
    final r = _rule;
    if (r == null) return null;
    return _lhSupplyOf('', '${_s(r.m['supplier'])} ${r.name}');
  }

  Future<void> _loadLighthouse(_TierRule r) async {
    final supply = _supply;
    if (supply == null) return;
    setState(() {
      _lhLoading = true;
      _lhError = null;
    });
    try {
      final key = supply.$3.isEmpty ? supply.$1 : '${supply.$1}::${supply.$3}';
      final d = await widget.service.fetchDetail(tab: 'supply', key: key, period: 'month');
      if (!mounted) return;
      setState(() {
        _lh = d;
        _lhLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lhLoading = false;
        _lhError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _rule;
    return _bizSubPage(
      context,
      title: '阶梯详情',
      onRefresh: _load,
      children: [
        if (_loading) _bizLoading(),
        if (!_loading && _error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(_error!, textAlign: TextAlign.center, style: _sans(context, size: 12, color: _kMute)),
          ),
        if (!_loading && r != null) ...[
          _progressCard(context, r),
          _bizSection(context, '档位明细', count: r.tiers.length),
          _tierTable(context, r),
          _bizSection(context, '灯塔经营', note: _supply == null ? '' : '供给方 · ${_supply!.$1}${_supply!.$3.isEmpty ? '' : ' ${_supply!.$3}'} · 本月'),
          _lighthouseCard(context, r),
        ],
      ],
    );
  }

  Widget _progressCard(BuildContext context, _TierRule r) {
    final period = '${_date(r.m['periodStart'])}–${_date(r.m['periodEnd'])}';
    final asOf = r.asOf;
    final asOfLabel = asOf == null ? '' : ' · 计算于 ${_hMd(asOf)} ${asOf.hour.toString().padLeft(2, '0')}:${asOf.minute.toString().padLeft(2, '0')}';
    final read = r.full
        ? '已到最高档 ${r.discount}。'
        : '第 ${r.level} 档 ${r.discount}，差 ¥${_wan(r.gap)} 到下一档；'
              '${r.reachable && r.eta != null ? '按本期日均预计 ${_hMd(r.eta!)} 到。' : '按本期日均本期难达。'}';
    final segs = math.max(1, r.tiers.length);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.name, style: _sans(context, size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('$period$asOfLabel', style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute))),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('¥${_wan(r.stat)}', style: _num(context, size: 20, color: _kHeroNum)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  r.full || r.next == null ? '本期累计' : '本期累计 / 下一档 ¥${_wan(r.next)}',
                  style: _sans(context, size: 11, color: _kMute),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var j = 0; j < segs; j++) ...[
                if (j > 0) const SizedBox(width: 3),
                Expanded(
                  child: LhThinProgressBar(
                    // 与跨档进度同一口径：第 j 段 = 爬到第 j+1 档，已到的段满，正在爬的段按进度。
                    progress: r.full || j < r.level
                        ? 1.0
                        : (j == r.level ? r.frac : 0.0),
                    color: r.full ? _kThinCapped : _kThinFill,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              for (var j = 0; j < r.tiers.length; j++) ...[
                if (j > 0) const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    '${r.tiers[j].$2}\n${_wan(r.tiers[j].$1)}',
                    style: LhTypography.mono(
                      context: context,
                      size: 9.5,
                      color: _fg(context, j < r.level ? _kDeep : _kMute),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(read, style: _sans(context, size: 12, color: _kInk2, height: 1.55)),
        ],
      ),
    );
  }

  Widget _tierTable(BuildContext context, _TierRule r) {
    final reachAt = {for (final (lv, at) in r.reaches) lv: at};
    return Container(
      decoration: _cardDeco(context, radius: 16),
      child: Column(
        children: [
          for (var i = 0; i < r.tiers.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: _ln(context, _kLine), width: 0.8)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text('第${i + 1}档', style: _sans(context, size: 12.5, weight: FontWeight.w600, color: i < r.level ? _kHeroNum : _kMute)),
                  ),
                  Expanded(
                    child: Text(
                      i + 1 < r.tiers.length ? '¥${_wan(r.tiers[i].$1)} – ${_wan(r.tiers[i + 1].$1)}' : '¥${_wan(r.tiers[i].$1)} 以上',
                      style: LhTypography.mono(context: context, size: 11, color: _fg(context, _kInk2)),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(r.tiers[i].$2, textAlign: TextAlign.right, style: LhTypography.mono(context: context, size: 11.5, color: _fg(context, _kInk))),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text(
                      reachAt[i + 1] != null
                          ? '${_hMd(reachAt[i + 1]!)} 已达'
                          : (i == r.level && r.reachable && r.eta != null ? '预计 ${_hMd(r.eta!)}' : (i < r.level ? '已达' : '—')),
                      textAlign: TextAlign.right,
                      style: LhTypography.mono(context: context, size: 10, color: _fg(context, _kMute)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lighthouseCard(BuildContext context, _TierRule r) {
    final supply = _supply;
    if (supply == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('认不出这条规则对应灯塔的哪家供给方（规则名 / 供应商名里没有省份）。', style: _sans(context, size: 11.5, color: _kMute)),
      );
    }
    final d = _lh;
    Widget metric(String label, String value, {Color color = _kInk}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sans(context, size: 11, color: _kInk2)),
          const SizedBox(height: 3),
          Text(value, style: _num(context, size: 15, color: color)),
        ],
      ),
    );
    final sales = _hNum(d?['sales']);
    final profit = _hNum(d?['profit']);
    final cover = sales != null && sales > 0 ? '${(r.stat / sales * 100).round()}%' : '—';
    return Container(
      decoration: _cardDeco(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: _lhLoading
                ? const SizedBox(height: 40, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))))
                : (_lhError != null
                      ? Text(_lhError!, style: _sans(context, size: 11.5, color: _kMute))
                      : Row(
                          children: [
                            metric('销售额', sales == null ? '—' : _wan(sales)),
                            metric('利润', profit == null ? '—' : _wan(profit), color: _kCoral),
                            metric('规则覆盖', cover),
                          ],
                        )),
          ),
          if (!_lhLoading && _lhError == null && sales != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                '规则累计 ¥${_wan(r.stat)} ÷ 灯塔本月销售 ${_wan(sales)}；规则只算挂在上面的产品，两边不相等是正常的。',
                style: _sans(context, size: 11, color: _kMute, height: 1.5),
              ),
            ),
          if (LhBizLinks.maybeOf(context)?.openSupply != null)
            Semantics(
              button: true,
              label: '在灯塔查看${supply.$1}${supply.$3}',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => _openLighthouseSupply(context, supply),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.8))),
                  child: Row(
                    children: [
                      Expanded(child: Text('在灯塔查看${supply.$1}${supply.$3.isEmpty ? '' : ' · ${supply.$3}'}', style: _sans(context, size: 12.5, color: _kDeep))),
                      Icon(Icons.chevron_right_rounded, size: 16, color: _fg(context, _kDeep)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
