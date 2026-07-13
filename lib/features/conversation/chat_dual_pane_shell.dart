import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// Windows / 宽屏下的「会话列表 + 聊天窗口」双栏壳。
///
/// 底部 Tab 横跨整宽；列表与聊天分栏渲染，窄屏不应使用本组件。
class ChatDualPaneShell extends StatelessWidget {
  const ChatDualPaneShell({
    super.key,
    required this.listPane,
    required this.chatPane,
    required this.bottomBar,
    this.listPaneWidth = 320,
  });

  final Widget listPane;
  final Widget chatPane;
  final Widget bottomBar;
  final double listPaneWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: listPaneWidth,
                  child: listPane,
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: DunesColors.borderSoft,
                ),
                Expanded(child: chatPane),
              ],
            ),
          ),
          bottomBar,
        ],
      ),
    );
  }
}

/// 双栏右侧尚未选中会话时的占位。
class ChatDualPaneEmpty extends StatelessWidget {
  const ChatDualPaneEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgSoft,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 52,
                color: DunesColors.text3.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 16),
              Text(
                '选择会话开始聊天',
                style: DunesTypography.sans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '从左侧列表打开私聊或群聊',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
