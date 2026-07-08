import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/cached_network_image.dart';
import 'giphy_proxy_service.dart';

enum _PickerTab { emoji, gif }

/// 聊天表情 + GIF 面板高度（与键盘区域接近，便于顶起消息列表）。
const kChatEmojiGifPanelHeight = 280.0;

/// 聊天表情 + GIF 面板（GIF 经后端代理，不暴露 GIPHY Key）。
class ChatEmojiGifPanel extends StatefulWidget {
  const ChatEmojiGifPanel({
    super.key,
    required this.controller,
    required this.giphyService,
    required this.onGifSelected,
  });

  final TextEditingController controller;
  final GiphyProxyService giphyService;
  final ValueChanged<GiphyListItem> onGifSelected;

  @override
  State<ChatEmojiGifPanel> createState() => _ChatEmojiGifPanelState();
}

class _ChatEmojiGifPanelState extends State<ChatEmojiGifPanel> {
  _PickerTab _tab = _PickerTab.emoji;
  final TextEditingController _gifSearchController = TextEditingController();
  final ScrollController _gifScrollController = ScrollController();

  List<GiphyListItem> _gifItems = const <GiphyListItem>[];
  bool _gifLoading = false;
  bool _gifLoadingMore = false;
  bool _gifHasMore = true;
  int _gifOffset = 0;
  String _gifQuery = '';
  String? _gifError;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _gifScrollController.addListener(_onGifScroll);
    unawaited(_loadGifs(reset: true));
  }

  @override
  void dispose() {
    _gifSearchController.dispose();
    _gifScrollController.dispose();
    super.dispose();
  }

  void _onGifScroll() {
    if (!_gifHasMore || _gifLoading || _gifLoadingMore) return;
    if (_gifScrollController.position.pixels <
        _gifScrollController.position.maxScrollExtent * 0.82) {
      return;
    }
    unawaited(_loadGifs(reset: false));
  }

  Future<void> _loadGifs({required bool reset}) async {
    if (reset) {
      if (_gifLoading) return;
      setState(() {
        _gifLoading = true;
        _gifError = null;
        _gifOffset = 0;
        _gifHasMore = true;
      });
    } else {
      if (_gifLoadingMore || !_gifHasMore) return;
      setState(() => _gifLoadingMore = true);
    }

    try {
      final page = _gifQuery.isEmpty
          ? await widget.giphyService.trending(
              offset: reset ? 0 : _gifOffset,
              limit: _pageSize,
            )
          : await widget.giphyService.search(
              _gifQuery,
              offset: reset ? 0 : _gifOffset,
              limit: _pageSize,
            );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _gifItems = page.items;
        } else {
          _gifItems = [..._gifItems, ...page.items];
        }
        _gifOffset = _gifItems.length;
        _gifHasMore = page.hasMore && page.items.isNotEmpty;
        _gifLoading = false;
        _gifLoadingMore = false;
        _gifError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gifLoading = false;
        _gifLoadingMore = false;
        _gifError = friendlyErrorText(e);
        if (reset) _gifItems = const <GiphyListItem>[];
      });
    }
  }

  void _switchTab(_PickerTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (tab == _PickerTab.gif && _gifItems.isEmpty && !_gifLoading) {
      unawaited(_loadGifs(reset: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kChatEmojiGifPanelHeight,
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Column(
        children: [
          _TabBar(
            tab: _tab,
            onSelect: _switchTab,
          ),
          if (_tab == _PickerTab.gif) _GifSearchBar(
            controller: _gifSearchController,
            onSubmitted: (value) {
              _gifQuery = value.trim();
              unawaited(_loadGifs(reset: true));
            },
          ),
          Expanded(
            child: _tab == _PickerTab.emoji
                ? EmojiPicker(
                    textEditingController: widget.controller,
                    config: Config(
                      height: kChatEmojiGifPanelHeight - 44,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        backgroundColor: DunesColors.bgApp,
                        columns: 8,
                        emojiSizeMax: 28,
                      ),
                      skinToneConfig: const SkinToneConfig(enabled: true),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: DunesColors.bgApp,
                        indicatorColor: DunesColors.accent,
                        iconColorSelected: DunesColors.accent,
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: DunesColors.bgApp,
                        hintText: '搜索表情',
                      ),
                    ),
                  )
                : _GifGrid(
                    items: _gifItems,
                    loading: _gifLoading,
                    loadingMore: _gifLoadingMore,
                    error: _gifError,
                    controller: _gifScrollController,
                    onRetry: () => unawaited(_loadGifs(reset: true)),
                    onPick: widget.onGifSelected,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.onSelect});

  final _PickerTab tab;
  final ValueChanged<_PickerTab> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, _PickerTab value) {
      final selected = tab == value;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(value),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? DunesColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? DunesColors.accent : DunesColors.text3,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('表情', _PickerTab.emoji),
        cell('GIF', _PickerTab.gif),
      ],
    );
  }
}

class _GifSearchBar extends StatelessWidget {
  const _GifSearchBar({
    required this.controller,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: '搜索 GIF',
          isDense: true,
          filled: true,
          fillColor: DunesColors.bgSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
      ),
    );
  }
}

class _GifGrid extends StatelessWidget {
  const _GifGrid({
    required this.items,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.controller,
    required this.onRetry,
    required this.onPick,
  });

  final List<GiphyListItem> items;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final ScrollController controller;
  final VoidCallback onRetry;
  final ValueChanged<GiphyListItem> onPick;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          '暂无 GIF',
          style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3),
        ),
      );
    }

    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: items.length + (loadingMore ? 1 : 0),
      itemBuilder: (_, index) {
        if (index >= items.length) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final item = items[index];
        return LayoutBuilder(
          builder: (context, constraints) {
            return InkWell(
              onTap: () => onPick(item),
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: DunesColors.bgSoft,
                  child: CachedDunesNetworkImage(
                    url: item.previewUrl,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    fit: BoxFit.cover,
                    errorBuilder: () => const Icon(Icons.gif_box_outlined),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
