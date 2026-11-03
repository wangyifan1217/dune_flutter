import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_main_tab_bar.dart';
import 'lighthouse_business_finance.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';
import 'lighthouse_visibility_sheet.dart';

// ════════════════════════════════════════════════════════════════════════
// 资管（2026-11-02 重做 · v2 对齐灯塔账本字阶）
//
//   入口页两个板块，各自一页：
//     · 业财对照：资管业财标签二（0.10），某一天、一个主体一张卡。
//       卡片同灯塔账本：左边主体身份，右边两块面板（业务 | 财务）共 6 个数；
//       「展开」后是全部指标，业务与财务按对应关系同排。点业务指标，
//       同排财务指标旁直接显示业财差额（不单独列差额表）；选中的指标所有卡片共用。
//       余额取当天；发生额是 1 月 1 日起累计，不跨天相加、不两天相减。
//     · 未结往来：资管「应收应付合计统计」四个 Tab（2.0）——渠道应收 / 渠道预收 /
//       渠道应付 / 供给应收。当前未结，不是历史；统计日只移动逾期线
//       （结束日后超过 15 天）。四个口径范围不同，不相加、不算净额。
//   字号跟灯塔账本一套：名称 12、指标标签 10、数值 13（单位 8.5）、角标 9。
//   页面用语保持正式：应收 / 应付 / 预收、多收 / 多付，不用口语化描述。
// ════════════════════════════════════════════════════════════════════════

const _kInk = Color(0xFF1F2421);
const _kInk2 = Color(0xFF5A5C56);
const _kMute = Color(0xFF94938A);
const _kBg = Color(0xFFF4F2F8);
const _kEdge = Color(0xFFE7E3EF);
const _kLine = Color(0xFFECE8F3);
const _kNeutralPanel = Color(0xFFF7F6FA);
const _kPurple = Color(0xFF7B5CD8);
const _kDeep = Color(0xFF5A458F);
const _kLavender = Color(0xFFF0ECF6);
const _kMist = Color(0xFFF5F2FA);
const _kFin = Color(0xFF2F6EA8);
const _kFinSoft = Color(0xFFE6EEF7);
const _kCopper = Color(0xFFB07A2B);
const _kCopperSoft = Color(0xFFF8EEDD);
const _kGreySoft = Color(0xFFEEEEF1);
const _kGrey = Color(0xFF5A5C56);

Color _fg(BuildContext context, Color c) => DunesColors.resolve(context, c);
Color _bg(BuildContext context, Color c) =>
    DunesColors.resolve(context, c, role: DunesColorRole.surface);
Color _ln(BuildContext context, Color c) =>
    DunesColors.resolve(context, c, role: DunesColorRole.border);

TextStyle _sans(
  BuildContext context, {
  double size = 12,
  FontWeight weight = FontWeight.w400,
  Color color = _kInk,
  double? height,
}) => LhTypography.sans(
  context: context,
  size: size,
  weight: weight,
  color: _fg(context, color),
  height: height,
);

TextStyle _mono(
  BuildContext context, {
  double size = 10,
  FontWeight weight = FontWeight.w500,
  Color color = _kInk,
}) => LhTypography.mono(
  context: context,
  size: size,
  weight: weight,
  color: _fg(context, color),
  height: 1.0,
);

/// 差额配色同灯塔：正数红、负数绿、0 灰（业财：正 = 业务高；未结：正 = 未结）。
Color _diffColor(double? v) {
  if (v == null || v.abs() < 0.5) return LhColors.mute2;
  return v > 0 ? LhColors.neg : LhColors.pos;
}

/// 元 → 带符号的万（不带单位）。
String _signedWan(double? yuan) {
  if (yuan == null) return '—';
  if (yuan.abs() < 0.5) return '0.00';
  return '${yuan > 0 ? '+' : '−'}${lhBfWan(yuan.abs())}';
}

BoxDecoration _cardDeco(BuildContext context, {double radius = 14}) => BoxDecoration(
  color: _bg(context, Colors.white),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: _ln(context, _kEdge), width: 0.8),
);

Widget _tag(BuildContext context, String text, Color fg, Color bg, {bool solid = false}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
  decoration: BoxDecoration(
    color: solid ? _fg(context, bg) : _bg(context, bg),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(
    text,
    maxLines: 1,
    style: solid
        ? LhTypography.sans(context: context, size: 9.5, weight: FontWeight.w600, color: Colors.white, height: 1.1)
        : _sans(context, size: 9.5, weight: FontWeight.w600, color: fg, height: 1.1),
  ),
);

Widget _indexBadge(BuildContext context, int i) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  decoration: BoxDecoration(
    color: _bg(context, _kLavender),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(
    i.toString().padLeft(2, '0'),
    style: _mono(context, size: 9.5, weight: FontWeight.w600, color: _kDeep),
  ),
);

/// 数值：数字 13 + 单位 8.5，同灯塔账本摘要格。
Widget _amount(
  BuildContext context,
  String text, {
  String unit = '万',
  Color color = _kInk,
  double size = 13,
}) {
  final missing = text == '—' || text.isEmpty;
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: missing ? '—' : text,
            style: LhTypography.number(
              context: context,
              size: missing ? 11.5 : size,
              color: _fg(context, missing ? _kMute : color),
            ).copyWith(height: 1.0),
          ),
          if (!missing && unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: LhTypography.sans(
                context: context,
                size: 8.5,
                weight: FontWeight.w500,
                color: _fg(context, _kMute),
                height: 1.0,
              ),
            ),
        ],
      ),
      maxLines: 1,
    ),
  );
}

/// 面板里的一格：标签一行（右端角标），数值一行。选中时白底浮起（同灯塔）。
Widget _cell(
  BuildContext context, {
  required String label,
  required String value,
  String unit = '万',
  Color color = _kInk,
  String? badge,
  Color? badgeColor,
  bool active = false,
  VoidCallback? onTap,
}) {
  final body = AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
    margin: EdgeInsets.symmetric(horizontal: active ? 2 : 0),
    padding: EdgeInsets.fromLTRB(active ? 7 : 9, active ? 5 : 6, active ? 6 : 8, active ? 4 : 5),
    decoration: BoxDecoration(
      color: active ? _bg(context, Colors.white) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: active ? _fg(context, _kPurple).withAlpha(46) : Colors.transparent,
        width: 0.8,
      ),
      boxShadow: active
          ? [BoxShadow(color: _kDeep.withAlpha(28), blurRadius: 6, offset: const Offset(0, 1.5))]
          : null,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(
                  context,
                  size: 10,
                  weight: FontWeight.w700,
                  color: active ? _kDeep : _kInk2,
                  height: 1.0,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Text(
                badge,
                maxLines: 1,
                style: _mono(context, size: 9, weight: FontWeight.w600, color: badgeColor ?? _kInk2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        _amount(context, value, unit: unit, color: color),
      ],
    ),
  );
  if (onTap == null) return body;
  return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body);
}

/// 同列格子拼成一块面板：中性底 / 淡色底，行间内缩发丝线。[title] = 面板抬头（带色点）。
Widget _panel(BuildContext context, List<Widget> cells, {Color? tint, String? title, Color? titleColor}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 2),
    decoration: BoxDecoration(
      color: tint == null ? _bg(context, _kNeutralPanel) : _fg(context, tint).withAlpha(24),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 6, 8, 2),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: _fg(context, titleColor ?? _kInk2), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(title, style: _sans(context, size: 9.5, weight: FontWeight.w700, color: titleColor ?? _kInk2, height: 1.0)),
              ],
            ),
          ),
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(height: 0.6, color: _ln(context, _kLine)),
            ),
          cells[i],
        ],
      ],
    ),
  );
}

/// 板块标题：同灯塔「产品汇总」—— 紫底小图标 + 13.5 标题 + 日期角标。
Widget _sectionHead(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? chip,
  Widget? trailing,
}) {
  return Row(
    children: [
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: _fg(context, _kPurple),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
      const SizedBox(width: 8),
      Text(title, style: _sans(context, size: 13.5, weight: FontWeight.w700)),
      if (chip != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _bg(context, _kLavender),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(chip, style: _mono(context, size: 9.5, weight: FontWeight.w600, color: _kDeep)),
        ),
      ],
      const Spacer(),
      if (trailing != null) trailing,
    ],
  );
}

Widget _pageHeader(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
    child: Row(
      children: [
        IconButton(
          tooltip: '返回',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.chevron_left_rounded, size: 24, color: _fg(context, _kInk2)),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 18, weight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
}

/// 顶栏右侧日期岛：同灯塔「今日 11.02」那一档。
Widget _dateIsland(BuildContext context, String label, String value, VoidCallback onTap) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _bg(context, Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _ln(context, _kEdge), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _sans(context, size: 11, color: _kInk2)),
            const SizedBox(width: 6),
            Text(value, style: _mono(context, size: 11, weight: FontWeight.w600, color: _kDeep)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 15, color: _fg(context, _kInk2)),
          ],
        ),
      ),
    ),
  );
}

Widget _chip(BuildContext context, String text, bool on, VoidCallback onTap) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _bg(context, on ? _kLavender : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ln(context, on ? _kLavender : _kEdge), width: 0.8),
      ),
      child: Text(
        text,
        style: _sans(
          context,
          size: 11.5,
          weight: on ? FontWeight.w700 : FontWeight.w500,
          color: on ? _kDeep : _kInk,
        ),
      ),
    ),
  );
}

/// 卡片底栏：同灯塔「↳ 细分 2 · … 展开」。
Widget _footBar(
  BuildContext context, {
  required String title,
  required String text,
  required bool open,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _fg(context, _kPurple),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(Icons.subdirectory_arrow_right_rounded, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Text(title, style: _sans(context, size: 11.5, weight: FontWeight.w700, color: _kDeep)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sans(context, size: 10.5, color: _kInk2),
            ),
          ),
          Text(open ? '收起' : '展开', style: _sans(context, size: 11.5, weight: FontWeight.w600, color: _kPurple)),
          Icon(
            open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 16,
            color: _fg(context, _kPurple),
          ),
        ],
      ),
    ),
  );
}

Widget _statusBox(BuildContext context, String text, {VoidCallback? onRetry}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardDeco(context),
    child: Column(
      children: [
        Text(text, textAlign: TextAlign.center, style: _sans(context, size: 12, color: _kInk2, height: 1.6)),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ],
    ),
  );
}

Widget _loadingBox(BuildContext context) => Container(
  height: 96,
  alignment: Alignment.center,
  decoration: _cardDeco(context),
  child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
);

Color _groupColor(String group) => switch (group) {
  '中石油' => LhColors.cnpc,
  '中石化' => LhColors.sinopec,
  '中油BP' => const Color(0xFF2F7D5B),
  _ => LhColors.mute2,
};

/// 页面骨架：顶栏 + 下拉刷新 + 内容。
Widget _scaffold(
  BuildContext context, {
  required Widget header,
  required List<Widget> children,
  required Future<void> Function() onRefresh,
}) {
  return Scaffold(
    backgroundColor: _bg(context, _kBg),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            0,
            0,
            dunesAppBottomNavContentPadding(context, fallback: 32),
          ),
          children: [
            header,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
    ),
  );
}


/// 「👥 N」：同灯塔各板块 / 各行的权限入口。普通人只读，授权管理人（许正阳）可改。
Widget _visButton(
  BuildContext context,
  LighthouseService service,
  String module,
  VoidCallback onTap, {
  String? entity,
}) {
  return LhVisibilityChip(service: service, module: module, entity: entity, onTap: onTap);
}

Future<void> _openVisibility(
  BuildContext context, {
  required LighthouseService service,
  required AuthSession session,
  required String module,
  required String title,
  String? entity,
}) {
  return showLighthouseVisibilitySheet(
    context,
    service: service,
    session: session,
    title: title,
    module: module,
    entity: entity,
  );
}

/// 指标性质角标：余额 / 累计 / 状态。
Widget _kindTag(BuildContext context, String kind) => switch (kind) {
  '余额' => _tag(context, '余额', _kFin, _kFinSoft),
  '累计' => _tag(context, '1.1 起累计', _kCopper, _kCopperSoft),
  _ => _tag(context, kind, _kGrey, _kGreySoft),
};

String _mdDate(DateTime x, DateTime ref) {
  final md = '${x.month}.${x.day.toString().padLeft(2, '0')}';
  return x.year == ref.year ? md : '${x.year}.$md';
}

/// 逾期日 = 账期结束日后第 (宽限天数 + 1) 天（资管：DATEDIFF(统计日, 结束日) > 15）。
DateTime _overdueFrom(DateTime end, int grace) => end.add(Duration(days: grace + 1));

/// 统计日这天，账期截至哪天及以前的已逾期 = 统计日 − (宽限天数 + 1)。
DateTime _overdueCutoff(DateTime asOf, int grace) => asOf.subtract(Duration(days: grace + 1));

/// 灯塔 / 资管同级切换：滑动的选中块，当前项深色，另一项点一下过去。
class LhBrandSwitch extends StatelessWidget {
  const LhBrandSwitch({
    super.key,
    required this.assetSelected,
    required this.onLighthouse,
    required this.onAsset,
    required this.selectedColor,
    required this.idleColor,
    required this.trackColor,
    required this.thumbColor,
  });

  final bool assetSelected;
  final VoidCallback onLighthouse;
  final VoidCallback onAsset;
  final Color selectedColor;
  final Color idleColor;
  final Color trackColor;
  final Color thumbColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / 2;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    left: assetSelected ? width : 0,
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B5CD8).withValues(alpha: 0.22),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _segment(
                        context,
                        label: '灯塔',
                        selected: !assetSelected,
                        onTap: onLighthouse,
                      ),
                      _segment(
                        context,
                        label: '资管',
                        selected: assetSelected,
                        onTap: onAsset,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: LhTypography.sans(
                context: context,
                size: 14,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? selectedColor : idleColor,
                letterSpacing: 0.2,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// 资管入口页顶栏：「灯塔  资管」同级切换（资管选中），点「灯塔」回去。
Widget _switchHeader(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: LhBrandSwitch(
        assetSelected: true,
        onLighthouse: () => Navigator.of(context).maybePop(),
        onAsset: () {},
        selectedColor: _fg(context, const Color(0xFF2B2147)),
        idleColor: _fg(context, const Color(0xFF8A80AE)),
        trackColor: const Color(0x142B2147),
        thumbColor: _bg(context, Colors.white),
      ),
    ),
  );
}
// ═════════════════════════════ 未结往来 · 模型 ═════════════════════════════

class LhLedgerGroup {
  const LhLedgerGroup({
    required this.projectName,
    required this.provinceName,
    required this.billTypeCode,
    required this.billTypeName,
    required this.billCount,
    required this.overdueCount,
    required this.diffAmount,
    required this.overdueAmount,
    required this.earliestEnd,
    required this.latestEnd,
  });

  factory LhLedgerGroup.fromJson(Map raw) {
    String? s(String k) {
      final v = raw[k];
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    return LhLedgerGroup(
      projectName: s('projectName'),
      provinceName: s('provinceName'),
      billTypeCode: s('billTypeCode'),
      billTypeName: s('billTypeName'),
      billCount: (raw['billCount'] as num?)?.toInt() ?? 0,
      overdueCount: (raw['overdueCount'] as num?)?.toInt() ?? 0,
      diffAmount: (raw['diffAmount'] as num?)?.toDouble() ?? 0,
      overdueAmount: (raw['overdueAmount'] as num?)?.toDouble() ?? 0,
      earliestEnd: s('earliestBillEnd'),
      latestEnd: s('latestBillEnd'),
    );
  }

  final String? projectName;
  final String? provinceName;
  final String? billTypeCode;
  final String? billTypeName;
  final int billCount;
  final int overdueCount;
  final double diffAmount;
  final double overdueAmount;
  final String? earliestEnd;
  final String? latestEnd;

  String label(String code) => code == 'SUPPLY'
      ? (provinceName ?? '未分省')
      : (projectName ?? '（空）');

  String get typeLabel => billTypeName ?? billTypeCode ?? '（未分类）';

  bool get hasOverdue => overdueAmount.abs() >= 0.0005;
}

class LhLedgerDim {
  const LhLedgerDim({
    required this.code,
    required this.name,
    required this.diffAmount,
    required this.billCount,
    required this.overdueAmount,
    required this.overdueCount,
    required this.groups,
  });

  factory LhLedgerDim.fromJson(Map raw) {
    final groups = <LhLedgerGroup>[];
    final g = raw['groups'];
    if (g is List) {
      for (final x in g) {
        if (x is Map) groups.add(LhLedgerGroup.fromJson(x));
      }
    }
    return LhLedgerDim(
      code: (raw['code'] ?? '').toString().trim().toUpperCase(),
      name: (raw['name'] ?? '').toString().trim(),
      diffAmount: (raw['diffAmount'] as num?)?.toDouble() ?? 0,
      billCount: (raw['billCount'] as num?)?.toInt() ?? 0,
      overdueAmount: (raw['overdueAmount'] as num?)?.toDouble() ?? 0,
      overdueCount: (raw['overdueCount'] as num?)?.toInt() ?? 0,
      groups: groups,
    );
  }

  final String code;
  final String name;
  final double diffAmount;
  final int billCount;
  final double overdueAmount;
  final int overdueCount;
  final List<LhLedgerGroup> groups;

  /// 逾期占差额的比例；差额不为正（多收 / 已取反的预收）时不画。
  double? get overdueShare {
    if (diffAmount <= 0.0005 || overdueAmount <= 0) return null;
    return (overdueAmount / diffAmount).clamp(0.0, 1.0).toDouble();
  }
}

class LhLedger {
  const LhLedger({
    required this.asOf,
    required this.graceDays,
    required this.dims,
    required this.restricted,
    required this.unavailable,
    required this.fixture,
  });

  factory LhLedger.fromJson(Map<String, dynamic> data) {
    final dims = <String, LhLedgerDim>{};
    final raw = data['dimensions'];
    if (raw is List) {
      for (final x in raw) {
        if (x is Map) {
          final d = LhLedgerDim.fromJson(x);
          if (d.code.isNotEmpty) dims[d.code] = d;
        }
      }
    }
    final grace = (data['graceDays'] as num?)?.toInt();
    return LhLedger(
      asOf: (data['asOf'] ?? '').toString(),
      graceDays: grace == null || grace <= 0 ? 15 : grace,
      dims: dims,
      restricted: data['restricted'] == true,
      unavailable: data['unavailable'] == true,
      fixture: data['fixture'] == true,
    );
  }

  final String asOf;
  final int graceDays;
  final Map<String, LhLedgerDim> dims;
  final bool restricted;
  final bool unavailable;
  final bool fixture;

  LhLedgerDim? dim(String code) => dims[code];
}

/// 四个口径的页面说明（与资管四个 Tab 一一对应，顺序固定）。
class _DimMeta {
  const _DimMeta({
    required this.code,
    required this.title,
    required this.tab,
    required this.tag,
    required this.tone,
    required this.firstCol,
    required this.summary,
    required this.rules,
    required this.negLabel,
  });

  final String code;
  final String title;
  final String tab;
  final String tag;
  final int tone; // 0 应收 · 1 预收 · 2 应付
  final String firstCol;
  final String summary;
  final List<(String, String)> rules;
  final String negLabel;

  Color get fg => switch (tone) {
    0 => _kCopper,
    1 => _kGrey,
    _ => _kFin,
  };
  Color get bg => switch (tone) {
    0 => _kCopperSoft,
    1 => _kGreySoft,
    _ => const Color(0xFFE3EEF7),
  };
}

const _kDimMeta = <String, _DimMeta>{
  'CHANNEL': _DimMeta(
    code: 'CHANNEL',
    title: '渠道应收',
    tab: '渠道应收统计',
    tag: '应收',
    tone: 0,
    firstCol: '财务项目',
    summary: '渠道销售类账单尚未收回的差额。',
    rules: [
      ('分组', '财务项目 × 账单类型'),
      ('差额', '账单金额与已收金额之差；部分回款的账单按剩余差额计入'),
      ('负数', '多收'),
      ('范围', '账单开始日晚于当天的不计入；预收名单内的项目不计入'),
    ],
    negLabel: '多收',
  ),
  'PREPAID': _DimMeta(
    code: 'PREPAID',
    title: '渠道预收',
    tab: '渠道预收统计',
    tag: '预收',
    tone: 1,
    firstCol: '财务项目',
    summary: '预收名单内项目的未结差额，金额已按资管口径取反列示。',
    rules: [
      ('分组', '财务项目 × 账单类型'),
      ('差额', '取反后列示：正数为多收的预收款'),
      ('负数', '预收款未收足'),
      ('范围', '账单开始日晚于当天的不计入；预收名单为空时无数据'),
    ],
    negLabel: '未收足',
  ),
  'PAYABLE': _DimMeta(
    code: 'PAYABLE',
    title: '渠道应付',
    tab: '渠道应付统计',
    tag: '应付',
    tone: 2,
    firstCol: '项目',
    summary: '应付渠道款项尚未支付的差额。',
    rules: [
      ('分组', '项目 × 账单类型'),
      ('差额', '账单金额与已付金额之差'),
      ('负数', '多付'),
      ('范围', '不含供应商应付；不做未到期截断；差额为 0 的分组同样列示'),
    ],
    negLabel: '多付',
  ),
  'SUPPLY': _DimMeta(
    code: 'SUPPLY',
    title: '供给应收',
    tab: '供给应收统计',
    tag: '应收',
    tone: 0,
    firstCol: '省份',
    summary: '供给侧应收款项（如应收返利）尚未收回的差额。',
    rules: [
      ('分组', '省份 × 账单类型'),
      ('差额', '账单金额与已收金额之差'),
      ('负数', '多收'),
      ('范围', '不按日期截断；未归属省份的列为「未分省」'),
    ],
    negLabel: '多收',
  ),
};


// ═════════════════════════════ 入口页 ═════════════════════════════

class LighthouseZgHubPage extends StatefulWidget {
  const LighthouseZgHubPage({
    super.key,
    required this.service,
    required this.session,
    this.onOpenLegacy,
    this.embedded = false,
  });

  final LighthouseService service;
  final AuthSession session;

  /// 原资管页（主体明细 / 净TA）。为空则不显示入口。
  final VoidCallback? onOpenLegacy;

  /// 嵌在灯塔页里时，顶栏切换由灯塔自己画，这里不再重复一条。
  final bool embedded;

  @override
  State<LighthouseZgHubPage> createState() => _ZgHubState();
}

class _ZgHubState extends State<LighthouseZgHubPage> {
  LhBfSummary? _bf;
  String? _bfError;
  bool _bfLoading = true;
  LhLedger? _bills;
  String? _billError;
  bool _billLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchBf());
    unawaited(_fetchBills());
  }

  Future<void> _fetchBf() async {
    try {
      final data = await widget.service.fetchBusinessFinance();
      if (!mounted) return;
      setState(() {
        _bf = LhBfSummary.from(data);
        _bfError = null;
        _bfLoading = false;
      });
    } on LighthouseBfException catch (e) {
      if (!mounted) return;
      setState(() {
        _bfError = e.forbidden ? '暂无权限' : e.message;
        _bfLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bfError = '$e'.replaceFirst('Exception: ', '');
        _bfLoading = false;
      });
    }
  }

  Future<void> _fetchBills() async {
    try {
      final data = await widget.service.fetchBillOutstanding();
      if (!mounted) return;
      setState(() {
        _bills = LhLedger.fromJson(data);
        _billError = null;
        _billLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _billError = '$e'.replaceFirst('Exception: ', '');
        _billLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_fetchBf(), _fetchBills()]);
  }

  void _openBf() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'lighthouse/zg/bf'),
        builder: (_) => LighthouseBfLinkedPage(service: widget.service, session: widget.session),
      ),
    );
  }

  void _openBills() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'lighthouse/zg/bills'),
        builder: (_) => LighthouseLedgerPage(service: widget.service, session: widget.session, initial: _bills),
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(text, style: _sans(context, size: 11.5, color: _kInk2)),
  );

  Widget _bfBody(BuildContext context) {
    if (_bfLoading && _bf == null) return _hint(context, '加载中…');
    final t = _bf?.total;
    if (_bf == null) return _hint(context, _bfError ?? '暂无数据');
    if (t == null) return _hint(context, '当日暂无快照');
    final d = t.difference['assetPrincipal'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _panel(context, [
            _cell(context, label: '业务资产', value: lhBfWan(t.business['assetPrincipal']), color: _kPurple),
            _cell(context, label: '电子券销售额', value: lhBfWan(t.business['salesAmount']), color: _kPurple),
          ], title: '业务', titleColor: _kPurple),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _panel(context, [
            _cell(
              context,
              label: '财务资产',
              value: lhBfWan(t.finance['assetPrincipal']),
              color: _kFin,
              badge: '差 ${_signedWan(d)}',
              badgeColor: _diffColor(d),
            ),
            _cell(
              context,
              label: '销售回款',
              value: lhBfWan(t.finance['salesAmount']),
              color: _kFin,
              badge: '差 ${_signedWan(t.difference['salesAmount'])}',
              badgeColor: _diffColor(t.difference['salesAmount']),
            ),
          ], tint: _kFin, title: '财务', titleColor: _kFin),
        ),
      ],
    );
  }

  Widget _billBody(BuildContext context) {
    if (_billLoading && _bills == null) return _hint(context, '加载中…');
    final b = _bills;
    if (b == null) return _hint(context, _billError ?? '暂无数据');
    if (b.restricted) return _hint(context, '暂无权限');
    if (b.unavailable) return _hint(context, '资管接口未配置');
    Widget cell(String code) {
      final m = _kDimMeta[code]!;
      final d = b.dim(code);
      return _cell(
        context,
        label: m.title,
        value: d == null ? '—' : lhBfWan(d.diffAmount),
        color: (d?.diffAmount ?? 0) < 0 ? LhColors.pos : _kInk,
        badge: d == null ? null : '逾期 ${lhBfWan(d.overdueAmount)}',
        badgeColor: _kCopper,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _panel(context, [cell('CHANNEL'), cell('SUPPLY')], title: '应收', titleColor: _kCopper)),
        const SizedBox(width: 8),
        Expanded(child: _panel(context, [cell('PREPAID'), cell('PAYABLE')], tint: _kFin, title: '预收与应付', titleColor: _kFin)),
      ],
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String chip,
    required String subtitle,
    required Widget body,
    required String foot,
    required VoidCallback onTap,
    required String module,
    required VoidCallback onVisibility,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: _cardDeco(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHead(
                context,
                icon: icon,
                title: title,
                chip: chip.isEmpty ? null : chip,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _visButton(context, widget.service, module, onVisibility),
                    const SizedBox(width: 8),
                    Text('进入', style: _sans(context, size: 11, weight: FontWeight.w600, color: _kPurple)),
                    Icon(Icons.chevron_right_rounded, size: 16, color: _fg(context, _kPurple)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(subtitle, style: _sans(context, size: 10.5, color: _kInk2)),
              ),
              const SizedBox(height: 10),
              body,
              const SizedBox(height: 8),
              Text(foot, style: _sans(context, size: 10, color: _kMute)),
            ],
          ),
        ),
      ),
    );
  }

  bool get _bfForbidden => _bf == null && _bfError == '暂无权限';
  bool get _billForbidden => _bills == null && (_billError ?? '').contains('暂无权限') || (_bills?.restricted ?? false);

  void _visibility(String module, String title) {
    unawaited(
      _openVisibility(context, service: widget.service, session: widget.session, module: module, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bf = _bf;
    final bills = _bills;
    final bfChip = bf == null || bf.asOfDate.isEmpty ? '' : lhBfShortDate(bf.asOfDate);
    final billChip = bills == null || bills.asOf.isEmpty ? '' : lhBfShortDate(bills.asOf);
    final bfFoot = bf == null || bf.rowsRestricted
        ? '单位：万元'
        : '${bf.rows.length} 个主体 · 余额截至当日，发生额 1 月 1 日起累计 · 单位：万元';
    final billAsOf = DateTime.tryParse(bills?.asOf ?? '');
    final billFoot = billAsOf == null
        ? '当前未结 · 账期结束日后第 ${(bills?.graceDays ?? 15) + 1} 天起逾期 · 单位：万元'
        : '当前未结 · 账期截至 ${_mdDate(_overdueCutoff(billAsOf, bills!.graceDays), billAsOf)} 及以前的已逾期 · 单位：万元';
    final cards = <Widget>[
      // 没有板块权限的人不出入口（许正阳在「谁能看到」里开关）。
      if (!_bfForbidden)
        _entry(
          context,
          icon: Icons.view_column_outlined,
          title: '业财对照',
          chip: bfChip,
          subtitle: '业务数据与财务数据按指标对照，选中指标显示业财差额',
          body: _bfBody(context),
          foot: bfFoot,
          onTap: _openBf,
          module: 'business_finance',
          onVisibility: () => _visibility('business_finance', '资管 · 业财对照'),
        ),
      if (!_billForbidden)
        _entry(
          context,
          icon: Icons.swap_horiz_rounded,
          title: '未结往来',
          chip: billChip,
          subtitle: '渠道应收、供给应收、渠道预收、渠道应付的未结差额与逾期',
          body: _billBody(context),
          foot: billFoot,
          onTap: _openBills,
          module: 'bills',
          onVisibility: () => _visibility('bills', '资管 · 未结往来'),
        ),
    ];
    return _scaffold(
      context,
      onRefresh: _refresh,
      header: widget.embedded ? const SizedBox(height: 8) : _switchHeader(context),
      children: [
        if (cards.isEmpty) _statusBox(context, '暂无资管板块权限'),
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          cards[i],
        ],
        if (widget.onOpenLegacy != null) ...[
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onOpenLegacy,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: _cardDeco(context),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('主体明细与净TA', style: _sans(context, size: 12.5, weight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: _fg(context, _kMute)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═════════════════════════════ 业财对照 ═════════════════════════════

/// 一排对照：业务指标 ⇄ 财务指标（任一侧可空）。difference 的键与财务键相同。
class _BfPair {
  const _BfPair({
    this.biz,
    this.fin,
    this.bizLabel = '',
    this.finLabel = '',
    required this.kind,
    this.pool = false,
    this.rate = false,
    this.short = '',
  });

  /// 业务字段；pool = 资金池 + 库存券 + 同步券。
  final String? biz;
  final String? fin;
  final String bizLabel;
  final String finLabel;

  /// 余额 / 累计 / 状态。
  final String kind;
  final bool pool;
  final bool rate;

  /// 汇总卡上的短名。
  final String short;

  bool get paired => biz != null && fin != null;

  String get title => paired ? '$bizLabel ⇄ $finLabel' : (biz != null ? bizLabel : finLabel);
}

const _kPairs = <_BfPair>[
  /* 0 */ _BfPair(biz: 'assetPrincipal', fin: 'assetPrincipal', bizLabel: '业务资产', finLabel: '财务资产', kind: '余额', short: '资产'),
  /* 1 */ _BfPair(biz: '_pool', fin: 'fundBalance', bizLabel: '券池', finLabel: '预付款余额', kind: '余额', pool: true, short: '券池 ⇄ 预付款'),
  /* 2 */ _BfPair(biz: 'purchaseAmount', fin: 'purchaseAmount', bizLabel: '电子券采购额', finLabel: '电子券采购付款', kind: '累计', short: '采购 ⇄ 付款'),
  /* 3 */ _BfPair(biz: 'invoiceAmount', fin: 'invoiceAmount', bizLabel: '发票金额', finLabel: '进项发票', kind: '累计', short: '发票'),
  /* 4 */ _BfPair(biz: 'salesAmount', fin: 'salesAmount', bizLabel: '电子券销售额', finLabel: '销售回款', kind: '累计', short: '销售 ⇄ 回款'),
  /* 5 */ _BfPair(biz: 'rebateAr', fin: 'rebateAr', bizLabel: '应收返利', finLabel: '已收返利', kind: '累计', short: '返利'),
  /* 6 */ _BfPair(biz: 'platformFee', fin: 'platformFee', bizLabel: '平台服务费', finLabel: '已付平台服务费', kind: '累计', short: '平台服务费'),
  /* 7 */ _BfPair(biz: 'commission', fin: 'commission', bizLabel: '返佣', finLabel: '已付返佣', kind: '累计', short: '返佣'),
  /* 8 */ _BfPair(biz: 'paymentFee', fin: 'paymentFee', bizLabel: '支付手续费', finLabel: '已付支付手续费', kind: '累计', short: '支付手续费'),
  /* 9 */ _BfPair(biz: 'netProfit', fin: 'assetProfit', bizLabel: '利润', finLabel: '计提利润', kind: '累计', short: '利润'),
  /* 10 */ _BfPair(biz: 'zombieCouponExpense', bizLabel: '僵尸券列支', kind: '状态'),
  /* 11 */ _BfPair(biz: 'fundUtilizationRate', bizLabel: '资金利用率', kind: '状态', rate: true),
  /* 12 */ _BfPair(biz: 'drainageAmount', bizLabel: '引流', kind: '累计'),
  /* 13 */ _BfPair(biz: 'verifyAmount', bizLabel: '核销额', kind: '累计'),
  /* 14 */ _BfPair(fin: 'bankBalance', finLabel: '银行账户余额', kind: '余额'),
  /* 15 */ _BfPair(fin: 'borrowIn', finLabel: '资金借入', kind: '余额'),
  /* 16 */ _BfPair(fin: 'borrowOut', finLabel: '资金借出', kind: '余额'),
];

/// 展开后的分组：标题、色条、说明、包含哪几排。
const _kPairSections = <(String, int, String, List<int>)>[
  ('资产与余额', 0xFF7B5CD8, '截至当日', [0, 1]),
  ('采购与发票', 0xFF3B6E96, '1 月 1 日起累计', [2, 3]),
  ('销售与返利', 0xFFB07A2B, '1 月 1 日起累计', [4, 5]),
  ('费用与利润', 0xFF2F7D5B, '1 月 1 日起累计', [6, 7, 8, 9]),
  ('仅业务列示', 0xFF94938A, '无对应财务指标，不计差额', [10, 11, 12, 13]),
  ('仅财务列示', 0xFF94938A, '无对应业务指标，不计差额', [14, 15, 16]),
];

/// 卡片摘要与汇总卡里可切换的三排：资产、券池对预付款、销售对回款。
const _kSummaryPairs = [0, 1, 4];

double? _bizVal(LhBfRow r, _BfPair p) {
  if (p.biz == null) return null;
  if (p.pool) return r.businessCouponPool;
  return r.business[p.biz!];
}

double? _finVal(LhBfRow r, _BfPair p) => p.fin == null ? null : r.finance[p.fin!];

String _valText(double? v, _BfPair p) {
  if (p.rate) return v == null ? '—' : lhBfNum(v * 100);
  return lhBfWan(v);
}

double? _pairDiff(LhBfRow r, _BfPair p) => p.paired ? r.difference[p.fin!] : null;


class LighthouseBfLinkedPage extends StatefulWidget {
  const LighthouseBfLinkedPage({super.key, required this.service, required this.session});

  final LighthouseService service;
  final AuthSession session;

  @override
  State<LighthouseBfLinkedPage> createState() => _BfLinkedState();
}

class _BfLinkedState extends State<LighthouseBfLinkedPage> {
  DateTime? _date;
  LhBfSummary? _s;
  String? _error;
  bool _loading = true;
  String _group = '全部';

  /// 选中的对照排（汇总卡与全部主体卡共用）。默认「业务资产 ⇄ 财务资产」。
  int _pair = 0;

  /// 展开解释框的位置：'<卡片 key>' = 卡片摘要，'<卡片 key>#grid' = 全部指标里那一排。同一时间只开一个。
  String? _explain;

  /// 汇总卡当前看的那一项（_kSummaryPairs 的下标）。
  int _heroPair = 0;
  final Set<String> _open = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    try {
      final data = await widget.service.fetchBusinessFinance(
        asOfDate: _date == null ? null : lhBfDateParam(_date!),
      );
      if (!mounted) return;
      setState(() {
        _s = LhBfSummary.from(data);
        _error = null;
        _loading = false;
      });
    } on LighthouseBfException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.forbidden ? '暂无权限查看业财对照' : e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _fetch();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: now,
      helpText: '截至日期',
    );
    if (picked == null || !mounted) return;
    final isToday = picked.year == now.year && picked.month == now.month && picked.day == now.day;
    setState(() => _date = isToday ? null : DateTime(picked.year, picked.month, picked.day));
    await _reload();
  }

  String get _dateValue {
    final a = _s?.asOfDate ?? '';
    if (a.isNotEmpty) return lhBfShortDate(a);
    if (_date != null) return lhBfShortDate(lhBfDateParam(_date!));
    return '';
  }

  /// 点一对：选中它并在 [where] 下方展开解释框；再点同一对收起。
  void _tapPair(int i, String where) {
    setState(() {
      if (_pair == i && _explain == where) {
        _explain = null;
      } else {
        _pair = i;
        _explain = _kPairs[i].paired ? where : null;
      }
    });
  }

  int _pairCount() => _kPairs.length;

  void _toggle(String key) {
    setState(() {
      if (!_open.remove(key)) _open.add(key);
    });
  }

  void _showVisibility({LhBfRow? row}) {
    unawaited(
      _openVisibility(
        context,
        service: widget.service,
        session: widget.session,
        module: 'business_finance',
        title: row == null ? '资管 · 业财对照' : '${row.title} · 业财对照',
        entity: row?.subjectKey,
      ),
    );
  }

  List<String> _groups(LhBfSummary s) {
    final seen = <String>{for (final r in s.rows) r.group};
    const order = ['中石油', '中石化', '中油BP', '全国', '待归属', '其它'];
    return ['全部', ...order.where(seen.contains)];
  }

  List<LhBfRow> _rows(LhBfSummary s) {
    final list = s.rows.where((r) => _group == '全部' || r.group == _group).toList();
    list.sort((a, b) {
      if (a.isTail != b.isTail) return a.isTail ? 1 : -1;
      final da = (a.difference['assetPrincipal'] ?? 0).abs();
      final db = (b.difference['assetPrincipal'] ?? 0).abs();
      return db.compareTo(da);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final children = <Widget>[];
    if (s == null) {
      children.add(_loading ? _loadingBox(context) : _statusBox(context, _error ?? '暂无数据', onRetry: _reload));
    } else {
      if (_loading) {
        children
          ..add(const LinearProgressIndicator(minHeight: 2))
          ..add(const SizedBox(height: 8));
      }
      if (_error != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('刷新失败：$_error', style: _sans(context, size: 11, color: LhColors.neg)),
          ),
        );
      }
      final rows = _rows(s);
      if (s.total == null && s.rows.isEmpty) {
        children.add(_statusBox(context, s.note.isNotEmpty ? s.note : '当日暂无快照'));
      } else {
        if (s.total != null) {
          children
            ..add(_heroCard(context, s, s.total!))
            ..add(const SizedBox(height: 12));
        }
        if (s.rows.isNotEmpty) {
          children
            ..add(_listHead(context, s))
            ..add(const SizedBox(height: 8));
          for (var i = 0; i < rows.length; i++) {
            children
              ..add(_subjectCard(context, rows[i], i + 1))
              ..add(const SizedBox(height: 8));
          }
        } else if (s.rowsRestricted) {
          children.add(_statusBox(context, '暂无主体明细权限，仅显示合计。'));
        }
      }
    }
    return _scaffold(
      context,
      onRefresh: _reload,
      header: _pageHeader(
        context,
        '业财对照',
        trailing: _dateIsland(context, '截至', _dateValue.isEmpty ? '今日' : _dateValue, _pickDate),
      ),
      children: children,
    );
  }

  // ── 汇总卡：重合图。大圆是数大的一边，小圆是数小的一边并内切其中；
  //    小圆 = 两本账都认的，露出的月牙 = 只有一边有的（月牙颜色 = 多在哪边）。──

  Widget _heroCard(BuildContext context, LhBfSummary s, LhBfRow t) {
    const key = '__TOTAL__';
    final open = _open.contains(key);
    final source = s.source == 'DAY' ? '当日落表' : '日终快照';
    final at = s.fetchedAt;
    final synced = at == null
        ? source
        : '$source · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final p = _kPairs[_kSummaryPairs[_heroPair]];
    final b = _bizVal(t, p);
    final f = _finVal(t, p);
    final ok = b != null && f != null && b > 0 && f > 0;
    final bizBig = ok && b >= f;
    final common = ok ? (b < f ? b : f) : null;
    final only = ok ? (b - f).abs() : null;
    final moonColor = bizBig ? _kPurple : _kFin;

    final stats = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('两本账都认的', style: _sans(context, size: 9.5, color: _kInk2)),
        const SizedBox(height: 3),
        _amount(context, lhBfWan(common), size: 16),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: _fg(context, moonColor), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(bizBig ? '只在业务账上的' : '只在财务账上的', style: _sans(context, size: 9.5, color: _kInk2)),
          ],
        ),
        const SizedBox(height: 3),
        _amount(context, lhBfWan(only), size: 13, color: ok ? (bizBig ? _kDeep : _kFin) : _kInk),
      ],
    );

    Widget side(String label, double? v, Color c, {bool end = false}) => Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: _fg(context, c), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: _sans(context, size: 9.5, color: _kInk2)),
          ],
        ),
        const SizedBox(height: 3),
        _amount(context, _valText(v, p), color: c),
      ],
    );

    return Container(
      decoration: _cardDeco(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHead(
                  context,
                  icon: Icons.account_balance_outlined,
                  title: '业财汇总',
                  chip: s.asOfDate.isEmpty ? null : lhBfShortDate(s.asOfDate),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(synced, style: _sans(context, size: 9.5, color: _kInk2)),
                      const SizedBox(width: 6),
                      _visButton(context, widget.service, 'business_finance', () => _showVisibility()),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _heroTabs(context, t),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Eclipse(biz: b, fin: f, size: 132, showLabel: true),
                    const SizedBox(width: 14),
                    Expanded(child: stats),
                  ],
                ),
                const SizedBox(height: 10),
                Container(height: 0.8, color: _ln(context, _kLine)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: side(p.bizLabel, b, _kPurple)),
                    Expanded(child: side(p.finLabel, f, _kFin, end: true)),
                  ],
                ),
              ],
            ),
          ),
          _footBar(
            context,
            title: '全部指标',
            text: '${s.rows.length} 个主体合计',
            open: open,
            onTap: () => _toggle(key),
          ),
          if (open) _pairGrid(context, t, key),
        ],
      ),
    );
  }

  /// 汇总卡顶部三项：资产 / 券池⇄预付 / 销售⇄回款，每项带重合比例。
  Widget _heroTabs(BuildContext context, LhBfRow t) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _bg(context, const Color(0xFFF1EFF7)), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          for (var k = 0; k < _kSummaryPairs.length; k++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _heroPair = k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: k == _heroPair ? _bg(context, Colors.white) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: k == _heroPair
                        ? [BoxShadow(color: _kDeep.withAlpha(36), blurRadius: 4, offset: const Offset(0, 1))]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        _kPairs[_kSummaryPairs[k]].short,
                        style: _sans(context, size: 11, weight: FontWeight.w700, color: k == _heroPair ? _kDeep : _kInk2),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _overlapText(_bizVal(t, _kPairs[_kSummaryPairs[k]]), _finVal(t, _kPairs[_kSummaryPairs[k]])),
                        style: _mono(context, size: 10, color: k == _heroPair ? _kDeep : _kInk2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 业务 − 财务 写成一道算式（不画条）：● 业务 9,755.58万  −  ● 财务 7,508.69万。
  /// 只有一侧的指标只写那一侧，另一侧写「无对应指标」。
  Widget _compareBars(BuildContext context, LhBfRow r, _BfPair p) {
    Widget side(String label, double? v, Color c, {bool end = false}) => Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: _fg(context, c), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: _sans(context, size: 9.5, weight: FontWeight.w600, color: _kInk2)),
          ],
        ),
        const SizedBox(height: 4),
        _amount(context, _valText(v, p), unit: p.rate ? '%' : '万', color: c, size: 14),
      ],
    );
    Widget none(String t, {bool end = false}) => Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(t, style: _sans(context, size: 10, color: _kMute)),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _ln(context, _kEdge), width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: p.biz != null ? side('业务', _bizVal(r, p), _kPurple) : none('无对应业务指标')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              p.paired ? '−' : '',
              style: LhTypography.sans(context: context, size: 16, weight: FontWeight.w300, color: _fg(context, _kMute), height: 1.2),
            ),
          ),
          Expanded(
            child: p.fin != null
                ? side('财务', _finVal(r, p), _kFin, end: true)
                : none('无对应财务指标', end: true),
          ),
        ],
      ),
    );
  }

  Widget _listHead(BuildContext context, LhBfSummary s) {
    final groups = _groups(s);
    int count(String g) => g == '全部' ? s.rows.length : s.rows.where((r) => r.group == g).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final g in groups) ...[
                _chip(context, '$g ${count(g)}', g == _group, () => setState(() => _group = g)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── 主体卡（同灯塔账本行）──

  Widget _subjectCard(BuildContext context, LhBfRow r, int index) {
    final key = r.subjectKey.isEmpty ? 'row$index' : r.subjectKey;
    final open = _open.contains(key);
    final sub = [
      if (r.ourEntityName.isNotEmpty) r.ourEntityName,
      if (r.counterpartyName.isNotEmpty) r.counterpartyName,
    ].join(' → ');
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Eclipse(biz: r.business['assetPrincipal'], fin: r.finance['assetPrincipal'], size: 34),
            const SizedBox(width: 8),
            _indexBadge(context, index),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 12, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            _tag(context, r.group, Colors.white, _groupColor(r.group), solid: true),
            const Spacer(),
            Text(
              _overlapText(r.business['assetPrincipal'], r.finance['assetPrincipal']),
              style: _mono(
                context,
                size: 12,
                weight: FontWeight.w600,
                color: _overlapColor(r.business['assetPrincipal'], r.finance['assetPrincipal']),
              ),
            ),
          ],
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, size: 9.5, color: _kMute, height: 1.35),
          ),
        ],
        if (r.subjectKey.isNotEmpty) ...[
          const SizedBox(height: 4),
          _visButton(context, widget.service, 'business_finance', () => _showVisibility(row: r), entity: r.subjectKey),
        ],
      ],
    );
    return Container(
      decoration: _cardDeco(context, radius: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final panels = _summaryPanels(context, r, key);
                    if (c.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [identity, const SizedBox(height: 8), panels],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 140, child: identity),
                        const SizedBox(width: 10),
                        Expanded(child: panels),
                      ],
                    );
                  },
                ),
                if (_explain == key && _kSummaryPairs.contains(_pair))
                  _explainBox(context, r, _pair, onClose: () => setState(() => _explain = null)),
              ],
            ),
          ),
          _footBar(
            context,
            title: '全部指标',
            text: '${_pairCount()} 项对照',
            open: open,
            onTap: () => _toggle(key),
          ),
          if (open) _pairGrid(context, r, key),
        ],
      ),
    );
  }

  /// 摘要：左业务（紫）、右财务（蓝），三排对照；选中排的财务格角标显示差额。
  Widget _summaryPanels(BuildContext context, LhBfRow r, String key) {
    final biz = <Widget>[];
    final fin = <Widget>[];
    for (final i in _kSummaryPairs) {
      final p = _kPairs[i];
      final on = _pair == i;
      final d = _pairDiff(r, p);
      biz.add(
        _cell(
          context,
          label: p.bizLabel,
          value: _valText(_bizVal(r, p), p),
          color: _kPurple,
          active: on,
          onTap: () => _tapPair(i, key),
        ),
      );
      fin.add(
        _cell(
          context,
          label: p.finLabel,
          value: _valText(_finVal(r, p), p),
          color: _kFin,
          active: on,
          badge: on ? '差 ${_signedWan(d)}' : null,
          badgeColor: _diffColor(d),
          onTap: () => _tapPair(i, key),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _panel(context, biz, title: '业务', titleColor: _kPurple)),
        const SizedBox(width: 6),
        Expanded(child: _panel(context, fin, tint: _kFin, title: '财务', titleColor: _kFin)),
      ],
    );
  }

  /// 展开：按「资产与余额 / 采购与发票 / 销售与返利 / 费用与利润 / 仅业务 / 仅财务」分组，
  /// 每排一张对比条（紫 = 业务、蓝 = 财务）；点哪排，哪排下方显示业财差额。
  Widget _pairGrid(BuildContext context, LhBfRow r, String key) {
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _fg(context, _kPurple), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('业务', style: _sans(context, size: 10, weight: FontWeight.w600, color: _kInk2)),
            const SizedBox(width: 10),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _fg(context, _kFin), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('财务', style: _sans(context, size: 10, weight: FontWeight.w600, color: _kInk2)),
          ],
        ),
      ),
    ];
    for (final sec in _kPairSections) {
      final color = Color(sec.$2);
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Container(width: 3, height: 12, decoration: BoxDecoration(color: _fg(context, color), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(sec.$1, style: _sans(context, size: 11, weight: FontWeight.w700)),
            ],
          ),
        ),
      );
      for (final i in sec.$4) {
        out.add(_pairRow(context, r, i, key));
      }
    }
    return Container(
      color: _bg(context, Colors.white),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out),
    );
  }

  Widget _pairRow(BuildContext context, LhBfRow r, int i, String key) {
    final p = _kPairs[i];
    final on = _pair == i;
    final d = _pairDiff(r, p);
    String? poolNote;
    if (p.pool) {
      String w(String k) => lhBfWan(r.business[k]);
      poolNote = '资金池 ${w('fundBalance')} · 库存券 ${w('inventoryBalance')} · 同步券 ${w('syncCouponBalance')}';
    }
    final where = '$key#grid';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapPair(i, where),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: _bg(context, on ? _kMist : _kNeutralPanel),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? _fg(context, _kPurple).withAlpha(90) : Colors.transparent, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, size: 11, weight: FontWeight.w700, color: on ? _kDeep : _kInk),
                  ),
                ),
                _kindTag(context, p.kind),
              ],
            ),
            const SizedBox(height: 6),
            _compareBars(context, r, p),
            if (poolNote != null) ...[
              const SizedBox(height: 3),
              Text(poolNote, style: _sans(context, size: 9.5, color: _kMute)),
            ],
            if (on && p.paired) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                decoration: BoxDecoration(
                  color: _fg(context, _diffColor(d)).withAlpha(22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text('业财差额', style: _sans(context, size: 10, weight: FontWeight.w700, color: _kInk2)),
                    const SizedBox(width: 8),
                    _amount(context, _signedWan(d), color: _diffColor(d), size: 12.5),
                    const Spacer(),
                    Icon(
                      _explain == where ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: _fg(context, _kPurple),
                    ),
                  ],
                ),
              ),
              if (_explain == where)
                _explainBox(context, r, i, onClose: () => setState(() => _explain = null)),
            ],
          ],
        ),
      ),
    );
  }

  // ── 解释框：资管算法 · 两边各是什么 · 差额常见来源 · 相关对照（用这一家的真实数）──

  Widget _explainBox(BuildContext context, LhBfRow r, int i, {required VoidCallback onClose}) {
    final p = _kPairs[i];
    final e = _kPairExplain[i];
    if (e == null) return const SizedBox.shrink();
    final b = _bizVal(r, p);
    final f = _finVal(r, p);
    final d = _pairDiff(r, p);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(t, style: _sans(context, size: 10.5, weight: FontWeight.w700, color: _kDeep)),
    );
    Widget para(String t) => Text(t, style: _sans(context, size: 11, color: _kInk, height: 1.6));
    Widget bullet(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 6),
            child: Container(width: 4, height: 4, decoration: BoxDecoration(color: _fg(context, _kPurple), shape: BoxShape.circle)),
          ),
          Expanded(child: para(t)),
        ],
      ),
    );
    Widget eqPart(String label, String value, Color c) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _sans(context, size: 9.5, color: _kInk2)),
        const SizedBox(height: 2),
        _amount(context, value, color: c, size: 13),
      ],
    );
    Widget op(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
      child: Text(t, style: LhTypography.sans(context: context, size: 14, weight: FontWeight.w300, color: _fg(context, _kInk2))),
    );

    final related = <Widget>[];
    if (p.pool) {
      related.add(
        _relatedLine(
          context,
          '券池构成',
          '资金池 ${lhBfWan(r.business['fundBalance'])} · 库存券 ${lhBfWan(r.business['inventoryBalance'])} · 同步券 ${lhBfWan(r.business['syncCouponBalance'])}',
          null,
        ),
      );
    }
    for (final j in e.related) {
      final q = _kPairs[j];
      final qd = _pairDiff(r, q);
      related.add(_relatedLine(context, q.title, '${_valText(_bizVal(r, q), q)} / ${_valText(_finVal(r, q), q)}', qd));
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _fg(context, _kPurple).withAlpha(80), width: 1),
        boxShadow: [BoxShadow(color: _kDeep.withAlpha(18), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.title, style: _sans(context, size: 12, weight: FontWeight.w700)),
              ),
              _tag(context, '资管口径', _kDeep, _kLavender),
              IconButton(
                tooltip: '收起',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 16, color: _fg(context, _kInk2)),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 2, right: 4),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(8)),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                eqPart(p.bizLabel, _valText(b, p), _kPurple),
                op('−'),
                eqPart(p.finLabel, _valText(f, p), _kFin),
                op('='),
                eqPart('业财差额', _signedWan(d), _diffColor(d)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('资管怎么算'),
                para(e.formula),
                label('两边各是什么'),
                bullet('业务：${e.biz}'),
                bullet('财务：${e.fin}'),
                label('差额常见来源'),
                for (final c in e.causes) bullet(c),
                if (related.isNotEmpty) ...[
                  label('这一家的相关对照'),
                  ...related,
                ],
                if (e.next.isNotEmpty) ...[
                  label('去哪核'),
                  para(e.next),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedLine(BuildContext context, String title, String values, double? diff) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _sans(context, size: 11, weight: FontWeight.w600)),
                Text(values, style: _mono(context, size: 10, color: _kInk2)),
              ],
            ),
          ),
          if (diff != null)
            Text('差 ${_signedWan(diff)}', style: _mono(context, size: 10.5, weight: FontWeight.w600, color: _diffColor(diff))),
        ],
      ),
    );
  }
}

/// 每一对的解释。formula 照资管 0.10 接口文档；causes 是常见来源（可能性，不是结论）。
class _PairExplain {
  const _PairExplain({
    required this.formula,
    required this.biz,
    required this.fin,
    required this.causes,
    this.related = const [],
    this.next = '',
  });

  final String formula;
  final String biz;
  final String fin;
  final List<String> causes;

  /// 一起看的其他对照（_kPairs 下标）。
  final List<int> related;
  final String next;
}

const _kPairExplain = <int, _PairExplain>{
  0: _PairExplain(
    formula: '业务资产 − 财务资产，截至当日余额。',
    biz: '资金池 + 库存券 + 同步券 + 应收返利 − 已返利 + 电子券销售额 − 销售回款。',
    fin: '预付款 + 销售未回 − 项目成本未付 + 监管户。',
    causes: [
      '两边公式不同：返利只在业务侧；项目成本未付、监管户只在财务侧。',
      '财务的销售未回含年初以前未结清的部分，业务侧从当年算起。',
      '券池与预付款的差额会整体带进资产差额。',
    ],
    related: [1, 4, 5],
    next: '先看券池 ⇄ 预付款和销售 ⇄ 回款两对，资产差额大多由这两对构成。',
  ),
  1: _PairExplain(
    formula: '（资金池 + 库存券 + 同步券）− 预付款余额，截至当日余额。',
    biz: '在供应商处尚未用掉的资金池，加上已买未卖的库存券和同步券。',
    fin: '已付给供应商、尚未冲减的预付款。',
    causes: [
      '预付款的冲减时点（采购、收票或核销）与业务扣减资金池的时点不同。',
      '已买未卖的库存券，在财务侧可能已不在预付款里。',
      '财务付款多于业务采购，多出的部分挂在预付款上。',
      '进项发票未入账，预付款迟迟不能冲减。',
    ],
    related: [2, 3],
    next: '向财务确认预付款按什么冲减；看采购 ⇄ 付款、发票 ⇄ 进项发票两对的差额是否能解释这里。',
  ),
  2: _PairExplain(
    formula: '电子券采购额 − 电子券采购付款，1 月 1 日起累计。',
    biz: '业务系统里向供应商下单采购电子券的金额。',
    fin: '财务实际付给供应商的采购款。',
    causes: [
      '预付在先、采购在后：钱已付，券还没买。',
      '账期付款：券已买，钱还没付。',
      '付款或采购记在了不同主体、不同年度。',
    ],
    related: [1, 3],
    next: '对照预付款余额：多付的部分通常会体现在预付款上。',
  ),
  3: _PairExplain(
    formula: '发票金额 − 进项发票，1 月 1 日起累计。',
    biz: '业务侧应取得的发票金额。',
    fin: '财务已入账的进项发票。',
    causes: [
      '发票未收到或未入账。',
      '进项发票整体为 0 时，多半是数据还没接入。',
      '开票时点与采购时点不同。',
    ],
    related: [2],
    next: '向财务确认进项发票的数据是否已接入灯塔。',
  ),
  4: _PairExplain(
    formula: '电子券销售额 − 销售回款，1 月 1 日起累计。',
    biz: '卖给渠道的电子券金额。',
    fin: '渠道实际打回来的款。',
    causes: [
      '渠道账期未到，或回款在途。',
      '部分回款，账单只收了一部分。',
      '财务回款里有年初以前销售的回款。',
    ],
    related: [0],
    next: '在「未结往来 · 渠道应收」看还没收回的账单和逾期。',
  ),
  5: _PairExplain(
    formula: '应收返利 − 已收返利，1 月 1 日起累计。',
    biz: '按业务结算应收的返利。',
    fin: '实际到账的返利。',
    causes: ['返利按业务结算计提，财务按到账记。', '返利尚未开票或未到账。'],
    next: '在「未结往来 · 供给应收」看应收返利的未结账单。',
  ),
  6: _PairExplain(
    formula: '平台服务费 − 已付平台服务费，1 月 1 日起累计。',
    biz: '按业务结算应付的平台服务费。',
    fin: '实际已付的平台服务费。',
    causes: ['账单未出或未付。', '付款记在不同主体。'],
  ),
  7: _PairExplain(
    formula: '返佣 − 已付返佣，1 月 1 日起累计。',
    biz: '按业务结算计提的返佣。',
    fin: '实际已付的返佣。',
    causes: ['返佣账单在途，尚未付款。', '一张账单分多次付款。'],
    next: '在「未结往来 · 渠道应付」看还没付的账单。',
  ),
  8: _PairExplain(
    formula: '支付手续费 − 已付支付手续费，1 月 1 日起累计。',
    biz: '按交易计提的支付通道手续费。',
    fin: '实际已付的手续费。',
    causes: ['通道按月结算，付款晚于计提。'],
  ),
  9: _PairExplain(
    formula: '利润 − 计提利润。',
    biz: '收入减成本，再减支付手续费。',
    fin: '计提利润（资管尚未提供）。',
    causes: ['资管没有给计提利润，这一对暂时没有差额。'],
  ),
};

/// 重合比例 = 小 ÷ 大（两边都为正才有意义），否则「—」。
double? _overlap(double? b, double? f) {
  if (b == null || f == null || b <= 0 || f <= 0) return null;
  return (b < f ? b : f) / (b > f ? b : f);
}

String _overlapText(double? b, double? f) {
  final x = _overlap(b, f);
  if (x == null) return '—';
  final pct = x * 100;
  if (pct >= 99.5 && x < 1) return '99%';
  return '${pct.round()}%';
}

Color _overlapColor(double? b, double? f) {
  final x = _overlap(b, f);
  if (x == null) return _kMute;
  if (x >= 0.95) return LhColors.pos;
  if (x < 0.6) return _kCopper;
  return _kInk;
}

/// 重合图：面积按金额。两边有一边 ≤ 0 时画一个虚线圈。
class _Eclipse extends StatelessWidget {
  const _Eclipse({required this.biz, required this.fin, required this.size, this.showLabel = false});

  final double? biz;
  final double? fin;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final x = _overlap(biz, fin);
    final painter = _EclipsePainter(
      biz: biz,
      fin: fin,
      bizColor: _fg(context, _kPurple),
      finColor: _fg(context, _kFin),
      paper: _bg(context, Colors.white),
      line: _ln(context, const Color(0xFFC9C4D6)),
    );
    Widget? label;
    if (showLabel) {
      double dx = 0;
      if (x != null) {
        final rBig = size / 2 - 1;
        final rSmall = rBig * _sqrt(x);
        dx = (biz! >= fin! ? 1 : -1) * (rBig - rSmall);
      }
      label = Transform.translate(
        offset: Offset(dx, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (x != null) Text('重合', style: _sans(context, size: 9.5, color: _kInk2, height: 1.1)),
            Text(
              x == null ? '—' : _overlapText(biz, fin),
              style: LhTypography.number(context: context, size: 15, color: _fg(context, x == null ? _kMute : _kInk)).copyWith(height: 1.1),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: painter,
        child: label == null ? null : Center(child: label),
      ),
    );
  }
}

double _sqrt(double v) {
  // 牛顿法，避免为一个开方引 dart:math。
  if (v <= 0) return 0;
  var g = v > 1 ? v : 1.0;
  for (var i = 0; i < 20; i++) {
    g = 0.5 * (g + v / g);
  }
  return g;
}

class _EclipsePainter extends CustomPainter {
  _EclipsePainter({
    required this.biz,
    required this.fin,
    required this.bizColor,
    required this.finColor,
    required this.paper,
    required this.line,
  });

  final double? biz;
  final double? fin;
  final Color bizColor;
  final Color finColor;
  final Color paper;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rBig = (size.shortestSide / 2) - 1;
    final x = _overlap(biz, fin);
    if (x == null) {
      final p = Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const dashes = 36;
      for (var i = 0; i < dashes; i += 2) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: rBig),
          i * 2 * 3.141592653589793 / dashes,
          2 * 3.141592653589793 / dashes,
          false,
          p,
        );
      }
      return;
    }
    final bizBig = biz! >= fin!;
    final rSmall = rBig * _sqrt(x);
    canvas.drawCircle(c, rBig, Paint()..color = bizBig ? bizColor : finColor);
    final sc = c + Offset((bizBig ? 1 : -1) * (rBig - rSmall), 0);
    canvas.drawCircle(sc, rSmall, Paint()..color = paper);
    canvas.drawCircle(
      sc,
      rSmall,
      Paint()
        ..color = bizBig ? finColor : bizColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide > 60 ? 1.6 : 1,
    );
  }

  @override
  bool shouldRepaint(covariant _EclipsePainter old) =>
      old.biz != biz ||
      old.fin != fin ||
      old.bizColor != bizColor ||
      old.finColor != finColor ||
      old.paper != paper ||
      old.line != line;
}

// ═════════════════════════════ 未结往来 ═════════════════════════════

const _kLedgerTabs = ['CHANNEL', 'SUPPLY', 'PREPAID', 'PAYABLE'];

class _TypeStat {
  _TypeStat(this.name);

  final String name;
  int groups = 0;
  int bills = 0;
  int overdueBills = 0;
  double diff = 0;
  double overdue = 0;
  String? earliestEnd;
}

class LighthouseLedgerPage extends StatefulWidget {
  const LighthouseLedgerPage({super.key, required this.service, required this.session, this.initial});

  final LighthouseService service;
  final AuthSession session;
  final LhLedger? initial;

  @override
  State<LighthouseLedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LighthouseLedgerPage> {
  static const int _pageSize = 30;

  LhLedger? _data;
  String? _error;
  bool _loading = false;
  DateTime? _asOf;
  String _code = 'CHANNEL';
  bool _overdueOnly = false;
  String? _billType;
  bool _showAll = false;

  /// 展开解释框的那张卡（'TOTAL' 或 分组 key）。
  String? _explainGroup;

  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    if (_data == null) {
      _loading = true;
      unawaited(_fetch());
    }
  }

  Future<void> _fetch() async {
    try {
      final data = await widget.service.fetchBillOutstanding(
        asOf: _asOf == null ? null : lhBfDateParam(_asOf!),
      );
      if (!mounted) return;
      setState(() {
        _data = LhLedger.fromJson(data);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _fetch();
  }

  Future<void> _pickAsOf() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf ?? today,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: today,
      helpText: '逾期统计日',
    );
    if (picked == null || !mounted) return;
    final d = DateTime(picked.year, picked.month, picked.day);
    setState(() => _asOf = d == today ? null : d);
    await _reload();
  }

  String get _asOfValue {
    if (_asOf != null) return lhBfShortDate(lhBfDateParam(_asOf!));
    final a = _data?.asOf ?? '';
    return a.isEmpty ? '今日' : lhBfShortDate(a);
  }

  void _pickDim(String code) {
    if (code == _code) return;
    setState(() {
      _code = code;
      _overdueOnly = false;
      _billType = null;
      _showAll = false;
      _explainGroup = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final children = <Widget>[];
    if (d == null) {
      children.add(_loading ? _loadingBox(context) : _statusBox(context, _error ?? '暂无数据', onRetry: _reload));
    } else if (d.restricted) {
      children.add(_statusBox(context, '暂无权限查看未结往来'));
    } else if (d.unavailable) {
      children.add(_statusBox(context, '资管接口未配置'));
    } else {
      if (_loading) {
        children
          ..add(const LinearProgressIndicator(minHeight: 2))
          ..add(const SizedBox(height: 8));
      }
      if (d.fixture) {
        children.add(
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _bg(context, _kCopperSoft), borderRadius: BorderRadius.circular(8)),
            child: Text('当前为样例数据，非资管实时结果。', style: _sans(context, size: 11, color: _kCopper)),
          ),
        );
      }
      if (_error != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('刷新失败：$_error', style: _sans(context, size: 11, color: LhColors.neg)),
          ),
        );
      }
      children
        ..add(_heroCard(context, d))
        ..add(const SizedBox(height: 10))
        ..add(_ledgerCard(context, d));
    }
    return _scaffold(
      context,
      onRefresh: _reload,
      header: _pageHeader(
        context,
        '未结往来',
        trailing: _dateIsland(context, '逾期统计日', _asOfValue, _pickAsOf),
      ),
      children: children,
    );
  }

  // ── 汇总：四个口径，同灯塔「产品汇总」两块面板 ──

  Widget _heroCard(BuildContext context, LhLedger d) {
    Widget cell(String code) {
      final m = _kDimMeta[code]!;
      final dim = d.dim(code);
      return _cell(
        context,
        label: m.title,
        value: dim == null ? '—' : lhBfWan(dim.diffAmount),
        color: (dim?.diffAmount ?? 0) < 0 ? LhColors.pos : _kInk,
        badge: dim == null ? null : '逾期 ${lhBfWan(dim.overdueAmount)}',
        badgeColor: _kCopper,
        active: code == _code,
        onTap: () => _pickDim(code),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(
            context,
            icon: Icons.swap_horiz_rounded,
            title: '未结汇总',
            chip: d.asOf.isEmpty ? null : lhBfShortDate(d.asOf),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_cutoffText(d), style: _sans(context, size: 9.5, color: _kInk2)),
                const SizedBox(width: 6),
                _visButton(
                  context,
                  widget.service,
                  'bills',
                  () => unawaited(
                    _openVisibility(
                      context,
                      service: widget.service,
                      session: widget.session,
                      module: 'bills',
                      title: '资管 · 未结往来',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _panel(context, [cell('CHANNEL'), cell('SUPPLY')], title: '应收', titleColor: _kCopper)),
              const SizedBox(width: 6),
              Expanded(child: _panel(context, [cell('PREPAID'), cell('PAYABLE')], tint: _kFin, title: '预收与应付', titleColor: _kFin)),
            ],
          ),
        ],
      ),
    );
  }

  // ── 口径 Tab + 列表（同灯塔「产品 / 供给方 / 渠道 / 人效」）──

  Widget _tabs(BuildContext context, LhLedger d) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _ln(context, _kLine), width: 0.8)),
      ),
      child: Row(
        children: [
          for (final code in _kLedgerTabs)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickDim(code),
                child: SizedBox(
                  height: 44,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _kDimMeta[code]!.title,
                        style: _sans(
                          context,
                          size: 13,
                          weight: code == _code ? FontWeight.w700 : FontWeight.w500,
                          color: code == _code ? _kDeep : _kInk2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 18,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: code == _code ? _fg(context, _kPurple) : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _flagFor(LhLedgerGroup g) {
    if (g.diffAmount.abs() < 0.0005) return _code == 'PAYABLE' ? '已结平' : null;
    if (g.diffAmount < 0) return _kDimMeta[_code]!.negLabel;
    return null;
  }

  String _range(LhLedgerGroup g) {
    final a = g.earliestEnd;
    final b = g.latestEnd;
    if (a == null && b == null) return '—';
    if (a == null || b == null || a == b) return lhBfShortDate(a ?? b!);
    final sameYear = a.length >= 4 && b.length >= 4 && a.substring(0, 4) == b.substring(0, 4);
    if (sameYear) return '${lhBfShortDate(a)}–${lhBfShortDate(b)}';
    return '${a.replaceAll('-', '.')}–${b.replaceAll('-', '.')}';
  }

  DateTime get _asOfDay => DateTime.tryParse(_data?.asOf ?? '') ?? DateUtils.dateOnly(DateTime.now());

  /// 汇总卡右上：统计日这天，账期截至哪天及以前的已逾期。
  String _cutoffText(LhLedger d) {
    final asOf = DateTime.tryParse(d.asOf);
    if (asOf == null) return '逾期：账期结束日后第 ${d.graceDays + 1} 天起';
    return '账期截至 ${_mdDate(_overdueCutoff(asOf, d.graceDays), asOf)} 及以前的已逾期';
  }

  /// 分组卡：账期截至范围 + 逾期日（最晚一张哪天起逾期；都过了就写已过逾期日）。
  String _endLine(LhLedgerGroup g) {
    final range = _range(g);
    final latest = DateTime.tryParse(g.latestEnd ?? g.earliestEnd ?? '');
    if (latest == null) return '账期截至 $range';
    final asOf = _asOfDay;
    final due = _overdueFrom(latest, _data?.graceDays ?? 15);
    if (!due.isAfter(asOf)) return '账期截至 $range · 均已过逾期日';
    final single = g.earliestEnd == null || g.latestEnd == null || g.earliestEnd == g.latestEnd;
    return '账期截至 $range · ${single ? '' : '最晚一张 '}${_mdDate(due, asOf)} 起逾期';
  }

  // ── 账单类型 · 风险矩阵：横轴逾期占比、纵轴未结差额（开方刻度）、圆大小 = 张数 ──

  List<_TypeStat> _typeStats(List<LhLedgerGroup> groups) {
    final map = <String, _TypeStat>{};
    for (final g in groups) {
      final t = map.putIfAbsent(g.typeLabel, () => _TypeStat(g.typeLabel));
      t.groups++;
      t.bills += g.billCount;
      t.overdueBills += g.overdueCount;
      t.diff += g.diffAmount;
      t.overdue += g.overdueAmount;
      final e = g.earliestEnd;
      if (e != null && (t.earliestEnd == null || e.compareTo(t.earliestEnd!) < 0)) t.earliestEnd = e;
    }
    return map.values.toList()..sort((a, b) => b.diff.compareTo(a.diff));
  }

  double _typeShare(_TypeStat t) => t.diff > 0.0005 ? (t.overdue / t.diff).clamp(0.0, 1.0).toDouble() : 0.0;

  /// 四个区：(名称, 是否重点)。金额以最大一类的 1/4 为界（开方刻度的中线），逾期以 50% 为界。
  (String, bool) _zoneOf(_TypeStat t, double maxDiff) {
    final hiAmt = maxDiff > 0 && t.diff > 0 && _sqrt(t.diff / maxDiff) >= 0.5;
    final hiDue = _typeShare(t) >= 0.5;
    if (hiAmt && hiDue) return ('重点催收', true);
    if (hiAmt) return ('金额大 · 多未到期', false);
    if (hiDue) return ('小额拖欠', false);
    return ('正常', false);
  }

  String _insight(List<_TypeStat> stats) {
    final pos = stats.fold<double>(0, (a, t) => t.diff > 0 ? a + t.diff : a);
    final od = stats.fold<double>(0, (a, t) => t.overdue > 0 ? a + t.overdue : a);
    if (pos <= 0) return '';
    final top = stats.take(3).fold<double>(0, (a, t) => t.diff > 0 ? a + t.diff : a);
    final parts = <String>['前 ${stats.length < 3 ? stats.length : 3} 类占未结差额 ${(top / pos * 100).round()}%'];
    if (od > 0) {
      final byOd = [...stats]..sort((a, b) => b.overdue.compareTo(a.overdue));
      final lead = byOd.where((t) => t.overdue > 0).take(2).toList();
      final leadSum = lead.fold<double>(0, (a, t) => a + t.overdue);
      parts.add('逾期 ${lhBfWan(od)} 万里 ${(leadSum / od * 100).round()}% 来自${lead.map((t) => t.name).join('和')}');
    }
    return '${parts.join('；')}。';
  }

  Widget _typeChart(BuildContext context, List<_TypeStat> stats, int grace) {
    final maxDiff = stats.fold<double>(0, (m, t) => t.diff > m ? t.diff : m);
    final maxBills = stats.fold<int>(1, (m, t) => t.bills > m ? t.bills : m);
    final sel = _billType;
    final asOf = _asOfDay;
    const due = Color(0xFFD08A3E);
    Color dotColor(_TypeStat t) {
      if (t.diff <= 0.0005) return LhColors.pos;
      return _zoneOf(t, maxDiff).$2 ? due : _kPurple;
    }

    void pick(String name) => setState(() {
      _billType = _billType == name ? null : name;
      _showAll = false;
    });

    final insight = _insight(stats);
    final selStat = sel == null ? null : stats.where((t) => t.name == sel).firstOrNull;

    Widget plot = LayoutBuilder(
      builder: (context, c) {
        const left = 36.0, top = 8.0, bottom = 22.0, right = 10.0, h = 196.0;
        final w = c.maxWidth;
        final pw = w - left - right;
        final ph = h - top - bottom;
        double yOf(double diff) => top + (1 - (maxDiff > 0 && diff > 0 ? _sqrt(diff / maxDiff) : 0)) * ph;
        final midY = top + ph / 2;
        final midX = left + pw / 2;
        Widget quad(double l, double t, double ww, double hh, Color col) =>
            Positioned(left: l, top: t, width: ww, height: hh, child: Container(color: _bg(context, col)));
        Widget label(String text, double l, double t, {Color color = _kInk2, FontWeight weight = FontWeight.w500}) =>
            Positioned(left: l, top: t, child: Text(text, style: _sans(context, size: 9.5, weight: weight, color: color)));
        Widget tick(String text, double l, double t, {TextAlign align = TextAlign.left, double width = 40}) => Positioned(
          left: l,
          top: t,
          width: width,
          child: Text(text, textAlign: align, style: _mono(context, size: 8.5, color: _kInk2)),
        );
        final dots = <Widget>[];
        for (var i = 0; i < stats.length; i++) {
          final t = stats[i];
          final on = sel == t.name;
          final r = 6 + 10 * _sqrt(t.bills / maxBills);
          // 圆心收在坐标区内，贴边的点不压到刻度和区名上。
          final x = (left + _typeShare(t) * pw).clamp(left + r, left + pw - r).toDouble();
          final y = (t.diff > 0 ? yOf(t.diff) : top + ph).clamp(top + r, top + ph - r).toDouble();
          final col = _fg(context, dotColor(t));
          dots.add(
            Positioned(
              left: x - r,
              top: y - r,
              width: 2 * r,
              height: 2 * r,
              child: Semantics(
                button: true,
                label: '${t.name}，未结 ${lhBfWan(t.diff)} 万，逾期占比 ${(_typeShare(t) * 100).round()}%',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => pick(t.name),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? col : col.withAlpha(52),
                      border: Border.all(color: on ? Colors.white : col, width: on ? 2 : 1.2),
                      boxShadow: on
                          ? [BoxShadow(color: col, spreadRadius: 1.5), BoxShadow(color: _kDeep.withAlpha(60), blurRadius: 8, offset: const Offset(0, 3))]
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${i + 1}',
                        style: _mono(context, size: 9, weight: FontWeight.w700, color: on ? Colors.white : dotColor(t)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        // 选中的点画在最上面。
        if (sel != null) {
          final idx = stats.indexWhere((t) => t.name == sel);
          if (idx >= 0) dots.add(dots.removeAt(idx));
        }
        return SizedBox(
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              quad(left, top, pw / 2, ph / 2, const Color(0xFFFBFAFE)),
              quad(midX, top, pw / 2, ph / 2, const Color(0xFFFBF1E7)),
              quad(midX, midY, pw / 2, ph / 2, const Color(0xFFFBFAFE)),
              Positioned(
                left: left,
                top: top,
                width: pw,
                height: ph,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: _ln(context, const Color(0xFFC9C4D6))),
                      bottom: BorderSide(color: _ln(context, const Color(0xFFC9C4D6))),
                    ),
                  ),
                ),
              ),
              Positioned(left: midX, top: top, width: 0.8, height: ph, child: Container(color: _ln(context, const Color(0xFFDCD5F3)))),
              Positioned(left: left, top: midY, width: pw, height: 0.8, child: Container(color: _ln(context, const Color(0xFFDCD5F3)))),
              label('重点催收', midX + 4, top + 3, color: const Color(0xFFA85A1E), weight: FontWeight.w700),
              label('金额大 · 多未到期', left + 4, top + 3),
              label('小额拖欠', midX + 4, top + ph - 15),
              label('正常', left + 4, top + ph - 15),
              tick(lhBfWan(maxDiff).split('.').first, 0, top - 5, align: TextAlign.right, width: left - 4),
              tick(lhBfWan(maxDiff / 4).split('.').first, 0, midY - 5, align: TextAlign.right, width: left - 4),
              tick('0', 0, top + ph - 6, align: TextAlign.right, width: left - 4),
              tick('0%', left - 4, top + ph + 4),
              tick('50%', midX - 10, top + ph + 4),
              tick('100%', left + pw - 22, top + ph + 4),
              ...dots,
            ],
          ),
        );
      },
    );

    Widget chip(String text, bool on, VoidCallback onTap, {Color? numColor, String? num}) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 28,
        padding: EdgeInsets.fromLTRB(num == null ? 12 : 6, 0, 10, 0),
        decoration: BoxDecoration(
          color: _bg(context, on ? _kLavender : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? _fg(context, _kPurple) : _ln(context, _kEdge), width: on ? 1 : 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (num != null) ...[
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _fg(context, numColor ?? _kPurple), shape: BoxShape.circle),
                child: Text(num, style: LhTypography.mono(context: context, size: 9, weight: FontWeight.w700, color: Colors.white, height: 1.0)),
              ),
              const SizedBox(width: 5),
            ],
            Text(text, style: _sans(context, size: 11, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? _kDeep : _kInk)),
          ],
        ),
      ),
    );

    Widget? detail;
    if (selStat != null) {
      final z = _zoneOf(selStat, maxDiff);
      final earliest = DateTime.tryParse(selStat.earliestEnd ?? '');
      final idx = stats.indexOf(selStat) + 1;
      Widget metric(String label, String value, {Color color = _kInk, String unit = '万'}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _sans(context, size: 9.5, color: _kInk2)),
            const SizedBox(height: 2),
            _amount(context, value, color: color, unit: unit),
          ],
        ),
      );
      detail = Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _bg(context, _kNeutralPanel), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _fg(context, dotColor(selStat)), shape: BoxShape.circle),
                  child: Text('$idx', style: LhTypography.mono(context: context, size: 9, weight: FontWeight.w700, color: Colors.white, height: 1.0)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(selStat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 12, weight: FontWeight.w700)),
                ),
                _tag(context, z.$1, z.$2 ? const Color(0xFFA85A1E) : _kDeep, z.$2 ? const Color(0xFFFBF1E7) : _kLavender),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                metric('未结差额', lhBfWan(selStat.diff), color: selStat.diff < -0.0005 ? LhColors.pos : _kInk),
                metric('其中逾期', selStat.overdue > 0 ? lhBfWan(selStat.overdue) : '0.00', color: const Color(0xFFA85A1E)),
                metric('逾期占比', '${(_typeShare(selStat) * 100).round()}', unit: '%'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                '${selStat.groups} 组 · ${selStat.bills} 张',
                if (earliest != null) '最早账期截至 ${_mdDate(earliest, asOf)}',
              ].join(' · '),
              style: _sans(context, size: 10, color: _kInk2),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(color: _bg(context, Colors.white), borderRadius: BorderRadius.circular(12), border: Border.all(color: _ln(context, _kEdge), width: 0.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('账单类型 · 风险矩阵', style: _sans(context, size: 12, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${stats.length} 类', style: _mono(context, size: 9.5, color: _kInk2)),
            ],
          ),
          if (insight.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(insight, style: _sans(context, size: 10.5, color: _kInk, height: 1.6)),
          ],
          const SizedBox(height: 8),
          plot,
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip('全部', sel == null, () => setState(() {
                  _billType = null;
                  _showAll = false;
                })),
                for (var i = 0; i < stats.length; i++) ...[
                  const SizedBox(width: 6),
                  chip(stats[i].name, sel == stats[i].name, () => pick(stats[i].name), num: '${i + 1}', numColor: dotColor(stats[i])),
                ],
              ],
            ),
          ),
          ?detail,
        ],
      ),
    );
  }

  Widget _ledgerCard(BuildContext context, LhLedger d) {
    final m = _kDimMeta[_code]!;
    final dim = d.dim(_code);
    final groups = dim?.groups ?? const <LhLedgerGroup>[];
    final stats = _typeStats(groups);
    final rows = groups
        .where((g) => !_overdueOnly || g.hasOverdue)
        .where((g) => _billType == null || g.typeLabel == _billType)
        .toList();
    final filtered = _overdueOnly || _billType != null;
    final shown = _showAll ? rows : rows.take(_pageSize).toList();

    final body = <Widget>[
      if (stats.isNotEmpty) ...[
        _typeChart(context, stats, d.graceDays),
        const SizedBox(height: 10),
      ],
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip(context, '全部 ${groups.length}', !_overdueOnly, () => setState(() {
              _overdueOnly = false;
              _showAll = false;
            })),
            const SizedBox(width: 6),
            _chip(context, '仅逾期 ${groups.where((g) => g.hasOverdue).length}', _overdueOnly, () => setState(() {
              _overdueOnly = true;
              _showAll = false;
            })),
            if (_billType != null) ...[
              const SizedBox(width: 6),
              _chip(context, '$_billType  ✕', true, () => setState(() {
                _billType = null;
                _showAll = false;
              })),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      _groupCard(context, m, null, 0, dim: dim),
    ];
    for (var i = 0; i < shown.length; i++) {
      body
        ..add(const SizedBox(height: 8))
        ..add(_groupCard(context, m, shown[i], i + 1));
    }
    if (rows.isEmpty) {
      body.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            filtered ? '当前筛选下无分组' : '暂无未结账单',
            textAlign: TextAlign.center,
            style: _sans(context, size: 11.5, color: _kMute),
          ),
        ),
      );
    }
    if (!_showAll && rows.length > _pageSize) {
      body.add(
        TextButton(
          onPressed: () => setState(() => _showAll = true),
          child: Text('显示其余 ${rows.length - _pageSize} 组', style: _sans(context, size: 11.5, weight: FontWeight.w600, color: _kPurple)),
        ),
      );
    }

    return Container(
      decoration: _cardDeco(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabs(context, d),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ],
      ),
    );
  }

  /// 一组一张卡（同灯塔账本行）。g 为 null = 合计卡（与资管底栏一致）。
  Widget _groupCard(BuildContext context, _DimMeta m, LhLedgerGroup? g, int index, {LhLedgerDim? dim}) {
    final isTotal = g == null;
    final diff = g == null ? dim?.diffAmount : g.diffAmount;
    final overdue = g == null ? dim?.overdueAmount : g.overdueAmount;
    final count = g == null ? dim?.billCount : g.billCount;
    final overdueCount = g == null ? dim?.overdueCount : g.overdueCount;
    final flag = g == null ? null : _flagFor(g);
    final hasOverdue = (overdue ?? 0).abs() >= 0.0005;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (!isTotal) ...[_indexBadge(context, index), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                g == null ? '合计' : g.label(m.code),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, size: 12, weight: FontWeight.w700, height: 1.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _tag(context, g == null ? '与资管底栏一致' : g.typeLabel, _kDeep, _kLavender),
            if (flag != null)
              _tag(context, flag, flag == '已结平' ? _kGrey : LhColors.pos, flag == '已结平' ? _kGreySoft : const Color(0xFFE8F1E4)),
          ],
        ),
        if (g != null) ...[
          const SizedBox(height: 5),
          Text(_endLine(g), style: _sans(context, size: 9.5, color: _kMute)),
        ],
      ],
    );

    final panels = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _panel(context, [
            _cell(
              context,
              label: '差额',
              value: diff == null ? '—' : lhBfWan(diff),
              color: (diff ?? 0) < -0.0005 ? LhColors.pos : _kInk,
            ),
            _cell(context, label: '账单张数', value: count == null ? '—' : '$count', unit: '张'),
          ]),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _panel(context, [
            _cell(
              context,
              label: '其中逾期',
              value: overdue == null ? '—' : (hasOverdue ? lhBfWan(overdue) : '0.00'),
              color: hasOverdue ? _kCopper : _kMute,
            ),
            _cell(context, label: '逾期张数', value: overdueCount == null ? '—' : '$overdueCount', unit: '张', color: hasOverdue ? _kCopper : _kInk),
          ], tint: _kCopper),
        ),
      ],
    );

    final gKey = g == null ? 'TOTAL' : '$index|${g.label(m.code)}|${g.typeLabel}';
    final open = _explainGroup == gKey;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _explainGroup = open ? null : gKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _bg(context, isTotal ? _kMist : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: open ? _fg(context, _kPurple).withAlpha(110) : _ln(context, _kEdge),
            width: open ? 1 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [identity, const SizedBox(height: 8), panels],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 168, child: identity),
                    const SizedBox(width: 10),
                    Expanded(child: panels),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(open ? '收起解读' : '解读', style: _sans(context, size: 10.5, weight: FontWeight.w600, color: _kPurple)),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 15, color: _fg(context, _kPurple)),
                ],
              ),
            ),
            if (open) _groupExplain(context, m, g, dim),
          ],
        ),
      ),
    );
  }

  // ── 解读框：全部按接口里这一组的数算，不写泛泛的口径说明 ──

  String _days(int n) => n <= 0 ? '当天' : '$n 天';

  Widget _groupExplain(BuildContext context, _DimMeta m, LhLedgerGroup? g, LhLedgerDim? dim) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final grace = d.graceDays;
    final asOf = _asOfDay;
    final cutoff = _overdueCutoff(asOf, grace);
    final lines = <(String, List<String>)>[];

    String w(double v) => lhBfWan(v.abs());
    final neg = m.negLabel;

    if (g == null) {
      // ── 合计卡：整个口径 ──
      if (dim == null) return const SizedBox.shrink();
      final groups = dim.groups;
      final pos = groups.where((x) => x.diffAmount > 0.0005).toList();
      final negs = groups.where((x) => x.diffAmount < -0.0005).toList();
      final share = dim.overdueShare;
      final what = <String>[
        '${m.title}共 ${groups.length} 组、${dim.billCount} 张账单，未结差额 ${lhBfWan(dim.diffAmount)} 万，与资管「${m.tab}」底栏一致。',
        if (negs.isNotEmpty)
          '其中 ${pos.length} 组尚有未结 ${w(pos.fold<double>(0, (a, x) => a + x.diffAmount))} 万，${negs.length} 组为$neg ${w(negs.fold<double>(0, (a, x) => a + x.diffAmount))} 万，两者相抵后为合计。',
      ];
      lines.add(('这一口径', what));
      lines.add((
        '逾期',
        [
          '统计日 ${_mdDate(asOf, asOf)}：账期截至 ${_mdDate(cutoff, asOf)} 及以前、仍有差额的账单算逾期。',
          '已逾期 ${lhBfWan(dim.overdueAmount)} 万、${dim.overdueCount} 张${share == null ? '' : '，占未结差额 ${(share * 100).round()}%'}；'
              '未逾期 ${lhBfWan(dim.diffAmount - dim.overdueAmount)} 万、${dim.billCount - dim.overdueCount} 张。',
        ],
      ));
      if (pos.isNotEmpty) {
        final top = [...pos]..sort((a, b) => b.diffAmount.compareTo(a.diffAmount));
        final t3 = top.take(3).toList();
        final sum3 = t3.fold<double>(0, (a, x) => a + x.diffAmount);
        final posSum = pos.fold<double>(0, (a, x) => a + x.diffAmount);
        lines.add((
          '集中度',
          [
            '前 ${t3.length} 组占未结 ${(sum3 / posSum * 100).round()}%：${t3.map((x) => '${x.label(m.code)}（${x.typeLabel}）${lhBfWan(x.diffAmount)} 万').join('；')}。',
          ],
        ));
        final allDue = groups.where((x) => x.billCount > 0 && x.overdueCount == x.billCount && x.diffAmount > 0.0005).length;
        if (allDue > 0) lines.last.$2.add('有 $allDue 组的账单已全部逾期。');
      }
    } else {
      // ── 分组卡：这一组 ──
      final earliest = DateTime.tryParse(g.earliestEnd ?? '');
      final latest = DateTime.tryParse(g.latestEnd ?? '');
      final what = <String>[
        '${g.label(m.code)} 的「${g.typeLabel}」账单共 ${g.billCount} 张'
            '${earliest == null ? '' : '，账期截至 ${_range(g)}'}。',
      ];
      if (g.diffAmount > 0.0005) {
        what.add('目前还有 ${lhBfWan(g.diffAmount)} 万未结'
            '${g.billCount > 0 ? '，平均每张 ${lhBfWan(g.diffAmount / g.billCount)} 万' : ''}。');
      } else if (g.diffAmount < -0.0005) {
        what.add('差额为负：这一组整体$neg ${w(g.diffAmount)} 万。');
      } else {
        what.add('差额为 0：这一组已结平。');
      }
      if (dim != null && dim.diffAmount > 0.0005 && g.diffAmount > 0.0005) {
        what.add('占${m.title}未结差额的 ${(g.diffAmount / dim.diffAmount * 100).toStringAsFixed(1)}%。');
      }
      lines.add(('这一组', what));

      final due = <String>[];
      final notDue = g.diffAmount - g.overdueAmount;
      if (g.hasOverdue) {
        if (g.overdueAmount > 0) {
          due.add('已逾期 ${lhBfWan(g.overdueAmount)} 万、${g.overdueCount} / ${g.billCount} 张'
              '${g.diffAmount > 0.0005 ? '，占这一组未结的 ${(g.overdueAmount / g.diffAmount * 100).clamp(0, 999).round()}%' : ''}。');
        } else {
          due.add('逾期部分为负：已逾期的 ${g.overdueCount} 张账单合计$neg ${w(g.overdueAmount)} 万。');
        }
        if (notDue.abs() >= 0.0005) {
          due.add(notDue > 0
              ? '未逾期的账单仍有 ${lhBfWan(notDue)} 万未结。'
              : '未逾期的账单合计$neg ${w(notDue)} 万。');
        }
        if (g.overdueAmount > g.diffAmount + 0.0005 && g.diffAmount > 0.0005) {
          due.add('逾期金额大于差额，说明未逾期的账单里有$neg抵减。');
        }
      } else {
        due.add('暂无逾期金额。');
      }
      if (g.billCount > 0 && g.overdueCount == g.billCount && g.diffAmount > 0.0005) due.add('这一组的账单已全部逾期。');
      if (earliest != null) {
        final firstDue = _overdueFrom(earliest, grace);
        if (!firstDue.isAfter(asOf)) {
          due.add('最早一张账期截至 ${_mdDate(earliest, asOf)}，${_mdDate(firstDue, asOf)} 起逾期，至今已逾期 ${_days(asOf.difference(firstDue).inDays + 1)}。');
        } else {
          due.add('最早一张账期截至 ${_mdDate(earliest, asOf)}，${_mdDate(firstDue, asOf)} 起逾期。');
        }
      }
      if (latest != null && earliest != null && latest != earliest) {
        final lastDue = _overdueFrom(latest, grace);
        due.add(lastDue.isAfter(asOf)
            ? '最晚一张账期截至 ${_mdDate(latest, asOf)}，还有 ${_days(lastDue.difference(asOf).inDays)} 到逾期日（${_mdDate(lastDue, asOf)}）。'
            : '最晚一张账期截至 ${_mdDate(latest, asOf)}，也已过逾期日。');
      }
      lines.add(('逾期', due));
    }

    final next = switch (m.code) {
      'CHANNEL' => '对照渠道回款流水，确认未结账单是否已回款未核销。',
      'SUPPLY' => '对照供应商返利到账情况，确认应收返利是否已结算。',
      'PREPAID' => '确认预收款对应的供货是否已完成、账单是否已出。',
      _ => '对照付款记录，确认未付账单的付款计划。',
    };
    lines.add(('建议核对', [next]));

    Widget para(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 6),
            child: Container(width: 4, height: 4, decoration: BoxDecoration(color: _fg(context, _kPurple), shape: BoxShape.circle)),
          ),
          Expanded(child: Text(t, style: _sans(context, size: 11, color: _kInk, height: 1.6))),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _fg(context, _kPurple).withAlpha(70), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (title, items) in lines) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(title, style: _sans(context, size: 10.5, weight: FontWeight.w700, color: _kDeep)),
            ),
            for (final t in items) para(t),
          ],
        ],
      ),
    );
  }
}
