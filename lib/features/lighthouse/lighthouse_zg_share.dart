import 'package:flutter/material.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'lighthouse_shared_card_data.dart';
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 资管 · 转发到 IM 的卡片（kind = 'zg'，2026-11-05）
//
//   跟灯塔转发同一条通路（LighthouseShareableCard → 结构化 TEXT payload），只是卡片是静态的：
//   一个主数 + 几格指标 + 几行明细，全是转发那一刻已经格式化好的字符串，不带原始金额、不回源拉数，
//   接收人看到的就是发送人当时看到的口径。老版本不认识 'zg'，只显示 fallbackText 那段文字。
// ═════════════════════════════════════════════════════════════════════════════

/// 一格：标签、值、单位、色调（in / out / neg / warn / 空）、角标。
Map<String, dynamic> lhZgCell(String label, String value, {String unit = '万', String tone = '', String? badge}) => {
  'l': label,
  'v': value,
  'u': unit,
  't': tone,
  if (badge != null) 'b': badge,
};

/// 组一张资管卡片的数据。
LighthouseSharedCardData lhZgShareData({
  required String module,
  required String title,
  required String range,
  required Map<String, dynamic> head,
  List<Map<String, dynamic>> cells = const [],
  List<Map<String, dynamic>> lines = const [],
  String? linesTitle,
  String? note,
}) => LighthouseSharedCardData.create({
  'kind': 'zg',
  'module': module,
  'title': title,
  'range': range,
  'period': 'month',
  'head': head,
  'cells': cells.take(8).toList(),
  'lines': lines.take(8).toList(),
  if (linesTitle != null) 'linesTitle': linesTitle,
  if (note != null) 'note': note,
  'capturedAt': DateTime.now().toIso8601String(),
});

Color _tone(BuildContext context, String? t) => DunesColors.resolve(
  context,
  switch (t) {
    'in' => const Color(0xFF6A4FC9),
    'out' => const Color(0xFFC9762B),
    'neg' => LhColors.neg,
    'warn' => const Color(0xFFA85A1E),
    'fin' => const Color(0xFF2F6EA8),
    _ => const Color(0xFF2B2147),
  },
);

const _kIcons = <String, IconData>{
  'business_finance': Icons.view_column_outlined,
  'bills': Icons.swap_horiz_rounded,
  'fund_plan': Icons.event_note_outlined,
  'fund_flow': Icons.waves_rounded,
  'fund_transfer': Icons.swap_calls_rounded,
};

/// 接收端 / 转发预览里的卡片：版式照资管板块卡（标题 + 主数 + 两列指标格 + 明细行）。
class LhZgSharedCardView extends StatelessWidget {
  const LhZgSharedCardView({super.key, required this.data});

  final LighthouseSharedCardData data;

  @override
  Widget build(BuildContext context) {
    final head = data.zgHead;
    final cells = data.zgCells;
    final lines = data.zgLines;
    Color c(Color x) => DunesColors.resolve(context, x);
    Widget amount(Map<String, String> m, double size) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: m['v'] ?? '—',
            style: LhTypography.number(context: context, size: size, color: _tone(context, m['t'])).copyWith(height: 1.0),
          ),
          if ((m['u'] ?? '').isNotEmpty && (m['v'] ?? '—') != '—')
            TextSpan(
              text: m['u'],
              style: LhTypography.sans(context: context, size: size * 0.42, weight: FontWeight.w500, color: c(const Color(0xFF94938A)), height: 1.0),
            ),
        ],
      ),
      maxLines: 1,
    );
    Widget cell(Map<String, String> m) => Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 9, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m['l'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(context: context, size: 11, weight: FontWeight.w700, color: c(const Color(0xFF5A5C56)), height: 1.0),
                ),
              ),
              if ((m['b'] ?? '').isNotEmpty)
                Text(m['b']!, style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w600, color: _tone(context, m['t']))),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: amount(m, 16)),
        ],
      ),
    );
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cell(cells[i])),
              Container(width: 0.6, color: c(const Color(0xFFECE8F3))),
              Expanded(child: i + 1 < cells.length ? cell(cells[i + 1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      );
      if (i + 2 < cells.length) rows.add(Container(height: 0.6, margin: const EdgeInsets.symmetric(horizontal: 8), color: c(const Color(0xFFECE8F3))));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: c(const Color(0xFF7B5CD8)), borderRadius: BorderRadius.circular(7)),
                child: Icon(_kIcons[data.zgModule] ?? Icons.account_balance_wallet_outlined, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '资管 · ${data.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(context: context, size: 15, weight: FontWeight.w700, color: c(const Color(0xFF2B2147))),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: c(const Color(0xFFF0ECF6)), borderRadius: BorderRadius.circular(6)),
                child: Text(data.range, style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: c(const Color(0xFF5A458F)))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(head['l'] ?? '', style: LhTypography.sans(context: context, size: 12, color: c(const Color(0xFF5A5C56)))),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: amount(head, 30))),
              if ((head['b'] ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(head['b']!, style: LhTypography.sans(context: context, size: 12, weight: FontWeight.w600, color: c(const Color(0xFF5A458F)))),
                ),
              ],
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: c(const Color(0xFFF7F6FA)), borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            ),
          ],
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (data.zgLinesTitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  data.zgLinesTitle!,
                  style: LhTypography.sans(context: context, size: 11, weight: FontWeight.w700, color: c(const Color(0xFF5A458F))),
                ),
              ),
            for (var i = 0; i < lines.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: c(const Color(0xFFECE8F3)), width: 0.6)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: c(const Color(0xFFF0ECF6)), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: LhTypography.mono(context: context, size: 9.5, weight: FontWeight.w600, color: c(const Color(0xFF5A458F))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lines[i]['l'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LhTypography.sans(context: context, size: 12.5, weight: FontWeight.w600, color: c(const Color(0xFF2B2147))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    amount(lines[i], 13),
                  ],
                ),
              ),
          ],
          if ((data.zgNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(data.zgNote!, style: LhTypography.sans(context: context, size: 10.5, color: c(const Color(0xFF94938A)), height: 1.4)),
          ],
          if (data.capturedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              '截至 ${data.capturedAt!.month}.${data.capturedAt!.day.toString().padLeft(2, '0')} '
              '${data.capturedAt!.hour.toString().padLeft(2, '0')}:${data.capturedAt!.minute.toString().padLeft(2, '0')} · 转发时的口径',
              style: LhTypography.mono(context: context, size: 9.5, color: c(const Color(0xFF94938A))),
            ),
          ],
        ],
      ),
    );
  }
}
