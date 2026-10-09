import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'proposal_intake_models.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// 提案页原型样式的字体：中文 Noto Sans SC（带真粗体），数字 JetBrains Mono。
/// 两个字体族只在原型样式里用，不影响 App 其他页面。
const kProposalProtoSans = 'Noto Sans SC Proposal';
const kProposalProtoSansFallback = [
  'Noto Sans SC',
  'PingFang SC',
  'Microsoft YaHei',
  'sans-serif',
];
const kProposalProtoMono = 'JetBrains Mono';
const kProposalProtoMonoFallback = [
  'Geist Mono',
  'Noto Sans SC Proposal',
  'Noto Sans SC',
  'monospace',
];

abstract final class ProposalPalette {
  static const page = Color(0xFFF3F0F7);
  static const app = Color(0xFFFBFAFD);
  static const soft = Color(0xFFF6F2FA);
  static const card = Colors.white;
  static const border = Color(0xFFE1D9EA);
  static const borderSoft = Color(0xFFEEE8F3);
  static const text = Color(0xFF292530);
  static const text2 = Color(0xFF66606D);
  static const text3 = Color(0xFF958E9E);
  static const purple = Color(0xFF7B5CD8);
  static const purpleDeep = Color(0xFF4F3488);
  static const purpleSoft = Color(0xFFE8DCF7);
  static const purpleLine = Color(0xFF9B7AD4);
  static const navTop = Color(0xFF342A49);
  static const navBottom = Color(0xFF2B243C);
  static const green = Color(0xFF3F7A38);
  static const greenSoft = Color(0xFFD7E8C8);
  static const amber = Color(0xFFB07A2B);
  static const amberSoft = Color(0xFFF4E8D2);
  static const coral = Color(0xFFBC5C40);
  static const coralSoft = Color(0xFFF5E5DC);

  /// 比 border 再深一档，用于需要压住底色的分隔线与序号列。
  static const borderStrong = Color(0xFFD8CBE6);

  /// purple 与 purpleDeep 之间的中间色，用于次级强调。
  static const purpleMid = Color(0xFF7255A8);

  /// 最浅一档文字：占位、禁用态。
  static const text4 = Color(0xFFC5BFCE);
}

/// 面板内部的三级字阶。板块大标题由 [ProposalSectionTitle] 统一承担，
/// 面板里再往下只允许这三档，避免子块字号盖过父块。
///
/// 眉标（如「产品结算」）> 区块标题 > 子区块标题 > 说明文案。
const kProposalEyebrowStyle = TextStyle(
  color: ProposalPalette.text2,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: .8,
);

const kProposalBlockTitleStyle = TextStyle(
  color: ProposalPalette.text,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

const kProposalSubBlockTitleStyle = TextStyle(
  color: ProposalPalette.text2,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

const kProposalCaptionStyle = TextStyle(
  color: ProposalPalette.text3,
  fontSize: 11,
  height: 1.45,
);

/// 原型「填报内容」简单行：只读整单（待最终确认、已完成）时，字段改成
/// 「名称在左、值在右」一行一条，卡片去掉外框，板块大标题不再重复。
/// 不包这一层时所有组件与原来完全一样。
class ProposalSimpleViewScope extends InheritedWidget {
  const ProposalSimpleViewScope({
    super.key,
    required super.child,
    this.readOnly = false,
    this.textRows = false,
  });

  /// 只读整单（待最终确认、已完成）：板块大标题也不再重复。
  /// 填写、复核时保留大标题，只把字段、输入框、复核按钮换成原型样式。
  final bool readOnly;

  /// 值都以文字展示（复核简单行、查看）：行固定一行高，名称不换行。
  final bool textRows;

  static bool textRowsOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ProposalSimpleViewScope>();
    return scope != null && (scope.readOnly || scope.textRows);
  }

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProposalSimpleViewScope>() !=
      null;

  static bool readOnlyOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ProposalSimpleViewScope>()
          ?.readOnly ==
      true;

  @override
  bool updateShouldNotify(ProposalSimpleViewScope oldWidget) =>
      oldWidget.readOnly != readOnly || oldWidget.textRows != textRows;
}

/// 账号打码：连续 8 位以上的数字只留前 4 位和后 4 位，中间写 ****。
/// 如「416230100100002564」→「4162 **** 2564」；账户名等文字原样保留。
String proposalMaskAccount(String raw) => raw.replaceAllMapped(
  RegExp(r'\d{8,}'),
  (m) {
    final digits = m[0]!;
    return '${digits.substring(0, 4)} **** ${digits.substring(digits.length - 4)}';
  },
);

/// 简单行多列排布时，分隔线由整排统一画（同一排对齐成一条线），格子自己不再画。
class ProposalGridRowScope extends InheritedWidget {
  const ProposalGridRowScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProposalGridRowScope>() !=
      null;

  @override
  bool updateShouldNotify(ProposalGridRowScope oldWidget) => false;
}

/// 简单行一行的标准高度：名称、值、复核标记都在这一条里垂直居中。
const double kProposalSimpleLineHeight = 22;

/// 原型的输入框：无外框，底部一条紫色虚线；聚焦时变成实线。
class ProposalDashedUnderlineBorder extends InputBorder {
  const ProposalDashedUnderlineBorder({
    super.borderSide = const BorderSide(color: Color(0xFFCFC2F5)),
    this.dashed = true,
  });

  final bool dashed;

  @override
  ProposalDashedUnderlineBorder copyWith({BorderSide? borderSide, bool? dashed}) =>
      ProposalDashedUnderlineBorder(
        borderSide: borderSide ?? this.borderSide,
        dashed: dashed ?? this.dashed,
      );

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.only(bottom: borderSide.width);

  @override
  ProposalDashedUnderlineBorder scale(double t) =>
      ProposalDashedUnderlineBorder(borderSide: borderSide.scale(t), dashed: dashed);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()
    ..addRect(
      Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        math.max(0.0, rect.height - borderSide.width),
      ),
    );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none) return;
    final paint = borderSide.toPaint();
    final y = rect.bottom - borderSide.width / 2;
    if (!dashed) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
      return;
    }
    const dash = 4.0;
    const gap = 3.0;
    for (var x = rect.left; x < rect.right; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, rect.right), y),
        paint,
      );
    }
  }
}

/// 提案页统一断点与栅格尺寸。
///
/// 同类区块必须用同一组阈值判断换行，手机与 PC 上栏位才能对齐；
/// 各自写 420 / 520 / 620 / 640 是此前对不齐的根因。
abstract final class ProposalLayout {
  /// 单列：手机、窄侧栏。
  static const compact = 560.0;

  /// 双列：平板、窄窗口。
  static const medium = 900.0;

  /// 三列以上：桌面。
  static const wide = 1280.0;

  /// 嵌套在卡片内部、可用宽度天然很窄的小行（徽标行、成对按钮）专用。
  static const tight = 420.0;

  static const radius = 10.0;
  static const radiusCard = 12.0;
  static const gap = 8.0;
  static const pad = 12.0;

  /// 栅格列数阶梯：1 / 2 / 3 / 4。
  static int columnsFor(double width) {
    if (width < compact) return 1;
    if (width < medium) return 2;
    if (width < wide) return 3;
    return 4;
  }

  /// 是否单列堆叠。所有 stacked / compact 判断都走这里。
  static bool isCompact(double width) => width < compact;

  /// 是否窄于双列上限。
  static bool isMedium(double width) => width < medium;

  /// 嵌套小行是否堆叠。
  static bool isTight(double width) => width < tight;
}

class ProposalStatusChip extends StatelessWidget {
  const ProposalStatusChip({
    super.key,
    required this.label,
    this.kind = ProposalChipKind.normal,
    this.icon,
  });

  final String label;
  final ProposalChipKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, border, color) = switch (kind) {
      ProposalChipKind.ok => (
        DunesColors.resolve(context, ProposalPalette.greenSoft),
        DunesColors.resolve(context, const Color(0xFFC8D5B0)),
        DunesColors.resolve(context, ProposalPalette.green),
      ),
      ProposalChipKind.warn => (
        DunesColors.resolve(context, ProposalPalette.coralSoft),
        DunesColors.resolve(context, const Color(0xFFE7C2B0)),
        DunesColors.resolve(context, ProposalPalette.coral),
      ),
      ProposalChipKind.draft => (
        DunesColors.resolve(context, ProposalPalette.amberSoft),
        DunesColors.resolve(context, const Color(0xFFE0CBA0)),
        DunesColors.resolve(context, ProposalPalette.amber),
      ),
      ProposalChipKind.purple => (
        DunesColors.resolve(context, ProposalPalette.purpleSoft),
        DunesColors.resolve(context, ProposalPalette.purpleLine),
        DunesColors.resolve(context, ProposalPalette.purpleDeep),
      ),
      ProposalChipKind.normal => (
        DunesColors.resolve(context, ProposalPalette.soft),
        DunesColors.resolve(context, ProposalPalette.borderSoft),
        DunesColors.resolve(context, ProposalPalette.text2),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          bg,
          role: DunesColorRole.surface,
        ),
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 13,
              color: DunesColors.resolveNullable(context, color),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: DunesColors.resolveNullable(context, color),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum ProposalChipKind { normal, purple, draft, warn, ok }

ProposalChipKind proposalSkuPlatformStatusChipKind(String raw) {
  return switch (normalizeProposalSkuPlatformStatus(raw)) {
    kProposalSkuPlatformStatusFailed => ProposalChipKind.warn,
    kProposalSkuPlatformStatusCreated => ProposalChipKind.ok,
    kProposalSkuPlatformStatusCreating => ProposalChipKind.purple,
    _ => ProposalChipKind.draft,
  };
}

class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.child,
    this.padding,
    this.margin = const EdgeInsets.only(bottom: 14),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry margin;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    if (ProposalSimpleViewScope.of(context)) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        child: child,
      );
    }
    final narrow = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    final resolvedPadding =
        padding ??
        (narrow ? const EdgeInsets.all(12) : const EdgeInsets.all(18));
    return Container(
      width: double.infinity,
      margin: margin,
      padding: resolvedPadding,
      decoration: BoxDecoration(
        color: gradient == null
            ? DunesColors.resolve(
                context,
                ProposalPalette.card,
                role: DunesColorRole.surface,
              )
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            ProposalPalette.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C4E3A6C),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ProposalSectionTitle extends StatelessWidget {
  const ProposalSectionTitle({
    super.key,
    required this.title,
    required this.tag,
    required this.description,
    this.lighthouse = false,
  });

  final String title;
  final String tag;
  final String description;
  final bool lighthouse;

  @override
  Widget build(BuildContext context) => ProposalSimpleViewScope.readOnlyOf(context)
      ? const SizedBox.shrink()
      : Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = ProposalLayout.isCompact(constraints.maxWidth);
        final heading = Wrap(
          spacing: 10,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text),
                fontSize: stacked ? 17 : 19,
                fontWeight: lighthouse ? FontWeight.w600 : FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  ProposalPalette.purpleSoft,
                  role: DunesColorRole.surface,
                ),
                border: lighthouse
                    ? null
                    : Border.all(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.borderStrong,
                          role: DunesColorRole.border,
                        ),
                      ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag.toUpperCase(),
                style: TextStyle(
                  color: DunesColors.resolve(context, ProposalPalette.purple),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                ),
              ),
            ),
          ],
        );
        final caption = Text(
          description,
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: kProposalCaptionStyle.copyWith(
            color: DunesColors.resolveNullable(
              context,
              kProposalCaptionStyle.color,
            ),
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 6), caption],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            Flexible(child: caption),
          ],
        );
      },
    ),
  );
}

enum ProposalFieldTone { fill, auto, locked }

ProposalFieldTone proposalFieldTone({required bool enabled, String? source}) {
  final tag = (source ?? '').trim();
  if (tag.contains('系统') ||
      tag.contains('当前用户') ||
      tag.contains('管理后台') ||
      tag.contains('合同抓取') ||
      tag.contains('从合同归集') ||
      tag.contains('实时串联')) {
    return ProposalFieldTone.auto;
  }
  // 只读不再套一层 locked 灰底卡片，避免复核页格子虚高。
  return enabled ? ProposalFieldTone.fill : ProposalFieldTone.fill;
}

class ProposalFormulaHint extends StatelessWidget {
  const ProposalFormulaHint({
    super.key,
    required this.formula,
    this.detail = '',
  });

  final String formula;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final extra = detail.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formula,
            style: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
              height: 1.25,
            ),
          ),
          if (extra.isNotEmpty)
            Text(
              extra,
              style: TextStyle(
                color: DunesColors.resolve(context, ProposalPalette.text3),
                fontSize: 10,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
  }
}

class ProposalFormulaQuestionMark extends StatelessWidget {
  const ProposalFormulaQuestionMark({
    super.key,
    required this.title,
    required this.formula,
    this.detail = '',
  });

  final String title;
  final String formula;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '查看测算公式',
      child: InkWell(
        onTap: () => unawaited(
          showProposalCostFormulaHelp(
            context,
            title: title,
            formula: formula,
            substitution: detail,
          ),
        ),
        borderRadius: BorderRadius.circular(10),
        // 小一号的问号：12px 浅紫细圈，不抢名称的位置。
        child: Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(left: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFB9ABEB),
                role: DunesColorRole.border,
              ),
              width: .8,
            ),
          ),
          child: Text(
            '?',
            style: TextStyle(
              color: DunesColors.resolve(context, const Color(0xFF6B4FD8)),
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class ProposalField extends StatelessWidget {
  const ProposalField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.source,
    this.formula,
    this.formulaDetail,
    this.trailing,
    this.footer,
    this.tone,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? source;
  final String? formula;
  final String? formulaDetail;
  final ProposalFieldTone? tone;

  /// 行内复核控件，紧贴字段标签右侧展示。
  final Widget? trailing;

  /// 字段下方补充信息，例如合同改动对照。
  final Widget? footer;

  /// 原型简单行：名称 104px（手机 76px）在左，值在右，行底一条细线。
  /// 行距比原型略紧（上下 4），复核、查看时一屏能多看几行。
  Widget _simpleRow(BuildContext context) {
    final narrow = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    // 只读简单行（复核、查看）：名称一行写完，放不下省略（悬停看全称）。
    // 手机名称列 68px，用短名称（去掉括号说明、「合同核心条款」→「条款」），不再折成两三行。
    final readOnly = ProposalSimpleViewScope.textRowsOf(context);
    final labelWidth = readOnly ? (narrow ? 68.0 : 118.0) : (narrow ? 76.0 : 104.0);
    if (readOnly) {
      return _readOnlyRow(context, labelWidth, narrow: narrow);
    }
    final inGridRow = ProposalGridRowScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: inGridRow
            ? null
            : Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFF3F0F8),
                    role: DunesColorRole.border,
                  ),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFF5B556A),
                    ),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (required)
                  Text(
                    ' *',
                    style: TextStyle(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFFC0563F),
                      ),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                if ((formula ?? '').trim().isNotEmpty)
                  ProposalFormulaQuestionMark(
                    title: label,
                    formula: formula!.trim(),
                    detail: formulaDetail ?? '',
                  ),
              ],
            ),
          ),
          SizedBox(width: narrow ? 8 : 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                child,
                if (footer != null) ...[const SizedBox(height: 6), footer!],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }

  /// 手机上的短名称：「项目（标签一二级）」→「项目」，「采购合同核心条款」→「采购条款」。
  static String compactLabel(String label) {
    var text = label.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '').trim();
    text = text.replaceAll('合同核心条款', '条款').replaceAll('核心条款', '条款');
    return text.isEmpty ? label : text;
  }

  /// 只读行：名称、值、复核标记都在一条 22px 的线上垂直居中，默认一行；
  /// 值展开（长文本、详情）时往下长，名称和复核标记仍贴顶。
  Widget _readOnlyRow(
    BuildContext context,
    double labelWidth, {
    bool narrow = false,
  }) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final shown = narrow ? compactLabel(label) : label;
    final inGridRow = ProposalGridRowScope.of(context);
    const line = kProposalSimpleLineHeight;
    final labelSpan = TextSpan(
      text: shown,
      children: [
        if (required)
          TextSpan(text: ' *', style: TextStyle(color: c(0xFFC0563F))),
      ],
    );
    final baseSize = narrow ? 11.5 : 12.0;
    var labelSize = baseSize;
    final hasFormula = (formula ?? '').trim().isNotEmpty;
    final available = labelWidth - (hasFormula ? 15 : 0);
    final painter = TextPainter(
      text: TextSpan(style: TextStyle(fontSize: baseSize), children: [labelSpan]),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    if (painter.width > available && available > 0) {
      labelSize = (baseSize * available / painter.width)
          .clamp(9.5, baseSize)
          .toDouble();
    }
    painter.dispose();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: narrow ? 3 : 4),
      decoration: BoxDecoration(
        border: inGridRow
            ? null
            : Border(
                bottom: BorderSide(color: c(0xFFF3F0F8, DunesColorRole.border)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            height: line,
            child: Row(
              children: [
                Flexible(
                  child: Tooltip(
                    message: label,
                    waitDuration: const Duration(milliseconds: 600),
                    // 名称放不下时先缩小字号（最小 9.5），还放不下才省略。
                    // 不用 LayoutBuilder：完整表单里这一行可能在 IntrinsicHeight 里，
                    // LayoutBuilder 不支持算固有高度，会让整块排版错乱。
                    child: Text.rich(
                      labelSpan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c(0xFF5B556A),
                        fontSize: labelSize,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                if ((formula ?? '').trim().isNotEmpty)
                  ProposalFormulaQuestionMark(
                    title: label,
                    formula: formula!.trim(),
                    detail: formulaDetail ?? '',
                  ),
              ],
            ),
          ),
          SizedBox(width: narrow ? 6 : 8),
          Expanded(
            child: ClipRect(
              child: Container(
                constraints: const BoxConstraints(minHeight: line),
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    child,
                    if (footer != null) ...[const SizedBox(height: 6), footer!],
                  ],
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: narrow ? 4 : 8),
            Container(
              constraints: const BoxConstraints(minHeight: line),
              alignment: Alignment.centerRight,
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ProposalSimpleViewScope.of(context)) return _simpleRow(context);
    final resolved = tone ?? proposalFieldTone(enabled: true, source: source);
    final (bg, border, chipKind) = switch (resolved) {
      ProposalFieldTone.auto => (
        Colors.transparent,
        Colors.transparent,
        ProposalChipKind.normal,
      ),
      ProposalFieldTone.locked => (
        DunesColors.resolve(context, ProposalPalette.page),
        DunesColors.resolve(context, ProposalPalette.borderStrong),
        ProposalChipKind.draft,
      ),
      ProposalFieldTone.fill => (
        Colors.transparent,
        Colors.transparent,
        ProposalChipKind.purple,
      ),
    };
    // fill 与 auto 都靠输入框自身的 hairline 描边表达，外层不再套底色方块。
    final framed =
        resolved != ProposalFieldTone.fill &&
        resolved != ProposalFieldTone.auto;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              framed ? bg : null,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(10),
            border: framed ? Border.all(color: border) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: DunesColors.resolve(
                          context,
                          ProposalPalette.text3,
                        ),
                        fontSize: 11,
                        letterSpacing: .2,
                      ),
                    ),
                    if (required)
                      Text(
                        '*',
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.coral,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    if ((formula ?? '').trim().isNotEmpty)
                      ProposalFormulaQuestionMark(
                        title: label,
                        formula: formula!.trim(),
                        detail: formulaDetail ?? '',
                      ),
                    if (source != null)
                      ProposalStatusChip(label: source!, kind: chipKind),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 2),
                child,
                if (footer != null) ...[const SizedBox(height: 6), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 逐条复核：可点通过，也可单条驳回；非责任人只显示待复核，避免误以为已有人审过。
class ProposalReviewToggle extends StatelessWidget {
  const ProposalReviewToggle({
    super.key,
    required this.reviewed,
    required this.onPressed,
    this.onReject,
    this.rejected = false,
    this.pendingLabel = '复核',
    this.subtle = false,
  });

  final bool reviewed;
  final bool rejected;
  final VoidCallback? onPressed;
  final VoidCallback? onReject;
  final String pendingLabel;
  final bool subtle;

  /// 原型右侧的复核标记，做成小胶囊：
  /// 只看时「待复核」橙色胶囊（悬停看谁来复核）、「✓ 已复核」绿色胶囊、「已驳回」红色胶囊；
  /// 轮到你复核时「有问题」描边小按钮 +「通过」紫色实心小按钮；复核后「✓ 已复核 · 撤销」。
  Widget _prototype(BuildContext context) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    // 手机上胶囊、按钮都收窄，给值多留位置。
    final narrow = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
    Widget pill(String text, int bg, int fg, {String? tip}) {
      final chip = Container(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 6 : 8, vertical: 2),
        decoration: BoxDecoration(
          color: c(bg, DunesColorRole.surface),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: narrow ? 10.5 : 11,
            height: 1.3,
            fontWeight: FontWeight.w500,
            color: c(fg),
          ),
        ),
      );
      return tip == null || tip.isEmpty
          ? chip
          : Tooltip(message: tip, child: chip);
    }

    final done = pill(narrow ? '✓ 已核' : '✓ 已复核', 0xFFE6F3EB, 0xFF2D6E47);
    if (onPressed == null) {
      if (reviewed) return done;
      if (rejected) return pill('已驳回', 0xFFFBE9E7, 0xFFB42318);
      // 待复核：淡紫胶囊（不再用橙色）。
      return pill(
        narrow ? '待核' : '待复核',
        0xFFF1ECFF,
        0xFF5B3FD0,
        tip: pendingLabel.startsWith('待') ? pendingLabel : '待$pendingLabel',
      );
    }
    ButtonStyle small({required bool primary}) => OutlinedButton.styleFrom(
      minimumSize: const Size(0, kProposalSimpleLineHeight),
      padding: EdgeInsets.symmetric(horizontal: narrow ? 7 : 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      foregroundColor: c(primary ? 0xFFFFFFFF : 0xFF9A4A0C),
      backgroundColor: c(
        primary ? 0xFF6B4FD8 : 0xFFFFFFFF,
        DunesColorRole.surface,
      ),
      side: primary
          ? BorderSide.none
          : BorderSide(color: c(0xFFF0C9A0, DunesColorRole.border)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      textStyle: TextStyle(
        fontSize: narrow ? 11 : 12,
        fontWeight: FontWeight.w700,
      ),
    );
    if (reviewed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          done,
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, kProposalSimpleLineHeight),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              foregroundColor: c(0xFF8A8499),
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: const Text('撤销'),
          ),
        ],
      );
    }
    return Wrap(
      spacing: narrow ? 4 : 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rejected) pill('已驳回', 0xFFFBE9E7, 0xFFB42318),
        if (onReject != null)
          OutlinedButton(
            onPressed: onReject,
            style: small(primary: false),
            child: const Text('有问题'),
          ),
        OutlinedButton(
          onPressed: onPressed,
          style: small(primary: true),
          child: const Text('通过'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ProposalSimpleViewScope.of(context)) return _prototype(context);
    final canAct = onPressed != null;
    if (!canAct) {
      final label = reviewed
          ? '已复核'
          : rejected
          ? '已驳回'
          : pendingLabel;
      if (subtle) {
        final color = reviewed
            ? DunesColors.resolve(context, ProposalPalette.green)
            : rejected
            ? DunesColors.resolve(context, const Color(0xFFB42318))
            : DunesColors.resolve(context, ProposalPalette.text3);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reviewed || rejected) ...[
              Icon(
                reviewed ? Icons.check_rounded : Icons.error_outline_rounded,
                size: 12,
                color: DunesColors.resolveNullable(context, color),
              ),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                color: DunesColors.resolveNullable(context, color),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }
      final chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: reviewed
              ? DunesColors.resolve(
                  context,
                  ProposalPalette.greenSoft,
                  role: DunesColorRole.surface,
                )
              : rejected
              ? DunesColors.resolve(
                  context,
                  const Color(0xFFF8E8E8),
                  role: DunesColorRole.surface,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.page,
                  role: DunesColorRole.surface,
                ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: reviewed
                ? DunesColors.resolve(
                    context,
                    ProposalPalette.green,
                    role: DunesColorRole.border,
                  )
                : rejected
                ? DunesColors.resolve(
                    context,
                    const Color(0xFFD9A3A3),
                    role: DunesColorRole.border,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.borderStrong,
                    role: DunesColorRole.border,
                  ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: reviewed
                ? DunesColors.resolve(context, ProposalPalette.green)
                : rejected
                ? DunesColors.resolve(context, const Color(0xFFB42318))
                : DunesColors.resolve(context, ProposalPalette.text3),
          ),
        ),
      );
      return chip;
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: reviewed
                ? DunesColors.resolve(
                    context,
                    ProposalPalette.greenSoft,
                    role: DunesColorRole.surface,
                  )
                : DunesColors.resolve(
                    context,
                    ProposalPalette.purpleSoft,
                    role: DunesColorRole.surface,
                  ),
            foregroundColor: reviewed
                ? DunesColors.resolve(context, ProposalPalette.green)
                : DunesColors.resolve(context, ProposalPalette.purpleDeep),
            side: BorderSide(
              color: reviewed
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.green,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      ProposalPalette.purple,
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                reviewed ? Icons.check_rounded : Icons.task_alt_rounded,
                size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                reviewed ? '已复核' : '点此复核',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        if (onReject != null)
          OutlinedButton(
            onPressed: onReject,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: DunesColors.resolve(
                context,
                const Color(0xFFB42318),
              ),
              side: BorderSide(
                color: DunesColors.resolve(
                  context,
                  Color(0xFFD9A3A3),
                  role: DunesColorRole.border,
                ),
              ),
            ),
            child: const Text('驳回', style: TextStyle(fontSize: 11)),
          ),
      ],
    );
  }
}

/// 提案页面的提示统一显示在屏幕中间，避免底部提示被表单遮挡。
void showProposalCenterToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!overlay.mounted) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: _ProposalCenterToast(message: message, error: error),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(milliseconds: 2000), () {
      if (entry.mounted) entry.remove();
    });
  });
}

Future<String?> showProposalRejectDialog({
  required BuildContext context,
  required String title,
  required String hint,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return null;
  final result = await showGeneralDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, _, __) {
      return MediaQuery.removeViewInsets(
        context: ctx,
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                type: MaterialType.transparency,
                child: _ProposalRejectDialog(title: title, hint: hint),
              ),
            ),
          ),
        ),
      );
    },
  );
  await WidgetsBinding.instance.endOfFrame;
  return result;
}

class _ProposalRejectDialog extends StatefulWidget {
  const _ProposalRejectDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_ProposalRejectDialog> createState() => _ProposalRejectDialogState();
}

class _ProposalRejectDialogState extends State<_ProposalRejectDialog> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 4,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('取消')),
        FilledButton(
          onPressed: () => _close(_controller.text.trim()),
          child: const Text('确认驳回'),
        ),
      ],
    );
  }
}

class _ProposalCenterToast extends StatefulWidget {
  const _ProposalCenterToast({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  State<_ProposalCenterToast> createState() => _ProposalCenterToastState();
}

class _ProposalCenterToastState extends State<_ProposalCenterToast> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 160),
        child: AnimatedScale(
          scale: _opacity == 0 ? .96 : 1,
          duration: const Duration(milliseconds: 160),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: widget.error
                  ? DunesColors.resolve(
                      context,
                      ProposalPalette.coral,
                      role: DunesColorRole.surface,
                    )
                  : DunesColors.resolve(
                      context,
                      ProposalPalette.purpleDeep,
                      role: DunesColorRole.surface,
                    ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x332B2340),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.error
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: DunesColors.resolve(context, Colors.white),
                  size: 18,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: DunesColors.resolve(context, Colors.white),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                      decorationColor: Colors.transparent,
                    ),
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

InputDecoration proposalInputDecoration({
  BuildContext? context,
  String? hint,
  bool readOnly = false,
  ProposalFieldTone tone = ProposalFieldTone.fill,
}) {
  if (context != null && ProposalSimpleViewScope.of(context)) {
    // 原型：无外框，底部紫色虚线；聚焦变紫色实线。
    return DunesColors.inputDecoration(
      context,
      InputDecoration(
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: const TextStyle(
          fontSize: 12,
          height: 1.2,
          color: ProposalPalette.text3,
        ),
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
        enabledBorder: const ProposalDashedUnderlineBorder(),
        disabledBorder: const ProposalDashedUnderlineBorder(
          borderSide: BorderSide(color: Color(0xFFE7E3F2)),
        ),
        focusedBorder: const ProposalDashedUnderlineBorder(
          borderSide: BorderSide(color: Color(0xFF6B4FD8), width: 1.5),
          dashed: false,
        ),
        border: const ProposalDashedUnderlineBorder(),
      ),
    );
  }
  final fillColor = switch (tone) {
    ProposalFieldTone.auto =>
      readOnly ? ProposalPalette.app : ProposalPalette.card,
    ProposalFieldTone.locked => ProposalPalette.app,
    ProposalFieldTone.fill =>
      readOnly ? ProposalPalette.app : ProposalPalette.card,
  };
  return DunesColors.inputDecoration(
    context,
    InputDecoration(
      hintText: hint,
      hintMaxLines: 1,
      hintStyle: const TextStyle(
        fontSize: 12,
        height: 1.2,
        color: ProposalPalette.text3,
      ),
      filled: true,
      fillColor: fillColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ProposalPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ProposalPalette.purpleLine),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ProposalPalette.borderSoft),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class ProposalChoiceChip extends StatelessWidget {
  const ProposalChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool enabled;

  /// 选中态比底色深一档，边框一起压深，避免和白底糊在一起。
  static const selectedFill = Color(0xFFD5DEE9);
  static const selectedBorder = Color(0xFFA9B6C8);

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && onSelected != null;
    final background = !enabled
        ? (selected
              ? DunesColors.resolve(
                  context,
                  const Color(0xFFD0D5DE),
                  role: DunesColorRole.surface,
                )
              : DunesColors.resolve(
                  context,
                  ProposalPalette.page,
                  role: DunesColorRole.surface,
                ))
        : (selected
              ? selectedFill
              : DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ));
    final foreground = enabled
        ? DunesColors.resolve(context, ProposalPalette.text)
        : DunesColors.resolve(context, ProposalPalette.text3);
    final border = selected
        ? (enabled
              ? selectedBorder
              : DunesColors.resolve(
                  context,
                  ProposalPalette.text4,
                  role: DunesColorRole.border,
                ))
        : DunesColors.resolve(
            context,
            ProposalPalette.text4,
            role: DunesColorRole.border,
          );
    return Material(
      color: DunesColors.resolveNullable(
        context,
        background,
        role: DunesColorRole.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            border,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: canTap ? () => onSelected!(!selected) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: DunesColors.resolveNullable(context, foreground),
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class ProposalPills extends StatelessWidget {
  const ProposalPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.single = false,
    this.onAdd,
    this.enabled = true,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool single;
  final VoidCallback? onAdd;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !enabled,
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final option in options)
          ProposalChoiceChip(
            label: option,
            selected: selected.contains(option),
            enabled: enabled,
            onSelected: (_) => onToggle(option),
          ),
        if (onAdd != null)
          ActionChip(
            label: const Text('+ 新增'),
            onPressed: enabled ? onAdd : null,
            backgroundColor: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            side: BorderSide(
              color: DunesColors.resolve(
                context,
                ProposalPalette.border,
                role: DunesColorRole.border,
              ),
              style: BorderStyle.solid,
            ),
            labelStyle: TextStyle(
              color: DunesColors.resolve(context, ProposalPalette.text3),
              fontSize: 11,
            ),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ],
    ),
  );
}

class ProposalPresidentDecisionBar extends StatelessWidget {
  const ProposalPresidentDecisionBar({
    super.key,
    required this.onApprove,
    required this.onReject,
    this.prototype = false,
  });

  final VoidCallback onApprove;
  final VoidCallback onReject;

  /// 原型样式：白底、左边一句提示，右边「驳回」（橙框）与「确认通过」（紫色，宽一倍）。
  final bool prototype;

  Widget _prototypeBar(BuildContext context) {
    const height = 48.0;
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final reject = OutlinedButton(
      key: const ValueKey('proposal-president-reject'),
      onPressed: onReject,
      style: OutlinedButton.styleFrom(
        foregroundColor: c(0xFF9A3412),
        backgroundColor: c(0xFFFFFFFF, DunesColorRole.surface),
        side: BorderSide(color: c(0xFFF0C9A0, DunesColorRole.border)),
        minimumSize: const Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: const Text(
        '驳回',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
    final approve = FilledButton(
      key: const ValueKey('proposal-president-approve'),
      onPressed: onApprove,
      style: FilledButton.styleFrom(
        backgroundColor: c(0xFF6B4FD8, DunesColorRole.surface),
        foregroundColor: c(0xFFFFFFFF),
        minimumSize: const Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: const Text(
        '确认通过',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
    final hint = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '待你最终确认',
            style: TextStyle(color: c(0xFF3F2A9A), fontWeight: FontWeight.w700),
          ),
          const TextSpan(text: ' · 各板块已复核完，内容已锁定'),
        ],
      ),
      style: TextStyle(color: c(0xFF5B556A), fontSize: 12),
    );
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c(0xFFFFFFFF, DunesColorRole.surface),
          border: Border(
            top: BorderSide(color: c(0xFFE7E3F2, DunesColorRole.border)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F3C2878),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (context, box) {
                  final buttons = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 160, child: reject),
                      const SizedBox(width: 10),
                      SizedBox(width: 260, child: approve),
                    ],
                  );
                  if (box.maxWidth >= 680) {
                    return Row(
                      children: [
                        Expanded(child: hint),
                        const SizedBox(width: 10),
                        buttons,
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hint,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: reject),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: approve),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (prototype) return _prototypeBar(context);
    const height = 48.0;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            ProposalPalette.app,
            role: DunesColorRole.surface,
          ),
          border: Border(
            top: BorderSide(
              color: DunesColors.resolve(
                context,
                ProposalPalette.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最终确认',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, ProposalPalette.text2),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('proposal-president-reject'),
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DunesColors.resolve(
                          context,
                          ProposalPalette.coral,
                        ),
                        side: BorderSide(
                          color: DunesColors.resolve(
                            context,
                            Color(0xFFE7C2B0),
                            role: DunesColorRole.border,
                          ),
                        ),
                        minimumSize: const Size(0, height),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text(
                        '驳回',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('proposal-president-approve'),
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: DunesColors.resolve(
                          context,
                          ProposalPalette.purpleDeep,
                          role: DunesColorRole.surface,
                        ),
                        foregroundColor: DunesColors.resolve(
                          context,
                          Colors.white,
                        ),
                        minimumSize: const Size(0, height),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text(
                        '确认通过',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProposalModuleConfirmBar extends StatelessWidget {
  const ProposalModuleConfirmBar({
    super.key,
    required this.onConfirm,
    this.title = '逐条已完成，还差最后一步',
    this.message = '点「确认本板块通过」才算科技复核结束。保存只是存内容，不会过关。',
    this.confirmLabel = '确认本板块通过',
    this.prototype = false,
  });

  /// 原型复核页底部条：左边提示，右边紫色「确认本板块通过」。
  final bool prototype;

  final VoidCallback onConfirm;
  final String title;
  final String message;
  final String confirmLabel;

  Widget _prototypeBar(BuildContext context) {
    Color c(int v, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, Color(v), role: role);
    final button = FilledButton(
      key: const ValueKey('proposal-module-confirm-bar'),
      onPressed: onConfirm,
      style: FilledButton.styleFrom(
        backgroundColor: c(0xFF6B4FD8, DunesColorRole.surface),
        foregroundColor: c(0xFFFFFFFF),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Text(confirmLabel),
    );
    final hint = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style: TextStyle(color: c(0xFF2D6E47), fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · $message'),
        ],
      ),
      style: TextStyle(color: c(0xFF5B556A), fontSize: 12),
    );
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c(0xFFFFFFFF, DunesColorRole.surface),
          border: Border(top: BorderSide(color: c(0xFFE7E3F2, DunesColorRole.border))),
          boxShadow: const [
            BoxShadow(color: Color(0x0F3C2878), blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 640
                    ? Row(
                        children: [
                          Expanded(child: hint),
                          const SizedBox(width: 10),
                          button,
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [hint, const SizedBox(height: 8), button],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (prototype) return _prototypeBar(context);
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DunesColors.resolveNullable(
            context,
            Color(0xFFECF8EE),
            role: DunesColorRole.surface,
          ),
          border: Border(
            top: BorderSide(
              color: DunesColors.resolve(
                context,
                Color(0xFFB9DDBE),
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolve(context, ProposalPalette.green),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF3E6B46),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  key: const ValueKey('proposal-module-confirm-bar'),
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: DunesColors.resolve(
                      context,
                      ProposalPalette.green,
                      role: DunesColorRole.surface,
                    ),
                    foregroundColor: DunesColors.resolve(context, Colors.white),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProposalNextPendingFooter extends StatelessWidget {
  const ProposalNextPendingFooter({
    super.key,
    required this.totalCount,
    required this.onPressed,
    this.loading = false,
  });

  final int totalCount;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const label = '下一个';
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            ProposalPalette.app,
            role: DunesColorRole.surface,
          ),
          border: Border(
            top: BorderSide(
              color: DunesColors.resolve(
                context,
                ProposalPalette.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: loading ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.resolve(
                  context,
                  ProposalPalette.purpleDeep,
                  role: DunesColorRole.surface,
                ),
                disabledBackgroundColor: DunesColors.resolve(
                  context,
                  ProposalPalette.purpleSoft,
                  role: DunesColorRole.surface,
                ),
              ),
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(loading ? '加载中…' : label),
            ),
          ),
        ),
      ),
    );
  }
}

const proposalIntakeProcessSteps = <(String, String)>[
  ('1', '提交人新建提案，填写市场、合同、财务、科技与产品，并指定科技部负责人等审核人。'),
  ('2', '提交人通知财务部负责人二填写财务技术接口。'),
  ('3', '填写人完成科技与产品后提交复核（必选财务技术接口须已勾选）。'),
  ('4', '提交人提交各板块进入复核。'),
  (
    '5',
    '市场部负责人一复核市场板块；科技部负责人复核科技（含财务技术接口）并对业务平台产品整板块复核，底部确认前会检查遗漏；财务部负责人二复核采购/销售合同并逐条复核财务，财务部负责人一整板块复核财务。发现问题可对单条点「驳回」，也可直接整板块驳回，不必先逐条点完复核。',
  ),
  ('6', '各板块复核完成后，提交人通知最终确认人。'),
  ('7', '最终确认人通过即完成；整单驳回则退回提交人重填。板块驳回后，填写人修改再点「重新提交并通知审核人」，系统会通知该板块审核人。'),
];

const proposalIntakePurchaseProcessSteps = <(String, String)>[
  (
    '1',
    '提交人新建采购提案，填写供给、采购合同、科技与产品，并指定科技部负责人、市场部负责人一、二等审核人，以及财务部负责人一、二（财务板块暂不复核）。',
  ),
  ('2', '提交人通知财务部负责人二填写财务技术接口。'),
  ('3', '填写人完成科技与产品后提交复核（必选财务技术接口须已勾选）。'),
  ('4', '提交人提交各板块进入复核。'),
  (
    '5',
    '市场部负责人一复核市场板块，并可填写 HUN ID；科技部负责人复核科技（含财务技术接口）并对业务平台产品整板块复核，底部确认前会检查遗漏；财务部负责人二复核采购合同。财务板块暂不复核。发现问题可对单条点「驳回」，也可直接整板块驳回，不必先逐条点完复核。',
  ),
  ('6', '各板块复核完成后，提交人通知最终确认人。'),
  ('7', '最终确认人通过即完成；整单驳回则退回提交人重填。板块驳回后，填写人修改再点「重新提交并通知审核人」，系统会通知该板块审核人。'),
];

List<(String, String)> proposalIntakeProcessStepsOf({required bool purchase}) =>
    purchase ? proposalIntakePurchaseProcessSteps : proposalIntakeProcessSteps;

Future<void> showProposalIntakeProcessHelp(
  BuildContext context, {
  bool purchase = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final maxWidth = MediaQuery.sizeOf(ctx).width - 48;
      final steps = proposalIntakeProcessStepsOf(purchase: purchase);
      return AlertDialog(
        title: const Text('协作提案流程'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        content: SizedBox(
          width: maxWidth < 420 ? maxWidth : 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: DunesColors.resolve(
                              ctx,
                              ProposalPalette.purpleSoft,
                              role: DunesColorRole.surface,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            step.$1,
                            style: TextStyle(
                              color: DunesColors.resolve(
                                ctx,
                                ProposalPalette.purpleDeep,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step.$2,
                            style: TextStyle(
                              color: DunesColors.resolve(
                                ctx,
                                ProposalPalette.text,
                              ),
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    '催办与转发',
                    style: TextStyle(
                      color: DunesColors.resolve(ctx, ProposalPalette.text),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '「催办」只把当前待办再发一次到审批助手，不改变提案阶段。\n'
                  '「转发」自己选会话，把提案名片发出去，不经过审批助手，也不推进流程。\n'
                  '点「通知财务填写 / 提交复核 / 通知最终人」仍走审批助手，那是第一次派发流程待办。',
                  style: TextStyle(
                    color: DunesColors.resolve(ctx, ProposalPalette.text),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}

Future<void> showProposalCostFormulaHelp(
  BuildContext context, {
  required String title,
  required String formula,
  String substitution = '',
}) {
  Widget body(BuildContext ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: DunesColors.resolve(ctx, ProposalPalette.text),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '测算公式',
          style: TextStyle(
            color: DunesColors.resolve(ctx, ProposalPalette.text3),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          formula,
          style: TextStyle(
            color: DunesColors.resolve(ctx, ProposalPalette.text),
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (substitution.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '代入当前值',
            style: TextStyle(
              color: DunesColors.resolve(ctx, ProposalPalette.text3),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            substitution,
            style: TextStyle(
              color: DunesColors.resolve(ctx, ProposalPalette.purpleDeep),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ),
      ],
    );
  }

  final narrow = ProposalLayout.isCompact(MediaQuery.sizeOf(context).width);
  if (narrow) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            12 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: SingleChildScrollView(child: body(ctx)),
        );
      },
    );
  }
  final maxWidth = MediaQuery.sizeOf(context).width - 48;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('测算公式'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        content: SizedBox(
          width: maxWidth < 420 ? maxWidth : 420,
          child: SingleChildScrollView(child: body(ctx)),
        ),
      );
    },
  );
}

class ProposalCostFormulaHelpButton extends StatelessWidget {
  const ProposalCostFormulaHelpButton({
    super.key,
    required this.title,
    required this.formula,
    this.substitution = '',
  });

  final String title;
  final String formula;
  final String substitution;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '查看测算公式',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: () => unawaited(
        showProposalCostFormulaHelp(
          context,
          title: title,
          formula: formula,
          substitution: substitution,
        ),
      ),
      icon: Icon(
        Icons.functions_outlined,
        size: 18,
        color: DunesColors.resolve(context, ProposalPalette.purpleDeep),
      ),
    );
  }
}

class ProposalIntakeProcessHelpButton extends StatelessWidget {
  const ProposalIntakeProcessHelpButton({
    super.key,
    this.compact = false,
    this.purchase = false,
  });

  final bool compact;
  final bool purchase;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '协作提案流程',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: compact ? 36 : 40,
        minHeight: compact ? 36 : 40,
      ),
      onPressed: () =>
          unawaited(showProposalIntakeProcessHelp(context, purchase: purchase)),
      icon: Icon(
        Icons.help_outline_rounded,
        size: compact ? 20 : 22,
        color: DunesColors.resolve(context, ProposalPalette.purpleDeep),
      ),
    );
  }
}

class ProposalIntakeProgressTimeline extends StatefulWidget {
  const ProposalIntakeProgressTimeline({
    super.key,
    required this.steps,
    this.compact = false,
    this.initiallyExpanded = false,
  });

  final List<ProposalIntakeProgressStep> steps;
  final bool compact;
  final bool initiallyExpanded;

  @override
  State<ProposalIntakeProgressTimeline> createState() =>
      _ProposalIntakeProgressTimelineState();
}

class _ProposalIntakeProgressTimelineState
    extends State<ProposalIntakeProgressTimeline> {
  static const _line = Color(0xFF5BB8A8);
  static const _lineSoft = Color(0xFFD8EDE8);
  static const _pending = ProposalPalette.text4;

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(ProposalIntakeProgressTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded && !oldWidget.initiallyExpanded) {
      _expanded = true;
    }
  }

  bool _isOpen(ProposalIntakeProgressStep step) {
    if (step.state == ProposalIntakeProgressState.current ||
        step.state == ProposalIntakeProgressState.rejected) {
      return true;
    }
    return step.id == 'end' && step.state == ProposalIntakeProgressState.done;
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final compact = widget.compact;
    final headline = proposalIntakeProgressHeadline(steps);
    final visible = [
      for (final step in steps)
        if (_expanded || _isOpen(step)) step,
    ];
    final hidden = steps.length - visible.length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12, bottom: 14),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            ProposalPalette.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 16,
              10,
              compact ? 14 : 16,
              10,
            ),
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                ProposalPalette.page,
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '审批进度',
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.text2,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (headline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          headline,
                          style: TextStyle(
                            color: DunesColors.resolve(
                              context,
                              ProposalPalette.text3,
                            ),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hidden > 0 || _expanded)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '收起步骤' : '查看全部步骤'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 16,
              14,
              compact ? 14 : 16,
              12,
            ),
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++)
                  _ProposalProgressRow(
                    step: visible[i],
                    isLast: i == visible.length - 1,
                    compact: compact,
                    line: _line,
                    lineSoft: _lineSoft,
                    pending: _pending,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalProgressRow extends StatelessWidget {
  const _ProposalProgressRow({
    required this.step,
    required this.isLast,
    required this.compact,
    required this.line,
    required this.lineSoft,
    required this.pending,
  });

  final ProposalIntakeProgressStep step;
  final bool isLast;
  final bool compact;
  final Color line;
  final Color lineSoft;
  final Color pending;

  bool get _active =>
      step.state == ProposalIntakeProgressState.done ||
      step.state == ProposalIntakeProgressState.current ||
      step.state == ProposalIntakeProgressState.rejected;

  Color get _accent {
    return switch (step.state) {
      ProposalIntakeProgressState.rejected => ProposalPalette.coral,
      ProposalIntakeProgressState.pending => pending,
      ProposalIntakeProgressState.current => line,
      ProposalIntakeProgressState.done => line,
    };
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (step.state) {
      ProposalIntakeProgressState.done => line,
      ProposalIntakeProgressState.current => DunesColors.resolve(
        context,
        ProposalPalette.purpleDeep,
      ),
      ProposalIntakeProgressState.rejected => DunesColors.resolve(
        context,
        ProposalPalette.coral,
      ),
      ProposalIntakeProgressState.pending => DunesColors.resolve(
        context,
        ProposalPalette.text3,
      ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _ProposalProgressDot(
                  state: step.state,
                  isEnd: step.id == 'end',
                  color: _accent,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: DunesColors.resolveNullable(
                        context,
                        _active ? line : lineSoft,
                        role: DunesColorRole.surface,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 2 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              step.title,
                              style: TextStyle(
                                color:
                                    step.state ==
                                        ProposalIntakeProgressState.pending
                                    ? DunesColors.resolve(
                                        context,
                                        ProposalPalette.text3,
                                      )
                                    : DunesColors.resolve(
                                        context,
                                        ProposalPalette.text,
                                      ),
                                fontSize: compact ? 13 : 14,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            if (step.id == 'initiate' &&
                                step.statusText.isNotEmpty &&
                                step.state != ProposalIntakeProgressState.done)
                              Text(
                                step.statusText,
                                style: TextStyle(
                                  color: DunesColors.resolveNullable(
                                    context,
                                    statusColor,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (step.time.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            step.time,
                            style: TextStyle(
                              color:
                                  step.state ==
                                      ProposalIntakeProgressState.current
                                  ? DunesColors.resolve(
                                      context,
                                      ProposalPalette.purpleDeep,
                                    )
                                  : DunesColors.resolve(
                                      context,
                                      ProposalPalette.text3,
                                    ),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (step.id != 'initiate' &&
                      (step.name.isNotEmpty ||
                          step.action.isNotEmpty ||
                          step.statusText.isNotEmpty)) ...[
                    const SizedBox(height: 3),
                    if (step.action.isNotEmpty)
                      Text(
                        step.action,
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            ProposalPalette.text3,
                          ),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    if (step.name.isNotEmpty || step.statusText.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          top: step.action.isNotEmpty ? 1 : 0,
                        ),
                        child: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (step.name.isNotEmpty)
                              Text(
                                step.name,
                                style: TextStyle(
                                  color:
                                      step.state ==
                                          ProposalIntakeProgressState.pending
                                      ? DunesColors.resolve(
                                          context,
                                          ProposalPalette.text3,
                                        )
                                      : DunesColors.resolve(
                                          context,
                                          ProposalPalette.text,
                                        ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            if (step.statusText.isNotEmpty)
                              Text(
                                step.statusText,
                                style: TextStyle(
                                  color: DunesColors.resolveNullable(
                                    context,
                                    statusColor,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalProgressDot extends StatelessWidget {
  const _ProposalProgressDot({
    required this.state,
    required this.isEnd,
    required this.color,
  });

  final ProposalIntakeProgressState state;
  final bool isEnd;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pending = state == ProposalIntakeProgressState.pending;
    if (isEnd) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: pending
              ? DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                )
              : color,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: pending
            ? DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              )
            : color,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.6),
      ),
      child: Icon(
        state == ProposalIntakeProgressState.rejected
            ? Icons.close
            : Icons.person,
        size: 13,
        color: pending ? color : DunesColors.resolve(context, Colors.white),
      ),
    );
  }
}

/// 结算比例只填小数（如 `0.08`），不允许输入 `%` / `％`。
class ProposalSettleRatioFormatter extends TextInputFormatter {
  const ProposalSettleRatioFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains('%') || newValue.text.contains('％')) {
      return oldValue;
    }
    final buffer = StringBuffer();
    var hasDot = false;
    for (final rune in newValue.text.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '.' && !hasDot) {
        hasDot = true;
        buffer.write(ch);
      } else if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
        buffer.write(ch);
      }
    }
    final text = buffer.toString();
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}


/// 原型简单行的值：默认一行，放不下时末尾给「展开」，点开看全文、可复制，再点「收起」。
/// 长文本拆成条目：先按「 · 」拆；只有一段时按「；」「;」、再按「。」分句（标点留在句尾）。
List<String> proposalBulletItems(String text) {
  List<String> clean(Iterable<String> parts) => [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
  final byDot = clean(text.split(' · '));
  if (byDot.length > 1) return byDot;
  final bySemi = clean(text.split(RegExp(r'[；;]')));
  if (bySemi.length > 1) return bySemi;
  final bySentence = clean(
    RegExp(r'[^。！？!?]+[。！？!?]?').allMatches(text).map((m) => m[0]!),
  );
  return bySentence.isEmpty ? [text] : bySentence;
}

class ProposalOneLineText extends StatefulWidget {
  const ProposalOneLineText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<ProposalOneLineText> createState() => _ProposalOneLineTextState();
}

class _ProposalOneLineTextState extends State<ProposalOneLineText> {
  bool _open = false;

  @override
  void didUpdateWidget(covariant ProposalOneLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _open = false;
  }

  Widget _toggle(String label) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, const Color(0xFF5B3FD0)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth.isFinite ? box.maxWidth : 10000);
        final overflow = painter.didExceedMaxLines;
        painter.dispose();
        if (!overflow) {
          return Text(widget.text, maxLines: 1, style: style);
        }
        if (_open) {
          // 展开后按条目排成「• 一条一行」：先按「 · 」分，只有一段时再按「；」「。」分句。
          final items = proposalBulletItems(widget.text);
          if (items.length <= 1) {
            return Text.rich(
              TextSpan(
                text: widget.text,
                style: style,
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _toggle('收起'),
                  ),
                ],
              ),
            );
          }
          final dotColor = DunesColors.resolve(
            context,
            const Color(0xFF8E7BE0),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 小圆点：4px，和第一行文字垂直居中。
                      SizedBox(
                        width: 10,
                        height: (style.fontSize ?? 13) * (style.height ?? 1.35),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: i == items.length - 1
                            ? Text.rich(
                                TextSpan(
                                  text: items[i],
                                  style: style,
                                  children: [
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: _toggle('收起'),
                                    ),
                                  ],
                                ),
                              )
                            : Text(items[i], style: style),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            _toggle('展开'),
          ],
        );
      },
    );
  }
}

/// 对照合同抓取原文和改后内容。原文可能很长，内容区必须能滚动，否则会溢出黄条。
class ProposalContractDiffDialog extends StatelessWidget {
  const ProposalContractDiffDialog({
    super.key,
    required this.label,
    required this.original,
    required this.current,
  });

  final String label;
  final String original;
  final String current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('查看「$label」改动'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '合同匹配原文',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                original.isEmpty ? '（空）' : original,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
              Text(
                '确认后的内容',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, ProposalPalette.text3),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                current.isEmpty ? '（空）' : current,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
