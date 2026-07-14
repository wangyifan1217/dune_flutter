import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'chat_quote.dart';
import '../conversation/conversation_models.dart';
import '../conversation/inbox_format.dart';
import 'chat_voice_player.dart';

class ChatConvHeader extends StatelessWidget {
  const ChatConvHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.onTapTitle,
    this.actions = const <Widget>[],
    this.leadingAvatar,
    this.showOnlineDot = false,
    this.showBackButton = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onTapTitle;
  final List<Widget> actions;
  final Widget? leadingAvatar;
  final bool showOnlineDot;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(showBackButton ? 4 : 12, 8, 8, 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, size: 28),
              color: DunesColors.text2,
            ),
          if (leadingAvatar != null) ...[
            GestureDetector(onTap: onTapTitle, child: leadingAvatar!),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GestureDetector(
              onTap: onTapTitle,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01 * 15.5,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (showOnlineDot) ...[
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: DunesColors.green,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.mono(
                            fontSize: 9.5,
                            color: DunesColors.text3,
                            letterSpacing: 0.04 * 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class ChatQuickActions extends StatelessWidget {
  const ChatQuickActions({
    super.key,
    required this.onCamera,
    required this.onAlbum,
    required this.onFile,
    required this.onApproval,
    this.onAt,
    this.onEmoji,
    this.onVideo,
    this.showAt = false,
    this.showVideo = false,
  });

  final VoidCallback onCamera;
  final VoidCallback onAlbum;
  final VoidCallback onFile;
  final VoidCallback onApproval;
  final VoidCallback? onAt;
  final VoidCallback? onEmoji;
  final VoidCallback? onVideo;
  final bool showAt;
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    final cells = <_QaCell>[
      _QaCell(icon: Icons.photo_outlined, label: '相册', onTap: onAlbum),
      _QaCell(icon: Icons.photo_camera_outlined, label: '拍照', onTap: onCamera),
      _QaCell(icon: Icons.folder_outlined, label: '文件', onTap: onFile),
      _QaCell(
        icon: Icons.assignment_outlined,
        label: '转发审批',
        onTap: onApproval,
      ),
      if (showAt && onAt != null)
        _QaCell(icon: Icons.alternate_email, label: '@', onTap: onAt!),
      if (showVideo && onVideo != null)
        _QaCell(icon: Icons.videocam_outlined, label: '视频', onTap: onVideo!),
    ];
    // 微信式宫格：每行最多 4 个白底圆角方块。
    // 表情已在输入栏，不再放入工具面板。
    const cols = 4;
    final rows = <List<_QaCell>>[];
    for (var i = 0; i < cells.length; i += cols) {
      rows.add(
        cells.sublist(i, i + cols > cells.length ? cells.length : i + cols),
      );
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFFF7F7F7),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < cols; c++)
                  Expanded(
                    child: c < rows[r].length
                        ? _WeChatToolTile(cell: rows[r][c])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeChatToolTile extends StatelessWidget {
  const _WeChatToolTile({required this.cell});

  final _QaCell cell;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: cell.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(cell.icon, size: 28, color: const Color(0xFF353535)),
          ),
          const SizedBox(height: 8),
          Text(
            cell.label,
            style: DunesTypography.sans(
              fontSize: 12,
              color: const Color(0xFF7A7A7A),
            ),
          ),
        ],
      ),
    );
  }
}

class _QaCell {
  const _QaCell({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.voiceMode,
    this.voiceEnabled = true,
    required this.sending,
    required this.onToggleVoice,
    required this.onSend,
    this.onPlus,
    this.plusOpen = false,
    this.onEmoji,
    this.emojiPicker,
    this.secondaryIcon,
    this.onStop,
    this.onVoiceHoldStart,
    this.onVoiceHoldMove,
    this.onVoiceHoldEnd,
    this.onVoiceHoldCancel,
    this.recording = false,
    this.recordWillCancel = false,
    this.recordDurationMs = 0,
    this.enabled = true,
    this.hintText,
    this.focusNode,
    this.onInputFocused,
    this.backgroundColor,
    this.onAttemptPasteImage,
  });

  final TextEditingController controller;
  final bool voiceMode;
  final bool voiceEnabled;
  final bool sending;
  final VoidCallback onToggleVoice;
  final VoidCallback onSend;
  /// 右侧「+」：展开/收起工具面板（发送改由键盘「发送」键完成）。
  final VoidCallback? onPlus;
  final bool plusOpen;
  final VoidCallback? onEmoji;
  final Widget? emojiPicker;
  final IconData? secondaryIcon;
  final VoidCallback? onStop;
  final GestureLongPressStartCallback? onVoiceHoldStart;
  final GestureLongPressMoveUpdateCallback? onVoiceHoldMove;
  final GestureLongPressEndCallback? onVoiceHoldEnd;
  final VoidCallback? onVoiceHoldCancel;
  final bool recording;
  final bool recordWillCancel;
  final int recordDurationMs;
  final bool enabled;
  final String? hintText;
  final FocusNode? focusNode;
  final VoidCallback? onInputFocused;
  final Color? backgroundColor;
  /// 返回 true 表示已处理图片粘贴；false 则回退插入剪贴板文本。
  final Future<bool> Function()? onAttemptPasteImage;

  @override
  Widget build(BuildContext context) {
    final showStop = sending && onStop != null;
    final interactionLocked = !enabled || (sending && !showStop);
    final effectiveVoiceMode = voiceEnabled && voiceMode;
    final wide = isWideChatLayout(context);
    final showEmojiControl =
        !wide && (emojiPicker != null || onEmoji != null);
    final minLines = wide ? 3 : 1;
    final maxLines = wide ? 8 : 4;
    final fieldPadV = wide ? 14.0 : 10.0;
    // 发送按钮在最底部，必须避开 iOS home indicator，否则会被底部横条盖住。
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        wide ? 12 : 10,
        wide ? 10 : 8,
        wide ? 12 : 10,
        bottomInset > 0 ? bottomInset + 4 : (wide ? 12.0 : 8.0),
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFF7F7F7),
        border: const Border(top: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (voiceEnabled) ...[
            _WeChatCircleIconBtn(
              icon: effectiveVoiceMode
                  ? Icons.keyboard_alt_outlined
                  : Icons.mic_none_rounded,
              onTap: interactionLocked ? null : onToggleVoice,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: effectiveVoiceMode
                ? GestureDetector(
                    onLongPressStart: interactionLocked
                        ? null
                        : onVoiceHoldStart,
                    onLongPressMoveUpdate: interactionLocked
                        ? null
                        : onVoiceHoldMove,
                    onLongPressEnd: interactionLocked ? null : onVoiceHoldEnd,
                    onLongPressCancel: interactionLocked
                        ? null
                        : onVoiceHoldCancel,
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: recording
                            ? (recordWillCancel
                                  ? DunesColors.coral
                                  : const Color(0xFF8B72B7))
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        recording
                            ? (recordWillCancel
                                  ? '松开取消'
                                  : '松开发送 ${(recordDurationMs / 1000).toStringAsFixed(1)}s')
                            : '按住 说话',
                        style: DunesTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: recording ? Colors.white : DunesColors.text2,
                        ),
                      ),
                    ),
                  )
                : _ChatTextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled && !showStop,
                    minLines: minLines,
                    maxLines: maxLines,
                    wide: wide,
                    fieldPadV: fieldPadV,
                    hintText: hintText,
                    onInputFocused: onInputFocused,
                    onSend: interactionLocked ? null : onSend,
                    onAttemptPasteImage: interactionLocked
                        ? null
                        : onAttemptPasteImage,
                  ),
          ),
          if (!effectiveVoiceMode) ...[
            if (showEmojiControl) ...[
              const SizedBox(width: 6),
              if (emojiPicker != null)
                emojiPicker!
              else if (onEmoji != null)
                _WeChatCircleIconBtn(
                  icon: secondaryIcon ?? Icons.emoji_emotions_outlined,
                  onTap: interactionLocked ? null : onEmoji,
                ),
            ],
            const SizedBox(width: 6),
            _WeChatPlusBtn(
              showStop: showStop,
              sending: sending,
              locked: interactionLocked,
              plusOpen: plusOpen,
              onTap: showStop
                  ? onStop
                  : (interactionLocked ? null : (onPlus ?? onSend)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 微信风格圆形图标按钮（语音 / 表情）。
class _WeChatCircleIconBtn extends StatelessWidget {
  const _WeChatCircleIconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 26, color: const Color(0xFF1A1A1A)),
        ),
      ),
    );
  }
}

/// 微信风格圆形「+」按钮（主题紫）。
class _WeChatPlusBtn extends StatelessWidget {
  const _WeChatPlusBtn({
    required this.showStop,
    required this.sending,
    required this.locked,
    required this.plusOpen,
    required this.onTap,
  });

  final bool showStop;
  final bool sending;
  final bool locked;
  final bool plusOpen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = showStop
        ? const Color(0xFFB65252)
        : locked
        ? const Color(0xFFC9BEDD)
        : (plusOpen ? const Color(0xFF553B96) : const Color(0xFF7E64BD));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Ink(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: showStop
                ? const Icon(Icons.stop_rounded, size: 18, color: Colors.white)
                : sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    plusOpen ? Icons.close_rounded : Icons.add_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ChatTextField extends StatefulWidget {
  const _ChatTextField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.minLines,
    required this.maxLines,
    required this.wide,
    required this.fieldPadV,
    required this.hintText,
    required this.onInputFocused,
    required this.onSend,
    required this.onAttemptPasteImage,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final bool wide;
  final double fieldPadV;
  final String? hintText;
  final VoidCallback? onInputFocused;
  final VoidCallback? onSend;
  final Future<bool> Function()? onAttemptPasteImage;

  @override
  State<_ChatTextField> createState() => _ChatTextFieldState();
}

class _ChatTextFieldState extends State<_ChatTextField> {
  bool _handlingPaste = false;

  bool _isPasteKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return false;
    return HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
  }

  bool _isSendKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    // 宽屏：Enter 发送，Shift+Enter 换行（对齐微信 PC / admin-web）。
    return widget.wide && !HardwareKeyboard.instance.isShiftPressed;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_isSendKey(event)) {
      widget.onSend?.call();
      return KeyEventResult.handled;
    }
    if (!_isPasteKey(event) || widget.onAttemptPasteImage == null) {
      return KeyEventResult.ignored;
    }
    if (_handlingPaste) return KeyEventResult.ignored;
    _handlingPaste = true;
    unawaited(() async {
      try {
        final handled = await widget.onAttemptPasteImage!();
        if (handled || !mounted) return;
        // 无图片时手动插入文本，因本事件已拦截默认粘贴。
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text == null || text.isEmpty) return;
        final value = widget.controller.value;
        final selection = value.selection;
        final start = selection.isValid
            ? selection.start
            : value.text.length;
        final end = selection.isValid ? selection.end : value.text.length;
        final next = value.text.replaceRange(start, end, text);
        widget.controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: start + text.length),
        );
      } finally {
        _handlingPaste = false;
      }
    }());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        enableInteractiveSelection: true,
        // iOS / Android：键盘右下角显示「发送」（随系统键盘语言），
        // 宽屏仍可用 Enter 发送、Shift+Enter 换行（见 _isSendKey）。
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => widget.onSend?.call(),
        onTap: widget.onInputFocused,
        contextMenuBuilder: (context, editableTextState) {
          final value = editableTextState.textEditingValue;
          final selection = value.selection;
          final canInsertNewline = widget.enabled && selection.isValid;
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: <ContextMenuButtonItem>[
              if (canInsertNewline)
                ContextMenuButtonItem(
                  label: '换行',
                  onPressed: () {
                    final start = selection.start;
                    final end = selection.end;
                    final next = value.text.replaceRange(start, end, '\n');
                    widget.controller.value = TextEditingValue(
                      text: next,
                      selection: TextSelection.collapsed(offset: start + 1),
                    );
                    editableTextState.hideToolbar();
                  },
                ),
              ...editableTextState.contextMenuButtonItems,
            ],
          );
        },
        style: DunesTypography.sans(
          fontSize: widget.wide ? 15 : 16,
          height: widget.wide ? 1.55 : 1.35,
          color: DunesColors.text,
        ),
        decoration: InputDecoration(
          hintText: widget.hintText ?? '输入消息…',
          hintStyle: DunesTypography.sans(
            fontSize: widget.wide ? 15 : 16,
            color: const Color(0xFFB0B0B0),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: widget.fieldPadV,
          ),
          isDense: !widget.wide,
        ),
      ),
    );
  }
}

class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.message,
    required this.mine,
    required this.showSenderMeta,
    required this.readLabel,
    required this.content,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.onReadTap,
    this.readTapLabel,
    this.avatar,
    this.trailingAvatar,
    this.timeLabel,
    this.showTimeForMine = false,
  });

  final NativeChatMessage message;
  final bool mine;
  final bool showSenderMeta;
  final String? readLabel;
  final Widget content;
  final VoidCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onReadTap;
  final String? readTapLabel;
  final Widget? avatar;
  final Widget? trailingAvatar;
  final String? timeLabel;
  final bool showTimeForMine;

  @override
  Widget build(BuildContext context) {
    final time = (timeLabel ?? '').trim();
    final showMeta =
        showSenderMeta ||
        (mine && showTimeForMine && time.isNotEmpty) ||
        (!mine && time.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: onLongPress,
        onLongPressStart: onLongPressStart,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!mine) ...[
              avatar ?? const SizedBox(width: 32),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: mine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (showMeta)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 3,
                        left: 2,
                        right: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showSenderMeta && !mine)
                            Flexible(
                              child: Text(
                                message.senderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DunesTypography.mono(
                                  fontSize: 9.5,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                          if (showSenderMeta && !mine && time.isNotEmpty)
                            const SizedBox(width: 6),
                          if (!mine && time.isNotEmpty)
                            Text(
                              time,
                              style: DunesTypography.mono(
                                fontSize: 9.5,
                                color: DunesColors.text3,
                              ),
                            ),
                          if (mine && showTimeForMine && time.isNotEmpty) ...[
                            Text(
                              time,
                              style: DunesTypography.mono(
                                fontSize: 9.5,
                                color: DunesColors.text3,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              message.senderName,
                              style: DunesTypography.mono(
                                fontSize: 9.5,
                                color: DunesColors.text3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  content,
                  if (readLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 2),
                      child: Text(
                        readLabel!,
                        style: DunesTypography.mono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: readLabel == '已读'
                              ? DunesColors.readReceipt
                              : DunesColors.text3,
                        ),
                      ),
                    )
                  else if (onReadTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 2),
                      child: GestureDetector(
                        onTap: onReadTap,
                        child: Text(
                          (readTapLabel ?? '查看已读').trim(),
                          style: DunesTypography.mono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: (readTapLabel ?? '').trim() != '未读'
                                ? DunesColors.readReceipt
                                : DunesColors.text3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (mine) ...[
              const SizedBox(width: 8),
              trailingAvatar ?? avatar ?? const SizedBox(width: 32),
            ],
          ],
        ),
      ),
    );
  }
}

class ChatTextBubble extends StatelessWidget {
  const ChatTextBubble({
    super.key,
    required this.text,
    required this.mine,
    this.quote,
    this.onQuoteTap,
    this.onSelectionQuote,
    this.onSelectionForward,
    this.onSelectionMulti,
    this.onSelectionRecall,
    this.enableSelection = true,
  });

  final String text;
  final bool mine;
  final ChatMessageQuote? quote;
  final VoidCallback? onQuoteTap;
  final ValueChanged<String>? onSelectionQuote;
  final ValueChanged<String>? onSelectionForward;
  final ValueChanged<String>? onSelectionMulti;
  final VoidCallback? onSelectionRecall;
  final bool enableSelection;

  String _selectedText(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    final start = selection.start;
    final end = selection.end;
    if (start < 0 || end <= start || end > value.text.length) return '';
    return value.text.substring(start, end).trim();
  }

  TextSpan _buildMentionTextSpan() {
    final baseStyle = DunesTypography.sans(
      fontSize: 13,
      height: 1.5,
      color: mine ? Colors.white : DunesColors.text,
    );
    final mentionStyle = baseStyle.copyWith(
      color: mine ? Colors.white : const Color(0xFF3B5BDB),
      fontWeight: FontWeight.w600,
    );
    final linkStyle = baseStyle.copyWith(
      color: mine ? const Color(0xFFE8DEFF) : const Color(0xFF3B5BDB),
      decoration: TextDecoration.underline,
      decorationColor: mine ? const Color(0xFFE8DEFF) : const Color(0xFF3B5BDB),
    );
    final spans = <InlineSpan>[];
    // URL 优先于 @mention，避免把链接里的 @ 误高亮。
    final tokenRe = RegExp(
      r'(https?:\/\/\S+)|(@[^@\s]+)',
      caseSensitive: false,
    );
    var start = 0;
    for (final match in tokenRe.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: baseStyle),
        );
      }
      final url = match.group(1);
      final mention = match.group(2);
      if (url != null && url.isNotEmpty) {
        // 去掉尾部常见标点，避免把句号/逗号带进链接。
        var href = url;
        var trailing = '';
        while (href.isNotEmpty &&
            '.,;:!?)]》」』、'.contains(href[href.length - 1])) {
          trailing = href[href.length - 1] + trailing;
          href = href.substring(0, href.length - 1);
        }
        spans.add(
          TextSpan(
            text: href,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                final uri = Uri.tryParse(href);
                if (uri == null) return;
                unawaited(
                  launchUrl(uri, mode: LaunchMode.externalApplication),
                );
              },
          ),
        );
        if (trailing.isNotEmpty) {
          spans.add(TextSpan(text: trailing, style: baseStyle));
        }
      } else if (mention != null) {
        spans.add(TextSpan(text: mention, style: mentionStyle));
      }
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        // 扁平化：己方纯色；对方浅底 + 细描边，避免与聊天背景融在一起。
        color: mine ? const Color(0xFF7E64BD) : DunesColors.bgApp,
        border: mine ? null : Border.all(color: DunesColors.borderSoft),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(mine ? 12 : 4),
          topRight: Radius.circular(mine ? 4 : 12),
          bottomLeft: const Radius.circular(12),
          bottomRight: const Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enableSelection)
            SelectableText.rich(
              _buildMentionTextSpan(),
              contextMenuBuilder: (context, editableTextState) {
                final selected = _selectedText(
                  editableTextState.textEditingValue,
                );
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: <ContextMenuButtonItem>[
                    ContextMenuButtonItem(
                      label: '复制',
                      onPressed: () {
                        editableTextState.copySelection(
                          SelectionChangedCause.toolbar,
                        );
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '引用',
                      onPressed: () {
                        onSelectionQuote?.call(selected);
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '转发',
                      onPressed: () {
                        onSelectionForward?.call(selected);
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '多选',
                      onPressed: () {
                        onSelectionMulti?.call(selected);
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '全选',
                      onPressed: () {
                        editableTextState.selectAll(
                          SelectionChangedCause.toolbar,
                        );
                      },
                    ),
                    if (onSelectionRecall != null)
                      ContextMenuButtonItem(
                        label: '撤回',
                        onPressed: () {
                          onSelectionRecall?.call();
                          editableTextState.hideToolbar();
                        },
                      ),
                  ],
                );
              },
            )
          else
            RichText(text: _buildMentionTextSpan()),
          if (quote != null && !quote!.isEmpty) ...[
            const SizedBox(height: 6),
            ChatQuoteBlock(quote: quote!, mine: mine, onTap: onQuoteTap),
          ],
        ],
      ),
    );
  }
}

/// 引用条（气泡内 / 输入框上方预览共用样式）。
class ChatQuoteBlock extends StatelessWidget {
  const ChatQuoteBlock({
    super.key,
    required this.quote,
    required this.mine,
    this.onTap,
    this.compact = false,
  });

  final ChatMessageQuote quote;
  final bool mine;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildPreviewBar(context);
    }
    return _buildBelowText(context);
  }

  Widget _buildPreviewBar(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: DunesColors.accent, width: 2.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quote.senderName.isEmpty ? '消息' : quote.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quote.preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 11,
              height: 1.35,
              color: DunesColors.text3,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }

  Widget _buildBelowText(BuildContext context) {
    final divider = mine
        ? Colors.white.withValues(alpha: 0.28)
        : DunesColors.borderSoft;
    final accent = mine
        ? Colors.white.withValues(alpha: 0.92)
        : DunesColors.accent;
    final textColor = mine
        ? Colors.white.withValues(alpha: 0.72)
        : DunesColors.text3;

    final child = Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: compact ? 5 : 6, left: compact ? 0 : 0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quote.senderName.isEmpty ? '消息' : quote.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: compact ? 11 : 11,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quote.preview,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: compact ? 11 : 12,
              height: 1.35,
              color: textColor,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}

/// 输入框上方：当前待发送的引用预览（微信式）。
class ChatQuotePreviewBar extends StatelessWidget {
  const ChatQuotePreviewBar({
    super.key,
    required this.quote,
    required this.onCancel,
  });

  final ChatMessageQuote quote;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ChatQuoteBlock(quote: quote, mine: false, compact: true),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onCancel,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: DunesColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatDateDivider extends StatelessWidget {
  const ChatDateDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Row(
        children: [
          const Expanded(
            child: Divider(height: 1, color: DunesColors.borderSoft),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Text(
              label.toUpperCase(),
              style: DunesTypography.mono(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.06 * 9.5,
                color: DunesColors.text3,
              ),
            ),
          ),
          const Expanded(
            child: Divider(height: 1, color: DunesColors.borderSoft),
          ),
        ],
      ),
    );
  }
}

class ChatSystemPill extends StatelessWidget {
  const ChatSystemPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          text,
          style: DunesTypography.mono(fontSize: 10, color: DunesColors.text3),
        ),
      ),
    );
  }
}

class ChatVoiceBubble extends StatefulWidget {
  const ChatVoiceBubble({
    super.key,
    required this.playKey,
    required this.durationSec,
    required this.mine,
    required this.resolveUrl,
    this.onPlayError,
  });

  final String playKey;
  final int durationSec;
  final bool mine;
  final Future<String> Function() resolveUrl;
  final ValueChanged<String>? onPlayError;

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  @override
  void initState() {
    super.initState();
    ChatVoicePlayer.instance.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    ChatVoicePlayer.instance.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() => setState(() {});

  Future<void> _toggle() async {
    try {
      final url = await widget.resolveUrl();
      if (url.trim().isEmpty) {
        widget.onPlayError?.call('语音地址为空');
        return;
      }
      await ChatVoicePlayer.instance.toggle(widget.playKey, url);
    } catch (e) {
      widget.onPlayError?.call('播放失败：${friendlyErrorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = ChatVoicePlayer.instance.playingKey == widget.playKey;
    return GestureDetector(
      onTap: () => unawaited(_toggle()),
      child: Container(
        constraints: BoxConstraints(
          minWidth: 80 + (widget.durationSec * 4).clamp(0, 80).toDouble(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: widget.mine ? const Color(0xFF7E64BD) : DunesColors.bgApp,
          border: widget.mine
              ? null
              : Border.all(color: DunesColors.borderSoft),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 18,
              color: widget.mine ? Colors.white : DunesColors.accent,
            ),
            const SizedBox(width: 6),
            ...List.generate(4, (i) {
              return Container(
                width: 3,
                height: playing ? 8.0 + (i * 3) : 6.0 + i,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: (widget.mine ? Colors.white : DunesColors.accent)
                      .withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
            const SizedBox(width: 8),
            Text(
              '${widget.durationSec}s',
              style: DunesTypography.mono(
                fontSize: 10,
                color: widget.mine ? Colors.white70 : DunesColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatFileAttach extends StatelessWidget {
  const ChatFileAttach({
    super.key,
    required this.fileName,
    required this.mine,
    required this.onTap,
    this.onSecondaryTapDown,
    this.isPdf = false,
    this.uploadProgress,
  });

  final String fileName;
  final bool mine;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool isPdf;
  /// 0~1；非空时在图标上展示圆形上传进度。
  final double? uploadProgress;

  @override
  Widget build(BuildContext context) {
    final progress = uploadProgress;
    final uploading = progress != null;
    return GestureDetector(
      onTap: uploading ? null : onTap,
      onSecondaryTapDown: uploading ? null : onSecondaryTapDown,
      child: Container(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: DunesColors.bgSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 16,
                      color: isPdf ? DunesColors.coral : DunesColors.text2,
                    ),
                  ),
                  if (uploading)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: progress > 0 && progress < 1 ? progress : null,
                        strokeWidth: 2.5,
                        color: const Color(0xFF7E64BD),
                        backgroundColor: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (uploading) ...[
                    const SizedBox(height: 2),
                    Text(
                      progress > 0
                          ? '上传中 ${(progress * 100).round()}%'
                          : '上传中…',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatPersonAvatar extends StatelessWidget {
  const ChatPersonAvatar({
    super.key,
    required this.initial,
    required this.seed,
    this.size = 32,
    this.showOnline = false,
  });

  final String initial;
  final int seed;
  final double size;
  final bool showOnline;

  @override
  Widget build(BuildContext context) {
    final style = InboxFormat.personStyle(seed);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: style.gradient.first,
            borderRadius: BorderRadius.circular(size * 0.18),
          ),
          child: Text(
            initial.isEmpty ? '?' : initial,
            style: TextStyle(
              color: style.textColor,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (showOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: DunesColors.green,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: DunesColors.bgApp, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class ChatEmojiPanel extends StatelessWidget {
  const ChatEmojiPanel({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  static const _emojis = <String>[
    '😀',
    '😁',
    '😂',
    '🤣',
    '😊',
    '😍',
    '😘',
    '😎',
    '🙂',
    '😉',
    '😢',
    '😭',
    '😡',
    '👍',
    '👏',
    '🙏',
    '❤️',
    '🔥',
    '✅',
    '❌',
    '💯',
    '🎉',
    '🤔',
    '😅',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: _emojis.length,
        itemBuilder: (_, i) => InkWell(
          onTap: () => onPick(_emojis[i]),
          child: Center(
            child: Text(_emojis[i], style: const TextStyle(fontSize: 22)),
          ),
        ),
      ),
    );
  }
}

class CommBackScaffold extends StatelessWidget {
  const CommBackScaffold({
    super.key,
    required this.crumb,
    required this.title,
    required this.onBack,
    required this.body,
    this.trailing,
  });

  final String crumb;
  final String title;
  final VoidCallback onBack;
  final Widget body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: DunesColors.borderSoft),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.chevron_left_rounded, size: 28),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          crumb,
                          style: DunesTypography.mono(
                            fontSize: 9.5,
                            color: DunesColors.text3,
                          ),
                        ),
                        Text(
                          title,
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing case final widget?) widget,
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class NotiCard extends StatelessWidget {
  const NotiCard({
    super.key,
    required this.title,
    required this.body,
    required this.timeLabel,
    this.tag,
    this.unread = false,
    this.onTap,
    this.read = false,
    this.showReadMark = false,
  });

  final String title;
  final String body;
  final String timeLabel;
  final String? tag;
  final bool unread;

  /// 点击回调；非空时整张卡片可点。
  final VoidCallback? onTap;

  /// 是否已读（用于显示勾选标记与淡化样式）。
  final bool read;

  /// 是否展示右侧"已读/点击已读"勾选标记。
  final bool showReadMark;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: read
              ? DunesColors.borderSoft
              : (unread
                    ? DunesColors.coral.withValues(alpha: 0.35)
                    : DunesColors.borderSoft),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (timeLabel.isNotEmpty)
                Text(
                  timeLabel,
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    color: DunesColors.text3,
                  ),
                ),
              if (showReadMark) ...[
                const SizedBox(width: 8),
                Icon(
                  read ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: read ? DunesColors.accent : DunesColors.text3,
                ),
              ],
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: DunesTypography.sans(
                fontSize: 12.5,
                color: DunesColors.text2,
                height: 1.45,
              ),
            ),
          ],
          if (tag != null && tag!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: DunesColors.accentSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tag!,
                style: DunesTypography.mono(
                  fontSize: 9,
                  color: DunesColors.accentDeep,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}
