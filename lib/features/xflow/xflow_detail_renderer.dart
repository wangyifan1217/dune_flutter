import 'package:flutter/material.dart';

import 'xflow_detail_logic.dart';
import 'xflow_detail_widgets.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final cfg = bundle.detailConfig;
    final showPush = cfg['showPushContext'] != false;
    final showCc = cfg['showCcCard'] != false;
    final showTrack = cfg['showApprovalFlow'] != false;
    final rejectInfo = lastRejectStep(bundle.trail, bundle.assigneeNames);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XfDetHero(detail: bundle.detail),
        XfDetClosedBanner(detail: bundle.detail),
        XfDetRejectBanner(detail: bundle.detail, info: rejectInfo),
        XfDetPeopleCard(bundle: bundle),
        XfDetPendingHint(bundle: bundle),
        if (showPush) XfDetPushContext(detail: bundle.detail),
        XfDetTabsWrap(bundle: bundle, service: service, showTrack: showTrack),
        if (showCc) XfDetCcCard(ccList: bundle.ccList),
        if (bundle.myTodo != null)
          XfDetApproveCard(onApprove: onApprove, onReject: onReject),
        XfDetActions(
          detail: bundle.detail,
          canReedit: bundle.canReedit,
          onDelete: onDelete,
          onPush: onPush,
          onInitiate: onInitiate,
          onReedit: onReedit,
          onVoid: onVoid,
        ),
      ],
    );
  }
}
