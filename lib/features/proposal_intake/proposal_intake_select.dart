import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'proposal_intake_ui.dart';

class ProposalSelectOption<T> {
  const ProposalSelectOption({
    required this.value,
    required this.label,
    this.meta,
  });

  final T value;
  final String label;
  final String? meta;

  bool matches(String keyword) {
    final needle = keyword.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final haystack = '${label.toLowerCase()} ${(meta ?? '').toLowerCase()}';
    return haystack.contains(needle);
  }
}

/// 下拉贴着输入框宽度、在框下方展开。人员和合同需输入关键词后才出结果。
class ProposalSelectField<T> extends StatefulWidget {
  const ProposalSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.title,
    this.hint = '请选择',
    this.searchable = false,
    this.requireKeyword = false,
    this.allowClear = true,
    this.onAdd,
    this.addLabel,
    this.onQueryChanged,
    this.remoteOptions = false,
    this.emptyText,
  });

  final T? value;
  final List<ProposalSelectOption<T>> options;
  final ValueChanged<T?>? onSelected;
  final String? title;
  final String hint;
  final bool searchable;
  final bool requireKeyword;
  final bool allowClear;
  final VoidCallback? onAdd;
  final String? addLabel;
  final ValueChanged<String>? onQueryChanged;
  final bool remoteOptions;
  final String? emptyText;

  @override
  State<ProposalSelectField<T>> createState() => _ProposalSelectFieldState<T>();
}

class _ProposalSelectFieldState<T> extends State<ProposalSelectField<T>> {
  final _focus = FocusNode();
  final _controller = TextEditingController();
  final _tapGroup = Object();
  OverlayEntry? _overlay;
  Timer? _queryDebounce;
  bool _choosing = false;
  ScrollPosition? _scrollPosition;

  bool get _enabled => widget.onSelected != null;
  bool get _canSearch =>
      widget.searchable ||
      widget.requireKeyword ||
      widget.options.length >= 6 ||
      widget.onAdd != null;

  ProposalSelectOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  String get _query => _controller.text.trim();

  List<ProposalSelectOption<T>> get _matched {
    final query = _query;
    if (widget.requireKeyword && query.isEmpty) {
      return <ProposalSelectOption<T>>[];
    }
    if (widget.remoteOptions) {
      return widget.options;
    }
    final selectedLabel = _selected?.label ?? '';
    if (query.isEmpty || query == selectedLabel) {
      return widget.options;
    }
    return widget.options
        .where((option) => option.matches(query))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _syncFromValue();
    _focus.addListener(_onFocus);
    _controller.addListener(_onQuery);
  }

  @override
  void didUpdateWidget(covariant ProposalSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _syncFromValue();
    }
    // OverlayEntry.markNeedsBuild during the parent's build throws
    // "setState() or markNeedsBuild() called during build".
    _rebuildOverlay();
  }

  void _rebuildOverlay() {
    if (_overlay == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlay?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _hideOverlay();
    _queryDebounce?.cancel();
    _focus.removeListener(_onFocus);
    _controller.removeListener(_onQuery);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncFromValue() {
    _controller.text = _selected?.label ?? '';
  }

  void _onFocus() {
    if (_focus.hasFocus && _enabled) {
      if (widget.requireKeyword) {
        _controller.clear();
      }
      _showOverlay();
      final onQueryChanged = widget.onQueryChanged;
      if (onQueryChanged != null) {
        onQueryChanged(_query);
      }
    } else {
      _hideOverlay();
      if (!_choosing) _syncFromValue();
    }
  }

  void _onQuery() {
    if (!_focus.hasFocus) return;
    _rebuildOverlay();
    final onQueryChanged = widget.onQueryChanged;
    if (onQueryChanged == null) return;
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted && _focus.hasFocus) onQueryChanged(_query);
    });
  }

  void _showOverlay() {
    if (_overlay != null) {
      _rebuildOverlay();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus || _overlay != null) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      _overlay = OverlayEntry(builder: _buildOverlay);
      overlay.insert(_overlay!);
      _listenScroll();
    });
  }

  void _hideOverlay() {
    _stopListenScroll();
    _overlay?.remove();
    _overlay = null;
  }

  void _listenScroll() {
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _scrollPosition)) return;
    _scrollPosition?.removeListener(_onAncestorsMove);
    _scrollPosition = next;
    _scrollPosition?.addListener(_onAncestorsMove);
  }

  void _stopListenScroll() {
    _scrollPosition?.removeListener(_onAncestorsMove);
    _scrollPosition = null;
  }

  void _onAncestorsMove() {
    _overlay?.markNeedsBuild();
  }

  void _choose(T? value) {
    _choosing = true;
    if (value == null) {
      _controller.text = '';
    } else {
      for (final option in widget.options) {
        if (option.value == value) {
          _controller.text = option.label;
          break;
        }
      }
    }
    widget.onSelected?.call(value);
    _focus.unfocus();
    _hideOverlay();
    _choosing = false;
  }

  Widget _buildOverlay(BuildContext _) {
    final fieldBox = context.findRenderObject();
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject();
    if (fieldBox is! RenderBox ||
        !fieldBox.hasSize ||
        overlayBox is! RenderBox ||
        !overlayBox.hasSize) {
      return const SizedBox.shrink();
    }
    final origin = overlayBox.globalToLocal(
      fieldBox.localToGlobal(Offset.zero),
    );
    final fieldSize = fieldBox.size;
    final overlaySize = overlayBox.size;
    const padding = 12.0;
    var menuWidth = math.max(fieldSize.width, 320.0);
    menuWidth = math.min(
      menuWidth,
      math.max(160.0, overlaySize.width - padding * 2),
    );
    var left = origin.dx;
    if (left + menuWidth > overlaySize.width - padding) {
      left = overlaySize.width - padding - menuWidth;
    }
    if (left < padding) left = padding;
    final spaceBelow =
        overlaySize.height - origin.dy - fieldSize.height - padding;
    final spaceAbove = origin.dy - padding;
    const preferred = 280.0;
    final openUp = spaceBelow < 140 && spaceAbove > spaceBelow;
    final maxHeight = (openUp ? spaceAbove : spaceBelow)
        .clamp(120.0, preferred)
        .toDouble();
    final top = openUp
        ? origin.dy - maxHeight - 4
        : origin.dy + fieldSize.height + 4;
    final matched = _matched;
    final emptyText = () {
      if ((widget.emptyText ?? '').trim().isNotEmpty) {
        return widget.emptyText!.trim();
      }
      if (widget.requireKeyword && _query.isEmpty) {
        return widget.remoteOptions
            ? '输入关键词后从合同归集查询'
            : '输入关键词后显示匹配结果';
      }
      if (widget.remoteOptions) {
        return _query.isEmpty ? '输入关键词后查询' : '没有匹配的结果';
      }
      if (widget.options.isEmpty) {
        return widget.addLabel == null ? '请先在管理端配置选项' : '暂无选项，可新增';
      }
      return '没有匹配的选项';
    }();
    return Positioned(
      left: left,
      top: top,
      width: menuWidth,
      child: TextFieldTapRegion(
        child: TapRegion(
          groupId: _tapGroup,
          child: Material(
              key: const ValueKey('proposal-select-menu'),
              color: Colors.white,
              elevation: 10,
              shadowColor: const Color(0x334E3A6C),
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (matched.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Text(
                        emptyText,
                        style: const TextStyle(
                          color: ProposalPalette.text3,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                        shrinkWrap: true,
                        itemCount: matched.length,
                        itemBuilder: (_, index) {
                          final option = matched[index];
                          final active = option.value == widget.value;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _choose(option.value),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option.label,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: ProposalPalette.text,
                                            fontSize: 13,
                                            height: 1.35,
                                            fontWeight: active
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                        if ((option.meta ?? '').isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              option.meta!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: ProposalPalette.text3,
                                                fontSize: 11,
                                                height: 1.3,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (active)
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: ProposalPalette.purple,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (widget.onAdd != null && widget.addLabel != null)
                    InkWell(
                      onTap: () {
                        _focus.unfocus();
                        _hideOverlay();
                        widget.onAdd!();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: ProposalPalette.borderSoft),
                          ),
                        ),
                        child: Text(
                          '+ ${widget.addLabel}',
                          style: const TextStyle(
                            color: ProposalPalette.purpleDeep,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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

  @override
  Widget build(BuildContext context) {
    final tip = [
      _selected?.label ?? '',
      if ((_selected?.meta ?? '').trim().isNotEmpty) _selected!.meta!.trim(),
    ].where((part) => part.isNotEmpty).join('\n');
    Widget field = TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: _enabled,
      readOnly: !_canSearch,
      minLines: 1,
      maxLines: 2,
      style: const TextStyle(
        fontSize: 13,
        height: 1.35,
        color: ProposalPalette.text,
        fontWeight: FontWeight.w500,
      ),
      decoration:
          proposalInputDecoration(
            hint: widget.hint,
            readOnly: !_enabled,
          ).copyWith(
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.allowClear && widget.value != null && _enabled)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => _choose(null),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: ProposalPalette.text3,
                  ),
                Icon(
                  _enabled
                      ? Icons.expand_more_rounded
                      : Icons.lock_outline_rounded,
                  size: _enabled ? 19 : 15,
                  color: ProposalPalette.text3,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
      onTap: _enabled
          ? () {
              if (!_focus.hasFocus) _focus.requestFocus();
              _showOverlay();
            }
          : null,
      onChanged: _canSearch ? (_) => setState(() {}) : null,
    );
    if (tip.isNotEmpty) {
      field = Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 350),
        child: field,
      );
    }
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) {
        if (_focus.hasFocus) {
          _focus.unfocus();
          _hideOverlay();
        }
      },
      child: field,
    );
  }
}
