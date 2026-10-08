import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'proposal_intake_ui.dart';

/// 查看/审批态只读值下方的紫色虚线开关。关掉后只读值与改动前完全一致。
const kProposalViewUnderlineEnabled = true;

/// 销售、采购提案的填写、复核、查看统一换成原型样式（行式字段、虚线输入框、
/// 「有问题 / 通过」、板块审核横幅、业务平台产品行、评论配色、标签页）。
/// 关掉后页面与改动前完全一致。
const kProposalPrototypeFormEnabled = true;

/// 原型「填报内容」简单行：复核中、待最终确认、已完成都用简单行
/// （一行一条；负责人、合同、盈利模式、研发、供给侧/渠道侧合成一行；没填的选填项不显示）。
/// 复核中可点「完整表单」切回原表单修改。关掉后与改动前完全一致。
const kProposalSimpleViewEnabled = true;

/// 本地联调时把当前登录人当成总裁，用来看「待你最终确认」那条。
/// 只在访问 127.0.0.1 / localhost 时生效。关掉后与改动前完全一致。
const kProposalLocalPresidentMock = true;

/// 当前登录人是否按本地总裁 mock 处理。正式环境 [localHost] 为 false，不会生效。
bool proposalIntakeMockPresident(
  int userId, {
  required bool enabled,
  required bool localHost,
}) =>
    enabled && localHost && userId > 0;

/// 只读值下方画一条紫色虚线，让查看、复核、最终确认时的字段与填写态看起来一致。
/// 只加 3px 底部留白和一条线，不改文字本身。
class ProposalDashedUnderline extends StatelessWidget {
  const ProposalDashedUnderline({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = DunesColors.resolve(
      context,
      ProposalPalette.purpleLine.withValues(alpha: .55),
      role: DunesColorRole.border,
    );
    return CustomPaint(
      key: const ValueKey('proposal-view-underline'),
      foregroundPainter: _DashedLinePainter(color),
      child: Padding(padding: const EdgeInsets.only(bottom: 3), child: child),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height - .5;
    const dash = 4.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      final end = (x + dash).clamp(0.0, size.width).toDouble();
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
