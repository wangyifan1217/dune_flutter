import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// Windows / macOS / 宽屏下的「侧栏导航 + 会话列表 + 聊天窗口」壳。
///
/// 左侧竖栏导航；列表与聊天分栏渲染，窄屏不应使用本组件。
class ChatDualPaneShell extends StatelessWidget {
  const ChatDualPaneShell({
    super.key,
    required this.listPane,
    required this.chatPane,
    required this.sideRail,
    this.listPaneWidth = 320,
  });

  final Widget listPane;
  final Widget chatPane;
  final Widget sideRail;
  final double listPaneWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sideRail,
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
