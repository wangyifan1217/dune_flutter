import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 未结账款（2026-10-27）
//
//   资管 /out/lighthouse/bill-outstanding 经 lighthouse-go 代理：
//   应收未回款 / 应付未付款，按「我方 + 对方 + 账单类型」分组。
//
//   · 逾期 = 账单结束日 + 7 天仍未结，界面写「超 7 天」，不写「超期」
//     （灯塔超期是提案 D+N / M+N，另一回事）。
//   · 全公司全量：受限账号后端回 restricted，前端整块不出现；专题下资金页不出现。
//   · 后端按标签二主体表给能对上的组挂了 provinceName，对不上写「未匹配」。
// ════════════════════════════════════════════════════════════════════════

/// 未结账款开关。2026-10-27 晚：先不用，资金页不出卡片、也不去拉接口。
/// 后端 /api/v1/lighthouse/bill-outstanding 保留，改回 true 即可恢复。
const bool lighthouseBillOutstandingEnabled = false;

class LhBillTotal {
  const LhBillTotal({
    required this.unpaidAmount,
    required this.unpaidCount,
    required this.overdueAmount,
    required this.overdueCount,
  });

  final double unpaidAmount;
  final int unpaidCount;
  final double overdueAmount;
  final int overdueCount;

  double get overdueShare =>
      unpaidAmount.abs() < 1e-9
      ? 0
      : (overdueAmount / unpaidAmount).clamp(0.0, 1.0).toDouble();

  static LhBillTotal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double d(String k) => (raw[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (raw[k] as num?)?.toInt() ?? 0;
    return LhBillTotal(
      unpaidAmount: d('unpaidAmount'),
      unpaidCount: i('unpaidCount'),
      overdueAmount: d('overdueAmount'),
      overdueCount: i('overdueCount'),
    );
  }
}

class LhBillGroup {
  const LhBillGroup({
    required this.side,
    required this.ourEntity,
    required this.counterparty,
    required this.billType,
    required this.billCount,
    required this.unpaidAmount,
    required this.overdueAmount,
    required this.earliestEnd,
    required this.provinceName,
  });

  final String side;
  final String ourEntity;
  final String counterparty;
  final String billType;
  final int billCount;
  final double unpaidAmount;
  final double overdueAmount;
  final DateTime? earliestEnd;
  final String provinceName;

  static LhBillGroup fromJson(Map raw) => LhBillGroup(
    side: (raw['side'] ?? '').toString().toUpperCase(),
    ourEntity: (raw['ourEntityName'] ?? '').toString(),
    counterparty: (raw['counterpartyName'] ?? '').toString(),
    billType: (raw['billTypeName'] ?? '').toString(),
    billCount: (raw['billCount'] as num?)?.toInt() ?? 0,
    unpaidAmount: (raw['unpaidAmount'] as num?)?.toDouble() ?? 0,
    overdueAmount: (raw['overdueAmount'] as num?)?.toDouble() ?? 0,
    earliestEnd: DateTime.tryParse((raw['earliestBillEnd'] ?? '').toString()),
    provinceName: (raw['provinceName'] ?? '').toString(),
  );
}

class LhBillOutstanding {
  const LhBillOutstanding({
    required this.restricted,
    required this.asOf,
    required this.receivable,
    required this.payable,
    required this.groups,
    this.fixture = false,
  });

  /// 受限账号 / 后端没配资管：整块不出现。
  final bool restricted;
  final String asOf;

  /// null = 这一侧没查（不是没有未结）。
  final LhBillTotal? receivable;
  final LhBillTotal? payable;
  final List<LhBillGroup> groups;

  /// 资管接口还没上时，本机用文档样例撑卡。
  final bool fixture;

  bool get visible => !restricted && (receivable != null || payable != null);

  static LhBillOutstanding fromJson(Map<String, dynamic> data) {
    final hidden = data['restricted'] == true || data['unavailable'] == true;
    return LhBillOutstanding(
      restricted: hidden,
      asOf: (data['asOf'] ?? '').toString(),
      receivable: LhBillTotal.fromJson(data['receivable']),
      payable: LhBillTotal.fromJson(data['payable']),
      groups: [
        for (final g in (data['groups'] as List? ?? const []))
          if (g is Map) LhBillGroup.fromJson(g),
      ],
      fixture: data['fixture'] == true,
    );
  }
}

/// 元 → 「2.29亿」「7083.9万」「860」。
String lhBillAmount(double yuan) {
  final v = yuan.abs();
  final sign = yuan < 0 ? '-' : '';
  if (v >= 1e8) return '$sign${(v / 1e8).toStringAsFixed(2)}亿';
  if (v >= 1e4) return '$sign${(v / 1e4).toStringAsFixed(1)}万';
  return '$sign${v.toStringAsFixed(0)}';
}

String _asOfShort(String asOf) =>
    asOf.length == 10 ? asOf.substring(5).replaceAll('-', '.') : asOf;

const _kDeep = Color(0xFF4A3A7A);
const _kPlum = Color(0xFF7B5CD8);
const _kLine = Color(0xFFECE6F6);
const _kOver = Color(0xFFD9785C);
const _kOverInk = Color(0xFF9A3F2C);
const _kRest = Color(0xFFD9CEF5);

// ── 资金页小卡 ────────────────────────────────────────────────────────────

class LighthouseBillOutstandingCard extends StatelessWidget {
  const LighthouseBillOutstandingCard({
    super.key,
    required this.data,
    required this.onTap,
    this.radius = 12,
  });

  final LhBillOutstanding data;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Color c(Color v, [DunesColorRole r = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: r);
    return Semantics(
      button: true,
      label: '未结账款，查看明细',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
          decoration: BoxDecoration(
            color: c(Colors.white, DunesColorRole.surface),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c(_kLine, DunesColorRole.border), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '未结账款',
                    style: LhTypography.sans(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: c(LhColors.ink),
                      context: context,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    data.fixture ? '资管账单 · 样例' : '资管账单',
                    style: LhTypography.sans(
                      size: 10,
                      color: c(LhColors.mute2),
                      context: context,
                    ),
                  ),
                  const Spacer(),
                  if (data.asOf.isNotEmpty)
                    Text(
                      '截至 ${_asOfShort(data.asOf)}',
                      style: LhTypography.mono(
                        size: 10,
                        color: c(LhColors.mute2),
                        context: context,
                      ),
                    ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: c(_kPlum)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _side(context, '应收未回款', data.receivable)),
                  Container(
                    width: 0.8,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: c(_kLine, DunesColorRole.border),
                  ),
                  Expanded(child: _side(context, '应付未付款', data.payable)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _side(BuildContext context, String label, LhBillTotal? t) {
    Color c(Color v, [DunesColorRole r = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, v, role: r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.sans(size: 10.5, color: c(LhColors.ink2), context: context),
        ),
        const SizedBox(height: 3),
        Text(
          t == null ? '—' : lhBillAmount(t.unpaidAmount),
          style: LhTypography.number(size: 17, color: c(_kDeep), context: context),
        ),
        const SizedBox(height: 5),
        if (t != null) ...[
          _shareBar(context, t.overdueShare),
          const SizedBox(height: 4),
          Text(
            '超7天 ${lhBillAmount(t.overdueAmount)} · ${(t.overdueShare * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LhTypography.sans(size: 10, color: c(_kOverInk), context: context),
          ),
        ],
      ],
    );
  }
}

Widget _shareBar(BuildContext context, double share) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 4,
      child: Row(
        children: [
          if (share > 0)
            Expanded(
              flex: (share * 1000).round().clamp(1, 1000),
              child: ColoredBox(
                color: DunesColors.resolve(context, _kOver, role: DunesColorRole.surface),
              ),
            ),
          if (share < 1)
            Expanded(
              flex: ((1 - share) * 1000).round().clamp(1, 1000),
              child: ColoredBox(
                color: DunesColors.resolve(context, _kRest, role: DunesColorRole.surface),
              ),
            ),
        ],
      ),
    ),
  );
}

// ── 明细弹层 ──────────────────────────────────────────────────────────────

Future<void> showLighthouseBillOutstandingSheet(
  BuildContext context,
  LhBillOutstanding data,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _BillSheet(data: data),
  );
}

class _BillSheet extends StatefulWidget {
  const _BillSheet({required this.data});

  final LhBillOutstanding data;

  @override
  State<_BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends State<_BillSheet> {
  late String _side = widget.data.payable != null ? 'AP' : 'AR';
  bool _overdueOnly = false;

  Color _c(Color v, [DunesColorRole r = DunesColorRole.foreground]) =>
      DunesColors.resolve(context, v, role: r);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final total = _side == 'AP' ? data.payable : data.receivable;
    final rows = [
      for (final g in data.groups)
        if (g.side == _side && (!_overdueOnly || g.overdueAmount > 0)) g,
    ];
    final asOf = DateTime.tryParse(data.asOf);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: _c(const Color(0xFFF5F5F7), DunesColorRole.surface),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _c(const Color(0xFFD6CBEF), DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  '未结账款',
                  style: LhTypography.sans(
                    size: 16,
                    weight: FontWeight.w700,
                    color: _c(LhColors.ink),
                    context: context,
                  ),
                ),
                const SizedBox(width: 8),
                if (data.asOf.isNotEmpty)
                  Text(
                    '截至 ${_asOfShort(data.asOf)}',
                    style: LhTypography.mono(size: 11, color: _c(LhColors.mute2), context: context),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _segment(),
            const SizedBox(height: 12),
            if (total != null) _summary(total),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '对方 × 账单类型 · ${rows.length} 组',
                  style: LhTypography.sans(
                    size: 13,
                    weight: FontWeight.w700,
                    color: _c(LhColors.ink),
                    context: context,
                  ),
                ),
                const Spacer(),
                _overdueToggle(),
              ],
            ),
            const SizedBox(height: 8),
            for (final g in rows) _groupRow(g, asOf),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    '没有未结账单',
                    style: LhTypography.sans(size: 12, color: _c(LhColors.mute2), context: context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _segment() {
    Widget seg(String key, String label, LhBillTotal? t) {
      final on = _side == key;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: t == null ? null : () => setState(() => _side = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _c(Colors.white, DunesColorRole.surface) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              t == null ? label : '$label ${lhBillAmount(t.unpaidAmount)}',
              style: LhTypography.sans(
                size: 12.5,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: _c(on ? _kDeep : LhColors.ink2),
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _c(const Color(0xFFECE7F6), DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg('AP', '应付未付款', widget.data.payable),
          seg('AR', '应收未回款', widget.data.receivable),
        ],
      ),
    );
  }

  Widget _summary(LhBillTotal t) {
    final cntShare = t.unpaidCount == 0 ? 0.0 : t.overdueCount / t.unpaidCount;
    TextStyle small(Color col) => LhTypography.sans(size: 11, color: _c(col), context: context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _c(const Color(0xFFF7F3FC), DunesColorRole.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _c(const Color(0xFFE2D8F0), DunesColorRole.border), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lhBillAmount(t.unpaidAmount),
                style: LhTypography.number(size: 26, color: _c(_kDeep), context: context),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('${t.unpaidCount} 张', style: small(LhColors.mute2)),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('超 7 天', style: small(_kOverInk)),
                  Text(
                    lhBillAmount(t.overdueAmount),
                    style: LhTypography.number(size: 17, color: _c(_kOver), context: context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('按金额 ${(t.overdueShare * 100).round()}% 超 7 天', style: small(LhColors.ink2)),
          const SizedBox(height: 4),
          _shareBar(context, t.overdueShare),
          const SizedBox(height: 8),
          Text(
            '按张数 ${(cntShare * 100).round()}% 超 7 天（${t.overdueCount} / ${t.unpaidCount}）',
            style: small(LhColors.ink2),
          ),
          const SizedBox(height: 4),
          _shareBar(context, cntShare),
        ],
      ),
    );
  }

  Widget _overdueToggle() {
    final on = _overdueOnly;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _overdueOnly = !on),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _c(on ? const Color(0xFFFBEEE9) : Colors.white, DunesColorRole.surface),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _c(on ? const Color(0xFFE8B8A8) : const Color(0xFFE4DCF4), DunesColorRole.border),
            width: 0.8,
          ),
        ),
        child: Text(
          '只看超 7 天',
          style: LhTypography.sans(
            size: 11.5,
            weight: on ? FontWeight.w700 : FontWeight.w500,
            color: _c(on ? _kOverInk : LhColors.ink2),
            context: context,
          ),
        ),
      ),
    );
  }

  Widget _groupRow(LhBillGroup g, DateTime? asOf) {
    final age = (asOf != null && g.earliestEnd != null)
        ? asOf.difference(g.earliestEnd!).inDays
        : null;
    final matched = g.provinceName.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _c(Colors.white, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _c(_kLine, DunesColorRole.border), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      g.counterparty.isEmpty ? '（未填对方）' : g.counterparty,
                      style: LhTypography.sans(
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: _c(LhColors.ink),
                        context: context,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: _c(
                          matched ? const Color(0xFFE5F0EA) : const Color(0xFFF0EFF3),
                          DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        matched ? g.provinceName : '未匹配',
                        style: LhTypography.sans(
                          size: 10,
                          weight: FontWeight.w700,
                          color: _c(matched ? const Color(0xFF2F6B4C) : LhColors.ink2),
                          context: context,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${g.billType} · 我方 ${g.ourEntity.isEmpty ? '—' : g.ourEntity}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(size: 11, color: _c(LhColors.ink2), context: context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lhBillAmount(g.unpaidAmount),
                style: LhTypography.number(size: 15, color: _c(LhColors.ink), context: context),
              ),
              const SizedBox(height: 2),
              Text(
                '${g.billCount} 张',
                style: LhTypography.mono(size: 10, color: _c(LhColors.mute2), context: context),
              ),
              if (g.overdueAmount > 0) ...[
                const SizedBox(height: 3),
                Text(
                  '超7天 ${lhBillAmount(g.overdueAmount)}',
                  style: LhTypography.sans(size: 10.5, color: _c(_kOverInk), context: context),
                ),
              ],
              if (age != null && age >= 0) ...[
                const SizedBox(height: 2),
                Text(
                  '最老 $age 天',
                  style: LhTypography.mono(size: 10, color: _c(LhColors.mute2), context: context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
