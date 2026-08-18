import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/cached_network_image.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'reconciliation_shucai_models.dart';

({String preset, String objectKey, String url}) reconResolvedUserAvatar({
  int userId = 0,
  String preset = '',
  String objectKey = '',
}) {
  final snap = userId > 0 ? userAvatarRefresh.snapshotFor(userId) : null;
  final profile = userId > 0 ? getCachedMyPageProfile(userId) : null;
  String first(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  return (
    preset: first([
      snap?.avatarPreset ?? '',
      profile?.avatarPreset ?? '',
      preset,
    ]),
    objectKey: first([
      snap?.avatarObjectKey ?? '',
      profile?.avatarObjectKey ?? '',
      objectKey,
    ]),
    url: first([
      snap?.avatarUrl ?? '',
      profile?.avatarUrl ?? '',
    ]),
  );
}

double reconAuditLaneWidth({
  required bool compact,
  List<String> steps = reconAuditChainSteps,
}) {
  return reconAuditLayerWidth(compact: compact) * steps.length +
      reconAuditRecordWidth(compact: compact);
}

double reconAuditLayerWidth({required bool compact}) => compact ? 52.0 : 58.0;

double reconAuditRecordWidth({required bool compact}) => compact ? 68.0 : 76.0;

Color reconAuditStatusColor(ReconRowReviewer? reviewer) {
  if (reviewer == null) return DunesColors.text3;
  if (reviewer.rejected) return DunesColors.coral;
  if (reviewer.confirmed) return DunesColors.green;
  return DunesColors.text3;
}

class ReconFrozenAuditLane extends StatelessWidget {
  const ReconFrozenAuditLane({
    super.key,
    required this.compact,
    required this.headerH,
    required this.fontSize,
    required this.rowCount,
    required this.heights,
    required this.noteHeights,
    required this.rowColorAt,
    required this.noteColorAt,
    required this.reviewersAt,
    required this.rowTitleAt,
    required this.isSummaryAt,
    this.avatarService,
    this.visibleSteps = reconAuditChainSteps,
    this.includeHeader = true,
    this.includeBody = true,
  });

  final bool compact;
  final double headerH;
  final double fontSize;
  final int rowCount;
  final List<double> heights;
  final List<double> noteHeights;
  final Color Function(int index) rowColorAt;
  final Color? Function(int index) noteColorAt;
  final List<ReconRowReviewer> Function(int index) reviewersAt;
  final String Function(int index) rowTitleAt;
  final bool Function(int index) isSummaryAt;
  final ConversationService? avatarService;
  final List<String> visibleSteps;
  final bool includeHeader;
  final bool includeBody;

  @override
  Widget build(BuildContext context) {
    final steps = visibleSteps.isEmpty ? reconAuditChainSteps : visibleSteps;
    final layerW = reconAuditLayerWidth(compact: compact);
    final recordW = reconAuditRecordWidth(compact: compact);
    final width = reconAuditLaneWidth(compact: compact, steps: steps);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            if (includeHeader)
              _band(
                height: headerH,
                color: const Color(0xFFF6F7F9),
                child: Row(
                  children: [
                    for (final step in steps)
                      _headerCell(
                        reconChainStepLabel(step),
                        width: layerW,
                      ),
                    _headerCell('审核记录', width: recordW),
                  ],
                ),
              ),
            if (includeBody)
              for (var i = 0; i < rowCount; i++) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: rowColorAt(i),
                    border: const Border(
                      bottom: BorderSide(
                        color: DunesColors.borderSoft,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    height: heights[i],
                    child: isSummaryAt(i)
                        ? const SizedBox.shrink()
                        : Row(
                            children: [
                              for (final step in steps)
                                _statusCell(
                                  reconReviewerForLayer(reviewersAt(i), step),
                                  width: layerW,
                                ),
                              _recordCell(
                                context,
                                index: i,
                                width: recordW,
                                steps: steps,
                              ),
                            ],
                          ),
                  ),
                ),
                if (noteHeights[i] > 0)
                  ColoredBox(
                    color: noteColorAt(i) ?? Colors.white,
                    child: SizedBox(height: noteHeights[i], width: width),
                  ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _band({
    required double height,
    required Color color,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          bottom: BorderSide(color: DunesColors.borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(height: height, child: child),
    );
  }

  Widget _headerCell(String text, {required double width}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCell(ReconRowReviewer? reviewer, {required double width}) {
    final label = reviewer?.statusLabel ?? '未处理';
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: fontSize - 1,
              fontWeight: FontWeight.w600,
              color: reconAuditStatusColor(reviewer),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordCell(
    BuildContext context, {
    required int index,
    required double width,
    required List<String> steps,
  }) {
    final reviewers = reconFilterReviewersForSteps(reviewersAt(index), steps);
    final canOpen = reviewers.isNotEmpty;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: canOpen
              ? InkWell(
                  onTap: () => showReconAuditRecordSheet(
                    context: context,
                    rowTitle: rowTitleAt(index),
                    reviewers: reviewers,
                    visibleSteps: steps,
                    avatarService: avatarService,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Text(
                      '查看',
                      style: DunesTypography.sans(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.brandPurple,
                      ),
                    ),
                  ),
                )
              : Text(
                  '—',
                  style: DunesTypography.sans(
                    fontSize: fontSize,
                    color: DunesColors.text3,
                  ),
                ),
        ),
      ),
    );
  }
}

Future<void> showReconAuditRecordSheet({
  required BuildContext context,
  required String rowTitle,
  required List<ReconRowReviewer> reviewers,
  List<String> visibleSteps = reconAuditChainSteps,
  ConversationService? avatarService,
}) {
  final body = ReconAuditRecordPane(
    rowTitle: rowTitle,
    reviewers: reviewers,
    visibleSteps: visibleSteps,
    avatarService: avatarService,
  );
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: body,
    ),
  );
}

class ReconAuditRecordPane extends StatelessWidget {
  const ReconAuditRecordPane({
    super.key,
    required this.rowTitle,
    required this.reviewers,
    this.visibleSteps = reconAuditChainSteps,
    this.avatarService,
  });

  final String rowTitle;
  final List<ReconRowReviewer> reviewers;
  final List<String> visibleSteps;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    final title = rowTitle.trim().isEmpty ? '审核记录' : rowTitle.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '审核记录',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < visibleSteps.length; i++) ...[
                _layerCard(
                  step: visibleSteps[i],
                  reviewer: reconReviewerForLayer(reviewers, visibleSteps[i]),
                ),
                if (i != visibleSteps.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _layerCard({
    required String step,
    required ReconRowReviewer? reviewer,
  }) {
    final name = (reviewer?.userName ?? '').trim().isEmpty
        ? '未处理'
        : reviewer!.userName.trim();
    final initial = name.isEmpty ? '审' : name.substring(0, 1);
    final time = reconFormatDecidedAt(reviewer?.decidedAt ?? '');
    final rejectHistory = (reviewer?.rejectReason ?? '').trim();
    final reason = (reviewer?.reason ?? '').trim();
    final avatar = reconResolvedUserAvatar(
      userId: reviewer?.userId ?? 0,
      preset: reviewer?.avatarPreset ?? '',
      objectKey: reviewer?.avatarObjectKey ?? '',
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ImUserAvatar(
                  initial: initial,
                  seed: reviewer?.userId ?? 0,
                  size: 36,
                  avatarPreset: avatar.preset,
                  avatarObjectKey: avatar.objectKey,
                  avatarUrl: avatar.url,
                  avatarService: avatarService,
                  borderRadius: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reconChainStepLabel(step),
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text3,
                        ),
                      ),
                      Text(
                        reviewer == null ? '未处理' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  reviewer?.statusLabel ?? '未处理',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: reconAuditStatusColor(reviewer),
                  ),
                ),
              ],
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '确认时间  $time',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
            ],
            if (reviewer?.rejected == true && reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              _kv('驳回原因', reason, DunesColors.coral),
            ],
            if (reviewer?.reconfirmed == true && reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              _kv('复核说明', reason, DunesColors.green),
            ],
            if (rejectHistory.isNotEmpty &&
                rejectHistory != reason) ...[
              const SizedBox(height: 8),
              _kv('驳回历史', rejectHistory, DunesColors.coral),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String text, Color color) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          TextSpan(
            text: text,
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
