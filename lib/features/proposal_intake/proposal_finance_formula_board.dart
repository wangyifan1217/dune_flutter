import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'proposal_cost_estimate.dart';
import 'proposal_finance_formula.dart';
import 'proposal_intake_select.dart';
import 'proposal_intake_ui.dart';

/// 测算金额、代入过程是否显示。先屏蔽，财务部分只显示每个产品选的收入公式和成本公式；
/// 改成 true 即恢复金额、代入、构成条和「利润」块。
const kProposalFinanceShowEstimates = true;

/// 财务部下半部分：按产品列出收入公式和成本公式，视觉上与顶部年化测算 hero 一致。
///
/// 每个产品一行「1、xxx 产品」，展开后依次是收入公式、项目成本；
/// 业务成本、税务成本按整份提案选择；下面是周转资金。
/// 顶部 hero 点「成本 / 收入 …」会跳到这里。
///
/// 谁能改什么由页面按角色传进 [ProposalFinanceBoardConfig]：
/// - 填写人：收入公式、项目 / 税务成本（产品结算里已有的项目成本自动带出、锁定）；
/// - 财务部负责人二：同上并按产品逐条复核；业务成本与利润对其加密；
/// - 财务部负责人一：财务复核时整份提案多选业务成本公式；
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
    this.businessWaitingText = '财务复核时由财务部负责人一选择公式',
    this.roleNote = '',
    this.reviewToggle,
    this.reviewStatus,
    this.onPromotionPlans,
    this.onRevenueFormula,
    this.onCostItemsChanged,
    this.onCostFormula,
    this.onBusinessFormulas,
    this.businessSettleRatio = '',
    this.businessFaceValue = '',
    this.onBusinessMeasure,
    this.operatingItems = const [],
    this.onOperatingItems,
    this.anchor,
    this.focusKeys = const {},
    this.turnoverCash,
    this.turnoverTimes,
    this.turnoverField,
    this.showEstimates = kProposalFinanceShowEstimates,
    this.settleLines,
    this.settleSummary,
    this.productInfo,
  });

  /// 「收入与成本」里同步产品结算：某个产品的收入（cost=false）或项目成本（cost=true）各条，
  /// 和产品卡同一个样子（只读）。不给就不显示。
  final Widget? Function(String skuId, bool cost)? settleLines;

  /// 收入 / 项目成本一行收起时的摘要，如「12 个产品 · 9 条收入」。
  final String Function(bool cost)? settleSummary;

  /// 产品分段标题后面的一句产品信息，如「面值 200 元  规模 300 万」。
  final String Function(String skuId)? productInfo;

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

  /// 业务成本公式（整份提案多选，和收入、项目成本同一套计算公式）。
  final ValueChanged<List<String>>? onBusinessFormulas;

  /// 业务成本测算用的比例、面值，二选一。
  final String businessSettleRatio;
  final String businessFaceValue;
  final void Function(String ratio, String face)? onBusinessMeasure;

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
  static const costInk = Color(0xFFB8641E);
}

Color _categoryColor(String key) => switch (key) {
  kProposalCostCategoryProject => _K.project,
  kProposalCostCategoryBusiness => _K.business,
  kProposalCostCategoryOperating => _K.operating,
  kProposalCostCategoryTax => _K.tax,
  _ => _K.grey,
};

Color _c(BuildContext context, Color light) =>
    DunesColors.resolve(context, light);

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
  const ProposalFinanceTag(
    this.text, {
    this.color = _K.text2,
    this.fill = const Color(0xFFF3F0F7),
  });

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
    // 放在左右分栏右侧时，左边格子已经写了块名，这里不再重复标题。
    final inSplit = _FinanceSplitScope.of(context);
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
                if (!inSplit) ...[
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
                ],
                band,
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: _border(context, _K.rowLine),
              ),
            rows[i],
          ],
          ?footer,
        ],
      ),
    );
  }
}

/// 一行一项：名称 · 摘要 · 金额 · 复核 · 展开箭头。展开后是公式、代入和可改的选择。
const double _kFinanceChevron = 18;
const double _kFinanceRowPadRight = 8;

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
    this.summaryStrong = false,
  });

  /// 摘要是这一行的重点（如结算规则）：深色加粗、可两行，而不是灰色小字。
  final bool summaryStrong;

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
            maxLines: _open ? 3 : (widget.summaryStrong ? 2 : 1),
            overflow: TextOverflow.ellipsis,
            style: widget.summaryStrong
                ? _sans(
                    context,
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: _K.ink,
                  )
                : _sans(context, size: 11.5, color: _K.text2),
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
              size: _kFinanceChevron,
              color: _c(context, _K.grey),
            ),
          )
        : const SizedBox(width: _kFinanceChevron);
    final head = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  value,
                  chevron,
                ],
              ),
              if (summary != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: summary),
              if (review != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(alignment: Alignment.centerLeft, child: review),
                ),
            ],
          )
        : Row(
            children: [
              SizedBox(width: widget.titleWidth, child: title),
              Expanded(child: summary ?? const SizedBox.shrink()),
              const SizedBox(width: 10),
              value,
              // 复核按钮 / 驳回意见可长可短：给它能用的宽度，不再把整行撑出右边。
              if (review != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: review,
                ),
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
            padding: const EdgeInsets.fromLTRB(14, 9, _kFinanceRowPadRight, 9),
            child: head,
          ),
        ),
        if (_open && widget.detail != null)
          Padding(
            // 右边留出标题行的箭头，展开后的金额和标题行金额同一列。
            padding: const EdgeInsets.fromLTRB(
              14,
              0,
              _kFinanceRowPadRight + _kFinanceChevron,
              6,
            ),
            child: widget.detail,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 成本
// ---------------------------------------------------------------------------

/// 成本块的三种用法。
/// - [full]：原来的按产品选公式（保留，暂不在页面上用）；
/// - [result]：市场部「成本测算」——结算写好就自动算，只读出结果，不用填；
/// - [inputs]：财务部「经营与周转」——只剩经营成本类型、月周转次数两项要填。
enum ProposalFinanceCostPanelMode { full, result, inputs, cost }

class ProposalFinanceCostPanel extends StatelessWidget {
  const ProposalFinanceCostPanel({
    super.key,
    required this.config,
    this.mode = ProposalFinanceCostPanelMode.full,
  });

  final ProposalFinanceBoardConfig config;
  final ProposalFinanceCostPanelMode mode;

  @override
  Widget build(BuildContext context) {
    if (mode == ProposalFinanceCostPanelMode.inputs) {
      return _inputsPanel(context);
    }
    final eval = config.evaluation;
    final sealed = config.businessSealed;
    final buckets = eval.buckets.values.toList();
    double shown(ProposalFinanceBucket bucket) =>
        sealed && bucket.category.key == kProposalCostCategoryBusiness
        ? 0
        : bucket.total;
    // 成本合计只包含项目、业务和税务成本。
    final total = buckets.fold<double>(0, (sum, b) => sum + shown(b));
    final scale = eval.salesScale;
    final products = config.products;

    final band = !config.showEstimates
        ? Text(
            products.isEmpty
                ? '请先在科技部添加业务产品'
                : '共 ${products.length} 个产品 · 收入、项目成本跟着产品结算同步 · 税务成本整份提案一次',
            style: _sans(context, size: 11.5, color: _K.text2),
          )
        : ProposalFinanceBand(
            value: _wan(total),
            unit: '万',
            label: '年化成本',
            color: _K.text2,
            compact: true,
            trailing: scale > 0
                ? ProposalFinanceTag(
                    '占规模 ${_wan(total / scale * 100)}%',
                    color: _K.heroInk,
                    fill: const Color(0xFFDCE4F6),
                  )
                : null,
            sub: sealed ? '不含已加密的业务成本' : '',
          );

    // 外层是成本类（项目 / 业务 / 税务），每一类点开后按产品列出；产品包在成本里面。
    // 利润块关掉时，收入公式也放在这里（按产品）。
    if (mode == ProposalFinanceCostPanelMode.result ||
        mode == ProposalFinanceCostPanelMode.cost) {
      return config.wrapAll(
        [kProposalFinanceCostAnchor, kProposalFinanceProfitAnchor],
        ProposalFinanceBlockShell(
          icon: Icons.receipt_long_outlined,
          title: mode == ProposalFinanceCostPanelMode.result ? '成本测算' : '收入与成本',
          band: config.roleNote.trim().isEmpty
              ? band
              : Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
                    band,
                    const SizedBox(height: 6),
              Text(
                      config.roleNote.trim(),
                      style: _sans(context, size: 11.5, color: _K.text2),
              ),
          ],
        ),
          rows: [
            if (mode == ProposalFinanceCostPanelMode.cost)
              config.wrap(
                'revenue',
                proposalFinanceRevenueRow(context, config),
              ),
            for (final key in const [
              kProposalCostCategoryProject,
              kProposalCostCategoryBusiness,
              kProposalCostCategoryTax,
            ])
              if (config.catalog.category(key) != null &&
                  !(sealed && key == kProposalCostCategoryBusiness))
                config.wrap(
                  proposalFinanceCategoryAnchor(key),
                  _categoryRow(
                    context,
                    key,
                    readOnly: mode == ProposalFinanceCostPanelMode.result,
                  ),
                ),
            if (mode == ProposalFinanceCostPanelMode.cost)
              config.wrap('turnoverTimes', _turnoverRow(context)),
          ],
        ),
      );
    }
    final rows = <Widget>[
      // 利润块关掉（或金额不展示）时，收入公式放在成本块第一行：业务成本、所得税要用到收入。
      if (!config.showEstimates || !kProposalFinanceShowProfit)
        config.wrap('revenue', proposalFinanceRevenueRow(context, config)),
      for (final key in const [
        kProposalCostCategoryProject,
        kProposalCostCategoryBusiness,
        kProposalCostCategoryTax,
      ])
        if (config.catalog.category(key) != null &&
            !(sealed && key == kProposalCostCategoryBusiness))
          config.wrap(
            proposalFinanceCategoryAnchor(key),
            _categoryRow(context, key),
          ),
      config.wrap('operatingCost', _operatingRow(context)),
      config.wrap('turnoverTimes', _turnoverRow(context)),
    ];
    return config.wrapAll(
      [
      kProposalFinanceCostAnchor,
        // 利润块屏蔽时，hero 跳「利润 / 毛利率」落到这里。
        if (!config.showEstimates || !kProposalFinanceShowProfit) ...[
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

  /// 财务部「经营与周转」：只剩两项要填 —— 经营成本类型（只选类型）、月周转次数（算周转资金）。
  Widget _inputsPanel(BuildContext context) {
    final times = config.turnoverTimes;
    final cash = config.turnoverCash;
    return config.wrapAll(
      const ['operatingCost', 'turnoverTimes', 'turnoverCash'],
      ProposalFinanceBlockShell(
        icon: Icons.tune_rounded,
        title: '经营与周转',
        band: ProposalFinanceBand(
          value: cash == null ? '—' : _wan(cash),
          unit: cash == null ? '' : '万',
          label: '周转资金',
          trailing: times == null || times <= 0
              ? null
              : ProposalFinanceTag(
                  '月周转 ${_wan(times)} 次',
                  color: _K.heroInk,
                  fill: const Color(0xFFDCE4F6),
                ),
        ),
        rows: [
          config.wrap('operatingCost', _operatingRow(context)),
          config.wrap('turnoverTimes', _turnoverRow(context)),
        ],
      ),
    );
  }

  /// 一类成本一行：合计 + 各产品摘要；点开后按产品分段，每段是这个产品这一类的成本项和公式。
  Widget _categoryRow(
    BuildContext context,
    String key, {
    bool readOnly = false,
  }) {
    final category = config.catalog.category(key)!;
    if (key == kProposalCostCategoryTax) {
      final bucket =
          config.evaluation.bucket(key) ??
          ProposalFinanceBucket(category: category, lines: const []);
      final editable = !readOnly && config.categoryEditable[key] == true;
      return ProposalFinanceRow(
        key: const ValueKey('finance-proposal-tax'),
        title: category.name,
        forceOpen: config.focusKeys.contains('taxCost'),
        summary: bucket.names.isEmpty
            ? '整份提案统一选择税务成本'
            : '整份提案 · ${bucket.names.join('、')}',
        value: config.showEstimates ? '${_wan(bucket.total)} 万' : '',
        collapsedReview: config.reviewStatus?.call('taxCost'),
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryDetail(
              bucket: bucket,
              editable: editable,
              allowItemEdit: editable,
              showEstimates: config.showEstimates,
              onItemsChanged: editable && config.onCostItemsChanged != null
                  ? (names) => config.onCostItemsChanged!('', category, names)
                  : null,
              onFormula: editable && config.onCostFormula != null
                  ? (name, code) =>
                        config.onCostFormula!('', category, name, code)
                  : null,
            ),
            if (!readOnly && config.reviewToggle != null)
              if (config.reviewToggle!('taxCost') case final toggle?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(alignment: Alignment.centerRight, child: toggle),
                ),
          ],
        ),
      );
    }
    if (key == kProposalCostCategoryBusiness) {
      final bucket =
          config.evaluation.bucket(key) ??
          ProposalFinanceBucket(category: category, lines: const []);
    final editable =
          !readOnly &&
          config.categoryEditable[key] == true &&
          config.onBusinessFormulas != null;
      final codes = [
        for (final line in bucket.lines)
          if (line.formula != null && line.formula!.code.isNotEmpty)
            line.formula!.code,
      ];
      final waiting = bucket.names.isEmpty && !editable;
      return ProposalFinanceRow(
        key: const ValueKey('finance-proposal-business'),
        title: category.name,
        initiallyOpen: bucket.names.isEmpty,
        forceOpen: config.focusKeys.contains('businessCost'),
        summary: bucket.names.isEmpty
            ? (editable ? '点开多选计算公式' : config.businessWaitingText)
            : '整份提案 · ${bucket.names.join('、')}',
        value: config.showEstimates && bucket.names.isNotEmpty
            ? '${_wan(bucket.total)} 万'
            : '',
        tag: waiting
            ? const ProposalFinanceTag(
                '待选择',
                color: ProposalPalette.amber,
                fill: ProposalPalette.amberSoft,
              )
            : const ProposalFinanceTag('整份提案'),
        collapsedReview: config.reviewStatus?.call('businessCost'),
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProposalBusinessFormulas(
              formulas: config.catalog.settlementFormulas,
              lines: bucket.lines,
              selectedCodes: codes,
              editable: editable,
              showEstimates: config.showEstimates,
              waitingText: config.businessWaitingText,
              onChanged: editable ? config.onBusinessFormulas : null,
              ratio: config.businessSettleRatio,
              face: config.businessFaceValue,
              onMeasure: editable ? config.onBusinessMeasure : null,
            ),
          ],
        ),
      );
    }
    final products = config.products;
    final show = config.showEstimates;
    final sealed =
        config.businessSealed && key == kProposalCostCategoryBusiness;
    final reviewKind = key == kProposalCostCategoryBusiness
        ? ''
        : ProposalFinanceFormulaBoardKeys.reviewKeyOf(key);
    final total = sealed
        ? 0.0
        : products.fold<double>(
            0,
            (sum, p) => sum + (p.evaluation.bucket(key)?.total ?? 0),
          );
    final summary = sealed
        ? '仅财务部负责人一和最终审批人可查看'
        : products.isEmpty
        ? '请先在科技部添加业务产品'
        : key == kProposalCostCategoryProject && config.settleSummary != null
        ? config.settleSummary!(true)
        : [
            for (var i = 0; i < products.length; i++)
              () {
                final bucket = products[i].evaluation.bucket(key);
                final count = bucket?.lines.length ?? 0;
                final name = '${i + 1}、${products[i].name}';
                if (count == 0) return '$name 无';
                return show ? '$name ${_wan(bucket!.total)}' : '$name $count 项';
              }(),
          ].join(' · ');
    final hasIssue =
        show &&
        !sealed &&
        products.any(
          (p) =>
              (p.evaluation.bucket(key)?.lines ?? const <ProposalFinanceLine>[])
                  .any((line) => line.missing.isNotEmpty),
        );
    return ProposalFinanceRow(
      key: ValueKey('finance-category-$key'),
      title: category.name,
      summary: summary,
      value: show && !sealed ? '${_wan(total)} 万' : '',
      tag: sealed
          ? const ProposalFinanceTag(
              '已加密',
              color: _K.red,
              fill: Color(0xFFF5E5DC),
            )
          : hasIssue
          ? const ProposalFinanceTag(
              '有缺项',
              color: ProposalPalette.amber,
              fill: ProposalPalette.amberSoft,
            )
          : null,
      collapsedReview: reviewKind.isEmpty
          ? null
          : config.reviewStatus?.call('kind:$reviewKind'),
      forceOpen: config.focusKeys.contains(proposalFinanceCategoryAnchor(key)),
      detail: sealed || products.isEmpty
                  ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < products.length; i++)
                  _ProductCategorySection(
                    config: config,
                    product: products[i],
                    index: i,
                    categoryKey: key,
                    readOnly: readOnly,
                  ),
              ],
            ),
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
      summary: items.isEmpty ? (editable ? '点开选择类型' : '未选择') : items.join('、'),
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

/// 业务成本：整份提案多选，选项和收入、项目成本的计算公式是同一套。
class _ProposalBusinessFormulas extends StatelessWidget {
  const _ProposalBusinessFormulas({
    required this.formulas,
    required this.lines,
    required this.selectedCodes,
    required this.editable,
    required this.showEstimates,
    required this.waitingText,
    this.onChanged,
    this.ratio = '',
    this.face = '',
    this.onMeasure,
  });

  final List<ProposalFinanceFormula> formulas;
  final List<ProposalFinanceLine> lines;
  final List<String> selectedCodes;
  final bool editable;
  final bool showEstimates;
  final String waitingText;
  final ValueChanged<List<String>>? onChanged;
  final String ratio;
  final String face;
  final void Function(String ratio, String face)? onMeasure;

  @override
  Widget build(BuildContext context) {
    final chosen = selectedCodes.toSet();
    final remaining = [
      for (final formula in formulas)
        if (!chosen.contains(formula.code)) formula,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            editable
                ? '整份提案选一次，可多选。选完后填写比例或面值，二选一。'
                : lines.isEmpty
                ? waitingText
                : '整份提案统一测算，不跟产品走。',
            style: _sans(context, size: 12, color: _K.grey),
          ),
        ),
        if (lines.isEmpty && editable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '尚未选择',
              style: _sans(context, size: 12, color: _K.grey),
            ),
          ),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
                    children: [
                        Expanded(
                  child: Text(
                    line.formula?.name ?? line.name,
                    style: _sans(context, size: 12.5, weight: FontWeight.w600),
                  ),
                ),
                if (showEstimates)
                  Text(
                    '${_wan(line.amount)} 万',
                    style: _mono(context, size: 12),
                  ),
                if (onChanged != null && line.formula != null)
                  IconButton(
                    tooltip: '移除',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => onChanged!([
                      for (final code in selectedCodes)
                        if (code != line.formula!.code) code,
                    ]),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _c(context, _K.grey),
                    ),
                  ),
              ],
            ),
          ),
        if (lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _BusinessMeasureFields(
              ratio: ratio,
              face: face,
              editable: onMeasure != null,
              onChanged: onMeasure,
            ),
          ),
        if (onChanged != null && remaining.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ProposalSelectField<String>(
              value: null,
              title: '业务成本计算公式',
              hint: '选择计算公式，可多选',
              searchable: true,
              options: [
                for (final formula in remaining)
                  ProposalSelectOption(
                    value: formula.code,
                    label: formula.name,
                    meta: [
                      '编码 ${formula.code}',
                      if (formula.settleMethodName.isNotEmpty)
                        formula.settleMethodName,
                      if (formula.expression.isNotEmpty) formula.expression,
                    ].join(' · '),
                  ),
              ],
              onSelected: (code) {
                if (code == null || chosen.contains(code)) return;
                onChanged!([...selectedCodes, code]);
              },
            ),
        ),
      ],
    );
  }
}

class _BusinessMeasureFields extends StatefulWidget {
  const _BusinessMeasureFields({
    required this.ratio,
    required this.face,
    required this.editable,
    this.onChanged,
  });

  final String ratio;
  final String face;
  final bool editable;
  final void Function(String ratio, String face)? onChanged;

  @override
  State<_BusinessMeasureFields> createState() => _BusinessMeasureFieldsState();
}

class _BusinessMeasureFieldsState extends State<_BusinessMeasureFields> {
  late final TextEditingController _ratio;
  late final TextEditingController _face;

  @override
  void initState() {
    super.initState();
    _ratio = TextEditingController(text: widget.ratio);
    _face = TextEditingController(text: widget.face);
  }

  @override
  void didUpdateWidget(covariant _BusinessMeasureFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ratio != _ratio.text) _ratio.text = widget.ratio;
    if (widget.face != _face.text) _face.text = widget.face;
  }

  @override
  void dispose() {
    _ratio.dispose();
    _face.dispose();
    super.dispose();
  }

  Widget _input(
    String label,
    TextEditingController controller,
    String hint,
    void Function(String value) write,
  ) {
    return ProposalField(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [ProposalSettleRatioFormatter()],
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: write,
        decoration: proposalInputDecoration(context: context, hint: hint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editable) {
      final ratio = widget.ratio.trim();
      final face = widget.face.trim();
      final text = ratio.isNotEmpty
          ? '比例 $ratio'
          : face.isNotEmpty
          ? '面值 $face'
          : '未填比例或面值';
      return Text(text, style: _sans(context, size: 12, color: _K.grey));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _input('比例', _ratio, '如 0.08，1 表示 100%', (value) {
            widget.onChanged?.call(value.trim(), '');
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _input('面值', _face, '填数字，按这个面值测算', (value) {
            widget.onChanged?.call('', value.trim());
          }),
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
    _CostLine lineWidget(ProposalFinanceLine line) => _CostLine(
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
    );
    bool isSimple(ProposalFinanceLine line) => _CostLine.simple(
      category,
      line,
      showEstimates: showEstimates,
      canChangeFormula: onFormula != null && !line.locked,
    );
    final simpleLines = [
      for (final line in bucket.lines)
        if (isSimple(line)) line,
    ];
    final border = _border(context, ProposalPalette.borderSoft);
    // 简单行收进一张表：表头「项目 | 计算公式」，一行一项，细线分隔。
    final table = simpleLines.isEmpty
        ? null
        : Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: _surface(context, ProposalPalette.app),
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _kFormulaNameWidth,
                        child: Text(
                          '项目',
                          style: _sans(context, size: 11, color: _K.grey),
                        ),
                      ),
                      Text(
                        '计算公式',
                        style: _sans(context, size: 11, color: _K.grey),
                      ),
                    ],
                  ),
                ),
                for (final line in simpleLines)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: border)),
                    ),
                    child: lineWidget(line),
                  ),
              ],
            ),
          );
    final children = <Widget>[
      ?table,
      for (final line in bucket.lines)
        if (!isSimple(line))
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
                ? '跟着产品结算，在项目成本（采购成本）里填写后自动带出'
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
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

/// 成本类里的一个产品：「1、产品名 主产品 · 金额 · 复核」，下面是这个产品这一类的成本项和公式。
class _ProductCategorySection extends StatelessWidget {
  const _ProductCategorySection({
    required this.config,
    required this.product,
    required this.index,
    required this.categoryKey,
    this.readOnly = false,
  });

  final ProposalFinanceBoardConfig config;
  final ProposalProductFinanceEvaluation product;
  final int index;
  final String categoryKey;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final key = categoryKey;
    final skuId = product.skuId;
    final show = config.showEstimates;
    final bucket = product.evaluation.bucket(key);
    if (bucket == null) return const SizedBox.shrink();
    final category = bucket.category;
    final editable =
        !readOnly &&
        config.canEditProduct(skuId, key) &&
        config.onCostItemsChanged != null;
    final reviewKind = key == kProposalCostCategoryBusiness
        ? ''
        : ProposalFinanceFormulaBoardKeys.reviewKeyOf(key);
    final settle = key == kProposalCostCategoryProject
        ? config.settleLines?.call(skuId, true)
        : null;
    // 上面已经同步列出产品结算的各条，下面不再重复「券使用成本 产品结算 公式…」，
    // 只留需要另外配置的（如推广费阶梯、可换公式的）。
    final shownBucket = settle == null
        ? bucket
        : ProposalFinanceBucket(
            category: bucket.category,
            lines: [
              for (final line in bucket.lines)
                if (!line.locked || category.resolveItem(line.name).tiered)
                  line,
            ],
          );
    final Widget? body = settle != null && shownBucket.lines.isEmpty
        ? null
        : bucket.lines.isEmpty &&
            !editable &&
            key == kProposalCostCategoryBusiness
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              config.businessWaitingText,
              style: _sans(context, size: 12, color: _K.grey),
            ),
          )
        : _CategoryDetail(
            bucket: shownBucket,
            editable: editable,
            // 项目成本只跟产品结算的应付行走，财务模块不能再增删。
            allowItemEdit: editable && key != kProposalCostCategoryProject,
            showEstimates: show,
            onItemsChanged: editable && key != kProposalCostCategoryProject
                ? (names) => config.onCostItemsChanged!(skuId, category, names)
                : null,
            onFormula: config.onCostFormula == null || !editable
                ? null
                : (name, code) =>
                      config.onCostFormula!(skuId, category, name, code),
            promotionPlans: product.promotionPlans,
            onPromotionPlans: editable && config.onPromotionPlans != null
                ? (plans) => config.onPromotionPlans!(skuId, plans)
                : null,
          );
    return _ProductSection(
      index: index,
      product: product,
      color: _categoryColor(key),
      info: config.productInfo?.call(skuId) ?? '',
      trailing: show ? '${_wan(bucket.total)} 万' : '',
      review: readOnly || reviewKind.isEmpty
          ? null
          : config.reviewToggle?.call(
              proposalFinanceProductReviewKey(skuId, reviewKind),
            ),
      // 先列产品结算里的项目成本各条（同步过来，只读），下面是另外要配的成本项和公式。
      leading: settle,
      child: body,
    );
  }
}

/// 产品分段：一张带细框的小表单。标题条「1、产品名 主产品 面值…」+ 复核在右；
/// 下面先是同步过来的结算各条（[leading]，贴边、每条一行），再是公式 / 成本项（[child]，同样左右留 10）。
class _ProductSection extends StatelessWidget {
  const _ProductSection({
    required this.index,
    required this.product,
    required this.color,
    this.child,
    this.leading,
    this.trailing = '',
    this.review,
    this.info = '',
  });

  final int index;
  final ProposalProductFinanceEvaluation product;
  final Color color;
  final Widget? child;
  final Widget? leading;
  final String trailing;

  /// 名称后面的一句产品信息（面值、规模）。
  final String info;
  final Widget? review;

  @override
  Widget build(BuildContext context) {
    final line = _border(context, ProposalPalette.borderSoft);
    final compact = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    final head = compact
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}',
                      style: _mono(context, size: 12, color: _K.text2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        product.name,
                        style: _sans(
                          context,
                          size: 12.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ProposalFinanceTag(product.isChild ? '关联产品' : '主产品'),
                  ],
                ),
                if (info.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    info,
                    style: _sans(context, size: 11.5, color: _K.text2),
                  ),
                ],
                if (trailing.isNotEmpty || review != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (trailing.isNotEmpty)
                        Text(trailing, style: _mono(context, size: 12)),
                      const Spacer(),
                      if (review != null) review!,
                    ],
                  ),
                ],
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${index + 1}',
                    style: _mono(context, size: 12, color: _K.text2),
                  ),
                ),
                Flexible(
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, size: 12.5, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                ProposalFinanceTag(product.isChild ? '关联产品' : '主产品'),
                if (info.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      info,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(context, size: 11.5, color: _K.text2),
                    ),
                  ),
                ],
                const Spacer(),
                if (trailing.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(trailing, style: _mono(context, size: 12)),
                ],
                if (review != null) ...[const SizedBox(width: 6), review!],
              ],
            ),
          );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: _surface(context, Colors.white),
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _surface(context, ProposalPalette.app),
            child: head,
          ),
          if (leading != null) ...[Container(height: 1, color: line), leading!],
          if (child != null) ...[
            Container(height: 1, color: line),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

/// 收入一行：合计 + 各产品公式；点开后按产品选收入公式（每个产品单独复核）。
Widget proposalFinanceRevenueRow(
  BuildContext context,
  ProposalFinanceBoardConfig config,
) {
  final products = config.products;
  final show = config.showEstimates;
  final revenue = config.evaluation.revenue;
  final hasIssue =
      show && products.any((p) => p.evaluation.revenue.missing.isNotEmpty);
  return ProposalFinanceRow(
    key: const ValueKey('finance-revenue-row'),
    title: '收入',
    summary: products.isEmpty
        ? '请先在科技部添加业务产品'
        : config.settleSummary != null
        ? config.settleSummary!(false)
        : [
            for (var i = 0; i < products.length; i++)
              '${i + 1}、${products[i].evaluation.revenue.formula?.name ?? '未选公式'}',
          ].join(' · '),
    value: show ? '${_wan(revenue.amount)} 万' : '',
    tag: hasIssue
        ? const ProposalFinanceTag(
            '有缺项',
            color: ProposalPalette.amber,
            fill: ProposalPalette.amberSoft,
          )
        : null,
    collapsedReview: config.reviewStatus?.call('kind:revenue'),
    forceOpen: config.focusKeys.contains('revenue'),
    detail: products.isEmpty
        ? _Trace(substitution: revenue.substitution)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < products.length; i++)
                _ProductSection(
                  index: i,
                  product: products[i],
                  color: ProposalPalette.purple,
                  info: config.productInfo?.call(products[i].skuId) ?? '',
                  trailing: show
                      ? '${_wan(products[i].evaluation.revenue.amount)} 万'
                      : '',
                  review: config.reviewToggle?.call(
                    proposalFinanceProductReviewKey(
                      products[i].skuId,
                      'revenue',
                    ),
                  ),
                  // 先列产品结算里的收入各条（同步过来，只读），下面是收入公式。
                  leading: config.settleLines?.call(products[i].skuId, false),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RevenueFormulaPicker(
                    config: config,
                    evaluation: products[i].evaluation,
                    onRevenueFormula:
                        config.canEditProduct(products[i].skuId, 'revenue') &&
                            config.onRevenueFormula != null
                        ? (group, code) => config.onRevenueFormula!(
                            products[i].skuId,
                            group,
                            code,
                          )
                        : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );
}

/// 收入公式：可改时是下拉，只读时只写公式名。
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onRevenueFormula != null)
          ProposalSelectField<String>(
            value: formula == null || group == null
                ? null
                : '${group.key}|${formula.code}',
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
                      if (f.settleMethodName.isNotEmpty) f.settleMethodName,
                      if (f.detail.isNotEmpty) f.detail,
                    ].join(' · '),
                  ),
            ],
            onSelected: (value) {
              if (value == null || !value.contains('|')) return;
              final cut = value.indexOf('|');
              onRevenueFormula!(
                value.substring(0, cut),
                value.substring(cut + 1),
              );
            },
          )
        else
          Text(
            formula == null ? '未选择收入公式' : formula.name,
            style: _sans(context, size: 12.5, weight: FontWeight.w600),
          ),
        if (show) ...[
          _Trace(
            formula: formula == null || formula.detail.isEmpty
                ? ''
                : '公式：${formula.expression}',
            substitution: line.substitution,
          ),
          _Missing(line.missing),
        ],
      ],
    );
  }
}

/// 一个成本项：产品结算带出的只写「出处 + 代入」，其余可选公式。
/// 表格里「项目」一列的宽度：税务成本、项目成本的简单行都用它，上下对齐。
const double _kFormulaNameWidth = 168;

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

  /// 只是「项目 + 公式」一行（放进表格）；要换公式、配阶梯、看测算的仍是一张小卡。
  static bool simple(
    ProposalCostCategory category,
    ProposalFinanceLine line, {
    required bool showEstimates,
    required bool canChangeFormula,
  }) {
    final item = category.resolveItem(line.name);
    return !showEstimates &&
        !item.tiered &&
        !(canChangeFormula && item.formulas.length > 1);
  }

  @override
  Widget build(BuildContext context) {
    final item = category.resolveItem(line.name);
    final formula = line.formula;
    final canChoose = onFormula != null && item.formulas.length > 1;
    if (!showEstimates && !item.tiered && !canChoose) {
      // 简单行（表格里的一行）：项目名固定宽度一列，公式一列，上下对齐。
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            SizedBox(
              width: _kFormulaNameWidth,
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
                ],
              ),
            ),
            Expanded(
              child: Text(
                formula?.name ?? '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 12, color: _K.text2),
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: '移除',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: onRemove,
                icon: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: _c(context, _K.grey),
                ),
              ),
          ],
        ),
      );
    }
    final head = Row(
      children: [
        Expanded(
          child: Row(
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
                const ProposalFinanceTag(
                  '产品结算',
                  color: ProposalPalette.green,
                  fill: ProposalPalette.greenSoft,
                )
              else if (item.tiered)
                line.pending
                    ? const ProposalFinanceTag(
                        '推广商 · 未配置',
                        color: ProposalPalette.amber,
                        fill: ProposalPalette.amberSoft,
                      )
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
            ],
          ),
        ),
        if (showEstimates) ...[
          const SizedBox(width: 8),
        Text(
          line.pending ? '—' : '${_wan(line.amount)} 万',
            style: _mono(
              context,
              size: 12.5,
              color: line.pending ? _K.grey : _K.ink,
        ),
          ),
        ],
        if (onRemove != null)
          IconButton(
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onRemove,
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: _c(context, _K.grey),
            ),
          ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
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
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Text(
                line.source,
                style: _sans(context, size: 11, color: _K.grey),
              ),
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
          else if (formula != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Text(
                '公式：${formula.name}',
                style: _sans(context, size: 11, color: _K.grey),
              ),
            ),
          if (showEstimates)
          _Trace(
            // 产品结算带出的不再写公式（出处已经说明），只写代入。
              formula: formula == null || formula.expression == formula.name
                ? ''
                : formula.expression,
            substitution: line.substitution,
          ),
          if (item.tiered && !line.locked)
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

/// 产品结算「应付」里的推广费阶梯：应付行写了「推广费」时出现。
/// 不配置 → 按应付行的比例算；配置了 → 按阶梯算（固定比例 / 年阶梯 / 连续月序），应付行比例不再使用。
class ProposalPromotionPlanField extends StatelessWidget {
  const ProposalPromotionPlanField({
    super.key,
    required this.plans,
    this.monthlyScale,
    this.amountText = '',
    this.onChanged,
    this.costName = '推广费',
    this.promoterOptions = const [],
  });

  final List<ProposalPromotionTierPlan> plans;
  final String costName;
  final List<String> promoterOptions;
  final double? monthlyScale;
  final String amountText;
  final ValueChanged<List<ProposalPromotionTierPlan>>? onChanged;

  @override
  Widget build(BuildContext context) {
    final active = plans.any((plan) => !plan.isEmpty);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _surface(context, _K.heroBg),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border(context, _K.heroBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                '项目成本（应付）.$costName阶梯',
                style: _sans(
                  context,
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: _K.heroInk,
                ),
              ),
              const SizedBox(width: 6),
              ProposalFinanceTag(active ? '按阶梯算' : '按应付比例算'),
              if (amountText.isNotEmpty)
                Text(amountText, style: _mono(context, size: 12.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            active ? '按以下年阶梯或连续月份规则计算。' : '请配置年阶梯或连续月份规则。',
            style: _sans(context, size: 11.5, color: _K.text2),
          ),
          _PromotionPlansEditor(
            plans: plans,
            promoterOptions: promoterOptions,
            showPromoter: costName == '推广费',
            monthlyScale: monthlyScale,
            onChanged: onChanged,
          ),
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
    this.promoterOptions = const [],
    this.showPromoter = true,
  });

  final List<ProposalPromotionTierPlan> plans;
  final List<String> promoterOptions;
  final bool showPromoter;
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
            child: Text(
              '未配置推广商方案',
              style: _sans(context, size: 11.5, color: _K.grey),
            ),
          ),
        if (plan != null)
          _PromotionPlanEditor(
            key: ValueKey('promotion-plan-${plan.id}'),
            plan: plan,
            promoterOptions: promoterOptions,
            showPromoter: showPromoter,
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
                label: Text(showPromoter ? '配置推广商' : '配置阶梯规则'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: _c(context, ProposalPalette.purpleDeep),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
      decoration: proposalInputDecoration(
        context: context,
        hint: hint,
        forceUnderline: true,
      ),
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
    this.promoterOptions = const [],
    this.showPromoter = true,
  });

  final ProposalPromotionTierPlan plan;
  final List<String> promoterOptions;
  final bool showPromoter;
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
        ProposalPromotionSegment(
          tiers: [ProposalPromotionTier(from: 0, rate: 0)],
        ),
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
          if (showPromoter)
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '推广商',
                    style: _sans(context, size: 11, color: _K.grey),
                  ),
                ),
                Expanded(
                  child: editable
                      ? DropdownButtonFormField<String>(
                          key: ValueKey(
                            'promotion-promoter-$id-${plan.promoter}',
                          ),
                          initialValue: plan.promoter.isEmpty
                              ? null
                              : plan.promoter,
                          isExpanded: true,
                          decoration: proposalInputDecoration(
                            context: context,
                            hint: '选择采购合同中的推广商',
                          ),
                          items: [
                            for (final name in {
                              ...promoterOptions,
                              if (plan.promoter.isNotEmpty) plan.promoter,
                            })
                              DropdownMenuItem(
                                value: name,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (name) => onChanged?.call(
                            plan.copyWith(promoter: name ?? ''),
                          ),
                        )
                      : Text(
                          plan.label,
                          style: _sans(
                            context,
                            size: 12.5,
                            weight: FontWeight.w700,
                          ),
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
          if (showPromoter && plan.promoter.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '推广费必须选择推广商',
                style: _sans(context, size: 11, color: _K.red),
              ),
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
                    child: Text(
                      '比例',
                      style: _sans(context, size: 11, color: _K.grey),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: editable
                        ? _promotionInput(
                            context,
                            key: 'promotion-$id-fixed-rate',
                            initial: proposalFormatPromotionRate(
                              plan.fixedRate,
                            ),
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
                            style: _mono(
                              context,
                              size: 12,
                              weight: FontWeight.w700,
                            ),
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
                    ? (segment) =>
                          _setSegments([...plan.segments]..[i] = segment)
                    : null,
                onRemove: editable && plan.segments.length > 1
                    ? () => _setSegments([...plan.segments]..removeAt(i))
                    : null,
              ),
            if (editable)
              _promotionAddButton(
                context,
                label: '添加月份段',
                onPressed: _addSegment,
              ),
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
                  child: Text(
                    '月份',
                    style: _sans(context, size: 11, color: _K.grey),
                  ),
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
                          style: _mono(
                            context,
                            size: 12,
                            weight: FontWeight.w700,
                          ),
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
                            style: _mono(
                              context,
                              size: 12,
                              weight: FontWeight.w700,
                            ),
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
                          segment.copyWith(
                            toMonth: on ? null : segment.fromMonth,
                          ),
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
                    child: Text(
                      '比例',
                      style: _sans(context, size: 11, color: _K.grey),
                    ),
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
                              segment.copyWith(
                                rate: double.tryParse(text) ?? 0,
                              ),
                            ),
                          )
                        : Text(
                            proposalFormatPromotionRate(segment.rate),
                            style: _mono(
                              context,
                              size: 12,
                              weight: FontWeight.w700,
                            ),
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
                              initial: proposalFormatPromotionRate(
                                tiers[i].rate,
                              ),
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
                child: Text(
                  category.hint,
                  style: _sans(context, size: 12, color: _K.grey),
                ),
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
                subtitle: _subtitleOf(name) == null
                    ? null
                    : Text(_subtitleOf(name)!),
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
          style: _mono(
            context,
            size: 11.5,
            weight: FontWeight.w500,
            color: _K.text2,
          ),
        ),
      ],
    );

    // 收入：外层一行，点开按产品选收入公式（产品包在收入里面）。
    final revenueRow = config.wrap(
      'revenue',
      proposalFinanceRevenueRow(context, config),
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

/// 块顶统一版式（以「利润」块为准）：左边大数 + 灰色「单位 · 名称」，右上一个标签，
/// 下面一行灰色等宽小字（等式或说明）。产品结算、成本、利润、市场部、科技部的块都用它。
class ProposalFinanceBand extends StatelessWidget {
  const ProposalFinanceBand({
    super.key,
    required this.value,
    this.unit = '',
    this.label = '',
    this.color = _K.ink,
    this.sub = '',
    this.trailing,
    this.numeric = true,
    this.compact = false,
  });

  final String value;
  final String unit;
  final String label;
  final Color color;
  final String sub;
  final Widget? trailing;

  /// 数字用等宽大字；文字（如提案名、平台名）用无衬线粗体。
  final bool numeric;

  /// 普通信息块使用紧凑字号，避免与页面主指标争夺视觉层级。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tail = [
      if (unit.isNotEmpty) unit,
      if (label.isNotEmpty) label,
    ].join(' · ');
    final empty = value.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: empty ? '未填写' : value,
                  style: numeric && !empty
                      ? _mono(
                          context,
                          size: compact ? 14 : 18,
                          weight: compact ? FontWeight.w600 : FontWeight.w700,
                          color: color,
                        )
                      : _sans(
                          context,
                          size: 15,
                          weight: FontWeight.w700,
                          color: empty ? _K.grey : color,
                        ),
                  children: [
                    if (tail.isNotEmpty)
                      TextSpan(
                        text: ' $tail',
                        style: _sans(context, size: 11, color: _K.grey),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _mono(
              context,
              size: 11.5,
              weight: FontWeight.w500,
              color: _K.text2,
            ),
          ),
        ],
      ],
    );
  }
}

/// 块顶多个数并排强化（如「1 个产品  3 条结算  2 个关联产品」）：数字等宽大字、单位灰色小字。
class ProposalFinanceStatBand extends StatelessWidget {
  const ProposalFinanceStatBand({
    super.key,
    required this.stats,
    this.color = _K.ink,
    this.trailing,
  });

  final List<(String, String)> stats;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const TextSpan(text: '    '),
                    TextSpan(
                      text: stats[i].$1,
                      style: _mono(context, size: 20, color: color),
                    ),
                    TextSpan(
                      text: ' ${stats[i].$2}',
                      style: _sans(
                        context,
                        size: 11.5,
                        weight: FontWeight.w500,
                        color: _K.text2,
                      ),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 财务部左右分栏：左边「产品结算 / 成本 / 利润」三格摘要，点一格右边出现那一块。
// ---------------------------------------------------------------------------

/// 左边一格：图标 + 块名、一个大数、一行小字。
class ProposalFinanceSplitTab {
  const ProposalFinanceSplitTab({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    this.sub = '',
    this.color = _K.heroInk,
  });

  final String id;
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String sub;
  final Color color;
}

/// 右侧内容在分栏里：块壳子据此去掉自己的标题行。
class _FinanceSplitScope extends InheritedWidget {
  const _FinanceSplitScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FinanceSplitScope>() != null;

  @override
  bool updateShouldNotify(_FinanceSplitScope oldWidget) => false;
}

/// 「资产走势」那种版式：左边一列格子，右边是选中那格的内容。
/// 宽屏格子宽一些；手机上格子收窄、数字自动缩小；特别窄（< 300）时格子横排在上面。
class ProposalFinanceSplit extends StatelessWidget {
  const ProposalFinanceSplit({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.detail,
    this.footer,
  });

  /// 左边格子下面的附加内容（负责人 / 复核人）。
  final Widget? footer;

  final List<ProposalFinanceSplitTab> tabs;
  final String selected;
  final ValueChanged<String> onSelect;
  final Widget detail;

  /// 当前位置是否在分栏右侧：块壳子据此去掉标题和上边距。
  static bool isInside(BuildContext context) => _FinanceSplitScope.of(context);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final pane = AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey('finance-split-$selected'),
            child: _FinanceSplitScope(child: detail),
          ),
        );
        Widget tile(ProposalFinanceSplitTab tab, {required bool dense}) =>
            _FinanceSplitTile(
              tab: tab,
              selected: tab.id == selected,
              dense: dense,
              onTap: () => onSelect(tab.id),
            );

        // App / 窄屏：概况与负责人上移横排，表单通栏变宽（不再左侧竖栏挤内容）。
        if (width < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      SizedBox(
                        width: 148,
                        child: tile(tabs[i], dense: true),
                      ),
                    ],
                  ],
                ),
              ),
              if (footer != null) ...[const SizedBox(height: 8), footer!],
              const SizedBox(height: 10),
              pane,
            ],
          );
        }
        final dense = width < 420;
        final railWidth = dense ? 92.0 : (width < 640 ? 112.0 : 136.0);
        final gap = dense ? 6.0 : 10.0;
        return Container(
          padding: EdgeInsets.all(dense ? 6 : 8),
          decoration: BoxDecoration(
            color: _surface(context, const Color(0xFFFAF9FD)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _border(context, const Color(0xFFE7E3F2)),
            ),
          ),
          // 负责人不放进左侧窄栏：名字比栏宽时会被右侧表单盖住。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: railWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < tabs.length; i++) ...[
                          if (i > 0) SizedBox(height: gap),
                          tile(tabs[i], dense: dense),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(child: pane),
                ],
              ),
              if (footer != null) ...[SizedBox(height: gap), footer!],
            ],
          ),
        );
      },
    );
  }
}

class _FinanceSplitTile extends StatelessWidget {
  const _FinanceSplitTile({
    required this.tab,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final ProposalFinanceSplitTab tab;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 与主 hero 同一套淡色：选中是淡蓝灰底 + 细边，图标、名称用 hero 墨蓝，数字深灰；不再按块上色。
    const accent = _K.heroInk;
    const soft = _K.heroBg;
    const edge = _K.heroBorder;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.fromLTRB(dense ? 8 : 10, 9, dense ? 6 : 8, 10),
          decoration: BoxDecoration(
            color: _surface(context, selected ? soft : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _border(context, selected ? edge : _K.rowLine),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _surface(
                        context,
                        selected ? const Color(0xFFDCE4F6) : _K.heroBg,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      tab.icon,
                      size: 13,
                      color: _c(context, selected ? accent : _K.grey),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(
                        context,
                        size: dense ? 11.5 : 12.5,
                        weight: FontWeight.w600,
                        color: selected ? accent : _K.text2,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 5 : 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: tab.value,
                        style: _mono(
                          context,
                          size: dense ? 17 : 19,
                          weight: FontWeight.w700,
                          color: _K.ink,
                        ),
                      ),
                      if (tab.unit.isNotEmpty)
                        TextSpan(
                          text: ' ${tab.unit}',
                          style: _sans(
                            context,
                            size: dense ? 10 : 11,
                            weight: FontWeight.w500,
                            color: _K.grey,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
