import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'proposal_cost_estimate.dart';
import 'proposal_finance_formula.dart';
import 'proposal_intake_select.dart';
import 'proposal_intake_ui.dart';

/// 财务部下半部分：「成本」「利润」两大块，视觉上与顶部年化测算 hero 一致。
///
/// 每块顶部一条 hero 带（大数字 + 构成），下面是一行一项的摘要；
/// 公式、代入过程、可改的选择都收在展开里，默认不铺开，信息量只在需要时出现。
/// 顶部 hero 点「成本 / 利润 / 收入 …」会跳到这里，并自动展开对应那一行。
///
/// 谁能改什么由页面按角色传进 [ProposalFinanceBoardConfig]：
/// - 填写人：收入公式、项目 / 经营 / 税务成本（产品结算里已有的项目成本自动带出、锁定）；
/// - 财务部负责人二：同上并逐条复核；业务成本与利润对其加密；
/// - 市场部负责人一：财务复核时选业务成本；
/// - 其他人：只读。
class ProposalFinanceBoardConfig {
  const ProposalFinanceBoardConfig({
    required this.evaluation,
    required this.catalog,
    this.revenueEditable = false,
    this.categoryEditable = const {},
    this.businessSealed = false,
    this.businessWaitingText = '由市场部负责人一在财务复核时选择',
    this.roleNote = '',
    this.reviewToggle,
    this.reviewStatus,
    this.promotionPlan = const ProposalPromotionTierPlan(),
    this.onPromotionTiers,
    this.onRevenueFormula,
    this.onCostItemsChanged,
    this.onCostFormula,
    this.anchor,
    this.focusKeys = const {},
    this.turnoverCash,
    this.turnoverTimes,
    this.turnoverField,
  });

  final ProposalFinanceEvaluation evaluation;
  final ProposalFinanceFormulaCatalog catalog;
  final bool revenueEditable;

  /// 每类成本当前用户能不能改，key 为 [ProposalCostCategory.key]。
  final Map<String, bool> categoryEditable;

  /// 业务成本对当前用户加密（财务部负责人二）。利润、毛利率同样不显示。
  final bool businessSealed;
  final String businessWaitingText;

  /// 一句话说明当前用户在这块能做什么。
  final String roleNote;

  /// 行内复核控件。key：revenue / costItems / businessCost / operatingCost /
  /// taxCost / turnoverCash / profit。
  final Widget? Function(String key)? reviewToggle;

  /// 收起时显示的复核状态（只读小标签）；展开后才出现复核按钮，页面保持整洁。
  final Widget? Function(String key)? reviewStatus;

  /// 推广费阶梯方案与写回。
  final ProposalPromotionTierPlan promotionPlan;
  final ValueChanged<ProposalPromotionTierPlan>? onPromotionTiers;
  final void Function(String groupKey, String code)? onRevenueFormula;
  final void Function(ProposalCostCategory category, List<String> names)?
  onCostItemsChanged;
  final void Function(ProposalCostCategory category, String name, String code)?
  onCostFormula;

  /// 页面的字段锚点：顶部 hero 跳转、闪烁定位都靠它。
  final Widget Function(String key, Widget child)? anchor;

  /// 正在被跳转定位的锚点 key：命中的行自动展开。
  final Set<String> focusKeys;

  final double? turnoverCash;
  final double? turnoverTimes;

  /// 「月周转次数」输入（或只读值），由页面按权限构建。
  final Widget? turnoverField;

  Widget wrap(String key, Widget child) => anchor?.call(key, child) ?? child;
}

/// 锚点 key：与顶部 hero 的跳转一致。
const kProposalFinanceCostAnchor = 'financeCost';
const kProposalFinanceProfitAnchor = 'financeProfit';

String proposalFinanceCategoryAnchor(String categoryKey) =>
    switch (categoryKey) {
      kProposalCostCategoryProject => 'costItems',
      kProposalCostCategoryBusiness => 'businessCost',
      kProposalCostCategoryOperating => 'operatingCost',
      kProposalCostCategoryTax => 'taxCost',
      _ => categoryKey,
    };

// ---------------------------------------------------------------------------
// 颜色与小件
// ---------------------------------------------------------------------------

abstract final class _K {
  static const ink = Color(0xFF2A2638);
  static const grey = Color(0xFF8A8499);
  static const text2 = Color(0xFF5B556A);
  static const red = Color(0xFFC0563F);
  static const heroBg = Color(0xFFEEF2FB);
  static const heroBorder = Color(0xFFD9E0F2);
  static const heroInk = Color(0xFF3B4A7A);
  static const profitBg = Color(0xFFF4F6FC);
  static const rowLine = Color(0xFFEFECF6);
  static const project = Color(0xFF6B4FD8);
  static const business = Color(0xFF4A83C4);
  static const operating = Color(0xFF3B8B5A);
  static const tax = Color(0xFFB07A2B);
}

Color _categoryColor(String key) => switch (key) {
  kProposalCostCategoryProject => _K.project,
  kProposalCostCategoryBusiness => _K.business,
  kProposalCostCategoryOperating => _K.operating,
  kProposalCostCategoryTax => _K.tax,
  _ => _K.grey,
};

Color _c(BuildContext context, Color light) => DunesColors.resolve(context, light);

Color _surface(BuildContext context, Color light) =>
    DunesColors.resolve(context, light, role: DunesColorRole.surface);

Color _border(BuildContext context, Color light) =>
    DunesColors.resolve(context, light, role: DunesColorRole.border);

String _wan(double value) => proposalFormatWan(value);

TextStyle _mono(
  BuildContext context, {
  double size = 13,
  FontWeight weight = FontWeight.w700,
  Color color = _K.ink,
}) => TextStyle(
  fontFamily: kProposalProtoMono,
  fontFamilyFallback: kProposalProtoMonoFallback,
  fontSize: size,
  fontWeight: weight,
  color: _c(context, color),
  height: 1.2,
  fontFeatures: const [FontFeature.tabularFigures()],
);

TextStyle _sans(
  BuildContext context, {
  double size = 12,
  FontWeight weight = FontWeight.w400,
  Color color = _K.ink,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  color: _c(context, color),
  height: 1.4,
);

class ProposalFinanceTag extends StatelessWidget {
  const ProposalFinanceTag(this.text, {this.color = _K.text2, this.fill = const Color(0xFFF3F0F7)});

  final String text;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _surface(context, fill),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: _sans(context, size: 10, weight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// 公式（灰）+ 代入（紫，可选中复制）。
class _Trace extends StatelessWidget {
  const _Trace({this.formula = '', this.substitution = ''});

  final String formula;
  final String substitution;

  @override
  Widget build(BuildContext context) {
    if (formula.isEmpty && substitution.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _surface(context, ProposalPalette.soft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (formula.isNotEmpty)
            Text(formula, style: _sans(context, size: 11, color: _K.text2)),
          if (substitution.isNotEmpty)
            SelectableText(
              substitution,
              style: _mono(
                context,
                size: 11.5,
                weight: FontWeight.w600,
                color: ProposalPalette.purpleDeep,
              ),
            ),
        ],
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing(this.missing);

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '提案里取不到：${missing.join('、')}，暂按 0 计',
        style: _sans(context, size: 11, color: ProposalPalette.amber),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 块外壳：hero 带 + 行
// ---------------------------------------------------------------------------

class ProposalFinanceBlockShell extends StatelessWidget {
  const ProposalFinanceBlockShell({
    required this.icon,
    required this.title,
    required this.band,
    required this.rows,
    this.tint = _K.heroBg,
    this.footer,
  });

  final IconData icon;
  final String title;
  final Widget band;
  final List<Widget> rows;
  final Color tint;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface(context, Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border(context, _K.heroBorder)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _surface(context, tint),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: _c(context, _K.heroInk)),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: _sans(
                        context,
                        size: 13,
                        weight: FontWeight.w700,
                        color: _K.heroInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                band,
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: _border(context, _K.rowLine)),
            rows[i],
          ],
          ?footer,
        ],
      ),
    );
  }
}

/// 一行一项：名称 · 摘要 · 金额 · 复核 · 展开箭头。展开后是公式、代入和可改的选择。
class ProposalFinanceRow extends StatefulWidget {
  const ProposalFinanceRow({
    required this.title,
    required this.value,
    this.summary = '',
    this.accent,
    this.valueColor = _K.ink,
    this.tag,
    this.review,
    this.collapsedReview,
    this.detail,
    this.initiallyOpen = false,
    this.forceOpen = false,
  });

  final String title;
  final String value;
  final String summary;
  final Color? accent;
  final Color valueColor;
  final Widget? tag;
  final Widget? review;

  /// 收起时代替 [review] 显示的复核状态。传了它，复核按钮只在展开后出现。
  final Widget? collapsedReview;
  final Widget? detail;
  final bool initiallyOpen;
  final bool forceOpen;

  @override
  State<ProposalFinanceRow> createState() => _ProposalFinanceRowState();
}

class _ProposalFinanceRowState extends State<ProposalFinanceRow> {
  late bool _open = widget.initiallyOpen || widget.forceOpen;

  @override
  void didUpdateWidget(covariant ProposalFinanceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceOpen && !oldWidget.forceOpen) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final compact = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    final canOpen = widget.detail != null;
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.accent != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _c(context, widget.accent!),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          widget.title,
          style: _sans(context, size: 12.5, weight: FontWeight.w700),
        ),
        if (widget.tag != null) ...[const SizedBox(width: 6), widget.tag!],
      ],
    );
    // 展开后由下面的明细说话，摘要不再重复一遍。
    final summary = widget.summary.isEmpty || (_open && widget.detail != null)
        ? null
        : Text(
            widget.summary,
            maxLines: _open ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 11.5, color: _K.text2),
          );
    final value = widget.value.isEmpty
        ? const SizedBox.shrink()
        : Text(
      widget.value,
      style: _mono(context, size: 13.5, color: widget.valueColor),
    );
    // 收起时只显示复核状态，点开这一行才出现复核 / 驳回按钮。
    final review = widget.collapsedReview != null && canOpen && !_open
        ? widget.collapsedReview
        : widget.review;
    final chevron = canOpen
        ? AnimatedRotation(
            turns: _open ? 0.25 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _c(context, _K.grey),
            ),
          )
        : const SizedBox(width: 18);
    final head = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  value,
                  if (review != null) ...[
                    const SizedBox(width: 6),
                    review,
                  ],
                  chevron,
                ],
              ),
              if (summary != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: summary),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 132, child: title),
              Expanded(child: summary ?? const SizedBox.shrink()),
              const SizedBox(width: 10),
              value,
              if (review != null) ...[
                const SizedBox(width: 8),
                review,
              ],
              chevron,
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: canOpen ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
            child: head,
          ),
        ),
        if (_open && widget.detail != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: widget.detail,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 成本
// ---------------------------------------------------------------------------

class ProposalFinanceCostPanel extends StatelessWidget {
  const ProposalFinanceCostPanel({super.key, required this.config});

  final ProposalFinanceBoardConfig config;

  @override
  Widget build(BuildContext context) {
    final eval = config.evaluation;
    final sealed = config.businessSealed;
    final buckets = eval.buckets.values.toList();
    double shown(ProposalFinanceBucket bucket) =>
        sealed && bucket.category.key == kProposalCostCategoryBusiness
        ? 0
        : bucket.total;
    final total = buckets.fold<double>(0, (sum, b) => sum + shown(b));
    final scale = eval.salesScale;

    final band = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text.rich(
              TextSpan(
                text: _wan(total),
                style: _mono(context, size: 18, weight: FontWeight.w700),
                children: [
                  TextSpan(
                    text: ' 万 · 年化成本',
                    style: _sans(context, size: 11, color: _K.grey),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (scale > 0)
              Text(
                '占规模 ${_wan(total / scale * 100)}%',
                style: _mono(context, size: 11.5, color: _K.heroInk),
              ),
          ],
        ),
        if (sealed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '不含已加密的业务成本',
              style: _sans(context, size: 11, color: _K.grey),
            ),
          ),
        const SizedBox(height: 8),
        _CompositionBar(
          parts: [
            for (final bucket in buckets)
              if (!(sealed &&
                  bucket.category.key == kProposalCostCategoryBusiness))
                (bucket.category.name, shown(bucket), _categoryColor(bucket.category.key)),
          ],
        ),
      ],
    );

    final rows = <Widget>[
      for (final bucket in buckets) _categoryRow(context, bucket),
      config.wrap('turnoverTimes', _turnoverRow(context)),
    ];
    return config.wrap(
      kProposalFinanceCostAnchor,
      ProposalFinanceBlockShell(
        icon: Icons.receipt_long_outlined,
        title: '成本',
        band: band,
        rows: rows,
      ),
    );
  }

  Widget _categoryRow(BuildContext context, ProposalFinanceBucket bucket) {
    final category = bucket.category;
    final anchorKey = proposalFinanceCategoryAnchor(category.key);
    final sealed =
        config.businessSealed && category.key == kProposalCostCategoryBusiness;
    final editable =
        config.categoryEditable[category.key] == true &&
        config.onCostItemsChanged != null &&
        !sealed;
    final waiting = category.key == kProposalCostCategoryBusiness
        ? config.businessWaitingText
        : '未选择';
    final summary = sealed
        ? '已加密，负责人二不可查看'
        : bucket.lines.isEmpty
        ? (editable ? '点开选择成本项' : waiting)
        : [
            for (final line in bucket.lines)
              line.pending ? '${line.name} 未配置阶梯' : '${line.name} ${_wan(line.amount)}',
          ].join(' · ');
    final hasIssue = bucket.lines.any((line) => line.missing.isNotEmpty);
    final row = ProposalFinanceRow(
      title: category.name,
      accent: _categoryColor(category.key),
      summary: summary,
      value: sealed ? '—' : '${_wan(bucket.total)} 万',
      tag: sealed
          ? const ProposalFinanceTag('已加密', color: _K.red, fill: Color(0xFFF5E5DC))
          : hasIssue
          ? const ProposalFinanceTag('有缺项', color: ProposalPalette.amber, fill: ProposalPalette.amberSoft)
          : null,
      review: config.reviewToggle?.call(
        ProposalFinanceFormulaBoardKeys.reviewKeyOf(category.key),
      ),
      collapsedReview: config.reviewStatus?.call(
        ProposalFinanceFormulaBoardKeys.reviewKeyOf(category.key),
      ),
      forceOpen: config.focusKeys.contains(anchorKey),
      detail: sealed
          ? null
          : _CategoryDetail(
              bucket: bucket,
              editable: editable,
              onItemsChanged: config.onCostItemsChanged == null
                  ? null
                  : (names) => config.onCostItemsChanged!(category, names),
              onFormula: config.onCostFormula == null || !editable
                  ? null
                  : (name, code) => config.onCostFormula!(category, name, code),
              promotionPlan: config.promotionPlan,
              onPromotionTiers: editable ? config.onPromotionTiers : null,
            ),
    );
    return config.wrap(anchorKey, row);
  }

  Widget _turnoverRow(BuildContext context) {
    final cash = config.turnoverCash;
    final times = config.turnoverTimes;
    return ProposalFinanceRow(
      title: '周转资金',
      accent: _K.grey,
      summary: times == null || times <= 0
          ? '填写月周转次数后自动算'
          : '月周转 ${_wan(times)} 次 · 年化规模 ÷ 12 ÷ 次数',
      value: cash == null ? '—' : '${_wan(cash)} 万',
      review: config.reviewToggle?.call('turnoverCash'),
      collapsedReview: config.reviewStatus?.call('turnoverCash'),
      forceOpen:
          config.focusKeys.contains('turnoverTimes') ||
          config.focusKeys.contains('turnoverCash'),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?config.turnoverField,
          _Trace(
            formula: '周转资金 = 年化规模 ÷ 12 ÷ 月周转次数',
            substitution: cash == null || times == null || times <= 0
                ? ''
                : '${_wan(config.evaluation.salesScale)} ÷ 12 ÷ ${_wan(times)} = ${_wan(cash)} 万元',
          ),
        ],
      ),
    );
  }
}

/// 复核 key 与成本类的对应。
abstract final class ProposalFinanceFormulaBoardKeys {
  static String reviewKeyOf(String categoryKey) => switch (categoryKey) {
    kProposalCostCategoryProject => 'costItems',
    kProposalCostCategoryBusiness => 'businessCost',
    kProposalCostCategoryOperating => 'operatingCost',
    kProposalCostCategoryTax => 'taxCost',
    _ => categoryKey,
  };
}

/// 成本构成条：四类成本按金额占比排成一条，下面一行图例。
class _CompositionBar extends StatelessWidget {
  const _CompositionBar({required this.parts});

  final List<(String, double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final positive = [
      for (final part in parts)
        if (part.$2 > 0) part,
    ];
    final total = positive.fold<double>(0, (sum, part) => sum + part.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: total <= 0
                ? Container(color: _surface(context, const Color(0xFFDCD6EA)))
                : Row(
                    children: [
                      for (var i = 0; i < positive.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: (positive[i].$2 / total * 1000).round().clamp(1, 1000),
                          child: Container(color: _c(context, positive[i].$3)),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final part in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _c(context, part.$3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(part.$1, style: _sans(context, size: 11, color: _K.text2)),
                  const SizedBox(width: 4),
                  Text(_wan(part.$2), style: _mono(context, size: 11)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _CategoryDetail extends StatelessWidget {
  const _CategoryDetail({
    required this.bucket,
    required this.editable,
    this.onItemsChanged,
    this.onFormula,
    this.promotionPlan = const ProposalPromotionTierPlan(),
    this.onPromotionTiers,
  });

  final ProposalFinanceBucket bucket;
  final bool editable;
  final ValueChanged<List<String>>? onItemsChanged;
  final void Function(String name, String code)? onFormula;
  final ProposalPromotionTierPlan promotionPlan;
  final ValueChanged<ProposalPromotionTierPlan>? onPromotionTiers;

  ProposalCostCategory get category => bucket.category;

  Future<void> _pick(BuildContext context) async {
    final locked = {
      for (final line in bucket.lines)
        if (line.locked) line.name,
    };
    final next = await showProposalCostItemPicker(
      context,
      category: category,
      selected: bucket.names,
      locked: locked,
    );
    if (next == null) return;
    onItemsChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final line in bucket.lines)
        _CostLine(
          category: category,
          line: line,
          onRemove: editable && !line.locked && onItemsChanged != null
              ? () => onItemsChanged!([
                  for (final name in bucket.names)
                    if (name != line.name) name,
                ])
              : null,
          onFormula: onFormula == null || line.locked
              ? null
              : (code) => onFormula!(line.name, code),
          promotionPlan: promotionPlan,
          onPromotionTiers: onPromotionTiers,
        ),
      if (editable)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_pick(context)),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(bucket.lines.isEmpty ? '选择${category.name}项' : '增减成本项'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: _c(context, ProposalPalette.purpleDeep),
                side: BorderSide(color: _border(context, ProposalPalette.border)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// 一个成本项：产品结算带出的只写「出处 + 代入」，其余可选公式。
class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.category,
    required this.line,
    this.onRemove,
    this.onFormula,
    this.promotionPlan = const ProposalPromotionTierPlan(),
    this.onPromotionTiers,
  });

  final ProposalCostCategory category;
  final ProposalFinanceLine line;
  final VoidCallback? onRemove;
  final ValueChanged<String>? onFormula;
  final ProposalPromotionTierPlan promotionPlan;
  final ValueChanged<ProposalPromotionTierPlan>? onPromotionTiers;

  @override
  Widget build(BuildContext context) {
    final item = category.resolveItem(line.name);
    final formula = line.formula;
    final canChoose = onFormula != null && item.formulas.length > 1;
    final head = Row(
      children: [
        Flexible(
          child: Text(
            line.name,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 12.5, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        if (line.locked)
          const ProposalFinanceTag('产品结算', color: ProposalPalette.green, fill: ProposalPalette.greenSoft)
        else if (item.tiered)
          line.pending
              ? const ProposalFinanceTag('阶梯 · 未配置', color: ProposalPalette.amber, fill: ProposalPalette.amberSoft)
              : const ProposalFinanceTag('阶梯', color: ProposalPalette.purpleDeep, fill: ProposalPalette.purpleSoft),
        const Spacer(),
        Text(
          line.pending ? '—' : '${_wan(line.amount)} 万',
          style: _mono(context, size: 12.5, color: line.pending ? _K.grey : _K.ink),
        ),
        if (onRemove != null)
          IconButton(
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 16, color: _c(context, _K.grey)),
          )
        else
          const SizedBox(width: 8),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: _surface(context, Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border(context, ProposalPalette.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (line.source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line.source, style: _sans(context, size: 11, color: _K.grey)),
            ),
          if (canChoose)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: ProposalSelectField<String>(
                value: formula?.code,
                title: '${line.name} 计算公式',
                hint: '选择公式',
                allowClear: false,
                options: [
                  for (final f in item.formulas)
                    ProposalSelectOption(
                      value: f.code,
                      label: f.name,
                      meta: f.detail.isEmpty ? null : f.detail,
                    ),
                ],
                onSelected: (value) {
                  if (value != null) onFormula!(value);
                },
              ),
            )
          else if (!line.locked && !line.pending && formula != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(formula.name, style: _sans(context, size: 11, color: _K.grey)),
            ),
          _Trace(
            // 产品结算带出的不再写公式（出处已经说明），只写代入。
            formula: line.locked || formula == null || formula.expression == formula.name
                ? ''
                : formula.expression,
            substitution: line.substitution,
          ),
          if (item.tiered && !line.locked)
            _PromotionTierEditor(
              plan: promotionPlan,
              hit: line.tierHit,
              onChanged: onPromotionTiers,
            ),
          _Missing(line.missing),
        ],
      ),
    );
  }
}

/// 推广费阶梯编辑：计量（按月 / 按年规模）、计费（全额 / 超额累进）、档位表。
/// 只读时同一张表，命中的档位高亮。
class _PromotionTierEditor extends StatelessWidget {
  const _PromotionTierEditor({
    required this.plan,
    required this.hit,
    this.onChanged,
  });

  final ProposalPromotionTierPlan plan;
  final int hit;
  final ValueChanged<ProposalPromotionTierPlan>? onChanged;

  bool get editable => onChanged != null;

  Widget _segment(
    BuildContext context,
    String title,
    List<(String, String)> options,
    String value,
    ValueChanged<String> onPick,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(title, style: _sans(context, size: 11, color: _K.grey)),
        ),
        for (final (code, label) in options) ...[
          ProposalChoiceChip(
            label: label,
            selected: value == code,
            enabled: editable,
            onSelected: editable ? (_) => onPick(code) : null,
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  void _setTier(int index, {double? from, double? rate}) {
    final tiers = [...plan.sorted];
    tiers[index] = ProposalPromotionTier(
      from: from ?? tiers[index].from,
      rate: rate ?? tiers[index].rate,
    );
    onChanged?.call(plan.copyWith(tiers: tiers));
  }

  @override
  Widget build(BuildContext context) {
    final tiers = plan.sorted;
    final unit = plan.monthly ? '月规模' : '年规模';
    Widget cell(String text, {bool head = false, bool strong = false}) => Text(
      text,
      style: head
          ? _sans(context, size: 11, color: _K.grey)
          : _mono(
              context,
              size: 12,
              weight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
    );
    Widget input(String key, double value, ValueChanged<double> onValue) =>
        SizedBox(
          height: 32,
          child: TextFormField(
            key: ValueKey(key),
            initialValue: proposalFormatWan(value),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: _mono(context, size: 12, weight: FontWeight.w500),
            decoration: proposalInputDecoration(context: context, hint: '0'),
            onChanged: (text) => onValue(double.tryParse(text.trim()) ?? 0),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _surface(context, ProposalPalette.soft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _segment(
            context,
            '计量',
            const [('monthly', '按月规模'), ('annual', '按年规模')],
            plan.basis,
            (code) => onChanged?.call(plan.copyWith(basis: code)),
          ),
          const SizedBox(height: 6),
          _segment(
            context,
            '计费',
            const [('whole', '全额累进'), ('excess', '超额累进')],
            plan.mode,
            (code) => onChanged?.call(plan.copyWith(mode: code)),
          ),
          const SizedBox(height: 4),
          Text(
            plan.excess
                ? '超额累进：每一段规模按各自档位比例计，再加总。'
                : '全额累进：$unit落在哪一档，整笔按该档比例计。',
            style: _sans(context, size: 11, color: _K.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 40, child: cell('档位', head: true)),
              Expanded(child: cell('$unit ≥（万元）', head: true)),
              const SizedBox(width: 8),
              Expanded(child: cell('比例（%）', head: true)),
              SizedBox(width: editable ? 28 : 0),
            ],
          ),
          if (tiers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                editable ? '还没有档位，点下面「添加档位」' : '未配置档位',
                style: _sans(context, size: 11.5, color: _K.grey),
              ),
            ),
          for (var i = 0; i < tiers.length; i++)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: i == hit
                    ? _surface(context, ProposalPalette.purpleSoft)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: cell('${i + 1}${i == hit ? ' ✓' : ''}', strong: i == hit),
                  ),
                  Expanded(
                    child: editable
                        ? input(
                            'from-$i-${tiers.length}',
                            tiers[i].from,
                            (v) => _setTier(i, from: v),
                          )
                        : cell(proposalFormatWan(tiers[i].from), strong: i == hit),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: editable
                        ? input(
                            'rate-$i-${tiers.length}',
                            tiers[i].rate,
                            (v) => _setTier(i, rate: v),
                          )
                        : cell('${proposalFormatWan(tiers[i].rate)}%', strong: i == hit),
                  ),
                  if (editable)
                    IconButton(
                      tooltip: '删除这一档',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => onChanged?.call(
                        plan.copyWith(tiers: [...tiers]..removeAt(i)),
                      ),
                      icon: Icon(Icons.close_rounded, size: 15, color: _c(context, _K.grey)),
                    ),
                ],
              ),
            ),
          if (editable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final last = tiers.isEmpty ? null : tiers.last;
                    onChanged?.call(
                      plan.copyWith(
                        tiers: [
                          ...tiers,
                          ProposalPromotionTier(
                            from: last == null ? 0 : last.from + 10,
                            rate: last?.rate ?? 0,
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('添加档位'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _c(context, ProposalPalette.purpleDeep),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 成本项多选：勾选后点「确定」一次写回。增值税两种口径互斥；产品结算带出的项不可取消。
Future<List<String>?> showProposalCostItemPicker(
  BuildContext context, {
  required ProposalCostCategory category,
  required List<String> selected,
  Set<String> locked = const {},
}) {
  final names = <String>[
    for (final item in category.items) item.name,
    for (final name in selected)
      if (category.itemOf(name) == null) name,
  ];
  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) {
      final picked = <String>{...selected, ...locked};
      return StatefulBuilder(
        builder: (context, setState) {
          void toggle(String name, bool on) {
            setState(() {
              if (!on) {
                picked.remove(name);
                return;
              }
              final group = category.itemOf(name)?.exclusiveGroup ?? '';
              if (group.isNotEmpty) {
                picked.removeWhere(
                  (other) =>
                      other != name &&
                      category.itemOf(other)?.exclusiveGroup == group,
                );
              }
              picked.add(name);
            });
          }

          String? subtitleOf(String name) {
            if (locked.contains(name)) return '产品结算里已有，自动计入';
            final item = category.resolveItem(name);
            if (item.tiered) return '阶梯计费 · 选中后在推广费里配置档位';
            if (category.key == kProposalCostCategoryProject) {
              return '产品结算里还没有，需在上方补一行应付';
            }
            final parts = [
              if (item.hint.isNotEmpty) item.hint,
              if (item.formulas.isNotEmpty)
                '公式：${item.formulas.map((f) => f.name).join(' / ')}',
            ];
            return parts.isEmpty ? null : parts.join(' · ');
          }

          return AlertDialog(
            title: Text('选择${category.name}项'),
            contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (category.hint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(category.hint, style: _sans(context, size: 12, color: _K.grey)),
                    ),
                  for (final name in names)
                    CheckboxListTile(
                      dense: true,
                      value: picked.contains(name),
                      onChanged: locked.contains(name)
                          ? null
                          : (on) => toggle(name, on == true),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(name),
                      subtitle: subtitleOf(name) == null ? null : Text(subtitleOf(name)!),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop([
                  for (final name in names)
                    if (picked.contains(name)) name,
                ]),
                child: Text('确定（${picked.length}）'),
              ),
            ],
          );
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// 利润
// ---------------------------------------------------------------------------

class ProposalFinanceProfitPanel extends StatelessWidget {
  const ProposalFinanceProfitPanel({super.key, required this.config});

  final ProposalFinanceBoardConfig config;

  @override
  Widget build(BuildContext context) {
    final eval = config.evaluation;
    final sealed = config.businessSealed;
    final profit = eval.profit;
    final margin = eval.margin;
    final revenue = eval.revenue;

    final band = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text.rich(
              TextSpan(
                text: sealed ? '—' : _wan(profit),
                style: _mono(
                  context,
                  size: 18,
                  color: sealed ? _K.grey : _K.red,
                ),
                children: [
                  TextSpan(
                    text: ' 万 · 年化利润',
                    style: _sans(context, size: 11, color: _K.grey),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (!sealed && margin != null)
              ProposalFinanceTag(
                '毛利率 ${_wan(margin)}%',
                color: margin < 0 ? _K.red : _K.heroInk,
                fill: const Color(0xFFDCE4F6),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          sealed
              ? '利润含业务成本，负责人二不可查看'
              : '= 收入 ${_wan(revenue.amount)} − 成本 ${_wan(eval.costTotal)}',
          style: _mono(context, size: 11.5, weight: FontWeight.w500, color: _K.text2),
        ),
      ],
    );

    final revenueRow = config.wrap(
      'revenue',
      ProposalFinanceRow(
        title: '收入',
        accent: ProposalPalette.purple,
        summary: revenue.formula?.name ?? '未选收入公式',
        value: '${_wan(revenue.amount)} 万',
        tag: revenue.missing.isEmpty
            ? null
            : const ProposalFinanceTag('有缺项', color: ProposalPalette.amber, fill: ProposalPalette.amberSoft),
        review: config.reviewToggle?.call('revenue'),
        collapsedReview: config.reviewStatus?.call('revenue'),
        forceOpen: config.focusKeys.contains('revenue'),
        detail: _RevenueDetail(config: config),
      ),
    );
    final profitRow = config.wrap(
      'profit',
      ProposalFinanceRow(
        title: '利润',
        accent: _K.red,
        summary: '收入 − 项目 − 业务 − 经营 − 税务',
        value: sealed ? '—' : '${_wan(profit)} 万',
        valueColor: !sealed && profit < 0 ? _K.red : _K.ink,
        review: config.reviewToggle?.call('profit'),
        collapsedReview: config.reviewStatus?.call('profit'),
        forceOpen: config.focusKeys.contains('profit'),
        detail: sealed
            ? null
            : _Trace(
                formula: config.catalog.profitFormula.expression,
                substitution: eval.profitSubstitution,
              ),
      ),
    );
    final marginRow = config.wrap(
      'margin',
      ProposalFinanceRow(
        title: '毛利率',
        accent: _K.heroInk,
        summary: '利润 ÷ 年化规模',
        value: sealed || margin == null ? '—' : '${_wan(margin)}%',
        valueColor: !sealed && margin != null && margin < 0 ? _K.red : _K.ink,
        forceOpen: config.focusKeys.contains('margin'),
        detail: sealed
            ? null
            : _Trace(
                formula: config.catalog.marginFormula.expression,
                substitution: eval.marginSubstitution,
              ),
      ),
    );
    return config.wrap(
      kProposalFinanceProfitAnchor,
      ProposalFinanceBlockShell(
        icon: Icons.savings_outlined,
        title: '利润',
        tint: _K.profitBg,
        band: band,
        rows: [revenueRow, profitRow, marginRow],
      ),
    );
  }
}

class _RevenueDetail extends StatelessWidget {
  const _RevenueDetail({required this.config});

  final ProposalFinanceBoardConfig config;

  @override
  Widget build(BuildContext context) {
    final eval = config.evaluation;
    final line = eval.revenue;
    final formula = line.formula;
    final group = eval.revenueGroup;
    final groups = eval.revenueGroups;
    final editable = config.revenueEditable && config.onRevenueFormula != null;
    final caption = [
      group == null ? '产品还没选业务平台，列出全部渠道侧公式' : '渠道侧公式 · ${group.name}',
      config.catalog.isFallback ? '资管快照' : '资管实时',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(caption, style: _sans(context, size: 11, color: _K.grey)),
        const SizedBox(height: 6),
        if (editable)
          ProposalSelectField<String>(
            value: formula == null || group == null ? null : '${group.key}|${formula.code}',
            title: '收入计算公式',
            hint: '选择收入计算公式',
            searchable: true,
            allowClear: false,
            options: [
              for (final g in groups)
                for (final f in g.formulas)
                  ProposalSelectOption(
                    value: '${g.key}|${f.code}',
                    label: f.name,
                    meta: [
                      if (groups.length > 1) g.name,
                      '编码 ${f.code}',
                      if (f.settleMethodName.isNotEmpty) f.settleMethodName,
                      if (f.detail.isNotEmpty) f.detail,
                    ].join(' · '),
                  ),
            ],
            onSelected: (value) {
              if (value == null || !value.contains('|')) return;
              final cut = value.indexOf('|');
              config.onRevenueFormula!(value.substring(0, cut), value.substring(cut + 1));
            },
          )
        else
          Text(
            formula == null ? '未选择收入公式' : '${formula.name}（编码 ${formula.code}）',
            style: _sans(context, size: 12.5, weight: FontWeight.w600),
          ),
        _Trace(
          formula: formula == null || formula.detail.isEmpty ? '' : '公式：${formula.expression}',
          substitution: line.substitution,
        ),
        _Missing(line.missing),
      ],
    );
  }
}
