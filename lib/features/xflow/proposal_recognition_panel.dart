import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'proposal_archive_models.dart';
import 'proposal_excel_preview_page.dart';
import 'proposal_recognition_ui.dart';
import 'proposal_upload_config.dart';
import 'xflow_detail_widgets.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

/// 审批详情页 Excel 识别区（与上传页 [ProposalRecognitionView] 一致）。
class XfDetRecognitionPanel extends StatefulWidget {
  const XfDetRecognitionPanel({
    super.key,
    required this.service,
    required this.detailConfig,
    required this.formValues,
    required this.fields,
    this.detailRaw = const {},
  });

  final XflowService service;
  final Map<String, dynamic> detailConfig;
  final Map<String, dynamic> formValues;
  final List<XflowField> fields;
  final Map<String, dynamic> detailRaw;

  @override
  State<XfDetRecognitionPanel> createState() => _XfDetRecognitionPanelState();
}

class _XfDetRecognitionPanelState extends State<XfDetRecognitionPanel> {
  ProposalArchiveData? _archive;
  bool _loading = true;
  String? _error;

  List<UploadPreviewSectionConfig> get _previewConfig =>
      previewSectionsFromDetailConfig(widget.detailConfig);

  List<UploadSummaryFieldConfig> get _summaryConfig =>
      summaryFieldsFromDetailConfig(widget.detailConfig);

  Set<String> get _initialExpandedIds => _previewConfig
      .where((section) => section.expanded)
      .map((section) => section.id)
      .toSet();

  String? get _archiveId => resolveProposalArchiveId(
    formValues: widget.formValues,
    detailConfig: widget.detailConfig,
    fields: widget.fields,
    detailRaw: widget.detailRaw,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final archiveId = _archiveId;
    final lookupCodes = _archiveLookupCodes;
    if ((archiveId == null || archiveId.isEmpty) && lookupCodes.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? raw;
      if (archiveId != null && archiveId.isNotEmpty) {
        raw = await widget.service.fetchProposalArchive(archiveId);
      } else {
        for (final code in lookupCodes) {
          raw = await widget.service.fetchLatestProposalArchiveByCode(code);
          if (raw != null) break;
        }
      }
      if (!mounted) return;
      setState(() {
        _archive = raw == null ? null : ProposalArchiveData.fromArchiveResponse(raw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> get _archiveLookupCodes {
    final out = <String>[];
    void add(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty || out.contains(s)) return;
      out.add(s);
    }

    final fv = widget.formValues;
    add(fv['title']);
    add(fv['proposalCode']);
    add(fv['proposalId']);
    add(fv['code']);
    final raw = widget.detailRaw;
    add(raw['title']);
    add(raw['proposalCode']);
    add(raw['code']);
    return out;
  }

  Map<String, dynamic> get _summaryData {
    final fv = widget.formValues;
    final archive = _archive;
    if (archive != null) {
      return uploadSummaryData(
        proposalId: archive.proposalId.isNotEmpty
            ? archive.proposalId
            : (fv['proposalCode'] ?? '').toString(),
        proposalType: archive.proposalType.isNotEmpty
            ? archive.proposalType
            : (fv['proposalType'] ?? '').toString(),
        productTags: archive.productTags.isNotEmpty
            ? archive.productTags
            : _stringList(fv['tag1']),
        channel: archive.channel.isNotEmpty
            ? archive.channel
            : (fv['launchChannel'] ?? '').toString(),
        province: archive.province.isNotEmpty
            ? archive.province
            : _provinceText(fv['provinces']),
        profitModel: archive.profitModel != '未识别'
            ? archive.profitModel
            : (fv['profitModel'] ?? '').toString(),
        fileName: archive.fileName,
      );
    }
    return uploadSummaryData(
      proposalId: (fv['proposalCode'] ?? fv['proposalId'] ?? '').toString(),
      proposalType: (fv['proposalType'] ?? '').toString(),
      productTags: _stringList(fv['tag1']),
      channel: (fv['launchChannel'] ?? fv['channel'] ?? '').toString(),
      province: _provinceText(fv['provinces']),
      profitModel: (fv['profitModel'] ?? '').toString(),
      fileName: (fv['sourceFileName'] ?? '').toString(),
    );
  }

  bool get _hasSummaryFallback {
    final data = _summaryData;
    return _summaryConfig.any(
      (field) => summaryFieldHasDisplayValue(summaryFieldValue(data, field)),
    );
  }

  Future<void> _openExcelPreview(ProposalArchiveData archive) async {
    await openProposalExcelPreview(
      context: context,
      session: widget.service.session,
      archiveId: archive.archiveId,
      fileName: archive.fileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasArchiveHint =
        (_archiveId != null && _archiveId!.isNotEmpty) ||
        _archiveLookupCodes.isNotEmpty;
    if (!hasArchiveHint && !_hasSummaryFallback && _archive == null) {
      return const SizedBox.shrink();
    }

    return XfDetCard(
      title: 'Excel 识别内容',
      icon: Icons.table_chart_outlined,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    '识别详情加载失败，以下为已提交摘要',
                    style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
                  ),
                  const SizedBox(height: 12),
                ],
                ProposalRecognitionView(
                  summaryFields: _summaryConfig,
                  previewSectionConfig: _previewConfig,
                  summaryData: _summaryData,
                  sections: _archive?.previewSections(_previewConfig) ?? const [],
                  archiveId: _archive?.archiveId ?? '',
                  fileName: _archive?.fileName ?? '',
                  fileSize: _archive?.fileSize ?? '',
                  sheetCount: _archive?.sheetCount ?? 0,
                  baselineMarginRate: _archive?.baselineMarginRate ?? 0,
                  baselineDiscountRate: _archive?.baselineDiscountRate ?? 0,
                  initialExpandedSectionIds: _initialExpandedIds,
                  resolveAssetUrl: widget.service.resolveProposalAssetUrl,
                  authenticatedImageHeaders: widget.service.authImageHeaders,
                  onPreviewTap: _archive != null && _archive!.archiveId.isNotEmpty
                      ? () => _openExcelPreview(_archive!)
                      : null,
                ),
              ],
            ),
    );
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (raw == null) return const [];
    final text = raw.toString().trim();
    return text.isEmpty ? const [] : [text];
  }

  String _provinceText(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).join('、');
    }
    return raw?.toString() ?? '';
  }
}
