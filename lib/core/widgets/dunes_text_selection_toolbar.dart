import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dunes_theme.dart';

/// 苹果 iOS 风格的磨砂玻璃长按文字操作菜单，替换系统默认的矩形文字条。
///
/// 支持 `<= 4` 项时横向胶囊排布、`> 4` 项时 4 列网格排布，带弹性缩放动画与触觉反馈。
class DunesTextSelectionToolbar extends StatefulWidget {
  const DunesTextSelectionToolbar({
    super.key,
    required this.anchors,
    required this.buttonItems,
  });

  factory DunesTextSelectionToolbar.buttonItems({
    Key? key,
    required TextSelectionToolbarAnchors anchors,
    required List<ContextMenuButtonItem> buttonItems,
  }) => DunesTextSelectionToolbar(
    key: key,
    anchors: anchors,
    buttonItems: buttonItems,
  );

  factory DunesTextSelectionToolbar.editableText({
    Key? key,
    required EditableTextState editableTextState,
  }) => DunesTextSelectionToolbar(
    key: key,
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: editableTextState.contextMenuButtonItems,
  );

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;

  @override
  State<DunesTextSelectionToolbar> createState() =>
      _DunesTextSelectionToolbarState();
}

class _DunesTextSelectionToolbarState extends State<DunesTextSelectionToolbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _resolvedLabel(ContextMenuButtonItem item) {
    final explicit = item.label?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return switch (item.type) {
      ContextMenuButtonType.cut => '剪切',
      ContextMenuButtonType.copy => '复制',
      ContextMenuButtonType.paste => '粘贴',
      ContextMenuButtonType.selectAll => '全选',
      ContextMenuButtonType.delete => '删除',
      ContextMenuButtonType.lookUp => '查询',
      ContextMenuButtonType.searchWeb => '搜索',
      ContextMenuButtonType.share => '共享',
      ContextMenuButtonType.liveTextInput => '实况文本',
      ContextMenuButtonType.custom => '操作',
    };
  }

  IconData _resolvedIcon(ContextMenuButtonItem item, String label) {
    if (label.contains('复制全部')) return Icons.library_add_check_outlined;
    if (label.contains('复制') || item.type == ContextMenuButtonType.copy) {
      return Icons.copy_rounded;
    }
    if (label.contains('全选') || item.type == ContextMenuButtonType.selectAll) {
      return Icons.select_all_rounded;
    }
    if (label.contains('剪切') || item.type == ContextMenuButtonType.cut) {
      return Icons.content_cut_rounded;
    }
    if (label.contains('粘贴') || item.type == ContextMenuButtonType.paste) {
      return Icons.content_paste_rounded;
    }
    if (label.contains('换行')) return Icons.keyboard_return_rounded;
    if (label.contains('引用')) return Icons.format_quote_rounded;
    if (label.contains('转发')) return Icons.shortcut_rounded;
    if (label.contains('收藏')) return Icons.star_outline_rounded;
    if (label.contains('置顶')) return Icons.push_pin_outlined;
    if (label.contains('多选')) return Icons.checklist_rounded;
    if (label.contains('撤回') || item.type == ContextMenuButtonType.delete) {
      return Icons.undo_rounded;
    }
    if (label.contains('删除')) return Icons.delete_outline_rounded;
    if (label.contains('更多')) return Icons.more_horiz_rounded;
    return Icons.touch_app_outlined;
  }

  bool _isDestructive(ContextMenuButtonItem item, String label) {
    return item.type == ContextMenuButtonType.delete ||
        label.contains('撤回') ||
        label.contains('删除');
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.buttonItems
        .where((e) => e.onPressed != null)
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark
        ? const Color(0xFF26252B).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.90);
    final border = dark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE5E5EA);
    final dividerColor = dark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE5E5EA);
    final useGrid = items.length > 4;

    return CustomSingleChildLayout(
      delegate: _DunesToolbarLayoutDelegate(
        anchorAbove: widget.anchors.primaryAnchor,
        anchorBelow:
            widget.anchors.secondaryAnchor ?? widget.anchors.primaryAnchor,
      ),
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: dark ? 0.36 : 0.14,
                        ),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: useGrid
                      ? _buildGrid(items, dark, dividerColor)
                      : _buildRow(items, dark, dividerColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    List<ContextMenuButtonItem> items,
    bool dark,
    Color dividerColor,
  ) {
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              VerticalDivider(width: 0.6, thickness: 0.6, color: dividerColor),
            _buildActionButton(items[i], dark, compact: false),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(
    List<ContextMenuButtonItem> items,
    bool dark,
    Color dividerColor,
  ) {
    const columns = 4;
    final rows = <List<ContextMenuButtonItem>>[];
    for (var i = 0; i < items.length; i += columns) {
      rows.add(
        items.sublist(
          i,
          (i + columns) > items.length ? items.length : i + columns,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                child: Divider(
                  height: 0.6,
                  thickness: 0.6,
                  color: dividerColor,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in rows[r])
                  SizedBox(
                    width: 68,
                    child: _buildActionButton(item, dark, compact: true),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
    ContextMenuButtonItem item,
    bool dark, {
    required bool compact,
  }) {
    final label = _resolvedLabel(item);
    final icon = _resolvedIcon(item, label);
    final destructive = _isDestructive(item, label);
    final fgColor = destructive
        ? DunesColors.resolve(context, DunesColors.coral)
        : (dark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F));

    return _ToolbarActionTile(
      icon: icon,
      label: label,
      color: fgColor,
      compact: compact,
      onTap: () {
        HapticFeedback.selectionClick();
        item.onPressed?.call();
      },
    );
  }
}

class _ToolbarActionTile extends StatefulWidget {
  const _ToolbarActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_ToolbarActionTile> createState() => _ToolbarActionTileState();
}

class _ToolbarActionTileState extends State<_ToolbarActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.90 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Padding(
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: widget.color),
              const SizedBox(height: 3.5),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: widget.color,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DunesToolbarLayoutDelegate extends SingleChildLayoutDelegate {
  _DunesToolbarLayoutDelegate({
    required this.anchorAbove,
    required this.anchorBelow,
  });

  final Offset anchorAbove;
  final Offset anchorBelow;

  static const double _gap = 10.0;
  static const double _edgePadding = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = (size.width - childSize.width - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );
    final dx = (anchorAbove.dx - childSize.width / 2).clamp(_edgePadding, maxX);

    final fitsAbove = anchorAbove.dy - childSize.height - _gap >= _edgePadding;
    final double dy;
    if (fitsAbove) {
      dy = anchorAbove.dy - childSize.height - _gap;
    } else {
      final maxY = (size.height - childSize.height - _edgePadding).clamp(
        _edgePadding,
        double.infinity,
      );
      dy = (anchorBelow.dy + _gap).clamp(_edgePadding, maxY);
    }
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_DunesToolbarLayoutDelegate oldDelegate) {
    return oldDelegate.anchorAbove != anchorAbove ||
        oldDelegate.anchorBelow != anchorBelow;
  }
}
