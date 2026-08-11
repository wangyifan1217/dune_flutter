import 'package:flutter/material.dart';

import 'xflow_detail_comments.dart';
import 'xflow_detail_logic.dart';
import 'xflow_detail_widgets.dart';
import 'xflow_models.dart';
import 'proposal_recognition_panel.dart';
import 'xflow_service.dart';
import 'xflow_template_runtime.dart';

/// 与 WebView `renderDetail()` 结构 1:1 对齐
class XflowDetailRenderer extends StatelessWidget {
  const XflowDetailRenderer({
    super.key,
    required this.bundle,
    required this.service,
    required this.onApprove,
    required this.onReject,
    this.onDelete,
    this.onPush,
    this.onInitiate,
    this.onReedit,
    this.onVoid,
    this.onWithdraw,
    this.onReturn,
    this.onOpenLinkedProposal,
  });

  final XflowDetailBundle bundle;
  final XflowService service;
  final Future<void> Function(String comment) onApprove;
  final Future<void> Function(String comment) onReject;
  final VoidCallback? onDelete;
  final VoidCallback? onPush;
  final VoidCallback? onInitiate;
  final VoidCallback? onReedit;
  final VoidCallback? onVoid;
  final VoidCallback? onWithdraw;
  final VoidCallback? onReturn;
  final void Function(int proposalId)? onOpenLinkedProposal;

  @override
  Widget build(BuildContext context) {
    final cfg = bundle.detailConfig;
    final showPush = cfg['showPushContext'] != false;
    final showCc = cfg['showCcCard'] != false;
    final showTrack = cfg['showApprovalFlow'] != false;
    final rejectInfo = lastRejectStep(bundle.trail, bundle.assigneeNames);
    final showRecognition = isUploadTemplateConfig(
      detailConfig: cfg,
      fields: bundle.fields,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XfDetHero(detail: bundle.detail),
        XfDetClosedBanner(detail: bundle.detail),
        XfDetRejectBanner(detail: bundle.detail, info: rejectInfo),
        XfDetPeopleCard(bundle: bundle),
        XfDetPendingHint(bundle: bundle),
        if (showPush) XfDetPushContext(detail: bundle.detail),
        if (showRecognition)
          XfDetRecognitionPanel(
            service: service,
            detailConfig: cfg,
            formValues: bundle.detail.formValues,
            fields: bundle.fields,
            detailRaw: bundle.detail.raw,
          ),
        // 填报/补充与审批进度均完整展示，不再用 Tab 切换。
        Builder(
          builder: (context) {
            var sections = buildSectionsByDetailConfig(
              bundle.fields,
              bundle.detail.formValues,
              cfg,
              bundle.detail,
            );
            if (sections.isEmpty) {
              sections = buildFieldSections(
                bundle.fields,
                bundle.detail.formValues,
                bundle.detail,
              );
            }
            if (sections.isEmpty) return const SizedBox.shrink();
            return XfDetCard(
              title: showRecognition ? '提交补充' : '填报内容',
              marginBottom: 10,
              child: XfDetFormSections(
                sections: sections,
                service: service,
                onOpenLinkedProposal: onOpenLinkedProposal,
              ),
            );
          },
        ),
        XfDetCommentsSection(
          service: service,
          businessType: (bundle.detail.raw['businessType'] ?? 'PROPOSAL')
              .toString()
              .trim()
              .isEmpty
              ? 'PROPOSAL'
              : (bundle.detail.raw['businessType'] ?? 'PROPOSAL').toString(),
          businessId: bundle.detail.id,
          fallbackPeople: [
            for (final e in bundle.assigneeNames.entries)
              ApprovalStakeholderPerson(id: e.key, displayName: e.value),
            if (bundle.detail.createdById > 0)
              ApprovalStakeholderPerson(
                id: bundle.detail.createdById,
                displayName: bundle.detail.ownerName,
              ),
            for (final cc in bundle.ccList)
              if (((cc['userId'] ?? cc['id']) as num?)?.toInt() != null)
                ApprovalStakeholderPerson(
                  id: ((cc['userId'] ?? cc['id']) as num).toInt(),
                  displayName:
                      (cc['displayName'] ?? cc['name'] ?? '').toString(),
                ),
          ],
        ),
        if (showTrack)
          XfDetCard(
            title: '审批进度',
            marginBottom: 10,
            child: XfDetTrackTimeline(bundle: bundle),
          ),
        if (showCc) XfDetCcCard(ccList: bundle.ccList),
        if (bundle.myTodo != null)
          XfDetApproveCard(onApprove: onApprove, onReject: onReject),
        XfDetActions(
          detail: bundle.detail,
          canReedit: bundle.canReedit,
          canDeleteDraft: bundle.canDeleteDraft,
          canWithdraw: bundle.canWithdraw,
          onDelete: onDelete,
          onPush: onPush,
          onInitiate: onInitiate,
          onReedit: onReedit,
          onVoid: onVoid,
          onWithdraw: onWithdraw,
          onReturn: onReturn,
          isDesignatedInitiator: bundle.isDesignatedInitiator,
          isPusher: bundle.isPusher,
        ),
      ],
    );
  }
}
