import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';

/// 聊天表情面板高度（与键盘区域接近，便于顶起消息列表）。
const kChatEmojiGifPanelHeight = 280.0;

class ChatEmojiGifPanel extends StatefulWidget {
  const ChatEmojiGifPanel({
    super.key,
    required this.controller,
    required this.service,
    required this.onSendSticker,
  });
  final TextEditingController controller;
  final ConversationService service;
  final Future<void> Function(Map<String, dynamic> sticker) onSendSticker;

  @override
  State<ChatEmojiGifPanel> createState() => _ChatEmojiGifPanelState();
}

class _ChatEmojiGifPanelState extends State<ChatEmojiGifPanel> {
  late Future<List<Map<String, dynamic>>> _packsFuture;
  String? _activePackId;
  final Map<String, Future<String>> _stickerUrlFutures = {};
  final Map<String, Future<Uint8List>> _stickerBytesFutures = {};
  final Map<String, List<Map<String, dynamic>>> _packAssets = {};
  final Map<String, bool> _packHasMore = {};
  final Map<String, String> _packLoadErrors = {};
  final Set<String> _loadedPacks = {};
  final Set<String> _loadingPacks = {};
  static const int _stickerPageSize = 24;

  @override
  void initState() {
    super.initState();
    _packsFuture = widget.service.fetchStickerPacks(summaryOnly: true);
  }

  void _selectPack(Map<String, dynamic> pack) {
    final id = '${pack['id']}';
    setState(() => _activePackId = id);
    if (!_loadedPacks.contains(id)) _loadPackPage(id);
  }

  Future<void> _loadPackPage(String packId, {bool restart = false}) async {
    if (_loadingPacks.contains(packId)) return;
    final id = int.tryParse(packId);
    if (id == null) return;
    final offset = restart ? 0 : (_packAssets[packId]?.length ?? 0);
    if (!restart && _packHasMore[packId] == false) return;
    setState(() {
      _loadingPacks.add(packId);
      _packLoadErrors.remove(packId);
      if (restart) {
        _packAssets.remove(packId);
        _loadedPacks.remove(packId);
      }
    });
    try {
      final page = await widget.service.fetchStickerPackAssets(
        id,
        offset: offset,
        limit: _stickerPageSize,
      );
      final items = (page['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() {
        final existing = offset == 0
            ? <Map<String, dynamic>>[]
            : (_packAssets[packId] ?? const <Map<String, dynamic>>[]);
        _packAssets[packId] = [...existing, ...items];
        _packHasMore[packId] = page['hasMore'] == true;
        _loadedPacks.add(packId);
      });
    } catch (error) {
      if (mounted) setState(() => _packLoadErrors[packId] = error.toString());
    } finally {
      if (mounted) setState(() => _loadingPacks.remove(packId));
    }
  }

  Color _surface(BuildContext context) => DunesColors.resolve(
    context,
    DunesColors.bgApp,
    role: DunesColorRole.surface,
  );

  @override
  Widget build(BuildContext context) {
    final surface = _surface(context);
    return Container(
      height: kChatEmojiGifPanelHeight,
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(
            color: DunesColors.resolve(
              context,
              DunesColors.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _packsFuture,
        builder: (context, snapshot) {
          final packs = snapshot.data ?? const <Map<String, dynamic>>[];
          Map<String, dynamic>? active;
          for (final pack in packs) {
            if ('${pack['id']}' == _activePackId) {
              active = {
                ...pack,
                'assets': _packAssets[_activePackId] ?? const [],
              };
              break;
            }
          }
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _emojiTab(
                        _activePackId == null,
                        () => setState(() => _activePackId = null),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          packs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (snapshot.hasError)
                        Tooltip(
                          message: '点此查看接口错误详情',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                  content: Text('表情包接口错误：${snapshot.error}'),
                                  action: SnackBarAction(
                                    label: '重试',
                                    onPressed: () => setState(
                                      () => _packsFuture = widget.service
                                          .fetchStickerPacks(summaryOnly: true),
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '加载失败 · 查看原因',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (snapshot.connectionState == ConnectionState.done &&
                          !snapshot.hasError &&
                          packs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '暂无自定义表情',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ...packs.map((pack) {
                        final id = '${pack['id']}';
                        return _packTab(
                          pack,
                          _activePackId == id,
                          () => _selectPack(pack),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: active == null
                    ? EmojiPicker(
                        textEditingController: widget.controller,
                        config: Config(
                          height: kChatEmojiGifPanelHeight - 52,
                          checkPlatformCompatibility: true,
                          emojiViewConfig: EmojiViewConfig(
                            backgroundColor: surface,
                            columns: 8,
                            emojiSizeMax: 28,
                          ),
                          skinToneConfig: const SkinToneConfig(enabled: true),
                          categoryViewConfig: CategoryViewConfig(
                            tabBarHeight: 52,
                            backgroundColor: surface,
                            indicatorColor: DunesColors.resolve(
                              context,
                              DunesColors.accent,
                            ),
                            iconColorSelected: DunesColors.resolve(
                              context,
                              DunesColors.accent,
                            ),
                            customCategoryView:
                                (
                                  config,
                                  state,
                                  tabController,
                                  pageController,
                                ) => SizedBox(
                                  height: 52,
                                  child: TabBar(
                                    controller: tabController,
                                    labelColor: config
                                        .categoryViewConfig
                                        .iconColorSelected,
                                    unselectedLabelColor:
                                        config.categoryViewConfig.iconColor,
                                    indicatorColor: config
                                        .categoryViewConfig
                                        .indicatorColor,
                                    dividerColor:
                                        config.categoryViewConfig.dividerColor,
                                    onTap: pageController.jumpToPage,
                                    tabs: state.categoryEmoji
                                        .map(
                                          (item) => Tab(
                                            icon: Icon(
                                              getIconForCategory(
                                                config
                                                    .categoryViewConfig
                                                    .categoryIcons,
                                                item.category,
                                              ),
                                              size: 28,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                          ),
                          bottomActionBarConfig: const BottomActionBarConfig(
                            enabled: false,
                          ),
                          searchViewConfig: SearchViewConfig(
                            backgroundColor: surface,
                            hintText: '搜索表情',
                          ),
                        ),
                      )
                    : _buildStickerGrid(active),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emojiTab(bool selected, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Container(
      width: 56,
      height: 52,
      padding: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected
                ? DunesColors.resolve(context, DunesColors.accent)
                : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_emotions_outlined,
            size: 25,
            color: selected
                ? DunesColors.resolve(context, DunesColors.accent)
                : null,
          ),
          Text(
            '表情',
            maxLines: 1,
            style: TextStyle(
              fontSize: 9,
              color: selected
                  ? DunesColors.resolve(context, DunesColors.accent)
                  : null,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _packTab(
    Map<String, dynamic> pack,
    bool selected,
    VoidCallback onTap,
  ) {
    final assets = (pack['assets'] as List? ?? const []).whereType<Map>();
    final cover = pack['cover'] is Map
        ? Map<String, dynamic>.from(pack['cover'] as Map)
        : assets.isEmpty
        ? null
        : Map<String, dynamic>.from(assets.first);
    final accent = DunesColors.resolve(context, DunesColors.accent);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 52,
        padding: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 28,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: cover == null
                    ? Icon(
                        Icons.photo_outlined,
                        size: 23,
                        color: selected ? accent : null,
                      )
                    : _stickerImage(cover),
              ),
            ),
            Text(
              (pack['name'] ?? '表情').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: selected ? accent : null,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerGrid(Map<String, dynamic> pack) {
    final packId = '${pack['id']}';
    final assets = (pack['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final loading = _loadingPacks.contains(packId);
    final error = _packLoadErrors[packId];
    if (assets.isEmpty) {
      if (loading) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (error != null) {
        return Center(
          child: TextButton.icon(
            onPressed: () => _loadPackPage(packId, restart: true),
            icon: const Icon(Icons.refresh),
            label: const Text('加载失败，点击重试'),
          ),
        );
      }
      return const Center(child: Text('该分类暂时没有表情'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 76)
            .floor()
            .clamp(4, 12)
            .toInt();
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle &&
                notification.metrics.extentAfter < 140 &&
                _packHasMore[packId] == true &&
                !_loadingPacks.contains(packId)) {
              _loadPackPage(packId);
            }
            return false;
          },
          child: GridView.builder(
            key: PageStorageKey<String>('sticker-pack-$packId'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount:
                assets.length +
                ((_packHasMore[packId] == true || loading || error != null)
                    ? 1
                    : 0),
            itemBuilder: (context, index) {
              if (index >= assets.length) {
                if (error != null) {
                  return IconButton(
                    tooltip: '加载下一批失败，点击重试',
                    onPressed: () => _loadPackPage(packId),
                    icon: const Icon(Icons.refresh),
                  );
                }
                if (loading) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return TextButton.icon(
                  onPressed: () => _loadPackPage(packId),
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('加载更多', style: TextStyle(fontSize: 10)),
                );
              }
              final asset = assets[index];
              return InkWell(
                onTap: () => widget.onSendSticker({
                  ...asset,
                  'stickerPackId': pack['id'],
                  'stickerPackName': pack['name'],
                }),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _stickerImage(asset, useThumbnail: false),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _stickerImage(Map<String, dynamic> asset, {bool useThumbnail = true}) {
    final thumbnailKey = (asset['thumbnailObjectKey'] ?? '').toString().trim();
    final displayAsset = !useThumbnail || thumbnailKey.isEmpty
        ? asset
        : <String, dynamic>{
            ...asset,
            'objectKey': thumbnailKey,
            'fileName': 'sticker-thumbnail.png',
            'mimeType': 'image/png',
          };
    final objectKey = (displayAsset['objectKey'] ?? '').toString();
    final cacheKey = 'im-stickers:$objectKey';
    final urlFuture = _stickerUrlFutures.putIfAbsent(
      cacheKey,
      () => widget.service.resolveMediaUrl(objectKey, bucket: 'im-stickers'),
    );
    return FutureBuilder<String>(
      future: urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.network(
            snapshot.data!,
            fit: BoxFit.contain,
            cacheWidth: 96,
            cacheHeight: 96,
            errorBuilder: (context, error, stack) => _fallback(displayAsset),
          );
        }
        if (snapshot.hasError) {
          return _fallback(displayAsset);
        }
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        );
      },
    );
  }

  Widget _fallback(Map<String, dynamic> asset) {
    final objectKey = (asset['objectKey'] ?? '').toString();
    final cacheKey = 'im-stickers:$objectKey';
    final bytesFuture = _stickerBytesFutures.putIfAbsent(
      cacheKey,
      () => widget.service.loadCachedChatMediaBytes({
        ...asset,
        'mediaBucket': 'im-stickers',
      }),
    );
    return FutureBuilder<Uint8List>(
      future: bytesFuture,
      builder: (context, snapshot) => snapshot.hasData
          ? Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              cacheWidth: 96,
              cacheHeight: 96,
            )
          : const Center(child: Icon(Icons.emoji_emotions_outlined)),
    );
  }
}
