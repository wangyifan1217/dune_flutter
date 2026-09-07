import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'native_nova_service.dart';
import 'nova_icon.dart';
import 'nova_markdown.dart';
import 'nova_markdown_preview.dart';
import 'nova_media.dart';
import 'nova_file_utils.dart';
import 'nova_models_service.dart';

const kNovaName = '韬管理';
const kNovaIdentityReply = '我是韬';
const kNovaIntro = '你好，我是你的NOVA助手。可以帮你查审批、找合同、对账单、读文档；直接问我即可。';
const kNovaInputPlaceholder = '问NOVA';
const kNovaInputBusyHint = 'NOVA正在生成中，请稍候…';

String novaModelDisplayName(String id) => id.trim().toUpperCase();

class NovaAiBadge extends StatelessWidget {
  const NovaAiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD580), Color(0xFFFFA850)],
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'AI',
        style: DunesTypography.mono(
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF5D3508),
        ),
      ),
    );
  }
}

class NovaAiAvatar extends StatelessWidget {
  const NovaAiAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return NovaIconImage(size: size, borderRadius: 9);
  }
}

class NovaPageHeader extends StatelessWidget {
  const NovaPageHeader({
    super.key,
    required this.onBack,
    this.onNewChat,
    this.onHistory,
    this.onOpenKb,
    this.onVoiceCall,
    this.actionsEnabled = true,
    this.voiceCallBlocked = false,
  });

  final VoidCallback onBack;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenKb;
  final VoidCallback? onVoiceCall;
  final bool actionsEnabled;
  final bool voiceCallBlocked;

  @override
  Widget build(BuildContext context) {
    final actionOpacity = actionsEnabled ? 1.0 : 0.38;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: '返回消息',
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                kNovaName,
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F1F1F),
                ),
              ),
            ),
          ),
          if (onVoiceCall != null)
            IconButton(
              tooltip: voiceCallBlocked ? '会议录音进行中，暂无法使用 τ 电话' : 'τ 电话',
              onPressed: actionsEnabled ? onVoiceCall : null,
              icon: Opacity(
                opacity: voiceCallBlocked ? 0.38 : 1,
                child: const Icon(Icons.phone_in_talk_rounded, size: 22),
              ),
            ),
          Opacity(
            opacity: actionOpacity,
            child: PopupMenuButton<_NovaHeaderAction>(
              enabled: actionsEnabled,
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz_rounded, size: 26),
              onSelected: (action) {
                switch (action) {
                  case _NovaHeaderAction.newChat:
                    onNewChat?.call();
                    break;
                  case _NovaHeaderAction.history:
                    onHistory?.call();
                    break;
                  case _NovaHeaderAction.knowledgeBase:
                    onOpenKb?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (onNewChat != null)
                  const PopupMenuItem(
                    value: _NovaHeaderAction.newChat,
                    child: _NovaHeaderMenuItem(
                      icon: Icons.add_comment_outlined,
                      label: '新对话',
                    ),
                  ),
                if (onHistory != null)
                  const PopupMenuItem(
                    value: _NovaHeaderAction.history,
                    child: _NovaHeaderMenuItem(
                      icon: Icons.history_rounded,
                      label: '对话历史',
                    ),
                  ),
                if (onOpenKb != null)
                  const PopupMenuItem(
                    value: _NovaHeaderAction.knowledgeBase,
                    child: _NovaHeaderMenuItem(
                      icon: Icons.menu_book_outlined,
                      label: '知识库',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _NovaHeaderAction { newChat, history, knowledgeBase }

class _NovaHeaderMenuItem extends StatelessWidget {
  const _NovaHeaderMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF333333)),
        const SizedBox(width: 10),
        Text(label, style: DunesTypography.sans(fontSize: 14)),
      ],
    );
  }
}

class NovaC4ModelPicker extends StatelessWidget {
  const NovaC4ModelPicker({
    super.key,
    required this.models,
    required this.selected,
    required this.onTap,
    this.modelCatalog = const <NovaModelCatalogEntry>[],
    this.enabled = true,
  });

  final List<String> models;
  final String selected;
  final VoidCallback? onTap;
  final List<NovaModelCatalogEntry> modelCatalog;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) return const SizedBox.shrink();
    // 生成中禁止切换模型。
    final multi = models.length > 1 && enabled;
    final label = novaModelDisplayName(
      selected.isNotEmpty ? selected : models.first,
    );
    final dimmed = !enabled && models.length > 1;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        alignment: Alignment.centerLeft,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(52, 2, 16, 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: multi ? onTap : null,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1FB),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDFD4F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      size: 15,
                      color: Color(0xFF7E64BD),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF553B96),
                      ),
                    ),
                    if (multi)
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Color(0xFF7E64BD),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showNovaModelSheet(
  BuildContext context, {
  required List<String> models,
  required String selected,
  required ValueChanged<String> onPick,
  List<NovaModelCatalogEntry> modelCatalog = const <NovaModelCatalogEntry>[],
  String title = '选择对话模型',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.borderSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text2,
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.52,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  itemCount: models.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final id = models[i];
                    final active = id == selected;
                    final intro = novaModelDisplayIntro(id, modelCatalog);
                    return Material(
                      color: active
                          ? const Color(0x14553B96)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          onPick(id);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: active
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0x2E553B96),
                                  ),
                                )
                              : null,
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: active
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF553B96),
                                            Color(0xFF7B5CB8),
                                          ],
                                        )
                                      : null,
                                  color: active ? null : DunesColors.bgApp,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.memory,
                                  size: 18,
                                  color: active
                                      ? Colors.white
                                      : DunesColors.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      novaModelDisplayName(id),
                                      style: DunesTypography.mono(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: DunesColors.text,
                                      ),
                                    ),
                                    if (intro.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        intro,
                                        style: DunesTypography.sans(
                                          fontSize: 11,
                                          color: DunesColors.text3,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (active)
                                Container(
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF553B96),
                                        Color(0xFF7B5CB8),
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 仅去掉底部说明文字，保留原有的占位空间，避免列表贴边。
              const SizedBox(height: 35),
            ],
          ),
        ),
      );
    },
  );
}

class NovaStatusBanner extends StatelessWidget {
  const NovaStatusBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.warning = true,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final bg = warning ? DunesColors.coralSoft : DunesColors.accentSoft;
    final fg = warning ? DunesColors.coral : DunesColors.accentDeep;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.info_outline : Icons.check_circle_outline,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: DunesTypography.sans(
                fontSize: 12,
                color: fg,
                height: 1.35,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('重试', style: TextStyle(fontSize: 12, color: fg)),
            ),
          ],
        ],
      ),
    );
  }
}

class NovaC4BusyHint extends StatelessWidget {
  const NovaC4BusyHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    // 「正在分析」类状态不再展示，避免输入栏上方多余灰字。
    if (t.isEmpty || t.contains('正在分析')) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: DunesTypography.sans(
          fontSize: 12,
          color: DunesColors.text3,
          height: 1.4,
        ),
      ),
    );
  }
}

class NovaC4ThinkPanel extends StatefulWidget {
  const NovaC4ThinkPanel({
    super.key,
    required this.status,
    required this.body,
    this.initialCollapsed = false,
    this.streaming = false,
  });

  final String status;
  final String body;
  final bool initialCollapsed;
  final bool streaming;

  @override
  State<NovaC4ThinkPanel> createState() => _NovaC4ThinkPanelState();
}

class _NovaC4ThinkPanelState extends State<NovaC4ThinkPanel> {
  late bool _collapsed =
      widget.initialCollapsed || widget.status.contains('已完成');

  @override
  void didUpdateWidget(NovaC4ThinkPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streaming &&
        !widget.streaming &&
        widget.body.trim().isNotEmpty) {
      _collapsed = true;
    }
    if (widget.status.contains('已完成') && !oldWidget.status.contains('已完成')) {
      _collapsed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.body.trim().isEmpty && widget.status.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: DunesColors.accentDeep,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '深度思考',
                          style: DunesTypography.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                          ),
                        ),
                        if (widget.status.isNotEmpty)
                          Text(
                            widget.status,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              color: DunesColors.text3,
                              height: 1.4,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: _collapsed ? -1.5708 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed && widget.body.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: DunesColors.borderSoft)),
              ),
              child: Text(
                widget.body,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                  height: 1.55,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NovaC4AiBubble extends StatelessWidget {
  const NovaC4AiBubble({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DefaultTextStyle(
        style: DunesTypography.sans(
          fontSize: 13,
          color: DunesColors.text,
          height: 1.5,
        ),
        child: child,
      ),
    );
  }
}

class NovaC4SentBubble extends StatelessWidget {
  const NovaC4SentBubble({
    super.key,
    this.text = '',
    this.child,
    this.highlighted = false,
    this.compactMedia = false,
  });

  final String text;
  final Widget? child;
  final bool highlighted;

  /// 图片/语音等媒体消息：对齐 WebView `.msg-bubble.sent` 内嵌缩略图，减小内边距。
  final bool compactMedia;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      padding: compactMedia
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7E64BD), Color(0xFF553B96)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D553B96),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
        border: highlighted
            ? Border.all(color: const Color(0x592F5D62), width: 2)
            : null,
      ),
      child:
          child ??
          Text(
            text,
            style: DunesTypography.sans(
              fontSize: 13,
              color: Colors.white,
              height: 1.5,
            ),
          ),
    );
  }
}

class NovaC4ThinkingDots extends StatefulWidget {
  const NovaC4ThinkingDots({super.key, this.label = '正在分析…'});

  final String label;

  @override
  State<NovaC4ThinkingDots> createState() => _NovaC4ThinkingDotsState();
}

class _NovaC4ThinkingDotsState extends State<NovaC4ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final t = (_controller.value + i * 0.15) % 1.0;
              final opacity = 0.35 + (t < 0.5 ? t : 1 - t) * 1.3;
              return Container(
                width: 5,
                height: 5,
                margin: EdgeInsets.only(right: i < 2 ? 4 : 6),
                decoration: BoxDecoration(
                  color: DunesColors.accent.withValues(
                    alpha: opacity.clamp(0.35, 1.0),
                  ),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
        if (widget.label.trim().isNotEmpty)
          Text(
            widget.label,
            style: DunesTypography.mono(
              fontSize: 10,
              color: DunesColors.text3,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
      ],
    );
  }
}

class NovaC4MessageStream extends StatelessWidget {
  const NovaC4MessageStream({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white),
      child: child,
    );
  }
}

/// NOVA 新会话的轻量引导页；不承载业务操作，避免改变既有会话能力。
class NovaC4EmptyState extends StatefulWidget {
  const NovaC4EmptyState({super.key});

  @override
  State<NovaC4EmptyState> createState() => _NovaC4EmptyStateState();
}

class _NovaC4EmptyStateState extends State<NovaC4EmptyState>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _greetingController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _greetingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _greetingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 54),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final lookOffset = math.sin(t * math.pi * 2) * 5;
                final blinkDistance = (t - 0.72).abs();
                final eyeScaleY = blinkDistance < 0.055
                    ? blinkDistance / 0.055
                    : 1.0;
                final smiling = t > 0.42 && t < 0.62;
                return Transform.translate(
                  offset: Offset(lookOffset, 0),
                  child: SizedBox(
                    width: 42,
                    height: 27,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: smiling
                            ? Text(
                                '^^',
                                key: const ValueKey('smile'),
                                style: DunesTypography.sans(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                  color: const Color(0xFF7E64BD),
                                ),
                              )
                            : Row(
                                key: const ValueKey('eyes'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _NovaAnimatedEye(verticalScale: eyeScaleY),
                                  const SizedBox(width: 7),
                                  _NovaAnimatedEye(verticalScale: eyeScaleY),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _greetingController,
              builder: (context, _) {
                const greeting = '今天想做些什么呢？';
                final length = (greeting.length * _greetingController.value)
                    .ceil()
                    .clamp(0, greeting.length);
                return Text(
                  greeting.substring(0, length),
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF222222),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NovaAnimatedEye extends StatelessWidget {
  const _NovaAnimatedEye({required this.verticalScale});

  final double verticalScale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleY: verticalScale,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Color(0xFF7E64BD),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class NovaMsgDateDivider extends StatelessWidget {
  const NovaMsgDateDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: DunesColors.borderSoft, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Text(
              label.toUpperCase(),
              style: DunesTypography.mono(
                fontSize: 9.5,
                color: DunesColors.text3,
                letterSpacing: 0.06 * 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(
            child: Divider(color: DunesColors.borderSoft, height: 1),
          ),
        ],
      ),
    );
  }
}

class NovaC11Header extends StatelessWidget {
  const NovaC11Header({
    super.key,
    required this.onBack,
    required this.onToggleSearch,
    this.searchOpen = false,
  });

  final VoidCallback onBack;
  final VoidCallback onToggleSearch;
  final bool searchOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
          ),
          Expanded(
            child: Text(
              '${kNovaName}对话历史',
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onToggleSearch,
            icon: Icon(searchOpen ? Icons.close : Icons.search, size: 20),
            tooltip: searchOpen ? '关闭搜索' : '搜索',
          ),
        ],
      ),
    );
  }
}

class NovaC11SearchBar extends StatelessWidget {
  const NovaC11SearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 15, color: DunesColors.text3),
            const SizedBox(width: 7),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜索历史对话',
                  hintStyle: TextStyle(fontSize: 13, color: DunesColors.text3),
                ),
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: DunesColors.text3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NovaHistoryDayLabel extends StatelessWidget {
  const NovaHistoryDayLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return NovaMsgDateDivider(label: label);
  }
}

class NovaHistoryCard extends StatelessWidget {
  const NovaHistoryCard({
    super.key,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.onTap,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
      child: Material(
        color: DunesColors.bgApp,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: DunesColors.borderSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NovaIconImage(size: 32, borderRadius: 9),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              title.isEmpty ? '新对话' : title,
                              style: DunesTypography.sans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: DunesColors.text,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (timeLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              timeLabel,
                              style: DunesTypography.mono(
                                fontSize: 9,
                                color: DunesColors.text3,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          preview,
                          style: DunesTypography.mono(
                            fontSize: 10,
                            color: DunesColors.text3,
                            height: 1.45,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NovaC4MessageRow extends StatelessWidget {
  const NovaC4MessageRow({
    super.key,
    required this.mine,
    required this.text,
    this.messageId = 0,
    this.time = '',
    this.userName = '',
    this.userInitial = '?',
    this.userSeed = 0,
    this.userAvatarPreset = '',
    this.userAvatarObjectKey = '',
    this.userAvatarUrl = '',
    this.avatarService,
    this.thinking = false,
    this.showAiBadge = true,
    this.thinkText = '',
    this.thinkStatus = '',
    this.streaming = false,
    this.attachments = const <NovaMessageAttachment>[],
    this.kind = 'TEXT',
    this.durationSec = 0,
    this.mediaResolver,
    this.highlighted = false,
    this.ragUsed = false,
    this.onResend,
  });

  final bool mine;
  final String text;
  final int messageId;
  final String time;
  final String userName;
  final String userInitial;
  final int userSeed;
  final String userAvatarPreset;
  final String userAvatarObjectKey;
  final String userAvatarUrl;
  final ConversationService? avatarService;
  final bool thinking;
  final bool showAiBadge;
  final String thinkText;
  final String thinkStatus;
  final bool streaming;
  final List<NovaMessageAttachment> attachments;
  final String kind;
  final int durationSec;
  final NovaMediaResolver? mediaResolver;
  final bool highlighted;
  final bool ragUsed;
  final VoidCallback? onResend;

  bool _isImageAttachment(NovaMessageAttachment a) {
    final k = a.kind.toUpperCase();
    if (k == 'IMAGE') return true;
    if (a.mimeType.startsWith('image/')) return true;
    final ext = a.fileName.split('.').last.toLowerCase();
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'gif' ||
        ext == 'webp';
  }

  bool _isImagePlaceholderLabel(String text) {
    final t = text.trim();
    return t == '[图片]' || t.startsWith('[图片]');
  }

  bool _shouldShowUserText(
    String text,
    List<NovaMessageAttachment> attachments,
  ) {
    if (text.trim().isEmpty) return false;
    if (attachments.isEmpty) return true;
    if (_isImagePlaceholderLabel(text)) return false;
    if (text.trim() == '已上传 1 张图片' && attachments.every(_isImageAttachment))
      return false;
    return true;
  }

  Widget? _buildKindMedia(
    BuildContext context,
    NovaMediaResolver? resolver, {
    required bool onDarkBubble,
  }) {
    if (resolver == null) return null;
    final upperKind = kind.toUpperCase();
    if ((upperKind == 'IMAGE' || _isImagePlaceholderLabel(text)) &&
        attachments.isNotEmpty) {
      final a = attachments.first;
      return NovaC4ImageThumb(
        resolver: resolver,
        url: a.url,
        objectKey: a.objectKey,
        fileName: a.fileName,
        previewBytes: a.previewBytes,
      );
    }
    if (upperKind == 'AUDIO') {
      final a = attachments.isNotEmpty ? attachments.first : null;
      return NovaC4VoiceBubble(
        resolver: resolver,
        url: a?.url ?? '',
        objectKey: a?.objectKey ?? '',
        durationSec: durationSec > 0 ? durationSec : 1,
        messageKey: 'nova-$messageId',
      );
    }
    if (upperKind == 'FILE' && attachments.isNotEmpty) {
      final a = attachments.first;
      final name = a.fileName.isNotEmpty ? a.fileName : text;
      return NovaC4FileLink(
        resolver: resolver,
        url: a.url,
        objectKey: a.objectKey,
        fileName: name,
        previewBytes: a.previewBytes,
        onDarkBubble: onDarkBubble,
        onTap: novaIsMarkdownFile(name, mimeType: a.mimeType)
            ? () => openNovaMarkdownPreview(
                context,
                resolver: resolver,
                fileName: name,
                url: a.url,
                objectKey: a.objectKey,
                previewBytes: a.previewBytes,
              )
            : null,
      );
    }
    return null;
  }

  Widget _buildUserBubbleContent(BuildContext context) {
    final resolver = mediaResolver;
    final upperKind = kind.toUpperCase();
    final hasAttachments = attachments.isNotEmpty;

    // WebView sendNovaDraftMessage：TEXT + combined attachments 同气泡。
    // 有本地 previewBytes 时即使 resolver 暂不可用也先展示缩略图。
    if (upperKind == 'TEXT' && hasAttachments) {
      final uniqueAttachments = dedupeNovaMessageAttachments(attachments);
      return NovaC4SentBubble(
        highlighted: highlighted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_shouldShowUserText(text, uniqueAttachments))
              Text(
                text,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ...uniqueAttachments.map(
              (a) => resolver != null
                  ? _combinedAttachment(context, resolver, a)
                  : _localAttachmentFallback(a),
            ),
          ],
        ),
      );
    }

    final kindMedia = _buildKindMedia(context, resolver, onDarkBubble: true);
    if (kindMedia != null) {
      return NovaC4SentBubble(
        highlighted: highlighted,
        compactMedia: true,
        child: kindMedia,
      );
    }
    return NovaC4SentBubble(text: text, highlighted: highlighted);
  }

  Widget _localAttachmentFallback(NovaMessageAttachment a) {
    if (_isImageAttachment(a) &&
        a.previewBytes != null &&
        a.previewBytes!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(a.previewBytes!, width: 170, fit: BoxFit.cover),
        ),
      );
    }
    final name = a.fileName.trim().isNotEmpty ? a.fileName.trim() : '附件';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        name,
        style: DunesTypography.sans(fontSize: 12, color: Colors.white70),
      ),
    );
  }

  Widget _buildAiBubbleContent(BuildContext context) {
    final resolver = mediaResolver;
    final kindMedia = _buildKindMedia(context, resolver, onDarkBubble: false);
    if (kindMedia != null) return kindMedia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (thinking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: NovaC4ThinkingDots(label: ''),
          )
        else ...[
          NovaMarkdownBody(
            text: text,
            streaming: streaming,
            mediaResolver: resolver,
          ),
          if (attachments.isNotEmpty && resolver != null)
            ...attachments.map(
              (a) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _combinedAttachment(
                  context,
                  resolver,
                  a,
                  onDarkBubble: false,
                ),
              ),
            ),
          if (ragUsed && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '已参考您的文档',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _combinedAttachment(
    BuildContext context,
    NovaMediaResolver resolver,
    NovaMessageAttachment a, {
    bool onDarkBubble = true,
  }) {
    if (_isImageAttachment(a)) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: NovaC4ImageThumb(
          resolver: resolver,
          url: a.url,
          objectKey: a.objectKey,
          fileName: a.fileName,
          previewBytes: a.previewBytes,
        ),
      );
    }
    final name = a.fileName.trim().isNotEmpty ? a.fileName.trim() : '附件';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: NovaC4FileLink(
        resolver: resolver,
        url: a.url,
        objectKey: a.objectKey,
        fileName: name,
        previewBytes: a.previewBytes,
        onDarkBubble: onDarkBubble,
        onTap: novaIsMarkdownFile(name, mimeType: a.mimeType)
            ? () => openNovaMarkdownPreview(
                context,
                resolver: resolver,
                fileName: name,
                url: a.url,
                objectKey: a.objectKey,
                previewBytes: a.previewBytes,
              )
            : null,
      ),
    );
  }

  /// 交给系统原生选择菜单处理长按复制/选取：iOS 显示 Cupertino 文本菜单，
  /// Android 和 Web 则使用各自平台的默认选择控件。额外提供“复制全部”，
  /// 不必拖拽选完整条 NOVA 回复。
  Widget _wrapCopyable(BuildContext context, Widget bubble, String copyText) {
    if (copyText.trim().isEmpty) return bubble;
    return SelectionArea(
      contextMenuBuilder: (menuContext, selectableRegionState) {
        final items = <ContextMenuButtonItem>[
          ContextMenuButtonItem(
            label: '复制全部',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyText));
              selectableRegionState.hideToolbar();
              if (menuContext.mounted) {
                showDunesToast(
                  menuContext,
                  '已复制整条回复',
                  duration: const Duration(milliseconds: 1200),
                );
              }
            },
          ),
          ...selectableRegionState.contextMenuButtonItems,
        ];
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: items,
        );
      },
      child: bubble,
    );
  }

  String get _userCopyText =>
      kind.toUpperCase() == 'TEXT' && _shouldShowUserText(text, attachments)
      ? text
      : '';

  String get _aiCopyText =>
      !thinking && kind.toUpperCase() == 'TEXT' ? text : '';

  @override
  Widget build(BuildContext context) {
    if (mine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: _wrapCopyable(
                    context,
                    _buildUserBubbleContent(context),
                    _userCopyText,
                  ),
                ),
              ],
            ),
            if (onResend != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 2),
                child: TextButton(
                  onPressed: onResend,
                  style: TextButton.styleFrom(
                    foregroundColor: DunesColors.text3,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    '重新发送',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Flexible(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: highlighted
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0x592F5D62),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F2F5D62),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ],
                    )
                  : null,
              child: _wrapCopyable(
                context,
                NovaC4AiBubble(child: _buildAiBubbleContent(context)),
                _aiCopyText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NovaC4QuickActions extends StatelessWidget {
  const NovaC4QuickActions({
    super.key,
    required this.onCamera,
    required this.onAlbum,
    required this.onOpenMeeting,
    required this.onMeetingPrd,
    this.enabled = true,
  });

  final VoidCallback onCamera;
  final VoidCallback onAlbum;
  final VoidCallback onOpenMeeting;
  final VoidCallback onMeetingPrd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cells = <_NovaQaCell>[
      _NovaQaCell(
        icon: Icons.photo_camera_outlined,
        label: '拍照',
        onTap: enabled ? onCamera : null,
      ),
      _NovaQaCell(
        icon: Icons.photo_library_outlined,
        label: '图片',
        onTap: enabled ? onAlbum : null,
      ),
      _NovaQaCell(
        icon: Icons.description_outlined,
        label: '会议纪要',
        onTap: enabled ? onOpenMeeting : null,
      ),
      _NovaQaCell(
        icon: Icons.article_outlined,
        label: 'PRD',
        onTap: enabled ? onMeetingPrd : null,
      ),
    ];
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: DunesColors.borderSoft)),
        ),
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
      ),
    );
  }
}

/// NOVA 专用输入栏。布局与 AI 助手的双层输入面板一致，交互仍由页面传入。
class NovaC4InputBar extends StatelessWidget {
  const NovaC4InputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.voiceMode,
    required this.sending,
    required this.enabled,
    required this.hintText,
    required this.modelLabel,
    required this.quickActionsOpen,
    required this.onToggleVoice,
    required this.onSend,
    required this.onPickModel,
    required this.onInputFocused,
    required this.onToggleQuickActions,
    this.onStop,
    this.onAttach,
    this.onCamera,
    this.onAlbum,
    this.onOpenMeeting,
    this.onMeetingPrd,
    this.recording = false,
    this.recordWillCancel = false,
    this.recordDurationMs = 0,
    this.onVoiceHoldStart,
    this.onVoiceHoldMove,
    this.onVoiceHoldEnd,
    this.onVoiceHoldCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool voiceMode;
  final bool sending;
  final bool enabled;
  final String hintText;
  final String modelLabel;
  final bool quickActionsOpen;
  final VoidCallback onToggleVoice;
  final VoidCallback onSend;
  final VoidCallback onPickModel;
  final VoidCallback onInputFocused;
  final VoidCallback onToggleQuickActions;
  final VoidCallback? onStop;
  final VoidCallback? onAttach;
  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;
  final VoidCallback? onOpenMeeting;
  final VoidCallback? onMeetingPrd;
  final bool recording;
  final bool recordWillCancel;
  final int recordDurationMs;
  final GestureLongPressStartCallback? onVoiceHoldStart;
  final GestureLongPressMoveUpdateCallback? onVoiceHoldMove;
  final GestureLongPressEndCallback? onVoiceHoldEnd;
  final VoidCallback? onVoiceHoldCancel;

  @override
  Widget build(BuildContext context) {
    final showStop = sending && onStop != null;
    final locked = !enabled || (sending && !showStop);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        6,
        16,
        bottomInset > 0 ? bottomInset + 8 : 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 18,
                  offset: Offset(0, 4),
                ),
              ],
              border: Border.all(color: const Color(0xFFF0F0F0)),
            ),
            child: voiceMode
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NovaVoiceHoldField(
                        locked: locked,
                        recording: recording,
                        recordWillCancel: recordWillCancel,
                        recordDurationMs: recordDurationMs,
                        onLongPressStart: onVoiceHoldStart,
                        onLongPressMoveUpdate: onVoiceHoldMove,
                        onLongPressEnd: onVoiceHoldEnd,
                        onLongPressCancel: onVoiceHoldCancel,
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _NovaInputIcon(
                          icon: Icons.keyboard_outlined,
                          onTap: onToggleVoice,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: enabled && !showStop,
                        minLines: 1,
                        maxLines: 4,
                        onTap: onInputFocused,
                        onSubmitted: locked ? null : (_) => onSend(),
                        style: DunesTypography.sans(
                          fontSize: 14,
                          color: const Color(0xFF262626),
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: hintText,
                          hintStyle: DunesTypography.sans(
                            fontSize: 14,
                            color: const Color(0xFFB6B6B6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 1,
                            vertical: 5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _NovaModelChip(
                            label: modelLabel,
                            onTap: locked ? null : onPickModel,
                          ),
                          const Spacer(),
                          if (_hasQuickActions)
                            _NovaInputIcon(
                              icon: quickActionsOpen
                                  ? Icons.close_rounded
                                  : Icons.add_rounded,
                              onTap: locked ? null : onToggleQuickActions,
                            ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              final hasText = value.text.trim().isNotEmpty;
                              return _NovaInputIcon(
                                icon: showStop
                                    ? Icons.stop_rounded
                                    : hasText
                                    ? Icons.arrow_upward_rounded
                                    : Icons.multitrack_audio_rounded,
                                onTap: showStop
                                    ? onStop
                                    : (locked
                                          ? null
                                          : (hasText ? onSend : onToggleVoice)),
                                filled: showStop || hasText,
                                accentBlue: hasText && !showStop,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          if (quickActionsOpen && !voiceMode)
            _NovaExpandedActions(
              onAttach: onAttach,
              onCamera: onCamera,
              onAlbum: onAlbum,
              onOpenMeeting: onOpenMeeting,
              onMeetingPrd: onMeetingPrd,
            ),
        ],
      ),
    );
  }

  bool get _hasQuickActions =>
      onAttach != null ||
      onCamera != null ||
      onAlbum != null ||
      onOpenMeeting != null ||
      onMeetingPrd != null;
}

class _NovaExpandedActions extends StatelessWidget {
  const _NovaExpandedActions({
    this.onAttach,
    this.onCamera,
    this.onAlbum,
    this.onOpenMeeting,
    this.onMeetingPrd,
  });

  final VoidCallback? onAttach;
  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;
  final VoidCallback? onOpenMeeting;
  final VoidCallback? onMeetingPrd;

  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, VoidCallback? onTap})>[
      (icon: Icons.photo_camera_outlined, label: '拍照', onTap: onCamera),
      (icon: Icons.photo_library_outlined, label: '图片', onTap: onAlbum),
      (icon: Icons.description_outlined, label: '会议纪要', onTap: onOpenMeeting),
      (icon: Icons.article_outlined, label: 'PRD', onTap: onMeetingPrd),
      (icon: Icons.attach_file_rounded, label: '文件', onTap: onAttach),
    ].where((action) => action.onTap != null).toList(growable: false);

    // APP 端一行三个小名片；多出的自动换行。
    const columns = 3;
    const gap = 6.0;
    const tileHeight = 58.0;
    final rows = (actions.length / columns).ceil().clamp(1, 8);
    final gridHeight = rows * tileHeight + (rows - 1) * gap;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: gridHeight,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return Material(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: action.onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, size: 18, color: const Color(0xFF3B3B3B)),
                    const SizedBox(height: 4),
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 10,
                        color: const Color(0xFF444444),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NovaModelChip extends StatelessWidget {
  const _NovaModelChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1FB),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFDFD4F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 13,
                color: Color(0xFF7E64BD),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 142),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF553B96),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NovaInputIcon extends StatelessWidget {
  const _NovaInputIcon({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.accentBlue = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool accentBlue;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Ink(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: filled
                ? (accentBlue
                      ? const Color(0xFF7E64BD)
                      : const Color(0xFFB65252))
                : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: filled
                  ? (accentBlue
                        ? const Color(0xFF7E64BD)
                        : const Color(0xFFB65252))
                  : const Color(0xFF323232),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: filled ? Colors.white : const Color(0xFF303030),
          ),
        ),
      ),
    );
  }
}

class _NovaVoiceHoldField extends StatelessWidget {
  const _NovaVoiceHoldField({
    required this.locked,
    required this.recording,
    required this.recordWillCancel,
    required this.recordDurationMs,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final bool locked;
  final bool recording;
  final bool recordWillCancel;
  final int recordDurationMs;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: locked ? null : onLongPressStart,
      onLongPressMoveUpdate: locked ? null : onLongPressMoveUpdate,
      onLongPressEnd: locked ? null : onLongPressEnd,
      onLongPressCancel: locked ? null : onLongPressCancel,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: recording
              ? (recordWillCancel ? DunesColors.coral : const Color(0xFF8B72B7))
              : const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          recording
              ? (recordWillCancel
                    ? '松开取消'
                    : '松开发送 ${(recordDurationMs / 1000).toStringAsFixed(1)}s')
              : '按住 说话',
          style: DunesTypography.sans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: recording ? Colors.white : const Color(0xFF444444),
          ),
        ),
      ),
    );
  }
}

class _NovaQaCell {
  const _NovaQaCell({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}
