import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'proposal_cost_estimate.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_ui.dart';

/// 提案详情顶部「年化测算」格子开关。关掉后页面与改动前完全一致。
const kProposalEstimateSummaryEnabled = true;

/// 提案列表每行显示评级、年化规模、毛利率（与原型一致），代替「已填 X%」。
/// 关掉后列表与改动前完全一致。
const kProposalListFiguresEnabled = true;

/// 列表行用的计划数字，与详情页财务部测算同一口径（只看主产品）。
/// 算不出来的项为空字符串。
({String scale, String margin}) proposalEstimateListFigures(
  Map<String, dynamic> form,
) {
  final scope = proposalIntakeProductFinanceScope(
    form,
    owner: kProposalProductFinanceMain,
  );
  final scaleValue = proposalEffectiveSalesScale(scope);
  final rollup = proposalProductScaleRollup(scope);
  final revenueKnown = rollup != null || proposalRevenueIsManual(scope);
  final scale = rollup?.salesScale ?? scaleValue;
  var margin = '';
  if (revenueKnown && scale > 0) {
    final procurement =
        proposalEstimatedProcurementCost(scope) ??
        proposalFinanceAmount(scope, kProposalCouponProcurementCostKey);
    final profit = proposalRoundWan(
      proposalEffectiveRevenue(scope) -
          procurement -
          proposalFinanceAmount(scope, 'projectCost'),
    );
    margin = proposalFormatWan(
      proposalEstimatedMarginAmount(scope, salesScale: scale, profit: profit),
    );
  }
  return (
    scale: scaleValue > 0 ? proposalFormatWan(scaleValue) : '',
    margin: margin,
  );
}

/// 原型里的颜色（Main 详情页顶部），夜间模式统一走 DunesColors.resolve。
abstract final class _C {
  static const ink = Color(0xFF2A2638);
  static const grey = Color(0xFF8A8499);
  static const text2 = Color(0xFF5B556A);
  static const label = Color(0xFF3D3850);
  static const purple = Color(0xFF6B4FD8);
  static const purpleLight = Color(0xFFC9BEF0);
  static const link = Color(0xFF5B3FD0);
  static const red = Color(0xFFC0563F);
  static const green = Color(0xFF3B8B5A);
  static const heroBg = Color(0xFFEEF2FB);
  static const heroBorder = Color(0xFFD9E0F2);
  static const heroPill = Color(0xFFDCE4F6);
  static const heroInk = Color(0xFF3B4A7A);
  static const boxBg = Color(0xFFFAF9FD);
  static const border = Color(0xFFE7E3F2);
  static const chipLine = Color(0xFFF1EEF8);
  static const cellLine = Color(0xFFEFECF6);
  static const axis = Color(0xFFDCD6EA);
  static const markIdle = Color(0xFFDCD6EA);
  static const profitBg = Color(0xFFF4F6FC);
}

/// 顶部测算的原始数字（万元）。算不出来的为 null，显示「—」。
/// 只读，全部取自财务部同一套测算，不写回表单。
class ProposalEstimateSummaryData {
  const ProposalEstimateSummaryData({
    required this.rating,
    this.ratingRule = '',
    this.scale,
    this.revenue,
    this.procurement,
    this.projectCost,
    this.businessCost,
    this.operatingCost,
    this.profit,
    this.margin,
    this.turnoverCash,
    this.turnoverTimes,
    this.skuCount = 0,
    this.faceRange = '',
  });

  /// 任务评级 S/A/B/C，没有年化规模时为「—」。
  final String rating;

  /// 评级规则说明，如「≥ 5,000万」。
  final String ratingRule;
  final double? scale;

  /// 收入（含采购的毛收入，与财务部「收入（万元）」一致）。
  final double? revenue;

  /// 电子券采购成本。
  final double? procurement;
  final double? projectCost;
  final double? businessCost;
  final double? operatingCost;

  /// 利润 = 收入 − 采购 − 项目成本（与财务部一致）。
  final double? profit;

  /// 毛利率（%）= 利润 ÷ 规模。
  final double? margin;
  final double? turnoverCash;
  final double? turnoverTimes;
  final int skuCount;
  final String faceRange;

  /// 原型里的「收入（利差）」= 收入 − 电子券采购。
  double? get spread {
    final r = revenue;
    if (r == null) return null;
    return r - (procurement ?? 0);
  }

  double? get monthlyScale => scale == null ? null : scale! / 12;
  double? get monthlyProfit => profit == null ? null : profit! / 12;

  double? pctOfScale(double? value) {
    final s = scale;
    if (value == null || s == null || s <= 0) return null;
    return value / s * 100;
  }

  double? get costTotal {
    final parts = [projectCost, businessCost, operatingCost];
    if (parts.every((v) => v == null)) return null;
    return parts.fold<double>(0, (sum, v) => sum + (v ?? 0));
  }
}

/// 「1980.5」→「1,980.5」。非数字原样返回。
String proposalEstimateGrouped(String raw) {
  final text = raw.trim();
  final match = RegExp(r'^(-?)(\d+)(\.\d+)?$').firstMatch(text);
  if (match == null) return text;
  final sign = match.group(1) ?? '';
  final digits = match.group(2)!;
  final fraction = match.group(3) ?? '';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$sign$buffer$fraction';
}

/// 原型格式：一位小数 + 千分位，如 90,000.0。null 显示「—」。
String proposalEstimateWan(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return '—';
  return proposalEstimateGrouped(value.toStringAsFixed(1));
}

String _pct(double? value) =>
    value == null || value.isNaN || value.isInfinite
    ? '—'
    : '${value.toStringAsFixed(1)}%';

/// 提案详情顶部，照原型（Main 详情页）：
/// 左边「年化利润 · 测算」大数字卡，右边「测算合计」小格 + 收入→成本→利润瀑布图，
/// 下面「规模 / 成本 / 利润」三张卡，每格注明来源，可点的直接切到对应板块。
///
/// 只负责展示；数值由页面按财务部现有测算算好传入。
class ProposalEstimateSummary extends StatelessWidget {
  const ProposalEstimateSummary({
    super.key,
    required this.data,
    this.onOpenSection,
    this.onOpenField,
    this.filling = false,
  });

  final ProposalEstimateSummaryData data;

  /// 点「来自 xx ›」：打开板块并定位到那一行（字段锚点 key）。
  final void Function(ProposalIntakeNavSection section, String fieldKey)?
  onOpenField;

  /// 测算里每个数的出处：板块 + 填报内容里那一行的锚点 + 说明。
  static const _sources = <String, (ProposalIntakeNavSection, String, String)>{
    '年化规模': (ProposalIntakeNavSection.market, 'salesScale', '市场部 · 规模'),
    '收入（利差）': (
      ProposalIntakeNavSection.finance,
      'productSalesSettle',
      '财务部 · 产品结算',
    ),
    '收入': (
      ProposalIntakeNavSection.finance,
      'productSalesSettle',
      '财务部 · 产品结算',
    ),
    '售价': (
      ProposalIntakeNavSection.finance,
      'productSalesSettle',
      '财务部 · 产品结算',
    ),
    '项目成本': (ProposalIntakeNavSection.finance, 'costItems', '财务部 · 项目成本'),
    '业务成本': (
      ProposalIntakeNavSection.finance,
      'operatingCost',
      '财务部 · 其他成本',
    ),
    '周转资金': (
      ProposalIntakeNavSection.finance,
      'turnoverTimes',
      '财务部 · 月周转次数',
    ),
    'SKU': (ProposalIntakeNavSection.tech, 'skuDetails', '科技部 · 业务平台产品'),
  };

  /// 打开某个数的出处；没有字段回调时只切板块。
  VoidCallback? _openerFor(String label, ProposalIntakeNavSection? section) {
    final source = _sources[label];
    final target = section ?? source?.$1;
    if (target == null) return null;
    final field = onOpenField;
    if (field != null && source != null && source.$1 == target) {
      return () => field(target, source.$2);
    }
    final open = onOpenSection;
    return open == null ? null : () => open(target);
  }

  /// 填写中：照原型填写页，用「年化利润 · 实时测算」+ 六个小格的紧凑版。
  final bool filling;
  final ValueChanged<ProposalIntakeNavSection>? onOpenSection;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('proposal-estimate-summary'),
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final phone = width < 640;
          if (filling) return _fillingLayout(context, width, phone: phone);
          // 紧凑原型：上排「年化利润」+「测算合计」，下排「规模 / 成本 / 利润」三张小卡。
          return _CompactEstimate(summary: this, width: width, phone: phone);
        },
      ),
    );
  }

  // ---------- 文字 ----------

  /// 用 RichText 画文字：样式与原型一致，也不会和下面表单里同名字段的 Text 混在一起。
  Widget _t(
    BuildContext context,
    String text, {
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color color = _C.ink,
    bool mono = false,
    int maxLines = 1,
    TextAlign align = TextAlign.start,
    List<InlineSpan> tail = const [],
  }) {
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        text: text,
        style: _style(context, size: size, weight: weight, color: color, mono: mono),
        children: tail,
      ),
    );
  }

  TextStyle _style(
    BuildContext context, {
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color color = _C.ink,
    bool mono = false,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: 1.3,
      color: DunesColors.resolve(context, color),
      fontFamily: mono ? kProposalProtoMono : kProposalProtoSans,
      fontFamilyFallback: mono
          ? kProposalProtoMonoFallback
          : kProposalProtoSansFallback,
      fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
    );
  }

  Color _bg(BuildContext context, Color light) =>
      DunesColors.resolve(context, light, role: DunesColorRole.surface);

  Color _line(BuildContext context, Color light) =>
      DunesColors.resolve(context, light, role: DunesColorRole.border);

  // ---------- 填写中：原型填写页的实时测算 ----------

  Widget _fillingLayout(BuildContext context, double width, {required bool phone}) {
    final spread = data.spread;
    final sideBySide = width >= 230 + _gap + 520;
    final hero = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _bg(context, _C.heroBg),
        border: Border.all(color: _line(context, _C.heroBorder)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _bg(context, _C.heroPill),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _t(context, '年化利润 · 实时测算', weight: FontWeight.w700),
                ),
                _t(context, '边填边算', size: 10, color: _C.heroInk),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _t(
            context,
            proposalEstimateWan(data.profit),
            size: phone ? 32 : 38,
            weight: FontWeight.w700,
            color: data.profit == null ? _C.grey : _C.red,
            mono: true,
            tail: [
              TextSpan(
                text: ' 万',
                style: _style(context, size: 14, weight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _t(
            context,
            '= 收入 ${proposalEstimateWan(spread)} − 项目成本 ${proposalEstimateWan(data.projectCost)}',
            size: 11,
            color: _C.text2,
            maxLines: 2,
          ),
        ],
      ),
    );
    final cells = <_Cell>[
      _Cell('年化规模', proposalEstimateWan(data.scale), '万',
          data.rating == '—' ? '来自 市场部' : '评级 ${data.rating} · 来自 市场部', ''),
      _Cell('收入（利差）', proposalEstimateWan(spread), '万',
          data.pctOfScale(spread) == null ? '来自 产品结算' : '利差 ${_pct(data.pctOfScale(spread))} · 来自 产品结算', ''),
      _Cell('项目成本', proposalEstimateWan(data.projectCost), '万', '来自 财务部', ''),
      _Cell('毛利率', data.margin == null ? '—' : data.margin!.toStringAsFixed(2), '%', '利润 ÷ 规模', '',
          null, data.margin != null && data.margin! < 0 ? _C.red : _C.ink),
      _Cell('月均利润', proposalEstimateWan(data.monthlyProfit), '万', '÷12', ''),
      _Cell('周转资金', proposalEstimateWan(data.turnoverCash), '万',
          data.turnoverTimes == null ? '规模 ÷ 12 ÷ 周转次数' : '规模 ÷ 12 ÷ ${proposalFormatWan(data.turnoverTimes!)} 次', ''),
    ];
    final gridWidth = sideBySide ? width - 240 - _gap : width;
    // 原型：auto-fill minmax(150px, 1fr)。
    final columns = (gridWidth / 150).floor().clamp(1, cells.length).toInt();
    Widget cell(_Cell c, {required bool lastInRow}) {
      final empty = c.value == '—';
      return Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: BoxDecoration(
          border: Border(
            right: lastInRow
                ? BorderSide.none
                : BorderSide(color: _line(context, _C.chipLine)),
            bottom: BorderSide(color: _line(context, _C.chipLine)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _t(context, c.label, size: 11, color: _C.label),
            const SizedBox(height: 1),
            _t(
              context,
              c.value,
              size: 15,
              weight: FontWeight.w700,
              color: empty ? _C.grey : c.color,
              mono: true,
              tail: [
                if (!empty)
                  TextSpan(
                    text: c.unit,
                    style: _style(context, size: 10, color: _C.text2),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            _t(context, c.sub, size: 10, color: _C.grey),
          ],
        ),
      );
    }

    final grid = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        border: Border.all(color: _line(context, _C.border)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < cells.length; i += columns)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++)
                    Expanded(
                      child: i + j < cells.length
                          ? cell(cells[i + j], lastInRow: j == columns - 1)
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!sideBySide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [hero, const SizedBox(height: _gap), grid],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 240, child: hero),
          const SizedBox(width: _gap),
          Expanded(child: grid),
        ],
      ),
    );
  }

}

class _Cell {
  const _Cell(
    this.label,
    this.value,
    this.unit,
    this.sub,
    this.src, [
    this.section,
    this.color = _C.ink,
  ]);

  final String label;
  final String value;
  final String unit;
  final String sub;
  final String src;
  final ProposalIntakeNavSection? section;
  final Color color;
}

/// 详情页标题、列表行改成原型样式（评级方块、带圆点的状态标签、流程格子）。
/// 关掉后这几处与改动前完全一致。
const kProposalPrototypeStyleEnabled = true;

/// 原型的评级方块：S 深紫、A 紫、其余浅紫。
class ProposalRatingBadge extends StatelessWidget {
  const ProposalRatingBadge({super.key, required this.rating, this.size = 20});

  final String rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (rating) {
      'S' => (const Color(0xFF3F2A9A), Colors.white),
      'A' => (_C.purple, Colors.white),
      _ => (const Color(0xFFEDE8FB), const Color(0xFF3F2A9A)),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: ValueKey('proposal-rating-badge-$rating'),
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark
            ? DunesColors.resolve(
                context,
                const Color(0xFFEDE8FB),
                role: DunesColorRole.surface,
              )
            : bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        rating,
        style: TextStyle(
          color: dark
              ? DunesColors.resolve(context, const Color(0xFF3F2A9A))
              : fg,
          // 原型：24px 方块里 12 号字，20px 方块里 11 号字。
          fontSize: size >= 24 ? 12 : 11,
          height: 1,
          fontWeight: FontWeight.w700,
          fontFamily: kProposalProtoMono,
          fontFamilyFallback: kProposalProtoMonoFallback,
        ),
      ),
    );
  }
}

/// 原型的状态标签：圆点 + 文字，按状态配色。
class ProposalStatusPill extends StatelessWidget {
  const ProposalStatusPill({
    super.key,
    required this.status,
    required this.label,
    this.dot = true,
  });

  /// 列表里带圆点；详情标题旁（原型）不带圆点。
  final bool dot;

  /// 提案 status：filling / reviewing / pending_president / done / draft。
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, dotColor) = switch (status) {
      'done' => (
        const Color(0xFFE6F3EB),
        const Color(0xFF2D6E47),
        _C.green,
      ),
      'pending_president' => (
        const Color(0xFFEDE8FB),
        const Color(0xFF3F2A9A),
        _C.purple,
      ),
      'reviewing' => (
        const Color(0xFFFDF2E6),
        const Color(0xFF9A4A0C),
        const Color(0xFFE8A866),
      ),
      _ => (
        const Color(0xFFF3F1F6),
        _C.text2,
        const Color(0xFFA9A2BC),
      ),
    };
    return Container(
      key: ValueKey('proposal-status-pill-$status'),
      padding: EdgeInsets.symmetric(horizontal: dot ? 9 : 8, vertical: dot ? 3 : 2),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: DunesColors.resolve(context, dotColor),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context),
              text: TextSpan(
                text: label,
                style: TextStyle(
                  color: DunesColors.resolve(context, fg),
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  fontFamily: kProposalProtoSans,
                  fontFamilyFallback: kProposalProtoSansFallback,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 原型的「流程」格子：每个环节一格，✓ 已过、橙框是当前、灰色未开始。
class ProposalFlowCard extends StatelessWidget {
  const ProposalFlowCard({super.key, required this.steps});

  final List<ProposalIntakeProgressStep> steps;

  @override
  Widget build(BuildContext context) {
    // 原型只列复核环节，格子名写板块名。
    const labels = {
      'review_market': '市场部',
      'review_tech': '科技部',
      'review_contract': '合同 · 财务逐条',
      'review_finance_module': '财务整板块',
      'notify_president': '通知最终人',
      'president': '总裁',
    };
    final visible = [
      for (final step in steps)
        if (labels.containsKey(step.id)) step,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    final current = [
      for (final step in visible)
        if (step.state == ProposalIntakeProgressState.current) step,
    ];
    final allDone = visible.every(
      (step) => step.state == ProposalIntakeProgressState.done,
    );
    final note = current.isNotEmpty
        ? '卡 · ${current.map((s) => s.name.isEmpty ? s.role : s.name).join('、')}'
        : (allDone ? '${visible.length}/${visible.length} 已通过' : '');
    final noteColor = current.isNotEmpty ? const Color(0xFFB4570F) : _C.green;
    TextStyle style(double size, Color color, {FontWeight? weight, bool mono = false}) =>
        TextStyle(
          fontSize: size,
          height: 1.3,
          fontWeight: weight,
          color: DunesColors.resolve(context, color),
          fontFamily: mono ? kProposalProtoMono : kProposalProtoSans,
          fontFamilyFallback: mono
              ? kProposalProtoMonoFallback
              : kProposalProtoSansFallback,
        );
    Widget rich(String text, TextStyle s, {int maxLines = 1}) => RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(text: text, style: s),
    );
    Widget cell(ProposalIntakeProgressStep step) {
      final (bg, value, color, ring) = switch (step.state) {
        ProposalIntakeProgressState.done => (
          const Color(0xFFEEF6F1),
          '✓',
          _C.green,
          false,
        ),
        // 原型格子里只放短值（✓ / 18/21 / 待你 / —）；长提示放到悬停里。
        ProposalIntakeProgressState.current => (
          const Color(0xFFFDF2E6),
          step.statusText.trim().isNotEmpty &&
                  step.statusText.trim().runes.length <= 5
              ? step.statusText.trim()
              : '进行中',
          const Color(0xFFB4570F),
          true,
        ),
        ProposalIntakeProgressState.rejected => (
          const Color(0xFFFBF0EC),
          '驳回',
          _C.red,
          false,
        ),
        ProposalIntakeProgressState.pending => (
          const Color(0xFFF5F4F8),
          '—',
          _C.grey,
          false,
        ),
      };
      final sub = [
        if (step.name.isNotEmpty) step.name,
        if (step.time.isNotEmpty && step.time != '当前') step.time,
      ].join(' · ');
      final tip = step.state == ProposalIntakeProgressState.current
          ? step.statusText.trim()
          : '';
      final box = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
          borderRadius: BorderRadius.circular(8),
          border: ring
              ? Border.all(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFE8A866),
                    role: DunesColorRole.border,
                  ),
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            rich(labels[step.id] ?? step.role, style(11, _C.label)),
            const SizedBox(height: 1),
            rich(value, style(14, color, weight: FontWeight.w700, mono: true)),
            const SizedBox(height: 1),
            rich(sub.isEmpty ? ' ' : sub, style(10, _C.text2)),
          ],
        ),
      );
      return tip.isEmpty ? box : Tooltip(message: tip, child: box);
    }

    const columns = 3;
    return Container(
      key: const ValueKey('proposal-flow-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        border: Border.all(
          color: DunesColors.resolve(context, _C.border, role: DunesColorRole.border),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            // 原型：「流程」在左，「卡 · 谁」靠右。
            child: Row(
              children: [
                rich('流程', style(13, _C.ink, weight: FontWeight.w700)),
                const SizedBox(width: 12),
                Expanded(
                  child: note.isEmpty
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.centerRight,
                          child: rich(note, style(11, noteColor, mono: true)),
                        ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < visible.length; i += columns) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) const SizedBox(width: 6),
                  Expanded(
                    child: i + j < visible.length
                        ? cell(visible[i + j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 顶部测算（PC、手机同一套，按宽度排版）：
/// 上排：左「年化利润 · 测算」小卡；右「测算合计」—— 左边一列六个指标，点哪个右边柱状图就换成它的构成。
/// 下排：「规模 / 成本 / 利润」三块，照灯塔「产品汇总」的样子（10 : 14 : 15）。
/// 指标和格子都能点回出处（填报内容里那一行）。
/// 手机照灯塔手机版：仍是左右两块 + 下面三块一排，只是字号收小；
/// 「测算合计」窄的时候指标改成两列放在柱状图上面。
class _CompactEstimate extends StatefulWidget {
  const _CompactEstimate({
    required this.summary,
    required this.width,
    required this.phone,
  });

  final ProposalEstimateSummary summary;
  final double width;
  final bool phone;

  @override
  State<_CompactEstimate> createState() => _CompactEstimateState();
}

/// 柱状图里的一根柱子。[lift] > 0 时悬空（瀑布图里的「减项」）。
class _Bar {
  const _Bar(this.label, this.value, this.color, {this.minus = false, this.lift = 0});

  final String label;
  final double? value;
  final Color color;
  final bool minus;
  final double lift;
}

class _CompactEstimateState extends State<_CompactEstimate> {
  String _selected = '收入（利差）';

  ProposalEstimateSummary get _s => widget.summary;
  ProposalEstimateSummaryData get _d => widget.summary.data;

  Widget _t(
    String text, {
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color color = _C.ink,
    bool mono = false,
    int maxLines = 1,
    TextAlign align = TextAlign.start,
    List<InlineSpan> tail = const [],
  }) => _s._t(
    context,
    text,
    size: size,
    weight: weight,
    color: color,
    mono: mono,
    maxLines: maxLines,
    align: align,
    tail: tail,
  );

  TextStyle _st({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color color = _C.ink,
    bool mono = false,
  }) => _s._style(context, size: size, weight: weight, color: color, mono: mono);

  Color _bg(Color c) => _s._bg(context, c);
  Color _ln(Color c) => _s._line(context, c);

  /// 手机宽度：字号、间距收小一档（布局不变）。
  bool get _compact => widget.phone;

  /// 太窄（< 340）才上下排。
  bool get _stacked => widget.width < 340;

  double get _heroWidth =>
      _stacked ? widget.width : (widget.width * .3).clamp(112.0, 200.0).toDouble();

  // ---------- 上左：年化利润（小） ----------

  Widget _hero({required bool stretch}) {
    final d = _d;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _bg(_C.heroBg),
        border: Border.all(color: _ln(_C.heroBorder)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _bg(_C.heroPill),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.show_chart,
                  size: 13,
                  color: DunesColors.resolve(context, _C.heroInk),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _t(
                    _compact ? '年化利润' : '年化利润 · 测算',
                    size: _compact ? 11 : 12,
                    weight: FontWeight.w700,
                    color: _C.heroInk,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _t(
            proposalEstimateWan(d.profit),
            // 手机上大数长了（如 12,345.0）收一档，免得被省略。
            size: _compact
                ? (proposalEstimateWan(d.profit).length > 6 ? 18 : 22)
                : 28,
            weight: FontWeight.w700,
            color: d.profit == null ? _C.grey : _C.red,
            mono: true,
            tail: [
              TextSpan(
                text: ' 万',
                style: _st(size: _compact ? 10 : 12, weight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _t(
            _pct(d.margin),
            size: _compact ? 10 : 11,
            weight: FontWeight.w700,
            mono: true,
            maxLines: 2,
            tail: [
              TextSpan(
                text: _compact ? ' 毛利率' : ' 毛利率 · 利润÷规模',
                style: _st(size: _compact ? 10 : 11, color: _C.text2, mono: true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _t(
            '= 收入 ${proposalEstimateWan(d.spread)} − 项目成本 ${proposalEstimateWan(d.projectCost)}',
            size: _compact ? 9 : 10,
            color: _C.text2,
            maxLines: 3,
          ),
          if (stretch) const Spacer() else const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _ln(_C.heroBorder))),
            ),
            child: _t(
              d.rating,
              size: _compact ? 13 : 14,
              weight: FontWeight.w700,
              mono: true,
              maxLines: 3,
              tail: [
                TextSpan(
                  text: d.ratingRule.isEmpty
                      ? '  任务评级 · 按年化规模自动'
                      : '  任务评级 · ${d.ratingRule}',
                  style: _st(size: 10, color: _C.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 上右：测算合计（左列指标 + 右边柱状图） ----------

  List<(String, String, String, Color)> get _metrics {
    final d = _d;
    final spread = d.spread;
    return [
      ('年化规模', proposalEstimateWan(d.scale), d.rating == '—' ? '' : '${d.rating} 级', _C.purple),
      ('收入（利差）', proposalEstimateWan(spread), _pct(d.pctOfScale(spread)), _C.purple),
      ('项目成本', proposalEstimateWan(d.projectCost), _pct(d.pctOfScale(d.projectCost)), _C.purpleLight),
      ('利润', proposalEstimateWan(d.profit), _pct(d.margin), _C.red),
      ('月均规模', proposalEstimateWan(d.monthlyScale), '÷12', _C.markIdle),
      (
        '周转资金',
        proposalEstimateWan(d.turnoverCash),
        d.turnoverTimes == null ? '' : '${proposalFormatWan(d.turnoverTimes!)}次/月',
        _C.markIdle,
      ),
    ];
  }

  /// 每个指标对应的柱状图：收入 / 成本 / 利润 用原版瀑布图；规模看「规模 → 收入 → 利润」；
  /// 月均规模看每月；周转资金看「月均规模 ÷ 周转次数」。
  (List<_Bar>, String) _barsFor(String metric) {
    final d = _d;
    final spread = d.spread;
    final cost = d.projectCost ?? 0;
    final profit = d.profit;
    switch (metric) {
      case '年化规模':
        return (
          [
            _Bar('年化规模', d.scale, _C.purple),
            _Bar('收入（利差）', spread, _C.purpleLight),
            _Bar('利润', profit, _C.red),
          ],
          '规模 → 收入 → 利润 · 年化',
        );
      case '月均规模':
        return (
          [
            _Bar('月均规模', d.monthlyScale, _C.purple),
            _Bar('月均收入', spread == null ? null : spread / 12, _C.purpleLight),
            _Bar('月均利润', d.monthlyProfit, _C.red),
          ],
          '每月 · 年化 ÷ 12',
        );
      case '周转资金':
        return (
          [
            _Bar('月均规模', d.monthlyScale, _C.purpleLight),
            _Bar('周转资金', d.turnoverCash, _C.purple),
          ],
          d.turnoverTimes == null
              ? '月均规模 ÷ 周转次数'
              : '月均规模 ÷ 每月周转 ${proposalFormatWan(d.turnoverTimes!)} 次',
        );
      default:
        final profitLift = profit != null && profit > 0 ? profit : 0.0;
        return (
          [
            _Bar('收入（利差）', spread, _C.purple),
            _Bar('项目成本', cost, _C.purpleLight, minus: true, lift: profitLift),
            _Bar('利润', profit, _C.red),
          ],
          '收入 − 项目成本 = 利润 · 年化',
        );
    }
  }

  Widget _metricRow((String, String, String, Color) m, {bool tight = false}) {
    final active = m.$1 == _selected;
    return InkWell(
      key: ValueKey('proposal-estimate-metric-${m.$1}'),
      onTap: () => setState(() => _selected = m.$1),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tight ? 5 : 8,
          vertical: tight ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: active ? _bg(const Color(0xFFF1ECFF)) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 2,
              color: DunesColors.resolve(context, active ? _C.purple : m.$4),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _t(
                tight && m.$1 == '收入（利差）' ? '收入' : m.$1,
                size: tight ? 10 : 12,
                weight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? const Color(0xFF3F2A9A) : _C.ink,
              ),
            ),
            _t(
              m.$2,
              size: tight ? 11 : 12,
              weight: FontWeight.w700,
              mono: true,
              color: m.$1 == '利润' ? _C.red : _C.ink,
            ),
            SizedBox(
              width: tight ? 34 : 50,
              child: _t(
                m.$3,
                size: tight ? 8.5 : 10,
                color: _C.grey,
                mono: true,
                align: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barChart(List<_Bar> bars, {required double height}) {
    final top = bars
        .map((b) => (b.value ?? 0).abs() + b.lift)
        .fold<double>(0, (a, b) => b > a ? b : a);
    final full = height - 24;
    double h(double? v) => top <= 0 || v == null || v <= 0
        ? 0
        : (v / top * full).clamp(0.0, full).toDouble();
    Widget column(_Bar b) {
      final active = b.label == _selected ||
          (_selected == '收入（利差）' && b.label == '收入（利差）');
      final color = active || _selected == '年化规模' || _selected == '月均规模' || _selected == '周转资金'
          ? b.color
          : b.color.withValues(alpha: .55);
      final labelColor = b.minus
          ? _C.green
          : (b.label.contains('利润') ? _C.red : _C.ink);
      final valueText = b.minus && b.value != null
          ? '−${proposalEstimateWan(b.value)}'
          : proposalEstimateWan(b.value);
      return Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _t(valueText, size: 11, weight: FontWeight.w700, color: labelColor, mono: true),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 56),
            child: Container(
              height: math.max(2.0, h(b.value)),
              decoration: BoxDecoration(
                color: DunesColors.resolve(context, color, role: DunesColorRole.surface),
                borderRadius: b.minus
                    ? BorderRadius.circular(3)
                    : const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ),
          SizedBox(height: h(b.lift)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _ln(_C.axis))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < bars.length; i++) ...[
                if (i > 0) const SizedBox(width: 18),
                Expanded(child: column(bars[i])),
              ],
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            for (var i = 0; i < bars.length; i++) ...[
              if (i > 0) const SizedBox(width: 18),
              Expanded(
                child: _t(
                  bars[i].label,
                  size: 10,
                  color: _C.text2,
                  mono: true,
                  align: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _summary(double width) {
    final metrics = _metrics;
    // 够宽：指标一列在左、柱状图在右；窄（手机）：指标两列在上、柱状图在下（同灯塔手机版）。
    final sideBySide = width >= 560;
    final selected = metrics.firstWhere(
      (m) => m.$1 == _selected,
      orElse: () => metrics[1],
    );
    final open = _s._openerFor(selected.$1, null);
    final source = ProposalEstimateSummary._sources[selected.$1];
    final (bars, caption) = _barsFor(selected.$1);
    final list = sideBySide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final m in metrics) _metricRow(m)],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < metrics.length; i += 2)
                Row(
                  children: [
                    Expanded(child: _metricRow(metrics[i], tight: true)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: i + 1 < metrics.length
                          ? _metricRow(metrics[i + 1], tight: true)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
            ],
          );
    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _t(caption, size: 10, color: _C.grey)),
            if (open != null && source != null)
              InkWell(
                key: const ValueKey('proposal-estimate-metric-source'),
                onTap: open,
                borderRadius: BorderRadius.circular(4),
                child: _t('来自 ${source.$3} ›', size: 10, color: _C.link),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _barChart(bars, height: sideBySide ? 138 : 112),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: _bg(_C.boxBg),
        border: Border.all(color: _ln(_C.border)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 15,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(context, _C.purple),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              _t('测算合计', weight: FontWeight.w700),
              const SizedBox(width: 8),
              Expanded(
                child: _t(
                  sideBySide ? '年化 · 万元 · 点指标切换柱状图' : '点指标切换',
                  size: 10,
                  color: _C.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!sideBySide) ...[
            Container(
              decoration: BoxDecoration(
                color: _bg(Colors.white),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(4),
              child: list,
            ),
            const SizedBox(height: 10),
            chart,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 250,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _bg(Colors.white),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: list,
                ),
                const SizedBox(width: 14),
                Expanded(child: chart),
              ],
            ),
        ],
      ),
    );
  }

  // ---------- 下：规模 / 成本 / 利润（灯塔产品汇总样式） ----------

  Widget _cell(
    String label,
    String value,
    String unit,
    String sub, {
    Color color = _C.ink,
    bool divider = true,
  }) {
    final open = _s._openerFor(label, null);
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: _ln(_C.cellLine)))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _t(
            label,
            size: _compact ? 10 : 11,
            color: _C.text2,
            tail: [
              TextSpan(
                text: ' →',
                style: _st(
                  size: _compact ? 10 : 11,
                  color: open == null ? _C.grey : _C.link,
                  weight: open == null ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          _t(
            value,
            size: _compact ? 13 : 15,
            weight: FontWeight.w700,
            mono: true,
            color: value == '—' ? _C.grey : color,
            tail: [
              if (unit.isNotEmpty && value != '—')
                TextSpan(
                  text: unit,
                  style: _st(size: _compact ? 8.5 : 9, color: _C.text2),
                ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 1),
            _t(sub, size: _compact ? 9 : 10, color: _C.grey, mono: true, maxLines: 2),
          ],
        ],
      ),
    );
    if (open == null) return body;
    final source = ProposalEstimateSummary._sources[label];
    return Tooltip(
      message: source == null ? '点击查看出处' : '来自 ${source.$3}，点击查看',
      child: InkWell(onTap: open, child: body),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    List<Widget> cells, {
    int columns = 1,
    bool result = false,
  }) {
    // 灯塔：规模 / 成本 灰白面板，利润 淡蓝面板；细边、圆角 12。
    const resultAccent = Color(0xFF4A83C4);
    return Container(
      padding: _compact
          ? const EdgeInsets.fromLTRB(7, 7, 7, 3)
          : const EdgeInsets.fromLTRB(10, 9, 10, 4),
      decoration: BoxDecoration(
        color: result
            ? DunesColors.resolve(context, resultAccent).withAlpha(24)
            : _bg(const Color(0xFFF7F6FA)),
        border: Border.all(
          color: result
              ? DunesColors.resolve(context, resultAccent).withAlpha(58)
              : _ln(const Color(0xFFE7E3EF)),
          width: .8,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: _compact ? 12 : 14,
                color: DunesColors.resolve(context, _C.text2),
              ),
              SizedBox(width: _compact ? 4 : 6),
              Expanded(
                child: _t(title, size: _compact ? 12 : 13, weight: FontWeight.w700),
              ),
              if (!_compact) _t('年化', size: 10, color: _C.grey, mono: true),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < cells.length; i += columns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: _compact ? 8 : 16),
                  Expanded(
                    child: i + j < cells.length ? cells[i + j] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _bottom() {
    final d = _d;
    final spread = d.spread;
    final price = d.pctOfScale(d.revenue);
    final scale = _section('规模', Icons.trending_up, [
      _cell('年化规模', proposalEstimateWan(d.scale), '万', d.rating == '—' ? '' : '${d.rating} 级'),
      _cell('月均规模', proposalEstimateWan(d.monthlyScale), '万', '÷12'),
      _cell('售价', price == null ? '—' : price.toStringAsFixed(1), '%', '收入 ÷ 规模'),
      _cell('SKU', d.skuCount == 0 ? '—' : '${d.skuCount}', '个', d.faceRange, divider: false),
    ]);
    final cost = _section('成本', Icons.receipt_long_outlined, [
      _cell('成本合计', proposalEstimateWan(d.costTotal), '万', '项目 + 业务 + 经营'),
      _cell(
        '项目成本',
        proposalEstimateWan(d.projectCost),
        '万',
        d.pctOfScale(d.projectCost) == null ? '' : '${_pct(d.pctOfScale(d.projectCost))} 规模',
      ),
      _cell('业务成本', proposalEstimateWan(d.businessCost), '万', ''),
      _cell(
        '周转资金',
        proposalEstimateWan(d.turnoverCash),
        '万',
        d.turnoverTimes == null ? '' : '每月周转 ${proposalFormatWan(d.turnoverTimes!)} 次',
        divider: false,
      ),
    ]);
    final profitCells = [
      _cell('利润', proposalEstimateWan(d.profit), '万', '收入 − 项目成本', color: _C.red),
      _cell('月均利润', proposalEstimateWan(d.monthlyProfit), '万', '÷12'),
      _cell(
        '收入',
        proposalEstimateWan(spread),
        '万',
        d.pctOfScale(spread) == null ? '' : '规模 × ${_pct(d.pctOfScale(spread))}',
      ),
      _cell('电子券采购', proposalEstimateWan(d.procurement), '万', ''),
      _cell(
        '毛利率',
        d.margin == null ? '—' : d.margin!.toStringAsFixed(2),
        '%',
        '利润 ÷ 规模',
        color: d.margin != null && d.margin! < 0 ? _C.red : _C.ink,
        divider: false,
      ),
      _cell(
        '成本率',
        d.pctOfScale(d.projectCost) == null ? '—' : d.pctOfScale(d.projectCost)!.toStringAsFixed(2),
        '%',
        '项目成本 ÷ 规模',
        divider: false,
      ),
    ];
    final profit = _section('利润', Icons.show_chart, profitCells, columns: 2, result: true);
    if (_stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          scale,
          const SizedBox(height: 8),
          cost,
          const SizedBox(height: 8),
          profit,
        ],
      );
    }
    // 灯塔：规模 : 成本 : 利润 = 10 : 14 : 15。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 10, child: scale),
          SizedBox(width: _compact ? 6 : 10),
          Expanded(flex: 14, child: cost),
          SizedBox(width: _compact ? 6 : 10),
          Expanded(flex: 15, child: profit),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = _compact ? 6.0 : 10.0;
    return Column(
      key: const ValueKey('proposal-estimate-compact'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_stacked) ...[
          _hero(stretch: false),
          const SizedBox(height: 8),
          _summary(widget.width),
        ] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: _heroWidth, child: _hero(stretch: true)),
                SizedBox(width: gap),
                Expanded(child: _summary(widget.width - _heroWidth - gap)),
              ],
            ),
          ),
        SizedBox(height: _compact ? 8 : 10),
        _bottom(),
      ],
    );
  }
}
