import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'lighthouse_equity_link.dart';
import 'lighthouse_theme.dart';

// 权益指路（不是对账）
//
//   许总（经营会 02:36）：「我想把这两个关系有链接关系，但是我又不想在
//   一个页面里面显示出来。……我就会点这个名字去看到他的这个数据链接到他
//   的这个权益收入部分。」
//   以及 01:26：「权益收入属于权益收入，根本不可能归到石油这个体系里面来。
//   以前的财务就喜欢把两个数据放在一个里面去，这是我很反感的地方。」
//
//   所以这里只做「指路」：
//     · 点供给名称始终先开卡片，单项也不直接跳；
//     · 卡片列出权益侧每个项目的收入与毛利，点项目再进入权益详情；
//       交易侧金额留在原行和跳转后的来路条，不合并两套账。

enum _PopoverPlacement { right, left, below, above }

/// 标签二名称下的联动线。
///
/// 不能用 [TextDecoration.underline]：账本名称走 [LhScrollRichText]，
/// 自定义 RenderBox 按文字高度 clip，下划线刚好画在裁切线下面，肉眼看不见。
class LhEquityLinkedLabel extends StatelessWidget {
  const LhEquityLinkedLabel({super.key, required this.child});

  final Widget child;

  static const color = Color(0xFF7B5CD8);
  static const thickness = 1.15;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _LhLinkedUnderlinePainter(),
      child: Padding(padding: const EdgeInsets.only(bottom: 3), child: child),
    );
  }
}

class _LhLinkedUnderlinePainter extends CustomPainter {
  const _LhLinkedUnderlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final y = size.height - LhEquityLinkedLabel.thickness / 2;
    final bounds = Rect.fromLTWH(0, y, size.width, 1);
    final paint = Paint()
      ..strokeWidth = LhEquityLinkedLabel.thickness
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          LhEquityLinkedLabel.color.withAlpha(190),
          LhEquityLinkedLabel.color.withAlpha(100),
        ],
      ).createShader(bounds);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _LhLinkedUnderlinePainter oldDelegate) => false;
}

/// 扩大点击热区，但不参与布局。孩子有多大，占位就多大。
class LhHitSlop extends SingleChildRenderObjectWidget {
  const LhHitSlop({
    super.key,
    this.minSize = 44,
    this.alignment = Alignment.center,
    required Widget super.child,
  });

  final double minSize;
  final Alignment alignment;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLhHitSlop(minSize: minSize, alignment: alignment);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLhHitSlop)
      ..minSize = minSize
      ..alignment = alignment;
  }
}

class _RenderLhHitSlop extends RenderProxyBox {
  _RenderLhHitSlop({required double minSize, required Alignment alignment})
    : _minSize = minSize,
      _alignment = alignment;

  double _minSize;
  Alignment _alignment;

  set minSize(double value) {
    if (_minSize == value) return;
    _minSize = value;
    markNeedsPaint();
  }

  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsPaint();
  }

  Rect get _hitRect {
    final w = math.max(size.width, _minSize);
    final h = math.max(size.height, _minSize);
    final extraLeft = (w - size.width) * (_alignment.x + 1) / 2;
    final extraTop = (h - size.height) * (_alignment.y + 1) / 2;
    return Rect.fromLTWH(-extraLeft, -extraTop, w, h);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_hitRect.contains(position)) return false;
    final childPos = Offset(
      position.dx.clamp(0.0, size.width),
      position.dy.clamp(0.0, size.height),
    );
    if (hitTestChildren(result, position: childPos) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestSelf(Offset position) => _hitRect.contains(position);
}

/// 把标签二名称变成一个轻量锚点：点击后在名称旁边打开权益速览气泡。
///
/// 使用 Overlay + CompositedTransformFollower，列表滚动时气泡仍跟着原行；
/// 屏幕右侧放不下会自动翻到左侧，窄屏则落在名称下方，不做底部抽屉。
class LhEquityPopoverAnchor extends StatefulWidget {
  const LhEquityPopoverAnchor({
    super.key,
    required this.title,
    this.periodLabel = '',
    this.transactionProfit,
    required this.links,
    required this.onOpenLink,
    required this.child,
  });

  final String title;

  /// 与账本当前行相同的统计期间，不把零值解释成“今天未出数”。
  final String periodLabel;
  final double? transactionProfit;
  final List<LhEquityLink> links;
  final ValueChanged<LhEquityLink> onOpenLink;
  final Widget child;

  @override
  State<LhEquityPopoverAnchor> createState() => _LhEquityPopoverAnchorState();
}

class _LhEquityPopoverAnchorState extends State<LhEquityPopoverAnchor> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void didUpdateWidget(covariant LhEquityPopoverAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entry = _entry;
    if (entry == null) return;
    // 气泡在 Overlay 里，父页面换期间时不会自动跟着锚点重建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_entry, entry)) entry.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _toggle() {
    // 省份下划线只负责解释关联关系：即使只有一个落点，也先展示卡片。
    // 进入供给二级页由账本行右侧的独立箭头承担，避免名称热区语义混杂。
    _entry == null ? _show() : _hide();
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void _show() {
    final overlay = Overlay.of(context);
    final targetBox = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (targetBox == null || overlayBox == null) return;

    final targetTopLeft = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetRect = targetTopLeft & targetBox.size;
    final viewport = overlayBox.size;
    final width = math.min(360.0, math.max(280.0, viewport.width - 24));
    final maxHeight = math.min(420.0, math.max(220.0, viewport.height - 24));

    const gap = 10.0;
    const edge = 12.0;
    final canRight = targetRect.right + gap + width <= viewport.width - edge;
    final canLeft = targetRect.left - gap - width >= edge;
    final canBelow =
        targetRect.bottom + gap + maxHeight <= viewport.height - edge;
    final placement = canRight
        ? _PopoverPlacement.right
        : canLeft
        ? _PopoverPlacement.left
        : canBelow
        ? _PopoverPlacement.below
        : _PopoverPlacement.above;

    Alignment targetAnchor;
    Alignment followerAnchor;
    Offset offset;
    switch (placement) {
      case _PopoverPlacement.right:
        targetAnchor = Alignment.topRight;
        followerAnchor = Alignment.topLeft;
        final top = targetRect.top.clamp(
          edge,
          viewport.height - maxHeight - edge,
        );
        offset = Offset(gap, top - targetRect.top);
      case _PopoverPlacement.left:
        targetAnchor = Alignment.topLeft;
        followerAnchor = Alignment.topRight;
        final top = targetRect.top.clamp(
          edge,
          viewport.height - maxHeight - edge,
        );
        offset = Offset(-gap, top - targetRect.top);
      case _PopoverPlacement.below:
        targetAnchor = Alignment.bottomLeft;
        followerAnchor = Alignment.topLeft;
        final left = targetRect.left.clamp(edge, viewport.width - width - edge);
        offset = Offset(left - targetRect.left, gap);
      case _PopoverPlacement.above:
        targetAnchor = Alignment.topLeft;
        followerAnchor = Alignment.bottomLeft;
        final left = targetRect.left.clamp(edge, viewport.width - width - edge);
        offset = Offset(left - targetRect.left, -gap);
    }

    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: _EquityPopover(
              width: width,
              maxHeight: maxHeight,
              placement: placement,
              title: widget.title,
              periodLabel: widget.periodLabel,
              transactionProfit: widget.transactionProfit,
              links: widget.links,
              onClose: _hide,
              onOpenLink: (link) {
                _hide();
                widget.onOpenLink(link);
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: widget.links.length == 1
            ? '跳到${widget.links.first.row}的权益收入'
            : '${widget.title}，选择${widget.links.length}项关联权益之一',
        child: LhHitSlop(
          alignment: Alignment.topLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _EquityPopover extends StatelessWidget {
  const _EquityPopover({
    required this.width,
    required this.maxHeight,
    required this.placement,
    required this.title,
    required this.periodLabel,
    required this.transactionProfit,
    required this.links,
    required this.onClose,
    required this.onOpenLink,
  });

  final double width;
  final double maxHeight;
  final _PopoverPlacement placement;
  final String title;
  final String periodLabel;
  final double? transactionProfit;
  final List<LhEquityLink> links;
  final VoidCallback onClose;
  final ValueChanged<LhEquityLink> onOpenLink;

  static const _line = Color(0xFFE4DCF4);
  static const _blue = Color(0xFF4A83C4);

  @override
  Widget build(BuildContext context) {
    final bubble = Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border.all(color: _line, width: 0.8),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F463B5E),
              blurRadius: 22,
              spreadRadius: -5,
              offset: Offset(0, 9),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Container(height: 0.7, color: _line),
            if (transactionProfit != null) _transactionStrip(),
            Flexible(
              child: links.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 22,
                      ),
                      child: Text(
                        '暂无关联权益',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: LhColors.mute2,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                      shrinkWrap: true,
                      itemCount: links.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        thickness: 0.7,
                        color: _line,
                      ),
                      itemBuilder: (context, index) =>
                          _projectRow(links[index]),
                    ),
            ),
            if (links.isNotEmpty) ...[_profitTotal(), _scopeNote()],
          ],
        ),
      ),
    );

    const arrowSize = 10.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: placement == _PopoverPlacement.right
              ? -arrowSize / 2
              : placement == _PopoverPlacement.below ||
                    placement == _PopoverPlacement.above
              ? 22
              : null,
          right: placement == _PopoverPlacement.left ? -arrowSize / 2 : null,
          top: placement == _PopoverPlacement.below
              ? -arrowSize / 2
              : placement == _PopoverPlacement.above
              ? null
              : 19,
          bottom: placement == _PopoverPlacement.above ? -arrowSize / 2 : null,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: arrowSize,
              height: arrowSize,
              decoration: BoxDecoration(
                color: LhColors.paper,
                border: Border.all(color: _line, width: 0.8),
              ),
            ),
          ),
        ),
        bubble,
      ],
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    child: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _blue.withAlpha(24),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.link_rounded, size: 14, color: _blue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$title · 关联权益',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LhTypography.sans(
                  size: 13,
                  color: LhColors.ink,
                  weight: FontWeight.w700,
                ),
              ),
              if (periodLabel.isNotEmpty)
                Text(
                  periodLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(size: 9, color: LhColors.mute),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: LhColors.purpleSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '${links.length}项',
            style: LhTypography.mono(
              size: 9,
              color: LhColors.purple,
              weight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 3),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          tooltip: '关闭',
          onPressed: onClose,
          icon: const Icon(
            Icons.close_rounded,
            size: 16,
            color: LhColors.mute2,
          ),
        ),
      ],
    ),
  );

  Widget _transactionStrip() {
    final value = transactionProfit!;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 9, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _blue.withAlpha(22), width: 0.7),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _blue.withAlpha(18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '标签二交易',
              style: LhTypography.sans(
                size: 9,
                color: _blue,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('交易毛利', style: LhTypography.sans(size: 9, color: LhColors.ink2)),
          const Spacer(),
          Text(
            _signedMoney(value),
            style: LhTypography.number(
              size: 11.5,
              color: value < 0
                  ? LhColors.pos
                  : value > 0
                  ? LhColors.neg
                  : LhColors.mute2,
            ),
          ),
        ],
      ),
    );
  }

  /// 一行 = 一个权益落点。金额只来自标签一的同期间项目，不拿来抵扣原行。
  Widget _projectRow(LhEquityLink link) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      hoverColor: _blue.withAlpha(12),
      onTap: () => onOpenLink(link),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 11, 4, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    link.row,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LhTypography.sans(
                      size: 12.5,
                      color: LhColors.ink,
                      weight: FontWeight.w700,
                    ),
                  ),
                  if (link.product.isNotEmpty ||
                      (link.channel.isNotEmpty && link.channel != '其他')) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (link.product.isNotEmpty)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: LhColors.purpleSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                link.product,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LhTypography.sans(
                                  size: 9.5,
                                  color: LhColors.purple,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (link.product.isNotEmpty &&
                            link.channel.isNotEmpty &&
                            link.channel != '其他')
                          const SizedBox(width: 5),
                        if (link.channel.isNotEmpty && link.channel != '其他')
                          Text(
                            link.channel,
                            style: LhTypography.sans(
                              size: 9,
                              color: LhColors.mute,
                              weight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 106,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _amountLine('收入', _incomeMoney(link.revenue), LhColors.ink2),
                  const SizedBox(height: 3),
                  _amountLine(
                    '毛利润',
                    _signedMoney(link.profit),
                    link.profit < 0
                        ? LhColors.pos
                        : link.profit > 0
                        ? LhColors.neg
                        : LhColors.mute2,
                    underlineLabel: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 16, color: _blue),
          ],
        ),
      ),
    );
  }

  Widget _profitTotal() {
    final total = links.fold<double>(0, (sum, link) => sum + link.profit);
    final color = total < 0
        ? LhColors.pos
        : total > 0
        ? LhColors.neg
        : LhColors.mute2;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 7, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LhColors.purpleSoft.withAlpha(120),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Text(
            '候选权益毛利润合计',
            style: LhTypography.sans(
              size: 10,
              color: LhColors.ink2,
              weight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            _signedMoney(total),
            style: LhTypography.number(size: 12, color: color),
          ),
        ],
      ),
    );
  }

  Widget _scopeNote() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 5, 16, 10),
    child: Text(
      '同省权益线索 · 合计不与标签二交易毛利相加 · 点击项目直达详情',
      style: LhTypography.sans(size: 9, color: LhColors.mute2),
    ),
  );

  Widget _amountLine(
    String label,
    String amount,
    Color color, {
    bool underlineLabel = false,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      !underlineLabel
          ? Text(
              label,
              style: LhTypography.sans(size: 9.5, color: LhColors.mute2),
            )
          : LhEquityLinkedLabel(
              child: Text(
                label,
                style: LhTypography.sans(
                  size: 9.5,
                  color: LhEquityLinkedLabel.color,
                  weight: FontWeight.w600,
                ),
              ),
            ),
      const SizedBox(width: 4),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            amount,
            maxLines: 1,
            style: LhTypography.number(size: 11.5, color: color),
          ),
        ),
      ),
    ],
  );

  static String _money(double yuan) {
    final wan = yuan.abs() / 10000;
    if (wan == 0) return '0.00万';
    if (wan >= 100) return '${wan.toStringAsFixed(1)}万';
    if (wan >= 0.01) return '${wan.toStringAsFixed(2)}万';
    final precise = wan
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '$precise万';
  }

  static String _signedMoney(double yuan) =>
      yuan == 0 ? _money(0) : '${yuan < 0 ? '−' : '+'}${_money(yuan)}';

  static String _incomeMoney(double yuan) =>
      yuan < 0 ? '−${_money(yuan)}' : _money(yuan);
}
