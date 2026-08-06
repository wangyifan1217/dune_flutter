import 'package:flutter/material.dart';

import 'proposal_upload_config.dart';
import 'xflow_form_styles.dart';

enum XflowApprovalFlowStepState { pending, current, done, rejected }

/// 销售提案上传页一致的审批流程区块（提交前预览）。
class XflowApprovalFlowSection extends StatelessWidget {
  const XflowApprovalFlowSection({
    super.key,
    required this.stages,
    this.layout = const {},
    this.onStageHelp,
    this.topSpacing = 18,
    this.pendingStatusLabel = '待发起',
    this.showHeader = true,
    this.userNames = const {},
    this.emptyHint,
  });

  final List<Map<String, dynamic>> stages;
  final Map<String, dynamic> layout;
  final Future<void> Function(int stageIndex)? onStageHelp;
  final double topSpacing;
  final String pendingStatusLabel;
  final bool showHeader;
  final Map<int, String> userNames;

  /// 预览失败等场景的空态文案；勿回退模板全量 stages。
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final rows = _buildStageRows();
    final stageCount = rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topSpacing > 0) SizedBox(height: topSpacing),
        if (showHeader) ...[
          XflowApprovalFlowBadge(
            label: '审批流程',
            subLabel: stageCount > 0 ? '$stageCount-STEP FLOW' : 'NO STAGES',
          ),
          const SizedBox(height: 10),
        ],
        XflowApprovalFlowCard(
          children: rows.isEmpty
              ? [
                  Text(
                    (emptyHint != null && emptyHint!.trim().isNotEmpty)
                        ? emptyHint!.trim()
                        : '未配置审批阶段，请在模板设计器「审批阶段」中维护',
                    style: const TextStyle(
                      fontSize: 11,
                      color: XfProposalUi.mute,
                      height: 1.5,
                    ),
                  ),
                ]
              : rows,
        ),
      ],
    );
  }

  List<Widget> _buildStageRows() {
    final flow = layout['approvalFlow'];
    final prefix = _stageExtras(flow is Map ? flow['prefix'] : null);
    final suffix = _stageExtras(flow is Map ? flow['suffix'] : null);
    if (stages.isEmpty && prefix.isEmpty && suffix.isEmpty) {
      return const [];
    }

    final rows = <Widget>[];
    var stepNo = 1;
    final total = prefix.length + stages.length + suffix.length;

    for (final stage in prefix) {
      rows.add(
        _FlowPreviewRow(
          stepNo: stepNo,
          title: (stage['stageName'] ?? '阶段').toString(),
          meta: (stage['meta'] ?? '系统自动').toString(),
          statusLabel: pendingStatusLabel,
          state: XflowApprovalFlowStepState.pending,
          isLast: stepNo == total,
        ),
      );
      stepNo++;
    }

    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final approverType = (stage['approverType'] ?? '').toString();
      rows.add(
        _FlowPreviewRow(
          stepNo: stepNo,
          title: (stage['stageName'] ?? stage['name'] ?? stage['label'] ?? '审批步骤')
              .toString(),
          meta: uploadStageMetaLabel(stage, userNames: userNames),
          statusLabel: pendingStatusLabel,
          state: XflowApprovalFlowStepState.pending,
          isLast: stepNo == total,
          onHelp: approverType != 'SYSTEM' && onStageHelp != null
              ? () => onStageHelp!(i)
              : null,
        ),
      );
      stepNo++;
    }

    for (final stage in suffix) {
      rows.add(
        _FlowPreviewRow(
          stepNo: stepNo,
          title: (stage['stageName'] ?? '阶段').toString(),
          meta: (stage['meta'] ?? '系统自动').toString(),
          statusLabel: pendingStatusLabel,
          state: XflowApprovalFlowStepState.pending,
          isLast: stepNo == total,
        ),
      );
      stepNo++;
    }

    return rows;
  }

  List<Map<String, dynamic>> _stageExtras(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}

/// 详情页流程追踪（Palette D 时间线，与销售提案预览一致）。
class XflowApprovalFlowTrackSection extends StatelessWidget {
  const XflowApprovalFlowTrackSection({
    super.key,
    required this.rows,
    this.topSpacing = 0,
  });

  final List<XflowApprovalFlowTrackRowData> rows;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text(
        '暂无审批流程记录',
        style: TextStyle(fontSize: 13, color: XfProposalUi.mute, height: 1.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topSpacing > 0) SizedBox(height: topSpacing),
        XflowApprovalFlowBadge(
          label: '流程追踪',
          subLabel: '${rows.length} EVENTS',
        ),
        const SizedBox(height: 10),
        XflowApprovalFlowCard(
          children: [
            for (var i = 0; i < rows.length; i++)
              _FlowTrackRow(data: rows[i], isLast: i == rows.length - 1),
          ],
        ),
      ],
    );
  }
}

class XflowApprovalFlowTrackRowData {
  const XflowApprovalFlowTrackRowData({
    required this.title,
    required this.time,
    required this.comment,
    required this.state,
    this.role,
    this.subComment,
  });

  final String title;
  final String time;
  final String comment;
  final String? role;
  final String? subComment;
  final XflowApprovalFlowStepState state;
}

class XflowApprovalFlowBadge extends StatelessWidget {
  const XflowApprovalFlowBadge({
    super.key,
    required this.label,
    required this.subLabel,
    this.trailing,
  });

  final String label;
  final String subLabel;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: XfProposalUi.coral.withAlpha(31),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: XfProposalUi.coral,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          subLabel,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: XfProposalUi.mute2,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.5, color: XfProposalUi.line)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: XfProposalUi.coral,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class XflowApprovalFlowCard extends StatelessWidget {
  const XflowApprovalFlowCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: XfProposalUi.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: XfProposalUi.lineSoft, width: 0.6),
      ),
      child: Column(children: children),
    );
  }
}

class _FlowPreviewRow extends StatelessWidget {
  const _FlowPreviewRow({
    required this.stepNo,
    required this.title,
    required this.meta,
    required this.statusLabel,
    required this.state,
    required this.isLast,
    this.onHelp,
  });

  final int stepNo;
  final String title;
  final String meta;
  final String statusLabel;
  final XflowApprovalFlowStepState state;
  final bool isLast;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    const dotSize = 12.0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: dotSize + 2,
            child: Column(
              children: [
                _FlowDot(state: state),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 0.5,
                      color: XfProposalUi.lineSoft,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          '$stepNo. $title',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: XfProposalUi.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onHelp != null) ...[
                        Material(
                          color: XfProposalUi.cardAlt,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onHelp,
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: Icon(
                                Icons.help_outline,
                                size: 12,
                                color: XfProposalUi.mute,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 8,
                          color: _statusColor(state),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: XfProposalUi.mute2,
                        letterSpacing: 0.2,
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

class _FlowTrackRow extends StatelessWidget {
  const _FlowTrackRow({required this.data, required this.isLast});

  final XflowApprovalFlowTrackRowData data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    const dotSize = 14.0;
    final commentStyle = _commentStyle(data.state);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: dotSize + 2,
            child: Column(
              children: [
                _FlowDot(state: data.state),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 0.5,
                      color: XfProposalUi.lineSoft,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              data.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: data.state == XflowApprovalFlowStepState.pending
                                    ? XfProposalUi.mute
                                    : XfProposalUi.ink,
                              ),
                            ),
                            if (data.role != null && data.role!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: data.state == XflowApprovalFlowStepState.done
                                      ? const Color(0xFFE8F5EE)
                                      : XfProposalUi.cardAlt,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  data.role!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: data.state == XflowApprovalFlowStepState.done
                                        ? const Color(0xFF085041)
                                        : XfProposalUi.mute2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        data.time,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: XfProposalUi.mute2,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: commentStyle.bg,
                      borderRadius: BorderRadius.circular(7),
                      border: Border(
                        left: BorderSide(color: commentStyle.border, width: 2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.comment,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            height: 1.5,
                            color: commentStyle.fg,
                            fontWeight: data.state == XflowApprovalFlowStepState.current
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                        if (data.subComment != null && data.subComment!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            data.subComment!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: XfProposalUi.mute,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowDot extends StatelessWidget {
  const _FlowDot({required this.state});

  final XflowApprovalFlowStepState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case XflowApprovalFlowStepState.done:
        return Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Color(0xFF4A7A3E),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 9, color: Colors.white),
        );
      case XflowApprovalFlowStepState.current:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: XfProposalUi.card,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3B82F6), width: 2),
          ),
        );
      case XflowApprovalFlowStepState.rejected:
        return Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Color(0xFFB4443D),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 9, color: Colors.white),
        );
      case XflowApprovalFlowStepState.pending:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: XfProposalUi.card,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFC9C3B7), width: 1),
          ),
        );
    }
  }
}

Color _statusColor(XflowApprovalFlowStepState state) {
  switch (state) {
    case XflowApprovalFlowStepState.done:
      return const Color(0xFF4A7A3E);
    case XflowApprovalFlowStepState.current:
      return const Color(0xFF3B82F6);
    case XflowApprovalFlowStepState.rejected:
      return const Color(0xFFB4443D);
    case XflowApprovalFlowStepState.pending:
      return XfProposalUi.mute2;
  }
}

({Color bg, Color fg, Color border}) _commentStyle(XflowApprovalFlowStepState state) {
  switch (state) {
    case XflowApprovalFlowStepState.done:
      return (
        bg: const Color(0xFFF3FAF6),
        fg: const Color(0xFF085041),
        border: const Color(0xFF1D9E75),
      );
    case XflowApprovalFlowStepState.current:
      return (
        bg: const Color(0xFFEFF6FF),
        fg: const Color(0xFF1D4ED8),
        border: const Color(0xFF3B82F6),
      );
    case XflowApprovalFlowStepState.rejected:
      return (
        bg: const Color(0xFFFFF8F7),
        fg: const Color(0xFF993C1D),
        border: const Color(0xFFB4443D),
      );
    case XflowApprovalFlowStepState.pending:
      return (
        bg: XfProposalUi.cardAlt,
        fg: XfProposalUi.mute,
        border: XfProposalUi.line,
      );
  }
}
