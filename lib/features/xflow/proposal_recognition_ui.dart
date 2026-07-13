import 'package:flutter/material.dart';

import 'proposal_archive_models.dart';
import 'proposal_upload_config.dart';

/// 与 [ProposalUploadPage] 上传识别区一致的 Palette D 样式。
class ProposalRecognitionColors {
  const ProposalRecognitionColors._();
  static const card = Color(0xFFFFFFFF);
  static const cardAlt = Color(0xFFFAF9F6);
  static const ink = Color(0xFF232320);
  static const mute = Color(0xFF7A7770);
  static const mute2 = Color(0xFF9A968E);
  static const line = Color(0xFFDED9D0);
  static const line2 = Color(0xFFECE8DE);
  static const coral = Color(0xFFD85A30);
  static const success = Color(0xFF4A7A3E);
  static const danger = Color(0xFFB4443D);
}

/// 上传页 / 详情页共用的 Excel 识别展示（已识别 + 内容预览）。
class ProposalRecognitionView extends StatefulWidget {
  const ProposalRecognitionView({
    super.key,
    required this.summaryFields,
    required this.previewSectionConfig,
    required this.summaryData,
    required this.sections,
    this.archiveId = '',
    this.fileName = '',
    this.fileSize = '',
    this.sheetCount = 0,
    this.baselineMarginRate = 0,
    this.baselineDiscountRate = 0,
    this.onPreviewTap,
    this.initialExpandedSectionIds = const {},
    this.resolveAssetUrl,
    this.authenticatedImageHeaders = const {},
  });

  final List<UploadSummaryFieldConfig> summaryFields;
  final List<UploadPreviewSectionConfig> previewSectionConfig;
  final Map<String, dynamic> summaryData;
  final List<ProposalArchiveSection> sections;
  final String archiveId;
  final String fileName;
  final String fileSize;
  final int sheetCount;
  final double baselineMarginRate;
  final double baselineDiscountRate;
  final VoidCallback? onPreviewTap;
  final Set<String> initialExpandedSectionIds;
  final String Function(String urlOrPath)? resolveAssetUrl;
  final Map<String, String> authenticatedImageHeaders;

  @override
  State<ProposalRecognitionView> createState() => _ProposalRecognitionViewState();
}

class _ProposalRecognitionViewState extends State<ProposalRecognitionView> {
  late Set<String> _expandedIds;

  @override
  void initState() {
    super.initState();
    _expandedIds = {...widget.initialExpandedSectionIds};
  }

  @override
  void didUpdateWidget(covariant ProposalRecognitionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialExpandedSectionIds != widget.initialExpandedSectionIds) {
      _expandedIds = {...widget.initialExpandedSectionIds};
    }
  }

  void _toggleSection(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewSections = _orderedSections();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onPreviewTap != null && widget.archiveId.isNotEmpty) ...[
          _excelPreviewButton(),
          const SizedBox(height: 16),
        ],
        _badgeKicker('已识别', 'EXTRACTED'),
        const SizedBox(height: 10),
        _summaryCard(),
        const SizedBox(height: 18),
        _badgeKicker(
          '内容预览',
          'PREVIEW · ${previewSections.length} SECTIONS',
        ),
        const SizedBox(height: 10),
        if (previewSections.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ProposalRecognitionColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ProposalRecognitionColors.line2, width: 0.6),
            ),
            child: const Text(
              '未配置预览板块',
              style: TextStyle(fontSize: 11, color: ProposalRecognitionColors.mute, height: 1.5),
            ),
          )
        else
          for (final section in previewSections) ...[
            _sectionCard(section),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  List<ProposalArchiveSection> _orderedSections() {
    final byId = {for (final s in widget.sections) s.id: s};
    final out = <ProposalArchiveSection>[];
    for (final cfg in widget.previewSectionConfig) {
      final section = byId[cfg.id];
      if (section == null) continue;
      out.add(
        ProposalArchiveSection(
          id: section.id,
          orderCn: cfg.orderCn.isNotEmpty ? cfg.orderCn : section.orderCn,
          title: cfg.title.isNotEmpty ? cfg.title : section.title,
          preview: section.preview,
          rows: section.rows,
          isFinancial: cfg.accent,
          tierRows: section.tierRows,
        ),
      );
    }
    return out;
  }

  Widget _excelPreviewButton() {
    return Material(
      color: ProposalRecognitionColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onPreviewTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ProposalRecognitionColors.line2, width: 0.6),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ProposalRecognitionColors.coral.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.table_chart_outlined,
                  size: 17,
                  color: ProposalRecognitionColors.coral,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fileName.isEmpty ? 'Excel 原文预览' : widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ProposalRecognitionColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.fileSize.isEmpty
                          ? '打开完整工作簿 · 保留表格、图片与布局'
                          : '${widget.fileSize} · ${widget.sheetCount} sheet',
                      style: const TextStyle(
                        fontSize: 9,
                        color: ProposalRecognitionColors.mute,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: ProposalRecognitionColors.mute2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final rows = <Widget>[];
    for (final field in widget.summaryFields) {
      final value = summaryFieldValue(widget.summaryData, field);
      if (!summaryFieldHasDisplayValue(value)) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 7));
      rows.add(_summaryFieldRow(field, value));
    }
    if (rows.isEmpty) {
      rows.add(
        const Text(
          '未配置识别摘要字段（recognitionConfig.summaryFields）',
          style: TextStyle(fontSize: 11, color: ProposalRecognitionColors.mute, height: 1.5),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ProposalRecognitionColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProposalRecognitionColors.line2, width: 0.6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _summaryFieldRow(UploadSummaryFieldConfig field, dynamic value) {
    final label = field.label.isNotEmpty ? field.label : field.source;
    switch (field.display) {
      case 'mono':
        return _fieldRow(label, valueMono: value.toString());
      case 'chip':
        return _fieldRow(label, child: _coralChip(value.toString()));
      case 'tags':
        final tags = value is Iterable
            ? value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
            : <String>[value.toString()];
        return _fieldRow(
          label,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: tags.map(_neutralChip).toList(),
          ),
        );
      default:
        return _fieldRow(label, valueText: value.toString());
    }
  }

  Widget _sectionCard(ProposalArchiveSection section) {
    final expanded = _expandedIds.contains(section.id);
    final isFinance = section.isFinancial;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: ProposalRecognitionColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFinance
              ? ProposalRecognitionColors.coral.withAlpha(90)
              : ProposalRecognitionColors.line2,
          width: 0.6,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: isFinance
                ? ProposalRecognitionColors.coral.withAlpha(13)
                : Colors.transparent,
            child: InkWell(
              onTap: () => _toggleSection(section.id),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: isFinance
                      ? const Border(
                          left: BorderSide(color: ProposalRecognitionColors.coral, width: 2),
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (section.orderCn.isNotEmpty)
                          Text(
                            section.orderCn,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              color: isFinance
                                  ? ProposalRecognitionColors.coral
                                  : ProposalRecognitionColors.mute2,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (section.orderCn.isNotEmpty) const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            section.title,
                            style: TextStyle(
                              fontSize: 12,
                              color: ProposalRecognitionColors.ink,
                              fontWeight: isFinance ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isFinance) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: ProposalRecognitionColors.coral.withAlpha(38),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text(
                              '灯塔基线',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 8,
                                color: ProposalRecognitionColors.coral,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: isFinance
                                ? ProposalRecognitionColors.coral
                                : ProposalRecognitionColors.mute2,
                          ),
                        ),
                      ],
                    ),
                    if (!expanded && section.preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        section.preview,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: ProposalRecognitionColors.mute,
                          height: 1.5,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (expanded) _sectionExpanded(section),
        ],
      ),
    );
  }

  Widget _sectionExpanded(ProposalArchiveSection section) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < section.rows.length; i++) ...[
            _rowKV(section.rows[i].label, section.rows[i].value),
            if (section.rows[i].images.isNotEmpty) ...[
              const SizedBox(height: 8),
              _rowImages(section.rows[i].images),
            ],
            if (i != section.rows.length - 1) const SizedBox(height: 5),
          ],
          if (section.tierRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '阶梯利润测算 · TIER MODEL',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8,
                color: ProposalRecognitionColors.mute2,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            _tierTable(section.tierRows),
          ],
          if (section.isFinancial) ...[
            const SizedBox(height: 12),
            _baselineEmbed(
              widget.baselineMarginRate,
              widget.baselineDiscountRate,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tierTable(List<ProposalArchiveTierRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: ProposalRecognitionColors.cardAlt,
        border: Border.all(color: ProposalRecognitionColors.line2, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: ProposalRecognitionColors.ink.withAlpha(8),
              border: const Border(
                bottom: BorderSide(color: ProposalRecognitionColors.line2, width: 0.5),
              ),
            ),
            child: const Row(
              children: [
                Expanded(child: _TierHeaderCell('规模', Alignment.centerLeft)),
                Expanded(child: _TierHeaderCell('供货', Alignment.centerRight)),
                Expanded(child: _TierHeaderCell('销售', Alignment.centerRight)),
                Expanded(child: _TierHeaderCell('净利', Alignment.centerRight)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: i != rows.length - 1
                    ? const Border(
                        bottom: BorderSide(color: Color(0xFFF2EFE6), width: 0.5),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TierCell(rows[i].scale, Alignment.centerLeft, ProposalRecognitionColors.ink),
                  ),
                  Expanded(
                    child: _TierCell(
                      '${rows[i].supply.toStringAsFixed(1)}%',
                      Alignment.centerRight,
                      ProposalRecognitionColors.ink,
                    ),
                  ),
                  Expanded(
                    child: _TierCell(
                      '${rows[i].sell.toStringAsFixed(1)}%',
                      Alignment.centerRight,
                      ProposalRecognitionColors.ink,
                    ),
                  ),
                  Expanded(
                    child: _TierCell(
                      rows[i].netProfit.toStringAsFixed(0),
                      Alignment.centerRight,
                      rows[i].netProfit < 0
                          ? ProposalRecognitionColors.danger
                          : (rows[i].netProfit >= 2000
                                ? ProposalRecognitionColors.success
                                : ProposalRecognitionColors.ink),
                      weight: rows[i].netProfit >= 5000 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _baselineEmbed(double marginRate, double discountRate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: ProposalRecognitionColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ProposalRecognitionColors.coral.withAlpha(90), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _baselineStat('目标毛利率', marginRate)),
              const SizedBox(width: 12),
              Expanded(child: _baselineStat('目标销售折扣', discountRate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _baselineStat(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: ProposalRecognitionColors.mute),
        ),
        const SizedBox(height: 2),
        Text(
          value == 0 ? '—' : '${value.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ProposalRecognitionColors.coral,
          ),
        ),
      ],
    );
  }

  Widget _badgeKicker(String label, String subLabel) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: ProposalRecognitionColors.coral.withAlpha(31),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              color: ProposalRecognitionColors.coral,
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
            fontSize: 8.5,
            color: ProposalRecognitionColors.mute2,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.5, color: ProposalRecognitionColors.line)),
      ],
    );
  }

  Widget _fieldRow(String label, {String? valueText, String? valueMono, Widget? child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: ProposalRecognitionColors.mute)),
        const Spacer(),
        if (child != null)
          Flexible(child: Align(alignment: Alignment.centerRight, child: child))
        else if (valueMono != null)
          Text(
            valueMono,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: ProposalRecognitionColors.ink,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            valueText ?? '—',
            style: const TextStyle(
              fontSize: 11,
              color: ProposalRecognitionColors.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _rowKV(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: ProposalRecognitionColors.mute, letterSpacing: 0.1),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 10.5, color: ProposalRecognitionColors.ink, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _rowImages(List<ProposalArchiveImage> images) {
    final resolver = widget.resolveAssetUrl;
    final headers = widget.authenticatedImageHeaders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < images.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final image = images[i];
              final raw = image.url.isNotEmpty ? image.url : image.blobKey;
              if (raw.isEmpty) return const SizedBox.shrink();
              final src = resolver != null ? resolver(raw) : raw;
              if (src.isEmpty) return const SizedBox.shrink();
              return _ProposalArchiveImageThumb(
                src: src,
                headers: headers,
                onTap: () => _openImagePreview(context, src, headers),
              );
            },
          ),
        ],
      ],
    );
  }

  void _openImagePreview(
    BuildContext context,
    String src,
    Map<String, String> headers,
  ) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ProposalArchiveImagePreview(
        src: src,
        headers: headers,
      ),
    );
  }

  Widget _coralChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: ProposalRecognitionColors.coral.withAlpha(31),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          color: ProposalRecognitionColors.coral,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _neutralChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: ProposalRecognitionColors.ink.withAlpha(14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          color: ProposalRecognitionColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TierHeaderCell extends StatelessWidget {
  const _TierHeaderCell(this.text, this.align);
  final String text;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 8,
          color: ProposalRecognitionColors.mute2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TierCell extends StatelessWidget {
  const _TierCell(this.text, this.align, this.color, {this.weight = FontWeight.w500});
  final String text;
  final Alignment align;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          color: color,
          fontWeight: weight,
        ),
      ),
    );
  }
}

class _ProposalArchiveImageThumb extends StatelessWidget {
  const _ProposalArchiveImageThumb({
    required this.src,
    required this.headers,
    required this.onTap,
  });

  final String src;
  final Map<String, String> headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ProposalRecognitionColors.cardAlt,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ProposalRecognitionColors.line2, width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5.4)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: Image.network(
                    src,
                    headers: headers.isEmpty ? null : headers,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    alignment: Alignment.center,
                    errorBuilder: (_, _, _) => Container(
                      height: 96,
                      alignment: Alignment.center,
                      child: const Text(
                        '图片加载失败',
                        style: TextStyle(
                          fontSize: 10,
                          color: ProposalRecognitionColors.mute,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  '点击放大查看',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: ProposalRecognitionColors.mute,
                    letterSpacing: 0.2,
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

class _ProposalArchiveImagePreview extends StatelessWidget {
  const _ProposalArchiveImagePreview({
    required this.src,
    required this.headers,
  });

  final String src;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(
                src,
                headers: headers.isEmpty ? null : headers,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: '关闭',
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Text(
              '双指缩放 · 点击空白处关闭',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
