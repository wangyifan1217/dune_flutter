import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
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
  });

  final String key;
  final String name;
  final Color color;
  final List<double?> values;
  final String Function(double v) format;

  /// null = 实线；否则 [实, 虚] 像素。
  final List<double>? dash;
}

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
    this.selectedIndex,
    this.onSelectedIndexChanged,
    this.trailing,
    this.lastIsPartial = false,
    this.body,
    this.emptyText = '暂无走势',
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

  /// 选中的点（labels 的绝对下标）。传了 [onSelectedIndexChanged] 时受控。
  final int? selectedIndex;
  final ValueChanged<int?>? onSelectedIndexChanged;
  final Widget? trailing;

  /// 最后一点是「进行中」的本期（今天）。
  final bool lastIsPartial;

  /// 非空时替换图例 + 图（资金「构成」）。
  final Widget? body;
  final String emptyText;

  @override
  State<LighthouseHeroTrendCard> createState() =>
      _LighthouseHeroTrendCardState();
}

class _LighthouseHeroTrendCardState extends State<LighthouseHeroTrendCard> {
  Set<String> _vis = <String>{};
  String? _focus;
  int? _localSel;
  String _lineSig = '';

  @override
  void initState() {
    super.initState();
    _resetVisibility();
  }

  @override
  void didUpdateWidget(LighthouseHeroTrendCard old) {
    super.didUpdateWidget(old);
    final sig = widget.lines.map((l) => l.key).join('|');
    if (sig != _lineSig) {
      _resetVisibility();
      return;
    }
    final f = widget.focusKey;
    if (f != null && f != old.focusKey && _hasLine(f)) {
      _vis = {..._vis, f};
      _focus = f;
    }
  }

  bool _hasLine(String key) => widget.lines.any((l) => l.key == key);

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
  }

  // ── 窗口 ──────────────────────────────────────────────────────────────────
  int get _n => math.max(0, math.min(widget.visibleCount, widget.labels.length));
  int get _start => widget.labels.length - _n;

  List<double?> _window(List<double?> v) {
    final out = List<double?>.filled(_n, null);
    for (var j = 0; j < _n; j++) {
      final i = _start + j;
      if (i >= 0 && i < v.length) {
        final x = v[i];
        out[j] = (x != null && x.isFinite) ? x : null;
      }
    }
    return out;
  }

  bool _hasData(List<double?> w) => w.any((v) => v != null);

  int? get _sel {
    final s = widget.onSelectedIndexChanged != null
        ? widget.selectedIndex
        : _localSel;
    if (s == null || s < _start || s >= widget.labels.length) return null;
    return s;
  }

  void _select(int? i) {
    if (widget.onSelectedIndexChanged != null) {
      widget.onSelectedIndexChanged!(i);
    } else {
      setState(() => _localSel = i);
    }
  }

  void _tapColumn(double dx, double w) {
    final n = _n;
    if (n <= 0) return;
    final j = n == 1
        ? 0
        : (((dx / w) - 0.05) / 0.90 * (n - 1)).round().clamp(0, n - 1).toInt();
    final i = _start + j;
    _select(_sel == i ? null : i);
  }

  void _scrubColumn(double dx, double w) {
    final n = _n;
    if (n <= 0) return;
    final j = n == 1
        ? 0
        : (((dx / w) - 0.05) / 0.90 * (n - 1)).round().clamp(0, n - 1).toInt();
    final i = _start + j;
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
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Text(
            widget.title,
            maxLines: 1,
            style: _sans(11.5, FontWeight.w700, _kInk),
          ),
          const Spacer(),
          if (widget.trailing != null) widget.trailing!,
        ],
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

  Widget _chips(List<LhHeroLine> available, bool hasBars) {
    final off = _c(const Color(0xFFD8D3E3));
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final l in available)
          _chip(
            name: l.name,
            on: _vis.contains(l.key),
            focus: _focus == l.key,
            swatch: _lineSwatch(
              _vis.contains(l.key) ? _c(l.color) : off,
              l.dash,
              _focus == l.key ? 2.5 : 2,
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
      ],
    );
  }

  // ── 图 ────────────────────────────────────────────────────────────────────
  Widget _chartBody() {
    final windows = <String, List<double?>>{
      for (final l in widget.lines) l.key: _window(l.values),
    };
    final available = widget.lines
        .where((l) => _hasData(windows[l.key]!))
        .toList();
    final barsWin = widget.bars == null ? null : _window(widget.bars!.values);
    final hasBars = barsWin != null && _hasData(barsWin);
    final showBars = hasBars && widget.barsVisible;
    if (available.isEmpty && !hasBars) {
      return Center(
        child: Text(widget.emptyText, style: _sans(10, FontWeight.w500, _kMute2)),
      );
    }
    final drawn = available.where((l) => _vis.contains(l.key)).toList();
    final focus = drawn.any((l) => l.key == _focus)
        ? _focus
        : (drawn.isEmpty ? null : drawn.first.key);
    // 没点任何一天时，默认标出最后一列（今天）：列高光 + 每根线一个圆点，
    // 但不出读数卡 —— 和原型一致，图不会光秃秃的。
    final sel = _sel;
    final markJ = sel != null ? sel - _start : (_n > 0 ? _n - 1 : null);
    final selJ = sel == null ? null : sel - _start;

    final paintLines = <_PaintLine>[
      for (final l in drawn)
        _PaintLine(
          values: windows[l.key]!,
          color: l.key == focus ? _c(_kFocus) : _c(l.color),
          dash: l.dash,
          focus: l.key == focus,
        ),
    ];
    // 主线最后画，压在最上面。
    paintLines.sort((a, b) => (a.focus ? 1 : 0) - (b.focus ? 1 : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chips(available, hasBars),
        const SizedBox(height: 7),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final tipOnLeft =
                  selJ != null &&
                  _n > 1 &&
                  (0.05 + 0.9 * selJ / (_n - 1)) > 0.55;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tapColumn(d.localPosition.dx, w),
                onLongPressStart: (d) => _scrubColumn(d.localPosition.dx, w),
                onLongPressMoveUpdate: (d) =>
                    _scrubColumn(d.localPosition.dx, w),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _HeroTrendPainter(
                          n: _n,
                          lines: paintLines,
                          bars: showBars ? barsWin : null,
                          selJ: markJ,
                          grid: _c(_kGrid, DunesColorRole.border),
                          base: _c(const Color(0xFFDCD2F5), DunesColorRole.border),
                          plum: _c(_kPlum),
                          barPos: _c(_kBarPos),
                          barNeg: _c(_kBarNeg),
                          barPosSel: _c(_kBarPosSel),
                          barNegSel: _c(_kBarNegSel),
                          dotFill: _c(const Color(0xFFFFFFFF), DunesColorRole.surface),
                        ),
                      ),
                    ),
                    if (sel != null)
                      Positioned(
                        top: 0,
                        left: tipOnLeft ? 2 : null,
                        right: tipOnLeft ? null : 2,
                        child: IgnorePointer(
                          child: _tooltip(
                            sel,
                            drawn,
                            focus,
                            showBars ? barsWin![selJ!] : null,
                            showBars,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 12,
          child: _xLabels(markJ == null ? null : _start + markJ),
        ),
      ],
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
                  l.key == focus ? _c(_kFocus) : _c(l.color),
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
    String short(String s) {
      final m = RegExp(r'^\d{1,2}\.(\d{1,2})$').firstMatch(s.trim());
      return m == null ? s : '.${m.group(1)}';
    }

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var j = 0; j < n; j++)
              if ((n - 1 - j) % step == 0 || _start + j == sel)
                Positioned(
                  left: (n == 1 ? 0.5 : 0.05 + 0.9 * j / (n - 1)) * w - 20,
                  width: 40,
                  top: 0,
                  child: Text(
                    short(widget.labels[_start + j]),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: _mono(
                      9,
                      _start + j == sel ? FontWeight.w700 : FontWeight.w400,
                      _start + j == sel ? _kDeep : const Color(0xFF7A7590),
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
  });

  final List<double?> values;
  final Color color;
  final List<double>? dash;
  final bool focus;
}

class _HeroTrendPainter extends CustomPainter {
  _HeroTrendPainter({
    required this.n,
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
  });

  final int n;
  final List<_PaintLine> lines;
  final List<double?>? bars;
  final int? selJ;
  final Color grid, base, plum, barPos, barNeg, barPosSel, barNegSel, dotFill;

  double _x(int j, double w) => n <= 1 ? w / 2 : w * (0.05 + 0.90 * j / (n - 1));

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (n <= 0 || w <= 0 || h <= 0) return;
    final hasBars = bars != null;
    final lineTop = h * (hasBars ? 0.10 : 0.12);
    final lineBot = h * (hasBars ? 0.58 : 0.88);
    final baseY = h * 0.80;

    // 虚线网格
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in const [0.10, 0.46]) {
      _dashedLine(canvas, Offset(0, h * f), Offset(w, h * f), gridPaint, 3, 3);
    }
    if (hasBars) {
      canvas.drawLine(
        Offset(0, baseY),
        Offset(w, baseY),
        Paint()
          ..color = base
          ..strokeWidth = 1,
      );
    }

    // 选中列的淡紫高光
    final colW = n <= 1 ? w * 0.3 : w * 0.90 / (n - 1);
    if (selJ != null) {
      final cx = _x(selJ!, w);
      final r = Rect.fromLTWH(cx - colW / 2, 0, colW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()
          ..shader = ui.Gradient.linear(
            r.topCenter,
            r.bottomCenter,
            [plum.withAlpha(0), plum.withAlpha(26)],
          ),
      );
    }

    // 柱：正向上、负向下，贴着基线
    if (hasBars) {
      final vs = bars!.whereType<double>().map((v) => v.abs());
      final mx = vs.isEmpty ? 0.0 : vs.reduce(math.max);
      if (mx > 0) {
        final bw = n > 7 ? 7.0 : 9.0;
        for (var j = 0; j < n && j < bars!.length; j++) {
          final v = bars![j];
          if (v == null) continue;
          final bh = v.abs() / mx * h * 0.17;
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
    for (final l in lines) {
      final pts = <({int j, double v})>[
        for (var j = 0; j < n && j < l.values.length; j++)
          if (l.values[j] != null) (j: j, v: l.values[j]!),
      ];
      if (pts.isEmpty) continue;
      var lo = pts.first.v, hi = pts.first.v;
      for (final p in pts) {
        lo = math.min(lo, p.v);
        hi = math.max(hi, p.v);
      }
      final span = (hi - lo).abs() < 1e-12 ? 1.0 : hi - lo;
      double y(double v) => (hi - lo).abs() < 1e-12
          ? (lineTop + lineBot) / 2
          : lineTop + (1 - (v - lo) / span) * (lineBot - lineTop);
      final offs = [for (final p in pts) Offset(_x(p.j, w), y(p.v))];
      final path = _smooth(offs);

      if (l.focus && offs.length >= 2) {
        final area = Path.from(path)
          ..lineTo(offs.last.dx, hasBars ? lineBot : h)
          ..lineTo(offs.first.dx, hasBars ? lineBot : h)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, lineTop),
              Offset(0, hasBars ? lineBot : h),
              [plum.withAlpha(66), plum.withAlpha(0)],
            ),
        );
        // 光晕：同一条路径先画一道模糊的影子
        canvas.drawPath(
          path.shift(const Offset(0, 1.5)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = l.color.withAlpha(110)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
        );
      }
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = l.focus ? 2.4 : 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = l.focus ? l.color : l.color.withAlpha(230);
      if (offs.length == 1) {
        canvas.drawCircle(offs.first, l.focus ? 2.4 : 1.6, Paint()..color = l.color);
      } else if (l.dash == null) {
        canvas.drawPath(path, stroke);
      } else {
        canvas.drawPath(_dashPath(path, l.dash!), stroke);
      }
      if (selJ != null) {
        for (var k = 0; k < pts.length; k++) {
          if (pts[k].j == selJ) {
            dots.add((at: offs[k], color: l.color, focus: l.focus));
          }
        }
      }
    }

    // 选中点：主线大圈 + 外圈光环，其它小圈
    for (final d in dots) {
      final r = d.focus ? 5.0 : 3.5;
      if (d.focus) {
        canvas.drawCircle(d.at, r + 4, Paint()..color = plum.withAlpha(46));
      }
      canvas.drawCircle(d.at, r, Paint()..color = dotFill);
      canvas.drawCircle(
        d.at,
        r - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = d.color,
      );
    }
  }

  static Path _smooth(List<Offset> p) {
    final path = Path();
    if (p.isEmpty) return path;
    path.moveTo(p.first.dx, p.first.dy);
    for (var k = 0; k < p.length - 1; k++) {
      final p0 = k > 0 ? p[k - 1] : p[k];
      final p1 = p[k];
      final p2 = p[k + 1];
      final p3 = k + 2 < p.length ? p[k + 2] : p[k + 1];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
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

  static void _dashedLine(
    Canvas c,
    Offset a,
    Offset b,
    Paint p,
    double on,
    double off,
  ) {
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    var d = 0.0;
    while (d < len) {
      final e = math.min(d + on, len);
      c.drawLine(a + dir * d, a + dir * e, p);
      d += on + off;
    }
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
