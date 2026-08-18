import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import 'recon_gfm.dart';
import 'recon_markdown_table.dart';
import 'reconciliation_shucai_models.dart';
import 'shucai_report_table.dart';

/// 对账明细：优先资管 Markdown；按条确认/反驳仍走结构化行键。
class ReconDetailList extends StatelessWidget {
  const ReconDetailList({
    super.key,
    required this.title,
    required this.report,
    required this.tab,
    this.markdown = '',
    this.decisions = const {},
    this.previous = const {},
    this.acks = const [],
    this.selectedRowKeys = const {},
    this.showActions = true,
    this.showBatchSelect = true,
    this.showConfirmAction = true,
    this.showReviewStats = false,
    this.showPrevious = true,
    this.compact = false,
    this.locked = false,
    this.avatarService,
    this.visibleSteps = reconAuditChainSteps,
    this.onToggleRow,
    this.onToggleSelectAll,
    this.onConfirmRow,
    this.onRejectRow,
  });

  final String title;
  final ShucaiReport report;
  final String tab;
  final String markdown;
  final Map<String, ReconRowDecision> decisions;
  final Map<String, List<ReconRowReviewer>> previous;
  final List<ReconPerson> acks;
  final Set<String> selectedRowKeys;
  final bool showActions;
  final bool showBatchSelect;
  final bool showConfirmAction;
  final bool showReviewStats;
  final bool showPrevious;
  final bool compact;
  final bool locked;
  final ConversationService? avatarService;
  final List<String> visibleSteps;
  final ValueChanged<String>? onToggleRow;
  final VoidCallback? onToggleSelectAll;
  final ValueChanged<String>? onConfirmRow;
  final ValueChanged<String>? onRejectRow;

  @override
  Widget build(BuildContext context) {
    final stats = reconReviewStats(
      report: report,
      tab: tab,
      previous: previous,
    );
    final md = markdown.trim();
    if (stats.total <= 0 && md.isEmpty) return const SizedBox.shrink();
    final heading = showReviewStats
        ? '$title  ·  ${stats.total} 条  ·  已确认 ${stats.confirmed}  ·  已驳回 ${stats.rejected}  ·  未处理 ${stats.pending}'
        : '$title  ·  ${stats.total} 条';
    final useMarkdownTable = parseReconGfmTables(md).isNotEmpty;

    final table = useMarkdownTable
        ? ReconMarkdownTable(
            markdown: md,
            report: report,
            compact: compact,
            showRowActions: showActions,
            showBatchSelect: showBatchSelect,
            showConfirmAction: showConfirmAction,
            showPrevious: showPrevious,
            rowActionsLocked: locked,
            selectedRowKeys: selectedRowKeys,
            decisions: decisions,
            previous: previous,
            acks: acks,
            visibleSteps: visibleSteps,
            avatarService: avatarService,
            onToggleRow: onToggleRow,
            onToggleSelectAll: onToggleSelectAll,
            onConfirmRow: onConfirmRow,
            onRejectRow: onRejectRow,
          )
        : ShucaiReportTable(
            report: report,
            compact: compact,
            showRowActions: showActions,
            showBatchSelect: showBatchSelect,
            showConfirmAction: showConfirmAction,
            showPrevious: showPrevious,
            rowActionsLocked: locked,
            selectedRowKeys: selectedRowKeys,
            decisions: decisions,
            previous: previous,
            acks: acks,
            visibleSteps: visibleSteps,
            avatarService: avatarService,
            onToggleRow: onToggleRow,
            onToggleSelectAll: onToggleSelectAll,
            onConfirmRow: onConfirmRow,
            onRejectRow: onRejectRow,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final headingWidget = Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            heading,
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
        );
        if (constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headingWidget,
              Expanded(child: table),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [headingWidget, table],
        );
      },
    );
  }
}
