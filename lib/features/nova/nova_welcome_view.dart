import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'nova_feedback_dialog.dart';
import 'nova_icon.dart';

/// 小饕迎宾视图：拟人形象、反馈与投诉、沙丘业务推荐卡与现有能力入口。
class NovaAiPartnerWelcomeView extends StatefulWidget {
  const NovaAiPartnerWelcomeView({
    super.key,
    required this.onSelectPrompt,
    this.name = '小饕',
    this.subtitle = '你在沙丘上的AI全能伙伴',
  });

  final ValueChanged<String> onSelectPrompt;
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
      icon: Icons.menu_book_outlined,
      iconColor: Color(0xFF2E75FF),
      iconBg: Color(0xFFEBF3FF),
    ),
    _WelcomePromptItem(
      title: '总结一下知识库里最近的文档',
      subtitle: '提炼要点，方便快速过一遍',
      prompt: '总结一下知识库里最近的文档，列出关键要点',
      icon: Icons.auto_awesome_outlined,
      iconColor: Color(0xFF7A42F4),
      iconBg: Color(0xFFF2ECFC),
    ),
    _WelcomePromptItem(
      title: '根据会议纪要列出要点',
      subtitle: '从会议入口选纪要，也可以直接问我',
      prompt: '根据最近的会议纪要，帮我列出要点和待办',
      icon: Icons.groups_2_rounded,
      iconColor: Color(0xFF00B087),
      iconBg: Color(0xFFE6F8F3),
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
    NovaFeedbackDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          // 1. 头像区：拟人 3D 头像 + 阿宝柔光粉紫蓝渐变光晕
          _buildStaggeredItem(
            start: 0.00,
            end: 0.40,
            offsetY: 18.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 蓝粉微光渐变光晕
                Container(
                  width: 150,
                  height: 150,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFFE5EEFC),
                        Color(0xFFEDE4FB),
                        Color(0x00F8F7FF),
                      ],
                      stops: [0.25, 0.70, 1.0],
                    ),
                  ),
                ),
                // 眨眼 3D 卡通拟人形象
                const NovaBlinkingAvatar(size: 114),
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
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF191D24),
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 5),

          // 3. 副标题：“你在沙丘上的AI全能伙伴” + 右侧贴边悬浮“反馈与投诉”
          _buildStaggeredItem(
            start: 0.16,
            end: 0.54,
            offsetY: 16.0,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    widget.subtitle,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF7E8695),
                    ),
                  ),
                ),
                Positioned(
                  right: -16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showFeedbackDialog,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF32363D),
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 6,
                              offset: Offset(-1, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 3),
                            Text(
                              '反馈与投诉',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // 4. 推荐提问卡片：3 张白色大圆角卡片（与支付宝阿宝一致）
          ..._prompts.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final start = 0.24 + index * 0.09;
            final end = (start + 0.40).clamp(0.0, 1.0);
            return _buildStaggeredItem(
              start: start,
              end: end,
              offsetY: 30.0,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: _PromptCard(
                  item: item,
                  onTap: () => widget.onSelectPrompt(item.prompt),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),

          _buildStaggeredItem(
            start: 0.58,
            end: 0.98,
            offsetY: 24.0,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                '内容由 AI 生成',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: const Color(0xFFC2C7D0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
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
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  final String title;
  final String subtitle;
  final String prompt;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
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
      scale: _pressed ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          borderRadius: BorderRadius.circular(22),
          splashColor: item.iconColor.withValues(alpha: 0.08),
          highlightColor: item.iconColor.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFEEF0F5), width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A2B3B60),
                  offset: Offset(0, 4),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: item.iconBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Icon(item.icon, size: 21, color: item.iconColor),
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
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF191D24),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: const Color(0xFF86909C),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFFCFD5DF),
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
        border: Border.all(color: Colors.white, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B3FE2).withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: NovaPersonAvatarImage(
          width: size,
          height: size,
          wink: true,
        ),
      ),
    );
  }
}
