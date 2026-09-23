import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/group_type_picker.dart';
import 'reply_sla_models.dart';

/// 工作群已读不回：不连接口的补丁演示（禁打扰 / 禁退 / @所有人名单 / 去回复上级）。
class ReplySlaGalleryPage extends StatefulWidget {
  const ReplySlaGalleryPage({super.key});

  @override
  State<ReplySlaGalleryPage> createState() => _ReplySlaGalleryPageState();
}

class _ReplySlaGalleryPageState extends State<ReplySlaGalleryPage> {

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
      unreadSeconds: status == ReplySlaStatus.unread ? seconds : 0,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgPage,
      appBar: AppBar(
        title: const Text('工作群已读不回 · 补丁演示'),
        backgroundColor: DunesColors.bgApp,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '只出现在上线后新建的工作群。点「回复此条」不算回复，发出引用才算。「去回复上级」只定位。',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2, height: 1.45),
          ),
          const SizedBox(height: 16),
          _section('群资料', '新工作群：免打扰不可开，未解散不能主动退'),
          _settingsMock(),
          const SizedBox(height: 18),
          _section('去回复上级', '义务被新消息冲走后，输入框上方出现定位钮，不发送、不关义务'),
          _jumpMock(),
          const SizedBox(height: 18),
          _section('@所有人 · 发送人', '3 人及以内逐行列；超过 3 人点摘要看名单。接收人只看自己。'),
          _bubble(
            mine: true,
            name: '我',
            text: '@所有人 今晚 8 点前回复本周进度',
            extra: _atAllLines(),
          ),
          _bubble(
            mine: true,
            name: '我',
            text: '@所有人 人多时不铺名单',
            extra: _atAllSummary(),
          ),
          const SizedBox(height: 18),
          _section('被 @ 的人', '有按钮；回了或失效后按钮消失'),
          _bubble(
            mine: false,
            name: '直属上级',
            text: '@我 这份对账今天下班前给一下',
            item: _item(id: 1, status: ReplySlaStatus.unread, seconds: 25 * 60, receiver: true),
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
            item: _item(id: 7, status: ReplySlaStatus.unread, seconds: 25 * 60, receiver: false),
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
          _section('不算、不出现', '同事互 @、普通群 / 旧群：气泡下什么都没有。@所有人只落在发送人的下级上。'),
          _bubble(mine: false, name: '同事', text: '@我 同事互 @ · 不产生义务'),
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
    Widget? extra,
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
                if (extra != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: extra),
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
    final unreadDur = formatReplySlaDuration(item.liveUnread(now));
    final text = switch (item.status) {
      ReplySlaStatus.unread => '未读 $unreadDur',
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

  Widget _settingsMock() {
    TextStyle sub = DunesTypography.sans(fontSize: 14, color: const Color(0xFF888888));
    return Container(
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        border: Border.all(color: DunesColors.borderSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: const Text('消息免打扰'),
            trailing: Text('工作群不可开启', style: sub),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: const Text('置顶聊天'),
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Text(
              '工作群不能主动退出，群主解散后可退出。',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(fontSize: 12, color: const Color(0xFF888888)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jumpMock() {
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        border: Border.all(color: DunesColors.borderSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            bottom: 48,
            child: Text(
              '林先敏：那我先下班了…\n上级：最新消息把上面那条冲走了。',
              style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2, height: 1.45),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD4380D),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '↑ 去回复上级',
                style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _atAllLines() {
    final style = DunesTypography.mono(fontSize: 10.5, fontWeight: FontWeight.w500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('@王奕凡 未读 25m', style: style.copyWith(color: DunesColors.text3)),
        Text('@李四 已读 · 未回复 40m', style: style.copyWith(color: const Color(0xFFD4380D))),
        Text('@王五 已回复 · 用时 8m', style: style.copyWith(color: DunesColors.readReceipt)),
      ],
    );
  }

  Widget _atAllSummary() {
    return InkWell(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('2人未回 · 3人已读未回 · 1人已回 · 1人已失效',
                      style: DunesTypography.sans(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _rosterRow('王奕凡', '未读 25m', DunesColors.text3),
                  _rosterRow('周可', '未读 1h', DunesColors.text3),
                  _rosterRow('李四', '已读 · 未回复 40m', const Color(0xFFD4380D)),
                  _rosterRow('陈六', '已读 · 未回复 1h20m', const Color(0xFFD4380D)),
                  _rosterRow('赵七', '已读 · 未回复 2h', const Color(0xFFD4380D)),
                  _rosterRow('王五', '已回复 · 用时 8m', DunesColors.readReceipt),
                  _rosterRow('钱八', '已失效', DunesColors.text3),
                ],
              ),
            ),
          ),
        );
      },
      child: Text(
        '2人未回 · 3人已读未回 · 1人已回 · 1人已失效',
        style: DunesTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFD4380D),
        ),
      ),
    );
  }

  Widget _rosterRow(String name, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(name, style: DunesTypography.sans(fontSize: 14))),
          Text(status, style: DunesTypography.mono(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
