import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';

/// 对账助手的静态预览页。
///
/// 目前先用本地示例数据把「对账信息—他人评价—我的评论—确认」这条流程
/// 展示出来，后续再接每日对账单和确认接口。
class NativeReconciliationAssistantPage extends StatefulWidget {
  const NativeReconciliationAssistantPage({
    super.key,
    required this.onBack,
    this.desktopMode = false,
  });

  final VoidCallback onBack;

  /// 桌面端已经位于会话右侧面板，直接展示详情，省去消息卡片过渡。
  final bool desktopMode;

  @override
  State<NativeReconciliationAssistantPage> createState() =>
      _NativeReconciliationAssistantPageState();
}

class _NativeReconciliationAssistantPageState
    extends State<NativeReconciliationAssistantPage> {
  final TextEditingController _commentController = TextEditingController();
  bool _confirmed = false;
  bool _showDetails = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _confirm() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _confirmed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已记录你的对账意见并完成确认'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktopMode) {
      // 桌面端先呈现会话里的名片，点击“查看详情”后直接切换到详情，
      // 不使用移动端的滑动过渡。
      return _showDetails
          ? _buildDetailScaffold()
          : _buildConversationScaffold();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final isDetail =
            child.key == const ValueKey<String>('reconciliation-detail');
        final begin = isDetail ? const Offset(1, 0) : const Offset(-0.16, 0);
        return SlideTransition(
          position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          _showDetails ? 'reconciliation-detail' : 'reconciliation-chat',
        ),
        child: _showDetails
            ? _buildDetailScaffold()
            : _buildConversationScaffold(),
      ),
    );
  }

  Widget _buildConversationScaffold() {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '对账助手',
              subtitle: '每日对账 · 3 位参与人',
              onBack: widget.onBack,
              leadingAvatar: const _ReconciliationAssistantAvatar(size: 45),
              actions: [
                IconButton(
                  tooltip: '说明',
                  onPressed: _showInfo,
                  icon: const Icon(Icons.help_outline_rounded, size: 21),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
                children: [
                  Center(
                    child: Text(
                      '今天 09:00',
                      style: DunesTypography.mono(
                        fontSize: 10,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ChatMessageRow(
                    message: const NativeChatMessage(
                      id: 1001,
                      senderUserId: 0,
                      senderName: '对账助手',
                      kind: 'RECONCILIATION_ASSISTANT',
                      bodyText: '今日对账信息已生成',
                      createdAt: null,
                    ),
                    mine: false,
                    showSenderMeta: true,
                    readLabel: null,
                    timeLabel: '09:00',
                    avatar: const _ReconciliationAssistantAvatar(size: 45),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ChatTextBubble(
                          text: '今日对账信息已生成，请核对下面的对账卡片并完成确认。',
                          mine: false,
                          enableSelection: false,
                        ),
                        const SizedBox(height: 8),
                        _ReconciliationMessageCard(
                          confirmed: _confirmed,
                          onTap: () => setState(() => _showDetails = true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '点击名片查看明细、评价与确认状态',
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对账助手'),
        content: const Text('每天由对账助手推送一份对账信息，参与人可以留下意见并确认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailScaffold() {
    final progress = _confirmed ? 1.0 : 2 / 3;
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        backgroundColor: DunesColors.bgApp,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: '返回对账消息',
          onPressed: () => setState(() => _showDetails = false),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B6FC4), Color(0xFF7652B8)],
                ),
              ),
              child: const Icon(
                Icons.sync_alt_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '对账助手',
              style: DunesTypography.sans(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '说明',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('对账助手'),
                content: const Text('每天由对账助手推送一份对账信息，参与人可以留下意见并确认。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.help_outline_rounded, size: 21),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 14),
            _buildSectionTitle('本次对账', '示例数据 · 2026年8月1日'),
            const SizedBox(height: 8),
            _buildSummaryCard(),
            const SizedBox(height: 18),
            _buildSectionTitle('确认进度', _confirmed ? '3/3 人已确认' : '2/3 人已确认'),
            const SizedBox(height: 8),
            _buildProgressCard(progress),
            const SizedBox(height: 18),
            _buildSectionTitle('本次评价', '所有参与人可见'),
            const SizedBox(height: 8),
            _buildReviewCard(),
            const SizedBox(height: 18),
            _buildCommentCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F5D62), Color(0xFF477E79)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x182F5D62),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日对账 · 7月结算',
                  style: DunesTypography.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _confirmed ? '你已完成确认' : '请核对信息并留下你的意见',
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(
            label: _confirmed ? '已确认' : '待确认',
            color: _confirmed ? const Color(0xFFD7F3E1) : Colors.white,
            textColor: _confirmed
                ? const Color(0xFF267449)
                : DunesColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String trailing) {
    return Row(
      children: [
        Text(
          title,
          style: DunesTypography.sans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: DunesColors.text,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: DunesTypography.sans(fontSize: 11.5, color: DunesColors.text3),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return _CardSurface(
      child: Column(
        children: [
          const _InfoLine(label: '对账周期', value: '2026.07.01 — 2026.07.31'),
          const Divider(height: 20, color: DunesColors.borderSoft),
          Row(
            children: [
              const Expanded(
                child: _AmountCell(label: '应收合计', value: '¥128,640.00'),
              ),
              Container(width: 1, height: 40, color: DunesColors.borderSoft),
              const Expanded(
                child: _AmountCell(label: '已核销', value: '¥128,640.00'),
              ),
              Container(width: 1, height: 40, color: DunesColors.borderSoft),
              const Expanded(
                child: _AmountCell(
                  label: '差异',
                  value: '¥0.00',
                  valueColor: DunesColors.green,
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: DunesColors.borderSoft),
          const _InfoLine(label: '附件', value: '3 份对账单 · 点击查看'),
        ],
      ),
    );
  }

  Widget _buildProgressCard(double progress) {
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '参与人确认状态',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: DunesTypography.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: DunesColors.accentSoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                DunesColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _confirmed ? '全部参与人已完成本次确认' : '还有 1 位参与人待确认',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard() {
    return _CardSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _ReviewRow(
            initial: '张',
            name: '张莉',
            role: '财务核对人',
            comment: '金额与发票明细一致，可以确认。',
            status: '已确认',
            statusColor: DunesColors.green,
            avatarColor: Color(0xFFE7DFF5),
            avatarTextColor: DunesColors.brandPurpleDeep,
          ),
          const Divider(height: 1, indent: 68, color: DunesColors.borderSoft),
          const _ReviewRow(
            initial: '李',
            name: '李明',
            role: '业务负责人',
            comment: '请关注 7 月 31 日的差旅费用。',
            status: '待确认',
            statusColor: DunesColors.amber,
            avatarColor: Color(0xFFDCEBEA),
            avatarTextColor: DunesColors.accent,
          ),
          const Divider(height: 1, indent: 68, color: DunesColors.borderSoft),
          _ReviewRow(
            initial: '我',
            name: '我',
            role: '当前核对人',
            comment: _commentController.text.trim().isEmpty
                ? '等待你填写意见'
                : _commentController.text.trim(),
            status: _confirmed ? '已确认' : '待确认',
            statusColor: _confirmed ? DunesColors.green : DunesColors.amber,
            avatarColor: const Color(0xFFD7E8E6),
            avatarTextColor: DunesColors.accent,
            isSelf: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCommentCard() {
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '我的评价',
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '所有参与人可见',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            enabled: !_confirmed,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text),
            decoration: InputDecoration(
              hintText: '输入本次对账意见（可选）',
              hintStyle: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
              filled: true,
              fillColor: DunesColors.bgSoft,
              contentPadding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DunesColors.accentLine),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _confirmed ? null : _confirm,
              icon: Icon(
                _confirmed ? Icons.check_circle_outline : Icons.check_rounded,
                size: 19,
              ),
              label: Text(_confirmed ? '已确认本次对账' : '确认本次对账'),
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.accent,
                disabledBackgroundColor: DunesColors.greenSoft,
                disabledForegroundColor: DunesColors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconciliationAssistantAvatar extends StatelessWidget {
  const _ReconciliationAssistantAvatar({this.size = 45});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B6FC4), Color(0xFF7652B8)],
        ),
      ),
      child: Icon(
        Icons.sync_alt_rounded,
        color: Colors.white,
        size: size * .44,
      ),
    );
  }
}

class _ReconciliationMessageCard extends StatelessWidget {
  const _ReconciliationMessageCard({
    required this.confirmed,
    required this.onTap,
  });

  final bool confirmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3F1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFC9DFDA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.compare_arrows_rounded,
                    size: 19,
                    color: DunesColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '今日对账 · 7月结算',
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  _StatusPill(
                    label: confirmed ? '已确认' : '待确认',
                    color: confirmed
                        ? const Color(0xFFD7F3E1)
                        : const Color(0xFFFFF3DC),
                    textColor: confirmed
                        ? const Color(0xFF267449)
                        : DunesColors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '2026.07.01 — 2026.07.31 · 3 位参与人',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '差异 ¥0.00',
                    style: DunesTypography.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.green,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '查看详情',
                    style: DunesTypography.sans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: DunesColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.child,
    this.padding = const EdgeInsets.all(15),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
        ),
        const Spacer(),
        Text(
          value,
          style: DunesTypography.sans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: DunesColors.text,
          ),
        ),
      ],
    );
  }
}

class _AmountCell extends StatelessWidget {
  const _AmountCell({
    required this.label,
    required this.value,
    this.valueColor = DunesColors.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: DunesTypography.mono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.initial,
    required this.name,
    required this.role,
    required this.comment,
    required this.status,
    required this.statusColor,
    required this.avatarColor,
    required this.avatarTextColor,
    this.isSelf = false,
  });

  final String initial;
  final String name;
  final String role;
  final String comment;
  final String status;
  final Color statusColor;
  final Color avatarColor;
  final Color avatarTextColor;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: avatarColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: avatarTextColor,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 5),
                      Text(
                        '本人',
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: DunesColors.accent,
                        ),
                      ),
                    ],
                    const Spacer(),
                    _StatusPill(
                      label: status,
                      color: statusColor.withValues(alpha: 0.12),
                      textColor: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  role,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  comment,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: isSelf && comment == '等待你填写意见'
                        ? DunesColors.text3
                        : DunesColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
