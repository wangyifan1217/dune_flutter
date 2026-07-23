import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'robot_character.dart';
import 'robot_models.dart';
import 'robot_widgets.dart';

/// N8N 流程运行页（静态模拟节点状态与回复）。不接真实 API，也不碰 C4 NOVA。
class NativeRobotRunPage extends StatefulWidget {
  const NativeRobotRunPage({
    super.key,
    required this.scenarioId,
    required this.onBack,
  });

  final String scenarioId;
  final VoidCallback onBack;

  @override
  State<NativeRobotRunPage> createState() => _NativeRobotRunPageState();
}

class _NativeRobotRunPageState extends State<NativeRobotRunPage> {
  late RobotScenario _scenario;
  late List<RobotFlowNode> _nodes;
  Timer? _timer;
  int _cursor = -1;
  bool _finished = false;

  static const _demoReplies = <String, List<String>>{
    'sc_meeting': [
      '已接收运行请求，workflowId=wf_meeting_demo',
      '摘要完成：本周同步了 3 项待办，重点关注上线窗口。',
      '质检通过：关键字段齐全，无明显缺漏。',
      '已推送到「产品周会」会话，delivery=ok',
    ],
    'sc_cursor': [
      'Cron 触发成功，period=本周',
      '汇总 12 个账号，异常用量 2 个。',
      '周报已发送给管理员。',
    ],
  };

  @override
  void initState() {
    super.initState();
    _scenario = RobotCatalog.scenarioById(widget.scenarioId);
    _nodes = _scenario.nodes
        .map((n) => n.copyWith(status: RobotNodeStatus.pending))
        .toList();
    _startDemo();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startDemo() {
    _timer?.cancel();
    setState(() {
      _cursor = -1;
      _finished = false;
      _nodes = _scenario.nodes
          .map((n) => n.copyWith(status: RobotNodeStatus.pending, reply: ''))
          .toList();
    });

    _timer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_cursor >= 0 && _cursor < _nodes.length) {
          final replies = _demoReplies[_scenario.id] ?? const <String>[];
          final reply = _cursor < replies.length ? replies[_cursor] : '节点输出（静态预览）';
          _nodes[_cursor] = _nodes[_cursor].copyWith(
            status: RobotNodeStatus.success,
            reply: reply,
            durationLabel: '${0.6 + _cursor * 0.3}s',
          );
        }
        _cursor++;
        if (_cursor >= _nodes.length) {
          _finished = true;
          t.cancel();
          return;
        }
        _nodes[_cursor] = _nodes[_cursor].copyWith(
          status: RobotNodeStatus.running,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _nodes.where((n) => n.status == RobotNodeStatus.success).length;
    final progress = _nodes.isEmpty ? 0.0 : done / _nodes.length;

    return ColoredBox(
      color: RobotTheme.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ProgressBanner(
                scenario: _scenario,
                progress: progress,
                finished: _finished,
                running: !_finished && _cursor >= 0,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                itemCount: _nodes.length,
                itemBuilder: (context, i) {
                  return _NodeTile(
                    index: i,
                    node: _nodes[i],
                    isLast: i == _nodes.length - 1,
                  );
                },
              ),
            ),
            if (_finished)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: RobotTheme.purple,
                            side: const BorderSide(color: RobotTheme.purple),
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('返回场景'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _startDemo,
                          style: FilledButton.styleFrom(
                            backgroundColor: RobotTheme.purple,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('再跑一遍'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '流程运行',
                  style: DunesTypography.sans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: RobotTheme.text,
                  ),
                ),
                Text(
                  'N8N 节点状态 · 静态模拟',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: RobotTheme.text3,
                  ),
                ),
              ],
            ),
          ),
          RobotAvatarStack(roleIds: _scenario.roleIds, size: 26),
        ],
      ),
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({
    required this.scenario,
    required this.progress,
    required this.finished,
    required this.running,
  });

  final RobotScenario scenario;
  final double progress;
  final bool finished;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final statusText = finished
        ? '全部节点已完成'
        : running
            ? '正在执行…'
            : '准备启动';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RobotTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scenario.title,
            style: DunesTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RobotTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: DunesTypography.sans(
              fontSize: 12,
              color: finished ? const Color(0xFF2E7544) : RobotTheme.purple,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: finished ? 1 : progress.clamp(0.05, 1),
              minHeight: 6,
              backgroundColor: RobotTheme.purpleSoft,
              color: RobotTheme.purple,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.index,
    required this.node,
    required this.isLast,
  });

  final int index;
  final RobotFlowNode node;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = robotStatusColor(node.status);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(robotStatusIcon(node.status), size: 22, color: color),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: node.status == RobotNodeStatus.success
                          ? const Color(0xFF2E7544).withValues(alpha: 0.35)
                          : const Color(0xFFE0E2E6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: node.status == RobotNodeStatus.running
                      ? RobotTheme.purple.withValues(alpha: 0.45)
                      : RobotTheme.cardBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${index + 1}. ${node.name}',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: RobotTheme.text,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          robotStatusLabel(node.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '类型 ${node.typeLabel}'
                    '${node.durationLabel.isEmpty ? '' : ' · ${node.durationLabel}'}',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: RobotTheme.text3,
                    ),
                  ),
                  if (node.reply.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        node.reply,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          height: 1.45,
                          color: RobotTheme.text2,
                        ),
                      ),
                    ),
                  ] else if (node.status == RobotNodeStatus.running) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: RobotTheme.purple,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '节点执行中，等待 N8N 回调…',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: RobotTheme.purple,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
