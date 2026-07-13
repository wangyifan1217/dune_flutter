import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      _QaCell(icon: Icons.photo_camera_outlined, label: '拍照', onTap: onCamera),
      _QaCell(icon: Icons.photo_library_outlined, label: '相册', onTap: onAlbum),
      _QaCell(icon: Icons.attach_file, label: '文件', onTap: onFile),
      _QaCell(
        icon: Icons.assignment_outlined,
        label: '转发审批',
        onTap: onApproval,
      ),
      if (showAt && onAt != null)
        _QaCell(icon: Icons.alternate_email, label: '@', onTap: onAt!),
      if (showVideo && onVideo != null)
        _QaCell(icon: Icons.videocam_outlined, label: '视频', onTap: onVideo!)
      else if (onEmoji != null)
        _QaCell(
          icon: Icons.emoji_emotions_outlined,
          label: '表情',
          onTap: onEmoji!,
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      // 固定单行高度：避免在更宽的屏幕（如大屏 iPhone）上按宽高比把整排撑高。
      child: Row(
        children: cells
            .map(
              (c) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: c.onTap,
                  child: SizedBox(
                    height: 46,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(c.icon, size: 18, color: DunesColors.text2),
                        const SizedBox(height: 3),
                        Text(
                          c.label,
                          style: DunesTypography.sans(
                            fontSize: 9.5,
                            color: DunesColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
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
    final fieldPadV = wide ? 14.0 : 9.0;
    // 宽屏输入区可以保留多行，但发送按钮应是紧凑的辅助操作，
    // 不应与整个输入框等高。
    final sendH = wide ? 44.0 : 40.0;
    // 发送按钮在最底部，必须避开 iOS home indicator，否则会被底部横条盖住。
    // 有安全区时用安全区作为下内边距（刚好托起按钮、不额外叠加），安卓为 0 时回退 9px。
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        wide ? 12 : 8,
        wide ? 10 : 7,
        wide ? 12 : 8,
        // 保留 Home Indicator 安全距离，并额外上移少量，避免输入栏贴底。
        bottomInset > 0 ? bottomInset + 6 : (wide ? 12.0 : 9.0),
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? DunesColors.bgApp,
        border: const Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (voiceEnabled) ...[
            _RoundIconBtn(
              icon: effectiveVoiceMode
                  ? Icons.keyboard_outlined
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
                        borderRadius: BorderRadius.circular(7),
                        border: recording
                            ? null
                            : Border.all(color: DunesColors.borderSoft),
                      ),
                      child: Text(
                        recording
                            ? (recordWillCancel
                                  ? '松开取消'
                                  : '松开发送 ${(recordDurationMs / 1000).toStringAsFixed(1)}s')
                            : '按住 说话',
                        style: DunesTypography.sans(
                          fontSize: 13.5,
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
              const SizedBox(width: 8),
              if (emojiPicker != null)
                emojiPicker!
              else if (onEmoji != null)
                _RoundIconBtn(
                  icon: secondaryIcon ?? Icons.emoji_emotions_outlined,
                  onTap: interactionLocked ? null : onEmoji,
                ),
            ],
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: showStop ? onStop : (interactionLocked ? null : onSend),
                child: Ink(
                  width: wide ? 56 : 52,
                  height: sendH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: showStop
                        ? const Color(0xFFB65252)
                        : interactionLocked
                        ? const Color(0xFFC9BEDD)
                        : const Color(0xFF8B72B7),
                  ),
                  child: Center(
                    child: showStop
                        ? const Icon(
                            Icons.stop_rounded,
                            size: 18,
                            color: Colors.white,
                          )
                        : sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '发送',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ],
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
        textInputAction: widget.wide
            ? TextInputAction.newline
            : TextInputAction.send,
        onTap: widget.onInputFocused,
        contextMenuBuilder: (context, editableTextState) {
          return AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          );
        },
        style: DunesTypography.sans(
          fontSize: widget.wide ? 15 : 13.5,
          height: widget.wide ? 1.55 : null,
          color: DunesColors.text,
        ),
        decoration: InputDecoration(
          hintText: widget.hintText ?? '输入消息…',
          hintStyle: DunesTypography.sans(
            fontSize: widget.wide ? 15 : 13.5,
            color: DunesColors.text3,
          ),
          filled: true,
          fillColor: const Color(0xFFFFFEFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFFE3DCEE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFFE3DCEE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFF9A82C5)),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: widget.fieldPadV,
          ),
          isDense: !widget.wide,
        ),
        onSubmitted: widget.wide || widget.onSend == null
            ? null
            : (_) => widget.onSend!(),
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, required this.onTap});
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
          width: 40,
          height: 40,
          child: Icon(icon, size: 23, color: DunesColors.text2),
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
    final spans = <InlineSpan>[];
    final regex = RegExp(r'@[^@\s]+');
    var start = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: baseStyle),
        );
      }
      spans.add(TextSpan(text: match.group(0), style: mentionStyle));
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
        color: mine ? null : DunesColors.bgApp,
        gradient: mine
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7E64BD), Color(0xFF553B96)],
              )
            : null,
        border: mine ? null : Border.all(color: DunesColors.borderSoft),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(mine ? 16 : 4),
          topRight: Radius.circular(mine ? 4 : 16),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
        boxShadow: mine
            ? const [
                BoxShadow(
                  color: Color(0x4D553B96),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
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
                        if (selected.isNotEmpty)
                          onSelectionQuote?.call(selected);
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '转发',
                      onPressed: () {
                        if (selected.isNotEmpty) {
                          onSelectionForward?.call(selected);
                        }
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '多选',
                      onPressed: () {
                        if (selected.isNotEmpty)
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
          border: Border.all(color: DunesColors.borderSoft),
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
          gradient: widget.mine
              ? const LinearGradient(
                  colors: [Color(0xFF7E64BD), Color(0xFF553B96)],
                )
              : null,
          color: widget.mine ? null : DunesColors.bgApp,
          border: widget.mine
              ? null
              : Border.all(color: DunesColors.borderSoft),
          borderRadius: BorderRadius.circular(16),
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
    this.isPdf = false,
  });

  final String fileName;
  final bool mine;
  final VoidCallback onTap;
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: DunesColors.bgApp,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        child: Row(
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
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
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
            gradient: LinearGradient(colors: style.gradient),
            borderRadius: BorderRadius.circular(size / 2),
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
