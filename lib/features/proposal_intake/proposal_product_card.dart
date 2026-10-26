import 'package:flutter/material.dart';

import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'proposal_intake_models.dart';
import 'proposal_intake_ui.dart';

/// 科技部、财务部共用的「产品卡」：一个产品一张卡，两个板块里编号、顺序、版式完全一样。
///
/// 卡片按「谁填」分段：
/// - 一、产品信息（科技部填）：面值、业务平台、年化规模、平台状态，包含的关联产品；
/// - 结算（财务部填）：收入（渠道付给我方）、项目成本（我方付出去的成本），每条一张小卡，
///   写明项目、比例、测算金额，算法写在下面；
/// - 三、关联产品结算：权益包里各关联产品自己的结算。
///
/// 当前板块负责的那段正常显示，对方负责的那段浅灰底、右上角「去 xx 部看 ›」跳到对方板块的同一张卡。
enum ProposalProductCardSide { tech, finance }

class ProposalProductCardLine {
  const ProposalProductCardLine({
    required this.name,
    this.ratio = '',
    this.redemptionRate = '',
    this.amount = '',
    this.note = '',
    this.basis = '',
    this.perUnit = '',
    this.detail = '',
    this.tag = '',
    this.minus = false,
  });

  final String name;

  /// 左边小标签，空时按收入 / 项目成本；收入下面的用券成本写「用券成本」。
  final String tag;

  /// 从收入里扣的一条（用券成本）：金额前面加「−」，标签用成本色。
  final bool minus;
  final String ratio;

  /// 用券成本的预计核销率。有值时显示在比例旁边。
  final String redemptionRate;
  final String amount;

  /// 统计口径简称：核销 / 销售 / 下发。
  final String basis;

  /// 每张券结多少元，如「195 元」。
  final String perUnit;

  /// 第二行灰字：计算公式、发票类型、税率，如「按核销统计结算单价 · 电子普通发票 · 0%」。
  final String detail;

  /// 悬停提示：资管公式原文和怎么乘出来的。
  final String note;
}

/// 权益包里包含的一个关联产品（现金券、满减券等）：名称、说明，以及它自己的收钱 / 付钱结算。
class ProposalRelatedProductEntry {
  const ProposalRelatedProductEntry({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.info = const [],
    this.receivables = const [],
    this.payables = const [],
    this.action,
    this.onSettleDetail,
  });

  final String id;
  final String title;

  /// 标题下的摘要，如「包内数量 2 · 2 条结算」。
  final String subtitle;

  /// 复核时展示关联产品已填的基础字段。
  final List<(String, String)> info;
  final List<ProposalProductCardLine> receivables;
  final List<ProposalProductCardLine> payables;

  /// 「填写结算 ›」等。
  final Widget? action;
  final VoidCallback? onSettleDetail;
}

/// 复核状态小标签。
class ProposalProductCardStatus {
  const ProposalProductCardStatus(this.label, {this.done = false});

  final String label;
  final bool done;
}

/// 同一主产品及其关联产品共用一套颜色。现在产品卡仍用统一紫色，弹窗用这套色对齐。
class ProposalProductTint {
  const ProposalProductTint({
    required this.soft,
    required this.line,
    required this.deep,
  });

  final Color soft;
  final Color line;
  final Color deep;

  static const _palette = <ProposalProductTint>[
    ProposalProductTint(
      soft: ProposalPalette.purpleSoft,
      line: ProposalPalette.purpleLine,
      deep: ProposalPalette.purpleDeep,
    ),
  ];

  static ProposalProductTint of(int index) {
    final i = index < 0 ? 0 : index;
    return _palette[i % _palette.length];
  }
}

class ProposalProductCard extends StatefulWidget {
  const ProposalProductCard({
    super.key,
    required this.index,
    required this.name,
    required this.side,
    this.tintIndex,
    this.info = const [],
    this.related = const [],
    this.techStatus,
    this.financeStatus,
    this.receivables = const [],
    this.payables = const [],
    this.relatedSettles = const [],
    this.relatedProducts = const [],
    this.otherSideLabel = '',
    this.onOtherSide,
    this.techAction,
    this.financeAction,
    this.initiallyExpanded = false,
    this.techExtra,
    this.onSettleTap,
    this.onSettleDetail,
  });

  /// 每条结算的「去复核 ›」：跳到财务部「收入与成本」对应那一行（cost=true 是项目成本）。
  final void Function(bool cost)? onSettleTap;

  /// 每条结算的「看明细 ›」：打开这个产品的结算明细（发票、税率、周期都在里面）。
  final VoidCallback? onSettleDetail;

  /// 产品色序号。关联产品和它的主产品传同一个序号。
  final int? tintIndex;

  /// 产品信息表下面额外的内容（如科技部可编辑的关联产品），随产品一起收起。
  final Widget? techExtra;

  /// 默认收起，只露标题栏；点标题栏展开整个产品。
  final bool initiallyExpanded;

  /// 从 0 开始，显示为 1、2、3。
  final int index;
  final String name;

  /// 当前在哪个板块：决定标题栏按钮和「去 xx 部看 ›」。科技部、财务部看到的内容一样。
  final ProposalProductCardSide side;

  /// 产品信息「名称：值」。
  final List<(String, String)> info;

  /// 包含的关联产品，一项一行，如「中石油50元现金券 × 2」（没有 [relatedProducts] 时用）。
  final List<String> related;
  final ProposalProductCardStatus? techStatus;
  final ProposalProductCardStatus? financeStatus;
  final List<ProposalProductCardLine> receivables;
  final List<ProposalProductCardLine> payables;
  final List<ProposalProductCardLine> relatedSettles;

  /// 关联产品：每个一张小卡，标题行 + 它自己的结算。
  final List<ProposalRelatedProductEntry> relatedProducts;

  /// 「去科技部看 ›」「去财务部看 ›」。
  final String otherSideLabel;
  final VoidCallback? onOtherSide;

  /// 标题栏右边的操作（如编辑 / 删除、「看明细 ›」）。
  final Widget? techAction;
  final Widget? financeAction;

  @override
  State<ProposalProductCard> createState() => _ProposalProductCardState();

  Widget _buildCard(
    BuildContext context, {
    required bool expanded,
    required VoidCallback onToggle,
    required Set<String> expandedRelatedIds,
    required ValueChanged<String> onRelatedToggle,
  }) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    final tint = ProposalProductTint.of(tintIndex ?? index);
    final onFinance = side == ProposalProductCardSide.finance;

    TextStyle text(
      double size, {
      Color color = ProposalPalette.text,
      FontWeight weight = FontWeight.w400,
    }) => TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: weight,
      color: c(color),
    );

    Widget tag(String label, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c(bg, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: text(11, color: fg, weight: FontWeight.w500),
      ),
    );

    Widget statusTag(ProposalProductCardStatus? status) => status == null
        ? const SizedBox.shrink()
        : status.done
        ? tag(
            '✓ ${status.label}',
            ProposalPalette.green,
            ProposalPalette.greenSoft,
          )
        : tag(status.label, ProposalPalette.amber, ProposalPalette.amberSoft);

    Widget otherLink() => onOtherSide == null || otherSideLabel.isEmpty
        ? const SizedBox.shrink()
        : InkWell(
            onTap: onOtherSide,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '$otherSideLabel ›',
                style: text(11.5, color: ProposalPalette.purpleDeep),
              ),
            ),
          );

    /// 小标题：「结算 1 条」「关联产品 2 个」，右边放复核状态 / 操作。
    Widget heading(
      String title, {
      String count = '',
      ProposalProductCardStatus? status,
      Widget? action,
      bool link = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          Text(title, style: text(13, weight: FontWeight.w600)),
          if (count.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(count, style: text(12, color: ProposalPalette.text3)),
          ],
          const Spacer(),
          if (link) otherLink(),
          ?action,
          if (status != null) ...[const SizedBox(width: 6), statusTag(status)],
        ],
      ),
    );

    final line = c(ProposalPalette.borderSoft, DunesColorRole.border);

    /// 主产品与关联产品共用两列字段表；窄屏每格把标签放在值上方。
    Widget infoTable(
      List<(String, String)> rows, {
      bool embedded = false,
    }) => LayoutBuilder(
      builder: (context, box) {
        final stacked = box.maxWidth < 520;
        const labelWidth = 96.0;
        Widget pair((String, String)? row) {
          if (row == null) return const Expanded(child: SizedBox.shrink());
          final (label, value) = row;
          final empty = value.trim().isEmpty;
          final labelText = Text(
            label,
            style: text(12.5, color: ProposalPalette.text2),
          );
          final valueText = Tooltip(
            message: empty ? '' : value,
            waitDuration: const Duration(milliseconds: 500),
            child: Text(
              empty ? '未填写' : value,
              softWrap: true,
              style: text(
                12.5,
                color: empty ? ProposalPalette.text3 : ProposalPalette.text,
              ),
            ),
          );
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: stacked ? 6 : 10,
                vertical: 6,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        labelText,
                        const SizedBox(height: 2),
                        valueText,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: labelWidth, child: labelText),
                        Expanded(child: valueText),
                      ],
                    ),
            ),
          );
        }

        final lines = <Widget>[];
        for (var i = 0; i < rows.length; i += 2) {
          lines.add(
            Container(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pair(rows[i]),
                  pair(i + 1 < rows.length ? rows[i + 1] : null),
                ],
              ),
            ),
          );
        }
        return Container(
          decoration: embedded
              ? null
              : BoxDecoration(
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(8),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: lines,
          ),
        );
      },
    );

    /// 一条结算（和财务部「收入与成本」同一个样子）：右下「看明细 ›」「去复核 ›」两个按钮。
    Widget settleLine(
      ProposalProductCardLine item, {
      required bool cost,
      VoidCallback? detail,
    }) =>
        ProposalSettleLineTile(
          line: item,
          cost: cost,
          onDetail: detail ?? onSettleDetail,
          onReview: onSettleTap == null ? null : () => onSettleTap!(cost),
        );

    /// 一组结算：主产品每条一张白卡；关联产品卡里每条之间一根细线。
    List<Widget> settleCards(
      List<ProposalProductCardLine> income,
      List<ProposalProductCardLine> cost,
    ) => [
      for (final item in income)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: settleLine(item, cost: false),
        ),
      for (final item in cost)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: settleLine(item, cost: true),
        ),
    ];

    List<Widget> settleRows(
      List<ProposalProductCardLine> income,
      List<ProposalProductCardLine> cost, {
      VoidCallback? detail,
    }) {
      final all = [
        for (final item in income) (item, false),
        for (final item in cost) (item, true),
      ];
      return [
        for (var i = 0; i < all.length; i++)
          Container(
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: line)),
            ),
            child: settleLine(all[i].$1, cost: all[i].$2, detail: detail),
          ),
      ];
    }

    final settleCount = receivables.length + payables.length;
    final relatedCount = relatedProducts.isNotEmpty
        ? relatedProducts.length
        : related.length;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 产品信息：科技部填，财务部看到「去科技部看 ›」。
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text('产品信息', style: text(13, weight: FontWeight.w600)),
                const Spacer(),
                if (onFinance) otherLink(),
                if (techStatus != null) ...[
                  const SizedBox(width: 6),
                  statusTag(techStatus),
                ],
              ],
            ),
          ),
          infoTable([('产品名称', name.trim()), ...info]),
          ?techExtra,
          // 结算：财务部填，科技部看到「去财务部看 ›」。
          heading(
            '结算',
            count: settleCount > 0 ? '$settleCount 条' : '',
            status: financeStatus,
            action: onFinance && expanded ? financeAction : null,
            link: !onFinance,
          ),
          if (settleCount == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '还没填结算',
                style: text(12.5, color: ProposalPalette.amber),
              ),
            )
          else
            ...settleCards(receivables, payables),
          // 关联产品：科技部、财务部都看得到。
          if (relatedProducts.isNotEmpty) ...[
            heading('关联产品', count: '$relatedCount 个'),
            for (var i = 0; i < relatedProducts.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: c(ProposalPalette.app, DunesColorRole.surface),
                      child: InkWell(
                        onTap: () => onRelatedToggle(relatedProducts[i].id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c(tint.soft, DunesColorRole.surface),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: text(
                                        11.5,
                                        color: tint.deep,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      relatedProducts[i].title,
                                      style: text(13, weight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    expandedRelatedIds.contains(relatedProducts[i].id)
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: 18,
                                    color: c(ProposalPalette.text3),
                                  ),
                                ],
                              ),
                              if (relatedProducts[i].subtitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 28, top: 3),
                                  child: Text(
                                    relatedProducts[i].subtitle,
                                    style: text(12, color: ProposalPalette.text2),
                                  ),
                                ),
                              if (relatedProducts[i].action != null)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: relatedProducts[i].action!,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (expandedRelatedIds.contains(relatedProducts[i].id)) ...[
                      Container(height: 1, color: line),
                      if (relatedProducts[i].info.isNotEmpty) ...[
                        infoTable(relatedProducts[i].info, embedded: true),
                        Container(height: 1, color: line),
                      ],
                      if (relatedProducts[i].receivables.isEmpty &&
                          relatedProducts[i].payables.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Text(
                            '还没填结算',
                            style: text(12.5, color: ProposalPalette.amber),
                          ),
                        )
                      else
                        ...settleRows(
                          relatedProducts[i].receivables,
                          relatedProducts[i].payables,
                          detail: relatedProducts[i].onSettleDetail,
                        ),
                    ],
                  ],
                ),
              ),
          ] else if (related.isNotEmpty) ...[
            heading('关联产品', count: '$relatedCount 个'),
            Text(related.join('，'), style: text(12.5)),
          ] else if (relatedSettles.isNotEmpty) ...[
            heading('关联产品结算'),
            ...settleCards(relatedSettles, const []),
          ],
        ],
      ),
    );

    // 标题栏（保持现在的样子）：编号圆点 + 产品名 + 一行概要；状态、按钮、箭头固定在右边。
    String infoOf(String key) =>
        info
            .where((row) => row.$1 == key)
            .map((row) => row.$2.trim())
            .firstOrNull ??
        '';
    final faceText = infoOf('面值');
    final sideStatus = onFinance ? financeStatus : techStatus;
    final metaSpans = <InlineSpan>[];
    void meta(String label, {Color color = ProposalPalette.text2}) {
      if (label.isEmpty) return;
      if (metaSpans.isNotEmpty) {
        metaSpans.add(TextSpan(text: '   ', style: text(11.5)));
      }
      metaSpans.add(
        TextSpan(
          text: label,
          style: text(11.5, color: color),
        ),
      );
    }

    if (faceText.isNotEmpty) meta('面值 $faceText');
    if (settleCount == 0) {
      meta('还没填结算', color: ProposalPalette.amber);
    } else {
      if (receivables.isNotEmpty) meta('收入 ${receivables.length} 条');
      if (payables.isNotEmpty) meta('成本 ${payables.length} 条');
    }
    if (relatedCount > 0) meta('含 $relatedCount 个关联产品');

    final header = Material(
      color: c(expanded ? tint.soft : Colors.white, DunesColorRole.surface),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c(
                    expanded ? tint.deep : tint.soft,
                    DunesColorRole.surface,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: expanded ? Colors.white : c(tint.deep),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.trim().isEmpty ? '未填写产品名称' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text(13.5, weight: FontWeight.w600),
                    ),
                    if (metaSpans.isNotEmpty)
                      Text.rich(
                        TextSpan(children: metaSpans),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (sideStatus != null) ...[
                const SizedBox(width: 6),
                statusTag(sideStatus),
              ],
              ?techAction,
              // 收起时财务部也能直接点「看明细 ›」，不用先展开。
              if (onFinance && financeAction != null && !expanded) ...[
                const SizedBox(width: 6),
                financeAction!,
              ],
              Tooltip(
                message: expanded ? '收起这个产品' : '展开这个产品',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: c(ProposalPalette.text3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c(Colors.white, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: c(
            expanded ? tint.line : ProposalPalette.borderSoft,
            DunesColorRole.border,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, if (expanded) body],
      ),
    );
  }
}

class _ProposalProductCardState extends State<ProposalProductCard> {
  late bool _expanded = widget.initiallyExpanded;
  final Set<String> _expandedRelatedIds = {};

  @override
  Widget build(BuildContext context) => widget._buildCard(
    context,
    expanded: _expanded,
    onToggle: () => setState(() => _expanded = !_expanded),
    expandedRelatedIds: _expandedRelatedIds,
    onRelatedToggle: (id) => setState(() {
      if (!_expandedRelatedIds.remove(id)) _expandedRelatedIds.add(id);
    }),
  );
}

/// 一条结算：第一行「收入 / 项目成本」标签 + 名称，右边「单价 198」「比例 0.975」，算得出时跟「年 X 万」；
/// 第二行灰字写计算公式、发票、税率。产品卡和财务部「收入与成本」共用。
class ProposalSettleLineTile extends StatelessWidget {
  const ProposalSettleLineTile({
    super.key,
    required this.line,
    required this.cost,
    this.onTap,
    this.onDetail,
    this.onReview,
  });

  final ProposalProductCardLine line;
  final bool cost;
  final VoidCallback? onTap;

  /// 「看明细 ›」：打开这个产品的结算明细。
  final VoidCallback? onDetail;

  /// 「去复核 ›」：跳到财务部「收入与成本」。
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    TextStyle text(
      double size, {
      Color color = ProposalPalette.text,
      FontWeight weight = FontWeight.w400,
    }) => TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: weight,
      color: c(color),
    );
    final ratio = line.ratio.trim();
    // 小数系数补成百分数：`0.98` → 98%，`1.0333333` → 103.33%。`4` 这种旧写法本身就是百分数。
    final parsedRatio = double.tryParse(ratio);
    final ratioText =
        ratio.isEmpty || ratio.endsWith('%') || parsedRatio == null
        ? ratio
        : '${_trimNumber(proposalRatioDisplayPercent(parsedRatio))}%';
    final rateRaw = line.redemptionRate.trim();
    final parsedRate = double.tryParse(rateRaw);
    final rateText = rateRaw.isEmpty || rateRaw.endsWith('%') || parsedRate == null
        ? rateRaw
        : '${_trimNumber(proposalRatioDisplayPercent(parsedRate))}%';
    final valueBase = ratioText.isNotEmpty
        ? '比例 $ratioText'
        : (line.perUnit.trim().isNotEmpty
              ? '单价 ${line.perUnit.trim().replaceAll(' 元', '').replaceAll('元', '')}'
              : '比例未填');
    final value = rateText.isEmpty ? valueBase : '$valueBase · 预计核销率 $rateText';
    final minusSide = cost || line.minus;
    final tag = line.tag.isNotEmpty ? line.tag : (cost ? '项目成本' : '收入');
    final amount = line.amount.trim();
    Widget action(String label, VoidCallback onPressed) => InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          style: text(
            11.5,
            color: ProposalPalette.purple,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
    final actions = [
      if (onDetail != null) action('看明细 ›', onDetail!),
      if (onReview != null) action('去复核 ›', onReview!),
    ];
    final amountText = amount.isEmpty || amount == '—'
        ? '年化 —'
        : '年化 ${line.minus ? '−' : ''}$amount';
    final categoryTag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c(
          minusSide ? ProposalPalette.coralSoft : ProposalPalette.greenSoft,
          DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        tag,
        style: text(
          11,
          color: minusSide ? ProposalPalette.coral : ProposalPalette.green,
          weight: FontWeight.w500,
        ),
      ),
    );
    final valueText = Text(
      value,
      style: text(
        13,
        weight: FontWeight.w600,
        color: value == '比例未填' ? ProposalPalette.amber : ProposalPalette.text,
      ),
    );
    final amountValue = Text(
      amountText,
      style: text(
        12,
        color: line.minus ? ProposalPalette.coral : ProposalPalette.text2,
      ),
    );
    Widget body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 390;
              final name = Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text(13, weight: FontWeight.w600),
              );
              final chevron = onTap == null
                  ? const SizedBox.shrink()
                  : Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: c(ProposalPalette.text3),
                    );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        categoryTag,
                        const SizedBox(width: 8),
                        Expanded(child: name),
                        chevron,
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [valueText, amountValue],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  categoryTag,
                  const SizedBox(width: 8),
                  Expanded(child: name),
                  valueText,
                  const SizedBox(width: 10),
                  amountValue,
                  if (onTap != null) ...[const SizedBox(width: 4), chevron],
                ],
              );
            },
          ),
          if (line.detail.trim().isNotEmpty || actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      line.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text(12, color: ProposalPalette.text2),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
        ],
      ),
    );
    if (line.note.isNotEmpty) {
      body = Tooltip(
        message: line.note,
        waitDuration: const Duration(milliseconds: 400),
        child: body,
      );
    }
    if (onTap != null) {
      body = InkWell(onTap: onTap, child: body);
    }
    return body;
  }
}

/// 「98.00」→「98」、「0.50」→「0.5」。
String _trimNumber(double v) {
  final text = v.toStringAsFixed(2);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

/// 一个产品某一类结算的只读列表（财务部「收入与成本」里同步产品结算用）：每条一行，细线分隔，外面一圈细框。
class ProposalSettleLineList extends StatelessWidget {
  const ProposalSettleLineList({
    super.key,
    required this.lines,
    required this.cost,
    this.emptyText = '',
    this.framed = true,
  });

  final List<ProposalProductCardLine> lines;
  final bool cost;
  final String emptyText;

  /// false：不画外框、贴边（放进已经有框的表单卡里）。
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final line = DunesColors.resolve(
      context,
      ProposalPalette.borderSoft,
      role: DunesColorRole.border,
    );
    if (lines.isEmpty) {
      if (emptyText.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: framed
            ? const EdgeInsets.only(top: 6)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          emptyText,
          style: TextStyle(
            fontSize: 12,
            color: DunesColors.resolve(context, ProposalPalette.amber),
          ),
        ),
      );
    }
    return Container(
      margin: framed ? const EdgeInsets.only(top: 6, bottom: 4) : null,
      decoration: framed
          ? BoxDecoration(
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: line)),
              ),
              child: ProposalSettleLineTile(line: lines[i], cost: cost),
            ),
        ],
      ),
    );
  }
}

/// 一组明细：彩色标题栏（如「收钱 · 应收」）右边直接写列名「比例 / 测算金额」，不再单独一行表头；
/// 每行 编号 / 项目 + 算式（同一行，灰色小字）/ 比例 / 测算金额。比例全空时不显示比例列。
class ProposalLineGroup extends StatelessWidget {
  const ProposalLineGroup({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.fg,
    required this.bg,
    required this.lines,
    this.circled = false,
    this.emptyText = '无',
  });

  final IconData icon;
  final String title;
  final String hint;
  final Color fg;
  final Color bg;
  final List<ProposalProductCardLine> lines;
  final bool circled;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    final narrow = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    TextStyle text(
      double size, {
      Color color = ProposalPalette.text,
      FontWeight weight = FontWeight.w400,
      bool mono = false,
    }) => TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: weight,
      color: c(color),
      fontFamily: mono ? kProposalProtoMono : null,
      fontFamilyFallback: mono ? kProposalProtoMonoFallback : null,
    );
    final showRatio = lines.any((l) => l.ratio.trim().isNotEmpty);
    final ratioWidth = narrow ? 52.0 : 64.0;
    final amountWidth = narrow ? 72.0 : 84.0;
    String no(int i) {
      if (!circled) return '${i + 1}';
      const marks = '①②③④⑤⑥⑦⑧⑨⑩';
      return i < marks.length ? marks[i] : '${i + 1}';
    }

    final line = BorderSide(
      color: c(ProposalPalette.borderSoft, DunesColorRole.border),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: c(ProposalPalette.borderSoft, DunesColorRole.border),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Container(
              color: c(bg, DunesColorRole.surface),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: c(fg)),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: text(12.5, color: fg, weight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text(11.5, color: fg),
                    ),
                  ),
                  if (lines.isNotEmpty && showRatio)
                    SizedBox(
                      width: ratioWidth,
                      child: Text(
                        '比例',
                        textAlign: TextAlign.right,
                        style: text(11, color: fg),
                      ),
                    ),
                  if (lines.isNotEmpty)
                    SizedBox(
                      width: amountWidth,
                      child: Text(
                        '测算金额',
                        textAlign: TextAlign.right,
                        style: text(11, color: fg),
                      ),
                    ),
                ],
              ),
            ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 5, 10, 5),
              child: Text(
                emptyText,
                style: text(12.5, color: ProposalPalette.text3),
              ),
            )
          else
            for (var i = 0; i < lines.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  border: i == 0 && title.isNotEmpty ? null : Border(top: line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        no(i),
                        style: text(
                          12,
                          color: ProposalPalette.text2,
                          mono: true,
                        ),
                      ),
                    ),
                    // 项目名后面同一行跟灰色小字算式，放不下才折行。
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: lines[i].name, style: text(12.5)),
                            if (lines[i].note.isNotEmpty)
                              TextSpan(
                                text: '   ${lines[i].note}',
                                style: text(11.5, color: ProposalPalette.text3),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (showRatio)
                      SizedBox(
                        width: ratioWidth,
                        child: Text(
                          lines[i].ratio.isEmpty ? '—' : lines[i].ratio,
                          textAlign: TextAlign.right,
                          style: text(12.5, mono: true),
                        ),
                      ),
                    SizedBox(
                      width: amountWidth,
                      child: Text(
                        lines[i].amount.isEmpty ? '—' : lines[i].amount,
                        textAlign: TextAlign.right,
                        style: text(12.5, mono: true, weight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// 市场部「成本测算」里的一个产品：和科技部 / 财务部的产品卡同一套编号、同一个颜色，
/// 按 项目成本 / 业务成本 / 税务成本 分组列出每一项、测算金额和代入算式。
/// 产品默认收起（标题栏上有合计）；「整份提案」那张默认展开。
class ProposalProductCostCard extends StatefulWidget {
  const ProposalProductCostCard({
    super.key,
    required this.index,
    required this.name,
    this.tintIndex,
    this.kindTag = '',
    this.total = '',
    this.groups = const [],
    this.mark = '',
    this.initiallyExpanded,
  });

  /// 产品色序号。关联产品和它的主产品传同一个序号。
  final int? tintIndex;

  /// 圆圈里写的字；空时写编号（index + 1）。整份提案那张写「全」。
  final String mark;

  final int index;
  final String name;

  /// 「主产品」「关联产品」。
  final String kindTag;
  final String total;

  /// 不给时：产品收起，「整份提案」展开。
  final bool? initiallyExpanded;

  /// (标题, 说明, 颜色, 底色, 明细)。
  final List<(String, String, Color, Color, List<ProposalProductCardLine>)>
  groups;

  @override
  State<ProposalProductCostCard> createState() =>
      _ProposalProductCostCardState();
}

class _ProposalProductCostCardState extends State<ProposalProductCostCard> {
  late bool _expanded = widget.initiallyExpanded ?? widget.mark.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    Color c(Color v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: role);
    final tint = ProposalProductTint.of(w.tintIndex ?? w.index);
    final whole = w.mark.isNotEmpty;
    final header = Material(
      color: c(Colors.white, DunesColorRole.surface),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c(tint.soft, DunesColorRole.surface),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  whole ? w.mark : '${w.index + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: c(tint.deep),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  w.name.trim().isEmpty ? '未填写产品名称' : w.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: c(ProposalPalette.text),
                  ),
                ),
              ),
              if (w.kindTag.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c(ProposalPalette.soft, DunesColorRole.surface),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    w.kindTag,
                    style: TextStyle(
                      fontSize: 11,
                      color: c(ProposalPalette.text2),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (w.total.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '合计 ',
                        style: TextStyle(
                          fontSize: 12,
                          color: c(ProposalPalette.text2),
                        ),
                      ),
                      TextSpan(
                        text: w.total,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c(ProposalPalette.text),
                          fontFamily: kProposalProtoMono,
                          fontFamilyFallback: kProposalProtoMonoFallback,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
                color: c(ProposalPalette.text3),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c(Colors.white, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: c(
            _expanded ? ProposalPalette.purpleLine : ProposalPalette.borderSoft,
            DunesColorRole.border,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_expanded)
            Container(
              height: 1,
              color: c(ProposalPalette.borderSoft, DunesColorRole.border),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, hint, fg, bg, lines) in w.groups)
                    ProposalLineGroup(
                      icon: Icons.receipt_long_outlined,
                      title: title,
                      hint: hint,
                      fg: fg,
                      bg: bg,
                      lines: lines,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
