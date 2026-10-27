import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_hero_swipe.dart';
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 主 Hero 走势卡（2026-10-21 · 对齐「产品汇总卡片改版」原型）
//
//   · 卡面：白 → 极淡紫的竖向渐变，右上角一团淡紫光。
//   · 多根线叠画，各按自己的区间归一（单位差几个数量级，只比形状）。
//     主线最粗、带光晕和渐变面；其它细线，深浅不同的紫，虚实区分。
//   · 图例是一排胶囊：点没显示的 → 加上并设为主线；点已显示的 → 设为主线；
//     再点主线 → 去掉（至少留一根）。
//   · 点某一天：那一列淡紫高光 + 每根线一个圆点 + 浮一张读数卡；再点同一天收起。
//   · 资金模式下面多一排柱（预收净增）：线在上半区，柱贴着底部基线正负两向长。
//   · 2026-10-26：图里横拖 = 股票式翻历史（往右拖看更早，拖到左沿附近回调
//     onNeedHistory 往前补一页，补完画面不跳）；线整体调细（主线 1.6 / 其它 1.0）。
//   · 2026-10-26 · 柱 + 线（原型 B，[combo]）：[lines] 当指标池，一个当柱（量，从 0 起，
//     画在后面）、一个当线（走势）。两种画法天然分得清，不再四根同形的线拧成一股；
//     图例换成「柱 · 核销额 ▾」「线 · 利润 ▾」两颗选择胶囊，浮动读数卡换成固定一行读数。
//     卡面、胶囊、选中列高光、翻历史、拉宽接力全部沿用。
//
// 只吃数据，不认识任何指标 —— 指标、颜色、格式都由 native_lighthouse_page 传进来。
// ═════════════════════════════════════════════════════════════════════════════

const Color _kInk = Color(0xFF2B2147);
const Color _kSub = Color(0xFF7A6AB3);
const Color _kMuteText = Color(0xFF5A5C56);
const Color _kMute2 = Color(0xFF94938A);
const Color _kFocus = Color(0xFF6A4FC9);
const Color _kPlum = Color(0xFF7B5CD8);
const Color _kDeep = Color(0xFF5A458F);
const Color _kEdge = Color(0xFFE2D9F6);
const Color _kChipEdge = Color(0xFFECE9F2);
const Color _kChipFocusEdge = Color(0xFFB9A6F0);
const Color _kChipFocusFill = Color(0xFFF1ECFD);
const Color _kGrid = Color(0xFFE8E1F7);
const Color _kBarPos = Color(0xFF9C82E6);
const Color _kBarNeg = Color(0xFFD6CBF5);
const Color _kBarPosSel = Color(0xFF5A458F);
const Color _kBarNegSel = Color(0xFF8E7BC9);

/// 一根线。[values] 与卡的 labels 一一对齐（右对齐，缺的填 null）。
class LhHeroLine {
  const LhHeroLine({
    required this.key,
    required this.name,
    required this.color,
    required this.values,
    required this.format,
    this.dash,
    this.stock = false,
  });

  final String key;
  final String name;
  final Color color;
  final List<double?> values;
  final String Function(double v) format;

  /// null = 实线；否则 [实, 虚] 像素。
  final List<double>? dash;

  /// 存量（总资产、中石油 / 中石化资产）：一周只动 1–2%，纵向值域至少给到量级的 4%，
  /// 免得小波动被拉成满屏大浪。流量（核销 / 利润 / 收入…）不设下限，各自拉满。
  final bool stock;
}

/// 分段模式里，柱（[LhHeroBars]）也占一个分段；选中它时 [LighthouseHeroTrendCard.focusKey]
/// 用这个键。
const String lhHeroBarsTabKey = '__bars__';

/// 底部一排柱（资金模式的预收净增）。
class LhHeroBars {
  const LhHeroBars({
    required this.name,
    required this.values,
    required this.format,
  });

  final String name;
  final List<double?> values;
  final String Function(double v) format;
}

class LighthouseHeroTrendCard extends StatefulWidget {
  const LighthouseHeroTrendCard({
    super.key,
    required this.title,
    required this.labels,
    required this.lines,
    this.subtitle,
    this.bars,
    this.barsVisible = false,
    this.onBarsVisibleChanged,
    this.defaultVisible,
    this.focusKey,
    this.visibleCount = 7,
    this.wideVisibleCount,
    this.selectedIndex,
    this.onSelectedIndexChanged,
    this.trailing,
    this.lastIsPartial = false,
    this.body,
    this.emptyText = '暂无走势',
    this.historyCount = 0,
    this.historyLoading = false,
    this.historyHasMore = false,
    this.onNeedHistory,
    this.combo = false,
    this.comboBarKeys = const <String>{},
    this.comboRatioLabels = const <String, String>{},
    this.segmented = false,
    this.compareLabel,
    this.onFocusChanged,
  });

  final String title;

  /// null = 自动写「叠加 N 条 · 各自归一」。
  final String? subtitle;
  final List<String> labels;
  final List<LhHeroLine> lines;
  final LhHeroBars? bars;
  final bool barsVisible;
  final ValueChanged<bool>? onBarsVisibleChanged;
  final Set<String>? defaultVisible;

  /// 外部指定的主线（例如下面点了某个指标格）。变了就加上并设为主线。
  final String? focusKey;

  /// 一屏画最近几个点。
  final int visibleCount;

  /// 拉宽到头时一屏几个点。跟 [LighthouseHeroWideHandoff.progress] 在两者之间连续变。
  /// null = 拉宽也不加点。
  final int? wideVisibleCount;

  /// 选中的点（labels 的绝对下标）。传了 [onSelectedIndexChanged] 时受控。
  final int? selectedIndex;
  final ValueChanged<int?>? onSelectedIndexChanged;
  final Widget? trailing;

  /// 最后一点是「进行中」的本期（今天）。
  final bool lastIsPartial;

  /// 非空时替换图例 + 图（资金「构成」）。
  final Widget? body;
  final String emptyText;

  /// 序列最前面有几个点是「往前拉」加载来的历史（只用来判断「往前补了一页」）。
  final int historyCount;
  final bool historyLoading;
  final bool historyHasMore;

  /// 拖到左沿附近时回调，外层去要更早的一页。null = 不能往前拉。
  final VoidCallback? onNeedHistory;

  /// 柱 + 线模式（原型 B）：[lines] 里一个当柱、一个当线，[bars] 不用。
  final bool combo;

  /// 能当柱的指标（量类：核销 / 销售 / GMV）。第一个有数的是默认柱。
  /// 外面点了指标格（[focusKey]）：在这里面的换柱，其余换线。
  final Set<String> comboBarKeys;

  /// 线指标 → 读数行里「线 ÷ 柱」的叫法（例如 profit → 利润率）。没有就不写比值。
  final Map<String, String> comboRatioLabels;

  /// 分段 + 大读数（原型 A 的排布，2026-10-26）：顶上一排分段按钮选主线，下面一行
  /// 大读数（主线那天的值 · 较前一期 · 日期），图里照样画多根线。点某天 → 读数跳到
  /// 那天，同时照旧浮那张列全字段的小卡片。
  final bool segmented;

  /// 分段读数里环比后面那几个字（「vs 上日」「vs 上月」）。null = 按横轴标签猜。
  final String? compareLabel;

  /// 分段模式里点了某一段（线的 key）。主 Hero 用它把左边大数换成同一个指标。
  final ValueChanged<String>? onFocusChanged;

  @override
  State<LighthouseHeroTrendCard> createState() =>
      _LighthouseHeroTrendCardState();
}

class _LighthouseHeroTrendCardState extends State<LighthouseHeroTrendCard>
    with SingleTickerProviderStateMixin {
  Set<String> _vis = <String>{};
  String? _focus;
  int? _localSel;
  String _lineSig = '';

  /// 从最新往回挪了几格（0 = 贴着今天）。拖动中是小数，跟手；松手吸到整格。
  /// 按「离末尾多远」记 —— 往前补了历史，末尾不变，画面自然停在原处。
  double _back = 0;
  late final AnimationController _pan;
  LighthouseHeroWideHandoff? _handoff;
  bool _relaying = false;

  /// 柱 + 线模式下用户挑的柱 / 线（null = 用默认）。
  String? _barKey;
  String? _lineKey;

  @override
  void initState() {
    super.initState();
    _pan = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _back = _pan.value);
      });
    _resetVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = LighthouseHeroWideScope.maybeOf(context);
    if (next == _handoff) return;
    _handoff?.progress.removeListener(_onWideProgress);
    _handoff = next;
    _handoff?.progress.addListener(_onWideProgress);
  }

  void _onWideProgress() {
    if (!mounted) return;
    if (_back > _maxBack) _back = _maxBack;
    setState(() {});
  }

  @override
  void dispose() {
    _handoff?.progress.removeListener(_onWideProgress);
    _pan.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LighthouseHeroTrendCard old) {
    super.didUpdateWidget(old);
    // 换了周期 / 口径（末尾那一格变了）→ 回到最新；只是往前补了历史 → 不动。
    final sameTail =
        widget.labels.isNotEmpty &&
        old.labels.isNotEmpty &&
        widget.labels.last == old.labels.last;
    final grew = widget.labels.length - old.labels.length;
    final prepended = widget.historyCount - old.historyCount;
    if (!sameTail || (grew != 0 && grew != prepended)) {
      _pan.stop();
      _back = 0;
    }
    if (_back > _maxBack) _back = _maxBack;
    final sig = widget.lines.map((l) => l.key).join('|');
    if (sig != _lineSig) {
      _resetVisibility();
      return;
    }
    final f = widget.focusKey;
    if (f != null && f != old.focusKey && _hasLine(f)) {
      _vis = {..._vis, f};
      _focus = f;
      _comboTakeFocus(f);
    }
  }

  /// 外面点了某个指标格：量类换柱，其余换线。
  void _comboTakeFocus(String? f) {
    if (!widget.combo || f == null || !_hasLine(f)) return;
    if (widget.comboBarKeys.contains(f)) {
      _barKey = f;
    } else {
      _lineKey = f;
    }
  }

  bool _hasLine(String key) =>
      widget.lines.any((l) => l.key == key) ||
      (key == lhHeroBarsTabKey && widget.segmented && widget.bars != null);

  void _resetVisibility() {
    _lineSig = widget.lines.map((l) => l.key).join('|');
    final want = widget.defaultVisible;
    _vis = {
      for (final l in widget.lines)
        if (want == null || want.contains(l.key)) l.key,
    };
    final f = widget.focusKey;
    if (f != null && _hasLine(f)) _vis.add(f);
    _focus = (f != null && _hasLine(f))
        ? f
        : widget.lines
              .map((l) => l.key)
              .firstWhere((k) => _vis.contains(k), orElse: () => '');
    if (_focus == '') _focus = null;
    _barKey = null;
    _lineKey = null;
    _comboTakeFocus(f);
  }

  // ── 视窗（股票式往前拉）────────────────────────────────────────────────
  //
  //   一屏 _n 格。_startD = 视窗左沿的绝对下标（可以是小数，拖动中跟手）。
  //   画的时候左右各多带一格（_i0 … _i0+_m），线从卡边出去而不是半路断掉。
  //   线的上下归一只看「整格视窗」那 _n 个点，拖动时不至于每帧乱跳。

  int get _len => widget.labels.length;
  int get _n {
    final a = widget.visibleCount;
    final b = widget.wideVisibleCount ?? a;
    // ?? 0.0（不是 0）：保持 double，lerpDouble 的 t 要 double，写 0 会推成 num 编译不过。
    final t = (_handoff?.progress.value ?? 0.0).clamp(0.0, 1.0);
    final n = ui.lerpDouble(a.toDouble(), b.toDouble(), t)!;
    return math.max(0, math.min(n.round(), _len));
  }
  double get _maxBack => _n < 2 ? 0.0 : math.max(0, _len - _n).toDouble();
  bool get _canPan => _maxBack > 0 || widget.onNeedHistory != null;

  /// 视窗左沿（绝对下标，小数）。拖出界时允许略超一点（橡皮筋）。
  double get _startD => (_len - _n) - _back;

  /// 整格视窗左沿（绝对下标）：归一、横轴、选中点都按它。
  int get _start =>
      ((_len - _n) - _back.clamp(0.0, _maxBack)).round().clamp(0, math.max(0, _len - _n)).toInt();

  int get _i0 => math.max(0, _startD.floor() - 1);
  int get _iEnd => math.min(_len, _startD.ceil() + _n + 1);
  int get _m => math.max(0, _iEnd - _i0);

  /// 本地第 k 格在横轴上的位置 = k + _origin（单位：格，0 = 视窗左沿）。
  double get _origin => _i0 - _startD;

  List<double?> _span(List<double?> v) {
    final out = List<double?>.filled(_m, null);
    for (var k = 0; k < _m; k++) {
      final i = _i0 + k;
      if (i >= 0 && i < v.length) {
        final x = v[i];
        out[k] = (x != null && x.isFinite) ? x : null;
      }
    }
    return out;
  }

  bool _hasData(List<double?> w) => w.any((v) => v != null && v.isFinite);

  /// 选中点：只有落在当前整格视窗里才画（拖走了就先不画，外层大数照旧）。
  int? get _sel {
    final s = widget.onSelectedIndexChanged != null
        ? widget.selectedIndex
        : _localSel;
    if (s == null || s < _start || s >= _start + _n || s >= _len) return null;
    return s;
  }

  double _stepPx(double w) => _n < 2 ? w : w * 0.90 / (_n - 1);

  void _maybeNeedHistory({bool onStart = false}) {
    final cb = widget.onNeedHistory;
    if (cb == null || !widget.historyHasMore || widget.historyLoading) return;
    if ((onStart && widget.historyCount == 0) || _startD <= 3) cb();
  }

  void _panStart(DragStartDetails d) {
    _pan.stop();
    _maybeNeedHistory(onStart: true);
  }

  void _panUpdate(DragUpdateDetails d, double w) {
    final dx = d.delta.dx;
    final handoff = _handoff;
    final wideT = handoff?.progress.value ?? 0;
    final atLatest = _back <= 0.02;
    if (handoff != null &&
        (_relaying || wideT > 0.02 || (atLatest && dx < 0))) {
      if (!_relaying) {
        _relaying = true;
        handoff.begin();
      }
      if (_back > 0 && dx < 0) setState(() => _back = 0);
      handoff.update(dx);
      return;
    }
    if (_n < 2) return;
    final step = dx / _stepPx(w);
    var next = _back + step;
    // 出界：越拽越沉，最多拽出小半格。
    if (next < 0 && step < 0) next = _back + step / (1 + (-_back) * 8);
    if (next > _maxBack && step > 0) {
      next = _back + step / (1 + (_back - _maxBack) * 8);
    }
    next = next.clamp(-0.45, _maxBack + 0.45).toDouble();
    if (next == _back) return;
    setState(() => _back = next);
    _maybeNeedHistory();
  }

  void _panEnd(DragEndDetails d, double w) {
    if (_relaying) {
      _relaying = false;
      _handoff?.end(d.velocity.pixelsPerSecond.dx);
    }
    if (_n < 2) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    // 甩一下多走几格（惯性），落点吸到整格。
    final fling = vx.abs() > 280 ? vx / _stepPx(w) * 0.22 : 0.0;
    final target = (_back + fling).round().clamp(0, _maxBack.round()).toDouble();
    _animateBackTo(target);
    _maybeNeedHistory();
  }

  void _panCancel() {
    if (_relaying) {
      _relaying = false;
      _handoff?.cancel();
    }
    _animateBackTo(_back.round().clamp(0, _maxBack.round()).toDouble());
  }

  void _animateBackTo(double target) {
    _pan.value = _back;
    final dist = (target - _back).abs();
    final ms = (180 + dist * 40).clamp(180, 420).round();
    _pan.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
  }

  void _backToLatest() {
    _animateBackTo(0);
  }

  void _select(int? i) {
    if (widget.onSelectedIndexChanged != null) {
      widget.onSelectedIndexChanged!(i);
    } else {
      setState(() => _localSel = i);
    }
  }

  int _colAt(double dx, double w) {
    final n = _n;
    if (n <= 1) return math.max(0, _len - 1);
    final t = ((dx / w) - 0.05) / 0.90 * (n - 1);
    return (_start + t.round()).clamp(_start, _start + n - 1).toInt();
  }

  void _tapColumn(double dx, double w) {
    if (_n <= 0) return;
    final i = _colAt(dx, w);
    _select(_sel == i ? null : i);
  }

  void _scrubColumn(double dx, double w) {
    if (_n <= 0) return;
    final i = _colAt(dx, w);
    if (_sel != i) _select(i);
  }

  void _tapChip(String key) {
    setState(() {
      final vis = {..._vis};
      var foc = _focus;
      if (!vis.contains(key)) {
        vis.add(key);
        foc = key;
      } else if (foc == key) {
        final others = widget.lines
            .where((l) => vis.contains(l.key) && l.key != key)
            .toList();
        if (others.isNotEmpty) {
          vis.remove(key);
          foc = others.first.key;
        }
      } else {
        foc = key;
      }
      _vis = vis;
      _focus = foc;
    });
  }

  // ── 样式 ──────────────────────────────────────────────────────────────────
  Color _c(Color c, [DunesColorRole role = DunesColorRole.foreground]) =>
      DunesColors.resolve(context, c, role: role);

  TextStyle _sans(double size, FontWeight w, Color c) => LhTypography.sans(
    size: size,
    color: _c(c),
    weight: w,
    height: 1.15,
    context: context,
  );

  TextStyle _mono(double size, FontWeight w, Color c) => LhTypography.mono(
    size: size,
    color: _c(c),
    weight: w,
    height: 1.15,
    context: context,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _c(const Color(0xFFFFFFFF), DunesColorRole.surface),
            _c(const Color(0xFFF6F2FE), DunesColorRole.surface),
          ],
        ),
        border: Border.all(color: _c(_kEdge, DunesColorRole.border), width: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -60,
            width: 180,
            height: 180,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kPlum.withAlpha(26),
                      _kPlum.withAlpha(0),
                    ],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 7),
                Expanded(child: widget.body ?? _chartBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 卡头：标题 + 右边的小部件。不再挂说明胶囊（「叠加 4 条」之类读着像格子噪音）。
  Widget _header() {
    // 往前翻过了：标题旁写清楚现在看的是哪几天，并给一颗「回最新」。
    final panned = widget.body == null && _n >= 2 && _back >= 0.5;
    final range = panned
        ? '${widget.labels[_start]}–${widget.labels[math.min(_len - 1, _start + _n - 1)]}'
        : null;
    final showPeriodChip = _periodChipVisible(panned);
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Text(
            widget.title,
            maxLines: 1,
            style: _sans(11.5, FontWeight.w700, _kInk),
          ),
          if (showPeriodChip) ...[
            const SizedBox(width: 6),
            Flexible(
              child: LayoutBuilder(
                builder: (context, box) => _periodChip(box.maxWidth),
              ),
            ),
          ],
          if (range != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                range,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(9.5, FontWeight.w600, _kSub),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: '回到最新',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _backToLatest,
                child: Container(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _c(_kChipFocusFill, DunesColorRole.surface),
                    border: Border.all(
                      color: _c(_kChipFocusEdge, DunesColorRole.border),
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('最新 ›', style: _sans(9.5, FontWeight.w700, _kDeep)),
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (range != null) const SizedBox(width: 4),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }

  /// 「本期合计」旁的小日期（2026-10-27）。
  ///   · 没点任何一格：写当期（最后一格；今天 / 本月还没过完就带「进行中」），淡紫底。
  ///   · 手指点到别的日期 / 月份：写那一格，紫色实底 + ×，点一下回到当期。
  ///   · 往前翻页且没选中：标题旁已经写了区间，这里不再重复。
  bool _periodChipVisible(bool panned) {
    if (widget.body != null || _len == 0) return false;
    return !(_sel == null && panned);
  }

  /// [maxWidth] 放不下「· 进行中」时只写日期（窄屏 Hero 右卡只有 ~70pt）。
  Widget _periodChip(double maxWidth) {
    final sel = _sel;
    final i = sel ?? _len - 1;
    final active = sel != null && sel != _len - 1;
    final partial = widget.lastIsPartial && i == _len - 1;
    final date = widget.labels[i].trim();
    final textStyle = active
        ? LhTypography.mono(
            size: 9.5,
            color: Colors.white,
            weight: FontWeight.w700,
            height: 1.15,
            context: context,
          )
        : _mono(9.5, FontWeight.w700, _kDeep);
    var text = partial ? '$date · 进行中' : date;
    if (partial) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final chrome = 12.0 + (active ? 12 : 0);
      if (tp.width + chrome > maxWidth) text = date;
      tp.dispose();
    }
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 18,
      padding: EdgeInsets.fromLTRB(6, 0, active ? 4 : 6, 0),
      // 不设 alignment：设了会在 Flexible 里撑满整格，标签就不贴着文字了。
      decoration: BoxDecoration(
        color: active
            ? _c(_kPlum, DunesColorRole.surface)
            : _c(_kChipFocusFill, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 2),
            const Icon(Icons.close_rounded, size: 10, color: Colors.white),
          ],
        ],
      ),
    );
    if (!active) return chip;
    return Semantics(
      button: true,
      label: '回到当期',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(null),
        child: chip,
      ),
    );
  }

  // ── 图例胶囊 ──────────────────────────────────────────────────────────────
  Widget _chip({
    required String name,
    required bool on,
    required bool focus,
    required Widget swatch,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: on,
      label: name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 21,
          padding: const EdgeInsets.fromLTRB(7, 0, 8, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _c(
              focus ? _kChipFocusFill : const Color(0xFFFFFFFF),
              DunesColorRole.surface,
            ),
            border: Border.all(
              color: _c(
                focus ? _kChipFocusEdge : (on ? _kEdge : _kChipEdge),
                DunesColorRole.border,
              ),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              swatch,
              const SizedBox(width: 5),
              Text(
                name,
                maxLines: 1,
                style: _sans(
                  10.5,
                  focus ? FontWeight.w700 : FontWeight.w500,
                  on ? _kInk : _kMute2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineSwatch(Color color, List<double>? dash, double width) => SizedBox(
    width: 12,
    height: 3,
    child: CustomPaint(
      painter: _SwatchPainter(color: color, dash: dash, width: width),
    ),
  );

  Widget _barSwatch(Color color) => SizedBox(
    height: 8,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in const [5.0, 8.0, 3.0]) ...[
          Container(width: 2, height: h, color: color),
          if (h != 3.0) const SizedBox(width: 1),
        ],
      ],
    ),
  );

  /// 图例：一行横滑，右缘渐隐 —— 原来 Wrap 折成两行，白吃掉图一截高度。
  Widget _chips(List<LhHeroLine> available, bool hasBars) {
    final off = _c(const Color(0xFFD8D3E3));
    final chips = <Widget>[
        for (final l in available)
          _chip(
            name: l.name,
            on: _vis.contains(l.key),
            focus: _focus == l.key,
            swatch: _lineSwatch(
              _vis.contains(l.key) ? _c(l.color) : off,
              l.dash,
              _focus == l.key ? 2 : 1.4,
            ),
            onTap: () => _tapChip(l.key),
          ),
        if (hasBars)
          _chip(
            name: widget.bars!.name,
            on: widget.barsVisible,
            focus: false,
            swatch: _barSwatch(widget.barsVisible ? _c(_kBarPos) : off),
            onTap: () =>
                widget.onBarsVisibleChanged?.call(!widget.barsVisible),
          ),
    ];
    return SizedBox(
      height: 21,
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.9, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 14),
          // Clamping：放得下时不接横拖，图例空白处照旧能左滑拉宽走势卡。
          physics: const ClampingScrollPhysics(),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (_, i) => chips[i],
        ),
      ),
    );
  }

  // ── 柱 + 线（原型 B）─────────────────────────────────────────────────────

  ({LhHeroLine bar, LhHeroLine line})? _comboPair(List<LhHeroLine> available) {
    if (available.length < 2) return null;
    LhHeroLine? find(String? k) {
      if (k == null) return null;
      for (final l in available) {
        if (l.key == k) return l;
      }
      return null;
    }

    final bar =
        find(_barKey) ??
        available.firstWhere(
          (l) => widget.comboBarKeys.contains(l.key),
          orElse: () => available.first,
        );
    var line = find(_lineKey);
    if (line == null || line.key == bar.key) {
      line = available.firstWhere(
        (l) => l.key != bar.key && !widget.comboBarKeys.contains(l.key),
        orElse: () => available.firstWhere((l) => l.key != bar.key),
      );
    }
    return (bar: bar, line: line);
  }

  /// 读数行默认读哪一天：停在最新 → 当期（今天 / 本月，没过完也读，读数带「进行中」，
  /// 和左边大数、标题旁的日期标签同一格）；往前翻了 → 视窗最右那天。
  /// 2026-10-27：原来今天没过完就退一天，结果默认高亮昨天、读数也是昨天，跟左边对不上。
  int? _comboReadIndex() {
    if (_len == 0) return null;
    return _back.abs() < 0.5 ? _len - 1 : math.min(_len - 1, _start + _n - 1);
  }

  /// 「柱 · 核销额 ▾」「线 · 利润 ▾」：和图例胶囊同一套外形，点开换指标。
  Widget _comboPickers(
    List<LhHeroLine> available,
    ({LhHeroLine bar, LhHeroLine line}) p,
  ) {
    final barOpts = available
        .where((l) => widget.comboBarKeys.contains(l.key))
        .toList();
    final lineOpts = available.where((l) => l.key != p.bar.key).toList();
    // 手机上右卡只有 ~200px，两颗胶囊加起来 ~220：放不下就整排等比缩一点，不溢出。
    return SizedBox(
      height: 21,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _comboPicker(
            role: '柱',
            cur: p.bar,
            options: barOpts.isEmpty ? <LhHeroLine>[p.bar] : barOpts,
            swatch: _barSwatch(_c(p.bar.color)),
            onPick: (k) => setState(() {
              // 选了现在当线的那个：两边对调。
              if (k == p.line.key) _lineKey = p.bar.key;
              _barKey = k;
            }),
          ),
          const SizedBox(width: 4),
          _comboPicker(
            role: '线',
            cur: p.line,
            options: lineOpts,
            swatch: _lineSwatch(_c(p.line.color), null, 2),
            onPick: (k) => setState(() => _lineKey = k),
          ),
        ],
      ),
      ),
    );
  }

  Widget _comboPicker({
    required String role,
    required LhHeroLine cur,
    required List<LhHeroLine> options,
    required Widget swatch,
    required ValueChanged<String> onPick,
  }) {
    return PopupMenuButton<String>(
      tooltip: '换$role的指标',
      onSelected: onPick,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      color: _c(const Color(0xFFFFFFFF), DunesColorRole.surface),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _c(_kEdge, DunesColorRole.border), width: 0.8),
      ),
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem<String>(
            value: o.key,
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: o.key == cur.key
                      ? Icon(Icons.check_rounded, size: 13, color: _c(_kFocus))
                      : null,
                ),
                Text(
                  o.name,
                  style: _sans(
                    12,
                    o.key == cur.key ? FontWeight.w700 : FontWeight.w500,
                    _kInk,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 21,
        padding: const EdgeInsets.fromLTRB(7, 0, 5, 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _c(_kChipFocusFill, DunesColorRole.surface),
          border: Border.all(
            color: _c(_kChipFocusEdge, DunesColorRole.border),
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 5),
            Text(
              '$role · ${cur.name}',
              maxLines: 1,
              style: _sans(10.5, FontWeight.w700, _kInk),
            ),
            const SizedBox(width: 1),
            Icon(Icons.expand_more_rounded, size: 14, color: _c(_kSub)),
          ],
        ),
      ),
    );
  }

  /// 固定一行读数（代替浮动读数卡）：日期 · 柱值 · 线值 · 比值。
  Widget _comboReadout(int? idx, ({LhHeroLine bar, LhHeroLine line}) p) {
    if (idx == null || idx < 0 || idx >= _len) {
      return const SizedBox(height: 16);
    }
    double? at(LhHeroLine l) => idx < l.values.length ? l.values[idx] : null;
    final bv = at(p.bar), lv = at(p.line);
    final partial = widget.lastIsPartial && idx == _len - 1;
    final ratioLabel = widget.comboRatioLabels[p.line.key];
    final ratio =
        ratioLabel != null && bv != null && lv != null && bv.abs() > 0
        ? lv / bv * 100
        : null;
    return SizedBox(
      height: 16,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${widget.labels[idx]}${partial ? ' 进行中' : ''}',
                style: _mono(9.5, FontWeight.w600, _kSub),
              ),
              TextSpan(
                text: '   ${p.bar.name} ',
                style: _sans(10, FontWeight.w500, _kMuteText),
              ),
              TextSpan(
                text: bv == null ? '—' : p.bar.format(bv),
                style: _mono(11.5, FontWeight.w700, _kInk),
              ),
              TextSpan(
                text: '   ${p.line.name} ',
                style: _sans(10, FontWeight.w500, _kMuteText),
              ),
              TextSpan(
                text: lv == null ? '—' : p.line.format(lv),
                style: _mono(11.5, FontWeight.w700, p.line.color),
              ),
              if (ratio != null) ...[
                TextSpan(
                  text: '   $ratioLabel ',
                  style: _sans(10, FontWeight.w500, _kMuteText),
                ),
                TextSpan(
                  text: '${ratio.toStringAsFixed(2)}%',
                  style: _mono(10.5, FontWeight.w700, _kInk),
                ),
              ],
            ],
          ),
          maxLines: 1,
        ),
      ),
    );
  }

  // ── 分段 + 大读数（原型 A 的排布）──────────────────────────────────────

  /// 一排分段按钮：淡紫底槽 + 白色选中块（同资金页「利润 | 资金」那条）。
  /// 指标多、手机卡窄时整排横滑（Clamping：放得下时不接横拖，不抢拉宽手势）。
  Widget _segmentTabs(List<LhHeroLine> available, String? focus) {
    // 2026-10-27 · 去掉托盘：每段一颗圆角小胶囊，选中那颗铺一层自己颜色的淡底。
    return SizedBox(
      height: 24,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in available)
              Semantics(
                button: true,
                selected: l.key == focus,
                label: l.name,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _focus = l.key;
                    _vis = {..._vis, l.key};
                    widget.onFocusChanged?.call(l.key);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 22,
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: l.key == focus
                          ? _c(l.color, DunesColorRole.surface).withAlpha(26)
                          : _c(const Color(0xFFF6F4FA), DunesColorRole.surface),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    // 每段前面一小段线（和图里那根线同色），比色块更像图例。
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 3,
                          decoration: BoxDecoration(
                            color: _c(l.color).withAlpha(l.key == focus ? 255 : 128),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l.name,
                          maxLines: 1,
                          style: _sans(
                            11.5,
                            l.key == focus ? FontWeight.w700 : FontWeight.w500,
                            l.key == focus ? _kInk : _kMuteText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 「2.68亿  ↑14%  10.25 整天 · 较前一日」：主线在读数那天的值、和前一期比。
  Widget _focusReadout(int? idx, LhHeroLine line) {
    if (idx == null || idx < 0 || idx >= _len) {
      return const SizedBox(height: 26);
    }
    final v = idx < line.values.length ? line.values[idx] : null;
    double? prev;
    for (var k = idx - 1; k >= 0 && k >= idx - 3; k--) {
      final p = k < line.values.length ? line.values[k] : null;
      if (p != null) {
        prev = p;
        break;
      }
    }
    final partial = widget.lastIsPartial && idx == _len - 1;
    final label = widget.labels[idx].trim();
    final isDay = RegExp(r'^\d{1,2}\.\d{1,2}$').hasMatch(label);
    final isMonth = RegExp(r'^\d{4}[.\-/]\d{1,2}$').hasMatch(label);
    // 2026-10-26 · 读数后面只写「vs 上日 / vs 上月」，日期和「整天」都不写了
    // （点了哪天，浮出来的小卡片上有日期）。
    final vs =
        widget.compareLabel ??
        (isDay ? 'vs 上日' : (isMonth ? 'vs 上月' : 'vs 上期'));
    // 值拆成「数 + 单位」：数大、单位小一号降色（2.68 亿）。
    final text = v == null ? '—' : line.format(v);
    final m = RegExp(r'^([−\-+]?[\d.,]+)(.*)$').firstMatch(text);
    final numText = m?.group(1) ?? text;
    final unit = m?.group(2) ?? '';
    final pct = (v != null && prev != null && prev.abs() > 1e-9)
        ? (v - prev) / prev.abs() * 100
        : null;
    final up = (pct ?? 0) >= 0;
    final pctColor = up ? const Color(0xFFB4501F) : const Color(0xFF2F7A4F);
    return SizedBox(
      height: 22,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              numText,
              // 2026-10-26 · 读数和选中那一段同色（核销紫、销售蓝、利润红、收入琥珀、
              // GMV 青、成本灰）；利润 / 净利润是负数时用绿。
              style: _sans(
                18,
                FontWeight.w800,
                (line.key == 'profit' || line.key == 'netProfit') &&
                        v != null &&
                        v < 0
                    ? LhColors.pos
                    : line.color,
              ).copyWith(
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
            Text(unit, style: _sans(11, FontWeight.w500, _kMuteText)),
            if (pct != null && !partial) ...[
              const SizedBox(width: 7),
              Text(
                '${up ? '↑' : '↓'}${pct.abs().toStringAsFixed(pct.abs() >= 10 ? 0 : 1)}%',
                style: _mono(11, FontWeight.w700, pctColor),
              ),
            ],
            if (partial || pct != null) ...[
              const SizedBox(width: 5),
              Text(
                partial ? '进行中' : vs,
                maxLines: 1,
                style: _sans(10, FontWeight.w500, _kMuteText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 图 ────────────────────────────────────────────────────────────────────
  Widget _chartBody() {
    // 图例按整条序列判断有没有数（不按视窗）—— 往前翻时胶囊不会忽隐忽现。
    final available = widget.lines.where((l) => _hasData(l.values)).toList();
    final pair = widget.combo ? _comboPair(available) : null;
    final hasBars = widget.bars != null && _hasData(widget.bars!.values);
    // 分段模式：柱也排进分段（资金页「总资产 | 中石油 | 中石化 | 预收净增」）。
    final barsTab = widget.segmented && pair == null && hasBars
        ? LhHeroLine(
            key: lhHeroBarsTabKey,
            name: widget.bars!.name,
            color: _kBarPos,
            values: widget.bars!.values,
            format: widget.bars!.format,
          )
        : null;
    final barsFocused = barsTab != null && _focus == lhHeroBarsTabKey;
    final showBars = hasBars && (widget.barsVisible || barsFocused);
    if (available.isEmpty && !hasBars) {
      return Center(
        child: Text(widget.emptyText, style: _sans(10, FontWeight.w500, _kMute2)),
      );
    }
    final spans = <String, List<double?>>{
      for (final l in available) l.key: _span(l.values),
    };
    final barsSpan = pair != null
        ? _span(pair.bar.values)
        : (showBars ? _span(widget.bars!.values) : null);
    final segTabs = <LhHeroLine>[...available, if (barsTab != null) barsTab];
    final seg = widget.segmented && pair == null && segTabs.isNotEmpty;
    final drawn = pair != null
        ? <LhHeroLine>[pair.line]
        : available
              .where((l) => _vis.contains(l.key) || (seg && l.key == _focus))
              .toList();
    final focus = pair != null
        ? pair.line.key
        : (barsFocused
              ? lhHeroBarsTabKey
              : (drawn.any((l) => l.key == _focus)
                    ? _focus
                    : (drawn.isEmpty ? null : drawn.first.key)));
    // 没点任何一天、且停在最新时，默认标出最后一列（今天）：列高光 + 每根线
    // 一个圆点，但不出读数卡。往前翻了就不标 —— 那一列已经不在屏上了。
    final sel = _sel;
    // 没点哪天时读数行和高亮都停在当期（见 _comboReadIndex）。
    final readIdx = (pair == null && !seg) ? null : _comboReadIndex();
    final markAbs =
        sel ??
        ((pair != null || seg)
            ? readIdx
            : (_back.abs() < 0.5 && _len > 0 ? _len - 1 : null));
    final markJ = markAbs == null ? null : markAbs - _i0;
    final selJ = sel == null ? null : sel - _start;
    final normFrom = _start - _i0;
    final normTo = normFrom + _n - 1;
    final windowEmpty =
        !drawn.any((l) {
          for (var k = normFrom; k <= normTo; k++) {
            final v = k >= 0 && k < spans[l.key]!.length ? spans[l.key]![k] : null;
            if (v != null) return true;
          }
          return false;
        }) &&
        !(barsSpan?.any((v) => v != null) ?? false);

    final paintLines = <_PaintLine>[
      for (final l in drawn)
        _PaintLine(
          values: spans[l.key]!,
          // 柱 + 线：线用自己的颜色（利润 = 铜色），和后面的紫柱一眼分开；一律实线。
          color: pair != null
              ? _c(l.color)
              // 主线也用自己的颜色（利润红、核销紫…），靠粗细和渐变面区分主次。
              : _c(l.color),
          dash: pair != null ? null : l.dash,
          focus: l.key == focus,
          format: l.format,
          stock: l.stock,
        ),
    ];
    // 主线最后画，压在最上面。
    paintLines.sort((a, b) => (a.focus ? 1 : 0) - (b.focus ? 1 : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pair != null) ...[
          _comboPickers(available, pair),
          const SizedBox(height: 5),
          _comboReadout(sel ?? readIdx, pair),
          const SizedBox(height: 4),
        ] else if (seg) ...[
          _segmentTabs(segTabs, focus),
          const SizedBox(height: 6),
          _focusReadout(
            sel ?? readIdx,
            segTabs.firstWhere(
              (l) => l.key == focus,
              orElse: () => drawn.isEmpty ? segTabs.first : drawn.first,
            ),
          ),
          const SizedBox(height: 4),
        ] else ...[
          _chips(available, hasBars),
          const SizedBox(height: 6),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final tipOnLeft =
                  selJ != null &&
                  _n > 1 &&
                  (0.05 + 0.9 * selJ / (_n - 1)) > 0.55;
              final pan = _canPan || _handoff != null;
              return LighthouseHDrag(
                behavior: HitTestBehavior.opaque,
                onStart: pan ? _panStart : null,
                onUpdate: pan ? (d) => _panUpdate(d, w) : null,
                onEnd: pan ? (d) => _panEnd(d, w) : null,
                onCancel: pan ? _panCancel : null,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tapColumn(d.localPosition.dx, w),
                onLongPressStart: (d) => _scrubColumn(d.localPosition.dx, w),
                onLongPressMoveUpdate: (d) =>
                    _scrubColumn(d.localPosition.dx, w),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRect(
                       child: CustomPaint(
                        painter: _HeroTrendPainter(
                          n: _n,
                          origin: _origin,
                          normFrom: normFrom,
                          normTo: normTo,
                          partialK: widget.lastIsPartial && _len > 0
                              ? _len - 1 - _i0
                              : null,
                          lines: paintLines,
                          bars: barsSpan,
                          selJ: markJ,
                          grid: _c(_kGrid, DunesColorRole.border),
                          base: _c(const Color(0xFFDCD2F5), DunesColorRole.border),
                          plum: _c(_kPlum),
                          barPos: _c(_kBarPos),
                          barNeg: _c(_kBarNeg),
                          barPosSel: _c(_kBarPosSel),
                          barNegSel: _c(_kBarNegSel),
                          dotFill: _c(const Color(0xFFFFFFFF), DunesColorRole.surface),
                          barsOverlay: pair != null,
                          barColor: pair != null ? _c(pair.bar.color) : null,
                        ),
                       ),
                      ),
                    ),
                    if (windowEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              widget.historyLoading ? '加载更早…' : '这段没有数据',
                              style: _sans(10, FontWeight.w500, _kMute2),
                            ),
                          ),
                        ),
                      ),
                    if (_viewportTag() case final tag?)
                      Positioned(
                        left: 2,
                        bottom: 2,
                        child: IgnorePointer(child: tag),
                      ),
                    // 点了某天：照旧浮那张列全字段的小卡片（分段模式也要，大读数只读主线）。
                    if (sel != null && pair == null)
                      Positioned(
                        top: 0,
                        left: tipOnLeft ? 2 : null,
                        right: tipOnLeft ? null : 2,
                        child: IgnorePointer(
                          child: _tooltip(
                            sel,
                            drawn,
                            focus,
                            showBars && sel < widget.bars!.values.length
                                ? widget.bars!.values[sel]
                                : null,
                            showBars,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              );
            },
          ),
        ),
        SizedBox(
          height: 12,
          child: ClipRect(child: _xLabels(markAbs)),
        ),
      ],
    );
  }

  /// 左下角的小状态：正在往前拉 / 已经到最早。
  Widget? _viewportTag() {
    if (_n < 2) return null;
    String? text;
    if (widget.historyLoading && _startD < 6) {
      text = '加载更早…';
    } else if (!widget.historyHasMore &&
        _maxBack > 0 &&
        _back >= _maxBack - 0.5 &&
        _back >= 0.5) {
      text = '已到最早';
    }
    if (text == null) return null;
    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _c(const Color(0xE6FFFFFF), DunesColorRole.surface),
        border: Border.all(color: _c(_kEdge, DunesColorRole.border), width: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: _sans(9, FontWeight.w600, _kSub)),
    );
  }

  Widget _tooltip(
    int sel,
    List<LhHeroLine> drawn,
    String? focus,
    double? barValue,
    bool showBars,
  ) {
    final title =
        '${widget.labels[sel]}'
        '${widget.lastIsPartial && sel == widget.labels.length - 1 ? ' · 今日进行中' : ''}';
    Widget row(Color c, String name, String v, {bool bold = false, bool round = true, Color? vc}) =>
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(round ? 1.5 : 1),
                ),
              ),
              const SizedBox(width: 5),
              Text(name, style: _sans(9.5, FontWeight.w500, _kMuteText)),
              const SizedBox(width: 10),
              Text(
                v,
                style: _mono(
                  9.5,
                  bold ? FontWeight.w700 : FontWeight.w500,
                  vc ?? (bold ? _kInk : _kMuteText),
                ),
              ),
            ],
          ),
        );
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
      decoration: BoxDecoration(
        color: _c(const Color(0xF0FFFFFF), DunesColorRole.surface),
        border: Border.all(color: _c(_kEdge, DunesColorRole.border), width: 0.8),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F4A3A7A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _mono(9, FontWeight.w600, _kSub)),
          for (final l in drawn)
            Builder(
              builder: (_) {
                final v = sel < l.values.length ? l.values[sel] : null;
                return row(
                  _c(l.color),
                  l.name,
                  v == null ? '待更新' : l.format(v),
                  bold: l.key == focus,
                  vc: v == null ? _kMute2 : null,
                );
              },
            ),
          if (showBars && barValue != null)
            row(
              barValue >= 0 ? _c(_kBarPos) : _c(_kBarNeg),
              widget.bars!.name,
              widget.bars!.format(barValue),
              bold: true,
              round: false,
            ),
        ],
      ),
    );
  }

  /// 横轴：「10.16」只写「.16」；点多时隔一个写一个（最后一个和选中的总写）。
  Widget _xLabels(int? sel) {
    final n = _n;
    if (n <= 0) return const SizedBox.shrink();
    final step = n > 7 ? 2 : 1;
    final shortRe = RegExp(r'^\d{1,2}\.(\d{1,2})$');
    // 月线「2026.06」整串写满 40px 一格，挤成一排、右端还被裁掉（看着像乱码）——
    // 缩成「6月」；1 月写年份「2026」交代跨年；本月（进行中）写「本月」。
    final monthRe = RegExp(r'^(\d{4})[.\-/](\d{1,2})$');
    // 往前翻过后：视窗第一格和每月 1 号写全「9.28」，不然跨月就分不清是哪个月。
    final panned = _back >= 0.5;
    String short(int i) {
      final s = widget.labels[i];
      final mm = monthRe.firstMatch(s.trim());
      if (mm != null) {
        if (widget.lastIsPartial && i == _len - 1) return '本月';
        final month = int.tryParse(mm.group(2)!) ?? 0;
        return month == 1 ? mm.group(1)! : '$month月';
      }
      final m = shortRe.firstMatch(s.trim());
      if (m == null) return s;
      // 日线的最后一格是「今天、还没过完」：直接写「今」，和那段虚线互相交代。
      if (widget.lastIsPartial && i == _len - 1) return '今';
      final day = int.tryParse(m.group(1)!) ?? 0;
      if (panned && (i == _start || day == 1)) return s.trim();
      return '.${m.group(1)}';
    }

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = _i0; i < _iEnd; i++)
              if ((_len - 1 - i) % step == 0 || i == sel)
                Positioned(
                  left: (n == 1 ? 0.5 : 0.05 + 0.9 * (i - _startD) / (n - 1)) * w - 20,
                  width: 40,
                  top: 0,
                  child: Text(
                    short(i),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: _mono(
                      9,
                      i == sel ? FontWeight.w700 : FontWeight.w400,
                      i == sel ? _kDeep : const Color(0xFF7A7590),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PaintLine {
  const _PaintLine({
    required this.values,
    required this.color,
    required this.dash,
    required this.focus,
    required this.format,
    this.stock = false,
  });

  final List<double?> values;
  final Color color;
  final List<double>? dash;
  final bool focus;
  final String Function(double v) format;
  final bool stock;
}

class _HeroTrendPainter extends CustomPainter {
  _HeroTrendPainter({
    required this.n,
    required this.origin,
    required this.normFrom,
    required this.normTo,
    required this.partialK,
    required this.lines,
    required this.bars,
    required this.selJ,
    required this.grid,
    required this.base,
    required this.plum,
    required this.barPos,
    required this.barNeg,
    required this.barPosSel,
    required this.barNegSel,
    required this.dotFill,
    this.barsOverlay = false,
    this.barColor,
  });

  /// 一屏几格。
  final int n;

  /// 本地第 k 格画在「视窗第 k + origin 格」（拖动中是小数）。
  final double origin;

  /// 归一只看这段本地下标（整格视窗），拖动时线不乱跳。
  final int normFrom, normTo;

  /// 「进行中」那一格的本地下标（今天还没过完）：通往它的最后一段画虚线、淡一档。
  final int? partialK;
  final List<_PaintLine> lines;
  final List<double?>? bars;
  final int? selJ;
  final Color grid, base, plum, barPos, barNeg, barPosSel, barNegSel, dotFill;

  /// 柱 + 线：柱从底部 0 起、铺满整个图高、画在线后面（不是资金那种底部正负柱带）。
  final bool barsOverlay;
  final Color? barColor;

  double _x(int k, double w) =>
      n <= 1 ? w / 2 : w * (0.05 + 0.90 * (k + origin) / (n - 1));

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (n <= 0 || w <= 0 || h <= 0) return;
    final hasBars = bars != null;
    // 2026-10-26 · 两个区上下分好：线区（上）/ 柱区（下），共用横轴。
    //   原来线挤在上半、柱沉在 80% 那根基线上，中间空一条带，两样东西各说各的。
    //   刻度字（1.94亿 / 4.28亿）压线又读不清，去掉了；量级看读数。
    // 2026-10-27 · 线不再顶满：上下各留一口气，渐变面才有地方淡出去。
    final lineTop = h * (barsOverlay ? 0.08 : 0.14);
    final lineBot = h * (barsOverlay ? 0.70 : (hasBars ? 0.56 : 0.80));
    final barTop = h * 0.70;
    final barBot = h * 0.98;

    // 网格：2026-10-27 · 三条很淡的点线（原来两根实发丝线）。柱 + 线只留顶上一条。
    final gridPaint = Paint()
      ..color = grid.withAlpha(170)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    final gridYs = barsOverlay
        ? [lineTop]
        : [
            lineTop,
            (lineTop + lineBot) / 2,
            hasBars ? lineBot : lineBot + (h - lineBot) * 0.5,
          ];
    for (final y0 in gridYs) {
      final y = y0.roundToDouble() + 0.5;
      for (var x = 0.0; x < w; x += 5) {
        canvas.drawLine(Offset(x, y), Offset(x + 1, y), gridPaint);
      }
    }

    // 「进行中」那一格垫一块很淡的竖条：这一格还没过完。
    final colW = n <= 1 ? w * 0.3 : w * 0.90 / (n - 1);
    if (partialK != null) {
      final cx = _x(partialK!, w);
      final bw = math.min(colW * 0.8, 40.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - bw / 2, 4, bw, h - 8),
          const Radius.circular(8),
        ),
        Paint()..color = plum.withAlpha(12),
      );
    }

    // 选中：一根细虚线竖线（原来是一整列渐变色块，太重）。颜色跟主线走。
    if (selJ != null) {
      final cx = _x(selJ!, w).roundToDouble() + 0.5;
      _PaintLine? focusLine;
      for (final l in lines) {
        if (l.focus) focusLine = l;
      }
      final guide = Paint()
        ..color = (focusLine?.color ?? plum).withAlpha(92)
        ..strokeWidth = 1;
      for (var y = 6.0; y < h - 6; y += 5) {
        canvas.drawLine(Offset(cx, y), Offset(cx, math.min(y + 2, h - 6)), guide);
      }
    }

    // 柱 + 线的柱：从底边 0 起（面积 / 高度编码的是量，必须从 0），按视窗里最大的
    // 那根铺到约 88% 高；今天没过完的那根只描虚线框，选中那根加深一档。
    if (hasBars && barsOverlay) {
      final baseY = (h * 0.985).roundToDouble() - 0.5;
      final topY = h * 0.12;
      var mx = 0.0;
      for (var k = math.max(0, normFrom); k <= normTo && k < bars!.length; k++) {
        final v = bars![k];
        if (v != null && v > mx) mx = v;
      }
      canvas.drawLine(
        Offset(0, baseY),
        Offset(w, baseY),
        Paint()
          ..color = base
          ..strokeWidth = 0.8,
      );
      if (mx > 0) {
        final unit = (baseY - topY) / mx;
        final bw = (colW * 0.46).clamp(4.0, 22.0).toDouble();
        final bc = barColor ?? barPos;
        for (var j = 0; j < bars!.length; j++) {
          final v = bars![j];
          if (v == null || v <= 0) continue;
          final bh = math.max(1.5, math.min(v, mx * 1.08) * unit);
          final x = _x(j, w);
          final rr = RRect.fromRectAndCorners(
            Rect.fromLTWH(x - bw / 2, baseY - bh, bw, bh),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          );
          if (j == partialK) {
            canvas.drawRRect(rr, Paint()..color = dotFill);
            canvas.drawPath(
              _dashPath(Path()..addRRect(rr), const [3, 2.5]),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = bc.withValues(alpha: 0.7),
            );
          } else {
            canvas.drawRRect(
              rr,
              Paint()..color = bc.withValues(alpha: j == selJ ? 0.42 : 0.2),
            );
          }
        }
      }
    }

    // 柱：在柱区里按正负各自的最大值分配上下 —— 全负时基线贴着柱区上沿、
    // 柱往下长满整个区；有正有负时基线落在中间按比例的位置。
    if (hasBars && !barsOverlay) {
      var pMax = 0.0, nMax = 0.0;
      for (var k = math.max(0, normFrom); k <= normTo && k < bars!.length; k++) {
        final v = bars![k];
        if (v == null) continue;
        if (v >= 0) {
          pMax = math.max(pMax, v);
        } else {
          nMax = math.max(nMax, -v);
        }
      }
      final total = pMax + nMax;
      final bandH = barBot - barTop;
      final baseY = total <= 0
          ? barBot
          : (barTop + bandH * pMax / total).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(0, baseY),
        Offset(w, baseY),
        Paint()
          ..color = base
          ..strokeWidth = 0.8,
      );
      if (total > 0) {
        final unit = bandH / total;
        final bw = n > 7 ? 6.0 : 8.0;
        for (var j = 0; j < bars!.length; j++) {
          final v = bars![j];
          if (v == null) continue;
          final cap = v >= 0 ? pMax : nMax;
          final bh = math.max(1.0, math.min(v.abs(), cap * 1.1) * unit);
          final x = _x(j, w);
          final isSel = j == selJ;
          final rect = v >= 0
              ? Rect.fromLTWH(x - bw / 2, baseY - bh, bw, bh)
              : Rect.fromLTWH(x - bw / 2, baseY, bw, bh);
          final rr = v >= 0
              ? RRect.fromRectAndCorners(
                  rect,
                  topLeft: const Radius.circular(2),
                  topRight: const Radius.circular(2),
                )
              : RRect.fromRectAndCorners(
                  rect,
                  bottomLeft: const Radius.circular(2),
                  bottomRight: const Radius.circular(2),
                );
          canvas.drawRRect(
            rr,
            Paint()
              ..color = v >= 0
                  ? (isSel ? barPosSel : barPos)
                  : (isSel ? barNegSel : barNeg),
          );
        }
      }
    }

    // 线
    final dots = <({Offset at, Color color, bool focus})>[];
    final ranges = _lineRanges();
    for (var li = 0; li < lines.length; li++) {
      final l = lines[li];
      final pts = <({int j, double v})>[
        for (var j = 0; j < l.values.length; j++)
          if (l.values[j] != null) (j: j, v: l.values[j]!),
      ];
      if (pts.isEmpty) continue;
      final lo = ranges[li]!.lo, hi = ranges[li]!.hi;
      final span = (hi - lo).abs() < 1e-12 ? 1.0 : hi - lo;
      double y(double v) => (hi - lo).abs() < 1e-12
          ? (lineTop + lineBot) / 2
          : lineTop + (1 - (v - lo) / span) * (lineBot - lineTop);
      // 「进行中」那一点超出值域时（今天还没过完，数小）钳在图里，不往下砸出去。
      final yMin = 4.0, yMax = h - 4;
      final offs = [
        for (final p in pts)
          Offset(_x(p.j, w), y(p.v).clamp(yMin, yMax).toDouble()),
      ];
      // 2026-10-27 · 线只画到最后一个整天；进行中那一格单独一个虚线空心圈（只给主线）。
      final tailPartial =
          partialK != null && offs.length >= 2 && pts.last.j == partialK;
      final bodyOffs = tailPartial ? offs.sublist(0, offs.length - 1) : offs;
      final path = _smooth(bodyOffs);

      // 柱 + 线不铺渐变面：底下已经有柱，再铺一层就糊了。
      if (l.focus && bodyOffs.length >= 2 && !barsOverlay) {
        final floor = hasBars ? lineBot : h;
        final area = Path.from(path)
          ..lineTo(bodyOffs.last.dx, floor)
          ..lineTo(bodyOffs.first.dx, floor)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, lineTop),
              Offset(0, floor),
              [l.color.withAlpha(60), l.color.withAlpha(10), l.color.withAlpha(0)],
              const [0.0, 0.7, 1.0],
            ),
        );
      }
      // 主线 2.4 + 一层淡淡的同色光晕；配线 1.3、三成色，只当背景看形状。
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = l.focus ? 2.4 : 1.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = l.focus ? l.color : l.color.withAlpha(82);
      if (bodyOffs.length == 1) {
        canvas.drawCircle(bodyOffs.first, l.focus ? 2.4 : 1.5, Paint()..color = stroke.color);
      } else if (bodyOffs.length >= 2) {
        final body = l.dash == null ? path : _dashPath(path, l.dash!);
        if (l.focus) {
          canvas.drawPath(
            body,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = l.color.withAlpha(46)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
        canvas.drawPath(body, stroke);
      }
      if (tailPartial && l.focus) {
        final at = offs.last;
        canvas.drawCircle(at, 4.2, Paint()..color = dotFill);
        canvas.drawPath(
          _dashPath(
            Path()..addOval(Rect.fromCircle(center: at, radius: 4.2)),
            const [2.4, 2],
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = l.color,
        );
      }
      if (selJ != null) {
        for (var k = 0; k < pts.length; k++) {
          if (pts[k].j == selJ) {
            dots.add((at: offs[k], color: l.color, focus: l.focus));
          }
        }
      }
    }

    // 选中点：主线实心圈 + 同色光环；配线小空心圈、淡一档。
    for (final d in dots) {
      if (d.focus) {
        canvas.drawCircle(d.at, 9, Paint()..color = d.color.withAlpha(36));
        canvas.drawCircle(d.at, 4.6, Paint()..color = dotFill);
        canvas.drawCircle(d.at, 3.4, Paint()..color = d.color);
      } else {
        canvas.drawCircle(d.at, 2.4, Paint()..color = dotFill);
        canvas.drawCircle(
          d.at,
          2.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = d.color.withAlpha(150),
        );
      }
    }
  }

  /// 每根线的纵向值域（视窗里那几格）。
  ///
  /// 2026-10-26 晚 · 改回「每根线各自拉满」：值域只取当前视窗里这几格，不并组、
  /// 不跟别的线共用一把尺，也不带视窗外的历史。这样每根线自己的起伏（哪个月掉下去、
  /// 哪个月冲上来）都完整画出来，一眼看出问题在哪 —— 共用尺子时利润、收入的拐点
  /// 被压平，看上去全是一路上涨。只有存量线（[LhHeroLine.stock]）保留 4% 下限。
  Map<int, ({double lo, double hi})> _lineRanges() {
    final out = <int, ({double lo, double hi})>{};
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final all = <double>[];
      final inView = <double>[];
      double? partialV;
      for (var j = 0; j < l.values.length; j++) {
        final v = l.values[j];
        if (v == null) continue;
        // 今天还没过完：不拿它定值域，否则整条线被压扁到上半截。
        if (j == partialK && !l.stock) {
          partialV = v;
          continue;
        }
        all.add(v);
        if (j >= normFrom && j <= normTo) inView.add(v);
      }
      // 整条线只有今天这一个点：只能拿它定值域。
      if (all.isEmpty && partialV != null) all.add(partialV);
      final ref = inView.isNotEmpty ? inView : all;
      if (ref.isEmpty) continue;
      var lo = ref.first, hi = ref.first;
      for (final v in ref) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      if (l.stock) {
        final level = math.max(hi.abs(), lo.abs());
        final minSpan = level * 0.04;
        if (hi - lo < minSpan && level > 0) {
          final mid = (hi + lo) / 2;
          lo = mid - minSpan / 2;
          hi = mid + minSpan / 2;
        }
      }
      out[i] = (lo: lo, hi: hi);
    }
    return out;
  }

  static Path _smooth(List<Offset> p) =>
      p.isEmpty ? Path() : _smoothRange(p, 0, p.length - 1);

  /// 从第 [from] 点画到第 [to] 点，切线仍按整条序列算 —— 拆成两段画时接缝是平的。
  ///
  /// 2026-10-26 · 换成单调三次（Fritsch–Carlson / Butland 切线）：原来的
  /// Catmull-Rom 在拐点会冲过头，画出数据里没有的鼓包（总资产 .20–.22 那两个包）。
  /// 单调插值保证两点之间不越过两端的值，平的地方就是平的。
  static Path _smoothRange(List<Offset> p, int from, int to) {
    final path = Path();
    if (p.isEmpty || from > to) return path;
    final m = _monoTangents(p);
    path.moveTo(p[from].dx, p[from].dy);
    for (var k = from; k < to; k++) {
      final a = p[k], b = p[k + 1];
      final hx = (b.dx - a.dx) / 3;
      path.cubicTo(
        a.dx + hx,
        a.dy + m[k] * hx,
        b.dx - hx,
        b.dy - m[k + 1] * hx,
        b.dx,
        b.dy,
      );
    }
    return path;
  }

  static List<double> _monoTangents(List<Offset> p) {
    final n = p.length;
    final m = List<double>.filled(n, 0);
    if (n < 2) return m;
    final d = List<double>.generate(n - 1, (k) {
      final dx = p[k + 1].dx - p[k].dx;
      return dx.abs() < 1e-9 ? 0.0 : (p[k + 1].dy - p[k].dy) / dx;
    });
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var k = 1; k < n - 1; k++) {
      final d0 = d[k - 1], d1 = d[k];
      if (d0 == 0 || d1 == 0 || (d0 > 0) != (d1 > 0)) {
        m[k] = 0;
        continue;
      }
      final h0 = p[k].dx - p[k - 1].dx, h1 = p[k + 1].dx - p[k].dx;
      final w1 = 2 * h1 + h0, w2 = h1 + 2 * h0;
      m[k] = (w1 + w2) / (w1 / d0 + w2 / d1);
    }
    return m;
  }

  static Path _dashPath(Path src, List<double> dash) {
    final out = Path();
    final on = dash.isNotEmpty ? dash[0] : 4.0;
    final off = dash.length > 1 ? dash[1] : on;
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
        d += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_HeroTrendPainter old) => true;
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, this.dash, this.width = 2});

  final Color color;
  final List<double>? dash;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    final y = size.height / 2;
    if (dash == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    final on = dash!.isNotEmpty ? dash![0] : 3.0;
    final off = dash!.length > 1 ? dash![1] : on;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + on, size.width), y), p);
      x += on + off;
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.width != width || old.dash != dash;
}

/// 卡头右边的「走势 | 构成」小切换。
class LighthouseHeroSegment extends StatelessWidget {
  const LighthouseHeroSegment({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Color c(Color x, [DunesColorRole r = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, x, role: r);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c(const Color(0xFFEEE8FB), DunesColorRole.surface),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index
                      ? c(const Color(0xFFFFFFFF), DunesColorRole.surface)
                      : const Color(0x00FFFFFF),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: i == index
                      ? const [
                          BoxShadow(
                            color: Color(0x264A3A7A),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  style: LhTypography.sans(
                    size: 10.5,
                    color: c(i == index ? _kInk : const Color(0xFF7A7590)),
                    weight: FontWeight.w700,
                    height: 1.0,
                    context: context,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡头右边的「迷你 K 线」：点它进全屏大图。四根小蜡烛，紫 / 淡紫相间。
class LighthouseHeroCandleGlyph extends StatelessWidget {
  const LighthouseHeroCandleGlyph({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Color c(int v) => DunesColors.resolve(context, Color(v));
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: CustomPaint(
        size: const Size(26, 14),
        painter: _CandleGlyphPainter(
          wick: c(0xFFB5AAD5),
          up: c(0xFF7B5CD8),
          down: c(0xFFC9BEEE),
        ),
      ),
    );
  }
}

class _CandleGlyphPainter extends CustomPainter {
  const _CandleGlyphPainter({
    required this.wick,
    required this.up,
    required this.down,
  });

  final Color wick, up, down;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 26, sy = size.height / 14;
    final w = Paint()
      ..color = wick
      ..strokeWidth = 1;
    const wicks = [
      [3.0, 1.0, 12.0],
      [9.0, 3.0, 13.0],
      [15.0, 2.0, 10.0],
      [21.0, 4.0, 12.0],
    ];
    for (final k in wicks) {
      canvas.drawLine(Offset(k[0] * sx, k[1] * sy), Offset(k[0] * sx, k[2] * sy), w);
    }
    const bodies = [
      [1.5, 3.0, 6.0, 1.0],
      [7.5, 6.0, 5.0, 0.0],
      [13.5, 4.0, 4.0, 1.0],
      [19.5, 6.0, 4.0, 0.0],
    ];
    for (final b in bodies) {
      canvas.drawRect(
        Rect.fromLTWH(b[0] * sx, b[1] * sy, 3 * sx, b[2] * sy),
        Paint()..color = b[3] > 0 ? up : down,
      );
    }
  }

  @override
  bool shouldRepaint(_CandleGlyphPainter old) =>
      old.wick != wick || old.up != up || old.down != down;
}
