import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../core/http/session_http.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../lighthouse/lighthouse_hero_metric.dart'
    show lighthouseHeroShellMarginH, lighthouseMainPageBg;
import '../lighthouse/lighthouse_service.dart';
import '../proposal_intake/native_proposal_intake_page.dart';
import '../proposal_intake/proposal_intake_models.dart';
import '../proposal_intake/proposal_intake_service.dart';
import '../proposal_intake/proposal_list_card.dart';
import '../proposal_intake/proposal_remote_finance.dart';
import '../tasks/native_task_detail_page.dart';
import '../tasks/native_task_home_pane.dart';
import '../tasks/task_api.dart';
import '../tasks/task_models.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/approval_detail_dialog.dart';
import '../xflow/xflow_service.dart';

// ════════════════════════════════════════════════════════════════════════
// 「我的」v3（2026-10-29 · 原型 v3 落地）
//
//   顶栏：我的 + 像素沙丘 + 身份行；
//   营收目标：半圆仪表（第一责任深紫 / 第二责任浅紫）+ 我相关提案数据池；
//   审批：待我审 / 待办理 / 我发起 / 抄送我 四格；
//   我的提案：已完成 / 进行中 / 待我处理 三段，行可展开；右下角宫格打开「更多」。
//
//   数据：
//     · 提案列表走 /proposal-intakes（related=1 我相关、不带 related 全公司、actionable=1 待我处理）；
//       全公司视角由组织用户「我的看全公司」控制；
//     · 数据池走 /proposal-intakes/{id}/cost-collection，只算已通过审批（total），审批中的不进合计；
//     · 收入 = 已通过发票的不含税金额（2026-10-29 起收据改算周转资金；发票正式进收入前先这样过渡），
//       全公司看板读 /approvals/cost-summary 的 invoice.approvedNet；
//     · 营收目标后端还没有（许总：下一步研发任务体系），先显示「待设定」，不放假数。
// ════════════════════════════════════════════════════════════════════════

/// v3 色板：底色直接用灯塔主页的淡灰紫，线和分段底也走冷紫灰；卡片不描边，改淡阴影。
abstract final class MinePalette {
  static const page = lighthouseMainPageBg; // #F3F1F7，跟灯塔主页同一个底
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2421);
  static const ink2 = Color(0xFF5A5C56);
  static const night = Color(0xFF2B2160);
  static const purple = Color(0xFF5B3FB8);
  static const purpleDeep = Color(0xFF45309A);
  static const purpleSoft = Color(0xFFF0ECF6);
  static const lavender = Color(0xFFB9A8EC);
  static const wash = Color(0xFFF8F6FC);
  static const washLine = Color(0xFFEEE9F7);
  static const washBorder = Color(0xFFE4DDF3);
  static const line = Color(0xFFECE8F3);
  static const track = Color(0xFFE7E3F0);
  static const copper = Color(0xFF8A5D1C);
  static const copperMid = Color(0xFFB07A2B);
  static const copperSoft = Color(0xFFFBF3E4);
  static const revenue = Color(0xFFC2453A);
  static const steel = Color(0xFF2D5878);
  static const steelSoft = Color(0xFFE9F0F5);

  // 数据池五类（与提案内「成本归集」同色）。
  static const project = Color(0xFF7B5CD8);
  static const business = Color(0xFF3B6E96);
  static const operating = Color(0xFFB07A2B);
  static const tax = Color(0xFF2F5D62);
  static const working = Color(0xFFCFC6EC);
}

const _tnum = [FontFeature.tabularFigures()];

/// 左右边距和灯塔主页同一条左沿（Hero / 账本卡都是 22）。
const double kMinePageGutter = lighthouseHeroShellMarginH;

Color _r(
  BuildContext context,
  Color light, [
  DunesColorRole role = DunesColorRole.foreground,
]) => DunesColors.resolve(context, light, role: role);

BoxDecoration _cardDecoration(BuildContext context, {double radius = 24}) {
  return BoxDecoration(
    color: _r(context, MinePalette.card, DunesColorRole.surface),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF1F2421).withValues(alpha: .04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: const Color(0xFF2B2160).withValues(alpha: .06),
        blurRadius: 30,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

String _groupInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

/// 元 → 万，按量级给小数位。
String _wan(double yuan) {
  final w = yuan / 10000;
  if (w.abs() >= 100) return _groupInt(w.round());
  if (w.abs() >= 1) return w.toStringAsFixed(1);
  if (w == 0) return '0';
  return w.toStringAsFixed(2);
}

String _monthDay(String raw) {
  final d = DateTime.tryParse(raw.trim());
  if (d != null) {
    final local = d.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  return m == null ? '' : '${m[2]}-${m[3]}';
}

// ── 顶栏 ──────────────────────────────────────────────────────────────────

/// 像素沙丘：和灯塔的像素灯塔同一种画法，画的是「沙丘」。
class MinePixelDunes extends StatelessWidget {
  const MinePixelDunes({super.key, this.width = 112});

  final double width;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      width: width,
      height: width * 34 / 112,
      child: CustomPaint(painter: _PixelDunesPainter(brightness)),
    );
  }
}

class _PixelDunesPainter extends CustomPainter {
  _PixelDunesPainter(this.brightness);

  final Brightness brightness;

  static const _rects = <(double, double, double, double, Color)>[
    (92, 2, 8, 4, Color(0xFFE8C98F)),
    (88, 6, 16, 4, Color(0xFFE8C98F)),
    (92, 10, 8, 4, Color(0xFFE8C98F)),
    (8, 10, 12, 2, Color(0xFFE2DAF4)),
    (40, 6, 16, 2, Color(0xFFE2DAF4)),
    (12, 18, 16, 4, Color(0xFFE2DAF4)),
    (4, 22, 36, 4, Color(0xFFE2DAF4)),
    (0, 26, 52, 4, Color(0xFFE2DAF4)),
    (56, 14, 12, 4, Color(0xFFA994E6)),
    (48, 18, 28, 4, Color(0xFFA994E6)),
    (36, 22, 52, 4, Color(0xFF8D74E0)),
    (24, 26, 80, 4, Color(0xFF7B5CD8)),
    (0, 30, 112, 4, Color(0xFF3D2E7C)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 112;
    final paint = Paint()..isAntiAlias = false;
    for (final (x, y, w, h, color) in _rects) {
      paint.color = DunesColors.forBrightness(brightness, color);
      canvas.drawRect(Rect.fromLTWH(x * s, y * s, w * s, h * s), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelDunesPainter old) =>
      old.brightness != brightness;
}

/// 顶栏：「我的」+ 像素沙丘 + 右侧操作；下一行头像、姓名、部门岗位、本月。
class MineHomeHeader extends StatelessWidget {
  const MineHomeHeader({
    super.key,
    required this.avatar,
    required this.name,
    required this.subtitle,
    this.actions = const [],
    this.month,
    this.onPickMonth,
    this.onCurrentMonth,
  });

  final Widget avatar;
  final String name;
  final String subtitle;
  final List<Widget> actions;

  /// 选中的月份；null 或当月 = 「本月」。
  final DateTime? month;

  /// 点月份：弹月份选择。
  final VoidCallback? onPickMonth;

  /// 点「本月」：回到当月。
  final VoidCallback? onCurrentMonth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final selected = month ?? DateTime(now.year, now.month);
    final isCurrent =
        selected.year == now.year && selected.month == now.month;
    final monthLabel = selected.year == now.year
        ? '${selected.month}月'
        : '${selected.year % 100}年${selected.month}月';
    Widget segment({
      required String label,
      required bool on,
      required VoidCallback? onTap,
      bool picker = false,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          padding: EdgeInsets.only(left: 12, right: picker ? 8 : 12),
          alignment: Alignment.center,
          decoration: on
              ? BoxDecoration(
                  color: _r(context, MinePalette.purple),
                  borderRadius: BorderRadius.circular(999),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tnum,
                  color: on ? Colors.white : _r(context, MinePalette.night),
                ),
              ),
              if (picker) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: on ? Colors.white : _r(context, MinePalette.night),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kMinePageGutter,
        18,
        kMinePageGutter,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '我的',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  height: 1,
                  color: _r(context, MinePalette.ink),
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MinePixelDunes(),
                  ),
                ),
              ),
              ...actions,
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _r(context, MinePalette.ink),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _r(context, MinePalette.ink2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: _cardDecoration(context, radius: 999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      segment(
                        label: '本月',
                        on: isCurrent,
                        onTap: isCurrent ? null : onCurrentMonth,
                      ),
                      segment(
                        label: monthLabel,
                        on: !isCurrent,
                        onTap: onPickMonth,
                        picker: true,
                      ),
                    ],
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

/// 顶栏右侧的「工作台」入口。窄屏时沙丘图会让位，这颗按钮保持原大。
class MineWorkbenchChip extends StatelessWidget {
  const MineWorkbenchChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _r(context, MinePalette.purple);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: '工作台',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Ink(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _r(context, MinePalette.purpleSoft, DunesColorRole.surface),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.apps_rounded, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    '工作台',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏右侧的圆形按钮（扫一扫、更多）。
class MineRoundAction extends StatelessWidget {
  const MineRoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Ink(
              width: 40,
              height: 40,
              decoration: _cardDecoration(context, radius: 999),
              child: Icon(icon, size: 19, color: _r(context, MinePalette.night)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 更多 ──────────────────────────────────────────────────────────────────

class MineCreateFab extends StatelessWidget {
  const MineCreateFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '更多',
      child: Material(
        color: _r(context, MinePalette.night),
        borderRadius: BorderRadius.circular(19),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2B2160).withValues(alpha: .32),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 更多面板：提案、审批与常用办公入口。PC 不放工作台。
Future<void> showMineCreateSheet(
  BuildContext context, {
  required VoidCallback onSales,
  required VoidCallback onPurchase,
  required VoidCallback onApproval,
  required VoidCallback onMeeting,
  required VoidCallback onKnowledge,
  VoidCallback? onWorkbench,
  bool showProposals = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFF1F2421).withValues(alpha: .36),
    builder: (ctx) {
      Widget option({
        required IconData icon,
        required List<Color> iconGradient,
        required Color bg,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
        final gradient = iconGradient
            .map((color) => DunesColors.resolve(ctx, color))
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _r(ctx, bg, DunesColorRole.surface),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.of(ctx).pop();
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: gradient.first.withValues(alpha: .22),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: _r(ctx, MinePalette.ink),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: _r(ctx, MinePalette.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: _r(ctx, MinePalette.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // 默认底栏最高只有屏高的 9/16，六项会 BOTTOM OVERFLOW。
      // 放开高度后仍限制在可视区域里，矮屏或大字号改为内部滚动。
      final media = MediaQuery.of(ctx);
      final maxHeight = media.size.height - media.padding.top - 24;
      // isScrollControlled 时子组件会撑满路由。空白区单独接点击，点面板外即收起。
      return Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ),
          ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: _r(ctx, MinePalette.card, DunesColorRole.surface),
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                18 + media.viewPadding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: _r(
                          ctx,
                          const Color(0xFFDCD6E8),
                          DunesColorRole.border,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      '更多',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _r(ctx, MinePalette.ink),
                      ),
                    ),
                  ),
                  if (onWorkbench != null)
                    option(
                      icon: Icons.apps_rounded,
                      iconGradient: const [
                        Color(0xFF6366F1),
                        Color(0xFF4338CA),
                      ],
                      bg: MinePalette.wash,
                      title: '工作台',
                      subtitle: '打开任务与协作工作台',
                      onTap: onWorkbench,
                    ),
                  if (showProposals) ...[
                    option(
                      icon: Icons.request_quote_outlined,
                      iconGradient: const [
                        Color(0xFF0EA5E9),
                        Color(0xFF0369A1),
                      ],
                      bg: MinePalette.wash,
                      title: '销售提案',
                      subtitle: '完成后在提案内发起业务审批',
                      onTap: onSales,
                    ),
                    option(
                      icon: Icons.shopping_bag_outlined,
                      iconGradient: const [
                        Color(0xFFF59E0B),
                        Color(0xFFB45309),
                      ],
                      bg: MinePalette.wash,
                      title: '采购提案',
                      subtitle: '完成后在提案内发起业务审批',
                      onTap: onPurchase,
                    ),
                  ],
                  option(
                    icon: Icons.add_task_rounded,
                    iconGradient: const [
                      Color(0xFF7C5CE6),
                      Color(0xFF552D8E),
                    ],
                    bg: MinePalette.page,
                    title: '审批',
                    subtitle: '进入后选择业务审批或非业务审批',
                    onTap: onApproval,
                  ),
                  option(
                    icon: Icons.article_rounded,
                    iconGradient: const [
                      Color(0xFF3880FF),
                      Color(0xFF1E40AF),
                    ],
                    bg: MinePalette.wash,
                    title: '会议纪要',
                    subtitle: '录制、上传并查看 AI 会议纪要',
                    onTap: onMeeting,
                  ),
                  option(
                    icon: Icons.auto_stories_rounded,
                    iconGradient: const [
                      Color(0xFF10B981),
                      Color(0xFF047857),
                    ],
                    bg: MinePalette.wash,
                    title: '企业知识库',
                    subtitle: '查看组织文档与知识沉淀',
                    onTap: onKnowledge,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Text(
                      '付款、开票、保证金等业务审批，请进入对应提案发起。',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: _r(ctx, MinePalette.ink2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
          ],
        );
    },
  );
}

// ── 主体 ──────────────────────────────────────────────────────────────────

/// 审批四格的数字，来自 /workbench/my-stats。
class MineApprovalCounts {
  const MineApprovalCounts({
    this.pendingForMe = 0,
    this.pendingTodo = 0,
    this.initiatedPending = 0,
    this.initiatedTotal = 0,
    this.cc = 0,
    this.rejected = 0,
    this.pendingInitiate = 0,
  });

  final int pendingForMe;
  final int pendingTodo;
  final int initiatedPending;
  final int initiatedTotal;
  final int cc;
  final int rejected;
  final int pendingInitiate;

  int get todoTotal => pendingForMe + pendingTodo + rejected + pendingInitiate;
}

/// 一个提案的数据池（只算已通过的审批）。金额单位：元。
class _MinePool {
  double project = 0;
  double business = 0;
  double operating = 0;
  double tax = 0;
  double working = 0;
  double revenue = 0;
  int approvals = 0;

  /// 本月开票审批：已通过、审批中（元）。全公司营收达成用。
  double invoicedMonth = 0;
  double invoicingMonth = 0;

  double get costs => project + business + operating + tax;
  double get bandTotal => costs + working;

  void add(_MinePool other) {
    project += other.project;
    business += other.business;
    operating += other.operating;
    tax += other.tax;
    working += other.working;
    revenue += other.revenue;
    approvals += other.approvals;
    invoicedMonth += other.invoicedMonth;
    invoicingMonth += other.invoicingMonth;
  }

  List<(Color, double)> get segments => [
    (MinePalette.project, project),
    (MinePalette.business, business),
    (MinePalette.operating, operating),
    (MinePalette.tax, tax),
    (MinePalette.working, working),
  ];

  static const _kInvoiceTemplateKey = 'finance-invoice-request';

  /// 发票含税金额减税额；没填税率（无 taxAmount）按原金额。
  static double _invoiceNet(Map raw) {
    final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
    final tax = (raw['taxAmount'] as num?)?.toDouble() ?? 0;
    return amount - tax;
  }

  static _MinePool parse(Map<String, dynamic> data) {
    final pool = _MinePool();
    final now = DateTime.now();
    final invoices = data['invoices'];
    if (invoices is List) {
      for (final raw in invoices) {
        if (raw is! Map) continue;
        if ('${raw['templateKey'] ?? ''}' != _kInvoiceTemplateKey) continue;
        // 收入：已通过发票的不含税金额（累计，不分月）。收据算周转资金，不进收入。
        if ('${raw['status'] ?? ''}'.trim().toUpperCase() == 'APPROVED') {
          pool.revenue += _invoiceNet(raw);
        }
        final created = DateTime.tryParse(
          '${raw['createdAt'] ?? ''}',
        )?.toLocal();
        final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
        final status = '${raw['status'] ?? ''}'.trim().toUpperCase();
        if (created == null ||
            created.year != now.year ||
            created.month != now.month) {
          continue;
        }
        if (status == 'APPROVED') {
          pool.invoicedMonth += amount;
        } else if (status != 'REJECTED') {
          pool.invoicingMonth += amount;
        }
      }
    }
    final buckets = data['buckets'];
    if (buckets is! List) return pool;
    for (final raw in buckets) {
      if (raw is! Map) continue;
      final total = (raw['total'] as num?)?.toDouble() ?? 0;
      pool.approvals += (raw['count'] as num?)?.toInt() ?? 0;
      switch ('${raw['bucket'] ?? ''}') {
        case 'projectCost':
          pool.project += total;
        case 'businessCost':
          pool.business += total;
        case 'operatingCost':
          pool.operating += total;
        case 'taxCost':
          pool.tax += total;
        case 'workingCapital':
          pool.working += total;
        case 'revenue':
          pool.revenue += total;
        case 'revenueOffset':
          pool.revenue -= total;
      }
    }
    return pool;
  }
}

class _MineCostApproval {
  const _MineCostApproval({
    required this.title,
    required this.businessType,
    required this.businessId,
    required this.templateKey,
    required this.category,
    required this.status,
    required this.amount,
    required this.occurredAt,
    this.initiatorName = '',
  });

  final String title;
  final String businessType;
  final int businessId;
  final String templateKey;
  final String category;
  final String status;
  final double amount;
  final DateTime? occurredAt;
  final String initiatorName;

  bool get isBusiness => category == 'biz';
  bool get isApproved => status == 'APPROVED';

  factory _MineCostApproval.fromMap(Map raw) => _MineCostApproval(
    title: '${raw['title'] ?? ''}'.trim(),
    businessType: '${raw['businessType'] ?? ''}'.trim(),
    businessId: (raw['businessId'] as num?)?.toInt() ?? 0,
    templateKey: '${raw['templateKey'] ?? ''}'.trim(),
    category: '${raw['category'] ?? ''}'.trim(),
    status: '${raw['status'] ?? ''}'.trim().toUpperCase(),
    amount: (raw['amount'] as num?)?.toDouble() ?? 0,
    occurredAt: DateTime.tryParse('${raw['occurredAt'] ?? ''}')?.toLocal(),
    initiatorName: '${raw['initiatorName'] ?? raw['submitterName'] ?? ''}'.trim(),
  );
}

/// 全公司审批归集：/approvals/cost-summary 的返回（金额单位：元）。
class _MineSummary {
  _MineSummary({
    required this.pool,
    this.bucketItems = const {},
    this.invoiceApproved = 0,
    this.invoicePending = 0,
    this.unclassifiedCount = 0,
    this.unclassifiedTotal = 0,
    this.missingAmount = 0,
  });

  final _MinePool pool;
  final Map<String, List<_MineCostApproval>> bucketItems;
  final double invoiceApproved;
  final double invoicePending;
  final int unclassifiedCount;
  final double unclassifiedTotal;
  final int missingAmount;

  static _MineSummary parse(Map<String, dynamic> data) {
    final pool = _MinePool.parse(data);
    final bucketItems = <String, List<_MineCostApproval>>{};
    final buckets = data['buckets'];
    if (buckets is List) {
      for (final raw in buckets) {
        if (raw is! Map) continue;
        final key = '${raw['bucket'] ?? ''}';
        final items = raw['items'];
        bucketItems[key] = items is List
            ? items
                  .whereType<Map>()
                  .map(_MineCostApproval.fromMap)
                  .where((item) => item.isApproved)
                  .toList(growable: false)
            : const [];
      }
    }
    final approvalCount = (data['approvalCount'] as num?)?.toInt();
    if (approvalCount != null) pool.approvals = approvalCount;
    final invoice = data['invoice'];
    final unclassified = data['unclassified'];
    double read(Object? map, String key) =>
        map is Map ? ((map[key] as num?)?.toDouble() ?? 0) : 0;
    // 收入：已通过发票的不含税金额。旧后端没有 approvedNet 时退回含税金额。
    if (invoice is Map) {
      pool.revenue += invoice['approvedNet'] is num
          ? read(invoice, 'approvedNet')
          : read(invoice, 'approved');
    }
    return _MineSummary(
      pool: pool,
      bucketItems: bucketItems,
      invoiceApproved: read(invoice, 'approved'),
      invoicePending: read(invoice, 'pending'),
      unclassifiedCount: unclassified is Map
          ? ((unclassified['count'] as num?)?.toInt() ?? 0)
          : 0,
      unclassifiedTotal: read(unclassified, 'total'),
      missingAmount: (data['missingAmount'] as num?)?.toInt() ?? 0,
    );
  }
}

enum _MineTab { done, doing, todo }

enum _MineTaskTab { doing, pending, done }

class MineHomeBody extends StatefulWidget {
  const MineHomeBody({
    super.key,
    required this.session,
    required this.counts,
    required this.onOpenPendingApprovals,
    required this.onOpenTodoApprovals,
    required this.onOpenInitiated,
    required this.onOpenCc,
    required this.onOpenRejected,
    required this.onOpenPendingInitiate,
    required this.onOpenLighthouse,
    required this.onOpenProposalList,
    this.onOpenProposalDetail,
    this.showProposals = true,
    this.companyView = false,
    this.refreshToken = 0,
    this.month,
  });

  /// 顶栏选中的月份；null = 当月。营收目标、数据池「本月」跟着它走。
  final DateTime? month;

  final AuthSession session;
  final MineApprovalCounts counts;
  final VoidCallback onOpenPendingApprovals;
  final VoidCallback onOpenTodoApprovals;
  final VoidCallback onOpenInitiated;
  final VoidCallback onOpenCc;
  final VoidCallback onOpenRejected;
  final VoidCallback onOpenPendingInitiate;
  final VoidCallback onOpenLighthouse;

  /// `sales` / `purchase`：打开对应提案列表。
  final ValueChanged<String> onOpenProposalList;

  /// PC：在「我的」内容区打开提案，不盖住左侧主导航。
  final ValueChanged<ProposalIntakeRow>? onOpenProposalDetail;

  /// 没有提案权限（外部用户等）时只显示审批。
  final bool showProposals;

  /// 全公司视角：已完成默认看全公司，营收目标与数据池按全公司算。
  final bool companyView;

  /// 外层下拉刷新时 +1，这里跟着重拉。
  final int refreshToken;

  @override
  State<MineHomeBody> createState() => _MineHomeBodyState();
}

class _MineHomeBodyState extends State<MineHomeBody> {
  static const _doingStatuses = {
    'draft',
    'filling',
    'reviewing',
    'pending_president',
  };
  static const _poolFetchLimit = 12;
  static const _kListPreview = 3;
  static const _kListExpanded = 10;
  static const _companyPoolLimit = 100;

  late final ProposalIntakeService _service = ProposalIntakeService(
    session: widget.session,
  );
  late final XflowService _xflow = XflowService(session: widget.session);

  _MineTab _tab = _MineTab.done;
  bool _scopeAll = false;
  bool _proposalsOpen = false;
  bool _tasksOpen = false;
  int? _openId;

  bool _loading = true;
  bool _allLoading = false;
  String? _error;
  int _generation = 0;

  List<ProposalIntakeRow> _doneMine = const [];
  List<ProposalIntakeRow>? _doneAll;
  List<ProposalIntakeRow> _doing = const [];
  List<ProposalIntakeRow> _actionable = const [];
  final Map<int, _MinePool> _pools = {};

  /// 全公司审批归集（/approvals/cost-summary）：本月 / 累计。
  _MineSummary? _summaryMonth;
  _MineSummary? _summaryAll;
  bool _summaryFailed = false;
  bool _summaryLoading = false;
  bool _historySummaryLoading = false;

  /// 数据池卡：全公司视角下看本月还是本年。默认本月。
  bool _poolMonthly = true;

  /// 全公司收入接灯塔（业务口径，元）。取不到时退回发票不含税。
  double? _lhRevenueMonth;
  final Set<int> _poolLoading = {};

  _MineTaskTab _taskTab = _MineTaskTab.doing;
  bool _tasksLoading = true;
  String? _tasksError;
  List<TaskItem> _mineTasks = const [];

  @override
  void initState() {
    super.initState();
    _scopeAll = widget.companyView;
    if (!widget.session.isExternalUser) unawaited(_loadTasks());
    if (widget.showProposals) {
      // _loading 初始就是 true，首帧不能 setState。
      unawaited(_load(silent: true));
    } else {
      _loading = false;
      _tab = _MineTab.todo;
    }
  }

  @override
  void didUpdateWidget(covariant MineHomeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      if (!widget.session.isExternalUser) unawaited(_loadTasks());
      if (widget.showProposals) unawaited(_load(silent: true));
    } else if (oldWidget.month != widget.month && widget.companyView) {
      setState(() {
        _summaryMonth = null;
        _lhRevenueMonth = null;
      });
      unawaited(_loadSummaries());
    }
  }

  DateTime get _selectedMonth {
    final now = DateTime.now();
    final m = widget.month;
    return m == null ? DateTime(now.year, now.month) : DateTime(m.year, m.month);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    final m = _selectedMonth;
    return m.year == now.year && m.month == now.month;
  }

  /// 「本月」或「9月」「25年12月」。
  String get _monthText {
    if (_isCurrentMonth) return '本月';
    final m = _selectedMonth;
    return m.year == DateTime.now().year
        ? '${m.month}月'
        : '${m.year % 100}年${m.month}月';
  }

  /// 汇总接口的 month 参数：当月传空，其余传 YYYY-MM。
  String get _monthKey => _isCurrentMonth
      ? ''
      : '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  /// 灯塔 offset：当月 0，上个月 -1。
  int get _monthOffset {
    final now = DateTime.now();
    final m = _selectedMonth;
    return (m.year - now.year) * 12 + (m.month - now.month);
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _service.fetchList(status: 'done', relatedOnly: true, pageSize: 50),
        _service.fetchList(relatedOnly: true, pageSize: 50),
        _service.fetchList(actionable: true, pageSize: 50),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _doneMine = results[0].items;
        _doing = results[1].items
            .where(
              (row) =>
                  _doingStatuses.contains(row.status) &&
                  (row.status != 'draft' ||
                      proposalIntakeHasMeaningfulContent(row)),
            )
            .toList(growable: false);
        _actionable = results[2].items;
        _loading = false;
        _error = null;
      });
      if (!widget.companyView) unawaited(_loadPools(_doneMine));
      if (_scopeAll || widget.companyView) unawaited(_loadAll());
      if (widget.companyView) unawaited(_loadSummaries());
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '提案加载失败，下拉重试';
      });
    }
  }

  Future<void> _loadAll() async {
    if (_allLoading) return;
    setState(() => _allLoading = true);
    try {
      final result = await _service.fetchList(
        status: 'done',
        pageSize: widget.companyView ? _companyPoolLimit : 50,
      );
      if (!mounted) return;
      setState(() {
        _doneAll = result.items;
        _allLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _allLoading = false);
    }
  }

  Future<void> _loadPools(
    List<ProposalIntakeRow> rows, {
    int limit = _poolFetchLimit,
  }) async {
    final ids = [
      for (final row in rows.take(limit))
        if (!_pools.containsKey(row.id) && !_poolLoading.contains(row.id))
          row.id,
    ];
    if (ids.isEmpty) return;
    _poolLoading.addAll(ids);
    // 全公司可能上百份：8 个一批，边拉边刷新。
    for (var i = 0; i < ids.length; i += 8) {
      final batch = ids.sublist(i, math.min(i + 8, ids.length));
      await Future.wait(
        batch.map((id) async {
          try {
            final data = await _xflow.fetchProposalCostCollection(id);
            _pools[id] = _MinePool.parse(data);
          } catch (_) {
            _pools[id] = _MinePool();
          } finally {
            _poolLoading.remove(id);
          }
        }),
      );
      if (!mounted) return;
      setState(() {});
    }
  }

  void _setScope(bool all) {
    if (_scopeAll == all) return;
    setState(() {
      _scopeAll = all;
      _openId = null;
    });
    if (all && _doneAll == null) unawaited(_loadAll());
  }

  Future<void> _loadTasks() async {
    if (widget.session.isExternalUser) return;
    try {
      final items = await TaskApi(widget.session).listTasks(
        scope: 'mine',
        size: 80,
        maxPages: 1,
      );
      if (!mounted) return;
      setState(() {
        _mineTasks = items;
        _tasksLoading = false;
        _tasksError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tasksLoading = false;
        _tasksError = '任务加载失败，下拉重试';
      });
    }
  }

  void _setTab(_MineTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _openId = null;
    });
  }

  Future<void> _openProposal(ProposalIntakeRow row) async {
    final openInPlace = widget.onOpenProposalDetail;
    if (isDesktopCommOnly && openInPlace != null) {
      openInPlace(row);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MineProposalDetail(session: widget.session, row: row),
      ),
    );
    if (mounted) unawaited(_load(silent: true));
  }

  // ── 文案 ──

  String _kindLabel(ProposalIntakeRow row) =>
      proposalIntakeIsPurchase(row.kind) ? '采购' : '销售';

  String _title(ProposalIntakeRow row) => row.title.trim().isEmpty
      ? proposalIntakeUntitledTitle(row.kind)
      : row.title.trim();

  String _roleOf(ProposalIntakeRow row) {
    final uid = widget.session.userId;
    final form = row.form;
    int id(String key) => int.tryParse('${form[key] ?? ''}'.trim()) ?? 0;
    if (uid <= 0) return '';
    if (id('marketOwner1UserId') == uid) return '市场负责人一';
    if (id('marketOwner2UserId') == uid) return '市场负责人二';
    if (id('operatorUserId') == uid) return '运营';
    if (id('technologyOwnerUserId') == uid) return '技术';
    if (id('financeOwner1UserId') == uid) return '财务负责人一';
    if (id('financeOwner2UserId') == uid) return '财务负责人二';
    if (id('contractAdminUserId') == uid) return '合同管理';
    if (row.createdBy == uid) return '发起人';
    if (id('presidentUserId') == uid) return '最终确认';
    return '';
  }

  String _scaleText(ProposalIntakeRow row) {
    final raw = proposalRemoteListFigures(row).scale;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return '';
    return '年化 ${_groupInt(value.round())} 万';
  }

  String _meta(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(' · ');

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showProposals) ...[
          _buildTargetCard(context),
          const SizedBox(height: 12),
          _buildPoolCard(context),
          const SizedBox(height: 16),
        ],
        _buildApprovalStrip(context),
        const SizedBox(height: 24),
        _buildProposalSection(context),
        if (!widget.session.isExternalUser) ...[
          const SizedBox(height: 24),
          _buildTaskSection(context),
        ],
      ],
    );
  }

  // ── 营收目标 ──

  /// 一份销售提案的月营收目标（万元）：测算收入按年化规模算，÷ 12 拆到月。
  /// 采购提案没有测算，记 0。
  double _monthlyRevenueTarget(ProposalIntakeRow row) {
    if (proposalIntakeIsPurchase(row.kind)) return 0;
    final main = row.financeEstimate['main'];
    final summary = main is Map ? main['summary'] : null;
    final fromSummary = summary is Map
        ? (summary['revenue'] as num?)?.toDouble()
        : null;
    final revenue =
        fromSummary ?? double.tryParse('${row.form['revenue'] ?? ''}') ?? 0;
    return revenue > 0 ? revenue / 12 : 0;
  }

  /// 销售提案年化销售规模（万元）。跟列表卡同一口径：测算 main.salesScale，否则表单。
  /// 采购提案不计。
  double _annualSalesWan(ProposalIntakeRow row) {
    if (proposalIntakeIsPurchase(row.kind)) return 0;
    final main = row.financeEstimate['main'];
    final fromEstimate = main is Map
        ? (main['salesScale'] as num?)?.toDouble()
        : null;
    if (fromEstimate != null && fromEstimate > 0) return fromEstimate;
    return double.tryParse('${row.form['salesScale'] ?? ''}') ?? 0;
  }

  /// 利润率分母：销售提案销售额（元）。本月按年化 ÷ 12；历史/个人相关用全年规模。
  double _salesYuanForMargin() {
    final Iterable<ProposalIntakeRow> rows = widget.companyView
        ? (_doneAll ?? const <ProposalIntakeRow>[])
        : _doneMine.take(_poolFetchLimit);
    var wan = 0.0;
    for (final row in rows) {
      wan += _annualSalesWan(row);
    }
    if (wan <= 0) return 0;
    final monthly = widget.companyView && _poolMonthly;
    return (monthly ? wan / 12 : wan) * 10000;
  }

  int get _daysLeftInMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0).day - now.day;
  }

  Future<void> _loadSummaries() async {
    if (_summaryLoading) return;
    _summaryLoading = true;
    try {
      unawaited(_loadLighthouseRevenue());
      final key = _monthKey;
      final summary = await _fetchSummary(key);
      if (!mounted || key != _monthKey) return;
      setState(() {
        _summaryMonth = summary;
        _summaryFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _summaryFailed = true);
    } finally {
      _summaryLoading = false;
    }
  }

  Future<void> _loadHistorySummary() async {
    if (_summaryAll != null || _historySummaryLoading) return;
    _historySummaryLoading = true;
    try {
      final summary = await _fetchSummary('all');
      if (!mounted) return;
      setState(() => _summaryAll = summary);
    } finally {
      _historySummaryLoading = false;
    }
  }

  /// 灯塔 Hero 的收入（/lighthouse/summary 的 metrics.revenue），和灯塔页同一个数。
  Future<void> _loadLighthouseRevenue() async {
    final service = LighthouseService(session: widget.session);
    double? read(Map<String, dynamic> summary) {
      final metrics = summary['metrics'] is Map ? summary['metrics'] as Map : summary;
      final value = metrics['revenue'];
      return value is num ? value.toDouble() : null;
    }

    try {
      final result = await service.fetchSummary(
        period: 'month',
        offset: _monthOffset,
      );
      if (!mounted) return;
      setState(() => _lhRevenueMonth = read(result));
    } catch (_) {
      // 没有灯塔权限或灯塔挂了：数据池收入退回发票不含税。
    } finally {
      service.dispose();
    }
  }

  Future<_MineSummary> _fetchSummary(String month) async {
    final path = month.isEmpty
        ? '/approvals/cost-summary'
        : '/approvals/cost-summary?month=$month';
    final resp = await dunesHttpGet(widget.session, path);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('cost-summary ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    final data = body is Map && body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
    return _MineSummary.parse(data);
  }

  Widget _buildTargetCard(BuildContext context) {
    if (widget.companyView) return _buildCompanyTargetCard(context);
    return _targetShell(
      context,
      chip: '按月拆分',
      trailing: '目标待设定',
      gaugeFirst: 0,
      gaugeSecond: 0,
      gaugeCenter: '—',
      headline: null,
      intro: '设定后按周期拆分到月',
      rows: const [
        ('第一责任', MinePalette.night, '— / —', 0.0),
        ('第二责任', MinePalette.lavender, '— / —', 0.0),
      ],
    );
  }

  /// 全公司视角（组织用户「我的看全公司」）：
  ///   · 本月目标 = Σ 全公司已完成销售提案测算收入 ÷ 12；
  ///   · 已达 = 全公司本月已通过的开票审批（含税），浅紫 = 本月开票审批中；
  ///   · 开票数据来自 /approvals/cost-summary，不按提案筛。
  Widget _buildCompanyTargetCard(BuildContext context) {
    final rows = _doneAll ?? const <ProposalIntakeRow>[];
    var targetWan = 0.0;
    for (final row in rows) {
      targetWan += _monthlyRevenueTarget(row);
    }
    final month = _summaryMonth;
    final ready = _doneAll != null && month != null;
    final doneWan = (month?.invoiceApproved ?? 0) / 10000;
    final pendingWan = (month?.invoicePending ?? 0) / 10000;
    final hasTarget = targetWan > 0;
    final first = hasTarget ? doneWan / targetWan : 0.0;
    final second = hasTarget ? pendingWan / targetWan : 0.0;
    String fmt(double wan) => _wan(wan * 10000);
    final percent = _summaryFailed
        ? '—'
        : (!ready ? '…' : (hasTarget ? '${(first * 100).round()}%' : '—'));

    return _targetShell(
      context,
      chip: '全公司',
      trailing: _isCurrentMonth
          ? '距月底 $_daysLeftInMonth 天'
          : '${_selectedMonth.year}年${_selectedMonth.month}月',
      gaugeFirst: ready ? first : 0,
      gaugeSecond: ready ? second : 0,
      gaugeCenter: percent,
      headline: _doneAll == null
          ? null
          : (
              ready ? fmt(doneWan) : '…',
              hasTarget ? '/ ${fmt(targetWan)} 万' : '/ 目标 0 万',
            ),
      intro: _summaryFailed
          ? '开票数据暂时取不到，下拉重试'
          : (hasTarget ? null : '已完成销售提案里还没有测算收入'),
      rows: [
        (
          '$_monthText已开票',
          MinePalette.night,
          ready ? '${fmt(doneWan)} 万' : '…',
          ready ? first : 0.0,
        ),
        (
          '开票审批中',
          MinePalette.lavender,
          ready ? '${fmt(pendingWan)} 万' : '…',
          ready ? second : 0.0,
        ),
      ],
    );
  }

  Widget _targetShell(
    BuildContext context, {
    required String chip,
    required String trailing,
    required double gaugeFirst,
    required double gaugeSecond,
    required String gaugeCenter,
    required (String, String)? headline,
    required String? intro,
    required List<(String, Color, String, double)> rows,
  }) {
    Widget progressRow((String, Color, String, double) item) {
      final (label, color, value, ratio) = item;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _r(context, color),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _r(context, MinePalette.ink2),
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: _tnum,
                  color: _r(context, MinePalette.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: _r(context, MinePalette.line, DunesColorRole.border),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ratio.clamp(0.0, 1.0),
                    child: ColoredBox(color: _r(context, color)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: _cardDecoration(context, radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Text(
                  '营收目标',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _r(context, MinePalette.ink),
                  ),
                ),
                const SizedBox(width: 8),
                _chip(context, chip, MinePalette.purpleSoft, MinePalette.purple),
                const Spacer(),
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _r(context, MinePalette.copper),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 136,
                  height: 84,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GaugePainter(
                            first: gaugeFirst,
                            second: gaugeSecond,
                            track: _r(
                              context,
                              MinePalette.line,
                              DunesColorRole.border,
                            ),
                            firstColor: _r(context, MinePalette.night),
                            secondColor: _r(context, MinePalette.lavender),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 2,
                        child: Column(
                          children: [
                            Text(
                              gaugeCenter,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                fontFeatures: _tnum,
                                color: _r(context, MinePalette.night),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '达成',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: _r(context, MinePalette.ink2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (headline != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: headline.$1,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  color: _r(context, MinePalette.ink),
                                ),
                              ),
                              TextSpan(
                                text: ' ${headline.$2}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _r(context, MinePalette.ink2),
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontFeatures: _tnum),
                        ),
                      if (intro != null) ...[
                        if (headline != null) const SizedBox(height: 6),
                        Text(
                          intro,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: _r(context, MinePalette.ink2),
                          ),
                        ),
                      ],
                      for (final item in rows) ...[
                        const SizedBox(height: 10),
                        progressRow(item),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 数据池（与营收目标同一套字号：标题 15/w700，主数 18/w700，格内 12/w600）──

  Widget _buildPoolCard(BuildContext context) {
    _MinePool? pool;
    _MineSummary? activeSummary;
    var ready = false;
    var approvals = 0;
    var unclassifiedCount = 0;
    var unclassifiedTotal = 0.0;
    var missingAmount = 0;
    var revenueFromLighthouse = false;

    if (widget.companyView) {
      final summary = _poolMonthly ? _summaryMonth : _summaryAll;
      activeSummary = summary;
      final lhRevenue = _poolMonthly ? _lhRevenueMonth : null;
      revenueFromLighthouse = lhRevenue != null;
      if (summary != null) {
        // 收入接灯塔（业务口径），成本仍是审批归集；拷一份，别改缓存里的 summary。
        pool = _MinePool()..add(summary.pool);
        if (lhRevenue != null) pool.revenue = lhRevenue;
        ready = true;
        approvals = summary.pool.approvals;
        unclassifiedCount = summary.unclassifiedCount;
        unclassifiedTotal = summary.unclassifiedTotal;
        missingAmount = summary.missingAmount;
      }
    } else {
      final sum = _MinePool();
      var counted = 0;
      for (final row in _doneMine.take(_poolFetchLimit)) {
        final p = _pools[row.id];
        if (p == null) continue;
        sum.add(p);
        counted++;
      }
      ready = counted > 0 || (!_loading && _doneMine.isEmpty);
      pool = sum;
      approvals = sum.approvals;
    }

    final p = pool ?? _MinePool();
    final failed = widget.companyView && _summaryFailed && !ready;
    final empty = ready && approvals == 0 && p.revenue == 0;
    final show = ready && !empty && !failed;
    final costs = p.costs;
    final profit = p.revenue - costs;
    final sales = _salesYuanForMargin();
    final margin = sales > 0 ? profit / sales * 100 : null;
    final ink2 = _r(context, MinePalette.ink2);
    final muted = _r(context, MinePalette.working);
    String amt(double yuan) => show ? _wan(yuan) : (ready || failed ? '—' : '…');

    Widget stat(String label, double value, Color color, {String? sub}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: ink2)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: amt(value),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: show ? _r(context, color) : muted,
                  ),
                ),
                if (show)
                  TextSpan(
                    text: ' 万',
                    style: TextStyle(fontSize: 12, color: ink2),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFeatures: _tnum),
          ),
          const SizedBox(height: 4),
          Text(
            sub ?? '',
            style: TextStyle(fontSize: 10.5, fontFeatures: _tnum, color: ink2),
          ),
        ],
      );
    }

    Widget cell(String label, String bucket, Color dot, double value) {
      final items = activeSummary?.bucketItems[bucket] ?? const [];
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.companyView && activeSummary != null
              ? () => _showCostBucketSheet(context, label, dot, items)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _r(context, dot),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: ink2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: amt(value)),
                      if (show)
                        TextSpan(
                          text: ' 万',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: ink2,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tnum,
                    color: show ? _r(context, MinePalette.ink) : muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final emptyText = failed
        ? '审批数据暂时取不到，下拉刷新重试。'
        : (widget.companyView && _poolMonthly
              ? '$_monthText还没有已通过的业务审批，切到「历史」看看。'
              : '在已完成提案里发起付款、开票、保证金等业务审批，通过后自动归入这里。');

    return Container(
      decoration: _cardDecoration(context, radius: 26),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Text(
                  '数据池',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _r(context, MinePalette.ink),
                  ),
                ),
                const SizedBox(width: 8),
                _chip(
                  context,
                  widget.companyView ? '全公司' : '我相关',
                  MinePalette.purpleSoft,
                  MinePalette.purple,
                ),
                const Spacer(),
                if (widget.companyView)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _r(context, MinePalette.track, DunesColorRole.surface),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _poolScopeButton(context, _monthText, _poolMonthly, () {
                          setState(() => _poolMonthly = true);
                        }),
                        _poolScopeButton(context, '历史', !_poolMonthly, () {
                          setState(() => _poolMonthly = false);
                          unawaited(_loadHistorySummary());
                        }),
                      ],
                    ),
                  )
                else
                  Text(
                    ready ? '$approvals 张审批' : '',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _r(context, MinePalette.copper),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: stat(
                    '收入',
                    p.revenue,
                    MinePalette.revenue,
                    sub: revenueFromLighthouse ? '灯塔 · 业务口径' : '发票 · 不含税',
                  ),
                ),
                Expanded(
                  child: stat(
                    '四类成本',
                    costs,
                    MinePalette.ink,
                    sub: show ? '$approvals 张审批' : '',
                  ),
                ),
                Expanded(
                  child: stat(
                    '利润',
                    profit,
                    profit < 0 ? MinePalette.revenue : MinePalette.night,
                    sub: show && margin != null
                        ? '利润率 ${margin.toStringAsFixed(1)}%'
                        : '',
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _r(context, MinePalette.wash, DunesColorRole.surface),
              border: Border(
                top: BorderSide(
                  color: _r(context, MinePalette.washLine, DunesColorRole.border),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (show)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cell('项目', 'projectCost', MinePalette.project, p.project)),
                      Expanded(child: cell('业务', 'businessCost', MinePalette.business, p.business)),
                      Expanded(child: cell('税务', 'taxCost', MinePalette.tax, p.tax)),
                      Expanded(child: cell('经营', 'operatingCost', MinePalette.operating, p.operating)),
                      Expanded(child: cell('周转', 'workingCapital', MinePalette.working, p.working)),
                    ],
                  )
                else
                  Text(
                    emptyText,
                    style: TextStyle(fontSize: 12, height: 1.5, color: ink2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCostBucketSheet(
    BuildContext context,
    String label,
    Color color,
    List<_MineCostApproval> items,
  ) {
    String date(DateTime? value) => value == null
        ? ''
        : '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final total = items.fold<double>(0, (sum, item) => sum + item.amount);
    final bizCount = items.where((item) => item.isBusiness).length;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      // 拖动关闭会抢走列表的上滑手势（网页端鼠标拖动尤其明显），只留点外面和关闭按钮。
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final ink = _r(ctx, MinePalette.ink);
        final ink2 = _r(ctx, MinePalette.ink2);
        final line = _r(ctx, MinePalette.line, DunesColorRole.border);
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .82,
            ),
            decoration: BoxDecoration(
              color: _r(ctx, MinePalette.page, DunesColorRole.surface),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _r(ctx, color),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$label成本',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _r(ctx, MinePalette.card, DunesColorRole.surface),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _poolMonthly ? _monthText : '历史',
                          style: TextStyle(fontSize: 11, color: ink2),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close_rounded, size: 20, color: ink2),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _wan(total),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            fontFeatures: _tnum,
                            color: ink,
                          ),
                        ),
                        TextSpan(text: ' 万  ·  已通过 ${items.length} 张'),
                        if (items.isNotEmpty)
                          TextSpan(text: '（业务 $bizCount · 非业务 ${items.length - bizCount}）'),
                      ],
                    ),
                    style: TextStyle(fontSize: 12, color: ink2),
                  ),
                ),
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
                          child: Text(
                            _poolMonthly ? '$_monthText暂无已通过的$label成本审批' : '暂无已通过的$label成本审批',
                            style: TextStyle(color: ink2),
                          ),
                        )
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(ctx).copyWith(
                            dragDevices: PointerDeviceKind.values.toSet(),
                          ),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            decoration: BoxDecoration(
                              color: _r(ctx, MinePalette.card, DunesColorRole.surface),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                thickness: 1,
                                indent: 14,
                                endIndent: 14,
                                color: line,
                              ),
                              itemBuilder: (_, index) {
                                final item = items[index];
                                final canOpen =
                                    item.businessType.isNotEmpty && item.businessId > 0;
                                final when = date(item.occurredAt);
                                return InkWell(
                                  onTap: !canOpen
                                      ? null
                                      : () {
                                          unawaited(
                                            showApprovalDetailOverlay(
                                              context: ctx,
                                              preferDialog: true,
                                              session: widget.session,
                                              share: ApprovalChatShare(
                                                businessType: item.businessType,
                                                businessId: item.businessId,
                                                title: item.title,
                                                status: item.status,
                                                templateKey: item.templateKey,
                                              ),
                                            ),
                                          );
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.title.isEmpty ? '审批单' : item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: ink,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  _chip(
                                                    ctx,
                                                    item.isBusiness ? '业务' : '非业务',
                                                    item.isBusiness
                                                        ? MinePalette.purpleSoft
                                                        : MinePalette.steelSoft,
                                                    item.isBusiness
                                                        ? MinePalette.purple
                                                        : MinePalette.steel,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    Icons.check_circle_rounded,
                                                    size: 12,
                                                    color: _r(ctx, MinePalette.purple),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '已通过',
                                                    style: TextStyle(fontSize: 11, color: ink2),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      [
                                                        '',
                                                        if (item.initiatorName.isNotEmpty)
                                                          item.initiatorName,
                                                        if (when.isNotEmpty) when,
                                                      ].join(' · '),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(fontSize: 11, color: ink2),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(text: _wan(item.amount)),
                                              TextSpan(
                                                text: ' 万',
                                                style: TextStyle(fontSize: 10.5, color: ink2),
                                              ),
                                            ],
                                          ),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: _tnum,
                                            color: ink,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 22,
                                          child: canOpen
                                              ? Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 18,
                                                  color: ink2,
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _poolScopeButton(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    return Material(
      color: on
          ? _r(context, MinePalette.card, DunesColorRole.surface)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on
                  ? _r(context, MinePalette.purple)
                  : _r(context, MinePalette.ink2),
            ),
          ),
        ),
      ),
    );
  }

  // ── 审批四格 ──

  Widget _buildApprovalStrip(BuildContext context) {
    final c = widget.counts;
    Widget cell({
      required IconData icon,
      required String label,
      required int count,
      required VoidCallback onTap,
      bool highlight = false,
    }) {
      return Expanded(
        child: Material(
          color: highlight
              ? _r(context, MinePalette.purpleSoft, DunesColorRole.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 9),
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: highlight
                          ? _r(context, MinePalette.purple)
                          : _r(context, MinePalette.page, DunesColorRole.surface),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 15,
                      color: highlight
                          ? Colors.white
                          : _r(context, MinePalette.night),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$label '),
                        TextSpan(
                          text: '$count',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: _tnum,
                            color: highlight
                                ? _r(context, MinePalette.purpleDeep)
                                : _r(context, MinePalette.ink),
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                      color: highlight
                          ? _r(context, MinePalette.purpleDeep)
                          : _r(context, MinePalette.ink2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: _cardDecoration(context, radius: 22),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          cell(
            icon: Icons.check_rounded,
            label: '待我审',
            count: c.pendingForMe,
            onTap: widget.onOpenPendingApprovals,
            highlight: true,
          ),
          cell(
            icon: Icons.schedule_rounded,
            label: '待办理',
            count: c.pendingTodo,
            onTap: widget.onOpenTodoApprovals,
          ),
          cell(
            icon: Icons.near_me_outlined,
            label: '我发起',
            count: c.initiatedPending,
            onTap: widget.onOpenInitiated,
          ),
          cell(
            icon: Icons.mail_outline_rounded,
            label: '抄送我',
            count: c.cc,
            onTap: widget.onOpenCc,
          ),
        ],
      ),
    );
  }

  // ── 我的提案 ──

  Widget _buildProposalSection(BuildContext context) {
    final todos = _todoItems();
    final doneRows = _scopeAll ? (_doneAll ?? const <ProposalIntakeRow>[]) : _doneMine;
    final tabs = <(_MineTab, String, int)>[
      if (widget.showProposals) (_MineTab.done, '已完成', doneRows.length),
      if (widget.showProposals) (_MineTab.doing, '进行中', _doing.length),
      (_MineTab.todo, '待我处理', todos.length),
    ];

    final limit = _proposalsOpen ? _kListExpanded : _kListPreview;
    Widget body;
    if (_loading && _tab != _MineTab.todo) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_error != null && _tab != _MineTab.todo) {
      body = _empty(context, _error!);
    } else {
      body = switch (_tab) {
        _MineTab.done =>
          _scopeAll && _doneAll == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : _buildDoneList(context, doneRows, limit: limit),
        _MineTab.doing => _buildDoingList(context, limit: limit),
        _MineTab.todo => _buildTodoList(context, todos, limit: limit),
      };
    }

    final proposalCount = switch (_tab) {
      _MineTab.done => doneRows.length,
      _MineTab.doing => _doing.length,
      _MineTab.todo => todos.length,
    };
    final donePending = _tab == _MineTab.done &&
        _scopeAll &&
        _doneAll == null &&
        (_loading || _allLoading);
    final proposalBusy = (_loading && _tab != _MineTab.todo) || donePending;
    final showFooter = !proposalBusy && _error == null && proposalCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                widget.showProposals ? '我的提案' : '待我处理',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _r(context, MinePalette.ink),
                ),
              ),
              const Spacer(),
              if (_tab == _MineTab.done &&
                  widget.showProposals &&
                  widget.companyView)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: _cardDecoration(context, radius: 999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _scopeButton(context, '我相关', !_scopeAll, () => _setScope(false)),
                      _scopeButton(context, '全公司', _scopeAll, () => _setScope(true)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (tabs.length > 1) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _r(context, MinePalette.track, DunesColorRole.surface),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                for (final (tab, label, count) in tabs)
                  Expanded(child: _tabButton(context, tab, label, count)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: _cardDecoration(context, radius: 24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body,
              if (showFooter)
                _listFooter(
                  context,
                  total: proposalCount,
                  unit: _tab == _MineTab.todo ? '项' : '份',
                  open: _proposalsOpen,
                  onToggle: () =>
                      setState(() => _proposalsOpen = !_proposalsOpen),
                  links: _tab == _MineTab.todo
                      ? [('审批流转', widget.onOpenPendingApprovals)]
                      : [
                          ('全部销售', () => widget.onOpenProposalList('sales')),
                          ('全部采购', () => widget.onOpenProposalList('purchase')),
                        ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 列表底栏：左边展开/收起，右边跳完整列表。
  Widget _listFooter(
    BuildContext context, {
    required int total,
    required String unit,
    required bool open,
    required VoidCallback onToggle,
    required List<(String, VoidCallback)> links,
  }) {
    final purple = _r(context, MinePalette.purple);
    final ink2 = _r(context, MinePalette.ink2);
    final canToggle = total > _kListPreview;
    final hidden = total - (open ? _kListExpanded : _kListPreview);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _r(context, MinePalette.line, DunesColorRole.border),
          ),
        ),
      ),
      child: Row(
        children: [
          if (canToggle)
            TextButton.icon(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                foregroundColor: purple,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              iconAlignment: IconAlignment.end,
              icon: Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(
                open
                    ? (hidden > 0 ? '收起 · 还有 $hidden $unit' : '收起')
                    : '展开 · 共 $total $unit',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                '共 $total $unit',
                style: TextStyle(fontSize: 12, color: ink2),
              ),
            ),
          const Spacer(),
          for (final (label, onTap) in links)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: ink2,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  const Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _scopeButton(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    return Material(
      color: on ? _r(context, MinePalette.night) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? Colors.white : _r(context, MinePalette.ink2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(
    BuildContext context,
    _MineTab tab,
    String label,
    int count,
  ) {
    final on = _tab == tab;
    final countColor = on
        ? MinePalette.purple
        : (tab == _MineTab.todo && count > 0
              ? MinePalette.copper
              : MinePalette.ink2);
    return GestureDetector(
      onTap: () => _setTab(tab),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? _r(context, MinePalette.card, DunesColorRole.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: const Color(0xFF1F2421).withValues(alpha: .10),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              TextSpan(
                text: ' $count',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tnum,
                  color: _r(context, countColor),
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on
                ? _r(context, MinePalette.ink)
                : _r(context, MinePalette.ink2),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: _r(context, MinePalette.ink2)),
        ),
      ),
    );
  }

  Widget _divided(BuildContext context, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: _r(context, MinePalette.line, DunesColorRole.border),
            ),
          rows[i],
        ],
      ],
    );
  }

  // ── 我的任务 ──

  bool _taskPending(TaskItem task) =>
      task.isPending || task.hasPendingChange || task.status == 'rejected';

  bool _taskDone(TaskItem task) =>
      task.status == 'completed' || task.status == 'cancelled';

  List<TaskItem> get _taskDoingRows => _mineTasks
      .where((task) => !_taskPending(task) && !_taskDone(task))
      .toList(growable: false);

  List<TaskItem> get _taskPendingRows =>
      _mineTasks.where(_taskPending).toList(growable: false);

  List<TaskItem> get _taskDoneRows =>
      _mineTasks.where(_taskDone).toList(growable: false);

  List<TaskItem> get _taskRows => switch (_taskTab) {
    _MineTaskTab.doing => _taskDoingRows,
    _MineTaskTab.pending => _taskPendingRows,
    _MineTaskTab.done => _taskDoneRows,
  };

  Future<void> _openTask(int taskId) async {
    if (taskId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          body: SafeArea(
            child: NativeTaskDetailView(
              session: widget.session,
              taskId: taskId,
              onBack: () => Navigator.of(routeContext).pop(),
            ),
          ),
        ),
      ),
    );
    if (mounted) unawaited(_loadTasks());
  }

  Future<void> _openAllTasks() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: const Text('我的任务'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(routeContext).pop(),
            ),
          ),
          body: NativeTaskHomePane(session: widget.session),
        ),
      ),
    );
    if (mounted) unawaited(_loadTasks());
  }

  Widget _buildTaskSection(BuildContext context) {
    final rows = _taskRows;
    final tabs = <(_MineTaskTab, String, int)>[
      (_MineTaskTab.doing, '进行中', _taskDoingRows.length),
      (_MineTaskTab.pending, '待处理', _taskPendingRows.length),
      (_MineTaskTab.done, '已完成', _taskDoneRows.length),
    ];
    final Widget body;
    if (_tasksLoading && _mineTasks.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_tasksError != null && _mineTasks.isEmpty) {
      body = _empty(context, _tasksError!);
    } else if (rows.isEmpty) {
      body = _empty(
        context,
        switch (_taskTab) {
          _MineTaskTab.doing => '没有进行中的任务',
          _MineTaskTab.pending => '没有待确认、待接收或被驳回的任务',
          _MineTaskTab.done => '还没有已完成的任务',
        },
      );
    } else {
      body = _divided(context, [
        for (final task in rows.take(_tasksOpen ? _kListExpanded : _kListPreview))
          _buildTaskRow(context, task),
      ]);
    }
    final showFooter = rows.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '我的任务',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _r(context, MinePalette.ink),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _r(context, MinePalette.track, DunesColorRole.surface),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              for (final (tab, label, count) in tabs)
                Expanded(child: _taskTabButton(context, tab, label, count)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _cardDecoration(context, radius: 24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body,
              if (showFooter)
                _listFooter(
                  context,
                  total: rows.length,
                  unit: '个',
                  open: _tasksOpen,
                  onToggle: () => setState(() => _tasksOpen = !_tasksOpen),
                  links: [('全部任务', _openAllTasks)],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _taskTabButton(
    BuildContext context,
    _MineTaskTab tab,
    String label,
    int count,
  ) {
    final on = _taskTab == tab;
    return GestureDetector(
      onTap: () {
        if (_taskTab == tab) return;
        setState(() => _taskTab = tab);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? _r(context, MinePalette.card, DunesColorRole.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              TextSpan(
                text: ' $count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tnum,
                  color: _r(
                    context,
                    on ? MinePalette.purple : MinePalette.ink2,
                  ),
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on
                ? _r(context, MinePalette.ink)
                : _r(context, MinePalette.ink2),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(BuildContext context, TaskItem task) {
    final overdue = task.overdue && task.status != 'completed';
    final status = overdue ? '已逾期' : taskDisplayStatusLabel(task);
    final due = formatTaskYmd(task.dueAt);
    final priority = task.priority == 'high' || task.priority == 'urgent'
        ? taskPriorityLabel(task.priority)
        : '';
    final change = task.hasPendingChange
        ? taskPendingChangeLabel(task.pendingChangeKind)
        : '';
    return InkWell(
      onTap: () => _openTask(task.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.trim().isEmpty ? '未命名任务' : task.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _r(context, MinePalette.ink),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _chip(
                        context,
                        taskKindLabel(task),
                        MinePalette.purpleSoft,
                        MinePalette.purple,
                      ),
                      if (priority.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _chip(
                          context,
                          priority,
                          MinePalette.copperSoft,
                          MinePalette.copper,
                        ),
                      ],
                      if (change.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _chip(
                          context,
                          change,
                          MinePalette.copperSoft,
                          MinePalette.copper,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _meta([
                      if (task.ownerName.trim().isNotEmpty) '负责 ${task.ownerName.trim()}',
                      if (due.isNotEmpty) '截止 $due',
                      '进度 ${task.progressPct}%',
                      if (task.subtaskCount > 0)
                        '子任务 ${taskSubtaskProgressLabel(task)}',
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: _r(context, MinePalette.ink2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _r(
                  context,
                  overdue ? MinePalette.copper : MinePalette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 已完成 ──

  Widget _buildDoneList(
    BuildContext context,
    List<ProposalIntakeRow> rows, {
    required int limit,
  }) {
    if (rows.isEmpty) {
      return _empty(
        context,
        _scopeAll ? '全公司暂无已完成提案' : '还没有你参与的已完成提案',
      );
    }
    final shown = rows.take(limit).toList(growable: false);
    if (shown.any((r) => !_pools.containsKey(r.id) && !_poolLoading.contains(r.id))) {
      unawaited(_loadPools(shown));
    }
    return _divided(context, [
      for (final row in shown) _buildDoneRow(context, row),
    ]);
  }

  Widget _buildDoneRow(BuildContext context, ProposalIntakeRow row) {
    final pool = _pools[row.id];
    final role = _roleOf(row);
    final approvals = pool?.approvals ?? row.relatedApprovalCount ?? 0;
    final completedRaw = '${row.review['presidentDecidedAt'] ?? ''}'.trim();
    final completed = _monthDay(completedRaw.isNotEmpty ? completedRaw : row.updatedAt);
    final owner = '${row.form['createdByName'] ?? row.form['initiatorName'] ?? ''}'
        .trim();
    final sector = '${row.form['sector'] ?? ''}'.trim();

    final value = pool == null ? '…' : '${_wan(pool.costs)} 万';
    final valueLabel = '成本归集';
    final detail = _meta([
      if (owner.isNotEmpty) '发起 $owner',
      if (completed.isNotEmpty) '完成 $completed',
      if (pool != null && approvals > 0) '$approvals 张已通过',
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rowHeader(
          context,
          ring: _Ring(progress: 1, color: MinePalette.purple, label: '', done: true),
          title: _title(row),
          kind: _kindLabel(row),
          meta: _meta([
            role.isEmpty ? (_scopeAll ? '全公司' : '') : role,
            _scaleText(row),
            sector,
          ]),
          detail: detail,
          value: value,
          valueLabel: valueLabel,
          valueColor: MinePalette.ink,
          onTap: () => _openProposal(row),
        ),
        if (pool != null && pool.bandTotal > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 12, 10),
            child: _PoolBand(pool: pool, height: 4),
          ),
      ],
    );
  }

  // ── 进行中 ──

  Widget _buildDoingList(BuildContext context, {required int limit}) {
    if (_doing.isEmpty) return _empty(context, '没有进行中的提案');
    return _divided(context, [
      for (final row in _doing.take(limit)) _buildDoingRow(context, row),
    ]);
  }

  Widget _buildDoingRow(BuildContext context, ProposalIntakeRow row) {
    final progress = proposalIntakeProgressSteps(row: row);
    final segments = proposalReviewSegments(progress);
    final total = segments.isEmpty ? 1 : segments.length;
    final doneCount = segments
        .where((s) => s.state == ProposalListStepState.done)
        .length;
    final rejected = segments.any(
      (s) => s.state == ProposalListStepState.rejected,
    );
    final waited = proposalReviewWaited(progress);
    final waitedDays = waited?.inDays ?? 0;
    final late = waitedDays >= 3 || rejected;
    final who = proposalReviewWhoText(progress);
    final now = proposalReviewNowText(progress);
    final mine = row.myAction.trim().isNotEmpty;

    final value = waited == null
        ? (row.status == 'draft' ? '草稿' : '—')
        : (waited.inDays >= 1
              ? '${waited.inDays} 天'
              : (waited.inHours >= 1 ? '${waited.inHours} 小时' : '刚到'));
    final valueLabel = rejected ? '已驳回' : (late ? '已卡住' : '本阶段');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rowHeader(
          context,
          ring: _Ring(
            progress: doneCount / total,
            color: late ? MinePalette.copperMid : MinePalette.lavender,
            label: '$doneCount/$total',
          ),
          title: _title(row),
          kind: _kindLabel(row),
          meta: _meta([
            _roleOf(row),
            mine ? '轮到你' : who,
            now,
          ]),
          detail: _meta([
            '${row.form['sector'] ?? ''}'.trim(),
            row.status == 'draft' ? '草稿' : '',
          ]),
          value: value,
          valueLabel: valueLabel,
          valueColor: late ? MinePalette.copper : MinePalette.ink,
          onTap: () => _openProposal(row),
        ),
      ],
    );
  }

  // ── 待我处理 ──

  List<_MineTodo> _todoItems() {
    final c = widget.counts;
    return [
      if (c.pendingForMe > 0)
        _MineTodo(
          kind: '审批',
          title: '${c.pendingForMe} 张审批待我审',
          subtitle: '提案内业务审批与日常审批',
          action: '审批',
          tone: _MineTodoTone.purple,
          onTap: widget.onOpenPendingApprovals,
        ),
      if (c.pendingTodo > 0)
        _MineTodo(
          kind: '办理',
          title: '${c.pendingTodo} 条审批待办理',
          subtitle: '审批通过后需要我执行的事项',
          action: '办理',
          tone: _MineTodoTone.purple,
          onTap: widget.onOpenTodoApprovals,
        ),
      if (c.rejected > 0)
        _MineTodo(
          kind: '驳回',
          title: '${c.rejected} 条我发起的审批被驳回',
          subtitle: '修改后重新提交',
          action: '处理',
          tone: _MineTodoTone.copper,
          onTap: widget.onOpenRejected,
        ),
      if (c.pendingInitiate > 0)
        _MineTodo(
          kind: '发起',
          title: '${c.pendingInitiate} 条待我确认发起',
          subtitle: '同事推送给我、等我确认发起的审批',
          action: '确认',
          tone: _MineTodoTone.steel,
          onTap: widget.onOpenPendingInitiate,
        ),
      for (final row in _actionable)
        _MineTodo(
          kind: '提案',
          title: _title(row),
          subtitle: _meta([
            _kindLabel(row),
            proposalReviewNowText(proposalIntakeProgressSteps(row: row)),
          ]),
          action: '处理',
          tone: _MineTodoTone.steel,
          onTap: () => _openProposal(row),
        ),
    ];
  }

  Widget _buildTodoList(
    BuildContext context,
    List<_MineTodo> todos, {
    required int limit,
  }) {
    if (todos.isEmpty) return _empty(context, '没有待处理的事项');
    return _divided(context, [
      for (final todo in todos.take(limit))
        InkWell(
          onTap: todo.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _r(context, todo.tone.soft, DunesColorRole.surface),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    todo.kind,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _r(context, todo.tone.fg),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: _r(context, MinePalette.ink),
                        ),
                      ),
                      if (todo.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          todo.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _r(context, MinePalette.ink2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _r(context, todo.tone.button),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    todo.action,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ]);
  }

  // ── 行的公共部分 ──

  Widget _rowHeader(
    BuildContext context, {
    required _Ring ring,
    required String title,
    required String kind,
    required String meta,
    String detail = '',
    required String value,
    required String valueLabel,
    required Color valueColor,
    required VoidCallback onTap,
  }) {
    final purchase = kind == '采购';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        child: Row(
          children: [
            SizedBox(width: 30, height: 30, child: ring),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _r(context, MinePalette.ink),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _chip(
                        context,
                        kind,
                        purchase ? MinePalette.steelSoft : MinePalette.purpleSoft,
                        purchase ? MinePalette.steel : MinePalette.purple,
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: _r(context, MinePalette.ink2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _r(context, MinePalette.ink2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tnum,
                    color: _r(context, valueColor),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: _r(context, MinePalette.ink2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _chip(BuildContext context, String text, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _r(context, bg, DunesColorRole.surface),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: _r(context, fg),
      ),
    ),
  );
}

enum _MineTodoTone {
  purple(MinePalette.purpleSoft, MinePalette.purple, MinePalette.night),
  steel(MinePalette.steelSoft, MinePalette.steel, MinePalette.night),
  copper(MinePalette.copperSoft, MinePalette.copper, MinePalette.copper);

  const _MineTodoTone(this.soft, this.fg, this.button);

  final Color soft;
  final Color fg;
  final Color button;
}

class _MineTodo {
  const _MineTodo({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.tone,
    required this.onTap,
  });

  final String kind;
  final String title;
  final String subtitle;
  final String action;
  final _MineTodoTone tone;
  final VoidCallback onTap;
}

/// 五类数据池色带。总额为 0 时画一条空轨道。
class _PoolBand extends StatelessWidget {
  const _PoolBand({required this.pool, required this.height});

  final _MinePool pool;
  final double height;

  @override
  Widget build(BuildContext context) {
    final segments = [
      for (final (color, value) in pool.segments)
        if (value > 0) (color, value),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: segments.isEmpty
            ? ColoredBox(
                color: _r(context, MinePalette.line, DunesColorRole.border),
              )
            : Row(
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, (segments[i].$2 * 1000 / pool.bandTotal).round()),
                      child: ColoredBox(color: _r(context, segments[i].$1)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// 行首的进度环：已完成整圈打勾，进行中按复核段数。
class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.color,
    required this.label,
    this.done = false,
  });

  final double progress;
  final Color color;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(
        progress: progress.clamp(0.0, 1.0),
        color: _r(context, color),
        track: _r(context, MinePalette.line, DunesColorRole.border),
      ),
      child: Center(
        child: done
            ? Icon(Icons.check_rounded, size: 16, color: _r(context, color))
            : Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tnum,
                  color: _r(context, MinePalette.ink),
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.5;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2 - 0.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// 营收目标半圆：先画第一 + 第二责任（浅紫），再盖第一责任（深紫）。
class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.first,
    required this.second,
    required this.track,
    required this.firstColor,
    required this.secondColor,
  });

  /// 占目标的比例，0–1。
  final double first;
  final double second;
  final Color track;
  final Color firstColor;
  final Color secondColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final radius = math.min(size.width / 2, size.height - 6) - stroke / 2;
    final center = Offset(size.width / 2, size.height - 10);
    final rect = Rect.fromCircle(center: center, radius: radius);
    Paint p(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawArc(rect, math.pi, math.pi, false, p(track));
    final both = (first + second).clamp(0.0, 1.0);
    if (both > 0) {
      canvas.drawArc(rect, math.pi, math.pi * both, false, p(secondColor));
    }
    final one = first.clamp(0.0, 1.0);
    if (one > 0) {
      canvas.drawArc(rect, math.pi, math.pi * one, false, p(firstColor));
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.first != first ||
      old.second != second ||
      old.track != track ||
      old.firstColor != firstColor ||
      old.secondColor != secondColor;
}

/// 从「我的」打开某一份提案：带返回的整页，复用提案详情。
///
/// [onClose] 有值时留在当前内容区（PC 左侧主导航不被盖住）；否则走整页路由。
class MineProposalDetail extends StatefulWidget {
  const MineProposalDetail({
    super.key,
    required this.session,
    required this.row,
    this.onClose,
  });

  final AuthSession session;
  final ProposalIntakeRow row;
  final VoidCallback? onClose;

  @override
  State<MineProposalDetail> createState() => _MineProposalDetailState();
}

class _MineProposalDetailState extends State<MineProposalDetail> {
  TaskShellChrome _chrome = const TaskShellChrome();

  /// 提案页先加载列表再打开 initialIntakeId；打开前盖一层，免得先闪一下整张列表。
  bool _formOpened = false;
  bool _coverTimedOut = false;
  Timer? _coverTimer;

  @override
  void initState() {
    super.initState();
    // 兜底：提案打不开（无权限、已删除）时 8 秒后露出列表，不让人干等。
    _coverTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _coverTimedOut = true);
    });
  }

  @override
  void dispose() {
    _coverTimer?.cancel();
    super.dispose();
  }

  void _leave() {
    final close = widget.onClose;
    if (close != null) {
      close();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _onChrome(TaskShellChrome chrome) {
    if (!mounted) return;
    final inForm = chrome.onBack != null;
    if (_formOpened && !inForm) {
      // 从提案详情退回列表 = 回「我的」。
      _leave();
      return;
    }
    setState(() {
      _chrome = chrome;
      if (inForm) _formOpened = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final purchase = proposalIntakeIsPurchase(widget.row.kind);
    final title = widget.row.title.trim();
    return Scaffold(
      backgroundColor: _r(context, const Color(0xFFF5F6F8), DunesColorRole.surface),
      appBar: AppBar(
        title: Text(
          title.isEmpty ? (purchase ? '采购提案' : '销售提案') : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: _chrome.onBack ?? _leave,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: NativeProposalIntakePage(
              key: ValueKey('mine-proposal-${widget.row.id}'),
              session: widget.session,
              kind: purchase ? 'purchase' : 'sales',
              initialIntakeId: widget.row.id,
              showCreate: false,
              onChromeChanged: _onChrome,
            ),
          ),
          if (!_formOpened && !_coverTimedOut)
            Positioned.fill(
              child: ColoredBox(
                color: _r(context, const Color(0xFFF5F6F8), DunesColorRole.surface),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
