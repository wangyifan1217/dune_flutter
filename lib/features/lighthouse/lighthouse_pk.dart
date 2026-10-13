// 灯塔 · PK 对比
//
// 账本卡片上点「PK」把产品（供给 / 渠道行也行）丢进 PK 篮，像加购物车一样
// 飞进「分类」行右侧的 PK 篮；点 PK 篮从右边滑进「PK 擂台」选 2–4 个和要比的
// 指标，「开始 PK」进结果页逐项对比。整套皮跟 K 线入口一个家族：白卡 +
// 淡紫发丝边 + 紫色柔投影，后面叠一张淡紫卡，右下角四分之一圆角标。
//
// 数据：加入时按当时的时间段给这一行拍一张指标快照；之后在灯塔里再看到这一行
// （换了时间段也算）就悄悄刷新成最新值。PK 篮存在本地，换 tab / 刷新页面不丢。

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_feedback.dart';
import 'lighthouse_theme.dart';

// ── 色板 ───────────────────────────────────────────────────────────────
abstract final class LhPkColors {
  static const deep = Color(0xFF5A458F);
  static const primary = Color(0xFF7B5CD8);
  static const soft = Color(0xFFB5AAD5);
  static const lavender = Color(0xFFF0ECF6);
  static const mist = Color(0xFFF4F2F8);
  static const page = Color(0xFFF5F3F8);
  static const line = Color(0xFFE4DCF4);
  static const edge = Color(0xFFE2D8F0);
  static const backA = Color(0xFFF1ECFB);
  static const backB = Color(0xFFE6DEF6);
  static const backEdge = Color(0xFFDCD0F0);
  static const ink = Color(0xFF2A2633);
  static const ink2 = Color(0xFF4A4558);
  static const mute = Color(0xFF8C8798);
  static const up = Color(0xFFE0362C);
  static const down = Color(0xFF0E9A57);
  static const warnBg = Color(0xFFFFF6E5);
  static const warnEdge = Color(0xFFF3D9A6);
  static const warnInk = Color(0xFF8A5A00);

  /// A 紫 / B 蓝 / C 琥珀 / D 青：跟 K 线大图的趋势紫、NX 蓝黄同一套，
  /// 都避开涨跌的红绿。
  static const slots = <Color>[
    Color(0xFF7B5CD8),
    Color(0xFF3F78E0),
    Color(0xFFE39A1F),
    Color(0xFF1A9BA8),
  ];
  static Color slot(int i) => slots[i.clamp(0, slots.length - 1)];
  static Color tint(Color c, double t) => Color.lerp(c, Colors.white, t)!;
}

const List<String> lhPkSlotLetters = ['A', 'B', 'C', 'D'];
const int lhPkMaxEntries = 4;
String lhPkLetter(int i) => lhPkSlotLetters[i.clamp(0, 3)];

/// PK 功能总开关：暂不上线，关掉后灯塔上不出现「＋PK」小钮和 PK 篮，代码和本地 PK 篮数据都保留。
/// 要上线时改成 true 即可。
const bool kLighthousePkEnabled = false;

// ── 指标 ───────────────────────────────────────────────────────────────
class LhPkMetric {
  const LhPkMetric(
    this.key,
    this.label, {
    this.lowerWins = false,
    this.isRate = false,
  });
  final String key;
  final String label;
  final bool lowerWins;
  final bool isRate;
}

const List<LhPkMetric> lhPkMetrics = [
  LhPkMetric('sales', '销售额'),
  LhPkMetric('verifiedSales', '核销额'),
  LhPkMetric('gmv', 'GMV'),
  LhPkMetric('profit', '利润'),
  LhPkMetric('grossMargin', '毛利率', isRate: true),
  LhPkMetric('revenue', '收入'),
  LhPkMetric('costTotal', '成本合计', lowerWins: true),
  LhPkMetric('prepaid', '经营性净现金流'),
];

String lhPkMoney(double v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e8) return '$sign${(a / 1e8).toStringAsFixed(2)}亿';
  final w = a / 1e4;
  return '$sign${w.toStringAsFixed(w >= 100 ? 1 : 2)}万';
}

String lhPkValue(LhPkMetric m, double v) =>
    m.isRate ? '${v.toStringAsFixed(1)}%' : lhPkMoney(v);

// ── PK 篮里的一项 ───────────────────────────────────────────────────────
class LhPkEntry {
  LhPkEntry({
    required this.key,
    required this.name,
    required this.tab,
    required this.group,
    required this.rangeLabel,
    required this.metrics,
    this.marginFormula = '',
  });

  /// `tab::name::group`，跟账本行的 trendKey 同口径。
  final String key;
  final String name;
  final String tab;
  final String group;

  /// 拍快照时灯塔选的时间段（10.13 / 本月 / 9.1–9.30…）。
  final String rangeLabel;

  /// 卡片上没有的指标是 null（比如核销额卡没有 GMV）。
  final Map<String, double?> metrics;

  /// 毛利率口径（利润÷GMV / 利润÷核销额…）。
  final String marginFormula;

  String get tabLabel => switch (tab) {
    'product' => '产品',
    'supply' => '供给',
    'channel' => '渠道',
    'people' => '人员',
    _ => tab,
  };

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'tab': tab,
    'group': group,
    'range': rangeLabel,
    'margin': marginFormula,
    'metrics': metrics,
  };

  static LhPkEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key']?.toString() ?? '';
    final name = raw['name']?.toString() ?? '';
    if (key.isEmpty || name.isEmpty) return null;
    final m = <String, double?>{};
    final rawMetrics = raw['metrics'];
    if (rawMetrics is Map) {
      rawMetrics.forEach((k, v) {
        m[k.toString()] = v is num ? v.toDouble() : null;
      });
    }
    return LhPkEntry(
      key: key,
      name: name,
      tab: raw['tab']?.toString() ?? '',
      group: raw['group']?.toString() ?? '',
      rangeLabel: raw['range']?.toString() ?? '',
      metrics: m,
      marginFormula: raw['margin']?.toString() ?? '',
    );
  }
}

// ── PK 篮（全局单例，存本地） ───────────────────────────────────────────
class LighthousePkBasket extends ChangeNotifier {
  LighthousePkBasket._();
  static final LighthousePkBasket instance = LighthousePkBasket._();

  static const String _prefsKey = 'lighthouse.pk.basket.v1';
  final List<LhPkEntry> _items = <LhPkEntry>[];
  bool _loaded = false;

  /// 最近一次画出来的 PK 篮按钮（飞入动画的落点）。不用 GlobalKey：
  /// 筛选区可能同时画两份（吸顶副本），GlobalKey 重复会直接崩。
  BuildContext? anchor;

  List<LhPkEntry> get items => List<LhPkEntry>.unmodifiable(_items);
  int get length => _items.length;
  bool get isFull => _items.length >= lhPkMaxEntries;
  int indexOf(String key) => _items.indexWhere((e) => e.key == key);
  bool contains(String key) => indexOf(key) >= 0;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      final restored = <LhPkEntry>[
        for (final x in list)
          if (LhPkEntry.fromJson(x) case final e?) e,
      ];
      // 加载期间用户已经加过的不丢：本地的排在后面补齐。
      for (final e in restored) {
        if (_items.length >= lhPkMaxEntries) break;
        if (!contains(e.key)) _items.add(e);
      }
      notifyListeners();
    } catch (_) {
      // 本地存储坏了就当空篮，不挡页面。
    }
  }

  /// true = 加进来了；false = 本来在，拿出去了；null = 满了没加。
  bool? toggle(LhPkEntry e) {
    final i = indexOf(e.key);
    if (i >= 0) {
      _items.removeAt(i);
      _changed();
      return false;
    }
    if (isFull) return null;
    _items.add(e);
    _changed();
    return true;
  }

  void remove(String key) {
    final i = indexOf(key);
    if (i < 0) return;
    _items.removeAt(i);
    _changed();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _changed();
  }

  /// 账本里又看到这一行：悄悄换成最新快照（build 里调用，不发通知）。
  void refresh(LhPkEntry e) {
    final i = indexOf(e.key);
    if (i < 0) return;
    final old = _items[i];
    if (old.rangeLabel == e.rangeLabel &&
        old.marginFormula == e.marginFormula &&
        mapEquals(old.metrics, e.metrics)) {
      return;
    }
    _items[i] = e;
    _save();
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  void _save() {
    final String data;
    try {
      data = jsonEncode(_items.map((e) => e.toJson()).toList());
    } catch (_) {
      return;
    }
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, data);
      } catch (_) {}
    }());
  }
}

// ── 皮：白卡 + 叠卡 + 角标 ─────────────────────────────────────────────
BoxDecoration lhPkCardDeco(
  BuildContext ctx, {
  double radius = 12,
  Color? edge,
  double edgeWidth = 0.8,
  bool raised = true,
  Color? glow,
}) {
  final g = glow ?? LhPkColors.deep;
  return BoxDecoration(
    color: DunesColors.resolve(ctx, Colors.white, role: DunesColorRole.surface),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: DunesColors.resolve(
        ctx,
        edge ?? LhPkColors.line,
        role: DunesColorRole.border,
      ),
      width: edgeWidth,
    ),
    boxShadow: raised
        ? [
            BoxShadow(
              color: g.withAlpha(26),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ]
        : null,
  );
}

/// 右下角四分之一圆角标。放在 Stack 里贴卡片右下角，卡片自己 clip 圆角。
class LhPkCorner extends StatelessWidget {
  const LhPkCorner({super.key, this.size = 10, this.color = LhPkColors.primary});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(size)),
      ),
    ),
  );
}

/// 后面叠一张淡紫卡。
class LhPkStack extends StatelessWidget {
  const LhPkStack({
    super.key,
    required this.child,
    this.radius = 8,
    this.dx = 3,
    this.dy = -3,
    this.angle = 0.06,
  });
  final Widget child;
  final double radius;
  final double dx;
  final double dy;
  final double angle;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: Transform(
            alignment: Alignment.bottomLeft,
            transform: Matrix4.translationValues(dx, dy, 0)..rotateZ(angle),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [LhPkColors.backA, LhPkColors.backB],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: LhPkColors.backEdge, width: 0.7),
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// 字母片 A / B / C / D。
class LhPkSlotBadge extends StatelessWidget {
  const LhPkSlotBadge({
    super.key,
    required this.index,
    this.size = 22,
    this.radius,
    this.ring,
  });
  final int index;
  final double size;
  final double? radius;
  final Color? ring;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: LhPkColors.slot(index),
      borderRadius: BorderRadius.circular(radius ?? size / 2),
      border: ring == null ? null : Border.all(color: ring!, width: 1.4),
    ),
    child: Text(
      lhPkLetter(index),
      style: LhTypography.mono(
        context: context,
        size: size * 0.5,
        color: Colors.white,
        weight: FontWeight.w800,
        height: 1.0,
      ),
    ),
  );
}

// ── 账本卡片上的「PK」小钮 ──────────────────────────────────────────────
class LhPkAddButton extends StatelessWidget {
  const LhPkAddButton({super.key, required this.entryKey, required this.onTap});
  final String entryKey;
  final void Function(BuildContext buttonContext) onTap;

  @override
  Widget build(BuildContext context) {
    final basket = LighthousePkBasket.instance;
    return AnimatedBuilder(
      animation: basket,
      builder: (ctx, _) {
        final i = basket.indexOf(entryKey);
        final added = i >= 0;
        final c = added ? LhPkColors.slot(i) : LhPkColors.deep;
        return Semantics(
          button: true,
          label: added ? '已加入 PK（${lhPkLetter(i)}），点一下移出' : '加入 PK 对比',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(ctx),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 18,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: added
                      ? c
                      : DunesColors.resolve(
                          ctx,
                          Colors.white,
                          role: DunesColorRole.surface,
                        ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: added ? c : LhPkColors.edge,
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.withAlpha(added ? 60 : 34),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 7, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            added ? Icons.check_rounded : Icons.add_rounded,
                            size: 10,
                            color: added ? Colors.white : LhPkColors.deep,
                          ),
                          const SizedBox(width: 1),
                          Text(
                            added ? 'PK·${lhPkLetter(i)}' : 'PK',
                            style: LhTypography.mono(
                              context: ctx,
                              size: 9.5,
                              color: added ? Colors.white : LhPkColors.deep,
                              weight: FontWeight.w800,
                              letterSpacing: -0.2,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: LhPkCorner(
                        size: 6,
                        color: added
                            ? LhPkColors.tint(c, 0.4)
                            : LhPkColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── 「分类」行右侧的 PK 篮 ──────────────────────────────────────────────
class LhPkBasketButton extends StatelessWidget {
  const LhPkBasketButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final basket = LighthousePkBasket.instance;
    basket.anchor = context;
    return AnimatedBuilder(
      animation: basket,
      builder: (ctx, _) {
        final n = basket.length;
        final dots = math.min(n, lhPkMaxEntries);
        return Semantics(
          button: true,
          label: n == 0 ? '打开 PK 擂台' : '打开 PK 擂台，已加入 $n 个',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  LhPkStack(
                    radius: 8,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.fromLTRB(7, 0, 10, 0),
                      clipBehavior: Clip.antiAlias,
                      decoration: lhPkCardDeco(
                        ctx,
                        radius: 8,
                        edge: LhPkColors.edge,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'PK',
                                style: LhTypography.mono(
                                  context: ctx,
                                  size: 12.5,
                                  color: n == 0
                                      ? LhPkColors.soft
                                      : LhPkColors.deep,
                                  weight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  height: 1.0,
                                ),
                              ),
                              if (dots > 0) ...[
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 12.0 + (dots - 1) * 7.0,
                                  height: 12,
                                  child: Stack(
                                    children: [
                                      for (var i = 0; i < dots; i++)
                                        Positioned(
                                          left: i * 7.0,
                                          top: 0,
                                          child: LhPkSlotBadge(
                                            index: i,
                                            size: 12,
                                            ring: Colors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const Positioned(
                            right: -10,
                            bottom: 0,
                            child: LhPkCorner(size: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (n > 0)
                    Positioned(
                      right: -7,
                      top: -7,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 15),
                        height: 15,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: LhPkColors.up,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          '$n',
                          style: LhTypography.mono(
                            context: ctx,
                            size: 8.5,
                            color: Colors.white,
                            weight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
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

// ── 加入时的「飞进 PK 篮」 ───────────────────────────────────────────────
/// 一个 widget 在屏幕上的矩形（带上页面缩放）。
Rect? lhPkGlobalRect(BuildContext? ctx) {
  if (ctx == null || !ctx.mounted) return null;
  final ro = ctx.findRenderObject();
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
  return MatrixUtils.transformRect(
    ro.getTransformTo(null),
    Offset.zero & ro.size,
  );
}

void lhPkFly(
  BuildContext context, {
  required Rect from,
  required Rect to,
  required int slot,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  var removed = false;
  entry = OverlayEntry(
    builder: (_) => _LhPkFlyer(
      from: from,
      to: to,
      slot: slot,
      onDone: () {
        if (removed) return;
        removed = true;
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _LhPkFlyer extends StatefulWidget {
  const _LhPkFlyer({
    required this.from,
    required this.to,
    required this.slot,
    required this.onDone,
  });
  final Rect from;
  final Rect to;
  final int slot;
  final VoidCallback onDone;

  @override
  State<_LhPkFlyer> createState() => _LhPkFlyerState();
}

class _LhPkFlyerState extends State<_LhPkFlyer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p0 = widget.from.center;
    final p2 = widget.to.center;
    final p1 = Offset((p0.dx + p2.dx) / 2 - 60, math.min(p0.dy, p2.dy) - 90);
    final color = LhPkColors.slot(widget.slot);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (ctx, _) {
            final t = Curves.easeInOutCubic.transform(_c.value);
            final u = 1 - t;
            final p = p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
            final scale = 1.0 - 0.45 * t;
            final fade = t > 0.86 ? ((1 - t) / 0.14).clamp(0.0, 1.0) : 1.0;
            return Stack(
              children: [
                Positioned(
                  left: p.dx - 22,
                  top: p.dy - 12,
                  child: Opacity(
                    opacity: fade,
                    child: Transform.rotate(
                      angle: -0.3 * math.sin(t * math.pi),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 44,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: LhPkColors.edge,
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withAlpha(80),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LhPkSlotBadge(index: widget.slot, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                'PK',
                                style: LhTypography.mono(
                                  context: ctx,
                                  size: 10,
                                  color: color,
                                  weight: FontWeight.w800,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── 底部提示条 ───────────────────────────────────────────────────────────
OverlayEntry? _lhPkToastEntry;
VoidCallback? _lhPkToastClose;

void lhPkToast(
  BuildContext context, {
  required String text,
  String? action,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _lhPkToastClose?.call();
  late OverlayEntry entry;
  var removed = false;
  void close() {
    if (removed) return;
    removed = true;
    entry.remove();
    if (identical(_lhPkToastEntry, entry)) {
      _lhPkToastEntry = null;
      _lhPkToastClose = null;
    }
  }

  entry = OverlayEntry(
    builder: (_) => _LhPkToast(
      text: text,
      action: action,
      onAction: onAction == null
          ? null
          : () {
              close();
              onAction();
            },
      onDone: close,
    ),
  );
  _lhPkToastEntry = entry;
  _lhPkToastClose = close;
  overlay.insert(entry);
}

class _LhPkToast extends StatefulWidget {
  const _LhPkToast({
    required this.text,
    required this.onDone,
    this.action,
    this.onAction,
  });
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback onDone;

  @override
  State<_LhPkToast> createState() => _LhPkToastState();
}

class _LhPkToastState extends State<_LhPkToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      _c.reverse().whenComplete(widget.onDone);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = math.min(420.0, mq.size.width - 32);
    return Positioned(
      left: (mq.size.width - w) / 2,
      width: w,
      bottom: mq.padding.bottom + 96,
      child: FadeTransition(
        opacity: _c,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF2E2547),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E1830).withAlpha(70),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LhTypography.sans(
                        context: context,
                        size: 12.5,
                        color: Colors.white,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.action != null && widget.onAction != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onAction,
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.action!,
                          style: LhTypography.sans(
                            context: context,
                            size: 12,
                            color: LhPkColors.deep,
                            weight: FontWeight.w700,
                          ),
                        ),
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
}

// ── 页面：缩放 + 路由 ───────────────────────────────────────────────────
/// 跟灯塔右上角「− 80% +」一起缩（PK 页挂在根路由上，不在页面缩放层里）。
class LhPkZoom extends StatelessWidget {
  const LhPkZoom({super.key, required this.zoom, required this.child});
  final double zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (ctx, box) {
      final z = zoom.clamp(0.5, 2.0).toDouble();
      if ((z - 1.0).abs() < 0.001) return child;
      final w = box.maxWidth;
      final h = box.maxHeight;
      return ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: w / z,
            maxWidth: w / z,
            minHeight: h / z,
            maxHeight: h / z,
            child: Transform.scale(
              scale: z,
              alignment: Alignment.topLeft,
              child: SizedBox(width: w / z, height: h / z, child: child),
            ),
          ),
        ),
      );
    },
  );
}

const String _kPkRoutePrefix = 'lighthouse-pk';

Route<T> _lhPkRoute<T>(String name, Widget page) => PageRouteBuilder<T>(
  settings: RouteSettings(name: '$_kPkRoutePrefix/$name'),
  transitionDuration: const Duration(milliseconds: 340),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (ctx, a, b) => page,
  transitionsBuilder: (ctx, a, b, child) {
    final curved = CurvedAnimation(
      parent: a,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  },
);

/// 从灯塔打开 PK 擂台（右边滑进来）。
Future<void> openLighthousePk(BuildContext context, {double uiZoom = 1.0}) {
  LighthouseFeedback.instance.play(LighthouseFeedbackKind.navigate);
  return Navigator.of(context, rootNavigator: true).push<void>(
    _lhPkRoute<void>('picker', LhPkPickerPage(uiZoom: uiZoom)),
  );
}

void _lhPkExitToLighthouse(BuildContext context) {
  LighthouseFeedback.instance.play(LighthouseFeedbackKind.collapse);
  Navigator.of(context).popUntil(
    (r) => !(r.settings.name?.startsWith(_kPkRoutePrefix) ?? false),
  );
}

// ── 小部件 ───────────────────────────────────────────────────────────────
class _PkTopBar extends StatelessWidget {
  const _PkTopBar({
    required this.backLabel,
    required this.onBack,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String backLabel;
  final VoidCallback onBack;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _PkChipButton(
              onTap: onBack,
              semantics: '返回$backLabel',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: LhPkColors.deep,
                  ),
                  Text(
                    backLabel,
                    style: LhTypography.sans(
                      context: context,
                      size: 12,
                      color: LhPkColors.deep,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: LhTypography.sans(
                  context: context,
                  size: 16,
                  color: LhPkColors.ink,
                  weight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LhTypography.sans(
                  context: context,
                  size: 10,
                  color: LhPkColors.mute,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 72,
          child: Align(
            alignment: Alignment.centerRight,
            child: trailing ?? const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );
}

class _PkChipButton extends StatelessWidget {
  const _PkChipButton({
    required this.onTap,
    required this.child,
    required this.semantics,
  });
  final VoidCallback onTap;
  final Widget child;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: lhPkCardDeco(context, radius: 10),
        child: child,
      ),
    ),
  );
}

class _PkSectionTitle extends StatelessWidget {
  const _PkSectionTitle(this.title, {this.hint});
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: LhTypography.sans(
            context: context,
            size: 13,
            color: LhPkColors.ink,
            weight: FontWeight.w700,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LhTypography.sans(
                context: context,
                size: 10.5,
                color: LhPkColors.mute,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _pkPrimaryButton(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
  IconData? icon,
}) {
  final enabled = onTap != null;
  return Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: enabled ? LhPkColors.deep : LhPkColors.soft,
          borderRadius: BorderRadius.circular(13),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: LhPkColors.deep.withAlpha(80),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: LhTypography.sans(
                context: context,
                size: 14.5,
                color: Colors.white,
                weight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: Colors.white),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _pkSecondaryButton(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
}) => Semantics(
  button: true,
  label: label,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          LhPkColors.mist,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LhPkColors.line, width: 1),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: LhTypography.sans(
          context: context,
          size: 13,
          color: LhPkColors.deep,
          weight: FontWeight.w700,
        ),
      ),
    ),
  ),
);

Widget _pkPageShell(
  BuildContext context, {
  required double uiZoom,
  required Widget body,
  required Widget bottomBar,
}) {
  return Scaffold(
    backgroundColor: DunesColors.resolve(
      context,
      LhPkColors.page,
      role: DunesColorRole.surface,
    ),
    body: LhPkZoom(
      zoom: uiZoom,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: body,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ),
                border: const Border(
                  top: BorderSide(color: Color(0xFFECE7F4), width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: LhPkColors.deep.withAlpha(14),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: bottomBar,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _pkWarn(BuildContext context, String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
  decoration: BoxDecoration(
    color: LhPkColors.warnBg,
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: LhPkColors.warnEdge, width: 0.8),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(
          Icons.info_outline_rounded,
          size: 12,
          color: Color(0xFFB9770E),
        ),
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          style: LhTypography.sans(
            context: context,
            size: 10.5,
            color: LhPkColors.warnInk,
            height: 1.35,
          ),
        ),
      ),
    ],
  ),
);

// ── ② PK 擂台：选产品 + 选指标 ──────────────────────────────────────────
class LhPkPickerPage extends StatefulWidget {
  const LhPkPickerPage({super.key, this.uiZoom = 1.0});
  final double uiZoom;

  @override
  State<LhPkPickerPage> createState() => _LhPkPickerPageState();
}

class _LhPkPickerPageState extends State<LhPkPickerPage> {
  final LighthousePkBasket _basket = LighthousePkBasket.instance;
  final Set<String> _unpicked = <String>{};
  final Set<String> _metricsOff = <String>{};

  @override
  void initState() {
    super.initState();
    _basket.addListener(_onBasket);
    unawaited(_basket.load());
  }

  @override
  void dispose() {
    _basket.removeListener(_onBasket);
    super.dispose();
  }

  void _onBasket() {
    if (!mounted) return;
    setState(() {
      final keys = _basket.items.map((e) => e.key).toSet();
      _unpicked.removeWhere((k) => !keys.contains(k));
    });
  }

  List<LhPkEntry> get _picked =>
      _basket.items.where((e) => !_unpicked.contains(e.key)).toList();

  /// 选中的几个都有这个指标才能比。
  List<LhPkMetric> _comparable(List<LhPkEntry> picked) => [
    for (final m in lhPkMetrics)
      if (picked.length >= 2 &&
          picked.every((e) => e.metrics[m.key] != null))
        m,
  ];

  /// 只有一部分有：灰着放出来，写「仅 A」。
  List<(LhPkMetric, String)> _partial(List<LhPkEntry> picked) {
    final out = <(LhPkMetric, String)>[];
    if (picked.length < 2) return out;
    for (final m in lhPkMetrics) {
      final has = <String>[
        for (final e in picked)
          if (e.metrics[m.key] != null) lhPkLetter(_basket.indexOf(e.key)),
      ];
      if (has.isNotEmpty && has.length < picked.length) {
        out.add((m, has.join('、')));
      }
    }
    return out;
  }

  void _start() {
    final picked = _picked;
    final metrics = _comparable(
      picked,
    ).where((m) => !_metricsOff.contains(m.key)).toList();
    if (picked.length < 2 || metrics.isEmpty) return;
    LighthouseFeedback.instance.play(LighthouseFeedbackKind.navigate);
    unawaited(
      Navigator.of(context).push<void>(
        _lhPkRoute<void>(
          'arena',
          LhPkArenaPage(
            entries: picked,
            slots: [for (final e in picked) _basket.indexOf(e.key)],
            metrics: metrics,
            uiZoom: widget.uiZoom,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _basket.items;
    final picked = _picked;
    final comparable = _comparable(picked);
    final partial = _partial(picked);
    final on = comparable.where((m) => !_metricsOff.contains(m.key)).toList();
    final ranges = picked.map((e) => e.rangeLabel).toSet();
    final canStart = picked.length >= 2 && on.isNotEmpty;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        _PkTopBar(
          backLabel: '灯塔',
          onBack: () => _lhPkExitToLighthouse(context),
          title: 'PK 擂台',
          subtitle: '选 2–4 个，同一口径逐项比',
          trailing: items.isEmpty
              ? null
              : Semantics(
                  button: true,
                  label: '清空 PK 篮',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      LighthouseFeedback.instance.play(
                        LighthouseFeedbackKind.collapse,
                      );
                      _basket.clear();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '清空',
                        style: LhTypography.sans(
                          context: context,
                          size: 12,
                          color: LhPkColors.mute,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 10),
        _PkSectionTitle(
          'PK 篮',
          hint: '${items.length} / $lhPkMaxEntries · 点卡片选或不选',
        ),
        if (items.isEmpty) _emptyBasket(context),
        for (var i = 0; i < items.length; i++) ...[
          _entryCard(context, items[i], i, !_unpicked.contains(items[i].key)),
          const SizedBox(height: 8),
        ],
        if (items.isNotEmpty && items.length < lhPkMaxEntries)
          _addMore(context, items.length),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: lhPkCardDeco(context, radius: 14, raised: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PkSectionTitle('比什么', hint: '选中的几个都有的指标才能比'),
              if (comparable.isEmpty)
                Text(
                  picked.length < 2 ? '先选 2 个以上' : '这几个没有共同的指标',
                  style: LhTypography.sans(
                    context: context,
                    size: 11.5,
                    color: LhPkColors.mute,
                  ),
                ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in comparable) _metricChip(context, m),
                  for (final (m, who) in partial)
                    _metricMuted(context, '${m.label} · 仅 $who'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: lhPkCardDeco(context, radius: 14, raised: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PkSectionTitle('看多久'),
              if (ranges.length <= 1)
                Text(
                  ranges.isEmpty
                      ? '跟灯塔当前选的时间段走'
                      : '跟灯塔当前选的时间段走：${ranges.first}',
                  style: LhTypography.sans(
                    context: context,
                    size: 11.5,
                    color: LhPkColors.ink2,
                  ),
                )
              else
                _pkWarn(
                  context,
                  '各自加入时的时间段不一样：'
                  '${[for (final e in picked) '${lhPkLetter(_basket.indexOf(e.key))} ${e.rangeLabel}'].join(' · ')}。'
                  '回灯塔切到同一个时间段，把它们在账本里都划过一遍，就会刷新成同一段。',
                ),
            ],
          ),
        ),
      ],
    );

    final bottom = Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < picked.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'VS',
                          style: LhTypography.mono(
                            context: context,
                            size: 9.5,
                            color: LhPkColors.soft,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Text(
                      lhPkLetter(_basket.indexOf(picked[i].key)),
                      style: LhTypography.mono(
                        context: context,
                        size: 13,
                        color: LhPkColors.slot(_basket.indexOf(picked[i].key)),
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                picked.length < 2
                    ? '至少选 2 个'
                    : '${picked.length} 个 · ${on.length} 项指标',
                style: LhTypography.sans(
                  context: context,
                  size: 10.5,
                  color: LhPkColors.mute,
                ),
              ),
            ],
          ),
        ),
        _pkPrimaryButton(
          context,
          label: '开始 PK',
          icon: Icons.chevron_right_rounded,
          onTap: canStart ? _start : null,
        ),
      ],
    );

    return _pkPageShell(
      context,
      uiZoom: widget.uiZoom,
      body: body,
      bottomBar: bottom,
    );
  }

  Widget _emptyBasket(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    decoration: lhPkCardDeco(context, radius: 14, raised: false),
    child: Column(
      children: [
        Text(
          'PK 篮还是空的',
          style: LhTypography.sans(
            context: context,
            size: 13,
            color: LhPkColors.ink,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '在灯塔账本卡片上点「＋PK」，把想比的产品加进来',
          textAlign: TextAlign.center,
          style: LhTypography.sans(
            context: context,
            size: 11.5,
            color: LhPkColors.mute,
          ),
        ),
        const SizedBox(height: 14),
        _PkChipButton(
          onTap: () => _lhPkExitToLighthouse(context),
          semantics: '回灯塔挑产品',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '回灯塔挑',
              style: LhTypography.sans(
                context: context,
                size: 12,
                color: LhPkColors.deep,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _entryCard(BuildContext context, LhPkEntry e, int slot, bool on) {
    final c = LhPkColors.slot(slot);
    final sales = e.metrics['sales'];
    final profit = e.metrics['profit'];
    return Semantics(
      button: true,
      selected: on,
      label: '${lhPkLetter(slot)} ${e.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
          setState(() {
            if (on) {
              _unpicked.add(e.key);
            } else {
              _unpicked.remove(e.key);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          clipBehavior: Clip.antiAlias,
          decoration: lhPkCardDeco(
            context,
            radius: 14,
            edge: on ? LhPkColors.tint(c, 0.55) : LhPkColors.line,
            edgeWidth: on ? 1.4 : 0.8,
            raised: on,
            glow: c,
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
                child: Row(
                  children: [
                    Opacity(
                      opacity: on ? 1 : 0.35,
                      child: LhPkSlotBadge(index: slot, size: 30, radius: 10),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LhTypography.sans(
                              context: context,
                              size: 13,
                              color: on ? LhPkColors.ink : LhPkColors.mute,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                height: 17,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: LhPkColors.tint(c, 0.88),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  e.group.isEmpty
                                      ? e.tabLabel
                                      : '${e.tabLabel} · ${e.group}',
                                  style: LhTypography.sans(
                                    context: context,
                                    size: 9.5,
                                    color: Color.lerp(c, Colors.black, 0.25)!,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      if (sales != null)
                                        TextSpan(
                                          text: '销售额 ${lhPkMoney(sales)}',
                                        ),
                                      if (sales != null && profit != null)
                                        const TextSpan(text: ' · '),
                                      if (profit != null) ...[
                                        const TextSpan(text: '利润 '),
                                        TextSpan(
                                          text: lhPkMoney(profit),
                                          style: TextStyle(
                                            color: profit >= 0
                                                ? LhPkColors.up
                                                : LhPkColors.down,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LhTypography.mono(
                                    context: context,
                                    size: 10,
                                    color: LhPkColors.mute,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: on ? LhPkColors.deep : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: on ? LhPkColors.deep : LhPkColors.soft,
                          width: 1.4,
                        ),
                      ),
                      child: on
                          ? const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    Semantics(
                      button: true,
                      label: '从 PK 篮移出 ${e.name}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          LighthouseFeedback.instance.play(
                            LighthouseFeedbackKind.collapse,
                          );
                          _basket.remove(e.key);
                        },
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(8, 6, 4, 6),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: LhPkColors.mute,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: LhPkCorner(size: 12, color: on ? c : LhPkColors.line),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addMore(BuildContext context, int nextSlot) {
    final c = LhPkColors.slot(nextSlot);
    return Semantics(
      button: true,
      label: '回灯塔再挑一个',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _lhPkExitToLighthouse(context),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              const Color(0xFFFBFAFD),
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCFC3EA), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: LhPkColors.tint(c, 0.4), width: 1.2),
                ),
                child: Text(
                  lhPkLetter(nextSlot),
                  style: LhTypography.mono(
                    context: context,
                    size: 11,
                    color: LhPkColors.tint(c, 0.2),
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '回灯塔再挑一个 · 产品 / 供给 / 渠道都能加',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(
                    context: context,
                    size: 12,
                    color: LhPkColors.primary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricChip(BuildContext context, LhPkMetric m) {
    final on = !_metricsOff.contains(m.key);
    return Semantics(
      button: true,
      selected: on,
      label: m.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
          setState(() {
            if (on) {
              _metricsOff.add(m.key);
            } else {
              _metricsOff.remove(m.key);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 28,
          clipBehavior: Clip.antiAlias,
          decoration: on
              ? lhPkCardDeco(context, radius: 8, edge: const Color(0xFFD9CCF2))
              : BoxDecoration(
                  color: const Color(0xFFEEEBF3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.transparent, width: 0.8),
                ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    m.label,
                    style: LhTypography.sans(
                      context: context,
                      size: 12,
                      color: on ? LhPkColors.deep : LhPkColors.mute,
                      weight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (on)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: LhPkCorner(size: 8),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricMuted(BuildContext context, String text) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFEEEBF3),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: LhTypography.sans(
        context: context,
        size: 11.5,
        color: LhPkColors.mute,
      ),
    ),
  );
}

// ── ③ PK 结果 ────────────────────────────────────────────────────────────
class _PkOutcome {
  _PkOutcome(this.metric, this.values, this.winners);
  final LhPkMetric metric;
  final List<double> values;

  /// 赢的下标（并列都算）；空 = 全部打平。
  final Set<int> winners;

  bool solo(int i) => winners.length == 1 && winners.contains(i);
}

class LhPkArenaPage extends StatelessWidget {
  const LhPkArenaPage({
    super.key,
    required this.entries,
    required this.slots,
    required this.metrics,
    this.uiZoom = 1.0,
  });

  final List<LhPkEntry> entries;
  final List<int> slots;
  final List<LhPkMetric> metrics;
  final double uiZoom;

  List<_PkOutcome> _outcomes() {
    final out = <_PkOutcome>[];
    for (final m in metrics) {
      final vals = <double>[for (final e in entries) e.metrics[m.key] ?? 0.0];
      final best = m.lowerWins ? vals.reduce(math.min) : vals.reduce(math.max);
      final winners = <int>{
        for (var i = 0; i < vals.length; i++)
          if ((vals[i] - best).abs() < 1e-6) i,
      };
      out.add(
        _PkOutcome(m, vals, winners.length == vals.length ? <int>{} : winners),
      );
    }
    return out;
  }

  String _letter(int i) => lhPkLetter(slots[i]);
  Color _color(int i) => LhPkColors.slot(slots[i]);

  /// 两个比时，每项下面一句人话。
  String _note(_PkOutcome o) {
    if (entries.length != 2) return '';
    if (o.winners.isEmpty) return '打平';
    final w = o.winners.first;
    final l = 1 - w;
    final wv = o.values[w];
    final lv = o.values[l];
    final m = o.metric;
    if (m.isRate) {
      return '${_letter(w)} ${m.lowerWins ? '低' : '高'} '
          '${(wv - lv).abs().toStringAsFixed(1)}pp';
    }
    if (lv.abs() < 1e-6) return '${_letter(l)} 本期为 0';
    if (wv.abs() < 1e-6) return '${_letter(w)} 本期为 0';
    if ((wv < 0) != (lv < 0)) return '${_letter(wv < 0 ? w : l)} 为负';
    final big = math.max(wv.abs(), lv.abs());
    final small = math.min(wv.abs(), lv.abs());
    final bigger = wv.abs() >= lv.abs() ? w : l;
    final smaller = bigger == w ? l : w;
    final ratio = big / small;
    if (ratio >= 1.5) {
      return '${_letter(bigger)} 是 ${_letter(smaller)} 的 '
          '${ratio.toStringAsFixed(1)} 倍';
    }
    final diff = (wv - lv).abs();
    if (diff / big < 0.03) return '只差 ${lhPkMoney(diff)}，几乎打平';
    return '${_letter(bigger)} 多 ${((ratio - 1) * 100).toStringAsFixed(0)}%';
  }

  String _summary(List<_PkOutcome> outs) {
    final parts = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final won = [
        for (final o in outs)
          if (o.solo(i)) o.metric.label,
      ];
      if (won.isNotEmpty) parts.add('${_letter(i)} 赢在 ${won.join('、')}');
    }
    return parts.isEmpty ? '各项都打平' : parts.join('；');
  }

  @override
  Widget build(BuildContext context) {
    final outs = _outcomes();
    final wins = List<int>.filled(entries.length, 0);
    for (final o in outs) {
      if (o.winners.length == 1) wins[o.winners.first]++;
    }
    final top = wins.reduce(math.max);
    final leaders = <int>[
      for (var i = 0; i < wins.length; i++)
        if (wins[i] == top) i,
    ];
    final ranges = entries.map((e) => e.rangeLabel).toSet();
    final groups = entries
        .map((e) => e.group)
        .where((g) => g.isNotEmpty)
        .toSet();
    final subtitle = [
      ranges.length == 1 ? ranges.first : '时间段不一致',
      if (groups.length == 1) '${entries.first.tabLabel} › ${groups.first}',
    ].join(' · ');
    final formulas = <int, String>{
      for (var i = 0; i < entries.length; i++)
        if (entries[i].marginFormula.isNotEmpty) i: entries[i].marginFormula,
    };
    final marginMixed = formulas.values.toSet().length > 1;
    final summary = _summary(outs);

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        _PkTopBar(
          backLabel: '擂台',
          onBack: () {
            LighthouseFeedback.instance.play(LighthouseFeedbackKind.collapse);
            Navigator.of(context).maybePop();
          },
          title: 'PK 结果',
          subtitle: subtitle,
          trailing: Semantics(
            button: true,
            label: '退出，回到灯塔',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _lhPkExitToLighthouse(context),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: lhPkCardDeco(context, radius: 10),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: LhPkColors.deep,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _header(context, wins),
        const SizedBox(height: 12),
        _score(context, wins, leaders, top, summary),
        if (ranges.length > 1) ...[
          const SizedBox(height: 10),
          _pkWarn(
            context,
            '时间段不一致：'
            '${[for (var i = 0; i < entries.length; i++) '${_letter(i)} ${entries[i].rangeLabel}'].join(' · ')}',
          ),
        ],
        const SizedBox(height: 14),
        _PkSectionTitle(
          '逐项对比',
          hint: entries.length == 2 ? '条从中线往两边长，赢的一边实色' : '条越长越大，赢的实色',
        ),
        for (final o in outs) ...[
          _metricRow(
            context,
            o,
            marginWarn: o.metric.key == 'grossMargin' && marginMixed
                ? '口径不同：'
                      '${[for (final f in formulas.entries) '${_letter(f.key)} ${f.value}'].join('，')}'
                : null,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );

    final bottom = Row(
      children: [
        Expanded(
          flex: 3,
          child: _pkSecondaryButton(
            context,
            label: '＋ 加对手',
            onTap: () => _lhPkExitToLighthouse(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _pkSecondaryButton(
            context,
            label: '换指标',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: _pkPrimaryButton(
            context,
            label: '复制结论',
            onTap: () {
              final text = _copyText(outs, wins, summary);
              unawaited(Clipboard.setData(ClipboardData(text: text)));
              LighthouseFeedback.instance.play(LighthouseFeedbackKind.success);
              lhPkToast(context, text: '结论已复制，可以直接贴到群里');
            },
          ),
        ),
      ],
    );

    return _pkPageShell(
      context,
      uiZoom: uiZoom,
      body: body,
      bottomBar: bottom,
    );
  }

  String _copyText(List<_PkOutcome> outs, List<int> wins, String summary) {
    final b = StringBuffer();
    b.writeln(
      '灯塔 PK · ${entries.map((e) => e.rangeLabel).toSet().join(' / ')}',
    );
    for (var i = 0; i < entries.length; i++) {
      b.writeln('${_letter(i)} ${entries[i].name}：胜 ${wins[i]} 项');
    }
    for (final o in outs) {
      final vals = [
        for (var i = 0; i < entries.length; i++)
          '${_letter(i)} ${lhPkValue(o.metric, o.values[i])}'
              '${o.solo(i) ? '✓' : ''}',
      ];
      b.writeln('${o.metric.label}：${vals.join(' / ')}');
    }
    b.write(summary);
    return b.toString();
  }

  Widget _header(BuildContext context, List<int> wins) {
    Widget card(int i) {
      final c = _color(i);
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: lhPkCardDeco(
          context,
          radius: 16,
          edge: LhPkColors.tint(c, 0.55),
          edgeWidth: 1.4,
          glow: c,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LhPkSlotBadge(index: slots[i], size: 26, radius: 8),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: Text(
                      entries[i].name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LhTypography.sans(
                        context: context,
                        size: 12.5,
                        color: LhPkColors.ink,
                        weight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${wins[i]}',
                        style: LhTypography.mono(
                          context: context,
                          size: 24,
                          color: c,
                          weight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '项胜出',
                          style: LhTypography.sans(
                            context: context,
                            size: 10.5,
                            color: LhPkColors.mute,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: LhPkCorner(size: 16, color: c),
            ),
          ],
        ),
      );
    }

    if (entries.length == 2) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(child: card(0)),
              const SizedBox(width: 12),
              Expanded(child: card(1)),
            ],
          ),
          LhPkStack(
            radius: 12,
            dx: 4,
            dy: -4,
            angle: 0.1,
            child: Container(
              width: 42,
              height: 42,
              clipBehavior: Clip.antiAlias,
              decoration: lhPkCardDeco(
                context,
                radius: 12,
                edge: LhPkColors.edge,
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      'VS',
                      style: LhTypography.mono(
                        context: context,
                        size: 14,
                        color: LhPkColors.deep,
                        weight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: LhPkCorner(size: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        for (var r = 0; r < entries.length; r += 2) ...[
          if (r > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: card(r)),
              const SizedBox(width: 10),
              Expanded(
                child: r + 1 < entries.length
                    ? card(r + 1)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _score(
    BuildContext context,
    List<int> wins,
    List<int> leaders,
    int top,
    String summary,
  ) {
    final total = wins.fold<int>(0, (a, b) => a + b);
    final verdict = top == 0
        ? '全部打平'
        : (leaders.length > 1 ? '平局' : '${_letter(leaders.first)} 领先');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: lhPkCardDeco(context, radius: 14, raised: false),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      ':',
                      style: LhTypography.mono(
                        context: context,
                        size: 16,
                        color: LhPkColors.soft,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                Text(
                  '${wins[i]}',
                  style: LhTypography.mono(
                    context: context,
                    size: 22,
                    color: _color(i),
                    weight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LhPkColors.lavender,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  verdict,
                  style: LhTypography.sans(
                    context: context,
                    size: 11,
                    color: LhPkColors.deep,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: total == 0 ? 1 : math.max(1, wins[i] * 10),
                      child: ColoredBox(color: _color(i)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary,
            textAlign: TextAlign.center,
            style: LhTypography.sans(
              context: context,
              size: 11,
              color: LhPkColors.ink2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueText(
    BuildContext context,
    _PkOutcome o,
    int i, {
    TextAlign align = TextAlign.left,
  }) {
    final won = o.solo(i);
    final v = o.values[i];
    return Text(
      lhPkValue(o.metric, v),
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: LhTypography.mono(
        context: context,
        size: 14.5,
        color: won ? _color(i) : (v < 0 ? LhPkColors.down : LhPkColors.mute),
        weight: won ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }

  Widget _winTag(int i) => Container(
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _color(i),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text(
      '胜',
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.0,
      ),
    ),
  );

  /// 一根条：赢的实色，输的淡色；负数画成空心。
  Widget _bar(_PkOutcome o, int i, double maxAbs, {required bool leftward}) {
    final v = o.values[i];
    final frac = maxAbs <= 0 ? 0.0 : (v.abs() / maxAbs).clamp(0.0, 1.0);
    final won = o.solo(i);
    final c = _color(i);
    final radius = leftward
        ? const BorderRadius.horizontal(left: Radius.circular(4))
        : const BorderRadius.horizontal(right: Radius.circular(4));
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = v.abs() < 1e-9 ? 0.0 : math.max(3.0, box.maxWidth * frac);
        return Align(
          alignment: leftward ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: w,
            height: 8,
            decoration: BoxDecoration(
              color: v < 0
                  ? LhPkColors.tint(c, 0.92)
                  : (won ? c : LhPkColors.tint(c, 0.62)),
              borderRadius: radius,
              border: v < 0
                  ? Border.all(color: LhPkColors.tint(c, 0.3), width: 1.1)
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _metricRow(
    BuildContext context,
    _PkOutcome o, {
    String? marginWarn,
  }) {
    final m = o.metric;
    final maxAbs = o.values.map((v) => v.abs()).reduce(math.max);
    final hasNeg = o.values.any((v) => v < 0);
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          m.label,
          style: LhTypography.sans(
            context: context,
            size: 12,
            color: LhPkColors.ink,
            weight: FontWeight.w700,
          ),
        ),
        Text(
          m.lowerWins ? '低者胜' : '高者胜',
          style: LhTypography.sans(
            context: context,
            size: 9,
            color: LhPkColors.mute,
          ),
        ),
      ],
    );
    final note = _note(o);
    final children = <Widget>[];
    if (entries.length == 2) {
      children.addAll([
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(child: _valueText(context, o, 0)),
                  if (o.solo(0)) ...[const SizedBox(width: 4), _winTag(0)],
                ],
              ),
            ),
            const SizedBox(width: 6),
            label,
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (o.solo(1)) ...[_winTag(1), const SizedBox(width: 4)],
                  Flexible(
                    child: _valueText(context, o, 1, align: TextAlign.right),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 8,
          child: Row(
            children: [
              Expanded(child: _bar(o, 0, maxAbs, leftward: true)),
              const SizedBox(width: 3),
              Expanded(child: _bar(o, 1, maxAbs, leftward: false)),
            ],
          ),
        ),
      ]);
    } else {
      children.add(Align(alignment: Alignment.centerLeft, child: label));
      for (var i = 0; i < entries.length; i++) {
        children.addAll([
          const SizedBox(height: 6),
          Row(
            children: [
              LhPkSlotBadge(index: slots[i], size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 8,
                  child: _bar(o, i, maxAbs, leftward: false),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (o.solo(i)) ...[_winTag(i), const SizedBox(width: 4)],
                    Flexible(
                      child: _valueText(context, o, i, align: TextAlign.right),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]);
      }
    }
    if (note.isNotEmpty || hasNeg) {
      children.addAll([
        const SizedBox(height: 7),
        Text(
          [if (note.isNotEmpty) note, if (hasNeg) '空心条 = 负数'].join(' · '),
          textAlign: TextAlign.center,
          style: LhTypography.sans(
            context: context,
            size: 10.5,
            color: LhPkColors.ink2,
          ),
        ),
      ]);
    }
    if (marginWarn != null) {
      children.addAll([
        const SizedBox(height: 7),
        Center(child: _pkWarn(context, marginWarn)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: lhPkCardDeco(context, radius: 12, raised: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
