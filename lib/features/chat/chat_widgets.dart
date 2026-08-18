import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'chat_file_type_icon.dart';
import 'chat_quote.dart';
import '../conversation/conversation_models.dart';
import '../conversation/inbox_format.dart';
import 'chat_voice_player.dart';
import 'voice_asr_store.dart';

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
    this.onCameraLongPress,
    this.onScreenshot,
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

  /// 长按拍照：录制小视频（微信式）。
  final VoidCallback? onCameraLongPress;

  /// PC：微信式区域截图（截完可裁剪编辑后发送）。
  final VoidCallback? onScreenshot;
  final VoidCallback? onAt;
  final VoidCallback? onEmoji;
  final VoidCallback? onVideo;
  final bool showAt;
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    final wide = isWideChatLayout(context);
    // PC 宽屏：图片 + 视频 + 截图 + 文件；APP：微信式宫格（相册 / 拍照长按拍视频 / 文件）。
    final cells = <_QaCell>[
      if (wide) ...[
        _QaCell(icon: Icons.photo_outlined, label: '图片', onTap: onAlbum),
        if (showVideo && onVideo != null)
          _QaCell(
            icon: Icons.videocam_outlined,
            label: '视频',
            onTap: onVideo!,
          ),
        if (onScreenshot != null)
          _QaCell(
            icon: Icons.crop_free_rounded,
            label: '截图',
            hint: '系统截图 Ctrl+Alt+A',
            onTap: onScreenshot!,
          ),
        _QaCell(icon: Icons.attach_file, label: '文件', onTap: onFile),
      ] else ...[
        _QaCell(icon: Icons.photo_outlined, label: '相册', onTap: onAlbum),
        _QaCell(
          icon: Icons.photo_camera_outlined,
          label: '拍照',
          onTap: onCamera,
          onLongPress: onCameraLongPress,
          hint: onCameraLongPress == null ? null : '长按拍视频',
        ),
        if (showVideo && onVideo != null)
          _QaCell(
            icon: Icons.videocam_outlined,
            label: '视频',
            onTap: onVideo!,
          ),
        _QaCell(icon: Icons.folder_outlined, label: '文件', onTap: onFile),
      ],
      _QaCell(
        icon: Icons.assignment_outlined,
        label: '转发审批',
        onTap: onApproval,
      ),
      if (showAt && onAt != null)
        _QaCell(icon: Icons.alternate_email, label: '@', onTap: onAt!),
      if (wide && onEmoji != null)
        _QaCell(
          icon: Icons.emoji_emotions_outlined,
          label: '表情',
          onTap: onEmoji!,
        ),
    ];
    if (wide) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        decoration: const BoxDecoration(
          color: DunesColors.bgApp,
          border: Border(top: BorderSide(color: DunesColors.borderSoft)),
        ),
        child: Row(
          children: cells
              .map(
                (c) => Expanded(
                  child: Tooltip(
                    message: (c.hint ?? '').isNotEmpty
                        ? '${c.label}（${c.hint}）'
                        : c.label,
                    waitDuration: const Duration(milliseconds: 400),
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
                ),
              )
              .toList(),
        ),
      );
    }
    // APP：微信式宫格，每行最多 4 个。
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
      onLongPress: cell.onLongPress,
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
          if ((cell.hint ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              cell.hint!,
              style: DunesTypography.sans(
                fontSize: 9,
                color: const Color(0xFFAAAAAA),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QaCell {
  const _QaCell({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.hint,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? hint;
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
    this.recordWillTranscribe = false,
    this.recordDurationMs = 0,
    this.enabled = true,
    this.hintText,
    this.focusNode,
    this.onInputFocused,
    this.showMobilePlusButton = true,
    this.backgroundColor,
    this.onAttemptPasteImage,
    this.inputHeight,
    this.onInputHeightDrag,
  });

  final TextEditingController controller;
  final bool voiceMode;
  final bool voiceEnabled;
  final bool sending;
  final VoidCallback onToggleVoice;
  final VoidCallback onSend;

  /// 右侧「+」：展开/收起工具面板；有输入文字时改为「发送」按钮
  ///（荣耀等中文 IME 在多行输入下常只显示「换行」，不能只靠键盘发送）。
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
  final bool recordWillTranscribe;
  final int recordDurationMs;
  final bool enabled;
  final String? hintText;
  final FocusNode? focusNode;
  final VoidCallback? onInputFocused;

  /// 个别纯文本会话（如机器人追问）不需要移动端「+」工具入口。
  final bool showMobilePlusButton;
  final Color? backgroundColor;

  /// 返回 true 表示已处理图片粘贴；false 则回退插入剪贴板文本。
  final Future<bool> Function()? onAttemptPasteImage;

  /// PC：固定输入框高度；为 null 时按 min/maxLines 自动增高。
  final double? inputHeight;

  /// PC：拖拽输入框上沿调整高度（deltaDy>0 为向下拖）。
  final ValueChanged<double>? onInputHeightDrag;

  @override
  Widget build(BuildContext context) {
    final wide = isWideChatLayout(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final canResize = wide && onInputHeightDrag != null && inputHeight != null;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final showStop = sending && onStop != null;
        final interactionLocked = !enabled || (sending && !showStop);
        final effectiveVoiceMode = voiceEnabled && voiceMode;
        final showEmojiControl =
            !wide && (emojiPicker != null || onEmoji != null);
        final minLines = wide ? 3 : 1;
        final maxLines = wide ? 8 : 4;
        final fieldPadV = wide ? 14.0 : 10.0;
        final hasText = controller.text.trim().isNotEmpty;
        // 有字时展示「发送」；无字时展示「+」（若允许）。
        final showMobileTrailing = !effectiveVoiceMode &&
            !wide &&
            (showStop || hasText || showMobilePlusButton);
        return Container(
          padding: EdgeInsets.fromLTRB(
            wide ? 12 : 10,
            canResize ? 0 : (wide ? 10 : 8),
            wide ? 12 : 10,
            bottomInset > 0
                ? bottomInset + (wide ? 6 : 4)
                : (wide ? 12.0 : 8.0),
          ),
          decoration: BoxDecoration(
            color: backgroundColor ??
                (wide ? DunesColors.bgApp : const Color(0xFFF7F7F7)),
            border: Border(
              top: BorderSide(
                color: wide ? DunesColors.borderSoft : const Color(0xFFE8E8E8),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canResize)
                _ComposerResizeHandle(onDrag: onInputHeightDrag!),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (voiceEnabled) ...[
                    if (wide)
                      _RoundIconBtn(
                        icon: effectiveVoiceMode
                            ? Icons.keyboard_outlined
                            : Icons.mic_none_rounded,
                        onTap: interactionLocked ? null : onToggleVoice,
                      )
                    else
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
                            onLongPressEnd:
                                interactionLocked ? null : onVoiceHoldEnd,
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
                                          : (recordWillTranscribe
                                                ? const Color(0xFF3C8B86)
                                                : const Color(0xFF8B72B7)))
                                    : Colors.white,
                                borderRadius:
                                    BorderRadius.circular(wide ? 7 : 8),
                                border: recording || !wide
                                    ? null
                                    : Border.all(color: DunesColors.borderSoft),
                              ),
                              child: Text(
                                recording
                                    ? (recordWillCancel
                                          ? '松开取消'
                                          : recordWillTranscribe
                                          ? '松开转文字 ${(recordDurationMs / 1000).toStringAsFixed(1)}s'
                                          : '松开发送 ${(recordDurationMs / 1000).toStringAsFixed(1)}s')
                                    : '按住 说话',
                                style: DunesTypography.sans(
                                  fontSize: wide ? 13.5 : 15,
                                  fontWeight: FontWeight.w500,
                                  color: recording
                                      ? Colors.white
                                      : DunesColors.text2,
                                ),
                              ),
                            ),
                          )
                        : wide
                        ? _PcComposerBox(
                            height: inputHeight ?? 108,
                            controller: controller,
                            focusNode: focusNode,
                            enabled: enabled && !showStop,
                            // 框内另有发送行占高，垂直 padding 略收，避免拖矮后首行被裁切。
                            fieldPadV: 10,
                            hintText: hintText,
                            onInputFocused: onInputFocused,
                            onSend: interactionLocked ? null : onSend,
                            onAttemptPasteImage: interactionLocked
                                ? null
                                : onAttemptPasteImage,
                            showStop: showStop,
                            sending: sending,
                            interactionLocked: interactionLocked,
                            onStop: onStop,
                          )
                        : _ChatTextField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: enabled && !showStop,
                            minLines: minLines,
                            maxLines: maxLines,
                            fixedHeight: inputHeight,
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
                  if (showMobileTrailing) ...[
                    if (showEmojiControl) ...[
                      const SizedBox(width: 6),
                      if (emojiPicker != null)
                        emojiPicker!
                      else if (onEmoji != null)
                        _WeChatCircleIconBtn(
                          icon:
                              secondaryIcon ?? Icons.emoji_emotions_outlined,
                          onTap: interactionLocked ? null : onEmoji,
                        ),
                    ],
                    const SizedBox(width: 6),
                    if (showStop)
                      _WeChatPlusBtn(
                        showStop: true,
                        sending: sending,
                        locked: false,
                        plusOpen: false,
                        onTap: onStop,
                      )
                    else if (hasText)
                      _WeChatSendBtn(
                        sending: sending,
                        locked: interactionLocked,
                        onTap: interactionLocked ? null : onSend,
                      )
                    else
                      _WeChatPlusBtn(
                        showStop: false,
                        sending: sending,
                        locked: interactionLocked,
                        plusOpen: plusOpen,
                        onTap: interactionLocked
                            ? null
                            : (onPlus ?? onSend),
                      ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// PC：输入框外壳，发送按钮落在框内右下角。
class _PcComposerBox extends StatelessWidget {
  const _PcComposerBox({
    required this.height,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.fieldPadV,
    required this.hintText,
    required this.onInputFocused,
    required this.onSend,
    required this.onAttemptPasteImage,
    required this.showStop,
    required this.sending,
    required this.interactionLocked,
    required this.onStop,
  });

  final double height;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final double fieldPadV;
  final String? hintText;
  final VoidCallback? onInputFocused;
  final VoidCallback? onSend;
  final Future<bool> Function()? onAttemptPasteImage;
  final bool showStop;
  final bool sending;
  final bool interactionLocked;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFEFF),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE3DCEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ChatTextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                minLines: 1,
                maxLines: null,
                fillParent: true,
                showOutline: false,
                wide: true,
                fieldPadV: fieldPadV,
                hintText: hintText,
                onInputFocused: onInputFocused,
                onSend: onSend,
                onAttemptPasteImage: onAttemptPasteImage,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: showStop
                        ? onStop
                        : (interactionLocked ? null : onSend),
                    child: Ink(
                      width: 56,
                      height: 32,
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
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '发送',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PC：输入框上沿拖拽条，向上拖升高输入区并托起消息列表。
class _ComposerResizeHandle extends StatelessWidget {
  const _ComposerResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: SizedBox(
          height: 14,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFC9C2D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PC 桌面端圆形图标按钮（语音等）。
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

/// 手机端有输入内容时替换「+」的发送按钮（对齐微信；不依赖 IME 右下角）。
class _WeChatSendBtn extends StatelessWidget {
  const _WeChatSendBtn({
    required this.sending,
    required this.locked,
    required this.onTap,
  });

  final bool sending;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = locked ? const Color(0xFFC9BEDD) : const Color(0xFF7E64BD);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Ink(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
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
                      height: 1,
                    ),
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
    this.fixedHeight,
    this.fillParent = false,
    this.showOutline = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final int minLines;
  final int? maxLines;
  final double? fixedHeight;
  final bool fillParent;
  final bool showOutline;
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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// PC 拖拽改变输入区高度后，EditableText 常残留 scrollOffset，
  /// 导致首行被顶边裁切；在内容已能完整展示时复位到顶部。
  void _clampScrollAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final max = pos.maxScrollExtent;
      final target = max <= 0 ? 0.0 : pos.pixels.clamp(0.0, max);
      if ((pos.pixels - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

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

  /// 输入法组字/选词中：Enter 应交还给 IME，不能直接发送。
  bool _isImeComposing() {
    final composing = widget.controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  /// Shift / Ctrl+Space 等是 Windows 中文输入法的中英切换，必须放行。
  bool _isImeToggleOrModifierKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock) {
      return true;
    }
    // Ctrl+Space：微软拼音等常见中/英切换。Ctrl+V 贴图不走这里。
    return key == LogicalKeyboardKey.space &&
        HardwareKeyboard.instance.isControlPressed;
  }

  /// 旧版复制图片/文件会写入占位文案，粘贴时不再插入。
  bool _isAttachmentPlaceholderText(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t == '[图片]' ||
        t == '图片' ||
        t == '发送了一张图片' ||
        t == '[文件]' ||
        t == '文件' ||
        t.startsWith('[文件]') ||
        t.startsWith('[附件]');
  }

  Future<void> _insertClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (_isAttachmentPlaceholderText(text)) return;
    if (!mounted) return;
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _handlePasteAttempt() async {
    if (_handlingPaste) return;
    _handlingPaste = true;
    try {
      if (widget.onAttemptPasteImage != null) {
        final handled = await widget.onAttemptPasteImage!();
        if (handled || !mounted) return;
      }
      await _insertClipboardText();
    } finally {
      _handlingPaste = false;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 组字中、中英切换键一律交给 IME；只拦「已上屏后的 Enter 发送 / Ctrl+V 贴图」。
    if (_isImeComposing() || _isImeToggleOrModifierKey(event)) {
      return KeyEventResult.ignored;
    }
    if (_isSendKey(event)) {
      widget.onSend?.call();
      return KeyEventResult.handled;
    }
    if (!_isPasteKey(event) || widget.onAttemptPasteImage == null) {
      return KeyEventResult.ignored;
    }
    unawaited(_handlePasteAttempt());
    return KeyEventResult.handled;
  }

  List<ContextMenuButtonItem> _pasteAwareButtonItems(
    EditableTextState editableTextState,
  ) {
    final items = editableTextState.contextMenuButtonItems;
    if (widget.onAttemptPasteImage == null) return items;
    return items
        .map((item) {
          if (item.type != ContextMenuButtonType.paste) return item;
          return ContextMenuButtonItem(
            label: item.label,
            type: ContextMenuButtonType.paste,
            onPressed: () {
              editableTextState.hideToolbar();
              unawaited(_handlePasteAttempt());
            },
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.fixedHeight;
    final useFixedHeight = fixed != null && fixed > 0;
    final expands = useFixedHeight || widget.fillParent;
    final outline = widget.showOutline;
    final field = TextField(
      key: const ValueKey<String>('dunes-chat-composer-field'),
      controller: widget.controller,
      focusNode: widget.focusNode,
      scrollController: expands ? _scrollController : null,
      enabled: widget.enabled,
      minLines: expands ? null : widget.minLines,
      maxLines: expands ? null : widget.maxLines,
      expands: expands,
      textAlignVertical: expands
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      enableInteractiveSelection: true,
      // PC：newline + Enter 发送；APP：尽量要 IME「发送」（多行时荣耀等常仍显示换行，
      // 此时靠输入栏「发送」按钮；上下文菜单仍可插入换行）。
      textInputAction: widget.wide
          ? TextInputAction.newline
          : TextInputAction.send,
      onSubmitted: widget.wide || widget.onSend == null
          ? null
          : (_) {
              widget.onSend!();
              // TextInputAction.send 会在 onSubmitted 之后主动 unfocus；
              // 发送后立刻抢回焦点，保持键盘不收起（对齐微信连发）。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                widget.focusNode?.requestFocus();
              });
            },
      onTap: widget.onInputFocused,
      contextMenuBuilder: (context, editableTextState) {
        final buttonItems = _pasteAwareButtonItems(editableTextState);
        if (widget.wide) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: buttonItems,
          );
        }
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
            ...buttonItems,
          ],
        );
      },
      style: DunesTypography.sans(
        fontSize: widget.wide ? 15 : 16,
        height: widget.wide ? 1.55 : 1.35,
        fontWeight: widget.wide ? FontWeight.w500 : null,
        color: widget.wide ? const Color(0xFF111111) : DunesColors.text,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText ?? '输入消息…',
        hintStyle: DunesTypography.sans(
          fontSize: widget.wide ? 15 : 16,
          color: widget.wide ? const Color(0xFF6F6E66) : const Color(0xFFB0B0B0),
        ),
        filled: outline,
        fillColor: outline
            ? (widget.wide ? const Color(0xFFFFFEFF) : Colors.white)
            : null,
        border: outline
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.wide ? 7 : 8),
                borderSide: widget.wide
                    ? const BorderSide(color: Color(0xFFE3DCEE))
                    : BorderSide.none,
              )
            : InputBorder.none,
        enabledBorder: outline
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.wide ? 7 : 8),
                borderSide: widget.wide
                    ? const BorderSide(color: Color(0xFFE3DCEE))
                    : BorderSide.none,
              )
            : InputBorder.none,
        focusedBorder: outline
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.wide ? 7 : 8),
                borderSide: widget.wide
                    ? const BorderSide(color: Color(0xFF9A82C5))
                    : BorderSide.none,
              )
            : InputBorder.none,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: widget.fieldPadV,
        ),
        isDense: !widget.wide,
      ),
    );

    final wrapped = expands
        ? NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _clampScrollAfterLayout();
              return false;
            },
            child: SizeChangedLayoutNotifier(child: field),
          )
        : field;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKeyEvent,
      child: useFixedHeight
          ? SizedBox(height: fixed, child: wrapped)
          : wrapped,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            avatar ?? const SizedBox(width: 45),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              onLongPressStart: onLongPressStart,
              onSecondaryTapDown: onSecondaryTapDown,
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
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            trailingAvatar ?? avatar ?? const SizedBox(width: 45),
          ],
        ],
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
    this.onSelectionFavorite,
    this.onSelectionMulti,
    this.onSelectionRecall,
    this.onActionsMenu,
    this.enableSelection = true,
    this.selectAllOnLongPress = false,
  });

  final String text;
  final bool mine;
  final ChatMessageQuote? quote;
  final VoidCallback? onQuoteTap;
  final ValueChanged<String>? onSelectionQuote;
  final ValueChanged<String>? onSelectionForward;
  final VoidCallback? onSelectionFavorite;
  final ValueChanged<String>? onSelectionMulti;
  final VoidCallback? onSelectionRecall;

  /// 与文件消息一致的操作菜单（深色图标宫格）。
  /// 提供后将不再弹出系统文字选区工具条。
  final void Function(Offset anchor, String selectedText)? onActionsMenu;
  final bool enableSelection;
  final bool selectAllOnLongPress;

  String _selectedText(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    final start = selection.start;
    final end = selection.end;
    if (start < 0 || end <= start || end > value.text.length) return '';
    return value.text.substring(start, end).trim();
  }

  /// 桌面右键常会变成「光标处单词选区」，不等于用户拖选的片段。
  /// 含空白/换行，或已覆盖整段，才视为明确选区。
  bool _isExplicitTextSelection(String fullText, TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed) return false;
    if (selection.start == 0 && selection.end == fullText.length) {
      return false;
    }
    final selected = fullText.substring(selection.start, selection.end);
    return RegExp(r'\s').hasMatch(selected);
  }

  TextSpan _buildMentionTextSpan() {
    // 对方气泡正文加深一档并略加重，PC/APP 一致，避免发灰难读。
    final baseStyle = DunesTypography.sans(
      fontSize: 13,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: mine ? Colors.white : const Color(0xFF111111),
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
                unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
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
                // APP 端长按消息时直接选中整条文本，和微信的消息操作习惯一致。
                final selection = editableTextState.textEditingValue.selection;
                final needsSelectAll =
                    !selection.isValid ||
                    selection.start != 0 ||
                    selection.end != text.length;
                if (selectAllOnLongPress && needsSelectAll && text.isNotEmpty) {
                  editableTextState.selectAll(SelectionChangedCause.longPress);
                }
                var selected = _selectedText(
                  editableTextState.textEditingValue,
                );
                // 桌面（尤其 macOS）右键会先选中光标下单词；转发/引用若沿用该选区
                // 只会带走一词。无明确拖选时按整条消息处理。
                if (!selectAllOnLongPress &&
                    selected.isNotEmpty &&
                    !_isExplicitTextSelection(text, selection)) {
                  selected = '';
                }
                // 与文件消息共用深色宫格菜单：拦截系统选区工具条。
                // selected 为空时由上层按整条消息处理，避免把「未选中」误当成「全选」。
                if (onActionsMenu != null) {
                  final anchor =
                      editableTextState.contextMenuAnchors.primaryAnchor;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    editableTextState.hideToolbar();
                    onActionsMenu!(anchor, selected);
                  });
                  return const SizedBox.shrink();
                }
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: <ContextMenuButtonItem>[
                    ContextMenuButtonItem(
                      label: '复制',
                      onPressed: () async {
                        // Windows 右键弹出菜单时框架可能会清掉当前选区。
                        // 这时仍应复制整条消息，不能静默写入空字符串。
                        final value = selected.isNotEmpty
                            ? selected
                            : text.trim();
                        if (value.isNotEmpty) {
                          await Clipboard.setData(ClipboardData(text: value));
                        }
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '引用',
                      onPressed: () {
                        onSelectionQuote?.call(
                          selected.isNotEmpty ? selected : text.trim(),
                        );
                        editableTextState.hideToolbar();
                      },
                    ),
                    ContextMenuButtonItem(
                      label: '转发',
                      onPressed: () {
                        onSelectionForward?.call(
                          selected.isNotEmpty ? selected : text.trim(),
                        );
                        editableTextState.hideToolbar();
                      },
                    ),
                    if (onSelectionFavorite != null)
                      ContextMenuButtonItem(
                        label: '收藏',
                        onPressed: () {
                          onSelectionFavorite!();
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

/// 会话置顶条：默认展示最新一条，可向下展开多条；点击定位原消息。
class ChatPinnedMessagesBar extends StatelessWidget {
  const ChatPinnedMessagesBar({
    super.key,
    required this.items,
    required this.expanded,
    required this.onToggleExpand,
    required this.onTapItem,
    this.onUnpinItem,
  });

  final List<NativePinnedMessage> items;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<NativePinnedMessage> onTapItem;
  final ValueChanged<NativePinnedMessage>? onUnpinItem;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final latest = items.first;
    final canExpand = items.length > 1;
    return Material(
      color: DunesColors.bgApp,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: expanded && canExpand
                  ? onToggleExpand
                  : () => onTapItem(latest),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: Color(0xFFE6A23C),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: expanded && canExpand
                          ? Text(
                              '置顶消息 · ${items.length}',
                              style: DunesTypography.sans(
                                fontSize: 13,
                                color: DunesColors.text2,
                              ),
                            )
                          : _PinnedMessageText(item: latest),
                    ),
                    if (canExpand)
                      IconButton(
                        tooltip: expanded ? '收起' : '展开全部置顶',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: onToggleExpand,
                        icon: Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: DunesColors.text3,
                        ),
                      )
                    else if (onUnpinItem != null)
                      IconButton(
                        tooltip: '取消置顶',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () => onUnpinItem!(latest),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (expanded && canExpand)
              ...items.indexed.map((entry) {
                final index = entry.$1;
                final item = entry.$2;
                return InkWell(
                  onTap: () => onTapItem(item),
                  child: Container(
                    decoration: index == 0
                        ? const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: DunesColors.borderSoft),
                            ),
                          )
                        : null,
                    padding: const EdgeInsets.fromLTRB(38, 12, 8, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _PinnedMessageText(item: item)),
                        if (onUnpinItem != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: '取消置顶',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 30,
                            ),
                            onPressed: () => onUnpinItem!(item),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _PinnedMessageText extends StatelessWidget {
  const _PinnedMessageText({required this.item});

  final NativePinnedMessage item;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.pinnedActionLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DunesTypography.sans(
            fontSize: 12,
            color: DunesColors.text3,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.contentLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DunesTypography.sans(
            fontSize: 13,
            color: DunesColors.text2,
            height: 1.4,
          ),
        ),
      ],
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
    this.asrKey,
    this.onPlayError,
  });

  final String playKey;
  final int durationSec;
  final bool mine;
  final Future<String> Function() resolveUrl;

  /// 本地转写缓存 key；有值时在气泡下方展示转写结果。
  final String? asrKey;
  final ValueChanged<String>? onPlayError;

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  @override
  void initState() {
    super.initState();
    ChatVoicePlayer.instance.addListener(_onPlayerChanged);
    VoiceAsrStore.instance.addListener(_onAsrChanged);
    unawaited(VoiceAsrStore.instance.ensureLoaded());
  }

  @override
  void dispose() {
    ChatVoicePlayer.instance.removeListener(_onPlayerChanged);
    VoiceAsrStore.instance.removeListener(_onAsrChanged);
    super.dispose();
  }

  void _onPlayerChanged() => setState(() {});

  void _onAsrChanged() => setState(() {});

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
    final asrKey = (widget.asrKey ?? '').trim();
    final transcript = asrKey.isEmpty
        ? null
        : VoiceAsrStore.instance.textFor(asrKey);
    final transcribing =
        asrKey.isNotEmpty && VoiceAsrStore.instance.isLoading(asrKey);

    return Column(
      crossAxisAlignment: widget.mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_toggle()),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              constraints: BoxConstraints(
                minWidth: 80 + (widget.durationSec * 4).clamp(0, 80).toDouble(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: widget.mine
                    ? const Color(0xFF7E64BD)
                    : DunesColors.bgApp,
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
          ),
        ),
        if (transcribing) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
              const SizedBox(width: 6),
              Text(
                '转写中…',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ],
        if (transcript != null && transcript.isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: DunesColors.bgApp,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DunesColors.borderSoft),
              ),
              child: Text(
                transcript,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ],
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
    this.fileSizeBytes,
    this.downloaded = false,
    this.uploadProgress,
    this.downloadProgress,
    this.onCancelUpload,
    this.onCancelDownload,
  });

  final String fileName;
  final bool mine;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// 文件字节数；空闲时在文件名下方展示格式化大小。
  final int? fileSizeBytes;

  /// 本地已缓存时在气泡右侧显示勾。
  final bool downloaded;

  /// 0~1；非空时在图标上展示圆形上传进度。
  final double? uploadProgress;

  /// 0~1；非空时在图标上展示圆形下载进度（与上传互斥优先上传）。
  final double? downloadProgress;

  /// 上传中点击取消。
  final VoidCallback? onCancelUpload;

  /// 下载中点击取消。
  final VoidCallback? onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final upload = uploadProgress;
    final download = downloadProgress;
    final busyProgress = upload ?? download;
    final uploading = upload != null;
    final downloading = !uploading && download != null;
    final busy = busyProgress != null;
    String? statusLabel;
    if (uploading) {
      final p = upload;
      statusLabel = p > 0 ? '上传中 ${(p * 100).round()}%' : '上传中…';
    } else if (downloading) {
      final p = download;
      statusLabel = p > 0 ? '下载中 ${(p * 100).round()}%' : '下载中…';
    }
    final sizeLabel = _formatFileSize(fileSizeBytes);
    return GestureDetector(
      onTap: busy ? null : onTap,
      onSecondaryTapDown: busy ? null : onSecondaryTapDown,
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
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ChatFileTypeIcon(fileName: fileName, size: 40),
                  if (busy)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: busyProgress > 0 && busyProgress < 1
                            ? busyProgress
                            : null,
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
                  if (statusLabel != null || sizeLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      statusLabel ?? sizeLabel!,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (uploading && onCancelUpload != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: '取消上传',
                onPressed: onCancelUpload,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: DunesColors.text3,
                ),
              ),
            ] else if (downloading && onCancelDownload != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: '取消下载',
                onPressed: onCancelDownload,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: DunesColors.text3,
                ),
              ),
            ] else if (downloaded && !busy) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle,
                size: 18,
                color: Color(0xFF07C160),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 知识库文档转发卡片（会话内展示）。
class ChatKbDocCard extends StatelessWidget {
  const ChatKbDocCard({
    super.key,
    required this.title,
    required this.typeLabel,
    required this.onTap,
    this.sizeLabel = '',
    this.onSecondaryTapDown,
  });

  final String title;
  final String typeLabel;
  final String sizeLabel;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (typeLabel.trim().isNotEmpty) typeLabel.trim().toUpperCase(),
      '知识库',
      if (sizeLabel.trim().isNotEmpty) sizeLabel.trim(),
    ].join(' · ');
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: DunesColors.brandPurpleLine.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DunesColors.brandPurpleSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: DunesColors.brandPurple,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            const Divider(height: 1, color: DunesColors.borderSoft),
            const SizedBox(height: 7),
            Row(
              children: [
                Text(
                  '沙丘知识库',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.brandPurpleDeep,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '打开 · 可存知识库',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: DunesColors.text3,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 会议纪要转发卡片（会话内展示）。
class ChatMeetingMinutesCard extends StatelessWidget {
  const ChatMeetingMinutesCard({
    super.key,
    required this.title,
    required this.onTap,
    this.onSecondaryTapDown,
  });

  final String title;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: DunesColors.accentLine.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DunesColors.accentSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.article_outlined,
                    size: 18,
                    color: DunesColors.accentDeep,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '会议纪要 · 摘要',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            const Divider(height: 1, color: DunesColors.borderSoft),
            const SizedBox(height: 7),
            Row(
              children: [
                Text(
                  '沙丘会议',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.accentDeep,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '查看 · 可存知识库',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: DunesColors.text3,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 审批转发卡片（会话内展示）。
class ChatApprovalCard extends StatelessWidget {
  const ChatApprovalCard({
    super.key,
    required this.title,
    required this.onTap,
    this.statusLabel = '',
    this.subtitle = '审批单据',
    this.onSecondaryTapDown,
  });

  final String title;
  final String statusLabel;
  final String subtitle;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: DunesColors.accentLine.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DunesColors.accentSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    size: 18,
                    color: DunesColors.accentDeep,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          subtitle,
                          if (statusLabel.trim().isNotEmpty) statusLabel.trim(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            const Divider(height: 1, color: DunesColors.borderSoft),
            const SizedBox(height: 7),
            Row(
              children: [
                Text(
                  '沙丘审批',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.accentDeep,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '查看详情',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: DunesColors.text3,
                ),
              ],
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
        bottom: false,
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
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (unread) ...[
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: DunesColors.coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        read
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: read ? DunesColors.accent : DunesColors.text3,
                      ),
                    ),
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
      ),
    );
    // 有已读勾选时由勾选区触发 onTap；否则整卡可点（仍可选中正文）。
    if (onTap == null || showReadMark) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}
