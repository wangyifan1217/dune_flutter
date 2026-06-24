import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'xflow_detail_logic.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
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
      decoration: decoration ??
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
  const XfDetHero({super.key, required this.detail});

  final XflowProposalDetail detail;

  @override
  Widget build(BuildContext context) {
    final raw = detail.raw;
    final tag1 = (raw['tag1'] ?? detail.formValues['tag1'] ?? '—').toString();
    final taskLevel = (raw['taskLevel'] ?? detail.formValues['taskLevel'] ?? 'C').toString();
    final coverage = raw['coverage'] ?? detail.formValues['provinces'];
    final tone = detailStatusTone(detail.status);

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
                style: DunesTypography.mono(fontSize: 11, color: DunesColors.text3),
              ),
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _metaChip(Icons.sell_outlined, tag1),
              _metaChip(Icons.bar_chart_outlined, '$taskLevel 级'),
              _metaChip(Icons.location_on_outlined, fmtList(coverage)),
            ],
          ),
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
        Text(text, style: DunesTypography.sans(fontSize: 11, color: DunesColors.text2)),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: DunesTypography.sans(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
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
                '提案已作废',
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
              border: Border(left: BorderSide(color: DunesColors.border, width: 3)),
            ),
            child: Text(
              '该提案已关闭，不可重新填写或再次提交。',
              style: DunesTypography.sans(fontSize: 12, height: 1.55, color: DunesColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class XfDetRejectBanner extends StatelessWidget {
  const XfDetRejectBanner({super.key, required this.detail, required this.info});

  final XflowProposalDetail detail;
  final RejectStepInfo? info;

  @override
  Widget build(BuildContext context) {
    if (detail.status.toLowerCase() != 'rejected') return const SizedBox.shrink();
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
          Text(meta, style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DunesColors.coral.withValues(alpha: 0.12)),
            ),
            child: Text(
              comment,
              style: DunesTypography.sans(fontSize: 12, height: 1.55, color: DunesColors.text2),
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
        (raw['owner1'] ?? d.ownerName).toString().ifEmpty(raw['initiator']?.toString() ?? '—'),
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
    final cur = currentApproverLabel(bundle.trail, bundle.assigneeNames, bundle.stages);
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
                      style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
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
    if (st != 'pending' && st != 'pending_initiate') return const SizedBox.shrink();
    if (bundle.myTodo != null) return const SizedBox.shrink();
    var who = currentApproverLabel(bundle.trail, bundle.assigneeNames, bundle.stages);
    if (who.isEmpty) who = '审批人';
    return XfDetCard(
      title: '审批进行中',
      icon: Icons.hourglass_empty,
      child: Text.rich(
        TextSpan(
          style: DunesTypography.sans(fontSize: 12, height: 1.5, color: DunesColors.text2),
          children: [
            const TextSpan(text: '当前节点：'),
            TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700)),
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
    if (draftedBy == null && pushMessage.isEmpty) return const SizedBox.shrink();
    final by = draftedBy is Map ? Map<String, dynamic>.from(draftedBy) : <String, dynamic>{};
    return XfDetCard(
      title: '运营推送上下文',
      icon: Icons.send_outlined,
      child: Column(
        children: [
          _pushRow('推送人', (by['name'] ?? '—').toString()),
          _pushRow('部门', (by['dept'] ?? '—').toString()),
          if ((by['at'] ?? '').toString().isNotEmpty)
            _pushRow('时间', (by['at'] ?? '').toString()),
          if (pushMessage.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DunesColors.bgSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pushMessage,
                style: DunesTypography.sans(fontSize: 12, height: 1.5, color: DunesColors.text2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pushRow(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft.withValues(alpha: 0.6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2)),
          Text(v, style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class XfDetTabsWrap extends StatefulWidget {
  const XfDetTabsWrap({
    super.key,
    required this.bundle,
    required this.service,
    required this.showTrack,
  });

  final XflowDetailBundle bundle;
  final XflowService service;
  final bool showTrack;

  @override
  State<XfDetTabsWrap> createState() => _XfDetTabsWrapState();
}

class _XfDetTabsWrapState extends State<XfDetTabsWrap> {
  String _tab = 'content';

  @override
  Widget build(BuildContext context) {
    final cfg = widget.bundle.detailConfig;
    var sections = buildSectionsByDetailConfig(
      widget.bundle.fields,
      widget.bundle.detail.formValues,
      cfg,
      widget.bundle.detail,
    );
    if (sections.isEmpty) {
      sections = buildFieldSections(
        widget.bundle.fields,
        widget.bundle.detail.formValues,
        widget.bundle.detail,
      );
    }

    return XfDetCard(
      marginBottom: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tabBtn('content', '填报内容'),
              if (widget.showTrack) ...[
                const SizedBox(width: 4),
                _tabBtn('track', '流程追踪'),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_tab == 'content')
            XfDetFormSections(sections: sections, service: widget.service)
          else
            XfDetTrackTimeline(bundle: widget.bundle),
        ],
      ),
    );
  }

  Widget _tabBtn(String id, String label) {
    final on = _tab == id;
    return Expanded(
      child: Material(
        color: on ? DunesColors.accent : DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _tab = id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : DunesColors.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class XfDetFormSections extends StatelessWidget {
  const XfDetFormSections({super.key, required this.sections, required this.service});

  final List<DetailSection> sections;
  final XflowService service;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Text('暂无填报内容', style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3));
    }
    return Column(
      children: [
        for (var si = 0; si < sections.length; si++)
          _SectionBlock(section: sections[si], sectionIndex: si, service: service),
      ],
    );
  }
}

class _SectionBlock extends StatefulWidget {
  const _SectionBlock({
    required this.section,
    required this.sectionIndex,
    required this.service,
  });

  final DetailSection section;
  final int sectionIndex;
  final XflowService service;

  @override
  State<_SectionBlock> createState() => _SectionBlockState();
}

class _SectionBlockState extends State<_SectionBlock> {
  bool _expanded = false;

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
            style: DunesTypography.sans(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final item in visible)
            item.expandable
                ? XfDetKvExpand(item: item, service: widget.service)
                : XfDetKv(label: item.label, value: item.value),
          if (hiddenCount > 0)
            TextButton(
              onPressed: () => setState(() => _expanded = true),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(vertical: 9),
                foregroundColor: DunesColors.accentDeep,
                backgroundColor: DunesColors.bgSoft,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  '展开剩余 $hiddenCount 项',
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class XfDetKv extends StatelessWidget {
  const XfDetKv({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DunesColors.borderSoft.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
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
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DunesColors.borderSoft.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.value,
                        style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more, size: 14, color: DunesColors.text3),
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
        items: normalizeUploadItems(item.rawValue)
            .where((e) => e['status'] != 'error')
            .toList(growable: false),
        service: service,
      );
    }
    return XfDetTable(field: item.field, rows: normalizeDynamicListValue(item.rawValue));
  }
}

class XfDetTable extends StatelessWidget {
  const XfDetTable({super.key, required this.field, required this.rows});

  final XflowField field;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('暂无明细', style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3));
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

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: DunesColors.borderSoft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 120,
          columnSpacing: 16,
          horizontalMargin: 10,
          headingTextStyle: DunesTypography.sans(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: DunesColors.text3,
          ),
          dataTextStyle: DunesTypography.sans(fontSize: 11.5, color: DunesColors.text2, height: 1.45),
          columns: [
            for (final col in cols)
              DataColumn(label: Text((col['label'] ?? col['key'] ?? '').toString())),
          ],
          rows: [
            for (final row in rows) ...[
              DataRow(
                cells: [
                  for (final col in cols)
                    DataCell(
                      Text(formatCellDisplay(row[col['key']], col, row)),
                    ),
                ],
              ),
              if (row[nestedKey] is List && (row[nestedKey] as List).isNotEmpty)
                DataRow(
                  cells: [
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          XfDetTable(
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
                        ],
                      ),
                    ),
                    for (var i = 1; i < cols.length; i++) const DataCell(SizedBox.shrink()),
                  ],
                ),
            ],
          ],
        ),
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
      return Text('暂无文件', style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3));
    }
    return Column(
      children: [
        for (final it in items) _FileItem(item: it, service: service),
      ],
    );
  }
}

class _FileItem extends StatelessWidget {
  const _FileItem({required this.item, required this.service});

  final Map<String, dynamic> item;
  final XflowService service;

  bool get _isImage {
    final name = (item['fileName'] ?? '').toString().toLowerCase();
    final mime = (item['mimeType'] ?? '').toString().toLowerCase();
    return mime.startsWith('image/') ||
        RegExp(r'\.(jpg|jpeg|png|heic|heif|gif|webp)$').hasMatch(name);
  }

  String _formatSize(dynamic bytes) {
    final n = (bytes is num) ? bytes.toInt() : int.tryParse('$bytes') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _open(BuildContext context, {required bool download}) async {
    final url = await service.resolveFileUrl(item);
    if (url.isEmpty) {
      if (context.mounted) {
        showDunesToast(context, '无法获取文件链接', kind: DunesToastKind.error);
      }
      return;
    }
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showDunesToast(context, '无法打开链接', kind: DunesToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (item['fileName'] ?? item['name'] ?? '未命名文件').toString();
    final size = item['size'];
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
              color: DunesColors.accentDeep,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                if (size != null)
                  Text(
                    _formatSize(size),
                    style: DunesTypography.sans(fontSize: 10, color: DunesColors.text3),
                  ),
              ],
            ),
          ),
          if (_isImage)
            TextButton(
              onPressed: () => _open(context, download: false),
              child: const Text('预览', style: TextStyle(fontSize: 11)),
            ),
          TextButton(
            onPressed: () => _open(context, download: true),
            child: const Text('下载', style: TextStyle(fontSize: 11)),
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
    final curStep = trail?.currentStep ?? 1;
    final st = detail.status.toLowerCase();

    String assigneeLabel(XflowApprovalStep step, String fallback) {
      if (step.assigneeId > 0 && bundle.assigneeNames.containsKey(step.assigneeId)) {
        return '${bundle.assigneeNames[step.assigneeId]} · $fallback';
      }
      return fallback;
    }

    final nodes = <Widget>[
      _HistoryStep(
        kind: _HistoryKind.done,
        icon: Icons.flag_outlined,
        who: (detail.raw['createdBy']?.toString() ?? '').ifEmpty(detail.ownerName.ifEmpty('发起人')),
        role: '提交人',
        time: fmtDetailTime(trail?.createdAtRaw ?? detail.raw['createdAt']),
        comment: '提交提案 · ${detail.code}',
      ),
    ];

    for (final step in steps) {
      final label = stageLabel(step.stepNo, step.stepType, bundle.stages);
      final who = assigneeLabel(step, label);
      final decision = step.decision.toUpperCase();
      _HistoryKind kind;
      IconData icon;
      String cmt;
      String tm;
      if (decision == 'APPROVED') {
        kind = _HistoryKind.done;
        icon = Icons.check;
        cmt = step.comment.isEmpty ? '已通过' : step.comment;
        tm = fmtDetailTime(step.decidedAtRaw);
      } else if (decision == 'REJECTED') {
        kind = _HistoryKind.rejected;
        icon = Icons.close;
        cmt = step.comment.isEmpty ? '已驳回' : step.comment;
        tm = fmtDetailTime(step.decidedAtRaw);
      } else if (step.stepNo == curStep && st == 'pending') {
        kind = _HistoryKind.cur;
        icon = Icons.schedule;
        cmt = '审批进行中';
        tm = '当前处理';
      } else {
        kind = _HistoryKind.todo;
        icon = Icons.circle_outlined;
        cmt = '待处理';
        tm = '待处理';
      }
      nodes.add(
        _HistoryStep(
          kind: kind,
          icon: icon,
          who: who,
          time: tm,
          comment: cmt,
          stepNo: kind == _HistoryKind.todo ? step.stepNo : null,
        ),
      );
    }

    if (st == 'approved') {
      nodes.add(
        _HistoryStep(
          kind: _HistoryKind.done,
          icon: Icons.check_circle_outline,
          who: '审批通过',
          time: fmtDetailTime(trail?.finishedAtRaw),
          comment: '全部节点已完成',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.route, size: 16, color: DunesColors.text2),
            const SizedBox(width: 6),
            Text('流程追踪', style: DunesTypography.sans(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        ...nodes,
      ],
    );
  }
}

enum _HistoryKind { done, cur, todo, rejected }

class _HistoryStep extends StatelessWidget {
  const _HistoryStep({
    required this.kind,
    required this.icon,
    required this.who,
    required this.time,
    required this.comment,
    this.role,
    this.stepNo,
  });

  final _HistoryKind kind;
  final IconData icon;
  final String who;
  final String time;
  final String comment;
  final String? role;
  final int? stepNo;

  @override
  Widget build(BuildContext context) {
    Color dotBg;
    Color dotFg;
    Color dotBorder;
    switch (kind) {
      case _HistoryKind.done:
        dotBg = DunesColors.greenSoft;
        dotFg = const Color(0xFF085041);
        dotBorder = const Color(0xFFB8E5D2);
      case _HistoryKind.cur:
        dotBg = Colors.white;
        dotFg = DunesColors.accent;
        dotBorder = DunesColors.accent;
      case _HistoryKind.rejected:
        dotBg = DunesColors.coralSoft;
        dotFg = const Color(0xFF993C1D);
        dotBorder = const Color(0xFFF0C4BC);
      case _HistoryKind.todo:
        dotBg = DunesColors.bgSoft;
        dotFg = DunesColors.text3;
        dotBorder = DunesColors.border;
    }

    Color cmtBg = DunesColors.bgSoft;
    Color cmtFg = DunesColors.text2;
    Color cmtBorder = DunesColors.border;
    switch (kind) {
      case _HistoryKind.done:
        cmtBorder = const Color(0xFF1D9E75);
      case _HistoryKind.cur:
        cmtBg = DunesColors.accentSoft;
        cmtFg = DunesColors.accentDeep;
        cmtBorder = DunesColors.accent;
      case _HistoryKind.rejected:
        cmtBg = DunesColors.coralSoft;
        cmtFg = const Color(0xFF993C1D);
        cmtBorder = DunesColors.coral;
      case _HistoryKind.todo:
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dotBg,
              shape: BoxShape.circle,
              border: Border.all(color: dotBorder, width: kind == _HistoryKind.cur ? 2 : 1.5),
            ),
            child: stepNo != null
                ? Text(
                    '$stepNo',
                    style: DunesTypography.mono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: dotFg,
                    ),
                  )
                : Icon(icon, size: 13, color: dotFg),
          ),
          const SizedBox(width: 10),
          Expanded(
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
                            who,
                            style: DunesTypography.sans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: kind == _HistoryKind.todo ? DunesColors.text3 : DunesColors.text,
                            ),
                          ),
                          if (role != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: kind == _HistoryKind.done
                                    ? DunesColors.greenSoft
                                    : DunesColors.bgCard,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                role!,
                                style: DunesTypography.mono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: kind == _HistoryKind.done
                                      ? const Color(0xFF085041)
                                      : DunesColors.text3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      time,
                      style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                  decoration: BoxDecoration(
                    color: cmtBg,
                    borderRadius: BorderRadius.circular(7),
                    border: Border(left: BorderSide(color: cmtBorder, width: 2)),
                  ),
                  child: Text(
                    comment,
                    style: DunesTypography.mono(
                      fontSize: 9.5,
                      height: 1.5,
                      color: cmtFg,
                      fontWeight: kind == _HistoryKind.cur ? FontWeight.w500 : FontWeight.w400,
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
        ? (item['reasons'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).join(' · ')
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
            style: DunesTypography.sans(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (metaParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                metaParts.join(' · '),
                style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3, height: 1.45),
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
            style: DunesTypography.sans(fontSize: 11.5, color: DunesColors.text3, height: 1.45),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '请填写审批意见（必填）',
              hintStyle: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
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
    this.onDelete,
    this.onPush,
    this.onInitiate,
    this.onReedit,
    this.onVoid,
  });

  final XflowProposalDetail detail;
  final bool canReedit;
  final VoidCallback? onDelete;
  final VoidCallback? onPush;
  final VoidCallback? onInitiate;
  final VoidCallback? onReedit;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final st = detail.status.toLowerCase();
    final buttons = <Widget>[];

    if (st == 'draft' || st == 'pending_initiate') {
      if (onDelete != null) {
        buttons.add(_ActBtn(label: '删除草稿', icon: Icons.delete_outline, danger: true, onPressed: onDelete!));
      }
    }
    if (st == 'draft' && onPush != null) {
      buttons.add(_ActBtn(label: '推送给业务负责人', icon: Icons.send_outlined, onPressed: onPush!));
    }
    if (st == 'pending_initiate' && onInitiate != null) {
      buttons.add(_ActBtn(label: '确认发起', icon: Icons.check, primary: true, onPressed: onInitiate!));
    }
    if (st == 'rejected' && canReedit) {
      if (onReedit != null) {
        buttons.add(_ActBtn(label: '重新填写并提交', icon: Icons.edit_outlined, primary: true, onPressed: onReedit!));
      }
      if (onVoid != null) {
        buttons.add(_ActBtn(label: '作废', icon: Icons.delete_outline, danger: true, onPressed: onVoid!));
      }
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
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
                  style: DunesTypography.sans(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
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
