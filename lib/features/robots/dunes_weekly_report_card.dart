import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'robot_markdown.dart';
import 'robot_models.dart';

typedef _Kpi = ({
  String label,
  String value,
  String note,
  Color ink,
  Color fill,
  IconData? icon,
});
typedef _ChartRow = ({String label, double value, String detail});

class DunesWeeklyReportCard extends StatelessWidget {
  const DunesWeeklyReportCard({
    super.key,
    required this.markdown,
    this.onForward,
    this.forwardBusy = false,
    this.deliveryLabel,
    this.scheduledDelivery = false,
  }) : _readingMode = false;

  const DunesWeeklyReportCard._reading({required this.markdown})
    : _readingMode = true,
      onForward = null,
      forwardBusy = false,
      deliveryLabel = null,
      scheduledDelivery = false;

  final String markdown;
  final VoidCallback? onForward;
  final bool forwardBusy;
  final String? deliveryLabel;
  final bool scheduledDelivery;
  final bool _readingMode;

  static const _ink = Color(0xFF15153E);
  static const _purple = Color(0xFF3B10B9);
  static const _rule = Color(0xFFDED9F2);
  static const _track = Color(0xFFE3E3F2);
  static const _palette = [
    Color(0xFF00B59E),
    Color(0xFF3594FB),
    Color(0xFF6958DC),
    Color(0xFFFFB60B),
  ];
  static const _coral = Color(0xFFFF726D);
  static const _tealInk = Color(0xFF00685D);
  static const _redInk = Color(0xFFF14545);
  static const _blueInk = Color(0xFF0067DF);
  static const _goldInk = Color(0xFFDE8800);
  static const _tealFill = Color(0xFFDDF6F1);
  static const _redFill = Color(0xFFFDE7E7);
  static const _blueFill = Color(0xFFE2EEFF);
  static const _goldFill = Color(0xFFFCF3E2);
  static const _purpleFill = Color(0xFFE7E1FB);

  Color _surface(BuildContext context, Color color) =>
      DunesColors.resolve(context, color, role: DunesColorRole.surface);

  Color _line(BuildContext context) =>
      DunesColors.resolve(context, _rule, role: DunesColorRole.border);

  TextStyle _style(
    BuildContext context,
    double size, {
    Color color = _ink,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    color: DunesColors.resolve(context, color),
    fontSize: _readingMode && size <= 13 ? size + 2 : size,
    fontWeight: weight,
    height: 1.15,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static final _amount = RegExp(r'^([+-]?)([0-9]+)(?:\.([0-9]+))? 万元$');
  String _money(String text, {bool positiveSign = false}) {
    final match = _amount.firstMatch(text.trim());
    if (match == null) return text;
    final whole = match.group(2)!;
    final fraction = (match.group(3) ?? '').replaceFirst(RegExp(r'0+$'), '');
    final digits = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    final sign = match.group(1)!;
    final plus =
        positiveSign &&
        sign.isEmpty &&
        (int.tryParse(whole) != 0 || fraction.isNotEmpty);
    return '${plus ? '+' : sign}$digits${fraction.isEmpty ? '' : '.$fraction'}万';
  }

  static final _heading = RegExp(r'\n\s*## ');
  static final _finance = RegExp(
    r'^流入 \*\*([^*]+)\*\*\s+流出 \*\*([^*]+)\*\*\s+净流入 \*\*([^*]+)\*\*',
  );
  static final _province = RegExp(r'^- (.+) \*\*(-?\d+(?:\.\d+)?) 万元\*\*$');
  static final _product = RegExp(
    r'^- (.+) (\d+) 笔 · \*\*(\d+(?:\.\d+)?) 万元\*\*$',
  );
  static final _operation = RegExp(r'^- (销售额|核销额|利润) \*\*([^*]+)\*\*(.*)$');
  static final _plan = RegExp(r'^- (回款|付款) \*\*([^*]+)\*\* · (-?\d+)%$');
  static final _cost = RegExp(
    r'^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|\s*(\d+(?:\.\d+)?) 万元\s*\|$',
  );

  static const _icons = {
    '灯塔资管': Icons.storage_rounded,
    '实际经营': Icons.bar_chart_rounded,
    '提案进展': Icons.description_outlined,
    '对账进展': Icons.fact_check_outlined,
    '成本审批': Icons.account_balance_wallet_outlined,
    '部门一览': Icons.groups_outlined,
    '会议纪要': Icons.calendar_today_outlined,
    '差旅': Icons.flight_takeoff_rounded,
  };
  static final _proposalTotals = RegExp(
    r'^新建 \*\*([^*]+)\*\*\s+通过／完成 \*\*([^*]+)\*\*\s+当前审批中 \*\*([^*]+)\*\*$',
  );
  static final _annualScale = RegExp(r'^预计年化总规模 \*\*([^*]+)\*\* · (.+)$');

  @override
  Widget build(BuildContext context) {
    final sections = markdown.trim().split(_heading);
    final header = sections.first.split('\n');
    final purple = DunesColors.resolve(context, _purple);
    final surface = _surface(context, const Color(0xFFFAF9FF));
    final line = _line(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deliveryLabel case final time? when time.isNotEmpty)
          Center(
            child: Tooltip(
              message: scheduledDelivery
                  ? '北京时间${RobotCatalog.weeklyReport.desc} · 实际收到 $time'
                  : '实际收到 $time',
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _surface(context, const Color(0xFFDEDAF6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  scheduledDelivery ? RobotCatalog.weeklyReportSchedule : time,
                  style: _style(context, 11),
                ),
              ),
            ),
          ),
        Material(
          color: surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 10, _readingMode ? 10 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.bar_chart_rounded,
                        color: purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            header.first.replaceFirst(RegExp(r'^#\s+'), ''),
                            style: _style(context, 18, weight: FontWeight.w900),
                          ),
                          if (header.length > 1)
                            Text(
                              _reportPeriod(header.skip(1).join(' ').trim()),
                              style: _style(context, 10),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '数据明细与口径',
                      onPressed: () => _showDetails(context),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: purple.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
                for (final section in sections.skip(1)) ...[
                  const SizedBox(height: 5),
                  Divider(height: 1, color: line),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _icons[section.split('\n').first] ??
                            Icons.insights_outlined,
                        size: 17,
                        color: purple,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          section.split('\n').first,
                          style: _style(context, 13, weight: FontWeight.w800),
                        ),
                      ),
                      if (section.startsWith('实际经营\n') &&
                          section.contains('销售额 **'))
                        Flexible(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _surface(context, _purpleFill),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(
                                '实际周度经营数据',
                                textAlign: TextAlign.center,
                                style: _style(context, 9),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _sectionBody(context, section),
                ],
                if (onForward != null) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: line),
                  Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: purple,
                        minimumSize: const Size(74, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: forwardBusy ? null : onForward,
                      icon: const Icon(
                        Icons.reply_rounded,
                        size: 20,
                        textDirection: TextDirection.rtl,
                      ),
                      label: const Text(
                        '转发',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _reportPeriod(String period) => period.replaceFirstMapped(
    RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})\s*–\s*(?:(\d{4})\.)?(\d{2})\.(\d{2})'),
    (date) {
      final firstMonth = int.parse(date[2]!);
      final lastMonth = int.parse(date[5]!);
      final firstDay = int.parse(date[3]!);
      final lastDay = int.parse(date[6]!);
      final crossYear =
          lastMonth < firstMonth || date[4] != null && date[4] != date[1];
      return '${crossYear ? '${date[1]}年' : ''}$firstMonth月$firstDay日–'
          '${crossYear ? '${date[4] ?? (int.parse(date[1]!) + 1)}年' : ''}'
          '${firstMonth == lastMonth && !crossYear ? '' : '$lastMonth月'}$lastDay日';
    },
  );

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据明细与口径'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: RobotMarkdown(markdown: markdown),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _sectionBody(BuildContext context, String section) {
    final divider = section.indexOf('\n');
    if (divider < 0) return const SizedBox.shrink();
    final title = section.substring(0, divider).trim();
    final lines = section.substring(divider + 1).trim().split('\n');
    final displayed = lines.where((line) => !line.startsWith('数据来源：')).toList();
    return switch (title) {
      '灯塔资管' => _financeSection(context, displayed),
      '实际经营' => _operationsSection(context, displayed),
      '提案进展' => _proposalsSection(context, displayed),
      '成本审批' => _costSection(context, displayed),
      '会议纪要' => _meetingsSection(context, displayed),
      '差旅' => _travelSection(context, displayed),
      '部门一览' => _markdown(
        context,
        displayed.where((line) => !line.startsWith('提案按主责人')).join('\n'),
        compact: true,
      ),
      _ => _markdown(context, displayed.join('\n')),
    };
  }

  static final _receivables = RegExp(
    r'^渠道应收 \*\*([^*]+)\*\*，其中逾期 \*\*([^*]+)／(\d+) 张\*\*',
  );
  static final _delta = RegExp(r'周环比 ([+-]?\d+(?:\.\d+)?)%');
  static final _reviewTitle = RegExp(r'^\*\*待复核节点\*\* · 超时提案 (\d+) 笔$');
  static final _count = RegExp(r'^- (.+) (\d+) 笔$');
  static final _costTotal = RegExp(
    r'^通过 \*\*(\d+) 笔\*\*\s+归集获批金额 \*\*([^*]+)\*\*',
  );
  static final _meetingTotal = RegExp(
    r'^录入 \*\*(\d+) 场\*\*\s+已生成 \*\*(\d+) 份\*\*',
  );
  static final _meetingCoverage = RegExp(r'^纪要覆盖率 \*\*(\d+%)\*\*');
  static final _travelTotal = RegExp(
    r'^已入库费用 \*\*([^*]+)\*\*\s+\*\*(\d+) 人\*\*\s+\*\*(\d+) 个省级地区\*\*',
  );

  String _planAmounts(String value) {
    final amounts = value.replaceFirst(RegExp(r' 万元$'), '').split('／');
    if (amounts.length != 2) return value;
    final actual = _money('${amounts[0]} 万元').replaceFirst(RegExp(r'万$'), '');
    return '$actual / ${_money('${amounts[1]} 万元')}';
  }

  Widget _financeSection(BuildContext context, List<String> lines) {
    final cash = lines.isEmpty ? null : _finance.firstMatch(lines.first);
    final receivables = lines
        .map(_receivables.firstMatch)
        .whereType<RegExpMatch>()
        .firstOrNull;
    final plan = lines.map(_plan.firstMatch).whereType<RegExpMatch>().toList();
    return _stack([
      if (cash != null)
        _tiles(context, [
          _tile(
            '流入',
            _money(cash.group(1)!),
            _tealInk,
            _tealFill,
            icon: Icons.arrow_downward_rounded,
          ),
          _tile(
            '流出',
            _money(cash.group(2)!),
            _redInk,
            _redFill,
            icon: Icons.arrow_upward_rounded,
          ),
          _tile(
            '净流入',
            _money(cash.group(3)!, positiveSign: true),
            _purple,
            _purpleFill,
            icon: Icons.balance_rounded,
          ),
        ]),
      if (receivables != null)
        Text(
          '渠道应收 ${_money(receivables.group(1)!)} · 逾期 ${_money(receivables.group(2)!)}／${receivables.group(3)}张',
          style: _style(context, 10.5),
        ),
      _markdown(
        context,
        (cash == null ? lines : lines.skip(1))
            .where(
              (line) =>
                  !_receivables.hasMatch(line) &&
                  !(cash != null &&
                      line.startsWith('- ') &&
                      line.contains('净额 ')) &&
                  (plan.isEmpty ||
                      (!_plan.hasMatch(line) && line != '**资金计划执行**')),
            )
            .join('\n'),
      ),
      if (plan.isNotEmpty) ...[
        Divider(height: 1, color: _line(context)),
        Text('资金计划执行', style: _style(context, 11.5, weight: FontWeight.w800)),
        _bars(
          context,
          [
            for (final row in plan)
              (
                label: '${row[1]}  ${_planAmounts(row[2]!)}',
                value: double.parse(row[3]!),
                detail: '${row[3]}%',
              ),
          ],
          ceiling: 100,
          labelFlex: 5,
          trackFlex: 10,
        ),
      ],
    ]);
  }

  Widget _operationsSection(BuildContext context, List<String> lines) {
    final rows = lines
        .map(_operation.firstMatch)
        .whereType<RegExpMatch>()
        .toList();
    const tones = [
      (_tealInk, _tealFill),
      (_blueInk, _blueFill),
      (_goldInk, _goldFill),
    ];
    return _stack([
      if (rows.isNotEmpty)
        _tiles(context, [
          for (final row in rows)
            _tile(
              row[1]!,
              _money(row[2]!),
              tones[const ['销售额', '核销额', '利润'].indexOf(row[1]!)].$1,
              tones[const ['销售额', '核销额', '利润'].indexOf(row[1]!)].$2,
              note: row[3]!.replaceFirst(' · ', ''),
            ),
        ]),
      _markdown(
        context,
        lines.where((line) => !_operation.hasMatch(line)).join('\n'),
      ),
    ]);
  }

  Widget _proposalsSection(BuildContext context, List<String> lines) {
    final totals = lines.isEmpty
        ? null
        : _proposalTotals.firstMatch(lines.first);
    final scaleIndex = lines.indexWhere(_annualScale.hasMatch);
    final scale = scaleIndex < 0
        ? null
        : _annualScale.firstMatch(lines[scaleIndex]);
    final saleIndex = lines.indexWhere((line) => line.startsWith('**销售提案'));
    final reviewIndex = lines.indexWhere(_reviewTitle.hasMatch);
    final extrasStart = scaleIndex >= 0 ? scaleIndex + 1 : saleIndex + 1;
    final mainEnd = saleIndex >= 0
        ? saleIndex
        : scaleIndex >= 0
        ? scaleIndex
        : reviewIndex >= 0
        ? reviewIndex
        : lines.length;
    final hasSales = saleIndex >= 0 || scale != null;
    final summaryStart = totals == null ? 0 : 1;
    return _stack([
      if (totals != null)
        _tiles(context, [
          _tile(
            '新建',
            totals[1]!.replaceFirst(' 笔', ''),
            _tealInk,
            _tealFill,
            icon: Icons.list_alt_outlined,
          ),
          _tile(
            '通过／完成',
            totals[2]!.replaceFirst(' 笔', ''),
            _blueInk,
            _blueFill,
            icon: Icons.check_rounded,
          ),
          _tile(
            '在审',
            totals[3]!.replaceFirst(' 笔', ''),
            _goldInk,
            _goldFill,
            icon: Icons.access_time_rounded,
          ),
        ]),
      _markdown(
        context,
        lines
            .skip(summaryStart)
            .take((mainEnd - summaryStart).clamp(0, lines.length))
            .join('\n'),
      ),
      if (hasSales)
        _salesPanel(
          context,
          saleIndex >= 0 ? lines[saleIndex].replaceAll('**', '') : '销售提案',
          scale,
          lines
              .skip(extrasStart)
              .map(_product.firstMatch)
              .whereType<RegExpMatch>()
              .toList(),
        ),
      if (hasSales || reviewIndex >= 0)
        _proposalDetails(
          context,
          lines
              .skip(hasSales ? extrasStart : reviewIndex)
              .where((line) => !_product.hasMatch(line))
              .toList(),
        ),
    ]);
  }

  Widget _salesPanel(
    BuildContext context,
    String heading,
    RegExpMatch? scale,
    List<RegExpMatch> products,
  ) => Container(
    decoration: BoxDecoration(
      color: _surface(context, const Color(0xFFF4F1FC)),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _line(context)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: _surface(context, _purpleFill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.sell_outlined,
                  size: 16,
                  color: DunesColors.resolve(context, _purple),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    heading,
                    style: _style(context, 13.5, weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (scale != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
            child: _stack([
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '预计年化总规模',
                      textAlign: TextAlign.center,
                      style: _style(context, 10),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _valueText(
                      context,
                      _money(scale[1]!),
                      18,
                      color: _purple,
                      weight: FontWeight.w900,
                      alignment: Alignment.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      scale[2]!.replaceFirst('覆盖 ', '规模覆盖\n'),
                      textAlign: TextAlign.center,
                      style: _style(context, 9.5),
                    ),
                  ),
                ],
              ),
              if (products.isNotEmpty)
                _bars(
                  context,
                  [
                    for (final row in products)
                      (
                        label:
                            '${row[1]}  ${row[2]}笔 · ${_money('${row[3]} 万元')}',
                        value: double.parse(row[3]!),
                        detail: '',
                      ),
                  ],
                  labelFlex: 7,
                  trackFlex: 10,
                ),
            ]),
          ),
      ],
    ),
  );

  Widget _proposalDetails(BuildContext context, List<String> lines) {
    final reviewIndex = lines.indexWhere(_reviewTitle.hasMatch);
    final beforeReview = reviewIndex < 0 ? lines : lines.take(reviewIndex);
    final notes = beforeReview.where((line) => line.trim().isNotEmpty).toList();
    final funding = notes
        .where(
          (line) => line.startsWith('能源资金提案') || line.startsWith('运营商资金提案'),
        )
        .toList();
    final purchaseIndex = notes.indexWhere((line) => line.startsWith('**采购完成'));
    final purchase = purchaseIndex < 0
        ? <String>[]
        : notes
              .skip(purchaseIndex + 1)
              .takeWhile(
                (line) => line.startsWith('涉及 ') || _count.hasMatch(line),
              )
              .toList();
    final review = reviewIndex < 0
        ? null
        : _reviewTitle.firstMatch(lines[reviewIndex]);
    final stages = reviewIndex < 0
        ? <RegExpMatch>[]
        : lines
              .skip(reviewIndex + 1)
              .takeWhile((line) => _count.hasMatch(line))
              .map((line) => _count.firstMatch(line)!)
              .toList();
    return _stack([
      if (funding.isNotEmpty)
        _detailRow(
          context,
          '资金',
          Icons.savings_outlined,
          _tealFill,
          funding.map(_fundingSummary).join(' · '),
        ),
      if (purchase.isNotEmpty)
        _detailRow(
          context,
          '采购',
          Icons.inventory_2_outlined,
          _purpleFill,
          purchase
              .map(
                (line) =>
                    line.replaceFirst(RegExp(r'^- '), '').replaceAll('**', ''),
              )
              .join(' · '),
        ),
      if (review != null) ...[
        Text('待复核节点', style: _style(context, 11.5, weight: FontWeight.w800)),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var i = 0; i < stages.length; i++)
              _labelChip(
                context,
                stages[i][1]!,
                stages[i][2]!,
                [_tealFill, _blueFill, _purpleFill][i % 3],
              ),
            _labelChip(context, '其中超时', review[1]!, _redFill),
          ],
        ),
      ],
    ]);
  }

  String _fundingSummary(String line) => line
      .split(' · 覆盖 ')
      .first
      .replaceFirst('资金提案 · ', '')
      .replaceFirstMapped(
        RegExp(r'\*\*([^*]+)\*\*'),
        (match) => _money(match[1]!),
      );

  Widget _detailRow(
    BuildContext context,
    String label,
    IconData icon,
    Color fill,
    String text,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: _surface(context, fill),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: DunesColors.resolve(context, _purple),
              ),
              const SizedBox(width: 4),
              Text(label, style: _style(context, 10, weight: FontWeight.w800)),
            ],
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: _style(context, 10))),
    ],
  );

  Widget _labelChip(
    BuildContext context,
    String label,
    String count,
    Color fill,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      color: _surface(context, fill),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  '),
            TextSpan(
              text: count,
              style: _style(
                context,
                12,
                color: fill == _redFill ? _redInk : _purple,
                weight: FontWeight.w800,
              ),
            ),
          ],
        ),
        style: _style(context, 10),
      ),
    ),
  );

  Widget _costSection(BuildContext context, List<String> lines) {
    final total = lines.isEmpty ? null : _costTotal.firstMatch(lines.first);
    final rows = lines.map(_cost.firstMatch).whereType<RegExpMatch>().toList();
    if (total == null || rows.isEmpty) {
      return _markdown(context, lines.join('\n'));
    }
    final values = rows.map((row) => double.parse(row[3]!)).toList();
    final colors = [_palette[0], _palette[1], const Color(0xFFFFC550), _coral];
    return _stack([
      _metricsText(context, [
        '通过 ',
        total[1]!,
        '笔  ·  获批 ',
        _money(total[2]!),
      ], align: TextAlign.left),
      if (values.any((v) => v > 0))
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 11,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++)
                  if (values[i] > 0)
                    Expanded(
                      flex: (values[i] * 100).round().clamp(1, 100000000),
                      child: ColoredBox(color: colors[i % colors.length]),
                    ),
              ],
            ),
          ),
        ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 9,
        runSpacing: 4,
        children: [
          for (var i = 0; i < rows.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: colors[i % colors.length]),
                const SizedBox(width: 4),
                Text(
                  '${rows[i][1]} ${_money('${rows[i][3]} 万元')}',
                  style: _style(context, 10),
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  Widget _meetingsSection(BuildContext context, List<String> lines) {
    final total = lines.isEmpty ? null : _meetingTotal.firstMatch(lines.first);
    if (total == null) return _markdown(context, lines.join('\n'));
    final coverage = lines
        .map(_meetingCoverage.firstMatch)
        .whereType<RegExpMatch>()
        .firstOrNull;
    return _stack([
      _band(
        context,
        _metricsText(context, [
          '',
          total[1]!,
          '场  ·  ',
          total[2]!,
          coverage == null ? '份' : '份  ·  覆盖率 ',
          if (coverage != null) coverage[1]!,
        ]),
      ),
      _markdown(
        context,
        lines
            .skip(1)
            .where((line) => !_meetingCoverage.hasMatch(line))
            .join('\n'),
        withCoverage: true,
      ),
    ]);
  }

  Widget _travelSection(BuildContext context, List<String> lines) {
    final total = lines.isEmpty ? null : _travelTotal.firstMatch(lines.first);
    final rows = [
      for (final row
          in lines.map(_province.firstMatch).whereType<RegExpMatch>())
        (
          label: row[1]!,
          value: double.parse(row[2]!),
          detail: _money('${row[2]} 万元'),
        ),
    ];
    return _stack([
      if (total != null)
        _band(
          context,
          _metricsText(context, [
            '',
            _money(total[1]!),
            '  ·  ',
            total[2]!,
            '人  ·  ',
            total[3]!,
            '个省级地区',
          ], align: TextAlign.left),
        )
      else if (lines.isNotEmpty)
        _band(context, _markdown(context, lines.first)),
      if (rows.isNotEmpty) _bars(context, rows, labelFlex: 2, trackFlex: 11),
    ]);
  }

  Widget _metricsText(
    BuildContext context,
    List<String> parts, {
    TextAlign align = TextAlign.center,
  }) => Text.rich(
    TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? _style(context, 14, color: _purple, weight: FontWeight.w900)
                : null,
          ),
      ],
    ),
    style: _style(context, 10.5, weight: FontWeight.w600),
    textAlign: align,
  );

  Widget _band(BuildContext context, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: _surface(context, const Color(0xFFEFEBFC)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: child,
    ),
  );

  Widget _markdown(
    BuildContext context,
    String text, {
    bool withCoverage = false,
    bool compact = false,
  }) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final lines = text.trim().split('\n');
    final start = lines.indexWhere((line) => line.startsWith('|'));
    if (start < 0 || start + 2 >= lines.length) {
      return RobotMarkdown(
        markdown: text.trim(),
        selectable: false,
        compact: !_readingMode,
      );
    }
    final table = lines
        .skip(start)
        .takeWhile((line) => line.startsWith('|'))
        .toList();
    if (table.any((row) => !row.endsWith('|')) ||
        table.length < 3 ||
        !RegExp(r'^\|[ |:-]+\|$').hasMatch(table[1])) {
      return RobotMarkdown(
        markdown: text.trim(),
        selectable: false,
        compact: !_readingMode,
      );
    }
    List<String> cells(String line) {
      final parts = line.split('|');
      return parts
          .sublist(1, parts.length - 1)
          .map((cell) => cell.trim())
          .toList();
    }

    final rows = [
      cells(table.first),
      for (final row in table.skip(2)) cells(row),
    ];
    if (rows.first.isEmpty ||
        rows.any((row) => row.length != rows.first.length)) {
      return RobotMarkdown(
        markdown: text.trim(),
        selectable: false,
        compact: !_readingMode,
      );
    }
    final before = lines.take(start).join('\n').trim();
    final after = lines.skip(start + table.length).join('\n').trim();
    return _stack([
      if (before.isNotEmpty)
        RobotMarkdown(
          markdown: before,
          selectable: false,
          compact: !_readingMode,
        ),
      _reportTable(
        context,
        rows.first.length,
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Table(
            border: TableBorder.all(color: _line(context)),
            columnWidths: withCoverage ? const {3: FlexColumnWidth(2)} : null,
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (var i = 0; i < rows.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: _surface(
                      context,
                      i == 0
                          ? const Color(0xFFE2DDF8)
                          : const Color(0xFFF6F4FC),
                    ),
                  ),
                  children: [
                    for (var j = 0; j < rows[i].length; j++)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: compact ? 0.75 : 1.5,
                        ),
                        child:
                            withCoverage &&
                                i > 0 &&
                                j == 3 &&
                                rows[i][j].endsWith('%')
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: _readingMode
                                        ? MediaQuery.textScalerOf(
                                            context,
                                          ).scale(38)
                                        : 30,
                                    child: Text(
                                      rows[i][j],
                                      textAlign: TextAlign.right,
                                      style: _style(
                                        context,
                                        10,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: _progress(
                                      context,
                                      (double.tryParse(
                                                rows[i][j].replaceFirst(
                                                  '%',
                                                  '',
                                                ),
                                              ) ??
                                              0) /
                                          100,
                                      _palette[0],
                                      height: 6,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                (i > 0
                                        ? _money(rows[i][j])
                                        : rows[i][j].replaceFirst(
                                            '当前审批中',
                                            '在审',
                                          ))
                                    .replaceAll('**', ''),
                                textAlign: TextAlign.center,
                                style: _style(
                                  context,
                                  compact ? 9 : 9.5,
                                  weight: i == 0
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      if (after.isNotEmpty)
        RobotMarkdown(
          markdown: after,
          selectable: false,
          compact: !_readingMode,
        ),
    ]);
  }

  Widget _reportTable(BuildContext context, int columns, Widget table) {
    if (!_readingMode) return table;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final minimum = columns * 76 * textScale;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minimum) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minimum, child: table),
        );
      },
    );
  }

  Widget _stack(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 4,
    children: [
      for (final child in children)
        if (child is! SizedBox || child.height != 0 || child.width != 0) child,
    ],
  );

  _Kpi _tile(
    String label,
    String value,
    Color ink,
    Color fill, {
    String note = '',
    IconData? icon,
  }) => (
    label: label,
    value: value,
    note: note,
    ink: ink,
    fill: fill,
    icon: icon,
  );

  Widget _valueText(
    BuildContext context,
    String value,
    double size, {
    Color color = _ink,
    FontWeight weight = FontWeight.w500,
    Alignment alignment = Alignment.centerLeft,
  }) => Align(
    alignment: alignment,
    child: Text(
      value,
      textAlign: alignment == Alignment.center
          ? TextAlign.center
          : TextAlign.start,
      style: _style(context, size, color: color, weight: weight),
    ),
  );

  Widget _tiles(BuildContext context, List<_Kpi> tiles) {
    const spacing = 6.0;
    final cards = [
      for (final tile in tiles)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _surface(context, tile.fill),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (tile.icon case final icon?) ...[
                          Icon(
                            icon,
                            size: 12,
                            color: DunesColors.resolve(context, tile.ink),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: _valueText(
                            context,
                            tile.label,
                            10,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    _valueText(
                      context,
                      tile.value,
                      16,
                      color: tile.ink,
                      weight: FontWeight.w900,
                    ),
                  ],
                ),
              ),
            ),
            if (tile.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    Text(tile.note, style: _style(context, 10)),
                    if (_delta.firstMatch(tile.note) case final delta?)
                      _progress(
                        context,
                        double.parse(delta[1]!).abs() / 10,
                        delta[1]!.startsWith('-') ? _coral : _palette[0],
                        height: 5,
                      ),
                  ],
                ),
              ),
          ],
        ),
    ];
    if (!_readingMode || cards.length < 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: spacing,
        children: [for (final card in cards) Expanded(child: card)],
      );
    }

    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var minimum = 112.0;
    for (final tile in tiles) {
      painter.text = TextSpan(
        text: tile.value,
        style: DefaultTextStyle.of(context).style.merge(
          _style(context, 16, color: tile.ink, weight: FontWeight.w900),
        ),
      );
      painter.layout();
      minimum = math.max(minimum, painter.width.ceilToDouble() + 18);
    }
    painter.dispose();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = ((available + spacing) / (minimum + spacing))
            .floor()
            .clamp(1, cards.length);
        final width = (available - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _progress(
    BuildContext context,
    double ratio,
    Color color, {
    double height = 7,
  }) => LinearProgressIndicator(
    value: ratio.clamp(0.0, 1.0).toDouble(),
    minHeight: height,
    borderRadius: BorderRadius.circular(5),
    backgroundColor: _surface(context, _track),
    color: color,
  );

  Widget _bars(
    BuildContext context,
    List<_ChartRow> rows, {
    double? ceiling,
    int labelFlex = 3,
    int trackFlex = 9,
  }) {
    final max =
        ceiling ??
        rows.fold<double>(0, (max, row) => row.value > max ? row.value : max);
    final showDetail = rows.any((row) => row.detail.isNotEmpty);
    return Column(
      spacing: 4,
      children: [
        for (var i = 0; i < rows.length; i++)
          Row(
            spacing: 6,
            children: [
              Expanded(
                flex: labelFlex,
                child: Text(
                  rows[i].label,
                  style: _style(context, 10, weight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: trackFlex,
                child: _progress(
                  context,
                  max > 0 ? rows[i].value / max : 0,
                  _palette[i % _palette.length],
                ),
              ),
              if (showDetail)
                Flexible(
                  flex: 2,
                  child: Text(
                    rows[i].detail,
                    textAlign: TextAlign.end,
                    style: _style(context, 10),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

bool isForwardedDunesWeeklyReport(Map<String, dynamic>? payload) =>
    payload?['robotKey'] == RobotCatalog.weeklyReportKey &&
    payload?['robotMarkdown'] == true &&
    payload?['forwardedFromRobot'] == true;

class DunesWeeklyReportShareTile extends StatelessWidget {
  const DunesWeeklyReportShareTile({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final lines = markdown.trim().split('\n');
    final period = lines.length > 1 && !lines[1].startsWith('#')
        ? DunesWeeklyReportCard._reportPeriod(lines[1].trim())
        : '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.bar_chart_rounded),
          title: const Text('沙丘经营周报'),
          subtitle: Text(period.isEmpty ? '查看周报' : period),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (context) => Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    tooltip: '关闭周报',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                body: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: DunesWeeklyReportCard._reading(
                          markdown: markdown,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
