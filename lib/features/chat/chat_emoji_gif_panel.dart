import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 聊天表情面板高度（与键盘区域接近，便于顶起消息列表）。
const kChatEmojiGifPanelHeight = 280.0;

/// 聊天表情面板。
class ChatEmojiGifPanel extends StatelessWidget {
  const ChatEmojiGifPanel({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kChatEmojiGifPanelHeight,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          DunesColors.bgApp,
          role: DunesColorRole.surface,
        ),
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
      child: EmojiPicker(
        textEditingController: controller,
        config: Config(
          height: kChatEmojiGifPanelHeight,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: DunesColors.resolve(
              context,
              DunesColors.bgApp,
              role: DunesColorRole.surface,
            ),
            columns: 8,
            emojiSizeMax: 28,
          ),
          skinToneConfig: const SkinToneConfig(enabled: true),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: DunesColors.resolve(
              context,
              DunesColors.bgApp,
              role: DunesColorRole.surface,
            ),
            indicatorColor: DunesColors.resolve(context, DunesColors.accent),
            iconColorSelected: DunesColors.resolve(context, DunesColors.accent),
          ),
          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
          searchViewConfig: SearchViewConfig(
            backgroundColor: DunesColors.resolve(
              context,
              DunesColors.bgApp,
              role: DunesColorRole.surface,
            ),
            hintText: '搜索表情',
          ),
        ),
      ),
    );
  }
}
