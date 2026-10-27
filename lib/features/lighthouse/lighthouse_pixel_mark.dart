import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ════════════════════════════════════════════════════════════════════════
// 灯塔像素件（2026-10-27 · v2 场景版）
//
//   顶栏「灯塔」右边的一整块像素场景：灯塔 + 光束扫向日期浮岛，
//   外加三个时段、五个事件、一个持续状态。原型见「灯塔像素动效原型」画布。
//
//   时段（浅色主题按中国时间自动切，深色主题固定夜晚；切换时像素逐格溶解）
//   浅色主题一律白底，不铺任何天空色块 —— 时段只靠天上的东西和光束亮度区分。
//     · 白天：太阳光芒交替、云飘、两只海鸥、偶尔鱼跃
//     · 黄昏：半个太阳沉进海里 + 海面碎金
//     · 夜晚：紫色星星、金色弯月、流星、月光倒影、塔窗亮灯、光束更亮
//
//   事件（[LighthousePixelController.fire]）
//     · sync    同步完成：灯头连闪三下，四颗数据包沿光束送进浮岛，浮岛亮一圈，弹对勾
//     · profit  利润上涨：海面升起三朵像素烟花（紫 / 金 / 粉），倒影落在浪上
//     · date    切换日期：光束一摆后锁定浮岛，浮岛闪光，星星重新排布
//     · ship    小船回港：点灯塔触发，光束一路跟着照，靠近时闪灯欢迎
//     · clear   数据补齐：storm 关掉时自动触发，云散雨停，升起一道灯塔紫虹
//
//   持续状态（[LighthousePixelController.storm]）
//     · 数据延迟：乌云、下雨、偶尔打闪、浪变高；灯头琥珀慢闪，光束被雾压短
//
//   全部用 CustomPainter 按像素格画，不依赖图片 / 像素字体；10 帧 / 秒，
//   只有帧号变了才重绘；「减少动态效果」时停在一帧、不放事件；
//   Ticker 走 TickerMode，保活页离屏时自动停。除负数外场景里不用绿色。
// ════════════════════════════════════════════════════════════════════════

/// 像素格边长（pt）。2026-10-27 · 2 → 2.5：顶栏抬头加高，像素更大、更清楚。
/// 想再大一点改成 3（整数在任何屏上都最锐）。
const double lighthousePixelSize = 2.5;

/// 场景固定 17 格高（灯塔 16 格 + 海面）。
const int lighthousePixelRows = 17;

/// 顶栏像素场景的高度 = 17 格。
const double lighthousePixelMarkHeight =
    lighthousePixelSize * lighthousePixelRows;

/// 顶栏像素灯塔开关。
const bool lighthousePixelMarkEnabled = true;

enum LighthousePixelEvent { sync, profit, date, ship, clear }

const Map<LighthousePixelEvent, int> _kEventFrames = {
  LighthousePixelEvent.sync: 36,
  LighthousePixelEvent.profit: 46,
  LighthousePixelEvent.date: 26,
  LighthousePixelEvent.ship: 76,
  LighthousePixelEvent.clear: 54,
};

class _PxEvent {
  _PxEvent(this.type, this.t0);
  final LighthousePixelEvent type;
  final int t0;
}

/// 页面驱动像素场景的遥控器：放事件、开关「数据延迟」、读浮岛是否该亮。
///
/// 不是 ChangeNotifier —— 场景本来就 10 帧 / 秒在重画，状态直接在下一帧读；
/// 所以在 build 里改 [storm] 也安全。只有 [islandGlow] 会通知（给浮岛加光）。
class LighthousePixelController {
  /// 同步完成 / 切换日期时，数据包或光束「到达」浮岛的那一小段为 true。
  final ValueNotifier<bool> islandGlow = ValueNotifier<bool>(false);

  final List<_PxEvent> _events = <_PxEvent>[];
  int _tick = 0;
  bool _attached = false;
  bool _still = false;
  bool _storm = false;
  int _stormSince = -1000;
  int _starShift = 0;

  bool get storm => _storm;

  /// 数据延迟：开 = 乌云下雨；关 = 自动放一次「数据补齐」彩虹。
  set storm(bool on) {
    if (on == _storm) return;
    _storm = on;
    if (on) {
      _stormSince = _tick;
    } else {
      fire(LighthousePixelEvent.clear);
    }
  }

  /// 放一个事件。场景没挂上 / 减少动态效果时忽略；同类事件重放会从头开始。
  void fire(LighthousePixelEvent type) {
    if (!_attached || _still) return;
    _events.removeWhere((e) => e.type == type);
    _events.add(_PxEvent(type, _tick));
    if (type == LighthousePixelEvent.date) _starShift += 5;
  }

  void _advance(int t) {
    _tick = t;
    _events.removeWhere((e) => t - e.t0 >= _kEventFrames[e.type]!);
    var glow = false;
    for (final e in _events) {
      final a = t - e.t0;
      if (e.type == LighthousePixelEvent.sync && a >= 20 && a <= 32) {
        glow = true;
      }
      if (e.type == LighthousePixelEvent.date && a >= 10 && a <= 20) {
        glow = true;
      }
    }
    if (islandGlow.value != glow) islandGlow.value = glow;
  }

  void dispose() => islandGlow.dispose();
}

// ── 顶栏像素灯塔 ──────────────────────────────────────────────────────────

class LighthousePixelMark extends StatefulWidget {
  const LighthousePixelMark({super.key, this.controller});

  /// 不传就只有待机动画 + 点灯塔放小船。
  final LighthousePixelController? controller;

  @override
  State<LighthousePixelMark> createState() => _LighthousePixelMarkState();
}

class _LighthousePixelMarkState extends State<LighthousePixelMark>
    with SingleTickerProviderStateMixin {
  static const int _stillFrame = 8;
  final ValueNotifier<int> _frame = ValueNotifier<int>(_stillFrame);
  final _LhPixelScene _scene = _LhPixelScene();
  LighthousePixelController? _own;
  Ticker? _ticker;
  int _base = _stillFrame;
  bool _still = false;

  LighthousePixelController get _ctl =>
      widget.controller ?? (_own ??= LighthousePixelController());

  @override
  void initState() {
    super.initState();
    _ctl._attached = true;
  }

  @override
  void didUpdateWidget(covariant LighthousePixelMark old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._attached = false;
      _ctl._attached = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _ctl._still = _still;
    if (_still) {
      _ticker?.stop();
      _ctl._events.clear();
      _ctl._advance(_frame.value);
      return;
    }
    _ticker ??= createTicker((elapsed) {
      // 帧号单调递增：Ticker 停了再开 elapsed 会归零，接在上一帧后面。
      final t = _base + elapsed.inMilliseconds ~/ 100;
      if (t != _frame.value) {
        _ctl._advance(t);
        _frame.value = t;
      }
    });
    if (!_ticker!.isActive) {
      _base = _frame.value + 1;
      _ticker!.start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frame.dispose();
    widget.controller?._attached = false;
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _ctl.fire(LighthousePixelEvent.ship),
        child: SizedBox(
          height: lighthousePixelMarkHeight,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LhPixelPainter(
                frame: _frame,
                scene: _scene,
                controller: _ctl,
                dark: dark,
                still: _still,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LhPixelPainter extends CustomPainter {
  _LhPixelPainter({
    required this.frame,
    required this.scene,
    required this.controller,
    required this.dark,
    required this.still,
  }) : super(repaint: frame);

  final ValueNotifier<int> frame;
  final _LhPixelScene scene;
  final LighthousePixelController controller;
  final bool dark;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) =>
      scene.paint(canvas, size, frame.value, controller, dark, still);

  @override
  bool shouldRepaint(covariant _LhPixelPainter old) =>
      old.dark != dark || old.still != still || old.controller != controller;
}

// ── 配色 ──────────────────────────────────────────────────────────────────

enum _Tod { day, dusk, night }

class _Pal {
  const _Pal({
    required this.sea,
    required this.hi,
    required this.lo,
    required this.star,
    required this.starDim,
    required this.beam,
    required this.beamA,
    required this.lamp,
    required this.lampLight,
    required this.ink,
    required this.sky,
    required this.win,
    required this.tower,
    required this.shade,
    required this.sail,
    required this.hull,
    required this.flag,
    required this.check,
    required this.rain,
    required this.cloud,
    required this.moon,
    required this.spark,
  });

  final int sea, hi, lo, star, starDim, beam, lamp, lampLight, ink, win;
  final double beamA;
  final List<int>? sky;
  final Map<String, int> tower, shade;
  final List<int> sail, hull, cloud;
  final int flag, check, rain;

  /// 月亮 / 月光倒影色。浅底上用金色，深底上用奶白。
  final int moon;

  /// 最亮的点（数据包头、烟花爆点、流星、闪电、浮岛光柱）。浅底上白色看不见，用金色。
  final int spark;

  /// 浅色主题：不管几点都是白底，夜晚只换星星 / 月亮 / 光束，不铺深色天空。
  /// 深色主题：固定 [night]（顶栏本身是深色，同样不铺天空块）。
  static _Pal of(_Tod tod, bool dark) => dark
      ? night
      : switch (tod) {
          _Tod.day => day,
          _Tod.dusk => dusk,
          _Tod.night => nightLight,
        };

  static const _dayTower = {
    'D': 0x3B2D66,
    'R': 0x4A3A7A,
    'W': 0xF8F5FF,
    'P': 0x6E55CC,
    'K': 0x2E2350,
    'S': 0x9384D3,
    'T': 0x7C6DC2,
  };
  static const _dayShade = {'P': 0x5843B4, 'W': 0xDDD3F8, 'S': 0x8273C6};

  static const day = _Pal(
    sea: 0xDCD2F7,
    hi: 0xF4F0FE,
    lo: 0xBFAEEE,
    star: 0xA48BEB,
    starDim: 0xCFC2F5,
    beam: 0xF2C14E,
    beamA: 0.24,
    lamp: 0xFFD66B,
    lampLight: 0xFFF3C4,
    ink: 0x5A458F,
    sky: null,
    win: 0x2E2350,
    tower: _dayTower,
    shade: _dayShade,
    sail: [0xEDE6FD, 0xC9BBF2],
    hull: [0x4A3A7A, 0x3B2D66],
    flag: 0x7B5CD8,
    check: 0x7B5CD8,
    rain: 0xB3A6E0,
    cloud: [0xD4CBEE, 0xBCB0E2],
    moon: 0xF2C14E,
    spark: 0xF2C14E,
  );

  static const dusk = _Pal(
    sea: 0xE2CCEA,
    hi: 0xFCEEF4,
    lo: 0xC4A5DC,
    star: 0xB39CEE,
    starDim: 0xE0D3F7,
    beam: 0xFFC66A,
    beamA: 0.38,
    lamp: 0xFFD66B,
    lampLight: 0xFFF3C4,
    ink: 0x5A3F7A,
    sky: null,
    win: 0xFFC66A,
    tower: _dayTower,
    shade: _dayShade,
    sail: [0xEDE6FD, 0xC9BBF2],
    hull: [0x4A3A7A, 0x3B2D66],
    flag: 0x7B5CD8,
    check: 0x7B5CD8,
    rain: 0xB3A6E0,
    cloud: [0xD4CBEE, 0xBCB0E2],
    moon: 0xF2C14E,
    spark: 0xF2C14E,
  );

  static const night = _Pal(
    sea: 0x30275C,
    hi: 0x5D50A0,
    lo: 0x221A45,
    star: 0xFFFFFF,
    starDim: 0x8E7FD0,
    beam: 0xFFF0C2,
    beamA: 0.6,
    lamp: 0xFFE08A,
    lampLight: 0xFFF8DA,
    ink: 0xD9CFFF,
    sky: null,
    win: 0xFFD66B,
    tower: {
      'D': 0x17112B,
      'R': 0x241B42,
      'W': 0xD9D0F5,
      'P': 0x7E66DA,
      'K': 0x17112B,
      'S': 0x5A4C99,
      'T': 0x4A3D86,
    },
    shade: {'P': 0x6650C4, 'W': 0xB9ADE6, 'S': 0x4D4089},
    sail: [0xE6DEFF, 0xB5A6E8],
    hull: [0x6E55CC, 0x4A3D86],
    flag: 0xB9A5F0,
    check: 0xE6DEFF,
    rain: 0x9C8FE0,
    cloud: [0x5A4E8A, 0x463B74],
    moon: 0xFFF3C4,
    spark: 0xFFFFFF,
  );

  /// 浅色主题的夜晚：白底不变，光束更亮、星星紫色闪、金月亮、塔窗亮灯。
  static const nightLight = _Pal(
    sea: 0xD9CEF6,
    hi: 0xF1ECFD,
    lo: 0xB9A7EC,
    star: 0x8E74E0,
    starDim: 0xC9BCF3,
    beam: 0xF2C14E,
    beamA: 0.42,
    lamp: 0xFFD66B,
    lampLight: 0xFFF3C4,
    ink: 0x5A458F,
    sky: null,
    win: 0xFFC94D,
    tower: _dayTower,
    shade: _dayShade,
    sail: [0xEDE6FD, 0xC9BBF2],
    hull: [0x4A3A7A, 0x3B2D66],
    flag: 0x7B5CD8,
    check: 0x7B5CD8,
    rain: 0xB3A6E0,
    cloud: [0xD4CBEE, 0xBCB0E2],
    moon: 0xF2C14E,
    spark: 0xF2C14E,
  );
}

// ── 精灵图 ────────────────────────────────────────────────────────────────

// 9 列 × 16 行；右侧两列压暗做体积。
const _kTower = <String>[
  '....D....',
  '...DDD...',
  '..DLYLD..',
  '..DYYYD..',
  '.DDDDDDD.',
  '.R.R.R.R.',
  '..WWWWW..',
  '..PPPPP..',
  '..PPKPP..',
  '..WWWWW..',
  '.PPPPPPP.',
  '.PPPPKPP.',
  '.WWWWWWW.',
  'PPPPPPPPP',
  'PPPPKKPPP',
  'SSSSTSSSS',
];
const _kGullUp = <String>['D...D', '.D.D.', '..D..'];
const _kGullDown = <String>['.....', 'DD.DD', '..D..'];
const _kShip = <String>[
  '.....F.....',
  '.....FF....',
  '.....M.....',
  '....sMSS...',
  '...ssMSSS..',
  'HHHHHHHHHHH',
  '.hhhhhhhhh.',
];
const _kCloud = <String>['...cc....', '.ccccc.c.', 'ccccccccc', '.ddddddd.'];
const _kStormCloud = <String>[
  '...cccc........',
  '.cccccccc.ccc..',
  'ccccccccccccccc',
  '.ddddddddddddd.',
];
const _kMoon = <String>['..MMM.', '.MM...', 'MM....', 'MM....', '.MM...', '..MMM.'];
const _kSun = <String>['.oo.', 'oOOo', 'oOOo', '.oo.'];
const _kCheck = <String>['....c', '...c.', 'c.c..', '.c...'];
const _kStars = <(double, int)>[
  (0.10, 2), (0.20, 7), (0.28, 1), (0.37, 10), (0.45, 4), (0.55, 8),
  (0.62, 2), (0.70, 6), (0.78, 11), (0.86, 3), (0.93, 9), (0.50, 12),
];
const _kBayer = <List<int>>[
  [0, 8, 2, 10],
  [12, 4, 14, 6],
  [3, 11, 1, 9],
  [15, 7, 13, 5],
];

// ── 场景 ──────────────────────────────────────────────────────────────────
//
// 先把一帧画进 W×H 的 RGBA 缓冲（按格合成透明度），再一次性按格铺到画布上。
// 好处：时段切换的「逐格溶解」只是两份缓冲按 Bayer 阈值挑格子。

class _LhPixelScene {
  static const int _h = lighthousePixelRows;
  int _w = 0;
  Float32List _a = Float32List(0);
  Float32List _b = Float32List(0);
  Float32List _out = Float32List(0);
  Float32List _cur = Float32List(0);
  _Tod? _lastTod;
  _Tod? _todFrom;
  int _todAt = -100;
  final Paint _paint = Paint()..isAntiAlias = false;

  // 当前这一帧的上下文
  late LighthousePixelController _c;
  bool _dark = false;

  void paint(
    Canvas canvas,
    Size size,
    int t,
    LighthousePixelController c,
    bool dark,
    bool still,
  ) {
    final w = (size.width / lighthousePixelSize).floor();
    if (w < 10) return;
    if (w != _w) {
      _w = w;
      final n = _w * _h * 4;
      _a = Float32List(n);
      _b = Float32List(n);
      _out = Float32List(n);
    }
    _c = c;
    _dark = dark;
    final tod = dark ? _Tod.night : _todNow();
    if (_lastTod != null && tod != _lastTod) {
      _todFrom = _lastTod;
      _todAt = t;
    }
    _lastTod = tod;

    _render(_a, tod, t);
    var src = _a;
    final ta = t - _todAt;
    if (_todFrom != null && ta >= 0 && ta < 12 && !still) {
      _render(_b, _todFrom!, t);
      _mix(_b, _a, ta / 12, _out);
      src = _out;
    }
    _blit(canvas, src);
  }

  static _Tod _todNow() {
    // 与「数据已同步」同一口径：中国时间，不依赖设备时区。
    final h = DateTime.now().toUtc().add(const Duration(hours: 8)).hour;
    if (h >= 6 && h < 17) return _Tod.day;
    if (h >= 17 && h < 19) return _Tod.dusk;
    return _Tod.night;
  }

  // ── 基础 ──
  double _hash(num n) {
    final s = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return s - s.floorToDouble();
  }

  bool _on(int t, int period, int phase) =>
      ((t + phase) % period) < period / 2;

  double _th(int x, int y) => (_kBayer[(y % 4 + 4) % 4][(x % 4 + 4) % 4] + 0.5) / 16;

  void _px(num xf, num yf, int rgb, [double a = 1]) {
    final x = xf.round();
    final y = yf.round();
    if (x < 0 || y < 0 || x >= _w || y >= _h || a <= 0.004) return;
    if (a > 1) a = 1;
    final b = _cur;
    final i = (y * _w + x) * 4;
    final da = b[i + 3];
    final oa = a + da * (1 - a);
    final r = ((rgb >> 16) & 255).toDouble();
    final g = ((rgb >> 8) & 255).toDouble();
    final bl = (rgb & 255).toDouble();
    b[i] = (r * a + b[i] * da * (1 - a)) / oa;
    b[i + 1] = (g * a + b[i + 1] * da * (1 - a)) / oa;
    b[i + 2] = (bl * a + b[i + 2] * da * (1 - a)) / oa;
    b[i + 3] = oa;
  }

  void _sprite(
    List<String> map,
    num ox,
    num oy,
    int? Function(String k) colorOf, [
    double alpha = 1,
  ]) {
    for (var r = 0; r < map.length; r++) {
      final line = map[r];
      for (var c = 0; c < line.length; c++) {
        final k = line[c];
        if (k == '.') continue;
        final col = colorOf(k);
        if (col != null) _px(ox + c, oy + r, col, alpha);
      }
    }
  }

  void _mix(Float32List a, Float32List b, double p, Float32List out) {
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final i = (y * _w + x) * 4;
        final src = p > _th(x, y) ? b : a;
        out[i] = src[i];
        out[i + 1] = src[i + 1];
        out[i + 2] = src[i + 2];
        out[i + 3] = src[i + 3];
      }
    }
  }

  void _blit(Canvas canvas, Float32List src) {
    const p = lighthousePixelSize;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final i = (y * _w + x) * 4;
        final a = src[i + 3];
        if (a < 0.01) continue;
        _paint.color = Color.fromRGBO(
          src[i].round().clamp(0, 255).toInt(),
          src[i + 1].round().clamp(0, 255).toInt(),
          src[i + 2].round().clamp(0, 255).toInt(),
          a.clamp(0.0, 1.0).toDouble(),
        );
        canvas.drawRect(Rect.fromLTWH(x * p, y * p, p, p), _paint);
      }
    }
  }

  double _shipX(int age) => _w + 1 - age * 1.25;

  // ── 一帧 ──
  void _render(Float32List buf, _Tod tod, int t) {
    _cur = buf;
    buf.fillRange(0, buf.length, 0);
    final pal = _Pal.of(tod, _dark);
    final c = _c;
    final ev = <LighthousePixelEvent, int>{
      for (final e in c._events) e.type: t - e.t0,
    };
    final storm = c._storm;
    final stormP = storm ? math.min(1.0, (t - c._stormSince) / 10) : 0.0;
    final clearA = ev[LighthousePixelEvent.clear];
    var cloudsP = 0.0;
    if (storm) {
      cloudsP = stormP;
    } else if (clearA != null) {
      cloudsP = 1 - math.min(1.0, clearA / 12);
    }
    final raining = (storm && stormP > 0.6) || (clearA != null && clearA < 4);
    final seaRows = (storm || (clearA != null && clearA < 8)) ? 3 : 2;
    final seaTop = _h - seaRows;
    final wide = _w >= 34;

    if (pal.sky != null) _sky(pal, tod);
    if (wide) {
      switch (tod) {
        case _Tod.night:
          _stars(pal, t, 12, true);
          _moon(pal);
          _shootingStar(pal, t);
        case _Tod.dusk:
          _stars(pal, t, 4, false);
          _sunset(seaTop);
        case _Tod.day:
          _sun(t);
          _dayClouds(t);
      }
    }
    if (clearA != null) _rainbow(clearA, seaTop);
    if (cloudsP > 0) _stormClouds(pal, cloudsP, t);
    if (tod != _Tod.night && cloudsP < 0.5 && _w >= 40) _gulls(pal, t, tod);
    _beam(pal, t, ev, seaTop, storm);
    _sea(pal, t, seaRows, seaTop);
    if (wide && tod == _Tod.night) _moonGlint(pal, t, seaTop);
    if (wide && tod == _Tod.dusk) _sunGlint(t, seaTop);
    if (tod == _Tod.day && !storm) _fish(t, seaTop);
    final profit = ev[LighthousePixelEvent.profit];
    if (profit != null) _fireworks(pal, profit, seaTop);
    final ship = ev[LighthousePixelEvent.ship];
    if (ship != null) _ship(pal, tod, ship, seaTop);
    if (raining) _rain(pal, t, seaTop);
    _tower(pal, tod, t, ev, storm);
    if (storm && stormP >= 1) _lightning(pal, t, seaTop, c._stormSince);
    final sync = ev[LighthousePixelEvent.sync];
    if (sync != null) _syncFx(pal, sync);
    final date = ev[LighthousePixelEvent.date];
    if (date != null) _dateFx(pal, date, seaTop);
  }

  // ── 天空 / 天体 ──
  void _sky(_Pal pal, _Tod tod) {
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final fx = math.min(
          1.0,
          math.min(math.max(0.0, (x - 1) / 12), math.max(0.0, (_w - 1 - x) / 14)),
        );
        final fy = tod == _Tod.night
            ? math.min(1.0, (y + 1) / 4)
            : math.min(1.0, math.max(0.0, (y - 1) / 10));
        final s = fx * fy * (tod == _Tod.night ? 1 : 0.85);
        if (s <= _th(x, y)) continue;
        final v = y / (_h - 1) + (_th(x + 2, y + 1) - 0.5) * 0.35;
        _px(x, y, v < 0.5 ? pal.sky![0] : pal.sky![1]);
      }
    }
  }

  void _stars(_Pal pal, int t, int n, bool avoidMoon) {
    for (var i = 0; i < n && i < _kStars.length; i++) {
      final fx = (_kStars[i].$1 + _c._starShift * 0.037) % 1.0;
      final x = (11 + (_w - 13) * fx).round();
      final y = _kStars[i].$2;
      if (avoidMoon && x >= _w - 15 && x <= _w - 6 && y <= 7) continue;
      final base = i % 3 == 0 ? pal.star : pal.starDim;
      _px(x, y, base, _on(t, 13 + (i % 4) * 4, i * 3) ? 1 : 0.25);
      if ((i == 0 || i == 6) && _on(t, 18 + i, i * 5)) {
        _px(x - 1, y, pal.star, 0.55);
        _px(x + 1, y, pal.star, 0.55);
        _px(x, y - 1, pal.star, 0.55);
        _px(x, y + 1, pal.star, 0.55);
      }
    }
  }

  void _moon(_Pal pal) {
    final x0 = _w - 13;
    const y0 = 1;
    for (var dy = -2; dy <= 7; dy++) {
      for (var dx = -2; dx <= 7; dx++) {
        final d = math.sqrt((dx - 2.5) * (dx - 2.5) + (dy - 2.5) * (dy - 2.5));
        if (d > 3.3 && d < 4.6) _px(x0 + dx, y0 + dy, pal.moon, 0.12);
      }
    }
    _sprite(_kMoon, x0, y0, (_) => pal.moon);
  }

  void _moonGlint(_Pal pal, int t, int seaTop) {
    final x0 = _w - 13;
    for (var x = x0; x < x0 + 6; x++) {
      if (_on(t + x * 3, 6, 0)) _px(x, seaTop, pal.moon, 0.75);
      if (seaTop + 1 < _h && x > x0 && x < x0 + 5 && _on(t + x * 5, 8, 2)) {
        _px(x, seaTop + 1, pal.moon, 0.45);
      }
    }
  }

  void _shootingStar(_Pal pal, int t) {
    final a = (t + 20) % 58;
    if (a >= 8) return;
    final hx = _w - 20 - a * 2.4;
    final hy = 1 + a * 0.55;
    _px(hx, hy, pal.spark);
    for (var k = 1; k <= 4; k++) {
      _px(hx + k * 1.2, hy - k * 0.28, pal.star, 0.6 - k * 0.12);
    }
  }

  void _sun(int t) {
    final x0 = _w - 12;
    const y0 = 2;
    _sprite(_kSun, x0, y0, (k) => k == 'O' ? 0xFFE9A6 : 0xFFD66B);
    const c = 0xFFD66B;
    if ((t ~/ 6) % 2 == 0) {
      for (final (dx, dy) in const [
        (1, -2), (2, -2), (1, 5), (2, 5), (-2, 1), (-2, 2), (5, 1), (5, 2),
      ]) {
        _px(x0 + dx, y0 + dy, c, 0.8);
      }
    } else {
      for (final (dx, dy) in const [(-1, -1), (4, -1), (-1, 4), (4, 4)]) {
        _px(x0 + dx, y0 + dy, c, 0.8);
      }
    }
  }

  void _dayClouds(int t) {
    final span = _w + 12;
    for (final (x0, y, sp) in const [(20, 1, 0.12), (55, 5, 0.08)]) {
      final x = (((x0 - t * sp) % span) + span) % span - 8;
      _sprite(_kCloud, x, y, (k) => k == 'c' ? 0xECE6FB : 0xDCD2F7);
    }
  }

  void _sunset(int seaTop) {
    final cx = (_w * 0.7).round();
    const rows = {-4: 0xFFE3A0, -3: 0xFFD27E, -2: 0xFFB867, -1: 0xFF9E5E};
    for (var dy = -4; dy <= -1; dy++) {
      for (var dx = -4; dx <= 3; dx++) {
        if ((dx + 0.5) * (dx + 0.5) + (dy + 0.5) * (dy + 0.5) <= 16.5) {
          _px(cx + dx, seaTop + dy, rows[dy]!);
        }
      }
    }
  }

  void _sunGlint(int t, int seaTop) {
    final cx = (_w * 0.7).round();
    for (var x = cx - 3; x <= cx + 2; x++) {
      if (_on(t + x, 4, 0)) _px(x, seaTop, 0xFFB867, 0.85);
    }
    for (var x = cx - 2; x <= cx + 1; x++) {
      if (_on(t + x * 2, 6, 1)) _px(x, seaTop + 1, 0xFFB867, 0.6);
    }
  }

  // ── 生物 ──
  void _gulls(_Pal pal, int t, _Tod tod) {
    final span = _w + 10;
    final list = tod == _Tod.day
        ? const [(1.2, 0, 5), (0.9, 37, 8)]
        : const [(1.0, 11, 6)];
    for (var i = 0; i < list.length; i++) {
      final (sp, off, y) = list[i];
      final gx = _w - ((t * sp + off) % span);
      if (gx > 10) {
        _sprite(_on(t, 6, i * 2) ? _kGullUp : _kGullDown, gx, y, (_) => pal.ink);
      }
    }
  }

  void _fish(int t, int seaTop) {
    final a = (t + 30) % 90;
    if (a >= 8) return;
    const arc = [0.0, 2.0, 3.0, 3.5, 3.0, 2.0, 0.5, 0.0];
    final fx = (_w * 0.42).round() + a;
    final fy = seaTop - arc[a];
    _px(fx, fy, 0xF2A65A);
    _px(fx - 1, fy + (a < 4 ? 0.6 : -0.6), 0xF2A65A, 0.7);
    if (a == 0 || a == 7) {
      _px(fx - 1, seaTop - 1, 0xF4F0FE, 0.9);
      _px(fx + 1, seaTop - 1, 0xF4F0FE, 0.9);
    }
  }

  // ── 光束 / 海 ──
  void _beam(
    _Pal pal,
    int t,
    Map<LighthousePixelEvent, int> ev,
    int seaTop,
    bool storm,
  ) {
    const lampX = 7;
    const lampY = 2;
    const slopes = [-0.2, -0.1, 0.0, 0.08, 0.0, -0.1];
    var slope = slopes[(t ~/ 4) % slopes.length];
    var spreadAdd = 0;
    var aMul = 1.0;
    var len = _w - lampX;
    final sync = ev[LighthousePixelEvent.sync];
    if (sync != null && sync < 22) {
      slope = 0;
      spreadAdd = 1;
      aMul = 1.8;
    }
    final date = ev[LighthousePixelEvent.date];
    if (date != null) {
      if (date < 9) {
        slope = math.sin(date * 0.9) * 0.38;
      } else if (date < 22) {
        slope = 0;
        spreadAdd = 1;
        aMul = 1.9;
      }
    }
    final ship = ev[LighthousePixelEvent.ship];
    if (ship != null) {
      // 光束一路跟着小船照。
      final sx = _shipX(ship) + 5;
      if (sx > 12 && sx < _w) {
        slope = ((seaTop - 3) - lampY) / (sx - lampX);
        len = (sx - lampX + 3).round();
        aMul *= 1.3;
      }
    }
    if (storm) {
      len = (len * 0.5).floor();
      aMul *= 0.75;
    }
    for (var k = 1; k <= len; k++) {
      final spread = k ~/ 10 + spreadAdd;
      final cy = (slope * k).round();
      final a = (math.min(1.0, pal.beamA * aMul) *
              math.pow(1 - k / (len + 1), 1.2))
          .toDouble();
      for (var d = -spread; d <= spread; d++) {
        final y = lampY + cy + d;
        if (y < 0 || y >= seaTop) continue;
        _px(lampX + k - 1, y, pal.beam, d == 0 ? a : a * 0.7);
      }
    }
  }

  double _seaFade(int x) {
    final f = _w - 9;
    if (x < f) return 1;
    return const [0.7, 0.48, 0.26][math.min(2, (x - f) ~/ 3)];
  }

  void _sea(_Pal pal, int t, int rows, int seaTop) {
    for (var y = seaTop; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        _px(x, y, pal.sea, _seaFade(x));
      }
    }
    final hiOff = (t ~/ 2) % 6;
    for (var x = -hiOff; x < _w; x += 6) {
      for (var k = 0; k < 3; k++) {
        if (x + k >= 0) _px(x + k, seaTop, pal.hi, _seaFade(x + k));
      }
    }
    final loOff = (t ~/ 3) % 6;
    for (var x = loOff - 6; x < _w; x += 6) {
      for (var k = 0; k < 2; k++) {
        if (x + k >= 0) _px(x + k, seaTop + 1, pal.lo, _seaFade(x + k));
      }
    }
    if (rows == 3) {
      final o = (t ~/ 2) % 4;
      for (var x = o - 4; x < _w; x += 4) {
        if (x >= 0) _px(x, seaTop + 2, pal.hi, 0.5 * _seaFade(x));
      }
      for (var x = 0; x < _w; x++) {
        if (_hash(x * 7 + t ~/ 2) > 0.86) {
          _px(x, seaTop - 1, pal.hi, 0.9 * _seaFade(x));
        }
      }
    }
  }

  // ── 事件 ──
  void _fireworks(_Pal pal, int age, int seaTop) {
    const rockets = [
      (0.34, 0, 4, 0x7B5CD8, 0xC4B3F5),
      (0.58, 7, 2, 0xFFC94D, 0xFFF0C2),
      (0.80, 14, 5, 0xF07FAA, 0xFBD0E0),
    ];
    for (final (fx, t0, by, c0, c1) in rockets) {
      final ra = age - t0;
      if (ra < 0) continue;
      final cx = (_w * fx).round();
      const rise = 6;
      if (ra < rise) {
        final y = (seaTop - 1) - (seaTop - 1 - by) * (ra / rise);
        _px(cx, y, pal.spark);
        _px(cx, y + 1, c1, 0.6);
        _px(cx, y + 2, c1, 0.3);
        continue;
      }
      final b = ra - rise;
      if (b > 18) continue;
      if (b < 2) {
        _px(cx, by, pal.spark);
        _px(cx - 1, by, c1, 0.9);
        _px(cx + 1, by, c1, 0.9);
        _px(cx, by - 1, c1, 0.9);
        _px(cx, by + 1, c1, 0.9);
      }
      final rad = math.min(b * 0.8, 5.2);
      const n = 12;
      for (var i = 0; i < n; i++) {
        final ang = i / n * math.pi * 2;
        final drop = 0.03 * b * b;
        final x = cx + math.cos(ang) * rad * 1.25;
        final y = by + math.sin(ang) * rad * 0.8 + drop;
        final col = b < 7 ? c0 : c1;
        final a = b < 10
            ? 1.0
            : (((b + i) % 2) == 1 ? 0.2 : 0.75) * (1 - (b - 10) / 9);
        if (y < seaTop) _px(x, y, col, a);
        if (b > 2 && b < 12) {
          final y2 = by + math.sin(ang) * rad * 0.48 + drop;
          if (y2 < seaTop) _px(cx + math.cos(ang) * rad * 0.75, y2, c1, 0.45);
        }
      }
      if (b < 12) {
        for (var k = -3; k <= 3; k++) {
          if (_hash(cx * 3 + k + b) > 0.45) {
            _px(cx + k * 2, seaTop, c0, 0.5 * (1 - b / 12));
          }
        }
      }
    }
  }

  void _ship(_Pal pal, _Tod tod, int age, int seaTop) {
    final x = _shipX(age);
    if (x < -12) return;
    final y0 = seaTop - 5 + (age ~/ 6) % 2;
    for (var k = 0; k < 5; k++) {
      if (_on(age + k, 4, 0)) {
        _px(x + 11 + k * 1.5, seaTop, pal.hi, 0.85 - k * 0.15);
      }
    }
    _sprite(_kShip, x, y0, (k) {
      switch (k) {
        case 'F':
          return pal.flag;
        case 'M':
          return pal.ink;
        case 'S':
          return pal.sail[0];
        case 's':
          return pal.sail[1];
        case 'H':
          return pal.hull[0];
        default:
          return pal.hull[1];
      }
    });
    if (tod != _Tod.day && _on(age, 6, 0)) {
      _px(x + 6, y0 + 2, 0xFFD66B);
      _px(x + 7, y0 + 2, 0xFFD66B, 0.35);
    }
  }

  void _rain(_Pal pal, int t, int seaTop) {
    for (var i = 0; i < 34; i++) {
      final x0 = _hash(i + 1) * (_w + 8);
      final sp = 1.5 + _hash(i + 50) * 0.6;
      final y = ((_hash(i + 99) * _h + t * sp) % (_h + 2)) - 1;
      final x = x0 - y * 0.5;
      if (y < seaTop) {
        _px(x, y, pal.rain, 0.85);
        _px(x + 0.6, y - 1, pal.rain, 0.4);
      } else if (y < seaTop + 1) {
        _px(x, seaTop - 1, pal.hi, 0.7);
      }
    }
  }

  void _stormClouds(_Pal pal, double p, int t) {
    const list = [(0.2, 0), (0.47, 1), (0.74, 0)];
    for (var i = 0; i < list.length; i++) {
      final (fx, y) = list[i];
      final x = (_w * fx).round() -
          7 +
          (1 - p) * (_w + 10) +
          math.sin((t + i * 9) / 12).round();
      _sprite(_kStormCloud, x, y, (k) => k == 'c' ? pal.cloud[0] : pal.cloud[1]);
    }
  }

  void _lightning(_Pal pal, int t, int seaTop, int since) {
    final sa = t - since;
    final la = sa % 38;
    if (sa <= 14 || la >= 2) return;
    final bx = (16 + _hash(sa ~/ 38) * (_w - 26)).round();
    var x = bx;
    for (var y = 3; y < seaTop; y++) {
      _px(x, y, pal.spark, la == 0 ? 1 : 0.55);
      if (y % 2 == 0) x += _hash(y + bx) > 0.5 ? 1 : -1;
    }
  }

  void _rainbow(int a, int seaTop) {
    if (a < 6) return;
    // 灯塔紫虹：粉 / 金 / 浅紫 / 主紫，刻意不带绿。
    const cols = [0xF07FAA, 0xFFC94D, 0xB9A5F0, 0x7B5CD8];
    final cx = (_w * 0.56).round();
    final cy = _h - 1;
    final pIn = math.min(1.0, (a - 6) / 8);
    final pOut = a > 40 ? (a - 40) / 14 : 0.0;
    for (var b = 0; b < 4; b++) {
      final r = 10 - b;
      final seen = <int>{};
      for (var ang = 0.0; ang <= math.pi; ang += 0.03) {
        final x = (cx + math.cos(ang) * r * 1.9).round();
        final y = (cy - math.sin(ang) * r).round();
        if (!seen.add(x * 100 + y)) continue;
        if (y < 0 || y >= seaTop) continue;
        final th = _th(x, y);
        if (pIn < th || pOut > th) continue;
        _px(x, y, cols[b], 0.6);
      }
    }
  }

  void _tower(
    _Pal pal,
    _Tod tod,
    int t,
    Map<LighthousePixelEvent, int> ev,
    bool storm,
  ) {
    var lamp = pal.lamp;
    var lampL = pal.lampLight;
    var glowA = 0.2 + 0.1 * ((t ~/ 6) % 4);
    var glowR = 1.0;
    if (storm) {
      final bright = (t % 10) < 5;
      lamp = bright ? 0xFFB45E : 0xC98A4A;
      lampL = bright ? 0xFFE0B5 : 0xE8B989;
      glowA = bright ? 0.32 : 0.1;
    }
    var flash = false;
    final sync = ev[LighthousePixelEvent.sync];
    if (sync != null && sync < 7 && sync % 2 == 0) flash = true;
    final date = ev[LighthousePixelEvent.date];
    if (date != null && date >= 9 && date < 12) flash = true;
    final ship = ev[LighthousePixelEvent.ship];
    if (ship != null) {
      final sx = _shipX(ship);
      if (sx < 18 && sx > -6 && (ship % 4) < 2) flash = true;
    }
    if (flash) {
      lamp = 0xFFFFFF;
      lampL = 0xFFFFFF;
      glowA = 0.55;
      glowR = 1.5;
    }
    final dayMul = tod == _Tod.day ? 0.8 : 1.0;
    for (var y = -3; y <= 8; y++) {
      for (var x = -4; x <= 14; x++) {
        final dx = (x - 4.5) / (5.5 * glowR);
        final dy = (y - 2.5) / (3.8 * glowR);
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 1) _px(x, y, lamp, glowA * (1 - d) * dayMul);
      }
    }
    for (var r = 0; r < _kTower.length; r++) {
      final line = _kTower[r];
      final shadeFrom = line.replaceAll(RegExp(r'\.+$'), '').length - 2;
      for (var c = 0; c < line.length; c++) {
        final k = line[c];
        if (k == '.') continue;
        int col;
        if (k == 'Y') {
          col = lamp;
        } else if (k == 'L') {
          col = lampL;
        } else if (k == 'K' &&
            tod != _Tod.day &&
            !(_hash(r * 13 + c + t ~/ 9) > 0.88)) {
          col = pal.win;
        } else if (c >= shadeFrom && pal.shade.containsKey(k)) {
          col = pal.shade[k]!;
        } else {
          col = pal.tower[k]!;
        }
        _px(c, r, col);
      }
    }
  }

  void _syncFx(_Pal pal, int a) {
    for (var i = 0; i < 4; i++) {
      final pa = a - (2 + i * 3);
      if (pa < 0) continue;
      final x = 8 + pa * 3;
      if (x < _w) {
        _px(x, 2, pal.spark);
        _px(x - 1, 2, pal.beam, 0.85);
        _px(x - 2, 2, pal.beam, 0.55);
        _px(x - 3, 2, pal.beam, 0.3);
        _px(x, 1, pal.beam, 0.3);
        _px(x, 3, pal.beam, 0.3);
      } else if (x < _w + 9) {
        final k = (x - _w) ~/ 3;
        _px(_w - 2, 2, pal.spark);
        for (var d = 1; d <= k + 1; d++) {
          final al = 0.75 - 0.2 * d;
          _px(_w - 2 - d, 2, pal.beam, al);
          _px(_w - 2, 2 - d, pal.beam, al);
          _px(_w - 2, 2 + d, pal.beam, al);
        }
      }
    }
    if (a >= 16) {
      final cx = _w - 9;
      const cy = 7;
      final fade = a > 30 ? (a % 2 == 1 ? 0.2 : 0.7) : 1.0;
      if (a == 16) {
        _sprite(_kCheck.sublist(2), cx, cy + 2, (_) => pal.check, fade);
      } else {
        _sprite(_kCheck, cx, cy, (_) => pal.check, fade);
      }
      if (a < 20) {
        final r = (a - 15) * 1.5;
        for (var i = 0; i < 8; i++) {
          final ang = i / 8 * math.pi * 2;
          _px(
            cx + 2 + math.cos(ang) * r * 1.2,
            cy + 1.5 + math.sin(ang) * r * 0.8,
            pal.check,
            0.5,
          );
        }
      }
    }
  }

  void _dateFx(_Pal pal, int a, int seaTop) {
    if (a < 10 || a >= 20) return;
    final f = 1 - (a - 10) / 10;
    for (var y = 0; y < seaTop; y++) {
      _px(_w - 1, y, pal.spark, 0.55 * f);
      _px(_w - 2, y, pal.spark, 0.25 * f);
    }
    final r = (a - 10) * 0.9;
    for (var i = 0; i < 8; i++) {
      final ang = i / 8 * math.pi * 2;
      _px(_w - 3 + math.cos(ang) * r * 1.3, 2 + math.sin(ang) * r * 0.8,
          pal.beam, f);
    }
  }
}
