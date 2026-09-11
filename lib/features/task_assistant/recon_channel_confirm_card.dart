import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'recon_channel_confirm_preview.dart';

/// 对账人在任务助手里确认 / 提意见的渠道名片（图二格式）。
class ReconChannelConfirmCard extends StatefulWidget {
  const ReconChannelConfirmCard({super.key, required this.channel});

  final ReconChannelSnapshot channel;

  @override
  State<ReconChannelConfirmCard> createState() =>
      _ReconChannelConfirmCardState();
}

class _ReconChannelConfirmCardState extends State<ReconChannelConfirmCard> {
  bool _confirmed = false;
  String _comment = '';

  void _markConfirmed({String comment = ''}) {
    if (!mounted) return;
    setState(() {
      _confirmed = true;
      _comment = comment;
    });
    showDunesCenterToast(
      context,
      comment.trim().isEmpty ? '已确认「${widget.channel.channel}」' : '已提交意见并确认',
    );
  }

  Future<void> _requestConfirm() async {
    final ch = widget.channel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认对账'),
        content: Text(
          '确认「${ch.channel}」${ch.periodLabel}（${ch.settlementCycle}）'
          '的应收、实收数据无误？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.brandPurple,
            ),
            child: const Text('确认无误'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _markConfirmed();
  }

  Future<void> _commentAndConfirm() async {
    var draft = _comment;
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提意见'),
        content: SizedBox(
          width: 360,
          child: TextFormField(
            initialValue: draft,
            onChanged: (value) => draft = value,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '应收实收不一致、漏单、延期等到账，写在这里',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draft.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.brandPurple,
            ),
            child: const Text('提交并确认'),
          ),
        ],
      ),
    );
    if (next == null || !mounted) return;
    if (next.isEmpty) {
      showDunesCenterToast(context, '请填写意见');
      return;
    }
    _markConfirmed(comment: next);
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        width: 320,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${ch.channel}  ${ch.periodLabel}  ${ch.settlementCycle}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                _pill(
                  _confirmed ? '已确认' : '待确认',
                  _confirmed ? const Color(0xFF267449) : DunesColors.amber,
                  _confirmed
                      ? const Color(0xFFD7F3E1)
                      : const Color(0xFFFFF3DC),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (ch.isMonthly) ...[
              _moneyLine('${_monthLabel(ch)}应收', ch.monthReceivable),
              const SizedBox(height: 6),
              _moneyLine('${_monthLabel(ch)}实收', ch.monthReceived),
              const SizedBox(height: 6),
              _moneyLine(
                '差额',
                ch.monthReceivable - ch.monthReceived,
                highlight: ch.monthReceivable != ch.monthReceived,
              ),
            ] else ...[
              _moneyLine('应收金额', ch.receivableAmount, indent: 1),
              const SizedBox(height: 8),
              for (final line in ch.lines) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 2),
                  child: Text(
                    line.date,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text2,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 6),
                  child: Text(
                    '应收 ${formatReconChannelMoney(line.receivable)}    实收 ${formatReconChannelMoney(line.received)}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: line.receivable == line.received
                          ? DunesColors.text
                          : const Color(0xFFB07A2B),
                    ),
                  ),
                ),
              ],
              _moneyLine('${_monthLabel(ch)}累计应收', ch.monthReceivable),
              const SizedBox(height: 4),
              _moneyLine('${_monthLabel(ch)}累计实收', ch.monthReceived),
            ],
            if (_comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '意见：$_comment',
                style: const TextStyle(
                  fontSize: 12,
                  color: DunesColors.text2,
                  height: 1.4,
                ),
              ),
            ],
            if (!_confirmed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DunesColors.brandPurple,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _requestConfirm,
                    child: const Text('确认'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _commentAndConfirm,
                    child: const Text('提意见'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _monthLabel(ReconChannelSnapshot channel) {
    final value = DateTime.tryParse(channel.asOfDate);
    return value == null ? '本月' : '${value.month}月';
  }

  Widget _moneyLine(
    String label,
    num value, {
    int indent = 0,
    bool highlight = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent * 16.0),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: DunesColors.text2),
          ),
          const Spacer(),
          Text(
            formatReconChannelMoney(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: highlight ? DunesColors.amber : DunesColors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

class ReconChannelConfirmPack extends StatelessWidget {
  const ReconChannelConfirmPack({super.key, required this.channels});

  final List<ReconChannelSnapshot> channels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final channel in channels) ...[
          const SizedBox(height: 8),
          ReconChannelConfirmCard(
            key: ValueKey<String>(channel.id),
            channel: channel,
          ),
        ],
      ],
    );
  }
}
