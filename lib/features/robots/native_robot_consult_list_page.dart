import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'robot_character.dart';
import 'robot_consult_store.dart';
import 'robot_markdown.dart';
import 'robot_models.dart';
import 'robot_service.dart';

/// 咨询列表 → GET /lighthouse/bot/consults
class NativeRobotConsultListPage extends StatefulWidget {
  const NativeRobotConsultListPage({
    super.key,
    required this.onBack,
    required this.onCreate,
    required this.onOpenDetail,
    this.session,
    this.robotKey = 'r_lighthouse',
  });

  final VoidCallback onBack;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpenDetail;
  final AuthSession? session;
  final String robotKey;

  @override
  State<NativeRobotConsultListPage> createState() =>
      _NativeRobotConsultListPageState();
}

class _NativeRobotConsultListPageState extends State<NativeRobotConsultListPage> {
  final _store = RobotConsultStore.instance;
  RobotRole _robot = RobotCatalog.lighthouse;
  String? _retryingId;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.bindSession(widget.session);
    _loadRobot();
    _store.refreshList(robotKey: widget.robotKey);
  }

  @override
  void didUpdateWidget(covariant NativeRobotConsultListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.token != widget.session?.token) {
      _store.bindSession(widget.session);
      _store.refreshList(robotKey: widget.robotKey);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRobot() async {
    final session = widget.session;
    if (session == null) return;
    try {
      final list = await RobotService(session: session).listRobots();
      if (!mounted || list.isEmpty) return;
      final matched = list.where((r) => r.id == widget.robotKey).firstOrNull;
      setState(() => _robot = matched ?? list.first);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rows = _store.records;
    return ColoredBox(
      color: RobotTheme.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody(rows)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          RobotFaceAvatar(role: _robot, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _robot.name,
                  style: DunesTypography.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: RobotTheme.text,
                  ),
                ),
                Text(
                  _store.unreadCount > 0
                      ? '未读 ${_store.unreadCount}'
                      : (_robot.category.isEmpty ? '咨询记录' : _robot.category),
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: RobotTheme.text3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _store.refreshList(robotKey: widget.robotKey),
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            color: RobotTheme.text2,
          ),
          IconButton(
            onPressed: widget.onCreate,
            tooltip: '新建咨询',
            icon: const Icon(Icons.add_rounded),
            color: RobotTheme.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<RobotConsultRecord> rows) {
    if (_store.loadingList && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_store.listError != null && rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _store.listError!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: const Color(0xFFC44949),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _store.refreshList(robotKey: widget.robotKey),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) return _buildEmpty();
    return RefreshIndicator(
      onRefresh: () => _store.refreshList(robotKey: widget.robotKey),
      child: _buildList(rows),
    );
  }

  Widget _buildEmpty() {
    final desc = _robot.desc.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RobotFaceAvatar(role: _robot, size: 72),
            const SizedBox(height: 16),
            Text(
              '还没有咨询记录',
              style: DunesTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RobotTheme.text,
              ),
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  height: 1.45,
                  color: RobotTheme.text3,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建咨询'),
              style: FilledButton.styleFrom(
                backgroundColor: RobotTheme.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<RobotConsultRecord> rows) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final row = rows[i];
        return Dismissible(
          key: ValueKey('consult-${row.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(row),
          onDismissed: (_) {
            // 已在 confirm 里删除；此处仅兜底刷新
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFC44949),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          child: _ConsultCard(
            record: row,
            retrying: _retryingId == row.id,
            onTap: () => widget.onOpenDetail(row.id),
            onRetry: () {
              unawaited(_retryConsult(row));
            },
            onDelete: () {
              unawaited(_confirmDelete(row));
            },
          ),
        );
      },
    );
  }

  Future<void> _retryConsult(RobotConsultRecord row) async {
    if (_retryingId != null) return;
    final q = row.question.trim();
    if (q.isEmpty) return;
    setState(() => _retryingId = row.id);
    try {
      final created = await _store.start(
        question: q,
        robotKey: row.robotKey.isNotEmpty ? row.robotKey : widget.robotKey,
      );
      if (!mounted) return;
      widget.onOpenDetail(created.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _retryingId = null);
    }
  }

  Future<bool> _confirmDelete(RobotConsultRecord row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条咨询？'),
        content: Text(
          row.question,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC44949)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    return _deleteRecord(row);
  }

  Future<bool> _deleteRecord(RobotConsultRecord row) async {
    try {
      await _store.delete(row.id);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
      return false;
    }
  }
}

class _ConsultCard extends StatelessWidget {
  const _ConsultCard({
    required this.record,
    required this.onTap,
    this.retrying = false,
    this.onRetry,
    this.onDelete,
  });

  final RobotConsultRecord record;
  final VoidCallback onTap;
  final bool retrying;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final color = switch (record.status) {
      RobotConsultStatus.queued => RobotTheme.text3,
      RobotConsultStatus.running => RobotTheme.purple,
      RobotConsultStatus.success => const Color(0xFF2E7544),
      RobotConsultStatus.failed => const Color(0xFFC44949),
    };
    final time =
        '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}';
    final done =
        record.nodes.where((n) => n.status == RobotNodeStatus.success).length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onDelete,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: record.unread && record.isTerminal
                  ? RobotTheme.purple.withValues(alpha: 0.45)
                  : RobotTheme.cardBorder,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 16, color: RobotTheme.purple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: RobotTheme.text,
                        ),
                      ),
                    ),
                    if (record.unread && record.isTerminal) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: RobotTheme.purple,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (record.status == RobotConsultStatus.running) ...[
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            record.status.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(width: 2),
                      IconButton(
                        onPressed: retrying ? null : onRetry,
                        tooltip: '重新咨询',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: retrying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: RobotTheme.purple,
                                ),
                              )
                            : const Icon(
                                Icons.replay_rounded,
                                size: 18,
                                color: RobotTheme.purple,
                              ),
                      ),
                    ],
                    if (onDelete != null) ...[
                      IconButton(
                        onPressed: onDelete,
                        tooltip: '删除',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: RobotTheme.text3,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  record.status == RobotConsultStatus.success &&
                          record.resultSummary.isNotEmpty
                      ? robotPlainPreview(record.resultSummary)
                      : '节点 $done/${record.nodes.length}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    height: 1.4,
                    color: RobotTheme.text2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  time,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: RobotTheme.text3,
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
