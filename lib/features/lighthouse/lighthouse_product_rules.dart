String lighthouseProductKey(String? product) => (product ?? '')
    .trim()
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'\s+'), '');

/// Exact transaction identities. Other brands and income products keep their rules.
bool lighthouseProductUsesGmv(String? product) => const {
  '满减券(交易)',
  '中石化满减券(交易)',
  '中石化普惠现金券(交易)',
}.contains(lighthouseProductKey(product));

/// 金刚位核销额换成 GMV：满减/中石化（毛利率也走 GMV）+ 移动点播 / 会员套餐订阅。
/// 点播、订阅的毛利率仍按运营商销售额，不进 [lighthouseProductUsesGmv]。
bool lighthouseProductReplacesVerifiedHeroWithGmv(String? product) {
  if (lighthouseProductUsesGmv(product)) return true;
  return const {'移动点播(积分)', '会员套餐订阅', '会员套餐点播'}.contains(
    lighthouseProductKey(product),
  );
}

String lighthouseGrossMarginDenominatorKey({
  String? product,
  String? group,
  String? basis,
}) => basis == 'gmv' || lighthouseProductUsesGmv(product)
    ? 'gmv'
    : (group ?? '').trim() == '运营商'
    ? 'sales'
    : 'verifiedSales';
