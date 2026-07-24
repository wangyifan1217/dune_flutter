import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'robot_character.dart';
import 'robot_consult_store.dart';
import 'robot_markdown.dart';
import 'robot_models.dart';
import 'robot_widgets.dart';

/// 咨询详情 → GET /robot/consults/{jobId}
/// 轮询用 markRead=0；首次进入详情默认标已读（文档 §5.4 / §6）。
class NativeRobotConsultDetailPage extends StatefulWidget {
  const NativeRobotConsultDetailPage({
    super.key,
    required this.consultId,
    required this.onBack,
    this.session,
  });

  final String consultId;
  final VoidCallback onBack;
  final AuthSession? session;

  @override
  State<NativeRobotConsultDetailPage> createState() =>
      _NativeRobotConsultDetailPageState();
}

class _NativeRobotConsultDetailPageState
    extends State<NativeRobotConsultDetailPage> {
  final _store = RobotConsultStore.instance;
  bool _loading = true;
  String? _error;
  /// null：按终态自动折叠；非 null：用户手动展开/收起。
  bool? _nodesExpandedOverride;
  bool _forwarding = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.bindSession(widget.session);
    _bootstrap();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _forwardResult(RobotConsultRecord record) async {
    final session = widget.session;
    final markdown = record.resultSummary.trim();
    if (session == null || markdown.isEmpty || _forwarding) return;
    final service = ConversationService(session: session);
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: service,
      title: '转发至',
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;

    setState(() => _forwarding = true);
    try {
      await service.sendText(
        conversationId,
        markdown,
        payload: <String, dynamic>{
          'robotMarkdown': true,
          'robotKey': record.robotKey,
          'robotName': RobotCatalog.roleById(record.robotKey).name,
          'forwardedFromRobot': true,
          'consultId': record.id,
          'question': record.question,
        },
      );
      if (mounted) showDunesToast(context, '已转发');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // 打开详情：先拉一次（默认标已读），未结束则继续轮询 markRead=0
    _store.watch(widget.consultId, markReadWhenOpen: true);
    // 给首屏一点时间；若本地已有缓存则立刻展示
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final record = _store.byId(widget.consultId);
    setState(() {
      _loading = false;
      if (record == null) {
        _error = '正在加载咨询详情…';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = _store.byId(widget.consultId);
    if (record == null) {
      return ColoredBox(
        color: RobotTheme.pageBg,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading)
                  const CircularProgressIndicator()
                else
                  Text(
                    _error ?? '记录不存在或加载失败',
                    style: DunesTypography.sans(color: RobotTheme.text2),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _bootstrap,
                  child: Text(_loading ? '加载中…' : '重试'),
                ),
                TextButton(onPressed: widget.onBack, child: const Text('返回')),
              ],
            ),
          ),
        ),
      );
    }

    final done =
        record.nodes.where((n) => n.status == RobotNodeStatus.success).length;
    final progress =
        record.nodes.isEmpty ? 0.0 : done / record.nodes.length;
    // 进行中默认展开；全部完成/失败后默认收起，用户可再打开。
    final nodesExpanded =
        _nodesExpandedOverride ?? !record.isTerminal;

    return ColoredBox(
      color: RobotTheme.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
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
                          '咨询详情',
                          style: DunesTypography.sans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: RobotTheme.text,
                          ),
                        ),
                        Text(
                          record.status.label,
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: record.status == RobotConsultStatus.success
                                ? const Color(0xFF2E7544)
                                : RobotTheme.purple,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (record.resultSummary.trim().isNotEmpty)
                    IconButton(
                      tooltip: '转发咨询结果',
                      onPressed: _forwarding
                          ? null
                          : () => _forwardResult(record),
                      icon: _forwarding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shortcut_rounded, size: 20),
                      color: RobotTheme.text2,
                    ),
                  RobotFaceAvatar(
                    role: RobotCatalog.lighthouse,
                    size: 32,
                    animate: true,
                    busy: record.status == RobotConsultStatus.running ||
                        record.status == RobotConsultStatus.queued,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  Container(
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
                          '问题',
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: RobotTheme.text3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.question,
                          style: DunesTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: RobotTheme.text,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: record.isTerminal
                                ? 1
                                : progress.clamp(0.05, 1),
                            minHeight: 6,
                            backgroundColor: RobotTheme.purpleSoft,
                            color: RobotTheme.purple,
                          ),
                        ),
                        if (record.resultSummary.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          RobotMarkdown(markdown: record.resultSummary),
                        ],
                      ],
                    ),
                  ),
                  if (record.nodes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _nodesExpandedOverride = !nodesExpanded;
                          });
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: RobotTheme.cardBorder),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_tree_outlined,
                                  size: 18,
                                  color: record.isTerminal
                                      ? const Color(0xFF2E7544)
                                      : RobotTheme.purple,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    record.isTerminal
                                        ? '执行节点 $done/${record.nodes.length} · 已完成'
                                        : '执行节点 $done/${record.nodes.length}',
                                    style: DunesTypography.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: RobotTheme.text,
                                    ),
                                  ),
                                ),
                                Text(
                                  nodesExpanded ? '收起' : '展开',
                                  style: DunesTypography.sans(
                                    fontSize: 12,
                                    color: RobotTheme.text3,
                                  ),
                                ),
                                Icon(
                                  nodesExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: RobotTheme.text3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (nodesExpanded) ...[
                      const SizedBox(height: 10),
                      for (var i = 0; i < record.nodes.length; i++)
                        _NodeTile(
                          index: i,
                          node: record.nodes[i],
                          isLast: i == record.nodes.length - 1,
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
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
                      child: RobotMarkdown(
                        markdown: node.reply,
                        compact: true,
                      ),
                    ),
                  ] else if (node.status == RobotNodeStatus.running) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: RobotTheme.purple,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '节点执行中…',
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
