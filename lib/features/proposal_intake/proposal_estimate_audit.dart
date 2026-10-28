import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'proposal_cost_estimate.dart';
import 'proposal_estimate_summary.dart';
import 'proposal_finance_formula.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_ui.dart';
import 'proposal_remote_finance.dart';

/// 「测算过程」透视：把后端这次测算的每一步摊开——规模怎么来的、每条结算怎么乘、
/// 收入 / 成本每一行用的公式和代入、最后怎么汇总——并自动做一遍对账，标出可疑的地方。
/// 只读；数字全部来自后端测算结果（和页面上显示的是同一份），这里不重新算钱，只做核对。
Future<void> showProposalEstimateAudit({
  required BuildContext context,
  required ProposalRemoteFinanceResult result,
  required Map<String, dynamic> form,
  String title = '',
}) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final body = ProposalEstimateAudit(result: result, form: form, title: title);
  if (!wide) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(child: body),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1040,
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
        ),
        child: body,
      ),
    ),
  );
}

/// 右上角「测算过程」整页透视先不露出（测算合计卡里的「算法」已经够用）；要再打开改成 true。
const bool kProposalEstimateAuditButton = false;

/// 和结算比例同一条规则。空字符串按 0，不走「没填比例时按 1」的测算兜底。
double _ratioOf(String raw) {
  if (raw.trim().isEmpty) return 0;
  return proposalParseSettleRatio(raw);
}

/// 测算合计「算法」用的简版步骤，按指标分开：点「收入」只看收入怎么算，点「成本」只看成本怎么算。
/// key 和测算合计左边的指标名一致：年化规模 / 收入 / 成本 / 利润 / 月均规模 / 周转资金。
/// 所有数字、代入都来自后端这次测算，这里只负责排成一步一步。
Map<String, List<ProposalEstimateCalcStep>> proposalEstimateCalcSteps(
  ProposalRemoteFinanceResult result,
  Map<String, dynamic> form,
) => ProposalEstimateAudit(result: result, form: form).calcSteps();

enum _CheckLevel { ok, warn, error }

class _Check {
  const _Check(this.level, this.title, [this.detail = '']);
  final _CheckLevel level;
  final String title;
  final String detail;
}

/// 一条产品结算在测算里的样子。
class _SettleAudit {
  _SettleAudit({
    required this.product,
    required this.owner,
    required this.kind,
    required this.bill,
    required this.price,
    required this.formula,
    required this.scale,
    required this.share,
    required this.amount,
    required this.perUnit,
    required this.substitution,
    required this.found,
    this.ratioRaw = '',
    this.unitRaw = '',
    this.face = 0,
    this.tier = false,
    this.redemption = '',
    this.rawAmount = 0,
    this.promotion = false,
  });

  /// 电子券采购款的预计核销率（空 = 不折算）。
  final String redemption;

  /// 后端结算表里的金额（核销率折算前）。
  final double rawAmount;

  /// 推广费：后端按「销售规模 ÷ 券包面值 × 主产品结算价 × 比例」算，不是简单的规模 × 比例。
  final bool promotion;

  final String ratioRaw;
  final String unitRaw;
  final double face;
  final bool tier;

  final String product;
  final String owner;
  final String kind; // 收入 / 项目成本 / 电子券采购款
  final String bill;
  final String price;
  final String formula;
  final double scale;
  final double share;
  final double amount;
  final double perUnit;
  final String substitution;

  /// 后端这次测算里有没有这一条（没有说明这条没参与计算）。
  final bool found;
}

class ProposalEstimateAudit extends StatelessWidget {
  const ProposalEstimateAudit({
    super.key,
    required this.result,
    required this.form,
    this.title = '',
  });

  final ProposalRemoteFinanceResult result;
  final Map<String, dynamic> form;
  final String title;

  static const _bucketOrder = [
    (kProposalCostCategoryProject, '项目成本'),
    (kProposalCostCategoryBusiness, '业务成本'),
    (kProposalCostCategoryTax, '税务成本'),
  ];

  bool get _businessSealed => form['businessCostRedacted'] == true;

  static String _n(double v, {int digits = 2}) {
    if (v.isNaN || v.isInfinite) return '—';
    final fixed = v.toStringAsFixed(digits);
    final trimmed = fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : fixed;
    final neg = trimmed.startsWith('-');
    final body = neg ? trimmed.substring(1) : trimmed;
    final parts = body.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  static String _pct(double v) => v.isNaN || v.isInfinite ? '—' : '${_n(v * 100)}%';

  static bool _same(double a, double b) =>
      (a - b).abs() <= math.max(0.02, b.abs() * 0.0005);

  double? _summaryNum(String key) => (result.summary[key] as num?)?.toDouble();

  List<_SettleAudit> _settlements() {
    final out = <_SettleAudit>[];
    void add(ProposalSkuDetailRow sku, String owner) {
      final name = sku.displayName.trim().isEmpty ? '未命名产品' : sku.displayName.trim();
      final rows = proposalIntakeSkuSettlements(sku);
      for (final row in rows) {
        final t = row.terms;
        final bill = t.billType.trim().split('/').last.trim();
        final coupon = row.isCost && (row.id.endsWith('-coupon') || bill == '券使用成本');
        final hit = result.settlement(sku.id, row.id);
        // 和后端 peSettlePriceText 一样：最后选的方式才算，另一种方式留下的数不用。
        var ratio = t.settleRatio.trim();
        var unit = t.settleUnitPrice.trim();
        final legacy = t.settlePrice.trim();
        if (ratio.isEmpty && unit.isEmpty && legacy.isNotEmpty) {
          if (legacy.contains('%') || t.settleMode.trim() == '按结算比例') {
            ratio = legacy;
          } else {
            unit = legacy;
          }
        }
        switch (t.priceMode.trim()) {
          case kProposalSettlePriceModeUnit:
            ratio = '';
          case kProposalSettlePriceModeDirect:
            unit = '';
          case kProposalSettlePriceModeTier:
            ratio = '';
            unit = '';
        }
        // 电子券采购款填了预计核销率：年测算再乘核销率（后端 peApplyCouponRedemption）。
        final redemption = coupon ? t.expectedRedemptionRate.trim() : '';
        var amount = (hit['amount'] as num?)?.toDouble() ?? 0;
        if (redemption.isNotEmpty) amount = amount * _ratioOf(redemption);
        out.add(
          _SettleAudit(
            product: name,
            owner: owner,
            kind: coupon ? '电子券采购款' : (row.isCost ? '项目成本' : '收入'),
            bill: bill.isEmpty ? (row.isCost ? '未选成本类型' : '渠道结算款') : bill,
            price: t.settleByTier
                ? '按阶梯'
                : (ratio.isNotEmpty
                      ? '比例 $ratio'
                      : (unit.isNotEmpty ? '单价 $unit 元' : '未填')),
            formula: t.displayFormula.trim(),
            scale: (hit['scale'] as num?)?.toDouble() ?? 0,
            share: (hit['share'] as num?)?.toDouble() ?? 0,
            amount: amount,
            redemption: redemption,
            rawAmount: (hit['amount'] as num?)?.toDouble() ?? 0,
            promotion: t.isPromotionFee,
            perUnit: (hit['perUnit'] as num?)?.toDouble() ?? 0,
            substitution: '${hit['substitution'] ?? ''}',
            found: hit.isNotEmpty,
            ratioRaw: ratio,
            unitRaw: unit,
            face: proposalIntakeSkuSettleFace(sku),
            tier: t.settleByTier,
          ),
        );
      }
    }

    for (final sku in proposalIntakeSkuDetails(form)) {
      add(sku, '主产品');
    }
    for (final sku in proposalIntakeChildProducts(form)) {
      add(sku, '关联产品');
    }
    return out;
  }

  List<ProposalProductFinanceEvaluation> get _products => [
    ...result.main.products,
    ...?result.children?.products,
  ];

  List<_Check> _checks(List<_SettleAudit> settles) {
    final total = result.total;
    final checks = <_Check>[];
    final coupon = total.procurement.amount;
    final revenue = total.revenue.amount;
    final gross = revenue + coupon;

    // 1. 规模
    final products = _products;
    if (products.isNotEmpty) {
      final sum = products.fold<double>(0, (s, p) => s + p.evaluation.salesScale);
      checks.add(
        _same(sum, total.salesScale)
            ? _Check(_CheckLevel.ok, '各产品年化规模加起来 = 总规模', '${_n(sum)} 万')
            : _Check(
                _CheckLevel.warn,
                '各产品年化规模加起来 ≠ 总规模',
                '产品合计 ${_n(sum)} 万，总规模 ${_n(total.salesScale)} 万，差 ${_n(sum - total.salesScale)} 万。'
                    '通常是市场部填了总规模、产品里又各自填了规模，两边对不上。',
              ),
      );
    }
    if (total.salesScale <= 0) {
      checks.add(const _Check(_CheckLevel.error, '年化规模是 0', '后面的收入、成本都会是 0，请先填规模。'));
    }

    // 2. 收入 = 各产品收入之和
    if (products.length > 1) {
      final sum = products.fold<double>(0, (s, p) => s + p.evaluation.revenue.amount);
      checks.add(
        _same(sum, revenue)
            ? _Check(_CheckLevel.ok, '各产品收入加起来 = 总收入', '${_n(sum)} 万')
            : _Check(_CheckLevel.warn, '各产品收入加起来 ≠ 总收入', '产品合计 ${_n(sum)} 万，总收入 ${_n(revenue)} 万'),
      );
    }

    // 3. 每个产品：结算里的收入金额 vs 收入公式算出来的
    for (final p in products) {
      final rows = settles.where((s) => s.product == p.name && s.kind == '收入').toList();
      if (rows.isEmpty) continue;
      final fromSettle = rows.fold<double>(0, (s, r) => s + r.amount);
      final fromFormula = p.evaluation.revenue.amount + p.evaluation.procurement.amount;
      if (!_same(fromSettle, fromFormula)) {
        checks.add(
          _Check(
            _CheckLevel.warn,
            '「${p.name}」收入结算合计和收入公式算的不一致',
            '结算各条加起来 ${_n(fromSettle)} 万，收入公式（扣券前）${_n(fromFormula)} 万。'
                '看一下收入公式：${p.evaluation.revenue.formula?.name ?? '未选'}',
          ),
        );
      }
    }

    // 4. 电子券采购款
    if (coupon > 0) {
      final ratio = gross > 0 ? coupon / gross : 1.0;
      checks.add(
        ratio >= 0.5
            ? _Check(
                _CheckLevel.error,
                '电子券采购款占结算收入 ${_pct(ratio)}，收入只剩 ${_n(revenue)} 万',
                '电子券采购款是挂在收入下面、从收入里扣的那部分。比例这么高，'
                    '像是把电子券采购款（如 97%）填成了「券使用成本」。请到产品结算里核对下面标出的几条。',
              )
            : _Check(_CheckLevel.ok, '电子券采购款已从收入里扣', '结算收入 ${_n(gross)} − 电子券采购款 ${_n(coupon)} = ${_n(revenue)} 万'),
      );
    }
    if (revenue <= 0 && total.salesScale > 0) {
      checks.add(_Check(_CheckLevel.error, '收入是 ${_n(revenue)} 万', '有规模却没有收入：检查收入结算的比例 / 单价和收入公式。'));
    }

    // 5. 结算条目
    final unfilled = settles.where((s) => s.price == '未填').toList();
    if (unfilled.isNotEmpty) {
      checks.add(
        _Check(
          _CheckLevel.warn,
          '${unfilled.length} 条结算没填比例或单价',
          unfilled.map((s) => '${s.product} · ${s.kind} · ${s.bill}').join('\n'),
        ),
      );
    }
    final missing = settles.where((s) => !s.found).toList();
    if (missing.isNotEmpty) {
      checks.add(
        _Check(
          _CheckLevel.warn,
          '${missing.length} 条结算没有参与这次测算',
          missing.map((s) => '${s.product} · ${s.kind} · ${s.bill}').join('\n'),
        ),
      );
    }
    final zero = settles.where((s) => s.found && s.price != '未填' && s.price != '按阶梯' && s.share == 0).toList();
    if (zero.isNotEmpty) {
      checks.add(
        _Check(
          _CheckLevel.warn,
          '${zero.length} 条结算份额算出来是 0',
          '填了单价但产品没有面值时，单价折不成比例。\n${zero.map((s) => '${s.product} · ${s.kind} · ${s.price}').join('\n')}',
        ),
      );
    }

    // 6. 待补 / 缺字段的行
    final pending = <String>[];
    void scan(String group, ProposalFinanceLine line) {
      if (line.pending || line.missing.isNotEmpty) {
        final why = [
          if (line.missing.isNotEmpty) '缺 ${line.missing.join('、')}',
          if (line.pending && line.substitution.isNotEmpty) line.substitution,
        ].join('；');
        pending.add('$group · ${line.name}${why.isEmpty ? '' : '：$why'}');
      }
    }
    scan('收入', total.revenue);
    for (final (key, label) in _bucketOrder) {
      if (key == kProposalCostCategoryBusiness && _businessSealed) continue;
      for (final line in total.bucket(key)?.lines ?? const <ProposalFinanceLine>[]) {
        scan(label, line);
      }
    }
    checks.add(
      pending.isEmpty
          ? const _Check(_CheckLevel.ok, '所有公式都算出了结果')
          : _Check(_CheckLevel.warn, '${pending.length} 行没算完整（按 0 计）', pending.join('\n')),
    );

    // 7. 各类成本合计 = 明细之和
    for (final (key, label) in _bucketOrder) {
      if (key == kProposalCostCategoryBusiness && _businessSealed) continue;
      final bucket = total.bucket(key);
      if (bucket == null) continue;
      final sum = bucket.lines.fold<double>(0, (s, l) => s + l.amount);
      if (!_same(sum, bucket.total)) {
        checks.add(_Check(_CheckLevel.warn, '$label 合计 ≠ 明细之和', '明细 ${_n(sum)} 万，合计 ${_n(bucket.total)} 万'));
      }
    }

    // 8. 汇总
    final project = total.total(kProposalCostCategoryProject);
    final business = _businessSealed ? 0.0 : total.total(kProposalCostCategoryBusiness);
    final tax = total.total(kProposalCostCategoryTax);
    final costTotal = _summaryNum('costTotal');
    if (costTotal != null && !_businessSealed) {
      checks.add(
        _same(costTotal, project + business + tax)
            ? _Check(_CheckLevel.ok, '成本合计 = 项目 + 业务 + 税务', '${_n(costTotal)} 万')
            : _Check(_CheckLevel.warn, '成本合计对不上', '汇总 ${_n(costTotal)} 万，三类相加 ${_n(project + business + tax)} 万'),
      );
    }
    final spread = _summaryNum('spread');
    if (spread != null && spread < 0) {
      checks.add(_Check(_CheckLevel.error, '利差为负：${_n(spread)} 万', '收入不够覆盖成本，核对收入比例和各项成本。'));
    }
    if (tax > revenue && revenue > 0) {
      checks.add(_Check(_CheckLevel.warn, '税务成本 ${_n(tax)} 万比收入还高', '多半是收入被电子券采购款扣得太多，或者税率填错。'));
    }
    return checks;
  }

  /// 产品自己在结算里填的年化规模（按月填的 × 12）。
  static double _ownScale(ProposalSkuDetailRow sku) {
    var total = 0.0;
    for (final row in proposalIntakeSkuSettlements(sku)) {
      final n = double.tryParse(row.terms.scale.trim()) ?? 0;
      total += row.terms.scalePeriod.trim() == '月' ? n * 12 : n;
    }
    return total;
  }

  /// 一个产品的年化规模是怎么来的：自己填了就用自己的；没填就按平摊。
  String _scaleDetail(ProposalProductFinanceEvaluation p) {
    final value = p.evaluation.salesScale;
    final own = _ownScale(p.sku);
    if (own > 0) {
      final parts = [
        for (final row in proposalIntakeSkuSettlements(p.sku))
          if ((double.tryParse(row.terms.scale.trim()) ?? 0) > 0)
            row.terms.scalePeriod.trim() == '月'
                ? '${row.terms.scale.trim()} 万/月 × 12'
                : '${row.terms.scale.trim()} 万/年',
      ];
      return '这个产品在结算里自己填了规模：${parts.join(' + ')}，合计 ${_n(own)} 万/年。';
    }
    final group = p.isChild ? proposalIntakeChildProducts(form) : proposalIntakeSkuDetails(form);
    final groupTotal = p.isChild ? (result.children?.salesScale ?? 0) : result.main.salesScale;
    final owned = group.fold<double>(0, (sum, sku) => sum + _ownScale(sku));
    final missing = group.where((sku) => _ownScale(sku) <= 0).length;
    if (groupTotal - owned <= 0 || missing == 0) {
      return p.isChild
          ? '关联产品没填自己的规模，关联产品这一组也没有总规模可以平摊，所以是 0。\n要算它，请在这个关联产品的结算里填年化规模。'
          : '这个产品没填自己的规模，总规模也没有剩下可以平摊的部分，所以是 0。';
    }
    return '这个产品没填自己的规模，按平摊：\n'
        '（${p.isChild ? '关联产品' : ''}总规模 ${_n(groupTotal)} − 已填规模的产品合计 ${_n(owned)}）'
        ' ÷ 没填规模的 $missing 个产品 = ${_n(value)} 万';
  }

  /// 一条结算的年化金额是怎么来的（和后端同一套规则）。
  String _settleDetail(_SettleAudit s) {
    if (!s.found) {
      return '这条结算这次没有参与测算：可能被共用结算替代了，或者这个产品不在测算范围里。';
    }
    if (s.promotion && !s.tier && s.ratioRaw.isNotEmpty) {
      return [
        '推广费按固定比例：销售规模 ÷ 券包面值 × 主产品结算价 × 推广费比例',
        if (s.substitution.isNotEmpty) s.substitution,
      ].join('\n');
    }
    final shareLine = s.tier
        ? '按阶梯方案：看规模落在哪一档${s.promotion ? '（推广费的计费基数是 规模 ÷ 面值 × 主产品结算价）' : ''}'
        : (s.ratioRaw.isNotEmpty
              ? '结算比例 ${s.ratioRaw}，即 ${_pct(s.share)}'
              : (s.unitRaw.isNotEmpty
                    ? (s.face > 0
                          ? '按面值：单价 ${s.unitRaw} 元 ÷ 面值 ${_n(s.face)} 元 = ${_pct(s.share)}'
                          : '按面值：填了单价 ${s.unitRaw} 元，但产品没有面值，算不出来，按 0')
                    : '比例、单价都没填，按 0 算'));
    final lines = [
      '规模：${_n(s.scale)} 万（这个产品的年化规模，点「年化规模」可看它怎么来的）',
      shareLine,
      if (s.substitution.isNotEmpty) '后端代入：${s.substitution}',
      if (s.redemption.isNotEmpty)
        '预计核销率 ${s.redemption}：${_n(s.rawAmount)} × ${_pct(_ratioOf(s.redemption))} = ${_n(s.amount)} 万',
      if (s.formula.isNotEmpty) '结算口径：${s.formula}',
      if (s.amount == 0)
        '为什么是 0：${s.scale == 0 ? '这个产品的规模是 0' : (s.share == 0 && !s.tier ? '份额是 0' : '阶梯方案在这个规模下不收费')}',
    ];
    return lines.join('\n');
  }

  /// 阶梯档位比例高得离谱（> 30%）时的提示：多半是把 0.575% 填成了 0.575（= 57.5%）。
  String? _tierRateNote(ProposalFinanceLine line) {
    if (!line.substitution.contains('阶梯')) return null;
    final rates = RegExp(r'([0-9]+(?:\.[0-9]+)?)%')
        .allMatches(line.substitution)
        .map((m) => double.tryParse(m.group(1)!) ?? 0)
        .where((v) => v > 30)
        .toList();
    if (rates.isEmpty) return null;
    final pct = rates.first;
    final raw = pct / 100;
    return '注意：档位比例是 ${_n(pct)}%，偏高。阶梯里的比例按小数填（${_n(raw, digits: 4)} 就是 ${_n(pct)}%）；'
        '如果本意是 ${_n(raw, digits: 4)}%，应该填 ${_n(raw / 100, digits: 6)}';
  }

  String _lineDetail(String group, ProposalFinanceLine line) {
    final f = line.formula;
    final rateNote = _tierRateNote(line);
    final lines = [
      if (f != null) '公式：${f.name}',
      if (f != null && f.expression.trim().isNotEmpty && f.expression.trim() != f.name) '表达式：${f.expression.trim()}',
      if (f == null) '没有选公式',
      if (line.locked) '这一项跟着产品结算算，每条怎么算见下面的代入',
      if (line.substitution.isNotEmpty) '代入：${line.substitution}',
      if (line.missing.isNotEmpty) '缺：${line.missing.join('、')}，所以按 0 计',
      '结果：${_n(line.amount)} 万',
      if (rateNote != null) rateNote,
      if (line.amount == 0 && line.missing.isEmpty)
        line.pending
            ? '为什么是 0：这一项还没算完（${line.substitution.isEmpty ? '规则未配置' : line.substitution}）'
            : '为什么是 0：没有对应的产品结算，或者比例 / 基数是 0',
    ];
    return '$group\n${lines.join('\n')}';
  }

  Map<String, List<ProposalEstimateCalcStep>> calcSteps() {
    final total = result.total;
    final scale = total.salesScale;
    final coupon = total.procurement.amount;
    final revenue = total.revenue.amount;
    final gross = revenue + coupon;
    final settles = _settlements();
    final products = _products;

    String settleFormula(_SettleAudit s) {
      if (!s.found) return '没参与测算';
      if (s.tier) return '按阶梯方案';
      if (s.ratioRaw.isEmpty && s.unitRaw.isEmpty) return '比例 / 单价没填';
      return '${_n(s.scale)} × ${_pct(s.share)}';
    }

    // ---- 年化规模：每个产品的规模加起来 ----
    final scaleSteps = <ProposalEstimateCalcStep>[
      for (final p in products)
        ProposalEstimateCalcStep(
          p.isChild ? '${p.name}（关联）' : p.name,
          _ownScale(p.sku) > 0 ? '自己填的规模' : '平摊',
          _n(p.evaluation.salesScale),
          sub: true,
          detail: _scaleDetail(p),
        ),
      ProposalEstimateCalcStep(
        '年化规模',
        products.length > 1 ? '${products.length} 个产品相加' : '市场部 / 产品年化规模',
        _n(scale),
        strong: true,
        warn: scale <= 0,
        detail: [
          '总规模取市场部填的年化规模；没填就用各产品结算里填的规模相加。',
          if (products.isNotEmpty)
            '各产品：${products.map((p) => '${p.name} ${_n(p.evaluation.salesScale)}').join('，')}',
        ].join('\n'),
      ),
    ];

    // ---- 收入：按产品（和后端每个产品的收入公式一致）→ 结算收入 → 扣电子券采购款 ----
    final revenueSteps = <ProposalEstimateCalcStep>[];
    for (final p in products) {
      final e = p.evaluation;
      final productGross = e.revenue.amount + e.procurement.amount;
      final incomes = settles.where((s) => s.product == p.name && s.kind == '收入').toList();
      final f = e.revenue.formula;
      revenueSteps.add(ProposalEstimateCalcStep(
        p.isChild ? '${p.name}（关联）' : p.name,
        incomes.length == 1 && incomes.first.found && !incomes.first.tier && incomes.first.share > 0
            ? '${_n(incomes.first.scale)} × ${_pct(incomes.first.share)}'
            : (f?.name ?? '按收入结算'),
        _n(productGross),
        sub: true,
        warn: incomes.isEmpty || incomes.any((s) => !s.found || (s.ratioRaw.isEmpty && s.unitRaw.isEmpty && !s.tier)),
        detail: [
          '规模：${_n(e.salesScale)} 万',
          for (final s in incomes) '收入结算 · ${s.bill}：${_settleDetail(s).replaceAll('\n', '；')}',
          if (incomes.isEmpty) '这个产品没有收入结算，收入按 0。',
          if (f != null) '收入公式：${f.name}${f.expression.trim().isNotEmpty && f.expression.trim() != f.name ? '（${f.expression.trim()}）' : ''}',
          if (e.revenue.substitution.isNotEmpty) '后端代入：${e.revenue.substitution}',
          if (e.procurement.amount > 0) '扣电子券采购款之前：${_n(productGross)} 万',
          if (e.revenue.missing.isNotEmpty) '缺：${e.revenue.missing.join('、')}',
        ].join('\n'),
      ));
    }
    revenueSteps.add(ProposalEstimateCalcStep(
      '结算收入',
      products.length > 1 ? '${products.length} 个产品相加' : (total.revenue.formula?.name ?? '按收入结算'),
      _n(gross),
      strong: coupon == 0,
      warn: gross <= 0 && scale > 0,
      detail: [
        '结算收入 = 各产品收入公式算出来的合计（扣电子券采购款之前）。',
        if (gross == 0) '为什么是 0：${scale == 0 ? '规模是 0' : '收入结算的比例 / 单价没填，或收入公式没选'}',
      ].join('\n'),
    ));
    if (coupon > 0) {
      for (final s in settles.where((s) => s.kind == '电子券采购款')) {
        revenueSteps.add(ProposalEstimateCalcStep(
          '${s.product} · 电子券采购款',
          s.redemption.isNotEmpty
              ? '${_n(s.scale)} × ${_pct(s.share)} × 核销率 ${s.redemption}'
              : (s.found ? '${_n(s.scale)} × ${_pct(s.share)}' : '没参与测算'),
          s.found ? '−${_n(s.amount)}' : '—',
          sub: true,
          warn: !s.found,
          detail: '${_settleDetail(s)}\n电子券采购款挂在收入下面，直接从收入里扣，不算项目成本。',
        ));
      }
      final listed = settles.where((s) => s.kind == '电子券采购款').fold<double>(0, (sum, s) => sum + s.amount);
      final couponHeavy = gross > 0 && coupon / gross >= 0.5;
      revenueSteps.add(ProposalEstimateCalcStep(
        '收入',
        '结算收入 ${_n(gross)} − 电子券采购款 ${_n(coupon)}',
        _n(revenue),
        strong: true,
        warn: couponHeavy,
        detail: [
          '收入 = 结算收入 ${_n(gross)} − 电子券采购款 ${_n(coupon)} = ${_n(revenue)} 万',
          if (!_same(listed, coupon))
            '上面各条电子券采购款加起来 ${_n(listed)}，后端扣的是 ${_n(coupon)}（共用结算里的电子券采购款也算在内）。',
          if (couponHeavy)
            '电子券采购款占结算收入 ${_pct(coupon / gross)}，像是把采购款填成了「券使用成本」，核对上面几条电子券采购款。',
        ].join('\n'),
      ));
    }
    if (total.rating.isNotEmpty) {
      revenueSteps.add(ProposalEstimateCalcStep(
        '任务评级 ${total.rating}',
        total.ratingRule.isEmpty ? '按收入档位' : total.ratingRule,
        '',
        sub: true,
        detail: '评级按收入（已扣电子券采购款）${_n(revenue)} 万落在哪一档定。',
      ));
    }

    // ---- 成本 ----
    final project = total.total(kProposalCostCategoryProject);
    final business = total.total(kProposalCostCategoryBusiness);
    final tax = total.total(kProposalCostCategoryTax);
    final costSteps = <ProposalEstimateCalcStep>[];
    for (final (key, label) in _bucketOrder) {
      if (key == kProposalCostCategoryBusiness && _businessSealed) {
        costSteps.add(const ProposalEstimateCalcStep(
          '业务成本',
          '仅财务部负责人一、总裁可见',
          '—',
          sub: true,
          detail: '业务成本只有财务部负责人一和总裁能看到金额和算法。',
        ));
        continue;
      }
      final lines = total.bucket(key)?.lines ?? const <ProposalFinanceLine>[];
      if (lines.isEmpty) {
        costSteps.add(ProposalEstimateCalcStep(
          label,
          '没有',
          '0',
          sub: true,
          detail: key == kProposalCostCategoryProject
              ? '产品结算里没有项目成本（应付）这一类，所以项目成本是 0。'
              : (key == kProposalCostCategoryBusiness ? '财务部负责人一还没选业务成本公式，所以是 0。' : '没有选税目，所以是 0。'),
        ));
        continue;
      }
      for (final line in lines) {
        final undone = line.pending || line.missing.isNotEmpty;
        costSteps.add(ProposalEstimateCalcStep(
          '$label · ${line.name}',
          undone
              ? (line.missing.isNotEmpty ? '缺 ${line.missing.join('、')}，按 0 计' : '没算完，按 0 计')
              : (line.substitution.isEmpty ? (line.formula?.name ?? '') : line.substitution),
          _n(line.amount),
          sub: true,
          warn: undone || _tierRateNote(line) != null,
          detail: _lineDetail(label, line),
        ));
      }
    }
    final costTotal = _summaryNum('costTotal') ?? (project + (_businessSealed ? 0 : business) + tax);
    costSteps.add(ProposalEstimateCalcStep(
      '成本',
      _businessSealed
          ? '项目 ${_n(project)} + 业务（仅授权） + 税务 ${_n(tax)}'
          : '项目 ${_n(project)} + 业务 ${_n(business)} + 税务 ${_n(tax)}',
      _n(costTotal),
      strong: true,
      detail: '成本 = 项目成本 + 业务成本 + 税务成本。\n电子券采购款已经从收入里扣掉，不在这里重复算。',
    ));

    // ---- 利润（利差） ----
    final spread = _summaryNum('spread') ?? (revenue - costTotal);
    final profitSteps = <ProposalEstimateCalcStep>[
      ProposalEstimateCalcStep('收入', '', _n(revenue), sub: true, detail: '点左边「收入」看收入怎么算。'),
      ProposalEstimateCalcStep('成本', '', '−${_n(costTotal)}', sub: true, detail: '点左边「成本」看成本怎么算。'),
      ProposalEstimateCalcStep(
        '利润',
        '收入 − 成本${scale > 0 ? '，占规模 ${_pct(spread / scale)}' : ''}',
        _n(spread),
        strong: true,
        warn: spread < 0,
        detail: '利润 = 收入 ${_n(revenue)} − 成本 ${_n(costTotal)} = ${_n(spread)} 万'
            '${scale > 0 ? '\n占规模：${_n(spread)} ÷ ${_n(scale)} = ${_pct(spread / scale)}' : ''}',
      ),
    ];

    // ---- 月均规模、周转资金 ----
    final monthly = _summaryNum('monthlyScale') ?? scale / 12;
    final times = proposalFinanceAmount(
      proposalIntakeProductFinanceScope(form, owner: kProposalProductFinanceMain),
      kProposalTurnoverTimesKey,
    );
    final turnover = _summaryNum('turnoverCash');
    final monthlySteps = <ProposalEstimateCalcStep>[
      ProposalEstimateCalcStep('年化规模', '', _n(scale), sub: true, detail: '点左边「年化规模」看它怎么来的。'),
      ProposalEstimateCalcStep(
        '月均规模',
        '${_n(scale)} ÷ 12',
        _n(monthly),
        strong: true,
        detail: '月均规模 = 年化规模 ${_n(scale)} ÷ 12 个月 = ${_n(monthly)} 万',
      ),
    ];
    final turnoverSteps = <ProposalEstimateCalcStep>[
      ProposalEstimateCalcStep('月均规模', '${_n(scale)} ÷ 12', _n(monthly), sub: true, detail: '年化规模 ÷ 12 个月。'),
      ProposalEstimateCalcStep(
        '每月周转次数',
        '财务部填写',
        times > 0 ? _n(times) : '—',
        sub: true,
        warn: times <= 0,
        detail: times > 0 ? '财务部「经营与周转」里填的每月周转次数。' : '财务部还没填每月周转次数，周转资金算不出来。',
      ),
      ProposalEstimateCalcStep(
        '周转资金',
        times > 0 ? '${_n(monthly)} ÷ ${_n(times)}' : '没填每月周转次数',
        turnover == null ? '—' : _n(turnover),
        strong: true,
        detail: times > 0
            ? '周转资金 = 月均规模 ${_n(monthly)} ÷ 每月周转 ${_n(times)} 次 = ${turnover == null ? '—' : _n(turnover)} 万\n意思是：一个月要周转几次，账上就要备多少钱。'
            : '没填每月周转次数，算不出来。',
      ),
    ];
    return {
      '年化规模': scaleSteps,
      '收入': revenueSteps,
      '成本': costSteps,
      '利润': profitSteps,
      '利差': profitSteps,
      '月均规模': monthlySteps,
      '周转资金': turnoverSteps,
    };
  }

  @override
  Widget build(BuildContext context) {
    final settles = _settlements();
    final checks = _checks(settles);
    final errors = checks.where((c) => c.level == _CheckLevel.error).length;
    final warns = checks.where((c) => c.level == _CheckLevel.warn).length;
    final oks = checks.length - errors - warns;
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    return Material(
      color: c(ProposalPalette.app, DunesColorRole.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
            decoration: BoxDecoration(
              color: c(Colors.white, DunesColorRole.surface),
              border: Border(bottom: BorderSide(color: c(ProposalPalette.borderSoft, DunesColorRole.border))),
            ),
            child: Row(
              children: [
                Icon(Icons.calculate_outlined, size: 20, color: c(ProposalPalette.purpleDeep)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('测算过程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c(ProposalPalette.text))),
                      Text(
                        [
                          if (title.isNotEmpty) title,
                          '单位万元 · 后端测算 ${result.engineVersion}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: c(ProposalPalette.text3)),
                      ),
                    ],
                  ),
                ),
                _Pill(label: '$errors 处错误', color: errors > 0 ? const Color(0xFFB42318) : ProposalPalette.text3),
                const SizedBox(width: 6),
                _Pill(label: '$warns 处要看', color: warns > 0 ? ProposalPalette.amber : ProposalPalette.text3),
                const SizedBox(width: 6),
                _Pill(label: '$oks 项通过', color: ProposalPalette.green),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close_rounded, color: c(ProposalPalette.text2)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _Section(
                  no: '0',
                  title: '自动核对',
                  hint: '先看这里：红色是算出来明显不对的，琥珀色是数对不上或没填全的。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final check in checks) _CheckRow(check: check)],
                  ),
                ),
                _Section(
                  no: '1',
                  title: '规模',
                  hint: '每个产品的年化规模：产品结算里填了规模就用产品自己的，没填的按「总规模 − 已填的」平均分。',
                  child: _scaleTable(),
                ),
                _Section(
                  no: '2',
                  title: '每条结算',
                  hint: '年化金额 = 产品年化规模 × 份额。份额：填比例就是比例；填单价就是 单价 ÷ 面值；按阶梯的按阶梯方案算。',
                  child: _settleTable(settles),
                ),
                _Section(
                  no: '3',
                  title: '收入',
                  hint: '每个产品按所选收入公式算出结算收入，再扣掉挂在收入下面的电子券采购款。',
                  child: _revenueTable(),
                ),
                _Section(
                  no: '4',
                  title: '成本',
                  hint: '项目成本来自产品结算里的项目成本；业务成本是财务部负责人一选的公式；税务成本按整份提案算一次。',
                  child: _costTable(),
                ),
                _Section(
                  no: '5',
                  title: '汇总',
                  hint: '页面顶部「测算合计」的每个数都从这里来。',
                  child: _summaryTable(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scaleTable() {
    final total = result.total;
    final products = _products;
    return _AuditTable(
      columns: const [
        _Col('产品', 4),
        _Col('归属', 2),
        _Col('年化规模', 2, numeric: true),
        _Col('月均', 2, numeric: true),
      ],
      rows: [
        for (final p in products)
          _Row([
            p.name,
            p.isChild ? '关联产品' : '主产品',
            _n(p.evaluation.salesScale),
            _n(p.evaluation.salesScale / 12),
          ]),
        _Row(['合计（总规模）', '', _n(total.salesScale), _n(total.salesScale / 12)], strong: true),
      ],
    );
  }

  Widget _settleTable(List<_SettleAudit> settles) {
    if (settles.isEmpty) return const _Empty('还没有产品结算');
    return _AuditTable(
      minWidth: 900,
      columns: const [
        _Col('产品', 3),
        _Col('类别', 2),
        _Col('名目', 2),
        _Col('比例 / 单价', 2),
        _Col('计算公式', 3),
        _Col('年化规模', 2, numeric: true),
        _Col('份额', 2, numeric: true),
        _Col('年化金额', 2, numeric: true),
        _Col('代入', 4),
      ],
      rows: [
        for (final s in settles)
          _Row(
            [
              s.owner == '主产品' ? s.product : '${s.product}（关联）',
              s.kind,
              s.bill,
              s.price,
              s.formula.isEmpty ? '—' : s.formula,
              s.found ? _n(s.scale) : '—',
              s.found ? _pct(s.share) : '—',
              s.found ? (s.kind == '电子券采购款' ? '−${_n(s.amount)}' : _n(s.amount)) : '未参与',
              s.substitution,
            ],
            tone: !s.found || s.price == '未填'
                ? _Tone.warn
                : (s.kind == '电子券采购款' ? _Tone.minus : _Tone.none),
          ),
      ],
    );
  }

  Widget _revenueTable() {
    final total = result.total;
    final products = _products;
    final rows = <_Row>[];
    for (final p in products) {
      final e = p.evaluation;
      rows.add(_Row([
        p.name,
        _formulaText(e.revenue.formula),
        e.revenue.substitution.isEmpty ? '—' : e.revenue.substitution,
        _n(e.revenue.amount + e.procurement.amount),
        e.procurement.amount == 0 ? '—' : '−${_n(e.procurement.amount)}',
        _n(e.revenue.amount),
      ], tone: e.revenue.pending || e.revenue.missing.isNotEmpty ? _Tone.warn : _Tone.none));
    }
    rows.add(_Row([
      '合计',
      '',
      '',
      _n(total.revenue.amount + total.procurement.amount),
      total.procurement.amount == 0 ? '—' : '−${_n(total.procurement.amount)}',
      _n(total.revenue.amount),
    ], strong: true));
    return _AuditTable(
      minWidth: 860,
      columns: const [
        _Col('产品', 3),
        _Col('收入公式', 4),
        _Col('代入', 5),
        _Col('结算收入', 2, numeric: true),
        _Col('电子券采购款', 2, numeric: true),
        _Col('收入', 2, numeric: true),
      ],
      rows: rows,
    );
  }

  static String _formulaText(ProposalFinanceFormula? f) {
    if (f == null) return '未选公式';
    final expression = f.expression.trim();
    if (expression.isEmpty || expression == f.name) return f.name;
    return '${f.name}\n$expression';
  }

  Widget _costTable() {
    final total = result.total;
    final rows = <_Row>[];
    for (final (key, label) in _bucketOrder) {
      if (key == kProposalCostCategoryBusiness && _businessSealed) {
        rows.add(_Row([label, '仅财务部负责人一、总裁可见', '', '', '—'], tone: _Tone.muted));
        continue;
      }
      final bucket = total.bucket(key);
      final lines = bucket?.lines ?? const <ProposalFinanceLine>[];
      if (lines.isEmpty) {
        rows.add(_Row([label, '（没有）', '', '', '0'], tone: _Tone.muted));
        continue;
      }
      for (final line in lines) {
        final flag = [
          if (line.missing.isNotEmpty) '缺 ${line.missing.join('、')}',
          if (line.pending) '未算完',
          if (line.locked) '跟产品结算',
        ].join(' · ');
        rows.add(_Row([
          label,
          line.name,
          _formulaText(line.formula),
          [line.substitution, if (flag.isNotEmpty) '（$flag）'].where((t) => t.isNotEmpty).join('\n'),
          _n(line.amount),
        ], tone: line.pending || line.missing.isNotEmpty ? _Tone.warn : _Tone.none));
      }
      rows.add(_Row(['$label 合计', '', '', '', _n(bucket?.total ?? 0)], strong: true));
    }
    return _AuditTable(
      minWidth: 860,
      columns: const [
        _Col('类别', 2),
        _Col('名目', 3),
        _Col('公式', 4),
        _Col('代入', 5),
        _Col('年化金额', 2, numeric: true),
      ],
      rows: rows,
    );
  }

  Widget _summaryTable() {
    final total = result.total;
    final scale = total.salesScale;
    final coupon = total.procurement.amount;
    final revenue = total.revenue.amount;
    final project = total.total(kProposalCostCategoryProject);
    final business = total.total(kProposalCostCategoryBusiness);
    final tax = total.total(kProposalCostCategoryTax);
    final costTotal = _summaryNum('costTotal') ?? (project + (_businessSealed ? 0 : business) + tax);
    final spread = _summaryNum('spread') ?? (revenue - costTotal);
    final monthly = _summaryNum('monthlyScale') ?? scale / 12;
    final turnover = _summaryNum('turnoverCash');
    final times = proposalFinanceAmount(
      proposalIntakeProductFinanceScope(form, owner: kProposalProductFinanceMain),
      kProposalTurnoverTimesKey,
    );
    return _AuditTable(
      columns: const [
        _Col('项目', 3),
        _Col('怎么算', 6),
        _Col('结果', 2, numeric: true),
      ],
      rows: [
        _Row(['年化规模', '各产品年化规模合计', _n(scale)]),
        _Row(['结算收入', '各产品收入公式算出来的合计（扣券前）', _n(revenue + coupon)]),
        _Row(['电子券采购款', '收入下面挂的电子券采购款合计', coupon == 0 ? '0' : '−${_n(coupon)}']),
        _Row(['收入', '${_n(revenue + coupon)} − ${_n(coupon)}', _n(revenue)], strong: true),
        _Row(['项目成本', '产品结算里的项目成本合计', _n(project)]),
        _Row(['业务成本', _businessSealed ? '仅财务部负责人一、总裁可见' : '所选业务成本公式合计', _businessSealed ? '—' : _n(business)]),
        _Row(['税务成本', '增值税及附加、印花税等', _n(tax)]),
        _Row([
          '成本合计',
          _businessSealed
              ? '${_n(project)} + 业务成本 + ${_n(tax)}'
              : '${_n(project)} + ${_n(business)} + ${_n(tax)}',
          _n(costTotal),
        ], strong: true),
        _Row(['利差', '${_n(revenue)} − ${_n(costTotal)}', _n(spread)], strong: true, tone: spread < 0 ? _Tone.warn : _Tone.none),
        _Row(['利差率', '${_n(spread)} ÷ ${_n(scale)}', scale > 0 ? _pct(spread / scale) : '—']),
        _Row(['月均规模', '${_n(scale)} ÷ 12', _n(monthly)]),
        _Row(['每月周转次数', '财务部填写', times > 0 ? _n(times) : '—']),
        _Row(['周转资金', times > 0 ? '${_n(monthly)} ÷ ${_n(times)}' : '没填周转次数', turnover == null ? '—' : _n(turnover)]),
        if (total.rating.isNotEmpty)
          _Row(['任务评级', total.ratingRule.isEmpty ? '按收入档位' : total.ratingRule, total.rating]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 小部件
// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fg = DunesColors.resolve(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.no, required this.title, required this.child, this.hint = ''});
  final String no;
  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c(Colors.white, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c(ProposalPalette.borderSoft, DunesColorRole.border)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c(ProposalPalette.purpleDeep),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(no, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c(ProposalPalette.text))),
                      if (hint.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(hint, style: TextStyle(fontSize: 11.5, height: 1.4, color: c(ProposalPalette.text3))),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});
  final _Check check;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    final (icon, color) = switch (check.level) {
      _CheckLevel.ok => (Icons.check_circle_rounded, ProposalPalette.green),
      _CheckLevel.warn => (Icons.error_outline_rounded, ProposalPalette.amber),
      _CheckLevel.error => (Icons.cancel_rounded, const Color(0xFFB42318)),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: check.level == _CheckLevel.error
            ? c(const Color(0xFFFDF1EF), DunesColorRole.surface)
            : null,
        border: Border(top: BorderSide(color: c(ProposalPalette.borderSoft, DunesColorRole.border))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: c(color)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c(ProposalPalette.text))),
                if (check.detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(check.detail, style: TextStyle(fontSize: 12, height: 1.45, color: c(ProposalPalette.text2))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
    child: Text(text, style: TextStyle(fontSize: 12.5, color: DunesColors.resolve(context, ProposalPalette.text3))),
  );
}

class _Col {
  const _Col(this.label, this.flex, {this.numeric = false});
  final String label;
  final int flex;
  final bool numeric;
}

enum _Tone { none, warn, minus, muted }

class _Row {
  const _Row(this.cells, {this.strong = false, this.tone = _Tone.none});
  final List<String> cells;
  final bool strong;
  final _Tone tone;
}

/// 整齐的只读表格：表头浅紫、数字列等宽右对齐、合计行加粗；窄屏横向滑动。
class _AuditTable extends StatelessWidget {
  const _AuditTable({required this.columns, required this.rows, this.minWidth = 560});
  final List<_Col> columns;
  final List<_Row> rows;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    Widget cell(String text, _Col col, {bool header = false, bool strong = false, _Tone tone = _Tone.none}) {
      final color = header
          ? ProposalPalette.text2
          : switch (tone) {
              _Tone.warn => const Color(0xFF9A5B0C),
              _Tone.minus => ProposalPalette.coral,
              _Tone.muted => ProposalPalette.text3,
              _Tone.none => ProposalPalette.text,
            };
      return Expanded(
        flex: col.flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: SelectableText(
            text,
            textAlign: col.numeric ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: header ? 11.5 : 12.5,
              height: 1.4,
              fontWeight: header || strong ? FontWeight.w700 : FontWeight.w400,
              color: c(color),
              fontFamily: col.numeric && !header ? kProposalProtoMono : null,
              fontFamilyFallback: col.numeric && !header ? kProposalProtoMonoFallback : null,
            ),
          ),
        ),
      );
    }

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: c(const Color(0xFFF4F1FB), DunesColorRole.surface),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final col in columns) cell(col.label, col, header: true)],
          ),
        ),
        for (var i = 0; i < rows.length; i++)
          Container(
            decoration: BoxDecoration(
              color: rows[i].strong
                  ? c(const Color(0xFFFAF8FE), DunesColorRole.surface)
                  : (rows[i].tone == _Tone.warn ? c(const Color(0xFFFFF8EC), DunesColorRole.surface) : null),
              border: Border(top: BorderSide(color: c(ProposalPalette.borderSoft, DunesColorRole.border))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns.length; j++)
                  cell(
                    j < rows[i].cells.length ? rows[i].cells[j] : '',
                    columns[j],
                    strong: rows[i].strong,
                    tone: rows[i].tone,
                  ),
              ],
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= minWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      },
    );
  }
}
