import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'native_nova_service.dart';
import 'nova_affinity.dart';
import 'nova_history_utils.dart';
import 'nova_time_utils.dart';

/// 小饕左侧个人与历史记录面板。
/// 亲密度按真实对话计算；下面是账号信息和对话记录。
class NovaSideDrawer extends StatefulWidget {
  const NovaSideDrawer({
    super.key,
    required this.session,
    required this.userName,
    this.userAvatarUrl = '',
    required this.onNewChat,
    required this.onOpenConversation,
    required this.onOpenHistoryAll,
    this.onOpenKb,
    this.currentConversationId = 0,
    this.onCurrentConversationDeleted,
  });

  final AuthSession session;
  final String userName;
  final String userAvatarUrl;
  final VoidCallback onNewChat;
  final void Function(
    int conversationId,
    int messageId,
    String title,
    String preview,
  )
  onOpenConversation;
  final VoidCallback onOpenHistoryAll;
  final VoidCallback? onOpenKb;
  final int currentConversationId;
  final VoidCallback? onCurrentConversationDeleted;

  @override
  State<NovaSideDrawer> createState() => _NovaSideDrawerState();
}

class _NovaSideDrawerState extends State<NovaSideDrawer> {
  late final NativeNovaService _service;
  bool _loading = true;
  List<NovaHistoryTurn> _historyItems = [];

  @override
  void initState() {
    super.initState();
    _service = NativeNovaService(session: widget.session);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final res = await _service.fetchHistoryTurns(size: 25);
      if (!mounted) return;
      setState(() {
        _historyItems = res.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelete(NovaHistoryTurn item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '删除对话记录',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '确定要删除「${item.title.isEmpty ? '此对话' : item.title}」吗？删除后将无法恢复。',
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF4E5969),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: Color(0xFF86909C))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF4D4F),
            ),
            child: const Text(
              '删除',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final convId = item.conversationId;
    setState(() {
      _historyItems.removeWhere((t) => t.conversationId == convId);
    });

    try {
      await _service.deleteConversation(convId);
      if (widget.currentConversationId == convId) {
        widget.onCurrentConversationDeleted?.call();
      }
    } catch (_) {}
  }

  void _safeCloseDrawer() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String get _identityLine {
    final title = widget.session.jobTitle.trim();
    final dept = widget.session.departmentName.trim();
    if (title.isNotEmpty && dept.isNotEmpty) return '$dept · $title';
    if (title.isNotEmpty) return title;
    if (dept.isNotEmpty) return dept;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.userName.trim().isNotEmpty
        ? widget.userName.trim()
        : (widget.session.displayName?.trim().isNotEmpty == true
              ? widget.session.displayName!.trim()
              : '阿凡');

    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 可滚动的主体内容
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                children: [
                  _buildUserHeader(displayName),
                  const SizedBox(height: 16),
                  _buildAffinityCard(),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFF2F3F5)),
                  const SizedBox(height: 14),
                  _buildChatHistorySection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. 顶部用户信息与设置
  Widget _buildUserHeader(String displayName) {
    return Row(
      children: [
        // 用户头像
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFF2E8),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: ClipOval(
            child: widget.userAvatarUrl.isNotEmpty
                ? Image.network(
                    widget.userAvatarUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _buildAvatarFallback(displayName),
                  )
                : _buildAvatarFallback(displayName),
          ),
        ),
        const SizedBox(width: 12),

        // 名字 + 向右细箭头
        Expanded(
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D2129),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0xFF86909C),
                    ),
                  ],
                ),
                if (_identityLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _identityLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF86909C),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 六角形齿轮/设置图标（图 2 右上角）
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _safeCloseDrawer();
              widget.onOpenKb?.call();
            },
            borderRadius: BorderRadius.circular(20),
            child: Tooltip(
              message: '知识库',
              child: Container(
                padding: const EdgeInsets.all(6),
                child: const Icon(
                  Icons.menu_book_outlined,
                  size: 22,
                  color: Color(0xFF4E5969),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarFallback(String displayName) {
    final firstChar = displayName.isNotEmpty
        ? displayName.characters.first
        : '我';
    return Text(
      firstChar,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFFFF7D00),
      ),
    );
  }

  NovaAffinitySnapshot get _affinity => computeNovaAffinity(_historyItems);

  Widget _buildAffinityCard() {
    final affinity = _affinity;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showAffinitySheet(affinity),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF9F7FF), Color(0xFFF0E9FC)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9E0FA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4D5F8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 13,
                      color: Color(0xFF6B3FE2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '亲密度 ${affinity.level}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B3FE2),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Color(0xFF6B3FE2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                affinity.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF7E8695),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: affinity.progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE5D8F7),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF6B3FE2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${affinity.intoLevel}/${affinity.levelStep}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B3FE2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final skill in affinity.skills)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: skill.unlocked
                            ? const Color(0xFFEDE7F6)
                            : const Color(0xFFF4F5F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        skill.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: skill.unlocked
                              ? const Color(0xFF6B3FE2)
                              : const Color(0xFFC2C7D0),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAffinitySheet(NovaAffinitySnapshot affinity) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '亲密度 ${affinity.level}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D2129),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                affinity.subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF86909C),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '从真实对话里点亮',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4E5969),
                ),
              ),
              const SizedBox(height: 8),
              for (final skill in affinity.skills)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        skill.unlocked
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: skill.unlocked
                            ? const Color(0xFF6B3FE2)
                            : const Color(0xFFC2C7D0),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        skill.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: skill.unlocked
                              ? const Color(0xFF1D2129)
                              : const Color(0xFF86909C),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        skill.unlocked ? '已点亮' : '还没问过',
                        style: TextStyle(
                          fontSize: 12,
                          color: skill.unlocked
                              ? const Color(0xFF6B3FE2)
                              : const Color(0xFFC2C7D0),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 对话记录专区（支持删除）
  Widget _buildChatHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '对话记录',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D2129),
              ),
            ),
            const Spacer(),
            // 新建对话图标按钮（带加号的对话气泡图标）
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _safeCloseDrawer();
                  widget.onNewChat();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EBFA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_comment_outlined,
                        size: 15,
                        color: Color(0xFF6B3FE2),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '新建',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B3FE2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6B3FE2),
                ),
              ),
            ),
          )
        else if (_historyItems.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            child: const Text(
              '暂无历史对话',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF86909C)),
            ),
          )
        else
          ..._buildGroupedHistoryItems(),

        const SizedBox(height: 12),
        // 底部“查看全部历史记录”入口
        Center(
          child: TextButton(
            onPressed: () {
              _safeCloseDrawer();
              widget.onOpenHistoryAll();
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B3FE2),
              visualDensity: VisualDensity.compact,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '查看全部历史记录',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGroupedHistoryItems() {
    final widgets = <Widget>[];

    // 新建会话默认展示在对话记录的最顶部
    final isNewCurrent = widget.currentConversationId <= 0;
    widgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: isNewCurrent ? const Color(0xFFF7F3FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              _safeCloseDrawer();
              widget.onNewChat();
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: isNewCurrent
                        ? const Color(0xFF6B3FE2)
                        : const Color(0xFF86909C),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '新对话',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isNewCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isNewCurrent
                            ? const Color(0xFF6B3FE2)
                            : const Color(0xFF1D2129),
                      ),
                    ),
                  ),
                  if (isNewCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBE3FA),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '当前',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B3FE2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    DateTime? prevDay;

    for (final item in _historyItems) {
      final at = item.lastMessageAt;
      final dayLabel = historyDayDividerLabel(at, prevDay);
      if (dayLabel != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Text(
              dayLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF86909C),
              ),
            ),
          ),
        );
        prevDay = at;
      } else if (prevDay == null && at != null) {
        prevDay = at;
      }

      final isCurrent = item.conversationId == widget.currentConversationId;

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Material(
            color: isCurrent ? const Color(0xFFF7F3FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                _safeCloseDrawer();
                widget.onOpenConversation(
                  item.conversationId,
                  item.messageId,
                  item.title,
                  item.preview,
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title.isNotEmpty ? item.title : '对话记录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isCurrent
                              ? const Color(0xFF6B3FE2)
                              : const Color(0xFF1D2129),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 删除按钮（优雅垃圾桶图标）
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 17,
                        color: Color(0xFFC2C7D0),
                      ),
                      tooltip: '删除对话',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      onPressed: () => _confirmDelete(item),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}
