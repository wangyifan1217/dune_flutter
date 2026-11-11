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
  const LhBizLinks({super.key, required this.openSupply, this.back, required super.child});

  /// [province] 是灯塔供给方行名（湖南省 / 内蒙古自治区），[group] 是中石油 / 中石化，可空。
  final void Function(String province, String group)? openSupply;

  /// 子页「返回」先问宿主：从灯塔直接跳进来的页（如阶梯详情）返回要回灯塔，宿主处理了返回 true。
  final bool Function()? back;

  static LhBizLinks? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<LhBizLinks>();

  @override
  bool updateShouldNotify(LhBizLinks oldWidget) => oldWidget.openSupply != openSupply || oldWidget.back != back;
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
///
/// 2026-11-11 · V2 样式：
///   ① 顶卡：品牌章 + 可达/难达/封顶 · 规则名 · 起止 / 第几天 / 计算于 · 本期累计 · 差多少到几 · 一根刻度尺
///      （各档门槛打刻度，实色已发生，斜纹按日均到期末，游标上挂当前累计）· 三格（当前档 / 日均 / 到期末约）。
///   ② 档位明细：竖向时间线 —— 已过 ✓、当前实心圈、下一档虚线圈 + 预计、之后灰。
///   ③ 灯塔经营：三格 + 一颗「回灯塔看 …」紫按钮。
///   字号不超过灯塔账本卡片：名字 12 / 数值 11.5–12 / 标签 10 / 单位 9。
class LighthouseBizTierPage extends StatefulWidget {
  const LighthouseBizTierPage({super.key, required this.service, required this.ruleId, this.fromLighthouse = false});

  final LighthouseService service;
  final String ruleId;

  /// 从灯塔阶梯卡片直接跳进来：返回按钮写「灯塔」，返回直接回灯塔（宿主处理）。
  final bool fromLighthouse;

  @override
  State<LighthouseBizTierPage> createState() => _BizTierState();
}

const Color _kTierTrack = Color(0xFFEFEBF6);
const Color _kTierFillFrom = Color(0xFFB8A6EE);
const Color _kTierProj = Color(0xFFCFC3EE);
const Color _kTierTick = Color(0xFFD6CDEB);
const Color _kTierInk = Color(0xFF2B2147);
const Color _kTierMute = Color(0xFF94938A);
const Color _kTierEdgeOn = Color(0xFFC2AEE7);
const Color _kTierCell = Color(0xFFFAF9FD);
const Color _kTierHair = Color(0xFFF1EEF6);

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

  // ── 小工具 ────────────────────────────────────────────────────────────

  TextStyle _mono(double size, Color color, {FontWeight weight = FontWeight.w500}) =>
      LhTypography.mono(context: context, size: size, color: _fg(context, color), weight: weight);

  static String _ymd(DateTime d) => '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 本期总天数、已过天数、剩余天数（按 asOf）。
  (int, int, int) _days(_TierRule r) {
    final st = r.start, en = r.end, at = r.asOf;
    if (st == null || en == null) return (0, 0, 0);
    final total = math.max(1, en.difference(st).inHours ~/ 24 + 1);
    final now = at ?? DateTime.now();
    final elapsed = (now.difference(st).inHours ~/ 24 + 1).clamp(0, total);
    return (total, elapsed, total - elapsed);
  }

  /// 按本期日均到期末的累计。
  double _projected(_TierRule r) {
    final (_, _, left) = _days(r);
    return r.stat + math.max(0.0, r.rate) * left;
  }

  /// 下一档的费率（「2%」）；封顶 / 没有下一档时空串。
  String _nextRate(_TierRule r) => !r.full && r.level < r.tiers.length ? r.tiers[r.level].$2 : '';

  Widget _chip(String text, Color fg, Color bg, {FontWeight weight = FontWeight.w600}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: _bg(context, bg), borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: _sans(context, size: 10, weight: weight, color: fg, height: 1.45)),
  );

  @override
  Widget build(BuildContext context) {
    final r = _rule;
    final supply = _supply;
    return _bizSubPage(
      context,
      title: '阶梯详情',
      backLabel: widget.fromLighthouse ? '灯塔' : '返回',
      onRefresh: _load,
      children: [
        if (_loading) _bizLoading(),
        if (!_loading && _error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(_error!, textAlign: TextAlign.center, style: _sans(context, size: 12, color: _kMute)),
          ),
        if (!_loading && r != null) ...[
          _progressCard(r),
          _bizSection(context, '档位明细', count: r.tiers.length),
          _tierTimeline(r),
          _bizSection(
            context,
            '灯塔经营',
            note: supply == null ? '' : '${supply.$1}${supply.$3.isEmpty ? '' : ' · ${supply.$3}'} · 本月',
          ),
          _lighthouseCard(r),
        ],
      ],
    );
  }

  // ── ① 顶卡 ─────────────────────────────────────────────────────────────

  Widget _progressCard(_TierRule r) {
    final supply = _supply;
    final group = supply?.$3 ?? '';
    final (total, elapsed, _) = _days(r);
    final asOf = r.asOf;
    final st = r.start, en = r.end;
    final meta = [
      if (st != null && en != null) '${_ymd(st)}–${_ymd(en)}',
      if (total > 0) '第 $elapsed/$total 天',
      if (asOf != null) '计算于 ${_hMd(asOf)} ${_hm(asOf)}',
    ].join(' · ');
    final kind = [_s(r.m['periodType']), _s(r.m['mode']), _s(r.m['base'])].where((e) => e.isNotEmpty).join(' · ');

    final (vLabel, vFg, vBg) = r.full
        ? ('封顶', _kMute, _kGreySoft)
        : (r.reachable ? ('可达', _kDeep, _kLavender) : ('难达', _kMute, _kGreySoft));

    final nextRate = _nextRate(r);
    final statRaw = _wan(r.stat);
    final unit = RegExp(r'^(.*?)(万|亿)$').firstMatch(statRaw);
    final projected = _projected(r);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _cardDeco(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (group.isNotEmpty) _chip(group, lhGroupColor(group), lhGroupColor(group).withAlpha(26)),
                    if (kind.isNotEmpty) Text(kind, style: _sans(context, size: 10, color: _kTierMute)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _chip(vLabel, vFg, vBg, weight: FontWeight.w700),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.name, style: _sans(context, size: 12, weight: FontWeight.w700, height: 1.4)),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta, style: _mono(10, _kTierMute, weight: FontWeight.w400)),
          ],
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: unit?.group(1) ?? statRaw, style: _mono(12, _kTierInk, weight: FontWeight.w700)),
                if (unit != null) TextSpan(text: unit.group(2), style: _sans(context, size: 9, color: _kTierMute)),
                TextSpan(text: '  本期累计', style: _sans(context, size: 10, color: _kTierMute)),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: r.full
                  ? [TextSpan(text: '已到最高档 ${r.discount}', style: _mono(11, _kInk, weight: FontWeight.w600))]
                  : [
                      TextSpan(text: '差 ${_wan(r.gap)}', style: _mono(11, _kInk, weight: FontWeight.w600)),
                      if (nextRate.isNotEmpty) ...[
                        TextSpan(text: ' 到 ', style: _sans(context, size: 10.5, color: _kInk2)),
                        TextSpan(text: nextRate, style: _mono(11, _kPurple, weight: FontWeight.w700)),
                      ],
                      TextSpan(
                        text: r.reachable && r.eta != null ? '  · 预计 ${_hMd(r.eta!)} 到' : '  · 本期难达',
                        style: _sans(context, size: 10.5, weight: FontWeight.w500, color: r.reachable ? _kPurple : _kTierMute),
                      ),
                    ],
            ),
          ),
          const SizedBox(height: 10),
          _ruler(r, projected),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _cell('当前档', r.discount)),
              const SizedBox(width: 6),
              Expanded(child: _cell('日均', r.rate > 0 ? _wan(r.rate) : '—')),
              const SizedBox(width: 6),
              Expanded(child: _cell('到期末约', r.full || r.rate <= 0 ? '—' : _wan(projected), strong: !r.full && r.rate > 0)),
            ],
          ),
          if (!r.full && r.rate > 0 && nextRate.isNotEmpty && r.next != null) ...[
            const SizedBox(height: 8),
            Text(
              projected >= r.next!
                  ? '按本期日均 ${_wan(r.rate)}/天，到期末约 ${_wan(projected)}，能过 $nextRate 档。'
                  : '按本期日均 ${_wan(r.rate)}/天，到期末约 ${_wan(projected)}，还差 ${_wan(r.next! - projected)} 才到 $nextRate 档。',
              style: _sans(context, size: 10.5, color: _kMute, height: 1.55),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(String label, String value, {bool strong = false}) => Container(
    padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
    decoration: BoxDecoration(
      color: _bg(context, strong ? _kHeroFill : _kTierCell),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: _ln(context, strong ? _kTierEdgeOn : _kTierCell), width: 0.9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _sans(context, size: 10, color: strong ? _kPurple : _kMute)),
        const SizedBox(height: 2),
        Text(value, style: _mono(11.5, strong ? _kHeroNum : _kInk, weight: FontWeight.w700)),
      ],
    ),
  );

  /// 刻度尺：各档门槛打刻度，游标挂当前累计，下面一行「费率 / 门槛」。
  Widget _ruler(_TierRule r, double projected) {
    final mins = [for (final t in r.tiers) t.$1];
    final last = mins.isEmpty ? 0.0 : mins.last;
    var maxV = last;
    final over = math.max(r.stat, r.full ? r.stat : projected);
    if (over > maxV) maxV = over * 1.05;
    if (maxV <= 0) maxV = math.max(1.0, r.stat);
    double at(double v) => (v / maxV).clamp(0.0, 1.0).toDouble();
    final fill = at(r.stat);
    final proj = r.full ? fill : at(projected);
    final reached = r.full ? r.tiers.length : r.level;

    return LayoutBuilder(
      builder: (context, c) {
        const pad = 6.0;
        final w = c.maxWidth - pad * 2;
        // 游标上方的当前累计小牌，左右夹住不出界。
        const tagW = 52.0;
        final tagLeft = (pad + w * fill - tagW / 2).clamp(0.0, c.maxWidth - tagW).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 16,
              child: Stack(
                children: [
                  Positioned(
                    left: tagLeft,
                    width: tagW,
                    top: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: _bg(context, _kTierInk), borderRadius: BorderRadius.circular(4)),
                        child: Text(_wan(r.stat), maxLines: 1, style: _mono(9, Colors.white, weight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 14,
              child: CustomPaint(
                painter: _TierRulerPainter(
                  pad: pad,
                  ticks: [for (final m in mins) at(m)],
                  reached: reached,
                  fill: fill,
                  projected: proj,
                  track: _bg(context, _kTierTrack),
                  fillFrom: _fg(context, _kTierFillFrom),
                  fillTo: _fg(context, _kPurple),
                  projColor: _fg(context, _kTierProj),
                  tick: _ln(context, _kTierTick),
                  tickOn: _fg(context, _kPurple),
                  knobFill: _bg(context, Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var j = 0; j < r.tiers.length; j++)
                    _rulerLabel(
                      x: pad + w * at(mins[j]),
                      maxW: c.maxWidth,
                      first: j == 0,
                      lastOne: j == r.tiers.length - 1 && at(mins[j]) > 0.9,
                      rate: r.tiers[j].$2,
                      min: mins[j] <= 0 ? '0' : _wan(mins[j]),
                      color: j < reached ? _kDeep : (j == reached && !r.full ? _kPurple : _kTierMute),
                      bold: j <= reached,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _rulerLabel({
    required double x,
    required double maxW,
    required bool first,
    required bool lastOne,
    required String rate,
    required String min,
    required Color color,
    required bool bold,
  }) {
    const w = 56.0;
    final col = Column(
      crossAxisAlignment: first ? CrossAxisAlignment.start : (lastOne ? CrossAxisAlignment.end : CrossAxisAlignment.center),
      children: [
        Text(rate, maxLines: 1, style: _mono(9.5, color, weight: bold ? FontWeight.w700 : FontWeight.w400)),
        Text(min, maxLines: 1, style: _mono(9, _kTierMute, weight: FontWeight.w400)),
      ],
    );
    if (first) return Positioned(left: 0, top: 0, width: w, child: col);
    if (lastOne) return Positioned(right: 0, top: 0, width: w, child: col);
    final left = (x - w / 2).clamp(0.0, maxW - w).toDouble();
    return Positioned(left: left, top: 0, width: w, child: col);
  }

  // ── ② 档位时间线 ───────────────────────────────────────────────────────

  Widget _tierTimeline(_TierRule r) {
    final reachAt = {for (final (lv, at) in r.reaches) lv: at};
    final n = r.tiers.length;
    // 当前所在档（下标）；level=0 表示还没进第 1 档。
    final cur = r.full ? n - 1 : r.level - 1;
    final rows = <Widget>[];
    for (var i = 0; i < n; i++) {
      final passed = i < cur;
      final current = i == cur;
      final isNext = !r.full && i == cur + 1;
      final range = i + 1 < n ? '${i == 0 && r.tiers[i].$1 <= 0 ? '0' : _wan(r.tiers[i].$1)} – ${_wan(r.tiers[i + 1].$1)}' : '${_wan(r.tiers[i].$1)} 以上';
      final title = [
        '第${i + 1}档',
        if (current) '当前',
        if (isNext) '下一档',
        if (i == n - 1 && !current) '最高',
      ].join(' · ');
      final sub = isNext && r.gap != null ? '$range · 差 ${_wan(r.gap)}' : range;

      Widget right;
      if (passed || (current && reachAt[i + 1] != null)) {
        final at = reachAt[i + 1];
        right = Text(at == null ? '已达' : '${_hMd(at)} 已达', style: _sans(context, size: 10, color: _kTierMute));
      } else if (current) {
        right = Text(i == 0 && r.start != null ? '${_hMd(r.start!)} 起' : '当前', style: _sans(context, size: 10, color: _kDeep));
      } else if (isNext) {
        right = r.reachable && r.eta != null
            ? _chip('预计 ${_hMd(r.eta!)}', _kDeep, _kLavender)
            : Text('本期难达', style: _sans(context, size: 10, color: _kTierMute));
      } else {
        right = Text(r.reachable ? '—' : '本期难达', style: _sans(context, size: 10, color: _kTierMute));
      }

      final strong = passed || current;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 18,
                child: CustomPaint(
                  painter: _TierStepPainter(
                    state: passed ? 0 : (current ? 1 : (isNext ? 2 : 3)),
                    lineUp: i > 0,
                    lineDown: i < n - 1,
                    upOn: i <= cur,
                    downOn: i < cur,
                    downDashed: i == cur && !r.full,
                    purple: _fg(context, _kPurple),
                    soft: _fg(context, _kTierEdgeOn),
                    track: _ln(context, _kTierTrack),
                    fill: _bg(context, Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: i == 0 ? null : Border(top: BorderSide(color: _ln(context, _kTierHair), width: 0.8)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: _sans(
                                context,
                                size: 11.5,
                                weight: FontWeight.w600,
                                color: current ? _kDeep : (strong || isNext ? _kInk : _kTierMute),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(sub, style: _mono(10, _kTierMute, weight: FontWeight.w400)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            r.tiers[i].$2,
                            style: _mono(11.5, isNext ? _kPurple : (strong ? _kInk : _kTierMute), weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          right,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 14, 2),
      decoration: _cardDeco(context, radius: 16),
      child: Column(children: rows),
    );
  }

  // ── ③ 灯塔经营 ─────────────────────────────────────────────────────────

  Widget _lighthouseCard(_TierRule r) {
    final supply = _supply;
    if (supply == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('认不出这条规则对应灯塔的哪家供给方（规则名 / 供应商名里没有省份）。', style: _sans(context, size: 11, color: _kMute)),
      );
    }
    final d = _lh;
    final sales = _hNum(d?['sales']);
    final profit = _hNum(d?['profit']);
    final cover = sales != null && sales > 0 ? '${(r.stat / sales * 100).round()}%' : '—';
    final canJump = LhBizLinks.maybeOf(context)?.openSupply != null;
    return Container(
      decoration: _cardDeco(context, radius: 16),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_lhLoading)
            const SizedBox(
              height: 40,
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))),
            )
          else if (_lhError != null)
            Text(_lhError!, style: _sans(context, size: 11, color: _kMute))
          else ...[
            Row(
              children: [
                Expanded(child: _metricCell('销售额', sales == null ? '—' : _wan(sales))),
                const SizedBox(width: 6),
                Expanded(child: _metricCell('利润', profit == null ? '—' : _wan(profit), color: _kCoral)),
                const SizedBox(width: 6),
                Expanded(child: _metricCell('规则覆盖', cover)),
              ],
            ),
            if (sales != null) ...[
              const SizedBox(height: 8),
              Text(
                '规则累计 ÷ 灯塔本月销售；规则只算挂上的产品，两边不相等是正常的。',
                style: _sans(context, size: 10, color: _kTierMute, height: 1.5),
              ),
            ],
          ],
          if (canJump) ...[
            const SizedBox(height: 10),
            Semantics(
              button: true,
              label: '回灯塔查看${supply.$1}${supply.$3}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openLighthouseSupply(context, supply),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: _bg(context, _kPurple), borderRadius: BorderRadius.circular(11)),
                  child: Row(
                    children: [
                      Icon(Icons.flare_rounded, size: 15, color: _fg(context, Colors.white)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '回灯塔看 ${supply.$1}${supply.$3.isEmpty ? '' : ' · ${supply.$3}'}',
                          style: _sans(context, size: 11.5, weight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: _fg(context, Colors.white)),
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

  Widget _metricCell(String label, String value, {Color color = _kInk}) {
    final m = RegExp(r'^(.*?)(万|亿)$').firstMatch(value);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      decoration: BoxDecoration(color: _bg(context, _kTierCell), borderRadius: BorderRadius.circular(9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sans(context, size: 10, color: _kMute)),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: m?.group(1) ?? value, style: _mono(11.5, color, weight: FontWeight.w700)),
                if (m != null) TextSpan(text: m.group(2), style: _sans(context, size: 9, color: _kTierMute)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶卡刻度尺：6px 轨道 · 渐变实色（已发生）· 斜纹（按日均到期末）· 各档刻度 · 白芯紫圈游标。
class _TierRulerPainter extends CustomPainter {
  _TierRulerPainter({
    required this.pad,
    required this.ticks,
    required this.reached,
    required this.fill,
    required this.projected,
    required this.track,
    required this.fillFrom,
    required this.fillTo,
    required this.projColor,
    required this.tick,
    required this.tickOn,
    required this.knobFill,
  });

  final double pad;
  final List<double> ticks;
  final int reached;
  final double fill;
  final double projected;
  final Color track, fillFrom, fillTo, projColor, tick, tickOn, knobFill;

  @override
  void paint(Canvas canvas, Size size) {
    const barH = 6.0;
    final w = size.width - pad * 2;
    final top = (size.height - barH) / 2;
    const r = Radius.circular(barH / 2);
    final whole = RRect.fromRectAndRadius(Rect.fromLTWH(pad, top, w, barH), r);
    final fx = pad + w * fill;
    final px = pad + w * projected;

    canvas.save();
    canvas.clipRRect(whole);
    canvas.drawRRect(whole, Paint()..color = track);
    if (px > fx) {
      final zone = Rect.fromLTRB(fx, top, px, top + barH);
      canvas.drawRect(zone, Paint()..color = projColor.withAlpha(90));
      final stripe = Paint()
        ..color = projColor
        ..strokeWidth = 1.6;
      canvas.save();
      canvas.clipRect(zone);
      for (var x = fx - barH; x < px + barH; x += 4.5) {
        canvas.drawLine(Offset(x, top + barH), Offset(x + barH, top), stripe);
      }
      canvas.restore();
    }
    if (fx > pad) {
      final rect = Rect.fromLTRB(pad, top, fx, top + barH);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..shader = LinearGradient(colors: [fillFrom, fillTo]).createShader(rect));
    }
    canvas.restore();

    // 刻度：已到的档紫色，下一档紫色加粗，其余淡紫。第 0 档在最左，不画。
    for (var j = 0; j < ticks.length; j++) {
      final x = pad + w * ticks[j];
      if (ticks[j] <= 0) continue;
      final on = j < reached;
      final isNext = j == reached;
      canvas.drawLine(
        Offset(x, isNext ? 0 : 2),
        Offset(x, size.height - (isNext ? 0 : 2)),
        Paint()
          ..color = on || isNext ? tickOn : tick
          ..strokeWidth = isNext ? 1.6 : 1,
      );
    }

    if (fill > 0 && fill < 1) {
      final c = Offset(fx, size.height / 2);
      canvas.drawCircle(c, 6.5, Paint()..color = tickOn.withAlpha(40));
      canvas.drawCircle(c, 5, Paint()..color = knobFill);
      canvas.drawCircle(
        c,
        5,
        Paint()
          ..color = fillTo
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_TierRulerPainter old) =>
      old.fill != fill || old.projected != projected || old.reached != reached || old.track != track || old.ticks.length != ticks.length;
}

/// 档位时间线左边的竖线 + 节点：0 已过（实心 ✓）· 1 当前（白芯紫圈）· 2 下一档（虚线圈）· 3 之后（灰点）。
class _TierStepPainter extends CustomPainter {
  _TierStepPainter({
    required this.state,
    required this.lineUp,
    required this.lineDown,
    required this.upOn,
    required this.downOn,
    required this.downDashed,
    required this.purple,
    required this.soft,
    required this.track,
    required this.fill,
  });

  final int state;
  final bool lineUp, lineDown, upOn, downOn, downDashed;
  final Color purple, soft, track, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final line = Paint()..strokeWidth = 2;
    if (lineUp) {
      line.color = upOn ? purple : track;
      canvas.drawLine(Offset(cx, 0), Offset(cx, cy - 7), line);
    }
    if (lineDown) {
      if (downDashed) {
        final p = Paint()
          ..color = soft
          ..strokeWidth = 2;
        for (var y = cy + 7; y < size.height; y += 6) {
          canvas.drawLine(Offset(cx, y), Offset(cx, math.min(y + 3, size.height)), p);
        }
      } else {
        line.color = downOn ? purple : track;
        canvas.drawLine(Offset(cx, cy + 7), Offset(cx, size.height), line);
      }
    }
    final c = Offset(cx, cy);
    switch (state) {
      case 0:
        canvas.drawCircle(c, 6, Paint()..color = purple);
        final tick = Paint()
          ..color = fill
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(
          Path()
            ..moveTo(cx - 2.6, cy + 0.2)
            ..lineTo(cx - 0.6, cy + 2.2)
            ..lineTo(cx + 2.8, cy - 1.8),
          tick,
        );
      case 1:
        canvas.drawCircle(c, 6, Paint()..color = fill);
        canvas.drawCircle(
          c,
          5.5,
          Paint()
            ..color = purple
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      case 2:
        canvas.drawCircle(c, 6, Paint()..color = track);
        final dash = Paint()
          ..color = purple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        for (var a = 0.0; a < math.pi * 2; a += math.pi / 4) {
          canvas.drawArc(Rect.fromCircle(center: c, radius: 5.5), a, math.pi / 8, false, dash);
        }
      default:
        canvas.drawCircle(c, 4.5, Paint()..color = track);
    }
  }

  @override
  bool shouldRepaint(_TierStepPainter old) =>
      old.state != state || old.upOn != upOn || old.downOn != downOn || old.downDashed != downDashed || old.purple != purple;
}
