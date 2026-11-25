import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 产品利润构成（2026-11-25 · 原型「手机 · 利润分布展开态」）
//
//   产品汇总卡「利润分布」点开后，主 Hero 原地换成这一块：当前周期的钱是哪几个
//   产品挣的、哪几个在亏。上面的「利润 | 资金 · 今日 | 本月 · 利润分布」一行不动。
//
//   · 数据：产品维 /lighthouse/dimension 的行（name / profit，单位元），同名合并。
//   · 版式：大数（合计）→ 盈利构成堆叠条 → 盈利组 → 小额折叠 → 亏损组 → 查看明细。
//     名称里的「（交易）」「（积分）」拆成小标签，名字本身不被截断。
//   · 交互：点一行（或构成条上的一段）高亮那个产品，再点取消；小额产品点开 / 收起；
//     打开时大数从 0 数上来、构成条和每行依次长出来。
//   · 动效：[LhProfitSplitReveal] —— 从按钮那一点画圆盖满主 Hero，原路收回。
// ═════════════════════════════════════════════════════════════════════════════

const _kInkStrong = Color(0xFF231D38);
const _kInk = Color(0xFF3A3352);
const _kMute = Color(0xFF6E6890);
const _kDeep = Color(0xFF4B36A8);
const _kLossDeep = Color(0xFFC42F2F);
const _kHeroUp = Color(0xFFD23C3C);
const _kHeroDown = Color(0xFF1F9D6B);
const _kBoxTop = Color(0xFFF8F6FE);
const _kBoxEdge = Color(0xFFE9E3F8);
const _kTrack = Color(0xFFEFEBF8);
const _kTagBg = Color(0xFFF4F1FB);

/// 盈利行的色阶（排名方块的字 / 构成条的段 / 行条，三处同色）与排名方块底色。
const _kGainShades = <Color>[
  Color(0xFF5B3FD0),
  Color(0xFF7B5FE6),
  Color(0xFF9D88EF),
  Color(0xFFBEB0F5),
  Color(0xFFCBBFF7),
  Color(0xFFD5CBF9),
];
const _kGainTints = <Color>[
  Color(0xFFEDE7FD),
  Color(0xFFF0ECFE),
  Color(0xFFF3F0FE),
  Color(0xFFF6F3FE),
  Color(0xFFF7F5FE),
  Color(0xFFF8F6FE),
];
const _kRestShade = Color(0xFFDCD3FA);

@immutable
class LhProfitSplitItem {
  const LhProfitSplitItem({required this.name, required this.profit});

  /// 接口原名（含括号里的口径）。
  final String name;

  /// 元。
  final double profit;

  /// 「中石油特惠现金券（交易）」→ (中石油特惠现金券, 交易)。
  (String, String?) get nameAndTag => lhProfitSplitNameTag(name);
}

(String, String?) lhProfitSplitNameTag(String raw) {
  final m = RegExp(r'^(.+?)\s*[（(]([^（）()]{1,8})[）)]\s*$').firstMatch(raw.trim());
  if (m == null) return (raw.trim(), null);
  return (m.group(1)!.trim(), m.group(2)!.trim());
}

@immutable
class LhProfitSplit {
  const LhProfitSplit({required this.gains, required this.losses});

  static const empty = LhProfitSplit(
    gains: <LhProfitSplitItem>[],
    losses: <LhProfitSplitItem>[],
  );

  /// 盈利产品，从大到小。
  final List<LhProfitSplitItem> gains;

  /// 亏损产品，亏得最多的在前。
  final List<LhProfitSplitItem> losses;

  double get gain => gains.fold<double>(0, (s, e) => s + e.profit);
  double get loss => losses.fold<double>(0, (s, e) => s + e.profit);
  double get total => gain + loss;
  bool get isEmpty => gains.isEmpty && losses.isEmpty;
}

/// 产品维的行 → 利润构成。同名合并，利润为 0 的产品不进来。
LhProfitSplit lighthouseProfitSplit(List<Map<String, dynamic>> rows) {
  final byName = <String, double>{};
  for (final r in rows) {
    final raw = r['profit'];
    final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}') ?? 0;
    if (!v.isFinite || v == 0) continue;
    var name = (r['name']?.toString() ?? '').trim();
    if (name.isEmpty) name = '未命名产品';
    byName[name] = (byName[name] ?? 0) + v;
  }
  final gains = <LhProfitSplitItem>[];
  final losses = <LhProfitSplitItem>[];
  byName.forEach((name, v) {
    if (v > 0) {
      gains.add(LhProfitSplitItem(name: name, profit: v));
    } else if (v < 0) {
      losses.add(LhProfitSplitItem(name: name, profit: v));
    }
  });
  gains.sort((a, b) => b.profit.compareTo(a.profit));
  losses.sort((a, b) => a.profit.compareTo(b.profit));
  return LhProfitSplit(
    gains: List<LhProfitSplitItem>.unmodifiable(gains),
    losses: List<LhProfitSplitItem>.unmodifiable(losses),
  );
}

/// 盈利组里直接列出来的那几个：占盈利 ≥ 2% 的，最多 6 个、至少 1 个；
/// 剩下只多 1 个时也直接列，不为一个产品做折叠。
int lhProfitSplitShownGains(LhProfitSplit d) {
  final g = d.gain;
  if (d.gains.isEmpty || g <= 0) return d.gains.length;
  var n = 0;
  for (final it in d.gains) {
    if (n >= 6 || it.profit / g < 0.02) break;
    n++;
  }
  n = math.max(1, n);
  if (d.gains.length - n == 1) n = d.gains.length;
  return n;
}

/// 金额口径跟灯塔一致：默认万，最大一项过亿就整块改亿。
class _Fmt {
  const _Fmt(this.yi);
  final bool yi;

  String get unit => yi ? '亿' : '万';
  String get unitLong => yi ? '亿元' : '万元';

  String abs(double yuan) => (yuan.abs() / (yi ? 1e8 : 1e4)).toStringAsFixed(2);

  String plain(double yuan) => '${yuan < 0 ? '−' : ''}${abs(yuan)}';

  String signed(double yuan) {
    if (yuan == 0) return abs(0);
    return '${yuan < 0 ? '−' : '+'}${abs(yuan)}';
  }

  String signedWithUnit(double yuan) => '${signed(yuan)}$unit';
}

String _pct(double part, double whole) {
  if (whole <= 0) return '—';
  final p = part / whole * 100;
  if (p > 0 && p < 1) return '<1%';
  return '${p.round()}%';
}

// ─────────────────────────────────────────────────────────────────────────────

class LhProfitSplitPanel extends StatefulWidget {
  const LhProfitSplitPanel({
    super.key,
    required this.loadRows,
    required this.title,
    required this.chip,
    this.live = false,
    this.caretFromRight,
    this.onViewDetail,
  });

  /// 当前周期产品维的行（name / profit，元）。
  final Future<List<Map<String, dynamic>>> Function() loadRows;

  /// 「今日利润构成」「本月利润构成」…
  final String title;

  /// 标题旁的小标签：「截至 14:24 · 进行中」「11.01–11.24」…
  final String chip;

  /// 当前期还没结束：小标签带一颗圆点。
  final bool live;

  /// 顶上小尖角离右边多远（对准「利润分布」按钮中心）；不给不画。
  final double? caretFromRight;

  /// 为空则不显示「查看产品明细」。
  final VoidCallback? onViewDetail;

  @override
  State<LhProfitSplitPanel> createState() => _LhProfitSplitPanelState();
}

// 字号不超过主 Hero（大数 34 / 单位 14、标题 13、正文 12.5 以下）：
//   大数 34 · 标题 13 · 行名 13 · 行金额 14 · 两格金额 15 · 说明 11–12 · 标签 10–10.5。
// 版式对齐原型「手机 · 利润构成精修版」：
//   ┌ 淡紫渐白的圆角面（小尖角对准按钮）──────────────────────────┐
//   │ 今日利润构成 [● 截至 14:54 · 进行中]                        │
//   │ 4.92万  8 个产品合计                                        │
//   │ [↑ 盈利 · 7 个 +5.08万] [↓ 亏损 · 1 个 −0.16万]             │
//   │ 盈利从哪来 …………………………………… 前 4 个占 99%            │
//   │ [■■■■■■ 61% ■■ 19% ■ 12% ■ ▪]                             │
//   │ [1] 中石油特惠现金券 [交易] ………………… +3.10               │
//   │     ━━━━━━━━━━━━━━━━━━━━━━━━━ 61%                        │
//   │ - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  │
//   │ [+3] 其余 3 个产品 ………………………………… +0.06 (⌄)           │
//   │ ─────────────────────────────────────────                 │
//   │ 拖后腿的 ……………………………………………… [吃掉盈利 3%]          │
//   │ [↓ 满减券 [交易] ………………………………… −0.16]                │
//   └────────────────────────────────────────────────────────────┘
//   [≡ 查看产品明细 ……………………………………… 8 个 →]

class _LhProfitSplitPanelState extends State<LhProfitSplitPanel> {
  late Future<List<Map<String, dynamic>>> _future;

  /// 高亮的产品（接口原名）。
  String? _focus;
  bool _restOpen = false;
  bool _lossRestOpen = false;
  int _productCount = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await widget.loadRows();
    final n = lighthouseProfitSplit(rows);
    if (mounted) {
      setState(() => _productCount = n.gains.length + n.losses.length);
    }
    return rows;
  }

  void _retry() => setState(() => _future = _load());

  void _toggleFocus(String name) {
    HapticFeedback.selectionClick();
    setState(() => _focus = _focus == name ? null : name);
  }

  void _toggleRest() {
    HapticFeedback.selectionClick();
    setState(() => _restOpen = !_restOpen);
  }

  Color _c(Color light, [DunesColorRole role = DunesColorRole.foreground]) =>
      DunesColors.resolve(context, light, role: role);

  Color _s(Color light) => _c(light, DunesColorRole.surface);

  TextStyle _sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _kInk,
    bool tabular = false,
    double? height,
    double? letterSpacing,
  }) {
    final s = LhTypography.sans(
      context: context,
      size: size,
      weight: weight,
      color: _c(color),
      height: height,
      letterSpacing: letterSpacing,
    );
    return tabular
        ? s.copyWith(fontFeatures: const [FontFeature.tabularFigures()])
        : s;
  }

  Duration _dur(int ms) => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: ms);

  @override
  Widget build(BuildContext context) {
    final caret = widget.caretFromRight;
    // 整块铺白：圆形展开时读得出「这是一张面」，也盖住底下渐隐的 Hero。
    return ColoredBox(
      color: _s(Colors.white),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.32],
                    colors: [_s(_kBoxTop), _s(Colors.white)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _c(_kBoxEdge, DunesColorRole.border)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: AnimatedSize(
                    duration: _dur(260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _future,
                      builder: (context, snap) {
                        final Widget child;
                        if (snap.connectionState != ConnectionState.done) {
                          child = _skeleton();
                        } else if (snap.hasError) {
                          child = _message(
                            Icons.error_outline_rounded,
                            '利润构成加载失败',
                            detail: snap.error
                                ?.toString()
                                .replaceFirst('Exception: ', ''),
                            onRetry: _retry,
                          );
                        } else {
                          final data = lighthouseProfitSplit(
                            snap.data ?? const <Map<String, dynamic>>[],
                          );
                          child = data.isEmpty
                              ? _message(Icons.inbox_outlined, '这个周期还没有产品利润数据')
                              : _body(data);
                        }
                        return AnimatedSwitcher(
                          duration: _dur(220),
                          child: KeyedSubtree(
                            key: ValueKey(
                              snap.connectionState == ConnectionState.done
                                  ? (snap.hasError ? 'err' : 'data')
                                  : 'loading',
                            ),
                            child: child,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (caret != null)
                Positioned(
                  top: 0,
                  right: caret - 6,
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _s(_kBoxTop),
                        border: Border(
                          left: BorderSide(color: _c(_kBoxEdge, DunesColorRole.border)),
                          top: BorderSide(color: _c(_kBoxEdge, DunesColorRole.border)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.onViewDetail != null) ...[
            const SizedBox(height: 12),
            _detailButton(),
          ],
        ],
      ),
    );
  }

  // ── 头：「今日利润构成  [● 截至 14:54 · 进行中]」 ──

  Widget _header() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(widget.title, style: _sans(13, weight: FontWeight.w700, color: _kInk)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _s(const Color(0xFFECE6FD)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.live) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _c(const Color(0xFF5B3FD0)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                widget.chip,
                style: _sans(
                  11,
                  weight: FontWeight.w600,
                  color: const Color(0xFF5B3FD0),
                  tabular: true,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 加载 / 出错 / 空 ──

  Widget _skeleton() {
    Widget block(double w, double h, {double r = 6}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: _s(const Color(0xFFECE8F6)),
        borderRadius: BorderRadius.circular(r),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 12),
          block(110, 34),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: block(double.infinity, 58, r: 12)),
              const SizedBox(width: 8),
              Expanded(child: block(double.infinity, 58, r: 12)),
            ],
          ),
          const SizedBox(height: 18),
          block(double.infinity, 22, r: 6),
          const SizedBox(height: 22),
          for (var i = 0; i < 4; i++) ...[
            Row(
              children: [
                block(20, 20),
                const SizedBox(width: 9),
                block(120.0 - i * 14, 13),
                const Spacer(),
                block(42, 13),
              ],
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 29),
              child: block(double.infinity, 5, r: 3),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _message(
    IconData icon,
    String text, {
    String? detail,
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28, color: _c(_kMute)),
                const SizedBox(height: 10),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: _sans(13, weight: FontWeight.w600),
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(11, color: _kMute),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      '重试',
                      style: _sans(13, weight: FontWeight.w600, color: _kDeep),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 内容 ──

  Widget _body(LhProfitSplit d) {
    var maxAbs = math.max(d.gain, -d.loss);
    for (final it in d.gains) {
      maxAbs = math.max(maxAbs, it.profit.abs());
    }
    final fmt = _Fmt(maxAbs >= 1e8);
    final shown = lhProfitSplitShownGains(d);
    final head = d.gains.take(shown).toList();
    final rest = d.gains.skip(shown).toList();
    final restSum = rest.fold<double>(0, (s, e) => s + e.profit);
    final lossHead = d.losses.take(4).toList();
    final lossRest = d.losses.skip(4).toList();
    final maxGain = d.gains.isNotEmpty ? d.gains.first.profit : 1.0;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduce ? 1.0 : 0.0, end: 1.0),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
      builder: (context, t, _) {
        // 每一行比上一行晚一点长出来。
        double stagger(int i) => Interval(
          math.min(0.6, 0.14 + i * 0.07),
          math.min(1.0, 0.54 + i * 0.07),
          curve: Curves.easeOutCubic,
        ).transform(t);
        final grow = const Interval(0.05, 0.7, curve: Curves.easeOutCubic).transform(t);
        var slot = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头 + 合计 + 盈亏两格 + 构成条
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 10),
                  _total(d, fmt, const Interval(0, 0.75, curve: Curves.easeOutCubic).transform(t)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          gain: true,
                          label: '盈利 · ${d.gains.length} 个',
                          value: fmt.signed(d.gain),
                          unit: fmt.unit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statCard(
                          gain: false,
                          label: '亏损 · ${d.losses.length} 个',
                          value: d.loss == 0 ? '0.00' : fmt.signed(d.loss),
                          unit: fmt.unit,
                        ),
                      ),
                    ],
                  ),
                  if (d.gains.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('盈利从哪来', style: _sans(12, weight: FontWeight.w600, color: _kInk)),
                        const Spacer(),
                        if (rest.isNotEmpty)
                          Text(
                            '前 ${head.length} 个占 ${_pct(d.gain - restSum, d.gain)}',
                            style: _sans(11, color: _kMute),
                          )
                        else
                          Text('单位：${fmt.unitLong}', style: _sans(11, color: _kMute)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _composition(d, head, restSum, grow),
                  ],
                ],
              ),
            ),
            // 盈利列表（左右各留 10，行自己再留 6：高亮底比文字宽一点）
            if (d.gains.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < head.length; i++)
                      _enter(
                        stagger(slot++),
                        _gainRow(head[i], i, fmt, share: _pct(head[i].profit, d.gain), width: head[i].profit / maxGain * grow),
                      ),
                    if (rest.isNotEmpty)
                      _enter(stagger(slot++), _restFold(rest, restSum, fmt)),
                  ],
                ),
              ),
            // 亏损
            if (d.losses.isNotEmpty)
              _enter(
                stagger(slot++),
                Container(
                  margin: EdgeInsets.fromLTRB(16, d.gains.isEmpty ? 14 : 4, 16, 0),
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
                  decoration: BoxDecoration(
                    border: d.gains.isEmpty
                        ? null
                        : Border(top: BorderSide(color: _c(const Color(0xFFF0ECF8), DunesColorRole.border))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('拖后腿的', style: _sans(12, weight: FontWeight.w600, color: _kInk)),
                          const Spacer(),
                          if (d.gain > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _s(const Color(0xFFFCEBE8)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '吃掉盈利 ${_pct(-d.loss, d.gain)}',
                                style: _sans(11, weight: FontWeight.w600, color: const Color(0xFFB03A33)),
                              ),
                            ),
                        ],
                      ),
                      for (final it in lossHead) ...[
                        const SizedBox(height: 8),
                        _lossRow(it, fmt),
                      ],
                      if (lossRest.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _lossRestRow(lossRest, fmt),
                      ],
                    ],
                  ),
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _enter(double t, Widget child) => Opacity(
    opacity: t.clamp(0.0, 1.0).toDouble(),
    child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
  );

  /// 「4.92万  8 个产品合计」：大数从 0 数到合计。
  Widget _total(LhProfitSplit d, _Fmt fmt, double t) {
    final total = d.total;
    final tone = total < 0 ? _kHeroDown : _kHeroUp;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: fmt.plain(total * t),
              // 跟主 Hero「今日盈利」大数同一款：number 34、单位 14（不比它大）。
              style: LhTypography.number(context: context, size: 34, color: _c(tone))
                  .copyWith(letterSpacing: -0.6, height: 1),
            ),
            TextSpan(text: fmt.unit, style: _sans(14, weight: FontWeight.w600, color: tone)),
            TextSpan(
              text: '   ${d.gains.length + d.losses.length} 个产品合计',
              style: _sans(11, weight: FontWeight.w500, color: _kMute),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }

  Widget _arrowChip({required bool up, double size = 16, double radius = 5}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _s(up ? const Color(0xFFEDE7FD) : const Color(0xFFFCEBE8)),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        size: size * 0.66,
        color: _c(up ? const Color(0xFF5B3FD0) : _kLossDeep),
      ),
    );
  }

  /// 盈 / 亏两格：「[↑] 盈利 · 7 个」下面「+5.08万」。
  Widget _statCard({
    required bool gain,
    required String label,
    required String value,
    required String unit,
  }) {
    final tone = gain ? _kDeep : _kLossDeep;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _s(Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(gain ? const Color(0xFFEEEAF8) : const Color(0xFFF5E4E1), DunesColorRole.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _arrowChip(up: gain),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(11, color: _kMute)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value, style: _sans(15, weight: FontWeight.w700, color: tone, tabular: true, height: 1.1)),
                  TextSpan(text: ' $unit', style: _sans(11, weight: FontWeight.w600, color: tone)),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// 构成条：22 高，占比 ≥ 10% 的段里写百分比；段色 = 行的排名色。点段 = 点那一行。
  Widget _composition(
    LhProfitSplit d,
    List<LhProfitSplitItem> head,
    double restSum,
    double t,
  ) {
    final segs = <(String?, double, Color)>[
      for (var i = 0; i < head.length; i++)
        (head[i].name, head[i].profit, _kGainShades[math.min(i, _kGainShades.length - 1)]),
      if (restSum > 0) (null, restSum, _kRestShade),
    ];
    final total = d.gain <= 0 ? 1.0 : d.gain;
    final n = segs.length;
    BorderRadius radius(int i) {
      const big = Radius.circular(6);
      const small = Radius.circular(2);
      if (n == 1) return BorderRadius.circular(6);
      if (i == 0) return const BorderRadius.horizontal(left: big, right: small);
      if (i == n - 1) return const BorderRadius.horizontal(left: small, right: big);
      return BorderRadius.circular(2);
    }

    return SizedBox(
      height: 22,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: t.clamp(0.001, 1.0).toDouble(),
          child: Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: math.max(1, (segs[i].$2 / total * 1000).round()),
                  child: Semantics(
                    button: true,
                    label: segs[i].$1 == null
                        ? '其余产品，占盈利 ${_pct(segs[i].$2, d.gain)}'
                        : '${lhProfitSplitNameTag(segs[i].$1!).$1}，占盈利 ${_pct(segs[i].$2, d.gain)}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: segs[i].$1 == null ? _toggleRest : () => _toggleFocus(segs[i].$1!),
                      child: AnimatedOpacity(
                        duration: _dur(180),
                        opacity: _focus == null || _focus == segs[i].$1 ? 1 : 0.3,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: _c(segs[i].$3), borderRadius: radius(i)),
                          child: segs[i].$2 / total >= 0.1
                              ? Opacity(
                                  opacity: ((t - 0.6) / 0.4).clamp(0.0, 1.0).toDouble(),
                                  child: Text(
                                    _pct(segs[i].$2, d.gain),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    softWrap: false,
                                    style: _sans(10, weight: FontWeight.w700, color: Colors.white, tabular: true, height: 1.0),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, {Color bg = _kTagBg, Color fg = _kMute}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: _s(bg), borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: _sans(10, color: fg, height: 1.25)),
    );
  }

  Widget _nameWithTag(String name, String? tag, String full, {Color? tagBg, Color? tagFg}) {
    return Row(
      children: [
        Flexible(
          child: Tooltip(
            message: full,
            child: Text(
              name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _sans(13, weight: FontWeight.w600, color: _kInkStrong),
            ),
          ),
        ),
        if (tag != null) ...[
          const SizedBox(width: 6),
          _tag(tag, bg: tagBg ?? _kTagBg, fg: tagFg ?? _kMute),
        ],
      ],
    );
  }

  /// 盈利一行：上「[1] 名称 [口径] …… +3.10」，下「细条 …… 61%」。点一下高亮、其余变淡。
  Widget _gainRow(
    LhProfitSplitItem it,
    int index,
    _Fmt fmt, {
    required String share,
    required double width,
  }) {
    final (name, tag) = it.nameAndTag;
    final color = _kGainShades[math.min(index, _kGainShades.length - 1)];
    final tint = _kGainTints[math.min(index, _kGainTints.length - 1)];
    final focused = _focus == it.name;
    final dimmed = _focus != null && !focused;
    return Semantics(
      button: true,
      selected: focused,
      label: '第 ${index + 1}，$name${tag == null ? '' : '（$tag）'}，盈利 ${fmt.abs(it.profit)}${fmt.unitLong}，占盈利 $share',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleFocus(it.name),
          child: AnimatedContainer(
            duration: _dur(200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 11),
            decoration: BoxDecoration(
              color: focused ? _s(const Color(0xFFF1ECFE)) : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedOpacity(
              duration: _dur(180),
              opacity: dimmed ? 0.42 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: _s(tint), borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          '${index + 1}',
                          style: _sans(10.5, weight: FontWeight.w700, color: color, tabular: true, height: 1.0),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: _nameWithTag(name, tag, it.name)),
                      const SizedBox(width: 10),
                      Text(
                        fmt.signedWithUnit(it.profit),
                        maxLines: 1,
                        style: _sans(14, weight: FontWeight.w700, color: _kInkStrong, tabular: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 29),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 5,
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(color: _s(_kTrack), borderRadius: BorderRadius.circular(3)),
                            child: FractionallySizedBox(
                              widthFactor: width.clamp(0.02, 1.0).toDouble(),
                              child: Container(
                                decoration: BoxDecoration(color: _c(color), borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 32,
                          child: Text(
                            share,
                            textAlign: TextAlign.right,
                            style: _sans(10.5, weight: FontWeight.w600, color: _kMute, tabular: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 小额折叠：虚线隔开，「[+3] 其余 3 个产品 …… +0.06 (⌄)」，点开在浅底里逐个列出。
  Widget _restFold(List<LhProfitSplitItem> rest, double restSum, _Fmt fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        CustomPaint(
          size: const Size(double.infinity, 1),
          painter: _LhDashPainter(_c(const Color(0xFFE6E0F5), DunesColorRole.border)),
        ),
        Semantics(
          button: true,
          expanded: _restOpen,
          label: '其余 ${rest.length} 个产品，合计 ${fmt.signed(restSum)}${fmt.unitLong}',
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleRest,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _s(_kTagBg), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        '+${rest.length}',
                        style: _sans(10.5, weight: FontWeight.w700, color: const Color(0xFF8A84A6), height: 1.0),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text('其余 ${rest.length} 个产品', style: _sans(12, color: _kMute))),
                    Text(fmt.signedWithUnit(restSum), style: _sans(12.5, weight: FontWeight.w700, color: _kInk, tabular: true)),
                    const SizedBox(width: 9),
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _s(_kTagBg), shape: BoxShape.circle),
                      child: AnimatedRotation(
                        turns: _restOpen ? 0.5 : 0,
                        duration: _dur(220),
                        curve: Curves.easeOutCubic,
                        child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _c(_kMute)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: _dur(240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _restOpen
              ? Container(
                  margin: const EdgeInsets.fromLTRB(35, 0, 6, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _s(const Color(0xFFFAF9FD)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      for (final it in rest)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  it.nameAndTag.$2 == null
                                      ? it.nameAndTag.$1
                                      : '${it.nameAndTag.$1} · ${it.nameAndTag.$2}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _sans(12, color: _kInk),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(fmt.signedWithUnit(it.profit), style: _sans(12, weight: FontWeight.w600, color: _kInk, tabular: true)),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 亏损一行：淡红底卡片「[↓] 满减券 [交易] …… −0.16」。点一下高亮。
  Widget _lossRow(LhProfitSplitItem it, _Fmt fmt) {
    final (name, tag) = it.nameAndTag;
    final focused = _focus == it.name;
    final dimmed = _focus != null && !focused;
    return Semantics(
      button: true,
      selected: focused,
      label: '$name${tag == null ? '' : '（$tag）'}，亏损 ${fmt.abs(it.profit)}${fmt.unitLong}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleFocus(it.name),
          child: AnimatedOpacity(
            duration: _dur(180),
            opacity: dimmed ? 0.42 : 1,
            child: AnimatedContainer(
              duration: _dur(200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _s(focused ? const Color(0xFFFBE7E3) : const Color(0xFFFDF5F3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _arrowChip(up: false, size: 20, radius: 6),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _nameWithTag(
                      name,
                      tag,
                      it.name,
                      tagBg: Colors.white,
                      tagFg: const Color(0xFF9A4A43),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    fmt.signedWithUnit(it.profit),
                    style: _sans(14, weight: FontWeight.w700, color: _kLossDeep, tabular: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lossRestRow(List<LhProfitSplitItem> rest, _Fmt fmt) {
    final sum = rest.fold<double>(0, (s, e) => s + e.profit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _lossRestOpen = !_lossRestOpen);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: Text('其余 ${rest.length} 个亏损产品', style: _sans(12, color: _kMute))),
                Text(fmt.signedWithUnit(sum), style: _sans(12.5, weight: FontWeight.w700, color: _kLossDeep, tabular: true)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _lossRestOpen ? 0.5 : 0,
                  duration: _dur(220),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _c(_kMute)),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: _dur(240),
          alignment: Alignment.topCenter,
          child: _lossRestOpen
              ? Column(
                  children: [
                    for (final it in rest) ...[
                      const SizedBox(height: 6),
                      _lossRow(it, fmt),
                    ],
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _detailButton() {
    return Semantics(
      button: true,
      label: '查看产品明细',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onViewDetail,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _s(const Color(0xFFF1EDFD)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.format_list_bulleted_rounded, size: 14, color: _c(_kDeep)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('查看产品明细', style: _sans(12.5, weight: FontWeight.w600, color: _kDeep)),
                ),
                if (_productCount > 0) ...[
                  Text('$_productCount 个', style: _sans(11, weight: FontWeight.w500, color: _kMute)),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.arrow_forward_rounded, size: 15, color: _c(_kDeep)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条横向虚线（小额折叠上面那条）。
class _LhDashPainter extends CustomPainter {
  const _LhDashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + dash, size.width), 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_LhDashPainter old) => old.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// 展开动效：从「利润分布」按钮那一点向外画圆，盖满整块主 Hero。
//
//   · 0 → 1（620ms）：圆从按钮正下方（离右上角 [originFromTopRight]）长到最远的角；
//     圆里的内容同时从右边滑进来、淡入；底下原来的 Hero 跟着淡出。
//   · 停稳后原 Hero 让位（Offstage，状态保留），这一块的高度跟着利润构成走，
//     高度变化由 AnimatedSize 接住，不会跳。
//   · 1 → 0（360ms）：原路收回到按钮。
//   · 系统开了「减弱动效」：直接切换。
// ═════════════════════════════════════════════════════════════════════════════

class LhProfitSplitReveal extends StatefulWidget {
  const LhProfitSplitReveal({
    super.key,
    required this.open,
    required this.child,
    required this.overlayBuilder,
    this.originFromTopRight = const Offset(56, 0),
  });

  final bool open;

  /// 原来的主 Hero。
  final Widget child;

  /// 盖上去的利润构成。
  final WidgetBuilder overlayBuilder;

  /// 圆心：离这一块右上角多远（按钮中心正下方）。
  final Offset originFromTopRight;

  @override
  State<LhProfitSplitReveal> createState() => _LhProfitSplitRevealState();
}

class _LhProfitSplitRevealState extends State<LhProfitSplitReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 360),
    value: widget.open ? 1.0 : 0.0,
  );

  @override
  void didUpdateWidget(LhProfitSplitReveal old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.open ? 1.0 : 0.0;
    } else if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, base) {
          final v = _c.value;
          final t = Curves.easeInOutCubic.transform(v);
          final fade = const Interval(0.18, 1, curve: Curves.easeOut).transform(v);
          final settled = widget.open && v >= 1;
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              // 原 Hero：一直挂着（走势图、日期条的状态都在），停稳后不占高度。
              Offstage(
                offstage: settled,
                child: IgnorePointer(
                  ignoring: widget.open,
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0).toDouble(),
                    child: base,
                  ),
                ),
              ),
              if (v > 0)
                ClipPath(
                  clipper: _LhRevealClipper(t, widget.originFromTopRight),
                  child: Opacity(
                    opacity: fade,
                    child: Transform.translate(
                      offset: Offset(28 * (1 - t), 0),
                      child: widget.overlayBuilder(context),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LhRevealClipper extends CustomClipper<Path> {
  _LhRevealClipper(this.t, this.fromTopRight);

  final double t;
  final Offset fromTopRight;

  @override
  Path getClip(Size size) {
    final o = Offset(
      (size.width - fromTopRight.dx).clamp(0.0, size.width).toDouble(),
      fromTopRight.dy.clamp(0.0, size.height).toDouble(),
    );
    var far = 0.0;
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      far = math.max(far, (corner - o).distance);
    }
    // 起点就有一颗按钮大小的圆：看上去是从按钮里长出来的。
    final r = 18 + (far - 18) * t;
    return Path()..addOval(Rect.fromCircle(center: o, radius: r));
  }

  @override
  bool shouldReclip(_LhRevealClipper old) =>
      old.t != t || old.fromTopRight != fromTopRight;
}
