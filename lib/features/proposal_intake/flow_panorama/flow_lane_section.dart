import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flow_ctx.dart';
import 'flow_lanes.dart';
import 'flow_topology.dart';

const Color _kBorder = Color(0xFFE4E8ED);
const Color _kDivider = Color(0xFFEDF0F3);
const Color _kInk = Color(0xFF16202B);
const Color _kMuted = Color(0xFF77828F);
const Color _kFaint = Color(0xFF8A94A0);

/// 画布排得开需要 1140px。窄于这个宽度就改用链路清单，
/// 手机上横向拖着看图是读不了的。
const double kFlowLaneListBreakpoint = 720;

/// 四流泳道视图：货 / 资金 / 发票 / 信息各一张白底画布。
///
/// 节点与链路仍然只来自 [kNodes] / [kEdges]，本组件不新增主体或链路，
/// 也不产生任何写死文案——所有文字都来自 [FlowCtx]。
class FlowLaneSection extends StatefulWidget {
  const FlowLaneSection({
    super.key,
    required this.ctx,
    this.compact = false,
    this.onSelect,
  });

  final FlowCtx ctx;
  final bool compact;
  final ValueChanged<String>? onSelect;

  @override
  State<FlowLaneSection> createState() => _FlowLaneSectionState();
}

class _FlowLaneSectionState extends State<FlowLaneSection> {
  FlowKind? _only;
  bool _issueOnly = false;
  final Set<FlowKind> _collapsed = <FlowKind>{};

  FlowCtx get _ctx => widget.ctx;

  FlowStatus _statusOf(EdgeDef e) =>
      e.st?.call(_ctx) ?? const FlowStatus(FlowLevel.ok, '正常');

  int get _issueCount {
    var n = 0;
    for (final e in kEdges) {
      if (_statusOf(e).level != FlowLevel.ok) n++;
    }
    return n;
  }

  List<LaneSeg> _segsOf(FlowLaneDef lane) {
    if (!_issueOnly) return lane.segs;
    return lane.segs.where((s) {
      final e = kEdgeById[s.id];
      if (e == null) return false;
      return _statusOf(e).level != FlowLevel.ok;
    }).toList();
  }

  static String _tidy(String value) {
    var text = value.trim();
    while (text.startsWith('·')) {
      text = text.substring(1).trim();
    }
    while (text.endsWith('·')) {
      text = text.substring(0, text.length - 1).trim();
    }
    return text;
  }

  String _nodeName(NodeDef? def) {
    if (def == null) return '—';
    final name = _tidy(def.name?.call(_ctx) ?? '');
    if (name.isNotEmpty) return name;
    final fallback = _tidy(def.fallback?.call(_ctx) ?? '');
    return fallback.isEmpty ? '—' : fallback;
  }

  String _nodeMeta(NodeDef? def) {
    if (def == null) return '';
    final rows = def.rows?.call(_ctx);
    if (rows != null && rows.isNotEmpty) {
      final parts = <String>[];
      for (final row in rows) {
        if (row.length < 2) continue;
        final value = _tidy(row[1]);
        if (value.isEmpty || value == '—') continue;
        parts.add('${row[0]} $value');
      }
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    return _tidy(def.meta?.call(_ctx) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final lanes = kFlowLanes
        .where((lane) => _only == null || _only == lane.kind)
        .toList();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolbar(),
          const SizedBox(height: 12),
          for (var i = 0; i < lanes.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _laneCard(lanes[i]),
          ],
        ],
      ),
    );
  }

  Widget _toolbar() {
    final issues = _issueCount;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _tab('全部', _only == null, null, () => setState(() => _only = null)),
        for (final kind in FlowKind.values)
          _tab(
            kKind[kind]!.name,
            _only == kind,
            kKind[kind]!.color,
            () => setState(() => _only = kind),
          ),
        _tab(
          '只看异常',
          _issueOnly,
          null,
          () => setState(() => _issueOnly = !_issueOnly),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            issues == 0 ? '全部正常' : '$issues 条待处理',
            style: TextStyle(
              fontSize: 12,
              color: issues == 0 ? _kFaint : kLevel[FlowLevel.block]!.ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(String label, bool active, Color? dot, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF2F5F8) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFFB9C4CF) : _kBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.2,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? _kInk : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _laneCard(FlowLaneDef lane) {
    final style = kKind[lane.kind]!;
    final segs = _segsOf(lane);
    final collapsed = _collapsed.contains(lane.kind);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _laneHeader(lane, style, segs.length, collapsed),
          if (!collapsed)
            segs.isEmpty
                ? _emptyHint()
                : LayoutBuilder(
                    builder: (context, box) =>
                        box.maxWidth < kFlowLaneListBreakpoint
                        ? _laneList(lane, segs)
                        : _laneCanvas(lane, segs),
                  ),
        ],
      ),
    );
  }

  Widget _laneHeader(
    FlowLaneDef lane,
    KindStyle style,
    int shown,
    bool collapsed,
  ) {
    final total = lane.segs.length;
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(lane.kind);
        } else {
          _collapsed.add(lane.kind);
        }
      }),
      child: Container(
        padding: EdgeInsets.fromLTRB(widget.compact ? 12 : 16, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(
              color: collapsed ? Colors.transparent : _kDivider,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: style.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              style.name,
              style: TextStyle(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: style.ink,
              ),
            ),
            const SizedBox(width: 10),
            if (widget.compact)
              const Spacer()
            else
              Expanded(
                child: Text(
                  style.desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: _kFaint),
                ),
              ),
            Text(
              shown == total ? '$total 条链路' : '$shown / $total 条',
              style: const TextStyle(fontSize: 11.5, color: _kFaint),
            ),
            const SizedBox(width: 6),
            Icon(
              collapsed ? Icons.expand_more : Icons.expand_less,
              size: 18,
              color: const Color(0xFF9AA4B0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Text(
        '本条流当前没有待处理链路',
        style: TextStyle(fontSize: 12.5, color: _kFaint),
      ),
    );
  }

  /// 窄屏形态：一条链路一行，不画图。
  ///
  /// 手机上把 1140px 的画布塞进 390px，只能横向拖着读，节点和标签都看不全。
  /// 清单保留同样的信息——起止主体、链路名、参数、责任人、状态——而且能直接点。
  Widget _laneList(FlowLaneDef lane, List<LaneSeg> segs) {
    final style = kKind[lane.kind]!;
    final edges = <EdgeDef>[];
    for (final seg in segs) {
      final edge = kEdgeById[seg.id];
      if (edge != null) edges.add(edge);
    }
    final rows = <Widget>[];
    for (var i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final isLast = i == edges.length - 1;
      final status = _statusOf(edge);
      final label = _tidy(edge.label(_ctx));
      final sub = _tidy(edge.sub?.call(_ctx) ?? '');
      final role = kOwnerRole[edge.own] ?? '';
      final owner = _ctx.owner(edge.own);
      final ownerText = role.isEmpty ? owner : '$role · $owner';
      rows.add(
        Semantics(
          button: widget.onSelect != null,
          child: InkWell(
            key: ValueKey('flow-lane-row-${edge.id}'),
            onTap: widget.onSelect == null
                ? null
                : () => widget.onSelect!(edge.id),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isLast ? Colors.transparent : _kDivider,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _listNodeChip(edge.a.node, lane.kind),
                            const Text(
                              '→',
                              style: TextStyle(fontSize: 12, color: _kFaint),
                            ),
                            _listNodeChip(edge.b.node, lane.kind),
                          ],
                        ),
                      ),
                      if (status.level != FlowLevel.ok) ...[
                        const SizedBox(width: 8),
                        _statusPill(status),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    label.isEmpty ? '—' : label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: style.ink,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: _kMuted,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      ownerText,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: _kFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _listNodeChip(String id, FlowKind kind) {
    final def = kNodeById[id];
    final style = kKind[kind]!;
    return GestureDetector(
      key: ValueKey('flow-lane-chip-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelect == null ? null : () => widget.onSelect!(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: style.color),
        ),
        child: Text(
          _nodeName(def),
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: style.ink,
          ),
        ),
      ),
    );
  }

  Widget _laneCanvas(FlowLaneDef lane, List<LaneSeg> segs) {
    final lines = <_LineSpec>[];
    final overlays = <Widget>[];
    for (final seg in segs) {
      final edge = kEdgeById[seg.id];
      if (edge == null) continue;
      final geo = laneGeometryOf(lane, seg);
      if (geo.from == geo.to) continue;
      final status = _statusOf(edge);
      final color = status.level == FlowLevel.ok
          ? kKind[lane.kind]!.color
          : kLevel[status.level]!.color;
      lines.add(_LineSpec(geo.from, geo.to, color));
      overlays.addAll(_edgeOverlays(edge, geo, status, lane.kind));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: lane.width,
        height: lane.height,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _LanePainter(lines))),
            for (final node in lane.nodes) _nodeCard(node, lane.kind),
            ...overlays,
          ],
        ),
      ),
    );
  }

  Widget _nodeCard(LaneNode pos, FlowKind kind) {
    final def = kNodeById[pos.id];
    final style = kKind[kind]!;
    final meta = _nodeMeta(def);
    return Positioned(
      left: pos.x,
      top: pos.y,
      width: kLaneNodeW,
      height: kLaneNodeH,
      child: MouseRegion(
        cursor: widget.onSelect == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('flow-lane-node-${pos.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect == null
              ? null
              : () => widget.onSelect!(pos.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: style.color),
            ),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              def?.role ?? pos.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, height: 1.2, color: style.ink),
            ),
            const SizedBox(height: 3),
            Text(
              _nodeName(def),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: _kInk,
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: _kMuted,
                ),
              ),
            ],
          ],
        ),
          ),
        ),
      ),
    );
  }

  List<Widget> _edgeOverlays(
    EdgeDef edge,
    LaneGeometry geo,
    FlowStatus status,
    FlowKind kind,
  ) {
    final style = kKind[kind]!;
    final label = _tidy(edge.label(_ctx));
    final sub = _tidy(edge.sub?.call(_ctx) ?? '');
    final note = _tidy(edge.note?.call(_ctx) ?? '');
    final role = kOwnerRole[edge.own] ?? '';
    final owner = _ctx.owner(edge.own);
    final ownerText = role.isEmpty ? owner : '$role · $owner';

    final title = Column(
      crossAxisAlignment:
          geo.vertical ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.isEmpty ? '—' : label,
          textAlign: geo.vertical ? TextAlign.left : TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: style.ink,
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            sub,
            textAlign: geo.vertical ? TextAlign.left : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.2,
              color: _kMuted,
            ),
          ),
        ],
      ],
    );

    final metaRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          geo.vertical ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            ownerText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, height: 1.2, color: _kFaint),
          ),
        ),
        if (status.level != FlowLevel.ok) ...[
          const SizedBox(width: 6),
          _statusPill(status),
        ],
      ],
    );

    final titleBox = Tooltip(
      message: note.isEmpty ? (label.isEmpty ? '—' : label) : note,
      waitDuration: const Duration(milliseconds: 350),
      child: title,
    );

    Widget tap(Widget child, {String suffix = ''}) {
      return MouseRegion(
        cursor: widget.onSelect == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('flow-lane-edge-${edge.id}$suffix'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect == null
              ? null
              : () => widget.onSelect!(edge.id),
          child: child,
        ),
      );
    }

    if (geo.vertical) {
      return [
        Positioned(
          left: geo.mid.dx + 14,
          top: geo.mid.dy - 14,
          width: 260,
          child: tap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [titleBox, const SizedBox(height: 4), metaRow],
            ),
          ),
        ),
      ];
    }

    final centerX = geo.mid.dx;
    final rowTop = geo.from.dy - kLaneNodeH / 2;
    final rowBottom = geo.from.dy + kLaneNodeH / 2;
    return [
      Positioned(
        left: centerX - 120,
        top: rowTop - 66,
        width: 240,
        height: 62,
        child: tap(Align(alignment: Alignment.bottomCenter, child: titleBox)),
      ),
      Positioned(
        left: centerX - 120,
        top: rowBottom + 10,
        width: 240,
        child: tap(metaRow, suffix: '-meta'),
      ),
    ];
  }

  Widget _statusPill(FlowStatus status) {
    final level = kLevel[status.level]!;
    return Tooltip(
      message: status.text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: level.chip,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          level.name,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: level.ink,
          ),
        ),
      ),
    );
  }
}

class _LineSpec {
  const _LineSpec(this.a, this.b, this.color);

  final Offset a;
  final Offset b;
  final Color color;
}

class _LanePainter extends CustomPainter {
  const _LanePainter(this.lines);

  final List<_LineSpec> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final dx = line.b.dx - line.a.dx;
      final dy = line.b.dy - line.a.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length < 2) continue;
      final ux = dx / length;
      final uy = dy / length;
      const head = 9.0;
      final base = Offset(line.b.dx - ux * head, line.b.dy - uy * head);

      final stroke = Paint()
        ..color = line.color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(line.a, base, stroke);

      final arrow = Path()
        ..moveTo(line.b.dx, line.b.dy)
        ..lineTo(base.dx - uy * 4.2, base.dy + ux * 4.2)
        ..lineTo(base.dx + uy * 4.2, base.dy - ux * 4.2)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LanePainter oldDelegate) => true;
}
