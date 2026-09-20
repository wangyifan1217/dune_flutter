import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'lighthouse_equity_link.dart';
import 'lighthouse_theme.dart';

enum _PopoverPlacement { right, left, below, above }

/// 标签二名称下的联动线。
///
/// 不能用 [TextDecoration.underline]：账本名称走 [LhScrollRichText]，
/// 自定义 RenderBox 按文字高度 clip，下划线刚好画在裁切线下面，肉眼看不见。
class LhEquityLinkedLabel extends StatelessWidget {
  const LhEquityLinkedLabel({super.key, required this.child});

  final Widget child;

  static const color = Color(0xFF7B5CD8);
  static const thickness = 2.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: color, width: thickness),
        ),
      ),
      child: Padding(padding: const EdgeInsets.only(bottom: 2), child: child),
    );
  }
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
  void updateRenderObject(BuildContext context, _RenderLhHitSlop renderObject) {
    renderObject
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
    required this.transactionProfit,
    required this.links,
    required this.onOpenLink,
    required this.child,
  });

  final String title;
  final double transactionProfit;
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
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _toggle() => _entry == null ? _show() : _hide();

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
        label: '${widget.title}，查看${widget.links.length}项关联权益',
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
    required this.transactionProfit,
    required this.links,
    required this.onClose,
    required this.onOpenLink,
  });

  final double width;
  final double maxHeight;
  final _PopoverPlacement placement;
  final String title;
  final double transactionProfit;
  final List<LhEquityLink> links;
  final VoidCallback onClose;
  final ValueChanged<LhEquityLink> onOpenLink;

  static const _line = Color(0xFFE4DCF4);
  static const _panel = Color(0xFFF5F8FC);
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
            _transactionStrip(),
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
                      padding: const EdgeInsets.fromLTRB(10, 5, 10, 9),
                      shrinkWrap: true,
                      itemCount: links.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        thickness: 0.7,
                        color: _line,
                      ),
                      itemBuilder: (context, index) =>
                          _projectRow(context, links[index]),
                    ),
            ),
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
    padding: const EdgeInsets.fromLTRB(14, 11, 8, 10),
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
          child: Text(
            '$title · 关联权益',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LhTypography.sans(
              size: 13,
              color: LhColors.ink,
              weight: FontWeight.w700,
            ),
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

  Widget _transactionStrip() => Container(
    margin: const EdgeInsets.fromLTRB(10, 9, 10, 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: _panel,
      border: Border.all(color: _blue.withAlpha(35), width: 0.7),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Text(
          '标签二交易',
          style: LhTypography.sans(
            size: 9.5,
            color: _blue,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(width: 0.7, height: 12, color: _blue.withAlpha(45)),
        const SizedBox(width: 8),
        Text('交易毛利', style: LhTypography.sans(size: 9.5, color: LhColors.mute)),
        const Spacer(),
        Text(
          _signedMoney(transactionProfit),
          style: LhTypography.number(
            size: 11,
            color: _profitColor(transactionProfit),
          ),
        ),
      ],
    ),
  );

  Widget _projectRow(BuildContext context, LhEquityLink link) => InkWell(
    borderRadius: BorderRadius.circular(9),
    hoverColor: _blue.withAlpha(12),
    onTap: () => onOpenLink(link),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  link.row,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(
                    size: 12,
                    color: LhColors.ink,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              if (link.channel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LhColors.purpleSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    link.channel,
                    style: LhTypography.sans(
                      size: 8.5,
                      color: LhColors.purple,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (link.product.isNotEmpty) link.product,
              if (link.group.isNotEmpty) link.group,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LhTypography.sans(size: 9.5, color: LhColors.mute),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metric('权益销售额', _money(link.sales), LhColors.ink2),
              const SizedBox(width: 16),
              _metric(
                '毛利润',
                _signedMoney(link.profit),
                _profitColor(link.profit),
              ),
              const Spacer(),
              Text(
                '查看',
                style: LhTypography.sans(
                  size: 9.5,
                  color: _blue,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 15, color: _blue),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: LhTypography.sans(size: 8.5, color: LhColors.mute2)),
      const SizedBox(width: 4),
      Text(value, style: LhTypography.number(size: 10.5, color: color)),
    ],
  );

  static Color _profitColor(double value) => value < 0
      ? LhColors.pos
      : value > 0
      ? LhColors.neg
      : LhColors.mute;

  static String _money(double value) {
    // 接口金额口径恒为「元」，气泡与灯塔主体统一换算为「万」。
    // 小额不能固定两位：24 元若显示成 0.00 万会丢失真实量级，因此不足
    // 0.01 万时最多保留到分（万口径 6 位小数），再去掉无意义尾零。
    final wan = value.abs() / 10000;
    if (wan == 0) return '0.00万';
    if (wan >= 100) return '${wan.toStringAsFixed(1)}万';
    if (wan >= 0.01) return '${wan.toStringAsFixed(2)}万';
    final precise = wan
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '$precise万';
  }

  static String _signedMoney(double value) {
    if (value == 0) return _money(0);
    return '${value > 0 ? '+' : '−'}${_money(value)}';
  }
}
