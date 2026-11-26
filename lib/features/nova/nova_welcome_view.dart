import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'nova_feedback_dialog.dart';
import 'nova_icon.dart';
import 'nova_personal_query.dart';

/// 小饕迎宾视图：拟人形象、反馈与投诉、沙丘业务推荐卡与现有能力入口。
class NovaAiPartnerWelcomeView extends StatefulWidget {
  const NovaAiPartnerWelcomeView({
    super.key,
    required this.onSelectPrompt,
    this.onSelectCapability,
    this.onSubmitFeedback,
    this.name = '小饕',
    this.subtitle = '你在沙丘上的AI全能伙伴',
  });

  final ValueChanged<String> onSelectPrompt;
  final void Function(NovaPersonalCapability capability, String prompt)?
      onSelectCapability;
  final Future<void> Function(String kind, String content)? onSubmitFeedback;
  final String name;
  final String subtitle;

  @override
  State<NovaAiPartnerWelcomeView> createState() =>
      _NovaAiPartnerWelcomeViewState();
}

class _NovaAiPartnerWelcomeViewState extends State<NovaAiPartnerWelcomeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;

  static const List<_WelcomePromptItem> _prompts = [
    _WelcomePromptItem(
      title: '帮我在知识库里找相关资料',
      subtitle: '检索已上传的制度、材料和文档',
      prompt: '帮我在知识库里找相关资料',
      icon: Icons.menu_book_rounded,
      iconColor: DunesColors.blue,
      iconBg: DunesColors.blueSoft,
    ),
    _WelcomePromptItem(
      title: '总结一下知识库里最近的文档',
      subtitle: '提炼要点，方便快速过一遍',
      prompt: '总结一下知识库里最近的文档，列出关键要点',
      icon: Icons.auto_awesome_rounded,
      iconColor: DunesColors.brandPurple,
      iconBg: DunesColors.brandPurpleSoft,
    ),
    _WelcomePromptItem(
      title: '根据会议纪要列出要点',
      subtitle: '从会议入口选纪要，也可以直接问我',
      prompt: '根据最近的会议纪要，帮我列出要点和待办',
      icon: Icons.groups_2_rounded,
      iconColor: DunesColors.green,
      iconBg: DunesColors.greenSoft,
    ),
    _WelcomePromptItem(
      title: '管理我的任务',
      subtitle: '查看本人负责、协同、参与和创建的任务',
      prompt: '帮我看看和我相关的任务',
      capability: NovaPersonalCapability.tasks,
      icon: Icons.task_alt_rounded,
      iconColor: DunesColors.accent,
      iconBg: DunesColors.accentSoft,
    ),
    _WelcomePromptItem(
      title: '查询灯塔数据',
      subtitle: '看今天的经营总览，只读',
      prompt: '今天灯塔整体怎么样？',
      capability: NovaPersonalCapability.lighthouse,
      icon: Icons.insights_rounded,
      iconColor: DunesColors.amber,
      iconBg: DunesColors.amberSoft,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Widget _buildStaggeredItem({
    required double start,
    required double end,
    required Widget child,
    double offsetY = 28.0,
  }) {
    final animation = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = animation.value;
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - progress) * offsetY),
            child: child,
          ),
        );
      },
    );
  }

  void _showFeedbackDialog() {
    final submit = widget.onSubmitFeedback;
    NovaFeedbackDialog.show(
      context,
      onSubmit: submit == null
          ? null
          : (kind, content) => submit(kind.name, content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 760;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 16,
        vertical: isWide ? 20 : 8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWide ? 640 : double.infinity,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),

              // 1. 头像区：拟人 3D 头像 + 沙丘紫暖金柔光光晕
              _buildStaggeredItem(
                start: 0.00,
                end: 0.40,
                offsetY: 18.0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 156,
                      height: 156,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            DunesColors.resolve(
                              context,
                              DunesColors.brandPurpleSoft,
                              role: DunesColorRole.surface,
                            ),
                            DunesColors.resolve(
                              context,
                              const Color(0x80F3EEFA),
                              role: DunesColorRole.surface,
                            ),
                            DunesColors.resolve(
                              context,
                              const Color(0x00F5F5F7),
                              role: DunesColorRole.surface,
                            ),
                          ],
                          stops: const [0.22, 0.62, 1.0],
                        ),
                      ),
                    ),
                    const NovaBlinkingAvatar(size: 112),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. 问候语：“Hi，我是小饕”
              _buildStaggeredItem(
                start: 0.10,
                end: 0.48,
                offsetY: 20.0,
                child: Text(
                  'Hi，我是${widget.name}',
                  style: DunesTypography.sans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolve(context, DunesColors.text),
                    letterSpacing: -0.5,
                    context: context,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // 3. 副标题 + iOS 胶囊反馈按钮
              _buildStaggeredItem(
                start: 0.16,
                end: 0.54,
                offsetY: 16.0,
                child: Column(
                  children: [
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: DunesColors.resolve(context, DunesColors.text2),
                        context: context,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FeedbackPillButton(onTap: _showFeedbackDialog),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 4. 玻璃通透感推荐提问卡片组
              _buildStaggeredItem(
                start: 0.24,
                end: 0.78,
                offsetY: 26.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.045)
                        : Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFEAE5F7),
                      width: 0.9,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? const Color(0x22000000)
                            : const Color(0x0E583EA8),
                        offset: const Offset(0, 6),
                        blurRadius: 20,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _prompts.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 70),
                        child: Divider(
                          height: 0.6,
                          thickness: 0.6,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.borderSoft,
                            role: DunesColorRole.border,
                          ),
                        ),
                      ),
                    _PromptCard(
                      item: _prompts[i],
                      onTap: () {
                        final item = _prompts[i];
                        final capability = item.capability;
                        if (capability != null &&
                            widget.onSelectCapability != null) {
                          widget.onSelectCapability!(capability, item.prompt);
                          return;
                        }
                        widget.onSelectPrompt(item.prompt);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildStaggeredItem(
            start: 0.58,
            end: 0.98,
            offsetY: 20.0,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                '内容由 AI 生成',
                style: DunesTypography.sans(
                  fontSize: 11.5,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
        ),
      ),
    );
  }
}

/// 快捷问答卡片项定义
class _WelcomePromptItem {
  const _WelcomePromptItem({
    required this.title,
    required this.subtitle,
    required this.prompt,
    this.capability,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  final String title;
  final String subtitle;
  final String prompt;
  final NovaPersonalCapability? capability;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
}

class _FeedbackPillButton extends StatefulWidget {
  const _FeedbackPillButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_FeedbackPillButton> createState() => _FeedbackPillButtonState();
}

class _FeedbackPillButtonState extends State<_FeedbackPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFE5E5EA),
                  role: DunesColorRole.border,
                ),
                width: 0.8,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  color: DunesColors.resolve(context, DunesColors.text2),
                  size: 15,
                ),
                const SizedBox(width: 4),
                Text(
                  '反馈与投诉',
                  style: DunesTypography.sans(
                    color: DunesColors.resolve(context, DunesColors.text2),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    context: context,
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

class _PromptCard extends StatefulWidget {
  const _PromptCard({required this.item, required this.onTap});

  final _WelcomePromptItem item;
  final VoidCallback onTap;

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          splashColor: item.iconColor.withValues(alpha: 0.07),
          highlightColor: DunesColors.resolve(
            context,
            DunesColors.bgSoft,
            role: DunesColorRole.surface,
          ).withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: DunesColors.resolveNullable(
                      context,
                      item.iconBg,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.icon,
                    size: 20,
                    color: DunesColors.resolveNullable(context, item.iconColor),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.resolve(context, DunesColors.text),
                          letterSpacing: -0.2,
                          context: context,
                        ),
                      ),
                      const SizedBox(height: 2.5),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          color: DunesColors.resolve(context, DunesColors.text2),
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小饕拟人形象：会话页和电话页固定 wink 静帧。
class NovaBlinkingAvatar extends StatelessWidget {
  const NovaBlinkingAvatar({super.key, this.size = 114});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: DunesColors.resolve(
            context,
            DunesColors.imSurface,
            role: DunesColorRole.border,
          ),
          width: 3.5,
        ),
        boxShadow: [
          BoxShadow(
            color: DunesColors.brandPurple.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: NovaPersonAvatarImage(width: size, height: size, animate: true),
      ),
    );
  }
}
