import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'proposal_cost_estimate.dart';
import 'proposal_finance_formula.dart';
import 'proposal_intake_select.dart';
import 'proposal_intake_ui.dart';

/// 测算金额、代入过程是否显示。先屏蔽，财务部分只显示每个产品选的收入公式和成本公式；
/// 改成 true 即恢复金额、代入、构成条和「利润」块。
const kProposalFinanceShowEstimates = false;

/// 财务部下半部分：按产品列出收入公式和成本公式，视觉上与顶部年化测算 hero 一致。
///
/// 每个产品一行「1、xxx 产品」，展开后依次是收入公式、项目成本（推广费下一个推广商：固定比例或连续月序）、
/// 业务成本、税务成本；下面是整单的经营成本类型和周转资金。
/// 顶部 hero 点「成本 / 收入 …」会跳到这里。
///
/// 谁能改什么由页面按角色传进 [ProposalFinanceBoardConfig]：
/// - 填写人：收入公式、项目 / 税务成本、经营成本类型（产品结算里已有的项目成本自动带出、锁定）；
/// - 财务部负责人二：同上并按产品逐条复核；业务成本与利润对其加密；
/// - 市场部负责人一：财务复核时按产品选业务成本；
/// - 其他人：只读。
class ProposalFinanceBoardConfig {
  const ProposalFinanceBoardConfig({
    required this.evaluation,
    required this.catalog,
    this.products = const [],
    this.revenueEditable = false,
    this.categoryEditable = const {},
    this.productEditable,
    this.businessSealed = false,
    this.businessWaitingText = '由市场部负责人一在财务复核时选择',
    this.roleNote = '',
    this.reviewToggle,
    this.reviewStatus,
    this.onPromotionPlans,
    this.onRevenueFormula,
    this.onCostItemsChanged,
    this.onCostFormula,
    this.operatingItems = const [],
    this.onOperatingItems,
    this.anchor,
    this.focusKeys = const {},
    this.turnoverCash,
    this.turnoverTimes,
    this.turnoverField,
    this.showEstimates = kProposalFinanceShowEstimates,
  });

  /// 主产品组的加总测算（利润块、构成条用）。
  final ProposalFinanceEvaluation evaluation;
  final ProposalFinanceFormulaCatalog catalog;

  /// 全部产品（主产品在前、子产品在后），按这个顺序编号。
  final List<ProposalProductFinanceEvaluation> products;
  final bool revenueEditable;

  /// 每类成本当前用户能不能改，key 为 [ProposalCostCategory.key]。
  final Map<String, bool> categoryEditable;

  /// 某个产品的某一段能不能改（该产品这一段复核过就锁）。key 为 `revenue` 或成本类 key；
  /// 与 [revenueEditable] / [categoryEditable] 同时满足才可改。
  final bool Function(String skuId, String key)? productEditable;

  bool canEditProduct(String skuId, String key) {
    final global = key == 'revenue'
        ? revenueEditable
        : categoryEditable[key] == true;
    return global && (productEditable?.call(skuId, key) ?? true);
  }

  /// 业务成本对当前用户加密（财务部负责人二）。利润、毛利率同样不显示。
  final bool businessSealed;
  final String businessWaitingText;

  /// 一句话说明当前用户在这块能做什么。
  final String roleNote;

  /// 行内复核控件。key：按产品的 `sku:<skuId>:revenue|costItems|taxCost`、
  /// 整个产品的 `sku:<skuId>`（只用于收起时的状态），以及 operatingCost / turnoverCash / profit。
  final Widget? Function(String key)? reviewToggle;

  /// 收起时显示的复核状态（只读小标签）；展开后才出现复核按钮，页面保持整洁。
  final Widget? Function(String key)? reviewStatus;

  /// 推广费方案写回（按产品，一个推广商）。
  final void Function(String skuId, List<ProposalPromotionTierPlan> plans)?
  onPromotionPlans;
  final void Function(String skuId, String groupKey, String code)?
  onRevenueFormula;
  final void Function(
    String skuId,
    ProposalCostCategory category,
    List<String> names,
  )?
  onCostItemsChanged;
  final void Function(
    String skuId,
    ProposalCostCategory category,
    String name,
    String code,
  )?
  onCostFormula;

  /// 经营成本类型（整单一份，只选类型）。
  final List<String> operatingItems;
  final ValueChanged<List<String>>? onOperatingItems;

  final bool showEstimates;

  /// 页面的字段锚点：顶部 hero 跳转、闪烁定位都靠它。
  final Widget Function(String key, Widget child)? anchor;

  /// 正在被跳转定位的锚点 key：命中的行自动展开。
  final Set<String> focusKeys;

  final double? turnoverCash;
  final double? turnoverTimes;

  /// 「月周转次数」输入（或只读值），由页面按权限构建。
  final Widget? turnoverField;

  Widget wrap(String key, Widget child) => anchor?.call(key, child) ?? child;

  Widget wrapAll(Iterable<String> keys, Widget child) {
    var out = child;
    for (final key in keys) {
      out = wrap(key, out);
    }
    return out;
  }
}

String proposalFinanceProductReviewKey(String skuId, String kind) =>
    'sku:$skuId:$kind';

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
    super.key,
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
    this.titleWidth = 132,
  });

  final String title;
  final double titleWidth;
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
        Flexible(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 12.5, weight: FontWeight.w700),
          ),
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
              SizedBox(width: widget.titleWidth, child: title),
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
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
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
    final products = config.products;

    final band = !config.showEstimates
        ? Text(
            products.isEmpty
                ? '请先在科技部添加业务产品'
                : '共 ${products.length} 个产品 · 按产品选择收入公式和成本公式',
            style: _sans(context, size: 11.5, color: _K.text2),
          )
        : Column(
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
      for (var i = 0; i < products.length; i++)
        i == 0
            // hero 跳「收入 / 各类成本」时落到第一个产品。
            ? config.wrapAll(const [
                'revenue',
                'costItems',
                'businessCost',
                'taxCost',
              ], _productRow(context, i, products[i]))
            : _productRow(context, i, products[i]),
      config.wrap('operatingCost', _operatingRow(context)),
      config.wrap('turnoverTimes', _turnoverRow(context)),
    ];
    return config.wrapAll(
      [
        kProposalFinanceCostAnchor,
        // 利润块屏蔽时，hero 跳「利润 / 毛利率」落到这里。
        if (!config.showEstimates) ...[
          kProposalFinanceProfitAnchor,
          'profit',
          'margin',
        ],
      ],
      ProposalFinanceBlockShell(
        icon: Icons.receipt_long_outlined,
        title: config.showEstimates ? '成本' : '收入与成本公式',
        band: band,
        rows: rows,
      ),
    );
  }

  Widget _productRow(
    BuildContext context,
    int index,
    ProposalProductFinanceEvaluation product,
  ) {
    final eval = product.evaluation;
    final sealed = config.businessSealed;
    int count(String key) => eval.bucket(key)?.lines.length ?? 0;
    final summary = [
      eval.revenue.formula?.name ?? '未选收入公式',
      '项目 ${count(kProposalCostCategoryProject)} 项',
      sealed ? '业务 已加密' : '业务 ${count(kProposalCostCategoryBusiness)} 项',
      '税务 ${count(kProposalCostCategoryTax)} 项',
    ].join(' · ');
    final hasIssue =
        config.showEstimates &&
        (eval.revenue.missing.isNotEmpty ||
            eval.buckets.values.any(
              (b) => b.lines.any((line) => line.missing.isNotEmpty),
            ));
    return ProposalFinanceRow(
      key: ValueKey('finance-product-${product.skuId}'),
      title: '${index + 1}、${product.name}',
      titleWidth: 220,
      accent: product.isChild ? _K.business : ProposalPalette.purple,
      summary: summary,
      value: config.showEstimates ? '${_wan(eval.revenue.amount)} 万' : '',
      tag: hasIssue
          ? const ProposalFinanceTag('有缺项', color: ProposalPalette.amber, fill: ProposalPalette.amberSoft)
          : ProposalFinanceTag(product.isChild ? '子产品' : '主产品'),
      collapsedReview: config.reviewStatus?.call('sku:${product.skuId}'),
      initiallyOpen: config.products.length == 1,
      detail: _ProductDetail(config: config, product: product),
    );
  }

  Widget _operatingRow(BuildContext context) {
    final category = config.catalog.category(kProposalCostCategoryOperating);
    final items = config.operatingItems;
    final editable =
        category != null &&
        config.categoryEditable[kProposalCostCategoryOperating] == true &&
        config.onOperatingItems != null;
    return ProposalFinanceRow(
      title: '经营成本',
      accent: _K.operating,
      summary: items.isEmpty
          ? (editable ? '点开选择类型' : '未选择')
          : items.join('、'),
      value: '',
      tag: const ProposalFinanceTag('只选类型'),
      review: config.reviewToggle?.call('operatingCost'),
      collapsedReview: config.reviewStatus?.call('operatingCost'),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (items.isEmpty)
                Text('未选择', style: _sans(context, size: 12, color: _K.grey)),
              for (final name in items) ProposalFinanceTag(name),
            ],
          ),
      if (editable)
        Padding(
          padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PickButton(
                  label: items.isEmpty ? '选择经营成本类型' : '增减类型',
                  onPressed: () async {
                    final next = await showProposalCostItemPicker(
                      context,
                      category: category,
                      selected: items,
                      allowCustom: true,
                    );
                    if (next != null) config.onOperatingItems!(next);
                  },
                ),
              ),
            ),
        ],
      ),
    );
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
    required this.showEstimates,
    this.allowItemEdit = true,
    this.onItemsChanged,
    this.onFormula,
    this.promotionPlans = const [],
    this.onPromotionPlans,
  });

  final ProposalFinanceBucket bucket;
  final bool editable;
  final bool showEstimates;
  final bool allowItemEdit;
  final ValueChanged<List<String>>? onItemsChanged;
  final void Function(String name, String code)? onFormula;
  final List<ProposalPromotionTierPlan> promotionPlans;
  final ValueChanged<List<ProposalPromotionTierPlan>>? onPromotionPlans;

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
          onRemove: allowItemEdit && !line.locked && onItemsChanged != null
              ? () => onItemsChanged!([
                  for (final name in bucket.names)
                    if (name != line.name) name,
                ])
              : null,
          onFormula: onFormula == null || line.locked
              ? null
              : (code) => onFormula!(line.name, code),
          showEstimates: showEstimates,
          promotionPlans: promotionPlans,
          onPromotionPlans: onPromotionPlans,
        ),
      if (bucket.lines.isEmpty && !allowItemEdit)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            category.key == kProposalCostCategoryProject
                ? '跟着产品结算，在采购（成本）里填写后自动带出'
                : '未选择',
            style: _sans(context, size: 12, color: _K.grey),
          ),
        ),
      if (allowItemEdit)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _PickButton(
              label: bucket.lines.isEmpty ? '选择${category.name}项' : '增减成本项',
              onPressed: () => _pick(context),
            ),
          ),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => unawaited(onPressed()),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: _c(context, ProposalPalette.purpleDeep),
        side: BorderSide(color: _border(context, ProposalPalette.border)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

/// 一个产品展开后的内容：收入公式 → 项目成本 → 业务成本 → 税务成本，每段旁边是这段的复核。
class _ProductDetail extends StatelessWidget {
  const _ProductDetail({required this.config, required this.product});

  final ProposalFinanceBoardConfig config;
  final ProposalProductFinanceEvaluation product;

  Widget _section(
    BuildContext context, {
    required String title,
    required Color color,
    required Widget child,
    String reviewKind = '',
    String trailing = '',
  }) {
    final review = reviewKind.isEmpty
        ? null
        : config.reviewToggle?.call(
            proposalFinanceProductReviewKey(product.skuId, reviewKind),
          );
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: _c(context, color), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: _sans(context, size: 12, weight: FontWeight.w700, color: _K.text2),
              ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(trailing, style: _mono(context, size: 12)),
              ],
              const Spacer(),
              ?review,
            ],
          ),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eval = product.evaluation;
    final skuId = product.skuId;
    final show = config.showEstimates;
    final children = <Widget>[
      _section(
        context,
        title: '收入',
        color: ProposalPalette.purple,
        reviewKind: 'revenue',
        trailing: show ? '${_wan(eval.revenue.amount)} 万' : '',
        child: _RevenueFormulaPicker(
          config: config,
          evaluation: eval,
          onRevenueFormula:
              config.canEditProduct(skuId, 'revenue') &&
                  config.onRevenueFormula != null
              ? (group, code) => config.onRevenueFormula!(skuId, group, code)
              : null,
        ),
      ),
    ];
    for (final key in kProposalCostCategoryOrder) {
      final bucket = eval.bucket(key);
      if (bucket == null) continue;
      final category = bucket.category;
      final sealed =
          config.businessSealed && key == kProposalCostCategoryBusiness;
      final editable =
          config.canEditProduct(skuId, key) &&
          config.onCostItemsChanged != null &&
          !sealed;
      children.add(
        _section(
          context,
          title: category.name,
          color: _categoryColor(key),
          reviewKind: key == kProposalCostCategoryBusiness
              ? ''
              : ProposalFinanceFormulaBoardKeys.reviewKeyOf(key),
          trailing: show && !sealed ? '${_wan(bucket.total)} 万' : '',
          child: sealed
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '已加密，负责人二不可查看',
                    style: _sans(context, size: 12, color: _K.grey),
                  ),
                )
              : bucket.lines.isEmpty && !editable &&
                    key == kProposalCostCategoryBusiness
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    config.businessWaitingText,
                    style: _sans(context, size: 12, color: _K.grey),
                  ),
                )
              : _CategoryDetail(
                  bucket: bucket,
                  editable: editable,
                  // 项目成本只跟产品结算的应付行走，财务模块不能再增删。
                  allowItemEdit:
                      editable && key != kProposalCostCategoryProject,
                  showEstimates: show,
                  onItemsChanged: editable && key != kProposalCostCategoryProject
                      ? (names) =>
                            config.onCostItemsChanged!(skuId, category, names)
                      : null,
                  onFormula: config.onCostFormula == null || !editable
                      ? null
                      : (name, code) =>
                            config.onCostFormula!(skuId, category, name, code),
                  promotionPlans: product.promotionPlans,
                  onPromotionPlans:
                      editable && config.onPromotionPlans != null
                      ? (plans) => config.onPromotionPlans!(skuId, plans)
                      : null,
                ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// 收入公式：可改时是下拉（按产品业务平台筛过的渠道侧公式），只读时写公式名和编码。
class _RevenueFormulaPicker extends StatelessWidget {
  const _RevenueFormulaPicker({
    required this.config,
    required this.evaluation,
    this.onRevenueFormula,
  });

  final ProposalFinanceBoardConfig config;
  final ProposalFinanceEvaluation evaluation;
  final void Function(String groupKey, String code)? onRevenueFormula;

  @override
  Widget build(BuildContext context) {
    final line = evaluation.revenue;
    final formula = line.formula;
    final group = evaluation.revenueGroup;
    final groups = evaluation.revenueGroups;
    final show = config.showEstimates;
    final caption = [
      group == null ? '产品还没选业务平台，列出全部渠道侧公式' : '渠道侧公式 · ${group.name}',
      config.catalog.isFallback ? '资管快照' : '资管实时',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(caption, style: _sans(context, size: 11, color: _K.grey)),
        ),
        if (onRevenueFormula != null)
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
              onRevenueFormula!(value.substring(0, cut), value.substring(cut + 1));
            },
          )
        else
          Text(
            formula == null ? '未选择收入公式' : '${formula.name}（编码 ${formula.code}）',
            style: _sans(context, size: 12.5, weight: FontWeight.w600),
          ),
        if (show) ...[
          _Trace(
            formula: formula == null || formula.detail.isEmpty ? '' : '公式：${formula.expression}',
            substitution: line.substitution,
          ),
          _Missing(line.missing),
        ],
      ],
    );
  }
}

/// 一个成本项：产品结算带出的只写「出处 + 代入」，其余可选公式。
class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.category,
    required this.line,
    required this.showEstimates,
    this.onRemove,
    this.onFormula,
    this.promotionPlans = const [],
    this.onPromotionPlans,
  });

  final ProposalCostCategory category;
  final ProposalFinanceLine line;
  final bool showEstimates;
  final VoidCallback? onRemove;
  final ValueChanged<String>? onFormula;
  final List<ProposalPromotionTierPlan> promotionPlans;
  final ValueChanged<List<ProposalPromotionTierPlan>>? onPromotionPlans;

  @override
  Widget build(BuildContext context) {
    final item = category.resolveItem(line.name);
    final formula = line.formula;
    final canChoose = onFormula != null && item.formulas.length > 1;
    if (!showEstimates && !item.tiered && !canChoose) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Flexible(
              child: Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 12.5, weight: FontWeight.w600),
              ),
            ),
            if (line.locked) ...[
              const SizedBox(width: 6),
              const ProposalFinanceTag(
                '产品结算',
                color: ProposalPalette.green,
                fill: ProposalPalette.greenSoft,
              ),
            ],
            if (formula != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '公式：${formula.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(context, size: 11, color: _K.grey),
                ),
              ),
            ] else
              const Spacer(),
            if (onRemove != null)
              IconButton(
                tooltip: '移除',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, size: 15, color: _c(context, _K.grey)),
              ),
          ],
        ),
      );
    }
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
              ? const ProposalFinanceTag('推广商 · 未配置', color: ProposalPalette.amber, fill: ProposalPalette.amberSoft)
              : ProposalFinanceTag(
                  promotionPlans.length > 1
                      ? '推广商 ${promotionPlans.length} 个'
                      : (promotionPlans.isEmpty
                            ? '月序配置'
                            : promotionPlans.first.fixed
                            ? '固定比例'
                            : promotionPlans.first.annual
                            ? '年阶梯'
                            : '月序配置'),
                  color: ProposalPalette.purpleDeep,
                  fill: ProposalPalette.purpleSoft,
                ),
        const Spacer(),
        if (showEstimates)
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
          else if (formula != null &&
              (!showEstimates || (!line.locked && !line.pending)))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                showEstimates ? formula.name : '公式：${formula.name}',
                style: _sans(context, size: 11, color: _K.grey),
              ),
            ),
          if (showEstimates)
            _Trace(
              // 产品结算带出的不再写公式（出处已经说明），只写代入。
              formula: line.locked || formula == null || formula.expression == formula.name
                  ? ''
                  : formula.expression,
              substitution: line.substitution,
            ),
          if (item.tiered)
            _PromotionPlansEditor(
              plans: promotionPlans,
              monthlyScale: showEstimates ? line.promotionMonthlyScale : null,
              onChanged: onPromotionPlans,
            ),
          if (showEstimates) _Missing(line.missing),
        ],
      ),
    );
  }
}

/// 推广费方案：每个产品配一个推广商，选按固定比例、年阶梯或连续月序配置。
class _PromotionPlansEditor extends StatelessWidget {
  const _PromotionPlansEditor({
    required this.plans,
    this.monthlyScale,
    this.onChanged,
  });

  final List<ProposalPromotionTierPlan> plans;
  final double? monthlyScale;
  final ValueChanged<List<ProposalPromotionTierPlan>>? onChanged;

  bool get editable => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final plan = plans.isEmpty ? null : plans.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan == null && !editable)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('未配置推广商方案', style: _sans(context, size: 11.5, color: _K.grey)),
          ),
        if (plan != null)
          _PromotionPlanEditor(
            key: ValueKey('promotion-plan-${plan.id}'),
            plan: plan,
            monthlyScale: monthlyScale,
            onChanged: editable ? (next) => onChanged?.call([next]) : null,
            onRemove: editable ? () => onChanged?.call(const []) : null,
          ),
        if (editable && plans.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onChanged?.call([
                  ProposalPromotionTierPlan(
                    id: proposalPromotionPlanNextId(plans),
                    segments: ProposalPromotionTierPlan.monthSeqSegments,
                  ),
                ]),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('配置推广商'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: _c(context, ProposalPalette.purpleDeep),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _promotionChoices(
  BuildContext context, {
  required String title,
  required List<(String, String)> options,
  required String value,
  ValueChanged<String>? onPick,
}) {
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
          enabled: onPick != null,
          onSelected: onPick == null ? null : (_) => onPick(code),
        ),
        const SizedBox(width: 6),
      ],
    ],
  );
}

Widget _promotionInput(
  BuildContext context, {
  required String key,
  required String initial,
  required String hint,
  required ValueChanged<String> onText,
  bool integer = false,
}) {
  return SizedBox(
    height: 32,
    child: TextFormField(
      key: ValueKey(key),
      initialValue: initial,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      style: _mono(context, size: 12, weight: FontWeight.w500),
      decoration: proposalInputDecoration(context: context, hint: hint),
      onChanged: (text) => onText(text.trim()),
    ),
  );
}

Widget _promotionAddButton(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: _c(context, ProposalPalette.purpleDeep),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

Widget _promotionRemoveButton(
  BuildContext context, {
  required String tooltip,
  required VoidCallback onPressed,
  IconData icon = Icons.close_rounded,
}) {
  return IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    onPressed: onPressed,
    icon: Icon(icon, size: 16, color: _c(context, _K.grey)),
  );
}

/// 一个推广商的方案：推广商名称、策略（按固定比例 / 年阶梯 / 连续月序配置）。
class _PromotionPlanEditor extends StatelessWidget {
  const _PromotionPlanEditor({
    super.key,
    required this.plan,
    this.monthlyScale,
    this.onChanged,
    this.onRemove,
  });

  final ProposalPromotionTierPlan plan;
  final double? monthlyScale;
  final ValueChanged<ProposalPromotionTierPlan>? onChanged;
  final VoidCallback? onRemove;

  bool get editable => onChanged != null;

  void _setSegments(List<ProposalPromotionSegment> segments) =>
      onChanged?.call(plan.copyWith(segments: segments));

  void _addSegment() {
    final segments = [...plan.segments];
    if (segments.isEmpty) {
      _setSegments(const [
        ProposalPromotionSegment(tiers: [ProposalPromotionTier(from: 0, rate: 0)]),
      ]);
      return;
    }
    final last = segments.last;
    if (last.toMonth == null) {
      segments[segments.length - 1] = last.copyWith(toMonth: last.fromMonth);
    }
    final start = (last.toMonth ?? last.fromMonth) + 1;
    segments.add(ProposalPromotionSegment(fromMonth: start, type: 'fixed'));
    _setSegments(segments);
  }

  @override
  Widget build(BuildContext context) {
    final id = plan.id;
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
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text('推广商', style: _sans(context, size: 11, color: _K.grey)),
              ),
              Expanded(
                child: editable
                    ? SizedBox(
                        height: 32,
                        child: TextFormField(
                          key: ValueKey('promotion-promoter-$id'),
                          initialValue: plan.promoter,
                          style: _sans(context, size: 12.5, weight: FontWeight.w700),
                          decoration: proposalInputDecoration(
                            context: context,
                            hint: '填写推广商名称',
                          ),
                          onChanged: (text) =>
                              onChanged?.call(plan.copyWith(promoter: text.trim())),
                        ),
                      )
                    : Text(
                        plan.label,
                        style: _sans(context, size: 12.5, weight: FontWeight.w700),
                      ),
              ),
              if (onRemove != null)
                _promotionRemoveButton(
                  context,
                  tooltip: '删除这个推广商方案',
                  icon: Icons.delete_outline_rounded,
                  onPressed: onRemove!,
                ),
            ],
          ),
          const SizedBox(height: 6),
          _promotionChoices(
            context,
            title: '策略',
            options: const [
              (kProposalPromotionStrategyFixed, '按固定比例'),
              (kProposalPromotionStrategyAnnual, '年阶梯'),
              (kProposalPromotionStrategyMonthSeq, '连续月序配置'),
            ],
            value: plan.strategy,
            onPick: editable
                ? (code) {
                    if (code == plan.strategy) return;
                    onChanged?.call(
                      plan.copyWith(
                        strategy: code,
                        segments: switch (code) {
                          kProposalPromotionStrategyFixed =>
                            ProposalPromotionTierPlan.fixedSegments,
                          kProposalPromotionStrategyAnnual =>
                            ProposalPromotionTierPlan.annualSegments,
                          _ => ProposalPromotionTierPlan.monthSeqSegments,
                        },
                      ),
                    );
                  }
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            plan.fixed
                ? '年化规模 × 比例；比例写小数，0.5 即 50%。'
                : plan.annual
                ? '按年化规模分档，只算一次，不分月份。档位单位万元，比例写小数，0.5 即 50%。'
                : '月规模 = 年化规模 ÷ 12；各月份段逐月计算，按 12 个月加总，没覆盖的月份按 0 计。档位单位万元，比例写小数。',
            style: _sans(context, size: 11, color: _K.grey),
          ),
          if (plan.fixed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text('比例', style: _sans(context, size: 11, color: _K.grey)),
                  ),
                  SizedBox(
                    width: 120,
                    child: editable
                        ? _promotionInput(
                            context,
                            key: 'promotion-$id-fixed-rate',
                            initial: proposalFormatPromotionRate(plan.fixedRate),
                            hint: '0.5',
                            onText: (text) => _setSegments([
                              ProposalPromotionSegment(
                                type: 'fixed',
                                rate: double.tryParse(text) ?? 0,
                              ),
                            ]),
                          )
                        : Text(
                            proposalFormatPromotionRate(plan.fixedRate),
                            style: _mono(context, size: 12, weight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            )
          else if (plan.annual)
            _PromotionSegmentEditor(
              keyPrefix: 'promotion-$id-annual',
              segment: plan.segments.isEmpty
                  ? ProposalPromotionTierPlan.annualSegments.first
                  : plan.segments.first,
              volume: monthlyScale == null ? null : monthlyScale! * 12,
              annualBasis: true,
              onChanged: editable ? (segment) => _setSegments([segment]) : null,
            )
          else ...[
            for (var i = 0; i < plan.segments.length; i++)
              _PromotionSegmentEditor(
                keyPrefix: 'promotion-$id-$i-${plan.segments.length}',
                segment: plan.segments[i],
                volume: monthlyScale,
                onChanged: editable
                    ? (segment) => _setSegments([...plan.segments]..[i] = segment)
                    : null,
                onRemove: editable && plan.segments.length > 1
                    ? () => _setSegments([...plan.segments]..removeAt(i))
                    : null,
              ),
            if (editable)
              _promotionAddButton(context, label: '添加月份段', onPressed: _addSegment),
          ],
        ],
      ),
    );
  }
}

int _promotionMonth(String text, {int fallback = 1}) {
  final n = int.tryParse(text) ?? fallback;
  if (n < 1) return 1;
  if (n > kProposalPromotionMonths) return kProposalPromotionMonths;
  return n;
}

/// 一段月份规则：第几到第几个月、阶梯或固定比例；阶梯档位单位万元，比例写小数。
class _PromotionSegmentEditor extends StatelessWidget {
  const _PromotionSegmentEditor({
    required this.keyPrefix,
    required this.segment,
    this.volume,
    this.annualBasis = false,
    this.onChanged,
    this.onRemove,
  });

  final String keyPrefix;
  final ProposalPromotionSegment segment;

  /// 拿来对档位的规模（万元）。月序配置是月规模，年阶梯是年化规模。
  final double? volume;

  /// 年阶梯：不写月份，档位按年化规模。
  final bool annualBasis;
  final ValueChanged<ProposalPromotionSegment>? onChanged;
  final VoidCallback? onRemove;

  bool get editable => onChanged != null;

  void _setTiers(List<ProposalPromotionTier> tiers) =>
      onChanged?.call(segment.copyWith(tiers: tiers));

  void _setTier(int index, {double? from, double? rate}) {
    final tiers = [...segment.sorted];
    tiers[index] = ProposalPromotionTier(
      from: from ?? tiers[index].from,
      rate: rate ?? tiers[index].rate,
    );
    _setTiers(tiers);
  }

  @override
  Widget build(BuildContext context) {
    final hit = volume == null ? -1 : segment.hitIndex(volume!);
    final tiers = segment.sorted;
    final openEnded = segment.toMonth == null;
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

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: BoxDecoration(
        color: _surface(context, Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border(context, ProposalPalette.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!annualBasis) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 6,
              children: [
                SizedBox(
                  width: 40,
                  child: Text('月份', style: _sans(context, size: 11, color: _K.grey)),
                ),
              Text('第', style: _sans(context, size: 11, color: _K.grey)),
              SizedBox(
                width: 48,
                child: editable
                    ? _promotionInput(
                        context,
                        key: '$keyPrefix-from-month',
                        initial: '${segment.fromMonth}',
                        hint: '1',
                        integer: true,
                        onText: (text) {
                          final from = _promotionMonth(text);
                          final to = segment.toMonth;
                          onChanged!(
                            segment.copyWith(
                              fromMonth: from,
                              toMonth: to == null || to >= from ? to : from,
                            ),
                          );
                        },
                      )
                    : Text(
                        '${segment.fromMonth}',
                        style: _mono(context, size: 12, weight: FontWeight.w700),
                      ),
              ),
              Text('个月至', style: _sans(context, size: 11, color: _K.grey)),
              if (!openEnded) ...[
                SizedBox(
                  width: 48,
                  child: editable
                      ? _promotionInput(
                          context,
                          key: '$keyPrefix-to-month',
                          initial: '${segment.toMonth}',
                          hint: '3',
                          integer: true,
                          onText: (text) {
                            if (text.isEmpty) {
                              onChanged!(segment.copyWith(toMonth: null));
                              return;
                            }
                            final to = _promotionMonth(
                              text,
                              fallback: segment.fromMonth,
                            );
                            onChanged!(
                              segment.copyWith(
                                toMonth: to < segment.fromMonth
                                    ? segment.fromMonth
                                    : to,
                              ),
                            );
                          },
                        )
                      : Text(
                          '${segment.toMonth}',
                          style: _mono(context, size: 12, weight: FontWeight.w700),
                        ),
                ),
                Text('个月', style: _sans(context, size: 11, color: _K.grey)),
              ],
              ProposalChoiceChip(
                label: '及以后',
                selected: openEnded,
                enabled: editable,
                onSelected: editable
                    ? (on) => onChanged!(
                        segment.copyWith(toMonth: on ? null : segment.fromMonth),
                      )
                    : null,
              ),
              if (onRemove != null)
                _promotionRemoveButton(
                  context,
                  tooltip: '删除这段月份',
                  onPressed: onRemove!,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _promotionChoices(
              context,
              title: '规则',
              options: const [('tier', '阶梯比例'), ('fixed', '固定比例')],
              value: segment.type,
              onPick: editable
                  ? (code) {
                      if (code == segment.type) return;
                      onChanged!(
                        segment.copyWith(
                          type: code,
                          tiers: code == 'tier' && segment.tiers.isEmpty
                              ? const [ProposalPromotionTier(from: 0, rate: 0)]
                              : segment.tiers,
                        ),
                      );
                    }
                  : null,
            ),
          ],
          if (!segment.tiered)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text('比例', style: _sans(context, size: 11, color: _K.grey)),
                  ),
                  SizedBox(
                    width: 120,
                    child: editable
                        ? _promotionInput(
                            context,
                            key: '$keyPrefix-fixed-rate',
                            initial: proposalFormatPromotionRate(segment.rate),
                            hint: '0.5',
                            onText: (text) => onChanged!(
                              segment.copyWith(rate: double.tryParse(text) ?? 0),
                            ),
                          )
                        : Text(
                            proposalFormatPromotionRate(segment.rate),
                            style: _mono(context, size: 12, weight: FontWeight.w700),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '0.5 即 50%',
                    style: _sans(context, size: 11, color: _K.grey),
                  ),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 6),
            _promotionChoices(
              context,
              title: '计费',
              options: const [('whole', '全额累进'), ('excess', '超额累进')],
              value: segment.mode,
              onPick: editable
                  ? (code) => onChanged!(segment.copyWith(mode: code))
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              annualBasis
                  ? (segment.excess
                        ? '超额累进：每一段年化规模按各自档位比例计，再加总。档位单位万元，比例写小数。'
                        : '全额累进：年化规模落在哪一档，整年按该档比例计。档位单位万元，比例写小数，0.5 即 50%。')
                  : (segment.excess
                        ? '超额累进：每一段月规模按各自档位比例计，再加总。档位单位万元，比例写小数。'
                        : '全额累进：月规模落在哪一档，整月按该档比例计。档位单位万元，比例写小数，0.5 即 50%。'),
              style: _sans(context, size: 11, color: _K.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(width: 40, child: cell('档位', head: true)),
                Expanded(
                  child: cell(
                    annualBasis ? '年化规模 ≥（万元）' : '月规模 ≥（万元）',
                    head: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: cell('比例（0.5=50%）', head: true)),
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
                      child: cell(
                        '${i + 1}${i == hit ? ' ✓' : ''}',
                        strong: i == hit,
                      ),
                    ),
                    Expanded(
                      child: editable
                          ? _promotionInput(
                              context,
                              key: '$keyPrefix-from-$i-${tiers.length}',
                              initial: proposalFormatWan(tiers[i].from),
                              hint: '0',
                              onText: (text) =>
                                  _setTier(i, from: double.tryParse(text) ?? 0),
                            )
                          : cell(
                              proposalFormatWan(tiers[i].from),
                              strong: i == hit,
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: editable
                          ? _promotionInput(
                              context,
                              key: '$keyPrefix-rate-$i-${tiers.length}',
                              initial: proposalFormatPromotionRate(tiers[i].rate),
                              hint: '0.5',
                              onText: (text) =>
                                  _setTier(i, rate: double.tryParse(text) ?? 0),
                            )
                          : cell(
                              proposalFormatPromotionRate(tiers[i].rate),
                              strong: i == hit,
                            ),
                    ),
                    if (editable)
                      _promotionRemoveButton(
                        context,
                        tooltip: '删除这一档',
                        onPressed: () => _setTiers([...tiers]..removeAt(i)),
                      ),
                  ],
                ),
              ),
            if (editable)
              _promotionAddButton(
                context,
                label: '添加档位',
                onPressed: () {
                  final last = tiers.isEmpty ? null : tiers.last;
                  _setTiers([
                    ...tiers,
                    ProposalPromotionTier(
                      from: last == null ? 0 : last.from + 1000,
                      rate: last?.rate ?? 0,
                    ),
                  ]);
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// 成本项多选：勾选后点「确定」一次写回。增值税两种口径互斥；产品结算带出的项不可取消。
/// [allowCustom] 为真时可以自行新增类型（经营成本用）。
Future<List<String>?> showProposalCostItemPicker(
  BuildContext context, {
  required ProposalCostCategory category,
  required List<String> selected,
  Set<String> locked = const {},
  bool allowCustom = false,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => _CostItemPickerDialog(
      category: category,
      selected: selected,
      locked: locked,
      allowCustom: allowCustom,
    ),
  );
}

class _CostItemPickerDialog extends StatefulWidget {
  const _CostItemPickerDialog({
    required this.category,
    required this.selected,
    required this.locked,
    required this.allowCustom,
  });

  final ProposalCostCategory category;
  final List<String> selected;
  final Set<String> locked;
  final bool allowCustom;

  @override
  State<_CostItemPickerDialog> createState() => _CostItemPickerDialogState();
}

class _CostItemPickerDialogState extends State<_CostItemPickerDialog> {
  late final List<String> _names = [
    for (final item in widget.category.items) item.name,
    for (final name in widget.selected)
      if (widget.category.itemOf(name) == null) name,
  ];
  late final Set<String> _picked = {...widget.selected, ...widget.locked};
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String name, bool on) {
    setState(() {
      if (!on) {
        _picked.remove(name);
        return;
      }
      final group = widget.category.itemOf(name)?.exclusiveGroup ?? '';
      if (group.isNotEmpty) {
        _picked.removeWhere(
          (other) =>
              other != name &&
              widget.category.itemOf(other)?.exclusiveGroup == group,
        );
      }
      _picked.add(name);
    });
  }

  void _addCustom() {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_names.contains(text)) _names.add(text);
      _picked.add(text);
      _custom.clear();
    });
  }

  String? _subtitleOf(String name) {
    if (widget.locked.contains(name)) return '产品结算里已有，自动计入';
    final item = widget.category.resolveItem(name);
    if (widget.category.itemOf(name) == null) return '自行新增，只记类型';
    if (item.tiered) return '按推广商配置 · 选中后填写推广商、年阶梯或月份折扣';
    if (widget.category.key == kProposalCostCategoryProject) {
      return '产品结算里还没有，需在上方补一行应付';
    }
    final parts = [
      if (item.hint.isNotEmpty) item.hint,
      if (item.formulas.isNotEmpty)
        '公式：${item.formulas.map((f) => f.name).join(' / ')}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
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
            if (widget.allowCustom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _custom,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '新增类型，如办公费',
                        ),
                        onSubmitted: (_) => _addCustom(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _addCustom, child: const Text('添加')),
                  ],
                ),
              ),
            for (final name in _names)
              CheckboxListTile(
                dense: true,
                value: _picked.contains(name),
                onChanged: widget.locked.contains(name)
                    ? null
                    : (on) => _toggle(name, on == true),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(name),
                subtitle: _subtitleOf(name) == null ? null : Text(_subtitleOf(name)!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([
            for (final name in _names)
              if (_picked.contains(name)) name,
          ]),
          child: Text('确定（${_picked.length}）'),
        ),
      ],
    );
  }
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

    // 收入公式按产品在上面选，这里只汇总各产品的收入。
    final revenueRow = ProposalFinanceRow(
      title: '收入',
      accent: ProposalPalette.purple,
      summary: revenue.formula?.name ?? '各产品按各自公式',
      value: '${_wan(revenue.amount)} 万',
      tag: revenue.missing.isEmpty
          ? null
          : const ProposalFinanceTag('有缺项', color: ProposalPalette.amber, fill: ProposalPalette.amberSoft),
      detail: _RevenueDetail(config: config),
    );
    final profitRow = config.wrap(
      'profit',
      ProposalFinanceRow(
        title: '利润',
        accent: _K.red,
        summary: '收入 − 项目 − 业务 − 税务',
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
    final products = config.products;
    if (products.isEmpty) {
      final line = config.evaluation.revenue;
      return _Trace(substitution: line.substitution);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < products.length; i++) ...[
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Text(
              '${i + 1}、${products[i].name} · '
              '${products[i].evaluation.revenue.formula?.name ?? '未选收入公式'}',
              style: _sans(context, size: 12, weight: FontWeight.w600),
            ),
          ),
          _Trace(substitution: products[i].evaluation.revenue.substitution),
          _Missing(products[i].evaluation.revenue.missing),
        ],
      ],
    );
  }
}
