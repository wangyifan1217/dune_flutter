import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flow_ctx.dart';
import 'flow_topology.dart';

//  4. 几何：端点、贝塞尔路径、采样点（用于点击命中与标签定位）
// ============================================================================

class _AnchorPoint {
  const _AnchorPoint(this.p, this.nx, this.ny);
  final Offset p;
  final double nx, ny; // 外法线方向
}

_AnchorPoint _anchorOf(Anchor a) {
  final n = kNodeById[a.node]!;
  final cx = n.x + n.w / 2, cy = n.y + n.h / 2;
  switch (a.side) {
    case 'L':
      return _AnchorPoint(Offset(n.x, cy + a.off), -1, 0);
    case 'R':
      return _AnchorPoint(Offset(n.x + n.w, cy + a.off), 1, 0);
    case 'T':
      return _AnchorPoint(Offset(cx + a.off, n.y), 0, -1);
    default:
      return _AnchorPoint(Offset(cx + a.off, n.y + n.h), 0, 1);
  }
}

class EdgeGeometry {
  EdgeGeometry(this.def) {
    final a = _anchorOf(def.a);
    final b = _anchorOf(def.b);
    late Offset c1, c2;
    if (def.c != null) {
      c1 = def.c![0];
      c2 = def.c![1];
    } else {
      c1 = Offset(a.p.dx + a.nx * def.d[0], a.p.dy + a.ny * def.d[0]);
      c2 = Offset(b.p.dx + b.nx * def.d[1], b.p.dy + b.ny * def.d[1]);
    }
    start = a.p;
    end = b.p;
    endNormal = Offset(b.nx, b.ny);
    path = Path()
      ..moveTo(a.p.dx, a.p.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.p.dx, b.p.dy);
    metric = path.computeMetrics().first;
    length = metric.length;
    // 每 6px 采样一次，供点击 / 悬停命中使用（对应 HTML 的 stroke-width:18 命中带）
    for (double d = 0; d <= length; d += 6) {
      final t = metric.getTangentForOffset(d);
      if (t != null) samples.add(t.position);
    }
  }

  final EdgeDef def;
  late final Path path;
  late final ui.PathMetric metric;
  late final double length;
  late final Offset start, end, endNormal;
  final List<Offset> samples = [];

  Offset at(double frac) {
    final t = metric.getTangentForOffset(length * frac.clamp(0.0, 1.0));
    return t?.position ?? start;
  }

  /// 截取一段用于「彗星拖尾」
  Path segment(double from, double to) =>
      metric.extractPath(from.clamp(0.0, length), to.clamp(0.0, length));
}

final Map<String, EdgeGeometry> kGeom = {
  for (final e in kEdges) e.id: EdgeGeometry(e),
};

// ============================================================================
//  5. 标注（标签）：组装 → 测量 → 避让
// ============================================================================

class LabelParts {
  const LabelParts({
    required this.name,
    required this.sub,
    required this.owner,
    required this.issue,
  });
  final bool name, sub, owner, issue;
  bool get any => name || sub || owner || issue;
}

class LabelBox {
  LabelBox({
    required this.edgeId,
    required this.painter,
    required this.showAvatar,
    required this.initial,
    required this.tone,
    required this.kindColor,
    required this.level,
    required this.pinned,
    required this.baseT,
  });

  final String edgeId;
  final TextPainter painter;
  final bool showAvatar;
  final String initial;
  final Color tone; // 状态色
  final Color kindColor;
  final FlowLevel level;
  final bool pinned;
  final double baseT;

  static const double avatar = 19;
  static const double gap = 8;
  static const double padV = 4;

  /// 【已补】compact：放不下时降级为「只留头像」，对应 HTML 的 .flowx-label.compact
  bool compact = false;

  double get width => compact
      ? avatar + 4
      : (showAvatar ? avatar + gap + 3 : 11) + painter.width + 11;
  double get height => compact
      ? avatar + 4
      : math.max(avatar + padV * 2, painter.height + padV * 2);

  Offset center = Offset.zero;
  bool visible = true;

  Rect get rect =>
      Rect.fromCenter(center: center, width: width, height: height);
}

// ============================================================================
class FlowPanoramaSection extends StatefulWidget {
  const FlowPanoramaSection({
    super.key,
    required this.ctx,
    this.compact = false,
    this.canRename = true,
    this.allowFullscreen = true,
    this.immersive = false,
    this.onNodeRenamed,
  });

  final FlowCtx ctx;
  final bool compact;
  final bool canRename;
  final bool allowFullscreen;
  final bool immersive;
  final void Function(String nodeId, String name)? onNodeRenamed;

  @override
  State<FlowPanoramaSection> createState() => _FlowPanoramaSectionState();
}

class _FlowPanoramaSectionState extends State<FlowPanoramaSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  // 视图状态
  FlowKind? _flow; // null = 全景
  String? _pinEdge;
  String? _pinNode;

  // 【已补】悬停聚焦，对应 HTML 的 FLOWX.hover
  String? _hoverEdge;
  String? _hoverNode;
  String? _hoverItem; // 清单项 hover 底色

  // 标注分类开关（默认全关）
  bool _showName = false;
  bool _showSub = false;
  bool _showOwner = false;
  bool _showIssue = false;

  // 视图开关
  bool _issueOnly = false;
  bool _zones = true;
  bool _anim = true;

  // 可编辑主体名（人工改名回写表单）
  final Map<String, String> _customName = {};

  // 内联改名
  String? _editing;
  final TextEditingController _editCtl = TextEditingController();
  final FocusNode _editFocus = FocusNode();

  // PC / APP 共用缩放
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  double _scale = 1;
  Size _viewportSize = Size.zero;

  double get _minScale => widget.compact ? 0.85 : 0.75;
  double get _maxScale => 4.0;
  Offset? _doubleTapAt;

  // 每条边的动画相位与周期
  late final Map<String, double> _phase;
  late final Map<String, double> _period;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    final rnd = math.Random(7);
    _phase = {for (final e in kEdges) e.id: rnd.nextDouble()};
    _period = {
      for (final e in kEdges) e.id: math.max(3.4, kGeom[e.id]!.length / 105),
    };
    _editFocus.addListener(() {
      if (!_editFocus.hasFocus && _editing != null) _commitRename();
    });
    _transform.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(FlowPanoramaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact) {
      _resetZoom();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _clock.dispose();
    _editCtl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = (scale - 1).abs() > 0.04;
    if ((zoomed != _zoomed || (scale - _scale).abs() > 0.008) && mounted) {
      setState(() {
        _zoomed = zoomed;
        _scale = scale;
      });
    }
  }

  void _resetZoom() {
    if (_transform.value == Matrix4.identity()) return;
    _transform.value = Matrix4.identity();
  }

  void _zoomBy(double factor, [Offset? focal]) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(_minScale, _maxScale);
    final actual = next / current;
    if ((actual - 1).abs() < 0.0008) return;
    final matrix = _transform.value.clone();
    final point =
        focal ?? Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    if (_viewportSize != Size.zero || focal != null) {
      final scene = _transform.toScene(point);
      matrix
        ..translate(scene.dx, scene.dy)
        ..scale(actual)
        ..translate(-scene.dx, -scene.dy);
    } else {
      matrix.scale(actual);
    }
    _transform.value = matrix;
  }

  void _onDoubleTapZoom() {
    if (_zoomed) {
      _resetZoom();
      return;
    }
    _zoomBy(2, _doubleTapAt);
  }

  void _onWheelZoom(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 普通滚轮翻页；按住 Ctrl 才缩放，避免和提案页抢滑动。
    if (!HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      final factor = math.exp(-resolved.scrollDelta.dy / 420);
      _zoomBy(factor, resolved.localPosition);
    });
  }

  // —— 取值 ——
  FlowCtx get ctx => widget.ctx;

  String nodeName(NodeDef n) {
    if (n.editable) {
      final raw = (_customName[n.id] ?? n.fallback?.call(ctx) ?? '').trim();
      if (raw.isEmpty) return widget.canRename ? '点击填写' : '未填写';
      return raw;
    }
    return n.name?.call(ctx) ?? n.role;
  }

  bool _isPlaceholderName(NodeDef n) {
    final raw = (_customName[n.id] ?? n.fallback?.call(ctx) ?? '').trim();
    return raw.isEmpty;
  }

  FlowStatus statusOf(EdgeDef e) {
    return e.st?.call(ctx) ?? const FlowStatus(FlowLevel.ok, '正常流转');
  }

  // 聚焦对象：pin 优先于 hover（与 HTML 一致）
  String? get _focusEdge => _pinEdge ?? _hoverEdge;
  String? get _focusNode => _pinNode ?? _hoverNode;

  bool get _dimming =>
      _flow != null || _issueOnly || _focusEdge != null || _focusNode != null;

  bool _isActive(EdgeDef e) {
    final fe = _focusEdge, fn = _focusNode;
    if (fe != null) return e.id == fe;
    if (fn != null) {
      final touch = e.a.node == fn || e.b.node == fn;
      return touch && (_flow == null || e.kind == _flow);
    }
    if (_issueOnly && statusOf(e).level == FlowLevel.ok) return false;
    return _flow == null || e.kind == _flow;
  }

  /// 标注「完整展开」的条件：只有点选（pin）会展开，hover 不会——与 HTML 注释一致
  bool _isPinned(EdgeDef e) =>
      _pinEdge == e.id ||
      (_pinNode != null && (e.a.node == _pinNode || e.b.node == _pinNode));

  LabelParts _partsOf(EdgeDef e) {
    final bad = statusOf(e).level != FlowLevel.ok;
    final pinned = _isPinned(e);
    return LabelParts(
      name: _showName || pinned || _issueOnly,
      sub: _showSub || pinned,
      owner: _showOwner || pinned,
      issue: bad && (_showIssue || pinned || _issueOnly),
    );
  }

  Set<String> get _activeNodeIds {
    final s = <String>{};
    for (final e in kEdges) {
      if (_isActive(e)) {
        s.add(e.a.node);
        s.add(e.b.node);
      }
    }
    final fn = _focusNode;
    if (fn != null) s.add(fn);
    return s;
  }

  // —— 标签组装 + 避让 ——
  List<LabelBox> _buildLabels() {
    final boxes = <LabelBox>[];
    for (final e in kEdges) {
      if (!_isActive(e)) continue;
      final parts = _partsOf(e);
      if (!parts.any) continue;

      final st = statusOf(e);
      final tone = kLevel[st.level]!.color;
      final kind = kKind[e.kind]!;
      final ownerName = ctx.owner(e.own);

      var sub = parts.sub ? (e.sub?.call(ctx) ?? '') : '';
      if (sub.length > 14) sub = '${sub.substring(0, 14)}…';

      final spans = <TextSpan>[];
      if (parts.name) {
        spans.add(
          TextSpan(
            text: e.label(ctx),
            style: TextStyle(
              color: st.level == FlowLevel.ok ? const Color(0xFFEDE8F6) : tone,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }
      if (sub.isNotEmpty) {
        spans.add(
          TextSpan(
            text: '${spans.isEmpty ? '' : '  '}$sub',
            style: const TextStyle(
              color: Color(0xFF8F84A8),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        );
      }
      if (parts.issue) {
        spans.add(
          TextSpan(
            text:
                '${spans.isEmpty ? '' : '  '}${kLevel[st.level]!.name} · ${st.text}',
            style: TextStyle(
              color: tone,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }
      if (parts.owner) {
        spans.add(
          TextSpan(
            text: '${spans.isEmpty ? '' : '  '}$ownerName',
            style: const TextStyle(color: Color(0xFFB7ACCB), fontSize: 9.5),
          ),
        );
      }
      if (spans.isEmpty) continue;

      final tp = TextPainter(
        text: TextSpan(children: spans),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      boxes.add(
        LabelBox(
          edgeId: e.id,
          painter: tp,
          showAvatar: parts.owner,
          initial: ownerName.isEmpty ? '·' : ownerName.substring(0, 1),
          tone: tone,
          kindColor: kind.color,
          level: st.level,
          pinned: _isPinned(e),
          baseT: e.t,
        ),
      );
    }

    _layout(boxes);
    return boxes;
  }

  /// 与 HTML 版一致的避让：
  ///   主体卡片是硬障碍 → 放不下先「降级为只留头像」→ 再放不下才隐藏；
  ///   异常链路永远给一个最不挡人的位置，不降级也不隐藏。
  void _layout(List<LabelBox> boxes) {
    final placed = <Rect>[for (final n in kNodes) n.rect.inflate(4)];

    int rank(LabelBox b) => b.level == FlowLevel.block
        ? 0
        : b.level == FlowLevel.warn
        ? 1
        : 2;
    // 加索引做 tie-break，保证与 JS 的稳定排序一致
    final indexed =
        [for (var i = 0; i < boxes.length; i++) MapEntry(i, boxes[i])]
          ..sort((x, y) {
            final r = rank(x.value).compareTo(rank(y.value));
            return r != 0 ? r : x.key.compareTo(y.key);
          });

    const deltas = [0.0, -0.09, 0.09, -0.16, 0.16, -0.24, 0.24, -0.32, 0.32];
    const shifts = [0.0, -26.0, 26.0, -50.0, 50.0];

    bool hits(Rect a, Rect b) =>
        !(a.right + 6 < b.left ||
            b.right + 6 < a.left ||
            a.bottom + 4 < b.top ||
            b.bottom + 4 < a.top);

    for (final entry in indexed) {
      final box = entry.value;
      final g = kGeom[box.edgeId]!;
      final bad = box.level != FlowLevel.ok;
      final rows = bad ? [...shifts, -80.0, 80.0, -112.0, 112.0] : shifts;

      Offset? attempt() {
        Offset? bestC;
        double bestCost = double.infinity;
        for (final dy in rows) {
          for (final delta in deltas) {
            final t = box.baseT + delta;
            if (t < 0.06 || t > 0.94) continue;
            final p = g.at(t) + Offset(0, dy);
            final w = box.width, h = box.height;
            if (p.dy < h / 2 + 8 || p.dy > kFlowH - h / 2 - 8) continue;
            if (p.dx < w / 2 + 4 || p.dx > kFlowW - w / 2 - 4) continue;
            final r = Rect.fromCenter(center: p, width: w, height: h);
            if (!placed.any((o) => hits(o, r))) return p;
            if (bad) {
              double cost = 0;
              for (final o in placed) {
                final i = o.intersect(r);
                if (i.width > 0 && i.height > 0) cost += i.width * i.height;
              }
              if (cost < bestCost) {
                bestCost = cost;
                bestC = p;
              }
            }
          }
        }
        return bad ? bestC : null;
      }

      var chosen = attempt();
      if (chosen == null && !box.compact) {
        box.compact = true; // 降级：只留头像
        chosen = attempt();
      }
      if (chosen == null) {
        box.visible = false;
        continue;
      }
      box.center = chosen;
      placed.add(box.rect);
    }
    boxes.removeWhere((b) => !b.visible);
  }

  // —— 交互 ——
  String? _edgeAt(Offset p) {
    String? hit;
    double best = 16;
    for (final e in kEdges) {
      if (!_isActive(e)) continue;
      for (final s in kGeom[e.id]!.samples) {
        final d = (s - p).distance;
        if (d < best) {
          best = d;
          hit = e.id;
        }
      }
    }
    return hit;
  }

  void _tapCanvas(Offset p) {
    if (_editing != null) {
      _commitRename();
      return;
    }
    final hit = _edgeAt(p);
    setState(() {
      if (hit == null) {
        _pinEdge = null;
        _pinNode = null;
      } else if (_pinEdge == hit) {
        _pinEdge = null;
      } else {
        _pinEdge = hit;
        _pinNode = null;
      }
    });
  }

  void _hoverCanvas(Offset p) {
    final hit = _edgeAt(p);
    if (hit != _hoverEdge) setState(() => _hoverEdge = hit);
  }

  void _tapNode(NodeDef n) {
    if (_editing != null && _editing != n.id) _commitRename();
    setState(() {
      _pinNode = n.id;
      _pinEdge = null;
    });
    if (n.editable && widget.canRename) _startRename(n);
  }

  void _startRename(NodeDef n) {
    if (!n.editable || !widget.canRename) return;
    final raw = (_customName[n.id] ?? n.fallback?.call(ctx) ?? '').trim();
    setState(() {
      _editing = n.id;
      _pinNode = n.id;
      _pinEdge = null;
      _editCtl.text = raw;
      _editCtl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editCtl.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _editFocus.requestFocus(),
    );
  }

  void _commitRename() {
    final id = _editing;
    if (id == null) return;
    final v = _editCtl.text.trim();
    setState(() {
      if (v.isEmpty) {
        _customName.remove(id);
      } else {
        _customName[id] = v;
      }
      _editing = null;
    });
    widget.onNodeRenamed?.call(id, v);
  }

  void _syncClock() {
    final want = _anim && TickerMode.of(context);
    if (want && !_clock.isAnimating) _clock.repeat();
    if (!want && _clock.isAnimating) _clock.stop();
  }

  void _clearPin() {
    if (_pinEdge != null || _pinNode != null) {
      setState(() {
        _pinEdge = null;
        _pinNode = null;
      });
    }
  }

  void _openFullscreen() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FlowPanoramaFullscreenPage(
          ctx: widget.ctx,
          canRename: widget.canRename,
          onNodeRenamed: widget.onNodeRenamed,
        ),
      ),
    );
  }

  Widget _fullscreenFab() {
    return Material(
      color: const Color(0xCC2B2340),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _openFullscreen,
        borderRadius: BorderRadius.circular(10),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.fullscreen, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  // —— 构建 ——
  @override
  Widget build(BuildContext context) {
    final counts = <FlowLevel, int>{
      FlowLevel.ok: 0,
      FlowLevel.warn: 0,
      FlowLevel.block: 0,
    };
    for (final e in kEdges) {
      final l = statusOf(e).level;
      counts[l] = counts[l]! + 1;
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _clearPin();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: !widget.compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(),
              const SizedBox(height: 10),
              if (widget.immersive)
                Expanded(child: ClipRect(child: _canvasViewport(counts)))
              else ...[
                _canvasViewport(counts),
                const SizedBox(height: 12),
                _detail(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvasViewport(Map<FlowLevel, int> counts) {
    return LayoutBuilder(
      builder: (c, box) {
        final canvas = SizedBox(
          width: kFlowW,
          height: kFlowH,
          child: _canvas(counts),
        );
        final fitted = FittedBox(fit: BoxFit.contain, child: canvas);
        final width = box.maxWidth.isFinite && box.maxWidth > 0
            ? box.maxWidth
            : kFlowW;
        final height = widget.immersive
            ? (box.maxHeight.isFinite && box.maxHeight > 0
                  ? box.maxHeight
                  : 420.0)
            : widget.compact
            ? math.max(300.0, math.min(width * kFlowH / kFlowW + 24, 520.0))
            : width * kFlowH / kFlowW;
        _viewportSize = Size(width, height);
        final viewer = _AbsorbParentScroll(
          absorbDrag: _zoomed || widget.immersive,
          onPointerSignal: widget.compact ? null : _onWheelZoom,
          child: GestureDetector(
            onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
            onDoubleTap: _onDoubleTapZoom,
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: _minScale,
              maxScale: _maxScale,
              boundaryMargin: const EdgeInsets.all(80),
              panEnabled: _zoomed || widget.immersive || widget.compact,
              scaleEnabled: widget.compact || widget.immersive,
              trackpadScrollCausesScale: false,
              child: SizedBox(width: width, height: height, child: fitted),
            ),
          ),
        );
        final viewport = widget.immersive || widget.compact
            ? SizedBox(width: width, height: height, child: viewer)
            : AspectRatio(aspectRatio: kFlowW / kFlowH, child: viewer);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF221B31)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF382A56).withOpacity(0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                viewport,
                if (widget.compact) _mobileZoomOverlay(),
                if (widget.allowFullscreen && !widget.compact)
                  Positioned(right: 10, top: 10, child: _fullscreenFab()),
              ],
            ),
          ),
        );
      },
    );
  }

  // ——— 工具栏 ———
  Widget _toolbar() {
    Widget tab(String text, FlowKind? k) {
      final on = _flow == k;
      final bg = k == null ? const Color(0xFF2E2740) : kKind[k]!.ink;
      return _Hoverable(
        builder: (hovering) => GestureDetector(
          onTap: () => setState(() => _flow = k),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: on
                  ? bg
                  : (hovering
                        ? const Color(0xFF7B5CD8).withOpacity(0.06)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(999),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2E2740).withOpacity(0.2),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 【已修正】未选中时是 currentColor（灰），不是流别彩色
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? Colors.white
                        : (hovering
                                  ? const Color(0xFF4B4159)
                                  : const Color(0xFF7A7086))
                              .withOpacity(0.9),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: on
                        ? Colors.white
                        : (hovering
                              ? const Color(0xFF4B4159)
                              : const Color(0xFF7A7086)),
                    fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget group(String title, List<Widget> children) => Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FC),
        border: Border.all(color: const Color(0xFFEAE3F1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFFA79DB5),
                fontFamily: 'monospace',
                letterSpacing: 0.6,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );

    Widget toggle(String text, bool value, ValueChanged<bool> onChanged) {
      return _Hoverable(
        builder: (hovering) => GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: value
                  ? const Color(0xFFEDE4FA)
                  : (hovering ? const Color(0xFFF2ECF8) : Colors.transparent),
              border: Border.all(
                color: value ? const Color(0xFFDCCDF3) : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? const Color(0xFF7B5CD8) : Colors.transparent,
                    border: Border.all(
                      color: value
                          ? const Color(0xFF7B5CD8)
                          : const Color(0xFFC4B9D2),
                      width: 1.5,
                    ),
                    boxShadow: value
                        ? [
                            BoxShadow(
                              color: const Color(0xFF7B5CD8).withOpacity(0.18),
                              blurRadius: 0,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: value
                        ? const Color(0xFF5B3FA8)
                        : (hovering
                              ? const Color(0xFF5B5069)
                              : const Color(0xFF8B8098)),
                    fontWeight: value ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F6FB),
            border: Border.all(color: const Color(0xFFE7E0EE)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 2,
            runSpacing: 4,
            children: [
              tab('全景大流转', null),
              tab('货物流', FlowKind.goods),
              tab('资金流', FlowKind.fund),
              tab('发票流', FlowKind.invoice),
              tab('信息流', FlowKind.info),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            group('标注', [
              toggle('环节名称', _showName, (v) => setState(() => _showName = v)),
              toggle('参数', _showSub, (v) => setState(() => _showSub = v)),
              toggle('责任人', _showOwner, (v) => setState(() => _showOwner = v)),
              toggle('异常说明', _showIssue, (v) => setState(() => _showIssue = v)),
            ]),
            group('视图', [
              toggle('只看异常', _issueOnly, (v) => setState(() => _issueOnly = v)),
              toggle('分区', _zones, (v) => setState(() => _zones = v)),
              toggle(
                '流动',
                _anim,
                (v) => setState(() {
                  _anim = v;
                  _syncClock();
                }),
              ),
            ]),
            group('缩放', [
              toggle('−', false, (_) => _zoomBy(1 / 1.25)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${(_scale * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF5B5069),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              toggle('＋', false, (_) => _zoomBy(1.25)),
              if (_zoomed) toggle('复位', true, (_) => _resetZoom()),
              if (widget.allowFullscreen)
                toggle('全屏', false, (_) => _openFullscreen()),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _mobileZoomOverlay() {
    Widget btn(IconData icon, VoidCallback onTap, {String? tooltip}) {
      return Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      );
    }

    return Positioned(
      right: 10,
      bottom: 12,
      child: Material(
        color: const Color(0xCC2B2340),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(Icons.add, () => _zoomBy(1.25), tooltip: '放大'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${(_scale * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xFFE4DCF2),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              btn(Icons.remove, () => _zoomBy(1 / 1.25), tooltip: '缩小'),
              btn(Icons.center_focus_strong, _resetZoom, tooltip: '复位'),
              if (widget.allowFullscreen)
                btn(Icons.fullscreen, _openFullscreen, tooltip: '全屏'),
            ],
          ),
        ),
      ),
    );
  }

  // ——— 画布 ———
  Widget _canvas(Map<FlowLevel, int> counts) {
    final labels = _buildLabels();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF171223),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF241D36), Color(0xFF151020)],
        ),
      ),
      child: Stack(
        children: [
          // 背景光晕：radial-gradient(ellipse 60% 50% at 14% 4%) / (50% 45% at 92% 96%)
          Positioned.fill(child: CustomPaint(painter: _BackdropPainter())),
          // 网格 + 分区 + 连线 + 标注
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (_, __) => MouseRegion(
                onHover: (e) => _hoverCanvas(e.localPosition),
                onExit: (_) => setState(() => _hoverEdge = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _tapCanvas(d.localPosition),
                  child: CustomPaint(
                    painter: _FlowPainter(
                      seconds: _clock.value * 120,
                      animate: _anim,
                      zones: _zones,
                      active: {for (final e in kEdges) e.id: _isActive(e)},
                      levels: {for (final e in kEdges) e.id: statusOf(e).level},
                      dimming: _dimming,
                      labels: labels,
                      phase: _phase,
                      period: _period,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 主体卡片（永远在连线与标注之上）
          for (final n in kNodes) _nodeCard(n),
          // 顶栏 / 底栏（带渐变遮罩）
          _topBar(counts),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _nodeCard(NodeDef n) {
    final actives = _activeNodeIds;
    final dim = _dimming && !actives.contains(n.id);
    final pinned = _pinNode == n.id;

    return Positioned(
      left: n.x,
      top: n.y,
      width: n.w,
      height: n.h,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: dim ? 0.34 : 1,
        child: _Hoverable(
          onEnter: () => setState(() => _hoverNode = n.id),
          onExit: () => setState(() => _hoverNode = null),
          builder: (hovering) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.translationValues(0, hovering ? -2 : 0, 0),
            child: GestureDetector(
              onTap: () => _tapNode(n),
              onLongPress: n.editable && widget.canRename
                  ? () => _startRename(n)
                  : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(17, 14, 16, 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: const Alignment(-0.7, -1),
                    end: const Alignment(0.7, 1),
                    colors: n.hub
                        ? [const Color(0xF7564484), const Color(0xF72D2346)]
                        : [const Color(0xF7342B4A), const Color(0xF7211A31)],
                  ),
                  border: Border.all(
                    color: pinned
                        ? const Color(0xFFB8A4E8).withOpacity(0.75)
                        : hovering
                        ? Colors.white.withOpacity(0.26)
                        : n.hub
                        ? const Color(0xFFB8A4E8).withOpacity(0.4)
                        : Colors.white.withOpacity(0.11),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        pinned
                            ? 0.45
                            : (hovering ? 0.44 : (n.hub ? 0.42 : 0.34)),
                      ),
                      blurRadius: pinned ? 44 : (n.hub ? 46 : 34),
                      offset: const Offset(0, 16),
                    ),
                    if (pinned)
                      BoxShadow(
                        color: const Color(0xFFB8A4E8).withOpacity(0.35),
                        blurRadius: 0,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: n.w - 33,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.role,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF8A7EA5),
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.7,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(right: 30),
                                child: _editing == n.id
                                    ? _inlineEditor(n)
                                    : GestureDetector(
                                        onTap: n.editable && !widget.compact
                                            ? () => _startRename(n)
                                            : () => _tapNode(n),
                                        onDoubleTap:
                                            n.editable && widget.canRename
                                            ? () => _startRename(n)
                                            : null,
                                        child: MouseRegion(
                                          cursor: n.editable
                                              ? SystemMouseCursors.text
                                              : SystemMouseCursors.click,
                                          child: Tooltip(
                                            message: n.editable
                                                ? (widget.compact
                                                      ? '长按可改写主体名称'
                                                      : '点击可改写主体名称')
                                                : nodeName(n),
                                            waitDuration: const Duration(
                                              milliseconds: 500,
                                            ),
                                            child: Text(
                                              nodeName(n),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: n.hub ? 17 : 14,
                                                height: 1.3,
                                                color: _isPlaceholderName(n)
                                                    ? const Color(0xFFB8A4E8)
                                                    : const Color(0xFFF4F1FA),
                                                fontWeight: FontWeight.w500,
                                                decoration:
                                                    n.editable &&
                                                        widget.canRename
                                                    ? TextDecoration.underline
                                                    : TextDecoration.none,
                                                decorationColor: const Color(
                                                  0x66B8A4E8,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              if (n.meta != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  n.meta!(ctx),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.35,
                                    color: Color(0xFF8A7EA5),
                                  ),
                                ),
                              ],
                              if (n.rows != null) ...[
                                const SizedBox(height: 9),
                                for (final r in n.rows!(ctx))
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          r[0],
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFB8ACD0),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Text(
                                            r[1],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: Color(0xFFF2ECFB),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: n.accent.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.32),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(n.icon, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 内联改名（等价于 HTML 的 contenteditable，回车 / 失焦提交）
  Widget _inlineEditor(NodeDef n) {
    return SizedBox(
      height: n.hub ? 24 : 21,
      child: TextField(
        controller: _editCtl,
        focusNode: _editFocus,
        cursorColor: const Color(0xFFB8A4E8),
        onSubmitted: (_) => _commitRename(),
        style: TextStyle(
          fontSize: n.hub ? 17 : 14,
          height: 1.3,
          color: const Color(0xFFF4F1FA),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: '输入机构名称',
          hintStyle: const TextStyle(color: Color(0xFF8A7EA5), fontSize: 13),
          contentPadding: EdgeInsets.zero,
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xB3B8A4E8)),
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xB3B8A4E8)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xB3B8A4E8)),
          ),
        ),
      ),
    );
  }

  Widget _topBar(Map<FlowLevel, int> counts) {
    Widget pill(FlowLevel l) {
      final s = kLevel[l]!;
      final hot = l == FlowLevel.block && counts[l]! > 0;
      return Container(
        margin: const EdgeInsets.only(left: 7),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF171222).withOpacity(0.8),
          border: Border.all(
            color: hot
                ? const Color(0xFFF08A8A).withOpacity(0.45)
                : Colors.white.withOpacity(0.09),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: s.color),
            ),
            const SizedBox(width: 6),
            Text(
              '${s.name} ${counts[l]}',
              style: TextStyle(
                fontSize: 9.5,
                fontFamily: 'monospace',
                color: hot ? const Color(0xFFF3B3B3) : const Color(0xFFB5AAC9),
              ),
            ),
          ],
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 46,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF100C18).withOpacity(0.78),
                const Color(0xFF100C18).withOpacity(0),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              // 绿色脉冲点（livePulse）
              AnimatedBuilder(
                animation: _clock,
                builder: (_, __) => CustomPaint(
                  size: const Size(17, 17),
                  painter: _PulseDotPainter(
                    t: ((_clock.value * 120) / 1.8) % 1.0,
                    color: const Color(0xFF8FD1A6),
                    radius: 3.5,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                '提案全链路 · 四流实时串联',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFCFC4E2),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${kNodes.length} 个主体 · ${kEdges.length} 条链路',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontFamily: 'monospace',
                  color: Color(0xFF7E7295),
                ),
              ),
              const Spacer(),
              pill(FlowLevel.ok),
              pill(FlowLevel.warn),
              pill(FlowLevel.block),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: widget.compact ? 56 : 42,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                const Color(0xFF0E0A15).withOpacity(0.82),
                const Color(0xFF0E0A15).withOpacity(0),
              ],
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 12 : 18,
            8,
            widget.compact ? 56 : 18,
            8,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in FlowKind.values) ...[
                  Container(
                    width: 18,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: kKind[k]!.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    kKind[k]!.name,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF948AA8),
                    ),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 4),
                    Text(
                      kKind[k]!.desc,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6E6486),
                      ),
                    ),
                  ],
                  const SizedBox(width: 16),
                ],
                Text(
                  widget.compact
                      ? '拖动查看 · 双指缩放 · 右下角可全屏'
                      : '点击补贴方 / 清算 / 开票 / 承接机构即可填写',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    color: Color(0xFF6E6486),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ——— 下方链路清单 ———
  Widget _detail() {
    Widget column(FlowKind k) {
      final kind = kKind[k]!;
      final lane = kEdges.where((e) => e.kind == k).toList();
      final bad = lane.where((e) => statusOf(e).level != FlowLevel.ok).length;
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        // 【已补】非当前流的整列变淡
        opacity: _flow == null || _flow == k ? 1 : 0.42,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFBFD),
            border: Border.all(color: const Color(0xFFEAE3F0)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: kind.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    kind.name,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3F3748),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${lane.length} 条${bad > 0 ? ' · $bad 异常' : ''}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: Color(0xFFA097AB),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 9),
                child: Divider(height: 1, color: Color(0xFFF0EAF5)),
              ),
              for (final e in lane) _detailItem(e, kind),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (c, box) {
        final cols = box.maxWidth > 1150 ? 4 : (box.maxWidth > 620 ? 2 : 1);
        final w = (box.maxWidth - 10 * (cols - 1)) / cols;
        final all = FlowKind.values;
        final rows = <Widget>[];
        for (var i = 0; i < all.length; i += cols) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < math.min(i + cols, all.length); j++) ...[
                    if (j > i) const SizedBox(width: 10),
                    SizedBox(width: w, child: column(all[j])),
                  ],
                ],
              ),
            ),
          );
          if (i + cols < all.length) rows.add(const SizedBox(height: 10));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }

  Widget _detailItem(EdgeDef e, KindStyle kind) {
    final st = statusOf(e);
    final tone = kLevel[st.level]!;
    final owner = ctx.owner(e.own);
    // 【已补】.act 规则与 HTML 一致：在筛选/聚焦状态下、且该链路处于激活集合中
    final act =
        _isActive(e) &&
        (_focusEdge != null || _focusNode != null || _flow != null);
    final hovering = _hoverItem == e.id;
    final highlight = act || hovering;

    Color bg;
    Color border;
    if (st.level == FlowLevel.block) {
      bg = const Color(0xFFFEF7F7);
      border = const Color(0xFFF1D2D2);
    } else if (st.level == FlowLevel.warn) {
      bg = const Color(0xFFFEFBF5);
      border = const Color(0xFFEFDCBB);
    } else {
      bg = highlight ? const Color(0xFFF6F2FB) : Colors.transparent;
      border = highlight ? const Color(0xFFE4DAEF) : Colors.transparent;
    }

    return _Hoverable(
      onEnter: () => setState(() {
        _hoverItem = e.id;
        _hoverEdge = e.id;
      }),
      onExit: () => setState(() {
        if (_hoverItem == e.id) _hoverItem = null;
        if (_hoverEdge == e.id) _hoverEdge = null;
      }),
      builder: (_) => GestureDetector(
        onTap: () => setState(() {
          _pinEdge = _pinEdge == e.id ? null : e.id;
          _pinNode = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    nodeName(kNodeById[e.a.node]!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF3B3345),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_right_alt,
                    size: 13,
                    color: Color(0xFFB0A5BE),
                  ),
                  Text(
                    nodeName(kNodeById[e.b.node]!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF3B3345),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: kind.chip,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      e.label(ctx),
                      style: TextStyle(
                        fontSize: 8.5,
                        fontFamily: 'monospace',
                        color: kind.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment(-0.7, -1),
                        end: Alignment(0.7, 1),
                        colors: [Color(0xFFB7A3E0), Color(0xFF7B5CD8)],
                      ),
                    ),
                    child: Text(
                      owner.isEmpty ? '·' : owner.substring(0, 1),
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    owner,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF5D5468),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    kOwnerRole[e.own] ?? '责任人',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFA097AB),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tone.chip,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tone.color,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          tone.name,
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: tone.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  children: [
                    if (st.level != FlowLevel.ok) ...[
                      TextSpan(
                        text: st.text,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.45,
                          color: tone.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(
                        text: ' ｜ ',
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.45,
                          color: Color(0xFF8C8296),
                        ),
                      ),
                    ],
                    TextSpan(
                      text: e.note?.call(ctx) ?? '',
                      style: const TextStyle(
                        fontSize: 9.5,
                        height: 1.45,
                        color: Color(0xFF8C8296),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  8. 小工具：hover 包装
// ============================================================================

class _PulseDotPainter extends CustomPainter {
  _PulseDotPainter({
    required this.t,
    required this.color,
    required this.radius,
  });
  final double t;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      radius + p * 7,
      Paint()..color = color.withOpacity(0.35 * (1 - p)),
    );
    canvas.drawCircle(c, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PulseDotPainter old) => old.t != t;
}

/// APP：手指按在画布上时吃掉外层纵滚。
/// PC：默认不拦截滚轮和拖拽；只有 Ctrl+滚轮、或已放大后的拖拽才接管。
class _AbsorbParentScroll extends StatelessWidget {
  const _AbsorbParentScroll({
    required this.child,
    this.onPointerSignal,
    this.absorbDrag = true,
  });
  final Widget child;
  final void Function(PointerSignalEvent event)? onPointerSignal;
  final bool absorbDrag;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: absorbDrag
          ? (_) {
              Scrollable.maybeOf(context)?.position.hold(() {});
            }
          : null,
      onPointerSignal: onPointerSignal,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => absorbDrag,
        child: child,
      ),
    );
  }
}

class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder, this.onEnter, this.onExit});
  final Widget Function(bool hovering) builder;
  final VoidCallback? onEnter, onExit;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _h = true);
        widget.onEnter?.call();
      },
      onExit: (_) {
        setState(() => _h = false);
        widget.onExit?.call();
      },
      child: widget.builder(_h),
    );
  }
}

// ============================================================================
//  9. 画布绘制：底纹、分区、连线、彗星流光、光珠、标注
// ============================================================================

/// 背景两团光晕 + 四周内阴影暗角（对应 .flowx-stage::before 与 inset shadow）
class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ellipse 60% x 50% at 14% 4%
    _ellipseGlow(
      canvas,
      size,
      const Offset(0.14, 0.04),
      0.60,
      0.50,
      const Color(0xFF8569CE),
      0.26,
    );
    // ellipse 50% x 45% at 92% 96%
    _ellipseGlow(
      canvas,
      size,
      const Offset(0.92, 0.96),
      0.50,
      0.45,
      const Color(0xFF3A7C8F),
      0.18,
    );

    // inset 0 0 80px rgba(0,0,0,.5)
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        size.center(Offset.zero),
        size.width * 0.62,
        [Colors.transparent, Colors.black.withOpacity(0.5)],
        [0.62, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vignette);
  }

  void _ellipseGlow(
    Canvas canvas,
    Size size,
    Offset at,
    double rx,
    double ry,
    Color color,
    double opacity,
  ) {
    final c = Offset(size.width * at.dx, size.height * at.dy);
    final rect = Rect.fromCenter(
      center: c,
      width: size.width * rx * 2,
      height: size.height * ry * 2,
    );
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        0.5,
        [color.withOpacity(opacity), Colors.transparent],
        [0.0, 0.6],
        ui.TileMode.clamp,
        (Matrix4.identity()
              ..translate(rect.center.dx, rect.center.dy)
              ..scale(rect.width, rect.height))
            .storage,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.seconds,
    required this.animate,
    required this.zones,
    required this.active,
    required this.levels,
    required this.dimming,
    required this.labels,
    required this.phase,
    required this.period,
  });

  final double seconds;
  final bool animate, zones, dimming;
  final Map<String, bool> active;
  final Map<String, FlowLevel> levels;
  final List<LabelBox> labels;
  final Map<String, double> phase, period;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (zones) _paintZones(canvas);
    _paintEdges(canvas);
    _paintLabels(canvas);
  }

  void _paintGrid(Canvas canvas, Size size) {
    // 【已修正】HTML 里网格是 rgba(255,255,255,.022) 再乘外层 opacity:.45
    final p = Paint()
      ..color = Colors.white.withOpacity(0.022 * 0.45)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _paintZones(Canvas canvas) {
    for (final z in kZones) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(z.x, z.y, z.w, z.h),
        const Radius.circular(20),
      );
      canvas.drawRRect(r, Paint()..color = Colors.white.withOpacity(0.018));
      _dashedRRect(canvas, r, Colors.white.withOpacity(0.07));

      final tp = TextPainter(
        text: TextSpan(
          text: z.label,
          style: const TextStyle(
            fontSize: 9.5,
            color: Color(0xFF8578A0),
            fontFamily: 'monospace',
            letterSpacing: 1.33,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(z.x + 22 - 10, z.y - 9, tp.width + 20, 18),
        const Radius.circular(999),
      );
      canvas.drawRRect(bg, Paint()..color = const Color(0xFF1E1730));
      tp.paint(canvas, Offset(z.x + 22, z.y - 9 + (18 - tp.height) / 2));
    }
  }

  void _dashedRRect(Canvas canvas, RRect r, Color color) {
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final n = math.min(d + 5, m.length);
        canvas.drawPath(m.extractPath(d, n), paint);
        d += 10;
      }
    }
  }

  void _paintEdges(Canvas canvas) {
    for (final e in kEdges) {
      final g = kGeom[e.id]!;
      final kind = kKind[e.kind]!;
      final level = levels[e.id] ?? FlowLevel.ok;
      final on = active[e.id] ?? true;
      final alpha = dimming ? (on ? 1.0 : 0.08) : 1.0;
      if (alpha <= 0.02) continue;

      // 光晕
      canvas.drawPath(
        g.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color =
              (level == FlowLevel.block ? const Color(0xFFF08A8A) : kind.color)
                  .withOpacity(
                    (level == FlowLevel.block
                            ? 0.26
                            : (on && dimming ? 0.22 : 0.13)) *
                        alpha,
                  ),
      );
      // 底线
      canvas.drawPath(
        g.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = kind.color.withOpacity(
            (on && dimming ? 0.95 : 0.5) * alpha,
          ),
      );
      // 箭头
      _arrow(canvas, g, kind.color.withOpacity(alpha));

      if (!animate) continue;

      if (level == FlowLevel.block) {
        // 卡顿：无彗星，光珠停在卡点呼吸（fxStall）
        final pos = g.at(e.t);
        final pulse = (math.sin(seconds * 4) + 1) / 2;
        canvas.drawCircle(
          pos,
          4.5 + pulse * 3,
          Paint()
            ..color = const Color(
              0xFFF08A8A,
            ).withOpacity((0.9 - pulse * 0.45) * alpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        canvas.drawCircle(
          pos,
          4.5,
          Paint()..color = const Color(0xFFF08A8A).withOpacity(alpha),
        );
        continue;
      }

      // 【已修正】预警链路的流光 opacity 是 .7，正常是 .95
      final flowOpacity = level == FlowLevel.warn ? 0.7 : 0.95;

      // 彗星拖尾 + 光珠
      final per = period[e.id] ?? 4;
      final ph = phase[e.id] ?? 0;
      final t = ((seconds / per) + ph) % 1.0;
      final head = g.length * t;
      final tail = math.min(120.0, math.max(52.0, g.length * 0.22));
      canvas.drawPath(
        g.segment(head - tail, head),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = kind.color.withOpacity(flowOpacity * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
      final dot = g.at(t);
      canvas.drawCircle(
        dot,
        6,
        Paint()
          ..color = kind.color.withOpacity(0.45 * flowOpacity * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        dot,
        3.5,
        Paint()..color = kind.color.withOpacity(flowOpacity * alpha),
      );
      canvas.drawCircle(
        dot,
        1.4,
        Paint()..color = Colors.white.withOpacity(0.55 * flowOpacity * alpha),
      );
    }
  }

  void _arrow(Canvas canvas, EdgeGeometry g, Color color) {
    final tan = g.metric.getTangentForOffset(g.length - 0.1);
    if (tan == null) return;
    final v = tan.vector;
    final ang = math.atan2(v.dy, v.dx);
    const len = 9.0;
    final tip = g.end;
    final p1 =
        tip - Offset(math.cos(ang - 0.45) * len, math.sin(ang - 0.45) * len);
    final p2 =
        tip - Offset(math.cos(ang + 0.45) * len, math.sin(ang + 0.45) * len);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      Paint()..color = color,
    );
  }

  void _paintLabels(Canvas canvas) {
    for (final b in labels) {
      // 卡顿标注的报警呼吸光环（fxAlarm）
      if (b.level == FlowLevel.block) {
        final p = (seconds / 2) % 1.0;
        final spread = Curves.easeOut.transform(math.min(p / 0.7, 1.0)) * 10;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            b.rect.inflate(spread),
            const Radius.circular(999),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(
              0xFFF08A8A,
            ).withOpacity(0.4 * (1 - math.min(p / 0.7, 1.0))),
        );
      }

      if (b.compact) {
        // 降级形态：只画头像，无胶囊底
        if (b.showAvatar) _avatar(canvas, b, b.center);
        continue;
      }

      final r = RRect.fromRectAndRadius(b.rect, const Radius.circular(999));
      final bg = b.level == FlowLevel.block
          ? const Color(0xFF2A1114).withOpacity(0.95)
          : b.level == FlowLevel.warn
          ? const Color(0xFF261A10).withOpacity(0.94)
          : const Color(0xFF130F1D).withOpacity(0.94);
      if (b.pinned) {
        canvas.drawRRect(
          r.inflate(1),
          Paint()
            ..color = Colors.black.withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      }
      canvas.drawRRect(r, Paint()..color = bg);
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = b.pinned
              ? const Color(0xFFB8A4E8).withOpacity(0.55)
              : (b.level == FlowLevel.ok
                    ? Colors.white.withOpacity(0.09)
                    : b.tone.withOpacity(0.6)),
      );

      double x = b.rect.left;
      if (b.showAvatar) {
        _avatar(canvas, b, Offset(x + 3 + LabelBox.avatar / 2, b.center.dy));
        x += 3 + LabelBox.avatar + LabelBox.gap;
      } else {
        x += 11;
      }
      b.painter.paint(canvas, Offset(x, b.center.dy - b.painter.height / 2));
    }
  }

  /// 头像：外圈流别/状态色 1px + 深底 2px + 渐变圆 + 姓氏
  void _avatar(Canvas canvas, LabelBox b, Offset c) {
    const r = LabelBox.avatar / 2;
    final ring = b.level == FlowLevel.ok ? b.kindColor : b.tone;
    canvas.drawCircle(c, r + 3, Paint()..color = ring);
    canvas.drawCircle(
      c,
      r + 2,
      Paint()..color = const Color(0xFF130F1D).withOpacity(0.95),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          c - const Offset(r, r),
          c + const Offset(r, r),
          [const Color(0xFF9B84CC), const Color(0xFF6A4FA0)],
        ),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: b.initial,
        style: const TextStyle(fontSize: 9, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => true;
}

class _FlowPanoramaFullscreenPage extends StatelessWidget {
  const _FlowPanoramaFullscreenPage({
    required this.ctx,
    required this.canRename,
    this.onNodeRenamed,
  });

  final FlowCtx ctx;
  final bool canRename;
  final void Function(String nodeId, String name)? onNodeRenamed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF241D36),
        foregroundColor: Colors.white,
        title: const Text('四流全屏'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FlowPanoramaSection(
            ctx: ctx,
            compact: MediaQuery.sizeOf(context).width < 700,
            canRename: canRename,
            allowFullscreen: false,
            immersive: true,
            onNodeRenamed: onNodeRenamed,
          ),
        ),
      ),
    );
  }
}
