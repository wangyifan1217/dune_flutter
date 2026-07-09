import 'proposal_upload_config.dart';
import 'xflow_models.dart';
import 'xflow_template_runtime.dart';

class ProposalArchiveRow {
  const ProposalArchiveRow(this.label, this.value);
  final String label;
  final String value;
}

class ProposalArchiveTierRow {
  const ProposalArchiveTierRow({
    required this.scale,
    required this.supply,
    required this.sell,
    required this.netProfit,
  });

  final String scale;
  final double supply;
  final double sell;
  final double netProfit;

  factory ProposalArchiveTierRow.fromJson(Object? raw) {
    final json = _asMap(raw) ?? const <String, dynamic>{};
    return ProposalArchiveTierRow(
      scale: _string(json['scale']),
      supply: _double(json['supply']),
      sell: _double(json['sell']),
      netProfit: _double(json['net_profit']),
    );
  }
}

class ProposalArchiveSection {
  const ProposalArchiveSection({
    required this.id,
    required this.orderCn,
    required this.title,
    required this.preview,
    required this.rows,
    this.isFinancial = false,
    this.tierRows = const [],
  });

  final String id;
  final String orderCn;
  final String title;
  final String preview;
  final List<ProposalArchiveRow> rows;
  final bool isFinancial;
  final List<ProposalArchiveTierRow> tierRows;

  factory ProposalArchiveSection.fromJson(
    Object? raw, {
    List<ProposalArchiveTierRow>? tierRows,
  }) {
    final json = _asMap(raw) ?? const <String, dynamic>{};
    final id = _string(json['id']);
    final rows = _asList(json['rows'])
        .map((row) {
          final map = _asMap(row) ?? const <String, dynamic>{};
          return ProposalArchiveRow(_string(map['label']), _string(map['value']));
        })
        .where((row) => row.label.isNotEmpty || row.value.isNotEmpty)
        .toList(growable: false);
    final sectionTierRows =
        tierRows ??
        _asList(json['tier_rows'])
            .map(ProposalArchiveTierRow.fromJson)
            .toList(growable: false);
    return ProposalArchiveSection(
      id: id,
      orderCn: _string(json['order_cn']),
      title: _string(json['title']),
      preview: _string(json['preview'], fallback: _buildSectionPreview(rows)),
      rows: rows,
      isFinancial: id == 'finance',
      tierRows: sectionTierRows,
    );
  }
}

class ProposalArchiveData {
  const ProposalArchiveData({
    required this.archiveId,
    required this.fileName,
    required this.fileSize,
    required this.sheetCount,
    required this.proposalId,
    required this.proposalType,
    required this.productTags,
    required this.channel,
    required this.province,
    required this.profitModel,
    required this.sections,
    required this.baselineMarginRate,
    required this.baselineDiscountRate,
  });

  final String archiveId;
  final String fileName;
  final String fileSize;
  final int sheetCount;
  final String proposalId;
  final String proposalType;
  final List<String> productTags;
  final String channel;
  final String province;
  final String profitModel;
  final List<ProposalArchiveSection> sections;
  final double baselineMarginRate;
  final double baselineDiscountRate;

  factory ProposalArchiveData.fromArchiveResponse(Map<String, dynamic> json) {
    final data = _asMap(json['data']) ?? json;
    final proposal = _asMap(data['proposal']) ?? data;
    final file = _asMap(proposal['file']) ?? const <String, dynamic>{};
    final baseline = _asMap(proposal['baseline']) ?? const <String, dynamic>{};
    final tierRows = _asList(proposal['tier_rows'])
        .map(ProposalArchiveTierRow.fromJson)
        .toList(growable: false);
    final sections = _asList(proposal['sections'])
        .map((section) {
          final id = _string(_asMap(section)?['id']);
          return ProposalArchiveSection.fromJson(
            section,
            tierRows: id == 'finance' ? tierRows : null,
          );
        })
        .toList(growable: false);

    return ProposalArchiveData(
      archiveId: _string(proposal['id']),
      fileName: _string(file['filename'], fallback: '未命名提案.xlsx'),
      fileSize: _formatBytes(_int(file['size'])),
      sheetCount: _int(file['sheet_count']),
      proposalId: _string(proposal['proposal_code']),
      proposalType: _string(proposal['type']),
      productTags: _stringList(proposal['product_tags']),
      channel: _string(proposal['channel']),
      province: _string(proposal['province']),
      profitModel: _string(proposal['profit_model'], fallback: '未识别'),
      sections: sections,
      baselineMarginRate: _double(baseline['margin_rate']),
      baselineDiscountRate: _double(baseline['discount_rate']),
    );
  }

  List<ProposalArchiveSection> previewSections(
    List<UploadPreviewSectionConfig> config,
  ) {
    final byId = {for (final section in sections) section.id: section};
    final out = <ProposalArchiveSection>[];
    for (final cfg in config) {
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
}

String? resolveProposalArchiveId({
  required Map<String, dynamic> formValues,
  required Map<String, dynamic> detailConfig,
  required List<XflowField> fields,
  Map<String, dynamic>? detailRaw,
}) {
  final recognition = detailConfig['recognitionConfig'];
  if (recognition is Map) {
    final uploadKey = (recognition['uploadFieldKey'] ?? '').toString().trim();
    if (uploadKey.isNotEmpty) {
      final value = formValues[uploadKey];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
  }
  for (final key in ['proposalExcel', 'proposalArchiveId']) {
    final value = formValues[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  if (detailRaw != null) {
    for (final key in ['proposalArchiveId', 'archiveId']) {
      final value = detailRaw[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
  }
  final uploadField = findPrimaryUploadField(fields);
  if (uploadField != null) {
    final value = formValues[uploadField.key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return null;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const <Object?>[];
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _stringList(Object? value) {
  return _asList(value)
      .map((item) => _string(item))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '-';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

String _buildSectionPreview(List<ProposalArchiveRow> rows) {
  final parts = rows
      .take(3)
      .map((row) {
        if (row.label.isEmpty) return row.value;
        if (row.value.isEmpty) return row.label;
        return '${row.label}: ${row.value}';
      })
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.join(' · ');
}
