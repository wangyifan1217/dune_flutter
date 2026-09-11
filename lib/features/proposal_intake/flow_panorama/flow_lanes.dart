import 'package:flutter/material.dart';

import '../proposal_intake_models.dart';
import 'flow_ctx.dart';
import 'flow_topology.dart';

/// 四流泳道布局。
///
/// 节点与链路集合仍然只来自 [kNodes] / [kEdges]（即「有表单字段支撑」的那一套），
/// 本文件不新增任何主体或链路，只负责把它们按流拆成四张独立画布的坐标。
const double kLaneNodeW = 168;
const double kLaneNodeH = 74;
const double kLaneW = 1140;

/// 主行基线：四条泳道的首行节点统一落在这个 y 上。
const double kLaneRowY = 104;

/// 信息流里「我方主体」下沉一行的 y。
const double kLaneRowY2 = 272;

class LaneNode {
  const LaneNode(this.id, this.x, this.y);

  final String id;
  final double x;
  final double y;

  Rect get rect => Rect.fromLTWH(x, y, kLaneNodeW, kLaneNodeH);
}

class LaneSeg {
  const LaneSeg(this.id, {this.off = 0});

  /// 对应 [kEdgeById] 的链路 id。
  final String id;

  /// 同向多线时的垂直错开量。
  final double off;
}

class FlowLaneDef {
  const FlowLaneDef({
    required this.kind,
    required this.height,
    required this.nodes,
    required this.segs,
  });

  final FlowKind kind;
  final double height;
  final List<LaneNode> nodes;
  final List<LaneSeg> segs;

  double get width => kLaneW;

  LaneNode? nodeAt(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

const List<FlowLaneDef> kFlowLanes = [
  FlowLaneDef(
    kind: FlowKind.goods,
    height: 250,
    nodes: [
      LaneNode('supplier', 24, kLaneRowY),
      LaneNode('hub', 330, kLaneRowY),
      LaneNode('tech', 636, kLaneRowY),
      LaneNode('channel', 942, kLaneRowY),
    ],
    segs: [LaneSeg('g1'), LaneSeg('g2'), LaneSeg('g3')],
  ),
  FlowLaneDef(
    kind: FlowKind.fund,
    height: 250,
    nodes: [
      LaneNode('supplier', 24, kLaneRowY),
      LaneNode('hub', 486, kLaneRowY),
      LaneNode('channel', 948, kLaneRowY),
    ],
    segs: [LaneSeg('f5'), LaneSeg('f4')],
  ),
  FlowLaneDef(
    kind: FlowKind.invoice,
    height: 250,
    nodes: [
      LaneNode('supplier', 24, kLaneRowY),
      LaneNode('hub', 486, kLaneRowY),
      LaneNode('channel', 948, kLaneRowY),
    ],
    segs: [LaneSeg('i1'), LaneSeg('isales')],
  ),
  FlowLaneDef(
    kind: FlowKind.info,
    height: 416,
    nodes: [
      LaneNode('supplier', 24, kLaneRowY),
      LaneNode('tech', 486, kLaneRowY),
      LaneNode('channel', 948, kLaneRowY),
      LaneNode('hub', 486, kLaneRowY2),
    ],
    segs: [LaneSeg('n2'), LaneSeg('n1'), LaneSeg('n4')],
  ),
];

/// 一条链路在泳道里的实际几何：起点、终点、是否竖直。
class LaneGeometry {
  const LaneGeometry(this.from, this.to, this.vertical);

  final Offset from;
  final Offset to;
  final bool vertical;

  Offset get mid => Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
}

/// 由两个节点矩形推出连线端点：同一行走左右边，跨行走上下边。
LaneGeometry laneGeometryOf(FlowLaneDef lane, LaneSeg seg) {
  final edge = kEdgeById[seg.id];
  final fallback = LaneGeometry(Offset.zero, Offset.zero, false);
  if (edge == null) return fallback;
  final a = lane.nodeAt(edge.a.node);
  final b = lane.nodeAt(edge.b.node);
  if (a == null || b == null) return fallback;

  final ra = a.rect;
  final rb = b.rect;
  if ((ra.center.dy - rb.center.dy).abs() < 1) {
    final y = ra.center.dy + seg.off;
    if (rb.center.dx > ra.center.dx) {
      return LaneGeometry(Offset(ra.right, y), Offset(rb.left, y), false);
    }
    return LaneGeometry(Offset(ra.left, y), Offset(rb.right, y), false);
  }
  final x = ra.center.dx + seg.off;
  if (rb.center.dy > ra.center.dy) {
    return LaneGeometry(Offset(x, ra.bottom), Offset(x, rb.top), true);
  }
  return LaneGeometry(Offset(x, ra.top), Offset(x, rb.bottom), true);
}

/// 四流节点/链路 → 上面表单取值格子。点图跳到这些字段并短暂高亮。
class FlowFieldJump {
  const FlowFieldJump(this.section, this.fieldKeys);

  final ProposalIntakeNavSection section;
  final List<String> fieldKeys;
}

const Map<String, FlowFieldJump> kFlowFieldJumps = {
  'supplier': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'purchaseCounterparty',
  ]),
  'hub': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'salesOurParty',
    'salesScale',
    'margin',
  ]),
  'channel': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'salesCounterparty',
  ]),
  'tech': FlowFieldJump(ProposalIntakeNavSection.tech, ['technologyPlatform']),
  'g1': FlowFieldJump(ProposalIntakeNavSection.finance, ['purchaseProducts']),
  'g2': FlowFieldJump(ProposalIntakeNavSection.tech, [
    'technologyCapabilities',
  ]),
  'g3': FlowFieldJump(ProposalIntakeNavSection.tech, ['outputForms']),
  'f4': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'channelSettleMode',
    'margin',
  ]),
  'f5': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'supplySettleMode',
    'supplyPayAccount',
  ]),
  'i1': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'supplyProducts',
    'purchaseCounterparty',
  ]),
  'isales': FlowFieldJump(ProposalIntakeNavSection.finance, [
    'salesInvoiceType',
    'productSalesSettle',
  ]),
  'n1': FlowFieldJump(ProposalIntakeNavSection.tech, ['outputForms']),
  'n2': FlowFieldJump(ProposalIntakeNavSection.tech, ['technologyPlatform']),
  'n4': FlowFieldJump(ProposalIntakeNavSection.tech, ['financeInterfaces']),
};
