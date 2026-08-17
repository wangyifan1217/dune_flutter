import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../chat/chat_file_type_icon.dart';
import '../shell/dunes_toast.dart';
import 'xflow_approval_flow_ui.dart';
import 'xflow_detail_logic.dart';
import 'xflow_file_open.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';
import 'xflow_upload_field.dart';

/// WebView `.xf-det-card` 容器
class XfDetCard extends StatelessWidget {
  const XfDetCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.marginBottom = 10,
    this.padding = const EdgeInsets.all(12),
    this.decoration,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final double marginBottom;
  final EdgeInsets padding;
  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: marginBottom),
      padding: padding,
      decoration:
          decoration ??
          BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.borderSoft),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: DunesColors.text2),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    title!,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// `.xf-det-hero` — 浅色渐变，非紫色
class XfDetHero extends StatelessWidget {
  const XfDetHero({
    super.key,
    required this.detail,
    this.showStatus = true,
  });

  final XflowProposalDetail detail;
  /// 动态审批详情可不展示状态角标（状态已在审批进度区体现）。
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final raw = detail.raw;
    final tag1 = (raw['tag1'] ?? detail.formValues['tag1'] ?? '')
        .toString()
        .trim();
    final taskLevel = (raw['taskLevel'] ?? detail.formValues['taskLevel'] ?? '')
        .toString()
        .trim();
    final coverageRaw = raw['coverage'] ?? detail.formValues['provinces'];
    final coverageText = fmtList(coverageRaw).trim();
    final tone = detailStatusTone(detail.status);

    final chips = <Widget>[
      if (tag1.isNotEmpty && tag1 != '—')
        _metaChip(Icons.sell_outlined, tag1),
      if (taskLevel.isNotEmpty)
        _metaChip(Icons.bar_chart_outlined, '$taskLevel 级'),
      if (coverageText.isNotEmpty && coverageText != '—')
        _metaChip(Icons.location_on_outlined, coverageText),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE4D6), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                detail.code,
                style: DunesTypography.mono(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
              if (showStatus)
                _StatusPill(label: detailStatusLabel(detail.status), tone: tone),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail.title.isEmpty ? '销售提案' : detail.title,
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: DunesColors.text,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: chips,
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: DunesColors.text2),
        const SizedBox(width: 4),
        Text(
          text,
          style: DunesTypography.sans(fontSize: 11, color: DunesColors.text2),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final DetailStatusTone tone;

  @override
  Widget build(BuildContext context) {
    Color bg = DunesColors.bgSoft;
    Color fg = DunesColors.text2;
    switch (tone) {
      case DetailStatusTone.ok:
        bg = const Color(0xFFE6F5EC);
        fg = const Color(0xFF2D8A5E);
      case DetailStatusTone.warn:
        bg = const Color(0xFFFFF4E0);
        fg = const Color(0xFFD4A017);
      case DetailStatusTone.bad:
        bg = const Color(0xFFFDE8E4);
        fg = DunesColors.coral;
      case DetailStatusTone.muted:
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class XfDetClosedBanner extends StatelessWidget {
  const XfDetClosedBanner({super.key, required this.detail});

  final XflowProposalDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.status.toLowerCase() != 'voided') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, size: 16, color: DunesColors.text2),
              const SizedBox(width: 6),
  Text(
                '已作废',
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: DunesColors.border, width: 3),
              ),
            ),
            child: Text(
              '该单据已关闭，不可重新填写或再次提交。',
              style: DunesTypography.sans(
                fontSize: 12,
                height: 1.55,
                color: DunesColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class XfDetRejectBanner extends StatelessWidget {
  const XfDetRejectBanner({
    super.key,
    required this.detail,
    required this.info,
  });

  final XflowProposalDetail detail;
  final RejectStepInfo? info;

  @override
  Widget build(BuildContext context) {
    if (detail.status.toLowerCase() != 'rejected')
      return const SizedBox.shrink();
    final meta = info != null
        ? '第${info!.stepNo}步 · ${info!.who}${info!.at.isNotEmpty ? ' · ${fmtDetailTime(info!.at).substring(0, info!.at.length >= 16 ? 16 : info!.at.length)}' : ''}'
        : '审批未通过，请修改后重新提交';
    final comment = info?.comment ?? '请查看流程追踪了解详情';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF5F3), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0C4BC), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: DunesColors.coral),
              const SizedBox(width: 6),
              Text(
                '审批已驳回',
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: DunesColors.coral.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              comment,
              style: DunesTypography.sans(
                fontSize: 12,
                height: 1.55,
                color: DunesColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class XfDetPeopleCard extends StatelessWidget {
  const XfDetPeopleCard({super.key, required this.bundle});

  final XflowDetailBundle bundle;

  @override
  Widget build(BuildContext context) {
    final d = bundle.detail;
    final fv = d.formValues;
    final raw = d.raw;
    final rows = <(String, String)>[];
    final createdBy = (raw['createdBy'] ?? '').toString();
    if (createdBy.isNotEmpty) rows.add(('创建人', createdBy));
    rows.add((
      '第一责任人',
      formatUserDisplay(fv['owner1']).ifEmpty(
        (raw['owner1'] ?? d.ownerName).toString().ifEmpty(
          raw['initiator']?.toString() ?? '—',
        ),
      ),
    ));
    final o2 = owner2Line(fv, raw);
    if (o2.isNotEmpty) rows.add(('第二责任人', o2));
    for (final e in [
      ('全国负责人', formatUserDisplay(fv['respNational'])),
      ('运营负责人', formatUserDisplay(fv['respOps'])),
      ('省区负责人', formatUserDisplay(fv['respProvince'])),
      ('技术负责人', formatUserDisplay(fv['respTech'])),
    ]) {
      if (e.$2.isNotEmpty) rows.add(e);
    }
    final techRoute = (raw['techRoute'] ?? fv['techRoute'] ?? '').toString();
    if (techRoute.isNotEmpty) rows.add(('技术路由', techRoute));
    final cur = currentApproverLabel(
      bundle.trail,
      bundle.assigneeNames,
      bundle.stages,
    );
    if (cur.isNotEmpty) rows.add(('当前审批节点', cur));
    if (rows.isEmpty) return const SizedBox.shrink();

    return XfDetCard(
      title: '相关责任人',
      icon: Icons.people_outline,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: i == rows.length - 1
                  ? null
                  : BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: DunesColors.borderSoft.withValues(alpha: 0.8),
                          style: BorderStyle.solid,
                        ),
                      ),
                    ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DunesColors.text,
                      ),
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

class XfDetPendingHint extends StatelessWidget {
  const XfDetPendingHint({super.key, required this.bundle});

  final XflowDetailBundle bundle;

  @override
  Widget build(BuildContext context) {
    final st = bundle.detail.status.toLowerCase();
    if (st != 'pending' && st != 'pending_initiate')
      return const SizedBox.shrink();
    if (bundle.myTodo != null) return const SizedBox.shrink();
    var who = currentApproverLabel(
      bundle.trail,
      bundle.assigneeNames,
      bundle.stages,
    );
    if (who.isEmpty) {
      who = (bundle.detail.raw['currentNodeLabel'] ?? '').toString().trim();
    }
    if (who.isEmpty) who = '待分配';
    return XfDetCard(
      title: '审批进行中',
      icon: Icons.hourglass_empty,
      child: Text.rich(
        TextSpan(
          style: DunesTypography.sans(
            fontSize: 12,
            height: 1.5,
            color: DunesColors.text2,
          ),
          children: [
            const TextSpan(text: '当前节点：'),
            TextSpan(
              text: who,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: '。您可在「流程追踪」查看完整进度。'),
          ],
        ),
      ),
    );
  }
}

class XfDetPushContext extends StatelessWidget {
  const XfDetPushContext({super.key, required this.detail});

  final XflowProposalDetail detail;

  @override
  Widget build(BuildContext context) {
    final raw = detail.raw;
    final draftedBy = raw['draftedBy'];
    final pushMessage = (raw['pushMessage'] ?? '').toString();
    if (draftedBy == null && pushMessage.isEmpty)
      return const SizedBox.shrink();
    final by = draftedBy is Map
        ? Map<String, dynamic>.from(draftedBy)
        : <String, dynamic>{};
    // 代发起人 = 被推送、待确认发起的同事（即我选择的运营部门同事）。
    final designated = raw['designatedInitiator'];
    final to = designated is Map
        ? Map<String, dynamic>.from(designated)
        : <String, dynamic>{};
    final toName = (to['name'] ?? '').toString();
    final toDept = (to['dept'] ?? '').toString();
    return XfDetCard(
      title: '运营推送上下文',
      icon: Icons.send_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (toName.isNotEmpty) ...[
            _pushInfoRow('代发起人', toName, highlight: true),
            if (toDept.isNotEmpty) _pushInfoRow('代发起人部门', toDept),
            const SizedBox(height: 4),
          ],
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Column(
              children: [
                _pushInfoRow('推送人', (by['name'] ?? '—').toString()),
                _pushInfoRow('部门', (by['dept'] ?? '—').toString()),
                if ((by['at'] ?? '').toString().isNotEmpty)
                  _pushInfoRow('推送时间', fmtDetailTime(by['at'])),
              ],
            ),
          ),
          if (pushMessage.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DunesColors.amberSoft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: DunesColors.amber.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '推送说明',
                    style: DunesTypography.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pushMessage,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      height: 1.5,
                      color: DunesColors.text2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pushInfoRow(String k, String v, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                color: highlight ? DunesColors.accent : DunesColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情填报区（历史名 TabsWrap；现已改为完整纵向展示，不再使用 Tab）。
class XfDetTabsWrap extends StatelessWidget {
  const XfDetTabsWrap({
    super.key,
    required this.bundle,
    required this.service,
    required this.showTrack,
    this.onOpenLinkedProposal,
  });

  final XflowDetailBundle bundle;
  final XflowService service;
  final bool showTrack;
  final void Function(int proposalId)? onOpenLinkedProposal;

  @override
  Widget build(BuildContext context) {
    final cfg = bundle.detailConfig;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XfDetCard(
          title: '填报内容',
          marginBottom: 10,
          child: XfDetFormSections(
            sections: sections,
            service: service,
            onOpenLinkedProposal: onOpenLinkedProposal,
          ),
        ),
        if (showTrack)
          XfDetCard(
            title: '审批进度',
            marginBottom: 10,
            child: XfDetTrackTimeline(bundle: bundle),
          ),
      ],
    );
  }
}

class XfDetFormSections extends StatelessWidget {
  const XfDetFormSections({
    super.key,
    required this.sections,
    required this.service,
    this.onOpenLinkedProposal,
  });

  final List<DetailSection> sections;
  final XflowService service;
  final void Function(int proposalId)? onOpenLinkedProposal;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Text(
        '暂无填报内容',
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
      );
    }
    return Column(
      children: [
        for (var si = 0; si < sections.length; si++)
          _SectionBlock(
            section: sections[si],
            sectionIndex: si,
            service: service,
            onOpenLinkedProposal: onOpenLinkedProposal,
          ),
      ],
    );
  }
}

class _SectionBlock extends StatefulWidget {
  const _SectionBlock({
    required this.section,
    required this.sectionIndex,
    required this.service,
    this.onOpenLinkedProposal,
  });

  final DetailSection section;
  final int sectionIndex;
  final XflowService service;
  final void Function(int proposalId)? onOpenLinkedProposal;

  @override
  State<_SectionBlock> createState() => _SectionBlockState();
}

class _SectionBlockState extends State<_SectionBlock> {
  /// 详情默认全部展开，不再折叠「展开剩余 N 项」。
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final items = widget.section.items;
    final visible = _expanded ? items : items.take(detailPreviewLimit).toList();
    final hiddenCount = _expanded ? 0 : items.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.section.title} · ${items.length} 项',
            style: DunesTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in visible)
            item.expandable
                ? XfDetKvExpand(item: item, service: widget.service)
                : Builder(
                    builder: (context) {
                      final linkedId = item.field.type == 'proposal'
                          ? parseLinkedProposalId(item.rawValue)
                          : 0;
                      final canOpen =
                          linkedId > 0 && widget.onOpenLinkedProposal != null;
                      return XfDetKv(
                        label: item.label,
                        value: item.value,
                        linkStyle: canOpen,
                        onTap: canOpen
                            ? () => widget.onOpenLinkedProposal!(linkedId)
                            : null,
                      );
                    },
                  ),
          if (hiddenCount > 0)
            TextButton(
              onPressed: () => setState(() => _expanded = true),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(vertical: 9),
                foregroundColor: DunesColors.accentDeep,
                backgroundColor: DunesColors.bgSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  '展开剩余 $hiddenCount 项',
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class XfDetKv extends StatelessWidget {
  const XfDetKv({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.linkStyle = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool linkStyle;

  @override
  Widget build(BuildContext context) {
    final valueStyle = DunesTypography.sans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: linkStyle ? DunesColors.accent : null,
    ).copyWith(
      decoration: linkStyle ? TextDecoration.underline : TextDecoration.none,
      decorationColor: linkStyle ? DunesColors.accent : null,
    );
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DunesColors.borderSoft.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class XfDetKvExpand extends StatefulWidget {
  const XfDetKvExpand({super.key, required this.item, required this.service});

  final DetailFieldItem item;
  final XflowService service;

  @override
  State<XfDetKvExpand> createState() => _XfDetKvExpandState();
}

class _XfDetKvExpandState extends State<XfDetKvExpand> {
  /// 明细 / 附件等可展开项默认打开。
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DunesColors.borderSoft.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.value,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more,
                          size: 18,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExpandBody(item: widget.item, service: widget.service),
            ),
        ],
      ),
    );
  }
}

class _ExpandBody extends StatelessWidget {
  const _ExpandBody({required this.item, required this.service});

  final DetailFieldItem item;
  final XflowService service;

  @override
  Widget build(BuildContext context) {
    if (item.field.type == 'upload') {
      return XfDetFileList(
        items: normalizeUploadItems(
          item.rawValue,
        ).where((e) => e['status'] != 'error').toList(growable: false),
        service: service,
      );
    }
    if (item.field.isCardDynamicList) {
      return XfDetRepeatableGroups(
        field: item.field,
        rows: normalizeDynamicListValue(item.rawValue),
        service: service,
      );
    }
    return XfDetTable(
      field: item.field,
      rows: normalizeDynamicListValue(item.rawValue),
    );
  }
}

class XfDetRepeatableGroups extends StatelessWidget {
  const XfDetRepeatableGroups({
    super.key,
    required this.field,
    required this.rows,
    required this.service,
  });

  final XflowField field;
  final List<Map<String, dynamic>> rows;
  final XflowService service;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        '暂无明细',
        style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
      );
    }
    final cols = field.columnsAsFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          _groupCard(cols, rows[i], '${field.itemTitle}${i + 1}'),
      ],
    );
  }

  Widget _groupCard(
    List<XflowField> cols,
    Map<String, dynamic> row,
    String title,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ),
          for (final col in cols)
            if (col.type == 'upload')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      col.label.isEmpty ? col.key : col.label,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DunesColors.text3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    XfDetFileList(
                      items: normalizeUploadItems(row[col.key])
                          .where((e) => e['status'] != 'error')
                          .toList(growable: false),
                      service: service,
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        col.label.isEmpty ? col.key : col.label,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        formatGroupCellDisplay(col, row),
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.text2,
                          height: 1.45,
                        ),
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

class XfDetTable extends StatelessWidget {
  const XfDetTable({
    super.key,
    required this.field,
    required this.rows,
    this.nested = false,
  });

  final XflowField field;
  final List<Map<String, dynamic>> rows;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        '暂无明细',
        style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
      );
    }
    final cols = inferColumns(rows, field);
    if (cols.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: DunesColors.borderSoft),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          const JsonEncoder.withIndent('  ').convert(rows),
          style: DunesTypography.mono(fontSize: 11, height: 1.5),
        ),
      );
    }
    final nestedKey = (field.raw['nestedKey'] ?? 'items').toString();
    final nestedCols = field.raw['nestedColumns'] is List
        ? (field.raw['nestedColumns'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerRow(cols),
        for (final row in rows) ...[
          _dataRow(cols, row),
          if (row[nestedKey] is List && (row[nestedKey] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: XfDetTable(
                nested: true,
                field: XflowField(
                  key: field.key,
                  type: 'dynamicList',
                  label: '',
                  placeholder: '',
                  required: false,
                  readonly: true,
                  options: const [],
                  children: const [],
                  raw: {'columns': nestedCols},
                ),
                rows: (row[nestedKey] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList(growable: false),
              ),
            ),
        ],
      ],
    );

    if (nested) return content;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: DunesColors.borderSoft),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _headerRow(List<Map<String, dynamic>> cols) {
    return Container(
      color: DunesColors.bgSoft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in cols)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  (col['label'] ?? col['key'] ?? '').toString(),
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(List<Map<String, dynamic>> cols, Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: DunesColors.borderSoft.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in cols)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  formatCellDisplay(row[col['key']], col, row),
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text2,
                    height: 1.45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class XfDetFileList extends StatelessWidget {
  const XfDetFileList({super.key, required this.items, required this.service});

  final List<Map<String, dynamic>> items;
  final XflowService service;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        '暂无文件',
        style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
      );
    }
    return Column(
      children: [for (final it in items) _FileItem(item: it, service: service)],
    );
  }
}

class _FileItem extends StatefulWidget {
  const _FileItem({required this.item, required this.service});

  final Map<String, dynamic> item;
  final XflowService service;

  @override
  State<_FileItem> createState() => _FileItemState();
}

class _FileItemState extends State<_FileItem> {
  bool _busy = false;
  bool _downloaded = false;
  bool _statusChecked = false;

  Map<String, dynamic> get item => widget.item;
  XflowService get service => widget.service;

  String get _fileName => xflowAttachmentFileName(item);

  bool get _isImage => xflowItemIsImage(item, _fileName);
  bool get _isPdf => xflowItemIsPdf(item, _fileName);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshDownloaded());
  }

  @override
  void didUpdateWidget(covariant _FileItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = xflowAttachmentCacheKey(oldWidget.item);
    final nextKey = xflowAttachmentCacheKey(item);
    if (oldKey != nextKey ||
        xflowAttachmentFileName(oldWidget.item) != _fileName) {
      unawaited(_refreshDownloaded());
    }
  }

  Future<void> _refreshDownloaded() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _downloaded = false;
          _statusChecked = true;
        });
      }
      return;
    }
    final ok = await isXflowAttachmentDownloaded(item);
    if (!mounted) return;
    setState(() {
      _downloaded = ok;
      _statusChecked = true;
    });
  }

  String _formatSize(dynamic bytes) {
    final n = (bytes is num) ? bytes.toInt() : int.tryParse('$bytes') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _open(BuildContext context, {required bool preferPreview}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await openXflowAttachment(
        context: context,
        service: service,
        item: item,
        preferPreview: preferPreview,
      );
      await _refreshDownloaded();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await downloadXflowAttachment(
        context: context,
        service: service,
        item: item,
        force: _downloaded,
        reveal: true,
      );
      if (path != null && path.isNotEmpty && mounted) {
        setState(() => _downloaded = true);
      } else {
        await _refreshDownloaded();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _openActionLabel {
    if (_busy) {
      return isDesktopCommOnly ? '打开中…' : '准备中…';
    }
    if (isDesktopCommOnly) return '打开';
    return '用其他应用打开';
  }

  String get _downloadActionLabel {
    if (_busy) return '处理中…';
    if (kIsWeb) return '下载';
    return _downloaded ? '重新下载' : '下载';
  }

  @override
  Widget build(BuildContext context) {
    final name = _fileName;
    final size = item['size'];
    final showPreview =
        !kIsWeb && !isDesktopCommOnly && (_isImage || _isPdf);
    final metaParts = <String>[
      if (size != null) _formatSize(size),
      if (_statusChecked && _downloaded) '已下载',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          ChatFileTypeIcon(fileName: name, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (metaParts.isNotEmpty)
                  Text(
                    metaParts.join(' · '),
                    style: DunesTypography.sans(
                      fontSize: 10,
                      color: _downloaded
                          ? const Color(0xFF3B82F6)
                          : DunesColors.text3,
                    ),
                  ),
              ],
            ),
          ),
          if (showPreview)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _open(context, preferPreview: true),
              child: const Text('预览', style: TextStyle(fontSize: 11)),
            ),
          if (!kIsWeb)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _open(context, preferPreview: false),
              child: Text(
                _openActionLabel,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          TextButton(
            onPressed: _busy ? null : () => _download(context),
            child: Text(
              _downloadActionLabel,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class XfDetTrackTimeline extends StatelessWidget {
  const XfDetTrackTimeline({super.key, required this.bundle});

  final XflowDetailBundle bundle;

  @override
  Widget build(BuildContext context) {
    final detail = bundle.detail;
    final trail = bundle.trail;
    final steps = trail?.steps ?? const <XflowApprovalStep>[];
    final parallel = trail?.isParallel ?? false;
    final curStep = trail?.currentStep ?? 1;
    final curSteps = trail?.currentSteps.toSet() ?? const <int>{};
    final st = detail.status.toLowerCase();

    String assigneeLabel(XflowApprovalStep step, String fallback) {
      if (step.assigneeId > 0 &&
          bundle.assigneeNames.containsKey(step.assigneeId)) {
        return '${bundle.assigneeNames[step.assigneeId]} · $fallback';
      }
      if (step.assigneeName.isNotEmpty) {
        return '${step.assigneeName} · $fallback';
      }
      return fallback;
    }

    // 并行：未决步骤统一「待处理」，勿用 currentStep == 某一步单独高亮
    bool isCurrentTrackStep(XflowApprovalStep step) {
      if (parallel) return false;
      final flagged = step.isCurrent;
      if (flagged != null) return flagged;
      if (curSteps.isNotEmpty) return curSteps.contains(step.stepNo);
      return step.stepNo == curStep;
    }

    final rows = <XflowApprovalFlowTrackRowData>[
      XflowApprovalFlowTrackRowData(
        title: trailSubmitterLabel(detail, trail, bundle.assigneeNames),
        role: '提交人',
        time: fmtDetailTime(trail?.createdAtRaw ?? detail.raw['createdAt']),
        comment: trailSubmitterComment(detail),
        subComment: trailProxyInitiatorNote(detail),
        state: XflowApprovalFlowStepState.done,
      ),
    ];

    for (final step in steps) {
      final label = step.stageName.isNotEmpty
          ? step.stageName
          : stageLabel(step.stepNo, step.stepType, bundle.stages);
      final who = assigneeLabel(step, label);
      final decision = step.decision.toUpperCase();
      late XflowApprovalFlowStepState state;
      late String cmt;
      late String tm;
      if (decision == 'APPROVED') {
        state = XflowApprovalFlowStepState.done;
        cmt = step.comment.isEmpty ? '已通过' : step.comment;
        tm = fmtDetailTime(step.decidedAtRaw);
      } else if (decision == 'REJECTED') {
        state = XflowApprovalFlowStepState.rejected;
        cmt = step.comment.isEmpty ? '已驳回' : step.comment;
        tm = fmtDetailTime(step.decidedAtRaw);
      } else if (st == 'pending' && isCurrentTrackStep(step)) {
        state = XflowApprovalFlowStepState.current;
        cmt = '审批进行中';
        tm = '当前处理';
      } else {
        state = XflowApprovalFlowStepState.pending;
        cmt = '待处理';
        tm = '待处理';
      }
      rows.add(
        XflowApprovalFlowTrackRowData(
          title: who,
          time: tm,
          comment: cmt,
          state: state,
        ),
      );
    }

    // 后端有时只返回已发生步骤，补齐模板后续节点，避免流程仅显示首节点。
    final shownStepNos = steps.map((s) => s.stepNo).where((n) => n > 0).toSet();
    for (var no = 1; no <= bundle.stages.length; no++) {
      if (shownStepNos.contains(no)) continue;
      final label = stageLabel(no, '', bundle.stages);
      final stage = bundle.stages[no - 1];
      final approverIds = stage['approverIds'];
      var who = label;
      if (approverIds is List && approverIds.isNotEmpty) {
        final aid = int.tryParse('${approverIds.first}') ?? 0;
        final name = bundle.assigneeNames[aid];
        if (name != null && name.isNotEmpty) who = '$name · $label';
      }
      final isCurrent = !parallel &&
          st == 'pending' &&
          (curSteps.isNotEmpty ? curSteps.contains(no) : no == curStep);
      rows.add(
        XflowApprovalFlowTrackRowData(
          title: who,
          time: isCurrent ? '当前处理' : '待处理',
          comment: isCurrent ? '审批进行中' : '待处理',
          state: isCurrent
              ? XflowApprovalFlowStepState.current
              : XflowApprovalFlowStepState.pending,
        ),
      );
    }

    if (st == 'approved') {
      rows.add(
        XflowApprovalFlowTrackRowData(
          title: '审批通过',
          time: fmtDetailTime(trail?.finishedAtRaw),
          comment: '全部节点已完成',
          state: XflowApprovalFlowStepState.done,
        ),
      );
    }

    return XflowApprovalFlowTrackSection(rows: rows);
  }
}

class XfDetCcCard extends StatelessWidget {
  const XfDetCcCard({super.key, required this.ccList});

  final List<Map<String, dynamic>> ccList;

  @override
  Widget build(BuildContext context) {
    if (ccList.isEmpty) return const SizedBox.shrink();
    return XfDetCard(
      title: '知会 / 抄送 · ${ccList.length} 人',
      icon: Icons.notifications_outlined,
      child: Column(
        children: [
          for (var i = 0; i < ccList.length; i++)
            _CcRow(item: ccList[i], isLast: i == ccList.length - 1),
        ],
      ),
    );
  }
}

class _CcRow extends StatelessWidget {
  const _CcRow({required this.item, required this.isLast});

  final Map<String, dynamic> item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '—').toString();
    final role = (item['role'] ?? '').toString();
    final dept = (item['dept'] ?? '').toString();
    final reasons = item['reasons'] is List
        ? (item['reasons'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .join(' · ')
        : '';
    final metaParts = <String>[
      if (role.isNotEmpty) role,
      if (dept.isNotEmpty) dept,
      if (reasons.isNotEmpty) reasons,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (metaParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                metaParts.join(' · '),
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class XfDetApproveCard extends StatefulWidget {
  const XfDetApproveCard({
    super.key,
    required this.onApprove,
    required this.onReject,
  });

  final Future<void> Function(String comment) onApprove;
  final Future<void> Function(String comment) onReject;

  @override
  State<XfDetApproveCard> createState() => _XfDetApproveCardState();
}

class _XfDetApproveCardState extends State<XfDetApproveCard> {
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(bool approve) async {
    final text = _comment.text.trim();
    if (text.isEmpty) {
      showDunesToast(context, '请填写审批意见', kind: DunesToastKind.error);
      return;
    }
    final ok = approve
        ? await confirmApproveDecision(context)
        : await confirmRejectDecision(context);
    if (!ok) return;
    setState(() => _submitting = true);
    try {
      if (approve) {
        await widget.onApprove(text);
      } else {
        await widget.onReject(text);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return XfDetCard(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8F6), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0C4BC), width: 1.5),
      ),
      title: '待您审批',
      icon: Icons.gavel_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '请查看填报内容与流程进度，填写意见后确认。',
            style: DunesTypography.sans(
              fontSize: 11.5,
              color: DunesColors.text3,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: '请填写审批意见（必填）',
              hintStyle: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.text3,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: DunesColors.borderSoft),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ApvBtn(
                label: '驳回',
                icon: Icons.close,
                reject: true,
                loading: _submitting,
                onPressed: () => _submit(false),
              ),
              const SizedBox(width: 8),
              _ApvBtn(
                label: '通过',
                icon: Icons.check,
                approve: true,
                loading: _submitting,
                onPressed: () => _submit(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApvBtn extends StatelessWidget {
  const _ApvBtn({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.approve = false,
    this.reject = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool approve;
  final bool reject;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bg = approve ? DunesColors.accent : Colors.white;
    final fg = approve ? Colors.white : DunesColors.coral;
    final border = approve ? DunesColors.accent : const Color(0xFFF0C4BC);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: approve ? Colors.white : DunesColors.coral,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: fg),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class XfDetActions extends StatelessWidget {
  const XfDetActions({
    super.key,
    required this.detail,
    required this.canReedit,
    this.canDeleteDraft = false,
    this.canWithdraw = false,
    this.onDelete,
    this.onPush,
    this.onInitiate,
    this.onReedit,
    this.onVoid,
    this.onWithdraw,
    this.onReturn,
    this.isDesignatedInitiator = false,
    this.isPusher = false,
  });

  final XflowProposalDetail detail;
  final bool canReedit;
  final bool canDeleteDraft;
  final bool canWithdraw;
  final VoidCallback? onDelete;
  final VoidCallback? onPush;
  final VoidCallback? onInitiate;
  final VoidCallback? onReedit;
  final VoidCallback? onVoid;
  final VoidCallback? onWithdraw;
  final VoidCallback? onReturn;
  final bool isDesignatedInitiator;
  final bool isPusher;

  @override
  Widget build(BuildContext context) {
    final st = detail.status.toLowerCase();
    final buttons = <Widget>[];

    // 草稿：创建人可删除 / 推送给同事。
    if (st == 'draft' && canDeleteDraft) {
      if (onDelete != null) {
        buttons.add(
          _ActBtn(
            label: '删除草稿',
            icon: Icons.delete_outline,
            danger: true,
            onPressed: onDelete!,
          ),
        );
      }
      if (onPush != null) {
        buttons.add(
          _ActBtn(
            label: '推送给业务负责人',
            icon: Icons.send_outlined,
            onPressed: onPush!,
          ),
        );
      }
    }
    // 已作废：创建人可删除（与草稿一致）。
    if (st == 'voided' && canDeleteDraft && onDelete != null) {
      buttons.add(
        _ActBtn(
          label: '删除',
          icon: Icons.delete_outline,
          danger: true,
          onPressed: onDelete!,
        ),
      );
    }
    // 待发起：仅代发起人(被推送人)可继续填写 / 提交审批 / 退回；推送人只读等待。
    if (st == 'pending_initiate' && isDesignatedInitiator) {
      if (onReedit != null) {
        buttons.add(
          _ActBtn(
            label: '继续填写',
            icon: Icons.edit_outlined,
            onPressed: onReedit!,
          ),
        );
      }
      if (onReturn != null) {
        buttons.add(
          _ActBtn(label: '退回给推送人', icon: Icons.undo, onPressed: onReturn!),
        );
      }
    }
    if (st == 'rejected' && canReedit) {
      if (onReedit != null) {
        buttons.add(
          _ActBtn(
            label: '重新填写并提交',
            icon: Icons.edit_outlined,
            primary: true,
            onPressed: onReedit!,
          ),
        );
      }
      if (onVoid != null) {
        buttons.add(
          _ActBtn(
            label: '作废',
            icon: Icons.delete_outline,
            danger: true,
            onPressed: onVoid!,
          ),
        );
      }
    }
    if (st == 'pending' && canWithdraw && onWithdraw != null) {
      buttons.add(
        _ActBtn(
          label: '撤回',
          icon: Icons.undo,
          danger: true,
          onPressed: onWithdraw!,
        ),
      );
    }

    if (buttons.isEmpty) {
      // 推送人在「待发起」阶段只读：提示等待代发起人处理。
      if (st == 'pending_initiate' && isPusher) {
        return Container(
          margin: const EdgeInsets.fromLTRB(0, 12, 0, 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DunesColors.bgSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: Text(
            '已推送给代发起人，等待对方继续填写并提交审批；对方也可退回给你。',
            style: DunesTypography.sans(
              fontSize: 12,
              height: 1.5,
              color: DunesColors.text2,
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ],
      ),
    );
  }
}

class _ActBtn extends StatelessWidget {
  const _ActBtn({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.white;
    Color fg = DunesColors.text;
    Color border = DunesColors.border;
    if (primary) {
      bg = DunesColors.accent;
      fg = Colors.white;
      border = DunesColors.accent;
    } else if (danger) {
      bg = DunesColors.coral;
      fg = Colors.white;
      border = DunesColors.coral;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
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

extension _StrExt on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
