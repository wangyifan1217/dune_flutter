import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

const _assistantPurple = Color(0xFF7B5CD8);

/// 会议纪要助理的纯静态对话预览，供首期 UI 验收使用。
class NativeMeetingAssistantPreviewPage extends StatelessWidget {
  const NativeMeetingAssistantPreviewPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0.08, end: 0),
          builder: (context, offset, child) => Transform.translate(
            offset: Offset(MediaQuery.sizeOf(context).width * offset, 0),
            child: Opacity(opacity: 1 - offset * 4, child: child),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  children: [
                    _buildWelcomeCard(),
                    const SizedBox(height: 18),
                    _buildAssistantMessage(),
                    const SizedBox(height: 12),
                    _buildUserMessage(),
                    const SizedBox(height: 12),
                    _buildDecisionReply(),
                  ],
                ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final compactActions = MediaQuery.sizeOf(context).width < 640;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: _assistantPurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '会议纪要助理',
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                Text(
                  '仅查询你有权限查看的会议纪要',
                  style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
                ),
              ],
            ),
          ),
          _ConversationAction(
            icon: Icons.history_rounded,
            label: '对话记录',
            compact: compactActions,
          ),
          const SizedBox(width: 8),
          _ConversationAction(
            icon: Icons.add_comment_outlined,
            label: '新建对话',
            primary: true,
            compact: compactActions,
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF1EDFF), Color(0xFFFAF9FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2DCFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '你好，我是会议纪要助理',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF49338B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '我可以帮你回顾自己的会议结论、重大决策和待办事项。',
            style: DunesTypography.sans(
              fontSize: 13,
              height: 1.5,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _PromptChip(label: '本周有哪些待办？'),
              _PromptChip(label: '总结上次项目会决策'),
              _PromptChip(label: '哪些事项快到期？'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantMessage() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AssistantAvatar(size: 32),
        const SizedBox(width: 8),
        Flexible(
          child: _ChatBubble(
            child: Text(
              '欢迎回来。你可以直接问我会议中的决策、行动项，或查看某场会议的要点。',
              style: DunesTypography.sans(fontSize: 13, height: 1.55, color: DunesColors.text),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserMessage() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _assistantPurple,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '帮我总结今天项目例会的重要决策',
          style: DunesTypography.sans(fontSize: 13, height: 1.45, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDecisionReply() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AssistantAvatar(size: 32),
        const SizedBox(width: 8),
        Flexible(
          child: _ChatBubble(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '项目例会 · 今日 10:00',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5D43AE),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '重大决策',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '• 本周完成会议纪要助理的静态交互验收\n'
                  '• 正式接入前仅开放本人会议纪要查询\n'
                  '• 行动项到期提醒默认提前 24 小时',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    height: 1.6,
                    color: DunesColors.text2,
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFE7E5EE)),
                const SizedBox(height: 9),
                Text(
                  '以上为静态预览内容，尚未连接真实会议数据。',
                  style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EAED))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(21),
              ),
              child: Text(
                '输入你的问题…',
                style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const CircleAvatar(
            radius: 20,
            backgroundColor: _assistantPurple,
            child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8D0FB)),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(fontSize: 12, color: const Color(0xFF5D43AE)),
      ),
    );
  }
}

class _ConversationAction extends StatelessWidget {
  const _ConversationAction({
    required this.icon,
    required this.label,
    this.primary = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : const Color(0xFF5D43AE);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 11,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: primary ? _assistantPurple : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: primary ? null : Border.all(color: const Color(0xFFD8D0FB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _assistantPurple, shape: BoxShape.circle),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.52),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: child,
    );
  }
}
