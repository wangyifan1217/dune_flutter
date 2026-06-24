import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/user_avatar_widget.dart';
import 'native_nova_service.dart';
import 'nova_icon.dart';
import 'nova_markdown.dart';
import 'nova_media.dart';
import 'nova_models_service.dart';

const kNovaName = '云枢';
const kNovaIntro =
    '你好，我是你的云枢助手。可以帮你查审批、找合同、对账单、读文档；直接问我即可。';
const kNovaInputPlaceholder = '问云枢';
const kNovaInputBusyHint = '云枢正在生成中，请稍候…';

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
    this.actionsEnabled = true,
  });

  final VoidCallback onBack;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenKb;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context) {
    final actionOpacity = actionsEnabled ? 1.0 : 0.38;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 11, 8, 11),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF8F1), DunesColors.bgApp],
        ),
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, size: 22),
              tooltip: '返回消息',
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DunesTypography.sans(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                  letterSpacing: -0.015 * 14.5,
                  height: 1.2,
                ),
                children: [
                  const TextSpan(text: kNovaName),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: NovaAiBadge(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onNewChat != null)
            Opacity(
              opacity: actionOpacity,
              child: SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: actionsEnabled ? onNewChat : null,
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: actionsEnabled ? '新对话' : '云枢正在生成中，请稍候…',
                ),
              ),
            ),
          if (onHistory != null)
            Opacity(
              opacity: actionOpacity,
              child: SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: actionsEnabled ? onHistory : null,
                  icon: const Icon(Icons.history, size: 20),
                  tooltip: actionsEnabled ? '对话历史' : '云枢正在生成中，请稍候…',
                ),
              ),
            ),
          if (onOpenKb != null)
            SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: onOpenKb,
                icon: const Icon(Icons.menu_book_outlined, size: 20),
                tooltip: '知识库',
              ),
            ),
        ],
      ),
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
  });

  final List<String> models;
  final String selected;
  final VoidCallback? onTap;
  final List<NovaModelCatalogEntry> modelCatalog;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) return const SizedBox.shrink();
    final multi = models.length > 1;
    final label = novaModelDisplayName(selected.isNotEmpty ? selected : models.first);
    final intro = novaModelDisplayIntro(selected.isNotEmpty ? selected : models.first, modelCatalog);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: multi ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: DunesColors.bgApp,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF553B96), Color(0xFF7B5CB8)],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8C553B96),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.memory, size: 17, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: DunesTypography.mono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                            letterSpacing: 0.03 * 13,
                            height: 1.25,
                          ),
                        ),
                        if (intro.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            intro,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              color: DunesColors.text3,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (multi)
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: DunesColors.text3),
                ],
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
                    '选择对话模型',
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
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: active
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0x2E553B96)),
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
                                          colors: [Color(0xFF553B96), Color(0xFF7B5CB8)],
                                        )
                                      : null,
                                  color: active ? null : DunesColors.bgApp,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.memory,
                                  size: 18,
                                  color: active ? Colors.white : DunesColors.accent,
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
                                      colors: [Color(0xFF553B96), Color(0xFF7B5CB8)],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 13, color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Text(
                  '模型介绍可在沙丘工作台 · 云枢模型管理中配置',
                  style: DunesTypography.sans(fontSize: 10, color: DunesColors.text3, height: 1.5),
                ),
              ),
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
              style: DunesTypography.sans(fontSize: 12, color: fg, height: 1.35),
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
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3, height: 1.4),
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
  late bool _collapsed = widget.initialCollapsed || widget.status.contains('已完成');

  @override
  void didUpdateWidget(NovaC4ThinkPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streaming && !widget.streaming && widget.body.trim().isNotEmpty) {
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
                  Icon(Icons.auto_awesome, size: 13, color: DunesColors.accentDeep),
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
                            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3, height: 1.4),
                          ),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: _collapsed ? -1.5708 : 0,
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: DunesColors.text3),
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
                style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3, height: 1.55),
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
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        border: Border.all(color: DunesColors.borderSoft),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: DefaultTextStyle(
        style: DunesTypography.sans(fontSize: 13, color: DunesColors.text, height: 1.5),
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
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
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
        border: highlighted ? Border.all(color: const Color(0x592F5D62), width: 2) : null,
      ),
      child: child ??
          Text(
            text,
            style: DunesTypography.sans(fontSize: 13, color: Colors.white, height: 1.5),
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

class _NovaC4ThinkingDotsState extends State<NovaC4ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
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
                  color: DunesColors.accent.withValues(alpha: opacity.clamp(0.35, 1.0)),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
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
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        gradient: RadialGradient(
          center: const Alignment(0, -1),
          radius: 1.4,
          colors: [
            const Color(0x0B7C62C2),
            Colors.transparent,
          ],
          stops: const [0.0, 0.65],
        ),
      ),
      child: child,
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
          const Expanded(child: Divider(color: DunesColors.borderSoft, height: 1)),
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
          const Expanded(child: Divider(color: DunesColors.borderSoft, height: 1)),
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
              style: DunesTypography.sans(fontSize: 16, fontWeight: FontWeight.w600),
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
                style: DunesTypography.sans(fontSize: 13, color: DunesColors.text),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: DunesColors.text3),
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
                              style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3),
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
    this.userAvatarUrl = '',
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
  });

  final bool mine;
  final String text;
  final int messageId;
  final String time;
  final String userName;
  final String userInitial;
  final int userSeed;
  final String userAvatarPreset;
  final String userAvatarUrl;
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

  bool _isImageAttachment(NovaMessageAttachment a) {
    final k = a.kind.toUpperCase();
    if (k == 'IMAGE') return true;
    if (a.mimeType.startsWith('image/')) return true;
    final ext = a.fileName.split('.').last.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif' || ext == 'webp';
  }

  bool _isImagePlaceholderLabel(String text) {
    final t = text.trim();
    return t == '[图片]' || t.startsWith('[图片]');
  }

  bool _shouldShowUserText(String text, List<NovaMessageAttachment> attachments) {
    if (text.trim().isEmpty) return false;
    if (attachments.isEmpty) return true;
    if (_isImagePlaceholderLabel(text)) return false;
    if (text.trim() == '已上传 1 张图片' && attachments.every(_isImageAttachment)) return false;
    return true;
  }

  Widget? _buildKindMedia(NovaMediaResolver? resolver, {required bool onDarkBubble}) {
    if (resolver == null) return null;
    final upperKind = kind.toUpperCase();
    if ((upperKind == 'IMAGE' || _isImagePlaceholderLabel(text)) && attachments.isNotEmpty) {
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
      return NovaC4FileLink(
        resolver: resolver,
        url: a.url,
        objectKey: a.objectKey,
        fileName: a.fileName.isNotEmpty ? a.fileName : text,
        onDarkBubble: onDarkBubble,
      );
    }
    return null;
  }

  Widget _buildUserBubbleContent() {
    final resolver = mediaResolver;
    final upperKind = kind.toUpperCase();
    final hasAttachments = attachments.isNotEmpty;

    // WebView sendNovaDraftMessage：TEXT + combined attachments 同气泡。
    if (upperKind == 'TEXT' && hasAttachments && resolver != null) {
      return NovaC4SentBubble(
        highlighted: highlighted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_shouldShowUserText(text, attachments))
              Text(
                text,
                style: DunesTypography.sans(fontSize: 13, color: Colors.white, height: 1.5),
              ),
            ...attachments.map((a) => _combinedAttachment(resolver, a)),
          ],
        ),
      );
    }

    final kindMedia = _buildKindMedia(resolver, onDarkBubble: true);
    if (kindMedia != null) {
      return NovaC4SentBubble(
        highlighted: highlighted,
        compactMedia: true,
        child: kindMedia,
      );
    }
    return NovaC4SentBubble(
      text: text,
      highlighted: highlighted,
    );
  }

  Widget _buildAiBubbleContent() {
    final resolver = mediaResolver;
    final kindMedia = _buildKindMedia(resolver, onDarkBubble: false);
    if (kindMedia != null) return kindMedia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (thinkText.isNotEmpty || thinkStatus.isNotEmpty)
          NovaC4ThinkPanel(
            status: thinkStatus,
            body: thinkText,
            streaming: streaming,
            initialCollapsed: !streaming,
          ),
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
            ...attachments.map((a) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _combinedAttachment(resolver, a, onDarkBubble: false),
                )),
          if (ragUsed && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '已参考您的文档',
                style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
              ),
            ),
        ],
      ],
    );
  }

  Widget _combinedAttachment(
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
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: NovaC4FileLink(
        resolver: resolver,
        url: a.url,
        objectKey: a.objectKey,
        fileName: a.fileName,
        onDarkBubble: onDarkBubble,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (time.isNotEmpty || userName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (userName.isNotEmpty)
                            Text(
                              userName,
                              style: DunesTypography.sans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: DunesColors.text2,
                              ),
                            ),
                          if (time.isNotEmpty && userName.isNotEmpty) const SizedBox(width: 6),
                          if (time.isNotEmpty)
                            Text(time, style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
                        ],
                      ),
                    ),
                  _buildUserBubbleContent(),
                  if (messageId > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Text(
                        '已读',
                        style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3, letterSpacing: 0.02 * 9),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            ImUserAvatar(
              initial: userInitial.isEmpty ? '?' : userInitial,
              seed: userSeed,
              size: 32,
              avatarPreset: userAvatarPreset.isEmpty ? null : userAvatarPreset,
              avatarUrl: userAvatarUrl.isEmpty ? null : userAvatarUrl,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NovaAiAvatar(),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kNovaName,
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.text2,
                        ),
                      ),
                      if (showAiBadge) ...[
                        const SizedBox(width: 6),
                        const NovaAiBadge(),
                      ],
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(time, style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
                      ],
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: highlighted
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x592F5D62), width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F2F5D62),
                              blurRadius: 0,
                              spreadRadius: 3,
                            ),
                          ],
                        )
                      : null,
                  child: NovaC4AiBubble(child: _buildAiBubbleContent()),
                ),
              ],
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
    required this.onNewChat,
    this.enabled = true,
  });

  final VoidCallback onCamera;
  final VoidCallback onAlbum;
  final VoidCallback onNewChat;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? 1.0 : 0.55;
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: const BoxDecoration(
          color: DunesColors.bgApp,
          border: Border(top: BorderSide(color: DunesColors.borderSoft)),
        ),
        child: Row(
          children: [
            Expanded(child: _QaCell(icon: Icons.photo_camera_outlined, label: '拍照', onTap: enabled ? onCamera : null)),
            Expanded(child: _QaCell(icon: Icons.photo_library_outlined, label: '图片', onTap: enabled ? onAlbum : null)),
            Expanded(child: _QaCell(icon: Icons.add, label: '新对话', onTap: enabled ? onNewChat : null)),
          ],
        ),
      ),
    );
  }
}

class _QaCell extends StatelessWidget {
  const _QaCell({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Icon(icon, size: 20, color: DunesColors.text2),
            const SizedBox(height: 5),
            Text(label, style: DunesTypography.sans(fontSize: 10, color: DunesColors.text3)),
          ],
        ),
      ),
    );
  }
}
