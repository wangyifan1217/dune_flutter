import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/group_type_picker.dart';
import 'reply_sla_models.dart';

/// 工作群已读不回：不连接口的状态一览，给产品看四种状态和建群选择。
class ReplySlaGalleryPage extends StatelessWidget {
  const ReplySlaGalleryPage({super.key});

  static ReplySlaItem _item({
    required int id,
    required ReplySlaStatus status,
    required int seconds,
    required bool receiver,
    String name = '王奕凡',
  }) {
    return ReplySlaItem(
      messageId: id,
      senderUserId: 1,
      receiverUserId: 2,
      receiverName: name,
      isReceiver: receiver,
      status: status,
      unrepliedSeconds: seconds,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgPage,
      appBar: AppBar(
        title: const Text('工作群已读不回 · 状态一览'),
        backgroundColor: DunesColors.bgApp,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '只出现在上线后新建的工作群。点「回复此条」不算回复，发出引用才算。',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2, height: 1.45),
          ),
          const SizedBox(height: 16),
          _section('被 @ 的人', '有按钮；回了或失效后按钮消失'),
          _bubble(
            mine: false,
            name: '直属上级',
            text: '@我 这份对账今天下班前给一下',
            item: _item(id: 1, status: ReplySlaStatus.unread, seconds: 0, receiver: true),
          ),
          _bubble(
            mine: false,
            name: '直属上级',
            text: '@我 已读但还没回',
            item: _item(id: 2, status: ReplySlaStatus.pending, seconds: 40, receiver: true),
          ),
          _bubble(
            mine: false,
            name: '隔级上级',
            text: '@我 已读未回 1 小时 20 分',
            item: _item(id: 3, status: ReplySlaStatus.pending, seconds: 80 * 60, receiver: true),
          ),
          _bubble(
            mine: false,
            name: '总裁办',
            text: '@我 已用引用回复关掉义务',
            item: _item(id: 4, status: ReplySlaStatus.replied, seconds: 8 * 60, receiver: true),
          ),
          _bubble(
            mine: false,
            name: '直属上级',
            text: '@我 原消息撤回 / 离群 / 解散',
            item: _item(id: 5, status: ReplySlaStatus.voided, seconds: 2 * 3600, receiver: true),
          ),
          _bubble(
            mine: false,
            name: '直属上级',
            text: '@我 未读时群已解散',
            item: _item(id: 6, status: ReplySlaStatus.voided, seconds: 0, receiver: true),
            dissolved: true,
          ),
          const SizedBox(height: 18),
          _section('发送人', '没有按钮，只出 @姓名 + 状态'),
          _bubble(
            mine: true,
            name: '我',
            text: '@王奕凡 对方还没打开会话',
            item: _item(id: 7, status: ReplySlaStatus.unread, seconds: 0, receiver: false),
          ),
          _bubble(
            mine: true,
            name: '我',
            text: '@王奕凡 对方已读，还没引用回复',
            item: _item(id: 8, status: ReplySlaStatus.pending, seconds: 25 * 60, receiver: false),
          ),
          _bubble(
            mine: true,
            name: '我',
            text: '@王奕凡 对方已引用回复',
            item: _item(id: 9, status: ReplySlaStatus.replied, seconds: 12 * 60, receiver: false),
          ),
          _bubble(
            mine: true,
            name: '我',
            text: '@王奕凡 群已解散 / 对方离群 / 我撤回',
            item: _item(id: 10, status: ReplySlaStatus.voided, seconds: 36 * 60, receiver: false),
          ),
          const SizedBox(height: 18),
          _section('建群选择', '默认普通群，创建后不可改'),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DunesColors.brandPurple),
            onPressed: () => showCreateGroupTypeDialog(
              context,
              membersText: '将与 王奕凡、林先敏共 2 人创建群聊，是否继续？',
            ),
            child: const Text('打开建群类型弹窗'),
          ),
          const SizedBox(height: 18),
          _section('不算、不出现', '同事互 @、@所有人、普通群 / 旧群：气泡下什么都没有'),
          _bubble(mine: false, name: '同事', text: '@我 同事互 @ · 不产生义务'),
          _bubble(mine: false, name: '上级', text: '@所有人 整条跳过'),
          _bubble(mine: false, name: '上级 · 普通群', text: '@我 普通群没有标记'),
        ],
      ),
    );
  }

  Widget _section(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DunesTypography.sans(fontSize: 15, fontWeight: FontWeight.w600, color: DunesColors.text)),
          const SizedBox(height: 2),
          Text(hint, style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3)),
        ],
      ),
    );
  }

  Widget _bubble({
    required bool mine,
    required String name,
    required String text,
    ReplySlaItem? item,
    bool dissolved = false,
  }) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!mine) _avatar(name, mine),
          if (!mine) const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(name, style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: mine ? DunesColors.accentSoft : DunesColors.bgApp,
                    border: Border.all(color: DunesColors.borderSoft),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(mine ? 12 : 4),
                      topRight: Radius.circular(mine ? 4 : 12),
                      bottomLeft: const Radius.circular(12),
                      bottomRight: const Radius.circular(12),
                    ),
                  ),
                  child: Text(text, style: DunesTypography.sans(fontSize: 14, color: DunesColors.text, height: 1.45)),
                ),
                if (item != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _annotation(item, now, mine: mine, dissolved: dissolved),
                  ),
              ],
            ),
          ),
          if (mine) const SizedBox(width: 8),
          if (mine) _avatar(name, mine),
        ],
      ),
    );
  }

  Widget _avatar(String name, bool mine) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mine ? DunesColors.accentSoft : const Color(0xFFC9D6D4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name.substring(0, 1),
        style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600, color: DunesColors.accent),
      ),
    );
  }

  Widget _annotation(ReplySlaItem item, DateTime now, {required bool mine, required bool dissolved}) {
    final color = switch (item.status) {
      ReplySlaStatus.pending => const Color(0xFFD4380D),
      ReplySlaStatus.replied => DunesColors.readReceipt,
      ReplySlaStatus.unread || ReplySlaStatus.voided => DunesColors.text3,
    };
    final dur = formatReplySlaDuration(item.liveUnreplied(now));
    final text = switch (item.status) {
      ReplySlaStatus.unread => '未读',
      ReplySlaStatus.pending => '已读 · 未回复 $dur',
      ReplySlaStatus.replied => '已回复 · 用时 $dur',
      ReplySlaStatus.voided => item.unrepliedSeconds > 0 ? '已失效 · 未回复 $dur' : '已失效',
    };
    final style = DunesTypography.mono(fontSize: 10.5, fontWeight: FontWeight.w500, color: color);
    final label = mine ? '@${item.receiverName} $text' : text;
    final canReply = !mine && item.isReceiver && item.isOpen && !dissolved;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (canReply)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: DunesColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DunesColors.accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.reply_rounded, size: 13, color: DunesColors.accent),
                const SizedBox(width: 3),
                Text(
                  '回复此条',
                  style: DunesTypography.mono(fontSize: 11, fontWeight: FontWeight.w600, color: DunesColors.accent),
                ),
              ],
            ),
          ),
        Text(label, style: style),
      ],
    );
  }
}
