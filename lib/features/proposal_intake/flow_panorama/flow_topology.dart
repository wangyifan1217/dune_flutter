import 'package:flutter/material.dart';

import 'flow_ctx.dart';

const double kFlowW = 1400;
const double kFlowH = 840;

class ZoneDef {
  const ZoneDef(this.x, this.y, this.w, this.h, this.label);
  final double x, y, w, h;
  final String label;
}

const List<ZoneDef> kZones = [
  ZoneDef(24, 110, 284, 470, '上游 · 供给'),
  ZoneDef(450, 76, 380, 674, '我方 · 主体与中台'),
  ZoneDef(1000, 110, 364, 520, '渠道'),
];

class NodeDef {
  const NodeDef({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.role,
    required this.icon,
    required this.accent,
    this.hub = false,
    this.editable = false,
    this.name,
    this.meta,
    this.fallback,
    this.rows,
  });

  final String id;
  final double x, y, w, h;
  final String role;
  final IconData icon;
  final Color accent;
  final bool hub, editable;
  final String Function(FlowCtx c)? name;
  final String Function(FlowCtx c)? meta;
  final String Function(FlowCtx c)? fallback;
  final List<List<String>> Function(FlowCtx c)? rows;

  Rect get rect => Rect.fromLTWH(x, y, w, h);
  Offset get center => rect.center;
}

final List<NodeDef> kNodes = [
  NodeDef(
    id: 'supplier',
    x: 46,
    y: 300,
    w: 240,
    h: 92,
    role: '供给方 · 采购对方',
    icon: Icons.factory_outlined,
    accent: const Color(0xFF6E9A63),
    name: (c) => c.purchaseTheirs,
    meta: (c) => '${c.purchaseName} · ${c.purchaseNo}',
  ),
  NodeDef(
    id: 'tech',
    x: 500,
    y: 100,
    w: 280,
    h: 92,
    role: '科技中台 · 接口',
    icon: Icons.code,
    accent: const Color(0xFF4E93A8),
    name: (c) => c.tau1,
    meta: (c) => c.outputs.join('、'),
  ),
  NodeDef(
    id: 'hub',
    x: 470,
    y: 350,
    w: 340,
    h: 160,
    role: '我方主体 · 提案发起',
    icon: Icons.account_balance,
    accent: const Color(0xFF8B6EC2),
    hub: true,
    name: (c) => c.salesOurs,
    rows: (c) => [
      ['采购签约', c.purchaseOurs],
      ['销售签约', c.salesOurs],
      ['年规模 / 毛利', c.hubScaleMarginText],
    ],
  ),
  NodeDef(
    id: 'channel',
    x: 1040,
    y: 150,
    w: 240,
    h: 92,
    role: '渠道主体 · 销售对方',
    icon: Icons.groups_outlined,
    accent: const Color(0xFF6C7BD6),
    name: (c) => c.salesTheirs,
    meta: (c) => '${c.channelMode} · ${c.channelCycle}',
  ),
];

final Map<String, NodeDef> kNodeById = {for (final n in kNodes) n.id: n};

class Anchor {
  const Anchor(this.node, this.side, [this.off = 0]);
  final String node;
  final String side;
  final double off;
}

class EdgeDef {
  EdgeDef({
    required this.id,
    required this.kind,
    required this.own,
    required this.a,
    required this.b,
    required this.label,
    this.d = const [90, 90],
    this.c,
    this.t = 0.5,
    this.sub,
    this.note,
    this.st,
  });

  final String id;
  final FlowKind kind;
  final String own;
  final Anchor a, b;
  final String Function(FlowCtx c) label;
  final List<double> d;
  final List<Offset>? c;
  final double t;
  final String Function(FlowCtx c)? sub;
  final String Function(FlowCtx c)? note;
  final FlowStatus? Function(FlowCtx c)? st;
}

String _join(List<String> items) => items.join('、');

final List<EdgeDef> kEdges = [
  EdgeDef(
    id: 'g1',
    kind: FlowKind.goods,
    own: 'market1',
    a: const Anchor('supplier', 'R', -30),
    b: const Anchor('hub', 'L', -66),
    d: const [100, 100],
    t: 0.3,
    label: (c) => _join(c.purchaseProducts),
    sub: (c) => c.purchaseNo,
    note: (c) =>
        '${_join(c.purchaseProducts)} 由 ${c.purchaseTheirs} 供给至 ${c.purchaseOurs}',
  ),
  EdgeDef(
    id: 'g2',
    kind: FlowKind.goods,
    own: 'tech',
    a: const Anchor('hub', 'T', -90),
    b: const Anchor('tech', 'B', -90),
    d: const [66, 66],
    label: (c) => _join(c.tau2),
    sub: (c) => c.tau1,
    note: (c) => '能力组件 ${_join(c.tau2)} 配置于 ${c.tau1}',
  ),
  EdgeDef(
    id: 'g3',
    kind: FlowKind.goods,
    own: 'tech',
    a: const Anchor('tech', 'R', -20),
    b: const Anchor('channel', 'L', -32),
    d: const [120, 120],
    t: 0.46,
    label: (c) => _join(c.outputs),
    sub: (c) => c.salesTheirs,
    note: (c) => '以 ${_join(c.outputs)} 发放至 ${c.salesTheirs}',
  ),
  EdgeDef(
    id: 'f4',
    kind: FlowKind.fund,
    own: 'fin1',
    a: const Anchor('hub', 'R', -20),
    b: const Anchor('channel', 'L', -12),
    d: const [125, 125],
    t: 0.58,
    label: (c) => c.channelMode,
    sub: (c) => c.channelCycle,
    note: (c) => '${c.salesOurs} → ${c.salesTheirs} · ${c.channelMode}',
    st: (c) => c.hasMargin && c.margin < 4.5
        ? FlowStatus(FlowLevel.warn, '毛利率 ${FlowCtx.n(c.margin)}% 低于红线')
        : null,
  ),
  EdgeDef(
    id: 'f5',
    kind: FlowKind.fund,
    own: 'fin1',
    a: const Anchor('hub', 'L', 20),
    b: const Anchor('supplier', 'R', 30),
    d: const [85, 85],
    label: (c) => '${c.supplyMode} · ${c.supplyCycle}',
    sub: (c) => c.payerAccount,
    note: (c) =>
        '${c.purchaseOurs} 按 ${c.supplyMode}/${c.supplyCycle} 向 ${c.purchaseTheirs} 付款（${c.payerAccount}）',
    st: (c) => RegExp(r'待|未').hasMatch(c.payerAccount)
        ? const FlowStatus(FlowLevel.warn, '付款账户未锁定，无法发起付款')
        : null,
  ),
  EdgeDef(
    id: 'i1',
    kind: FlowKind.invoice,
    own: 'fin2',
    a: const Anchor('supplier', 'R', 0),
    b: const Anchor('hub', 'L', 64),
    d: const [105, 105],
    t: 0.68,
    label: (c) => c.purchaseTerms.isEmpty ? c.purchaseName : c.purchaseTerms,
    sub: (c) => c.purchaseName,
    note: (c) =>
        '${c.purchaseTheirs} 向 ${c.purchaseOurs} 开票 · ${c.purchaseTerms.isEmpty ? c.purchaseName : c.purchaseTerms}',
  ),
  EdgeDef(
    id: 'n1',
    kind: FlowKind.info,
    own: 'tech',
    a: const Anchor('channel', 'L', 32),
    b: const Anchor('tech', 'R', 20),
    d: const [125, 125],
    t: 0.54,
    label: (c) => _join(c.outputs),
    sub: (c) => c.salesTheirs,
    note: (c) => '${c.salesTheirs} 通过 ${_join(c.outputs)} 发起请求',
  ),
  EdgeDef(
    id: 'n2',
    kind: FlowKind.info,
    own: 'tech',
    a: const Anchor('tech', 'L', -20),
    b: const Anchor('supplier', 'T', -50),
    d: const [120, 80],
    t: 0.3,
    label: (c) => c.tau1,
    sub: (c) => c.purchaseTheirs,
    note: (c) => '${c.tau1} 对接 ${c.purchaseTheirs}',
  ),
  EdgeDef(
    id: 'n4',
    kind: FlowKind.info,
    own: 'tech',
    a: const Anchor('tech', 'B', 90),
    b: const Anchor('hub', 'T', 90),
    d: const [66, 66],
    label: (c) => _join(c.financeInterfaces),
    note: (c) => '对账字段：${_join(c.financeInterfaces)}',
    st: (c) => c.missingIf.isNotEmpty
        ? FlowStatus(FlowLevel.block, '缺 ${c.missingIf.length} 项必需对账字段')
        : null,
  ),
];

final Map<String, EdgeDef> kEdgeById = {for (final e in kEdges) e.id: e};
