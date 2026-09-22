import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'native_nova_service.dart';
import 'nova_icon.dart';
import 'nova_markdown.dart';
import 'nova_markdown_preview.dart';
import 'nova_media.dart';
import 'nova_file_utils.dart';
import 'nova_models_service.dart';

const kNovaName = '小饕';
const kNovaIdentityReply = '我是小饕';
const kNovaIntro = '你好，我是你的小饕AI助手。可以帮你检索知识库、读文档、整理会议纪要；直接问我即可。';
const kNovaInputPlaceholder = '问小饕...';
const kNovaInputBusyHint = '小饕正在生成中，请稍候…';

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
    required this.tabController,
    this.onNewChat,
    this.onHistory,
    this.onOpenKb,
    this.onVoiceCall,
    this.onOpenDrawer,
    this.actionsEnabled = true,
    this.voiceCallBlocked = false,
  });

  final VoidCallback onBack;
  final TabController tabController;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenKb;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onOpenDrawer;
  final bool actionsEnabled;
  final bool voiceCallBlocked;

  static const tabLabels = ['服务', '小饕'];

  @override
  Widget build(BuildContext context) {
    final actionOpacity = actionsEnabled ? 1.0 : 0.40;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF0F1F5), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: actionOpacity,
            child: _HeaderCircleButton(
              icon: Icons.notes_rounded,
              iconSize: 20,
              tooltip: '个人与历史记录',
              onTap: actionsEnabled ? onOpenDrawer : null,
            ),
          ),
          Expanded(
            child: Center(child: _NovaSegmentedTabs(controller: tabController)),
          ),
          _HeaderCircleButton(
            icon: Icons.close_rounded,
            iconSize: 20,
            tooltip: '关闭',
            onTap: onBack,
          ),
        ],
      ),
    );
  }
}

class _NovaSegmentedTabs extends StatelessWidget {
  const _NovaSegmentedTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final animation = controller.animation ?? controller;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = (controller.animation?.value ?? controller.index.toDouble())
            .clamp(0.0, 1.0);
        return Container(
          width: 156,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / 2;
              return Stack(
                children: [
                  Positioned(
                    left: t * segmentWidth,
                    top: 0,
                    bottom: 0,
                    width: segmentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < NovaPageHeader.tabLabels.length; i++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (controller.index != i) {
                                controller.animateTo(i);
                              }
                            },
                            child: Center(
                              child: Text(
                                NovaPageHeader.tabLabels[i],
                                style: DunesTypography.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color.lerp(
                                    const Color(0xFF8B919E),
                                    const Color(0xFF6B3FE2),
                                    i == 0 ? (1 - t) : t,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    this.iconSize = 18,
    this.iconOffset = Offset.zero,
    this.tooltip,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final double iconSize;
  final Offset iconOffset;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: Ink(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F9),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE8EAF0), width: 0.8),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled
              ? () {
                  Tooltip.dismissAllToolTips();
                  onTap?.call();
                }
              : null,
          child: Center(
            child: Transform.translate(
              offset: iconOffset,
              child: Icon(icon, size: iconSize, color: const Color(0xFF2C323E)),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
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
    // 检索/分析类状态不再展示，避免输入栏上方留下灰色小字。
    if (t.isEmpty ||
        t.contains('正在分析') ||
        t.contains('正在按所选材料检索') ||
        t.contains('正在检查知识库') ||
        t.contains('正在加载') ||
        t.contains('正在生成') ||
        t.contains('请稍候')) {
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
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.88,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A18274B),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFEDEFF5)),
      ),
      child: DefaultTextStyle(
        style: DunesTypography.sans(
          fontSize: 14.5,
          color: const Color(0xFF1F2329),
          height: 1.55,
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

  /// 图片/语音等媒体消息：减小内边距。
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
          : const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x082E75FF),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: highlighted
            ? Border.all(color: const Color(0xFF2E75FF), width: 1.5)
            : Border.all(color: const Color(0xFFD4E5FF), width: 0.8),
      ),
      child:
          child ??
          Text(
            text,
            style: DunesTypography.sans(
              fontSize: 14.5,
              color: const Color(0xFF1D2129),
              height: 1.45,
            ),
          ),
    );
  }
}

class NovaC4ThinkingDots extends StatefulWidget {
  const NovaC4ThinkingDots({super.key, this.label = '小饕正在思考'});

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
      duration: const Duration(milliseconds: 1100),
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
              final t = (_controller.value + i * 0.18) % 1.0;
              final bounce = (t < 0.5 ? t : 1 - t) * 2;
              final dy = -3.5 * Curves.easeOut.transform(bounce);
              final opacity = 0.35 + bounce * 0.65;
              return Transform.translate(
                offset: Offset(0, dy),
                child: Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.only(right: i < 2 ? 5 : 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B3FE2).withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
        if (widget.label.trim().isNotEmpty)
          Text(
            widget.label,
            style: DunesTypography.sans(
              fontSize: 12.5,
              color: const Color(0xFF86909C),
              fontWeight: FontWeight.w500,
            ),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F8FC), Color(0xFFF3F5FA)],
        ),
      ),
      child: child,
    );
  }
}

/// NOVA 新会话的轻量引导页；不承载业务操作，避免改变既有会话能力。
class NovaC4EmptyState extends StatelessWidget {
  const NovaC4EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 54),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 27,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NovaAnimatedEye(),
                  SizedBox(width: 7),
                  _NovaAnimatedEye(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '今天想做些什么呢？',
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF222222),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NovaAnimatedEye extends StatelessWidget {
  const _NovaAnimatedEye();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        color: Color(0xFF7E64BD),
        shape: BoxShape.circle,
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
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEDEFF5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 11,
              color: const Color(0xFF86909C),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
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
    this.onDelete,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFEDEFF5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x0818274B),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x146B3FE2),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: NovaPersonAvatarImage(width: 36, height: 36),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              title.isEmpty ? '新对话' : title,
                              style: DunesTypography.sans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1D2129),
                                height: 1.35,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (timeLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              timeLabel,
                              style: DunesTypography.sans(
                                fontSize: 11,
                                color: const Color(0xFF86909C),
                              ),
                            ),
                          ],
                          if (onDelete != null) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: Color(0xFFC2C7D0),
                              ),
                              tooltip: '删除对话',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              onPressed: onDelete,
                            ),
                          ],
                        ],
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          preview,
                          style: DunesTypography.sans(
                            fontSize: 12.5,
                            color: const Color(0xFF4E5969),
                            height: 1.45,
                          ),
                          maxLines: 2,
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
        onTap: novaIsPreviewableDocument(name, mimeType: a.mimeType)
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
                  color: const Color(0xFF1D2129),
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
            padding: EdgeInsets.symmetric(vertical: 2),
            child: NovaC4ThinkingDots(),
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
        onTap: novaIsPreviewableDocument(name, mimeType: a.mimeType)
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
              HapticFeedback.selectionClick();
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

  Widget _buildUserAvatar() {
    final initial = userInitial.isNotEmpty
        ? userInitial
        : (userName.isNotEmpty ? userName[0] : '我');
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF0F4FC),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ImUserAvatar(
        initial: initial,
        seed: userSeed,
        size: 38,
        avatarPreset: userAvatarPreset.trim().isEmpty ? null : userAvatarPreset,
        avatarObjectKey:
            userAvatarObjectKey.trim().isEmpty ? null : userAvatarObjectKey,
        avatarUrl: userAvatarUrl.trim().isEmpty ? null : userAvatarUrl,
        avatarService: avatarService,
        fallbackBackground: const Color(0xFFF0F4FC),
        fallbackForeground: const Color(0xFF2E75FF),
      ),
    );
  }

  Widget _buildAiAvatar() {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x186B3FE2),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: NovaPersonAvatarImage(width: 38, height: 38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = mine ? _buildMineColumn(context) : _buildAiRow(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey('nova-anim-$messageId-$mine'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: _NovaTappableTime(
        time: time,
        alignEnd: mine,
        child: body,
      ),
    );
  }

  Widget _buildMineColumn(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _wrapCopyable(
                  context,
                  _buildUserBubbleContent(context),
                  _userCopyText,
                ),
              ),
              _buildUserAvatar(),
            ],
          ),
          if (onResend != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 46),
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

  Widget _buildAiRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAiAvatar(),
          Flexible(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: highlighted
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF6B3FE2),
                        width: 1.8,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F6B3FE2),
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

class _NovaTappableTime extends StatefulWidget {
  const _NovaTappableTime({
    required this.time,
    required this.alignEnd,
    required this.child,
  });

  final String time;
  final bool alignEnd;
  final Widget child;

  @override
  State<_NovaTappableTime> createState() => _NovaTappableTimeState();
}

class _NovaTappableTimeState extends State<_NovaTappableTime> {
  bool _pinned = false;
  bool _hovering = false;

  bool get _showTime =>
      widget.time.isNotEmpty && (_pinned || _hovering);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.time.isEmpty
          ? null
          : (_) => setState(() => _hovering = true),
      onExit: widget.time.isEmpty
          ? null
          : (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.time.isEmpty
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _pinned = !_pinned);
              },
        behavior: HitTestBehavior.deferToChild,
        child: Column(
          crossAxisAlignment: widget.alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            widget.child,
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: _showTime
                  ? Padding(
                      padding: EdgeInsets.only(
                        top: 4,
                        left: widget.alignEnd ? 0 : 46,
                        right: widget.alignEnd ? 46 : 0,
                      ),
                      child: Text(
                        widget.time,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: const Color(0xFF86909C),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
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
        icon: Icons.groups_2_rounded,
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
    this.onOpenKb,
    this.onVoiceCall,
    this.onNewChat,
    this.onHistory,
    this.voiceCallBlocked = false,
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
  final VoidCallback? onOpenKb;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistory;
  final bool voiceCallBlocked;
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
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(
        14,
        4,
        14,
        bottomInset > 0 ? bottomInset + 6 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 悬浮大药丸输入条（高度自适应，圆角 30）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x121A2038),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                  spreadRadius: 1,
                ),
              ],
              border: Border.all(color: const Color(0xFFEDEFF5)),
            ),
            child: voiceMode
                ? Row(
                    children: [
                      if (_hasQuickActions)
                        _NovaInputIcon(
                          icon: quickActionsOpen
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                          onTap: locked ? null : onToggleQuickActions,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _NovaVoiceHoldField(
                          locked: locked,
                          recording: recording,
                          recordWillCancel: recordWillCancel,
                          recordDurationMs: recordDurationMs,
                          onLongPressStart: onVoiceHoldStart,
                          onLongPressMoveUpdate: onVoiceHoldMove,
                          onLongPressEnd: onVoiceHoldEnd,
                          onLongPressCancel: onVoiceHoldCancel,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _NovaInputIcon(
                        icon: Icons.keyboard_outlined,
                        onTap: onToggleVoice,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左侧：加号快捷操作按钮
                      if (_hasQuickActions)
                        _NovaInputIcon(
                          icon: quickActionsOpen
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                          onTap: locked ? null : onToggleQuickActions,
                        ),
                      const SizedBox(width: 6),

                      // 中间：输入框
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: enabled && !showStop,
                          minLines: 1,
                          maxLines: 4,
                          onTap: onInputFocused,
                          onSubmitted: locked ? null : (_) => onSend(),
                          style: DunesTypography.sans(
                            fontSize: 14.5,
                            color: const Color(0xFF1D2129),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: hintText,
                            hintStyle: DunesTypography.sans(
                              fontSize: 14,
                              color: const Color(0xFF86909C),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 7,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // 右侧：发送/语音/停止按钮（高质感圆形药丸图标）
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          final hasText = value.text.trim().isNotEmpty;
                          return _NovaInputIcon(
                            icon: showStop
                                ? Icons.stop_rounded
                                : hasText
                                ? Icons.arrow_upward_rounded
                                : Icons.graphic_eq_rounded,
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
          ),
          const SizedBox(height: 10),
          _NovaShortcutStrip(
            locked: locked,
            expanded: quickActionsOpen,
            swipeExpand: !isDesktopCommOnly,
            onToggleMore: onToggleQuickActions,
            onOpenKb: onOpenKb,
            onOpenMeeting: onOpenMeeting,
            onVoiceCall: voiceCallBlocked ? null : onVoiceCall,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: quickActionsOpen && !voiceMode
                ? _NovaMoreGrid(
                    onAttach: onAttach,
                    onCamera: onCamera,
                    onAlbum: onAlbum,
                    onMeetingPrd: onMeetingPrd,
                    onNewChat: onNewChat,
                    onHistory: onHistory,
                    onPickModel: onPickModel,
                    modelLabel: modelLabel,
                  )
                : const SizedBox.shrink(),
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
      onMeetingPrd != null ||
      onOpenKb != null ||
      onVoiceCall != null ||
      onNewChat != null ||
      onHistory != null;
}

class _NovaShortcutItem {
  const _NovaShortcutItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
}

class _NovaShortcutStrip extends StatelessWidget {
  const _NovaShortcutStrip({
    required this.locked,
    required this.expanded,
    required this.onToggleMore,
    this.swipeExpand = false,
    this.onOpenKb,
    this.onOpenMeeting,
    this.onVoiceCall,
  });

  final bool locked;
  final bool expanded;
  final bool swipeExpand;
  final VoidCallback onToggleMore;
  final VoidCallback? onOpenKb;
  final VoidCallback? onOpenMeeting;
  final VoidCallback? onVoiceCall;

  void _onVerticalDragEnd(DragEndDetails details) {
    if (locked || !swipeExpand) return;
    final velocity = details.primaryVelocity ?? 0;
    if (!expanded && velocity < -220) {
      HapticFeedback.selectionClick();
      onToggleMore();
      return;
    }
    if (expanded && velocity > 220) {
      HapticFeedback.selectionClick();
      onToggleMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_NovaShortcutItem>[
      if (onOpenKb != null)
        _NovaShortcutItem(
          icon: Icons.menu_book_outlined,
          label: '知识库',
          onTap: locked ? null : onOpenKb,
        ),
      if (onOpenMeeting != null)
        _NovaShortcutItem(
          icon: Icons.groups_2_rounded,
          label: '会议',
          onTap: locked ? null : onOpenMeeting,
        ),
      if (onVoiceCall != null)
        _NovaShortcutItem(
          icon: Icons.phone_in_talk_rounded,
          label: '电话',
          onTap: locked ? null : onVoiceCall,
        ),
      _NovaShortcutItem(
        icon: expanded ? Icons.expand_less_rounded : Icons.apps_rounded,
        label: expanded ? '收起' : '更多',
        onTap: locked ? null : onToggleMore,
        active: expanded,
      ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: swipeExpand ? _onVerticalDragEnd : null,
      child: Column(
        children: [
          Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _NovaCircleAction(
                    icon: item.icon,
                    label: item.label,
                    onTap: item.onTap,
                    active: item.active,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: expanded ? 46 : 36,
              height: 4,
              decoration: BoxDecoration(
                color: expanded
                    ? const Color(0xFFC4B5E8)
                    : const Color(0xFFD8DCE6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NovaCircleAction extends StatelessWidget {
  const _NovaCircleAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFF1EBFA) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active
                        ? const Color(0xFFD9C9F4)
                        : const Color(0xFFEEF0F5),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: active
                      ? const Color(0xFF6B3FE2)
                      : const Color(0xFF2C323F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active
                      ? const Color(0xFF6B3FE2)
                      : const Color(0xFF4E5969),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NovaMoreGrid extends StatelessWidget {
  const _NovaMoreGrid({
    this.onAttach,
    this.onCamera,
    this.onAlbum,
    this.onMeetingPrd,
    this.onNewChat,
    this.onHistory,
    this.onPickModel,
    this.modelLabel = '',
  });

  final VoidCallback? onAttach;
  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;
  final VoidCallback? onMeetingPrd;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistory;
  final VoidCallback? onPickModel;
  final String modelLabel;

  @override
  Widget build(BuildContext context) {
    final actions = <_NovaShortcutItem>[
      if (onCamera != null)
        _NovaShortcutItem(
          icon: Icons.photo_camera_outlined,
          label: '拍照',
          onTap: onCamera,
        ),
      if (onAlbum != null)
        _NovaShortcutItem(
          icon: Icons.photo_library_outlined,
          label: '图片',
          onTap: onAlbum,
        ),
      if (onAttach != null)
        _NovaShortcutItem(
          icon: Icons.attach_file_rounded,
          label: '文件',
          onTap: onAttach,
        ),
      if (onMeetingPrd != null)
        _NovaShortcutItem(
          icon: Icons.article_outlined,
          label: 'PRD',
          onTap: onMeetingPrd,
        ),
      if (onNewChat != null)
        _NovaShortcutItem(
          icon: Icons.add_comment_outlined,
          label: '新对话',
          onTap: onNewChat,
        ),
      if (onHistory != null)
        _NovaShortcutItem(
          icon: Icons.history_rounded,
          label: '历史',
          onTap: onHistory,
        ),
      if (onPickModel != null)
        _NovaShortcutItem(
          icon: Icons.auto_awesome_rounded,
          label: modelLabel.trim().isEmpty ? '模型' : modelLabel,
          onTap: onPickModel,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.start,
        children: [
          for (final action in actions)
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 420
                  ? (MediaQuery.sizeOf(context).width - 28) / 4
                  : 88,
              child: _NovaCircleAction(
                icon: action.icon,
                label: action.label,
                onTap: action.onTap,
              ),
            ),
        ],
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
          width: filled ? 32 : 30,
          height: filled ? 32 : 30,
          decoration: BoxDecoration(
            color: filled
                ? (accentBlue
                      ? const Color(0xFF6B3FE2)
                      : const Color(0xFF4E5969))
                : const Color(0xFFF5F6F9),
            shape: BoxShape.circle,
            boxShadow: filled
                ? const [
                    BoxShadow(
                      color: Color(0x226B3FE2),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: filled ? 18 : 17,
            color: filled ? Colors.white : const Color(0xFF4E5969),
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
              ? (recordWillCancel ? DunesColors.coral : const Color(0xFF2E75FF))
              : const Color(0xFFF3F7FF),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: recording ? Colors.transparent : const Color(0xFFD6E4FF),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!recording) ...[
              const Icon(
                Icons.mic_none_rounded,
                size: 20,
                color: Color(0xFF2E75FF),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              recording
                  ? (recordWillCancel
                        ? '松开取消'
                        : '松开发送 ${(recordDurationMs / 1000).toStringAsFixed(1)}s')
                  : '按住说话',
              style: DunesTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: recording ? Colors.white : const Color(0xFF2E75FF),
              ),
            ),
          ],
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
