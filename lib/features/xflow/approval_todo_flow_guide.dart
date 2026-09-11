import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 审批待办列表右上角「？」：通过后办理流程示意。
Future<void> showApprovalTodoFlowGuide(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: DunesColors.bgApp,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '通过后待办流程',
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: DunesColors.borderSoft),
              const Expanded(child: ApprovalTodoFlowGuide()),
            ],
          ),
        ),
      );
    },
  );
}

class ApprovalTodoFlowGuide extends StatelessWidget {
  const ApprovalTodoFlowGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        _loopGroup('付款 + 回票（行政/业务采购、合同付款、推广费、预付款、贷款付息还款）', [
          ['终审通过', '付款', '已付款', '先票后款：核验发票'],
          ['核验失败', '不重审', '发起人「补传发票」', '核验人再核验'],
          ['先款后票：补传发票 → 核验　·　到期未回票催办 → 无法收回'],
        ]),
        _loopGroup('仅付款（保证金、税费、招待费、差旅；携程差旅跳过付款）', [
          ['终审通过', '付款', '已付款'],
        ]),
        _loopGroup('用印（合同）', [
          ['终审通过', '盖章 · 朱虹旭', '填写快递单号', '确认签回', '确认归档'],
        ]),
        _loopGroup('客诉', [
          ['退券：作废券 → 付款 → 已付款 → 月度复核'],
          ['赔付：付款 → 已付款 → 月度复核'],
          ['补发：下发券码 → 月度复核'],
        ]),
        _loopGroup('一次性 / 到期', [
          ['开票 · 收据跟催 · 礼品备货 · 数据导出'],
          ['预付款到期还款 · 设备到期退还 · 开户归还证照'],
        ]),
        const SizedBox(height: 4),
        Text(
          '同一张单：先待审批，通过后进待办，办完才消失。无规则或未启用的模板，通过后与现在完全一样。',
          style: DunesTypography.sans(
            fontSize: 12,
            height: 1.55,
            color: DunesColors.text3,
          ),
        ),
      ],
    );
  }

  Widget _loopGroup(String title, List<List<String>> loops) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.accentDeep,
            ),
          ),
          const SizedBox(height: 8),
          for (final loop in loops)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < loop.length; i++) ...[
                    _loopChip(loop[i], highlight: i == 0),
                    if (i < loop.length - 1)
                      Text(
                        '→',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _loopChip(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? DunesColors.greenSoft : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? DunesColors.green : DunesColors.border,
        ),
      ),
      child: Text(
        text,
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text),
      ),
    );
  }
}
