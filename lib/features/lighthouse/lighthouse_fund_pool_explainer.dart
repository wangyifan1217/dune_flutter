// 灯塔 · 资产四宫格「这些数怎么读」说明。
//
// 展开「总资产金额」后，面板底部两条等式下面有一个「ⓘ 这些数怎么读」，
// 点开是这张底部弹层：三方角色 → 每一格的意思和资管原名 → 两条等式怎么读 →
// 常见误读 → 数据日期 → 还在等财务确认的三件事。
//
// 资管原名取自后端 shucai_tag2.go 里接口的列名；标「待财务确认」的是从公式
// 结构推出来的理解，确认前不要写成定论。

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_feedback.dart';
import 'lighthouse_theme.dart';

abstract final class _C {
  static const deep = Color(0xFF5A458F);
  static const primary = Color(0xFF7B5CD8);
  static const tile = Color(0xFFF3F1F7);
  static const line = Color(0xFFE8E4EF);
  static const ink = Color(0xFF2A2633);
  static const ink2 = Color(0xFF4A4558);
  static const mute = Color(0xFF8C8798);
  static const assets = Color(0xFF1F8A5B);
  static const recon = Color(0xFFB5478A);
  static const warnBg = Color(0xFFFFF6E5);
  static const warnEdge = Color(0xFFF3D9A6);
  static const warnInk = Color(0xFF8A5A00);
  static const noBg = Color(0xFFFFF3F1);
  static const noEdge = Color(0xFFF6D3CE);
  static const noInk = Color(0xFFB0281F);
}

/// 一格：卡上的名字 / 资管原名 / 意思；[pending] = 理解还待财务确认。
class _Term {
  const _Term(this.name, this.source, this.meaning, {this.pending = false});
  final String name;
  final String source;
  final String meaning;
  final bool pending;
}

const List<(String, List<_Term>)> _kTermGroups = [
  (
    '资金',
    [
      _Term('已入账', '监管户余额', '已经进到监管户里的钱。'),
      _Term('待入账', '在途资金', '平安那边打过来、还在路上没入账的钱。'),
      _Term(
        '期末应收返利',
        '期末应收返利',
        '字面是「应收的返利」：更可能是中石油按采购量返给我们、还没到账的钱，'
            '而不是平安欠我们的货款。',
        pending: true,
      ),
    ],
  ),
  (
    '券',
    [
      _Term('在手券', '库存券余额', '我方手上的库存券。'),
      _Term('同步在途', '合同券余额', '合同券，台账还在同步中。'),
      _Term('已预支', '预支券余额', '预支领用出去的券。'),
    ],
  ),
  (
    '期末预付款对账',
    [
      _Term(
        '可动用额度',
        '资金池余额',
        '资金池里还能用来出券的额度。它不算进账面资产，所以大概率不是我方账户里'
            '可以直接调拨的现金，更可能放在中石油那边。',
        pending: true,
      ),
      _Term('券资产', '库存券 + 合同券', '在手券和同步在途加起来。'),
      _Term(
        '期末预付',
        '期末预付款余额',
        '我方已经付给中石油、券还没拿全的钱，记在我方账上，是我方的资产。'
            '正数 = 我方预付、待收货；负数 = 我方反过来欠中石油。',
      ),
      _Term('对账差额', '系统差异', '一条核对用的缺口，见下面第二条等式。'),
    ],
  ),
  (
    '资产',
    [
      _Term('账面资产', '资产合计', '已入账 + 待入账 + 期末预付。'),
      _Term('本月 / 今日利润', '灯塔利润', '真正赚了多少，只看这两格。'),
    ],
  ),
];

/// 打开说明弹层。
Future<void> showLighthouseFundPoolExplainer(BuildContext context) {
  LighthouseFeedback.instance.play(LighthouseFeedbackKind.expand);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x331E1830),
    builder: (ctx) => const LighthouseFundPoolExplainerSheet(),
  );
}

/// 面板底部那一行小链接：「ⓘ 这些数怎么读」。
class LighthouseFundPoolExplainLink extends StatelessWidget {
  const LighthouseFundPoolExplainLink({super.key, this.scale = 1.0});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = DunesColors.resolve(context, _C.deep);
    return Semantics(
      button: true,
      label: '这些数怎么读',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showLighthouseFundPoolExplainer(context),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6 * scale, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 12 * scale, color: c),
              SizedBox(width: 4 * scale),
              Text(
                '这些数怎么读',
                style: LhTypography.sans(
                  context: context,
                  size: 10 * scale,
                  color: c,
                  weight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LighthouseFundPoolExplainerSheet extends StatelessWidget {
  const LighthouseFundPoolExplainerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final paper = DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: mq.size.height * 0.86,
        ),
        child: Material(
          color: paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _C.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '资产这几格怎么读',
                        style: LhTypography.sans(
                          context: context,
                          size: 16,
                          color: _C.ink,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: _C.mute,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    20 + mq.padding.bottom,
                  ),
                  children: [
                    _section(context, '1 · 谁和谁做生意'),
                    _roles(context),
                    const SizedBox(height: 18),
                    _section(context, '2 · 每一格是什么'),
                    for (final (group, terms) in _kTermGroups) ...[
                      _groupTitle(context, group),
                      _termTable(context, terms),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    _section(context, '3 · 底下两条等式怎么读'),
                    _formula(
                      context,
                      color: _C.assets,
                      result: '账面资产',
                      expr: '已入账 + 待入账 + 期末预付',
                      read: '我方自己的钱，加上我方对外的权利。资金池、券、返利都不在里面。',
                    ),
                    const SizedBox(height: 8),
                    _formula(
                      context,
                      color: _C.recon,
                      result: '对账差额',
                      expr: '期末预付 − 可动用额度 − 券资产 − 期末应收返利',
                      read:
                          '核对我方付给中石油的预付款，有没有都落到资金池、手上的券和返利里。'
                          '理想是 0；不为 0 说明台账里有一笔没对上，要去查是哪张单据没核销或没同步。',
                    ),
                    const SizedBox(height: 18),
                    _section(context, '4 · 别这样读'),
                    _dont(
                      context,
                      '对账差额不是利润。',
                      '它是台账的缺口，不能当成赚到的钱。赚了多少只看「本月利润 / 今日利润」。',
                    ),
                    const SizedBox(height: 8),
                    _dont(
                      context,
                      '不要拿「期末应收返利 − 期末预付」算毛利。',
                      '期末预付是还没收到的货，期末应收返利是另一笔钱，两边不是同一批货、也不是同一个时点，'
                          '相减得不出任何一笔生意的毛利。',
                    ),
                    const SizedBox(height: 18),
                    _section(context, '5 · 数据是哪天的'),
                    _para(
                      context,
                      '资管只给已经结完账的日子出数，灯塔显示的是上海时间昨天的快照'
                      '（今天打开，看到的是昨天的数）。',
                    ),
                    const SizedBox(height: 6),
                    _para(
                      context,
                      '和资管手工表对数时，先对齐三件事：看的是同一天；中油BP 算在中石油里；'
                      '系统差异不加进资产。',
                    ),
                    const SizedBox(height: 18),
                    _section(context, '6 · 还在等财务确认'),
                    _pending(context, [
                      '「期末应收返利」是谁欠我们的：中石油的返利，还是平安的货款？',
                      '「资金池余额」的钱在谁那里：我方账户，还是中石油的资金池？为什么不算进资产合计？',
                      '「系统差异」设计上要核对什么？正常应该是 0，还是会长期挂着一个数？',
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: LhTypography.sans(
        context: context,
        size: 13,
        color: _C.ink,
        weight: FontWeight.w800,
      ),
    ),
  );

  Widget _groupTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Text(
      text,
      style: LhTypography.sans(
        context: context,
        size: 11,
        color: _C.mute,
        weight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _para(BuildContext context, String text) => Text(
    text,
    style: LhTypography.sans(
      context: context,
      size: 12,
      color: _C.ink2,
      height: 1.55,
    ),
  );

  Widget _roles(BuildContext context) {
    Widget node(String who, String role, {bool us = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: us ? const Color(0xFFF6F2FC) : _C.tile,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: us ? const Color(0xFFD9CCF2) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              who,
              style: LhTypography.sans(
                context: context,
                size: 13,
                color: us ? _C.deep : _C.ink,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              role,
              style: LhTypography.sans(
                context: context,
                size: 10.5,
                color: _C.mute,
              ),
            ),
          ],
        ),
      ),
    );
    Widget arrow(String label) => SizedBox(
      width: 46,
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: LhTypography.sans(context: context, size: 9, color: _C.mute),
          ),
          const Icon(Icons.east_rounded, size: 14, color: _C.primary),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            node('中石油', '上游 · 供货'),
            arrow('供券'),
            node('我方', '中间商', us: true),
            arrow('卖券'),
            node('平安', '下游 · 采购'),
          ],
        ),
        const SizedBox(height: 8),
        _para(
          context,
          '我方先把钱付给中石油（这笔记成「期末预付」），从中石油拿券，再卖给平安；'
          '平安付的钱先在路上（待入账），到了就进监管户（已入账）。',
        ),
      ],
    );
  }

  Widget _termTable(BuildContext context, List<_Term> terms) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _C.line,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < terms.length; i++) ...[
            if (i > 0) const SizedBox(height: 1),
            Container(
              color: _C.tile,
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          terms[i].name,
                          style: LhTypography.sans(
                            context: context,
                            size: 12.5,
                            color: _C.ink,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '原名 ${terms[i].source}',
                          style: LhTypography.sans(
                            context: context,
                            size: 9.5,
                            color: _C.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: terms[i].meaning),
                          if (terms[i].pending)
                            const TextSpan(
                              text: '  待财务确认',
                              style: TextStyle(
                                color: _C.warnInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      style: LhTypography.sans(
                        context: context,
                        size: 11.5,
                        color: _C.ink2,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formula(
    BuildContext context, {
    required Color color,
    required String result,
    required String expr,
    required String read,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _C.tile,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: result,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' = ',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                TextSpan(text: expr),
              ],
            ),
            style: LhTypography.mono(
              context: context,
              size: 11.5,
              color: _C.ink2,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _para(context, read),
        ],
      ),
    );
  }

  Widget _dont(BuildContext context, String head, String body) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _C.noBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.noEdge, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            head,
            style: LhTypography.sans(
              context: context,
              size: 12.5,
              color: _C.noInk,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          _para(context, body),
        ],
      ),
    );
  }

  Widget _pending(BuildContext context, List<String> items) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _C.warnBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.warnEdge, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: LhTypography.mono(
                    context: context,
                    size: 11.5,
                    color: _C.warnInk,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    items[i],
                    style: LhTypography.sans(
                      context: context,
                      size: 11.5,
                      color: _C.warnInk,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '标了「待财务确认」的几格，是按公式结构推出来的理解，确认后会改成定论。',
            style: LhTypography.sans(
              context: context,
              size: 10.5,
              color: _C.mute,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
