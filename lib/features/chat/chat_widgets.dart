import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
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
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onTapTitle;
  final List<Widget> actions;
  final Widget? leadingAvatar;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
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
      _QaCell(icon: Icons.assignment_outlined, label: '转发审批', onTap: onApproval),
      if (showAt && onAt != null)
        _QaCell(icon: Icons.alternate_email, label: '@', onTap: onAt!),
      if (showVideo && onVideo != null)
        _QaCell(icon: Icons.videocam_outlined, label: '视频', onTap: onVideo!)
      else if (onEmoji != null)
        _QaCell(icon: Icons.emoji_emotions_outlined, label: '表情', onTap: onEmoji!),
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
                          style: DunesTypography.sans(fontSize: 9.5, color: DunesColors.text3),
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
    required this.sending,
    required this.onToggleVoice,
    required this.onSend,
    this.onEmoji,
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
  });

  final TextEditingController controller;
  final bool voiceMode;
  final bool sending;
  final VoidCallback onToggleVoice;
  final VoidCallback onSend;
  final VoidCallback? onEmoji;
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

  @override
  Widget build(BuildContext context) {
    final showStop = sending && onStop != null;
    final interactionLocked = !enabled || (sending && !showStop);
    // 发送按钮在最底部，必须避开 iOS home indicator，否则会被底部横条盖住。
    // 有安全区时用安全区作为下内边距（刚好托起按钮、不额外叠加），安卓为 0 时回退 9px。
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 9, 12, bottomInset > 0 ? bottomInset : 9),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _RoundIconBtn(
            icon: voiceMode ? Icons.keyboard_outlined : Icons.mic_none_rounded,
            onTap: interactionLocked ? null : onToggleVoice,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: voiceMode
                ? GestureDetector(
                    onLongPressStart: interactionLocked ? null : onVoiceHoldStart,
                    onLongPressMoveUpdate: interactionLocked ? null : onVoiceHoldMove,
                    onLongPressEnd: interactionLocked ? null : onVoiceHoldEnd,
                    onLongPressCancel: interactionLocked ? null : onVoiceHoldCancel,
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: recording
                            ? (recordWillCancel ? DunesColors.coral : const Color(0xFF7E64BD))
                            : DunesColors.bgSoft,
                        borderRadius: BorderRadius.circular(18),
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
                : TextField(
                    controller: controller,
                    enabled: enabled && !showStop,
                    minLines: 1,
                    maxLines: 4,
                    style: DunesTypography.sans(fontSize: 13.5, color: DunesColors.text),
                    decoration: InputDecoration(
                      hintText: hintText ?? '输入消息…',
                      hintStyle: DunesTypography.sans(fontSize: 13.5, color: DunesColors.text3),
                      filled: true,
                      fillColor: DunesColors.bgSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: interactionLocked ? null : (_) => onSend(),
                  ),
          ),
          if (!voiceMode) ...[
            const SizedBox(width: 8),
            if (onEmoji != null)
              _RoundIconBtn(
                icon: secondaryIcon ?? Icons.emoji_emotions_outlined,
                onTap: interactionLocked ? null : onEmoji,
              ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: showStop ? onStop : (interactionLocked ? null : onSend),
                child: Ink(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: showStop
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF8A4A4A), Color(0xFF6A3333)],
                          )
                        : interactionLocked
                            ? null
                            : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF7E64BD), Color(0xFF553B96)],
                              ),
                    color: interactionLocked && !showStop
                        ? DunesColors.text3.withValues(alpha: 0.35)
                        : null,
                  ),
                  child: showStop
                      ? const Icon(Icons.stop_rounded, size: 18, color: Colors.white)
                      : sending
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
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
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: DunesColors.text2),
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
  final VoidCallback? onReadTap;
  final String? readTapLabel;
  final Widget? avatar;
  final Widget? trailingAvatar;
  final String? timeLabel;
  final bool showTimeForMine;

  @override
  Widget build(BuildContext context) {
    final time = (timeLabel ?? '').trim();
    final showMeta = showSenderMeta || (mine && showTimeForMine && time.isNotEmpty) || (!mine && time.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            avatar ?? const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showMeta)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showSenderMeta && !mine)
                          Flexible(
                            child: Text(
                              message.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3),
                            ),
                          ),
                        if (showSenderMeta && !mine && time.isNotEmpty) const SizedBox(width: 6),
                        if (!mine && time.isNotEmpty)
                          Text(time, style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
                        if (mine && showTimeForMine && time.isNotEmpty) ...[
                          Text(time, style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
                          const SizedBox(width: 6),
                          Text(
                            message.senderName,
                            style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3),
                          ),
                        ],
                      ],
                    ),
                  ),
                GestureDetector(
                  onLongPress: onLongPress,
                  child: content,
                ),
                if (readLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 2),
                    child: Text(
                      readLabel!,
                      style: DunesTypography.mono(
                        fontSize: 9,
                        color: message.peerRead ? DunesColors.accent : DunesColors.text3,
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
                        style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3),
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
    );
  }
}

class ChatTextBubble extends StatelessWidget {
  const ChatTextBubble({super.key, required this.text, required this.mine});

  final String text;
  final bool mine;

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
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 13,
          height: 1.5,
          color: mine ? Colors.white : DunesColors.text,
        ),
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
          const Expanded(child: Divider(height: 1, color: DunesColors.borderSoft)),
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
          const Expanded(child: Divider(height: 1, color: DunesColors.borderSoft)),
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
  });

  final String playKey;
  final int durationSec;
  final bool mine;
  final Future<String> Function() resolveUrl;

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
    final url = await widget.resolveUrl();
    await ChatVoicePlayer.instance.toggle(widget.playKey, url);
  }

  @override
  Widget build(BuildContext context) {
    final playing = ChatVoicePlayer.instance.playingKey == widget.playKey;
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        constraints: BoxConstraints(minWidth: 80 + (widget.durationSec * 4).clamp(0, 80).toDouble()),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: widget.mine
              ? const LinearGradient(colors: [Color(0xFF7E64BD), Color(0xFF553B96)])
              : null,
          color: widget.mine ? null : DunesColors.bgApp,
          border: widget.mine ? null : Border.all(color: DunesColors.borderSoft),
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
                  color: (widget.mine ? Colors.white : DunesColors.accent).withValues(alpha: 0.75),
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
  });

  final String fileName;
  final bool mine;
  final VoidCallback onTap;

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
              child: const Icon(Icons.insert_drive_file_outlined, size: 16, color: DunesColors.text2),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w500),
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
            style: TextStyle(color: style.textColor, fontSize: size * 0.38, fontWeight: FontWeight.w500),
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
    '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎',
    '🙂', '😉', '😢', '😭', '😡', '👍', '👏', '🙏',
    '❤️', '🔥', '✅', '❌', '💯', '🎉', '🤔', '😅',
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
          child: Center(child: Text(_emojis[i], style: const TextStyle(fontSize: 22))),
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
                border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
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
                          style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3),
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
  });

  final String title;
  final String body;
  final String timeLabel;
  final String? tag;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: unread ? DunesColors.coral.withValues(alpha: 0.35) : DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: DunesTypography.sans(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (timeLabel.isNotEmpty)
                Text(timeLabel, style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body, style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text2, height: 1.45)),
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
                style: DunesTypography.mono(fontSize: 9, color: DunesColors.accentDeep),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
