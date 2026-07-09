// proposal_upload_page.dart
//
// 提案上传归档页 · 沙丘审批平台组件
//
// 配色: 炭色 + 珊瑚 accent (palette D)
//   • 主色 charcoal #232320 承载所有结构性元素
//   • 珊瑚 #D85A30 仅用于识别 / 警戒 / 关键强调, 珍稀出现
//   • 暖 off-white 底 #F8F7F5, 卡片纯白 #FFFFFF, hairline 分隔
//
// 状态流: empty → uploading → parsed → (submitted)
//
// 交互:
//   • 5 张内容预览卡, "四·财务数据" 默认展开且珊瑚 accent
//   • 灯塔基线内嵌在财务卡内 (违背检测基准数据)
//   • Excel 识别审批人时间线, 当前步骤珊瑚呼吸圈

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/config/dunes_defaults.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'proposal_archive_models.dart';
import 'proposal_excel_preview_page.dart';
import 'proposal_recognition_ui.dart';
import 'proposal_upload_config.dart';
import 'xflow_form_renderer.dart';
import 'xflow_linkage.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';
import 'xflow_template_runtime.dart';

class ProposalUploadPage extends StatefulWidget {
  const ProposalUploadPage({
    super.key,
    this.onBack,
    required this.session,
    this.service,
    required this.templateKey,
    this.onSubmitted,
  });

  final VoidCallback? onBack;
  final AuthSession session;
  final XflowService? service;
  final String templateKey;
  final void Function(int proposalId)? onSubmitted;

  @override
  State<ProposalUploadPage> createState() => _ProposalUploadPageState();
}

// ══════════════════════════════════════════════════════════════════════
// Palette D · 炭色 + 珊瑚 accent
// ══════════════════════════════════════════════════════════════════════
class _PDColors {
  const _PDColors._();
  static const bg = Color(0xFFF8F7F5);
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

// ══════════════════════════════════════════════════════════════════════
// Data models
// ══════════════════════════════════════════════════════════════════════
enum _UploadState { empty, uploading, parsed }

class _ParsedProposal {
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
  final List<_ProposalSection> sections;
  final double baselineMarginRate;
  final double baselineDiscountRate;
  final Map<String, dynamic> owners;

  _ParsedProposal({
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
    required this.owners,
  });

  factory _ParsedProposal.fromUploadResponse(Map<String, dynamic> json) {
    final data = _asMap(json['data']) ?? json;
    final proposal = _asMap(data['proposal']) ?? data;
    final file = _asMap(proposal['file']) ?? const <String, dynamic>{};
    final baseline = _asMap(proposal['baseline']) ?? const <String, dynamic>{};
    final owners = _asMap(proposal['owners']) ?? const <String, dynamic>{};
    final tierRows = _asList(
      proposal['tier_rows'],
    ).map(_TierRow.fromJson).toList(growable: false);
    final sections = _asList(proposal['sections'])
        .map(
          (section) => _ProposalSection.fromJson(
            section,
            tierRows: _sectionId(section) == 'finance' ? tierRows : null,
          ),
        )
        .toList(growable: false);

    return _ParsedProposal(
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
      owners: owners,
    );
  }

  Map<String, dynamic> toXflowSubmitValues({
    Map<String, List<String>>? extractRules,
  }) {
    final rules = extractRules ?? defaultUploadExtractRules;
    List<String> labels(String key, List<String> fallback) =>
        rules[key] ?? fallback;
    final financeScale = _sectionValue(
      sections,
      labels('targetMonthlyScaleWan', const ['销售规模', '承诺月规模', '月规模']),
    );
    final financeProfit = _sectionValue(
      sections,
      labels('targetMonthlyProfitWan', const ['利润', '承诺月毛利', '月毛利']),
    );
    final launchDate = _sectionValue(
      sections,
      labels('launchDate', const ['上线日期', '计划上线日期']),
    );
    final txType = _sectionValue(sections, labels('txType', const ['交易类型']));
    final goodType =
        _sectionValue(sections, labels('goodType', const ['商品类型'])) ??
        _inferGoodType(productTags);
    final techPlatform = _sectionValue(
      sections,
      labels('techPlatform', const ['技术平台', '技术标签', '技术能力']),
    );
    final owner1 = _firstNonEmpty([
      _string(owners['national']),
      _string(owners['regional']),
      _string(owners['provincial']),
    ]);
    final owner2 = _firstNonEmpty(
      [
        _string(owners['regional']),
        _string(owners['provincial']),
      ].where((name) => name != owner1).toList(growable: false),
    );
    final body = <String, dynamic>{
      'title': _proposalTitle(fileName: fileName, proposalCode: proposalId),
      'proposalCode': proposalId,
      'launchChannel': channel,
      'launchDate': launchDate ?? '',
      'txType': txType ?? '',
      'goodType': goodType ?? '',
      'proposalType': proposalType,
      'tag1': productTags.map(_tagCode).where((tag) => tag.isNotEmpty).toList(),
      'provinces': _splitListText(province),
      'owner1': owner1,
      'owner1Level':
          _sectionValue(
            sections,
            labels('owner1Level', const ['第一责任人等级', '任务等级']),
          ) ??
          '',
      'owner2': owner2,
      'owner2Level':
          _sectionValue(
            sections,
            labels('owner2Level', const ['第二责任人等级']),
          ) ??
          '',
      'techPlatform': techPlatform ?? '',
      'respNational': _string(owners['national']),
      'respOps': _string(owners['regional']),
      'respProvince': _string(owners['provincial']),
      'respTech': _string(owners['tech']),
      'targetMonthlyScaleWan': financeScale ?? '',
      'targetMonthlyProfitWan': financeProfit ?? '',
      'profitModel': profitModel == '未识别' ? '' : profitModel,
      'solutionDesc': _solutionText(sections),
      'proposalArchiveId': archiveId,
      'sourceFileName': fileName,
      'sourceFileSize': fileSize,
      'sourceSheetCount': sheetCount,
    };
    body.removeWhere((_, value) {
      if (value is String) return value.trim().isEmpty;
      if (value is Iterable) return value.isEmpty;
      return value == null;
    });
    return body;
  }
}

class _ProposalSection {
  final String id;
  final String orderCn;
  final String title;
  final String preview;
  final List<_SectionRow> rows;
  final bool isFinancial;
  final List<_TierRow>? tierRows;

  const _ProposalSection({
    required this.id,
    required this.orderCn,
    required this.title,
    required this.preview,
    required this.rows,
    this.isFinancial = false,
    this.tierRows,
  });

  factory _ProposalSection.fromJson(Object? raw, {List<_TierRow>? tierRows}) {
    final json = _asMap(raw) ?? const <String, dynamic>{};
    final id = _string(json['id']);
    final rows = _asList(json['rows'])
        .map((row) {
          final map = _asMap(row) ?? const <String, dynamic>{};
          return _SectionRow(_string(map['label']), _string(map['value']));
        })
        .where((row) => row.label.isNotEmpty || row.value.isNotEmpty)
        .toList(growable: false);
    final sectionTierRows =
        tierRows ??
        _asList(
          json['tier_rows'],
        ).map(_TierRow.fromJson).toList(growable: false);
    return _ProposalSection(
      id: id,
      orderCn: _string(json['order_cn']),
      title: _string(json['title']),
      preview: _string(json['preview'], fallback: _buildSectionPreview(rows)),
      rows: rows,
      isFinancial: id == 'finance',
      tierRows: sectionTierRows.isEmpty ? null : sectionTierRows,
    );
  }
}

class _SectionRow {
  final String label;
  final String value;
  const _SectionRow(this.label, this.value);
}

class _TierRow {
  final String scale;
  final double supply;
  final double sell;
  final double netProfit; // 单位: 万

  const _TierRow({
    required this.scale,
    required this.supply,
    required this.sell,
    required this.netProfit,
  });

  factory _TierRow.fromJson(Object? raw) {
    final json = _asMap(raw) ?? const <String, dynamic>{};
    return _TierRow(
      scale: _string(json['scale']),
      supply: _double(json['supply']),
      sell: _double(json['sell']),
      netProfit: _double(json['net_profit']),
    );
  }
}

class _UploadException implements Exception {
  final String message;
  const _UploadException(this.message);

  @override
  String toString() => message;
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

String _sectionId(Object? raw) => _string(_asMap(raw)?['id']);

String _formatBytes(int bytes) {
  if (bytes <= 0) return '-';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

String _buildSectionPreview(List<_SectionRow> rows) {
  final parts = rows
      .take(3)
      .map((row) => row.value)
      .where((value) => value.isNotEmpty)
      .map((value) {
        final runes = value.runes.toList();
        if (runes.length <= 30) return value;
        return '${String.fromCharCodes(runes.take(30))}…';
      })
      .toList(growable: false);
  return parts.join(' · ');
}

String? _sectionValue(List<_ProposalSection> sections, List<String> labels) {
  for (final section in sections) {
    for (final row in section.rows) {
      final label = row.label.trim();
      if (label.isEmpty) continue;
      if (labels.any(label.contains) && row.value.trim().isNotEmpty) {
        return row.value.trim();
      }
    }
  }
  return null;
}

String _solutionText(List<_ProposalSection> sections) {
  final parts = <String>[];
  for (final section in sections) {
    if (section.id != 'business' && section.id != 'solution') continue;
    for (final row in section.rows) {
      final value = row.value.trim();
      if (value.isNotEmpty) parts.add(value);
    }
  }
  if (parts.isNotEmpty) return parts.join('\n');
  return sections
      .expand((section) => section.rows)
      .map((row) => row.value.trim())
      .where((value) => value.isNotEmpty)
      .take(8)
      .join('\n');
}

String _proposalTitle({
  required String fileName,
  required String proposalCode,
}) {
  if (proposalCode.isNotEmpty) return proposalCode;
  return fileName.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '');
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

List<String> _splitListText(String value) {
  return value
      .split(RegExp(r'[,，、/;\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _tagCode(String tag) {
  final text = tag.trim();
  const known = {
    '成品油零售': 'RETAIL_FUEL',
    '电子券': 'COUPON',
    '加油卡': 'FUEL_CARD',
    '保险': 'INSURANCE',
    'SaaS': 'SAAS',
    'SAAS': 'SAAS',
    '权益券包': 'BENEFIT_PACK',
  };
  if (known.containsValue(text)) return text;
  return known[text] ?? '';
}

String? _inferGoodType(List<String> tags) {
  final text = tags.join(' ');
  if (text.contains('油')) return '油品';
  if (text.contains('券') ||
      text.contains('保险') ||
      text.toLowerCase().contains('saas')) {
    return '虚拟商品';
  }
  return null;
}

String _friendlySubmitError(Object err) {
  if (err is _UploadException) return err.message;
  final text = err.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}

// ══════════════════════════════════════════════════════════════════════
// State
// ══════════════════════════════════════════════════════════════════════
class _ProposalUploadPageState extends State<ProposalUploadPage> {
  _UploadState _state = _UploadState.empty;
  _ParsedProposal? _parsed;
  final Set<String> _expandedIds = <String>{};
  bool _submitting = false;
  late final XflowService _service;
  XflowTemplateDetail? _template;
  Map<String, dynamic> _detailConfig = const {};
  final Map<String, dynamic> _supplementalValues = <String, dynamic>{};
  bool _configLoading = true;
  String? _configError;
  bool _pickingFile = false;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        XflowService(session: widget.session, templateKey: widget.templateKey);
    _loadTemplateConfig();
  }

  Future<void> _loadTemplateConfig() async {
    setState(() {
      _configLoading = true;
      _configError = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchTemplateDetail(
          templateKey: widget.templateKey,
          includeDictEnrich: true,
        ),
        _service.fetchDetailConfig(templateKey: widget.templateKey),
      ]);
      if (!mounted) return;
      final template = results[0] as XflowTemplateDetail;
      final detailConfig = Map<String, dynamic>.from(results[1] as Map);
      final supplemental = supplementalFormFields(template.fields);
      if (!mounted) return;
      setState(() {
        _template = template;
        _detailConfig = detailConfig;
        _configLoading = false;
        for (final field in supplemental) {
          _supplementalValues.putIfAbsent(field.key, () => '');
        }
        _supplementalValues.removeWhere(
          (key, _) => supplemental.every((field) => field.key != key),
        );
        _expandedIds
          ..clear()
          ..addAll(
            previewSectionsFromDetailConfig(detailConfig)
                .where((section) => section.expanded)
                .map((section) => section.id),
          );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _configError = e.toString();
        _configLoading = false;
      });
    }
  }

  String get _pageTitle => templateTitleFromDetail(_template, fallback: '销售提案');

  String get _pageSubtitle => templateSubtitleFromDetail(_template);

  XflowField? get _uploadField =>
      findPrimaryUploadField(_template?.fields ?? const []);

  List<XflowField> get _supplementalFields =>
      supplementalFormFields(_template?.fields ?? const []);

  Map<String, List<String>> get _extractRules =>
      extractRulesFromDetailConfig(_detailConfig);

  List<UploadPreviewSectionConfig> get _previewSectionConfig =>
      previewSectionsFromDetailConfig(_detailConfig);

  List<UploadSummaryFieldConfig> get _summaryFields =>
      summaryFieldsFromDetailConfig(_detailConfig);

  List<Map<String, dynamic>> get _approvalStages =>
      approvalStagesFromDetailConfig(_detailConfig);

  bool get _canSubmit =>
      _state == _UploadState.parsed && _parsed != null && !_submitting;

  String get _apiBase {
    final base = widget.session.apiBase.trim();
    if (base.isNotEmpty) return base.replaceAll(RegExp(r'/$'), '');
    return DunesDefaults.apiBase;
  }

  String get _templateKey {
    final key = widget.templateKey.trim();
    return key.isEmpty ? XflowService.salesTemplateKey : key;
  }

  Map<String, String> get _authHeaders {
    final headers = <String, String>{};
    final token = widget.session.token.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  void _applyParsedToForm(_ParsedProposal parsed) {
    final extracted = parsed.toXflowSubmitValues(extractRules: _extractRules);
    for (final field in _supplementalFields) {
      final key = field.key;
      if (!extracted.containsKey(key)) continue;
      // 人员字段（如技术负责人）不回填，由用户自行搜索选择。
      final isUser = field.type == 'user' ||
          field.type == 'userSelect' ||
          field.raw['dataSource']?.toString() == 'org_user';
      if (isUser) continue;
      final next = extracted[key];
      if (next == null) continue;
      if (next is String && next.trim().isEmpty) continue;
      if (next is Iterable && next.isEmpty) continue;
      _supplementalValues[key] = next;
    }
    final template = _template;
    if (template != null) {
      XflowLinkage.recompute(template.fields, template.layout, _supplementalValues);
    }
  }

  void _onFormFieldChanged(String key, dynamic value) {
    setState(() {
      _supplementalValues[key] = value;
      final template = _template;
      if (template != null) {
        XflowLinkage.recompute(template.fields, template.layout, _supplementalValues);
      }
    });
  }

  Future<void> _handleUpload() async {
    if (_pickingFile || _state == _UploadState.uploading) return;
    setState(() => _pickingFile = true);
    XFile? file;
    try {
      file = await _pickExcelFile();
    } catch (_) {
      if (mounted) {
        _showUploadError('无法打开文件选择器，请重试');
      }
      return;
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
    if (file == null) return;

    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      _showUploadError('请选择 .xlsx 格式的提案文件');
      return;
    }

    setState(() => _state = _UploadState.uploading);
    try {
      final bytes = await file.readAsBytes();
      final uploadField = _uploadField;
      final maxBytes = uploadField != null
          ? _uploadMaxBytes(uploadField)
          : 5 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        throw _UploadException(
          '文件超过 ${(maxBytes / (1024 * 1024)).toStringAsFixed(0)} MB 限制',
        );
      }
      final parsed = await _uploadAndParse(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _state = _UploadState.parsed;
        _applyParsedToForm(parsed);
        _expandedIds
          ..clear()
          ..addAll(
            _previewSectionConfig
                .where((section) => section.expanded)
                .map((section) => section.id),
          );
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _state = _UploadState.empty);
      _showUploadError(err is _UploadException ? err.message : '上传解析失败：$err');
    }
  }

  /// iOS 需声明 UTI；类型组合异常时逐级降级，避免选择器无法弹出。
  Future<XFile?> _pickExcelFile() async {
    const primary = XTypeGroup(
      label: 'Excel 提案',
      extensions: ['xlsx'],
      mimeTypes: [
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
      uniformTypeIdentifiers: [
        'org.openxmlformats.spreadsheetml.sheet',
        'com.microsoft.excel.xlsx',
      ],
    );
    try {
      return await openFile(acceptedTypeGroups: const [primary]);
    } catch (_) {
      try {
        const fallback = XTypeGroup(
          label: 'Excel 提案',
          extensions: ['xlsx'],
        );
        return await openFile(acceptedTypeGroups: const [fallback]);
      } catch (_) {
        return openFile();
      }
    }
  }

  Future<_ParsedProposal> _uploadAndParse(
    String fileName,
    Uint8List bytes,
  ) async {
    final uri = Uri.parse('$_apiBase/proposals/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_authHeaders);
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ),
    );

    final streamed = await req.send();
    final bodyText = await streamed.stream.bytesToString();
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(bodyText);
      body = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      throw _UploadException('服务返回不是有效 JSON：HTTP ${streamed.statusCode}');
    }

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final data = _asMap(body['data']);
      throw _UploadException(
        _string(
          data?['message'],
          fallback: _string(
            body['message'],
            fallback: 'HTTP ${streamed.statusCode}',
          ),
        ),
      );
    }
    if (body['success'] == false) {
      final data = _asMap(body['data']);
      throw _UploadException(
        _string(
          data?['message'],
          fallback: _string(body['message'], fallback: '解析失败'),
        ),
      );
    }
    return _ParsedProposal.fromUploadResponse(body);
  }

  void _showUploadError(String message) {
    showDunesToast(context, message, kind: DunesToastKind.error);
  }

  void _showUploadSuccess(String message) {
    showDunesToast(context, message);
  }

  Future<void> _handleSubmit() async {
    final parsed = _parsed;
    if (parsed == null || _submitting) return;
    final missing = firstMissingRequiredSupplementalField(
      _supplementalFields,
      _supplementalValues,
    );
    if (missing != null) {
      _showUploadError('请填写$missing');
      return;
    }
    final ok = await confirmSubmitForApproval(context);
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      final values = parsed.toXflowSubmitValues(extractRules: _extractRules);
      // 人员类字段不走 Excel 回填值，只认用户在表单里选择的结果。
      for (final field in _supplementalFields) {
        final isUser = field.type == 'user' ||
            field.type == 'userSelect' ||
            field.raw['dataSource']?.toString() == 'org_user';
        if (isUser) values.remove(field.key);
      }
      final uploadKey = _uploadField?.key.trim() ?? '';
      if (uploadKey.isNotEmpty && parsed.archiveId.isNotEmpty) {
        values[uploadKey] = parsed.archiveId;
      }
      for (final field in _supplementalFields) {
        final value = _supplementalValues[field.key];
        if (!supplementalFieldHasValue(value, field: field)) continue;
        values[field.key] = value;
      }
      final res = await _submitToXflow(values);
      final businessId = _int(
        res['businessId'] ?? res['proposalId'] ?? res['id'],
      );
      if (!mounted) return;
      _showUploadSuccess(
        businessId > 0 ? '已提交审批 · 提案 #$businessId' : '已提交审批',
      );
      if (businessId > 0) {
        widget.onSubmitted?.call(businessId);
      }
    } catch (err) {
      if (!mounted) return;
      _showUploadError('提交审批失败：${_friendlySubmitError(err)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<Map<String, dynamic>> _submitToXflow(
    Map<String, dynamic> values,
  ) async {
    final uri = Uri.parse(
      '$_apiBase/xflow/templates/${Uri.encodeComponent(_templateKey)}/submit',
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._authHeaders,
    };
    final resp = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(values),
    );
    final decoded = jsonDecode(resp.body);
    final body = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw _UploadException(
        _string(body['message'], fallback: 'HTTP ${resp.statusCode}'),
      );
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return body;
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

  void _resetUpload() {
    setState(() {
      _state = _UploadState.empty;
      _parsed = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_configLoading) {
      return Scaffold(
        backgroundColor: _PDColors.bg,
        appBar: AppBar(
          backgroundColor: _PDColors.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              size: 18,
              color: _PDColors.ink,
            ),
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
          title: const Text(
            '加载模板',
            style: TextStyle(
              color: _PDColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_configError != null) {
      return Scaffold(
        backgroundColor: _PDColors.bg,
        appBar: AppBar(
          backgroundColor: _PDColors.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              size: 18,
              color: _PDColors.ink,
            ),
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
          title: const Text('加载失败'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_configError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _PDColors.bg,
      appBar: AppBar(
        backgroundColor: _PDColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(
          bottom: BorderSide(color: _PDColors.line, width: 0.5),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            size: 18,
            color: _PDColors.ink,
          ),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          _pageTitle,
          style: const TextStyle(
            color: _PDColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(child: _buildScrollContent()),
          XflowXfActionBar(
            label: '提交审批',
            loading: _submitting,
            onPressed: _canSubmit ? _handleSubmit : null,
            onDisabledTap: () =>
                _showUploadError('请先上传并识别 Excel 提案'),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollContent() {
    final parsed = _parsed;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      children: [
        if (_pageSubtitle.isNotEmpty) ...[
          Text(
            _pageSubtitle,
            style: const TextStyle(
              fontSize: 12,
              color: _PDColors.mute,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
        ],
        _buildTemplateForm(),
        if (parsed != null) ...[
          const SizedBox(height: 14),
          ProposalRecognitionView(
            summaryFields: _summaryFields,
            previewSectionConfig: _previewSectionConfig,
            summaryData: uploadSummaryData(
              proposalId: parsed.proposalId,
              proposalType: parsed.proposalType,
              productTags: parsed.productTags,
              channel: parsed.channel,
              province: parsed.province,
              profitModel: parsed.profitModel,
              fileName: parsed.fileName,
            ),
            sections: _previewSectionsFor(parsed)
                .map(
                  (s) => ProposalArchiveSection(
                    id: s.id,
                    orderCn: s.orderCn,
                    title: s.title,
                    preview: s.preview,
                    rows: s.rows
                        .map((r) => ProposalArchiveRow(r.label, r.value))
                        .toList(),
                    isFinancial: s.isFinancial,
                    tierRows: (s.tierRows ?? const [])
                        .map(
                          (t) => ProposalArchiveTierRow(
                            scale: t.scale,
                            supply: t.supply,
                            sell: t.sell,
                            netProfit: t.netProfit,
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
            archiveId: parsed.archiveId,
            fileName: parsed.fileName,
            fileSize: parsed.fileSize,
            sheetCount: parsed.sheetCount,
            baselineMarginRate: parsed.baselineMarginRate,
            baselineDiscountRate: parsed.baselineDiscountRate,
            initialExpandedSectionIds: _previewSectionConfig
                .where((section) => section.expanded)
                .map((section) => section.id)
                .toSet(),
            onPreviewTap: parsed.archiveId.isEmpty
                ? null
                : () => _openExcelPreview(parsed),
          ),
        ],
        _buildWorkflowSection(),
      ],
    );
  }

  Widget _buildTemplateForm() {
    final template = _template;
    if (template == null) return const SizedBox.shrink();
    return XflowFormRenderer(
      fields: template.fields,
      values: _supplementalValues,
      layout: template.layout,
      service: _service,
      embedded: true,
      showProgressCard: false,
      showActionBar: false,
      fieldOverride: _overrideFormField,
      onChanged: _onFormFieldChanged,
    );
  }

  Widget? _overrideFormField(XflowField field) {
    if (field.type != 'upload' &&
        field.raw['actionKind']?.toString() != 'excel-import') {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _buildExcelImportField(field),
    );
  }

  String? _uploadHelpText(XflowField field) {
    final meta = field.raw['meta'];
    if (meta is Map) {
      final fromMeta =
          (meta['helpText'] ?? meta['namingRule'] ?? meta['hint'] ?? '')
              .toString()
              .trim();
      if (fromMeta.isNotEmpty) return fromMeta;
    }
    final help = (field.raw['helpText'] ?? field.raw['hint'] ?? '')
        .toString()
        .trim();
    return help.isEmpty ? null : help;
  }

  String _uploadAcceptHint(XflowField field) {
    final custom = (field.raw['acceptHint'] ?? '').toString().trim();
    if (custom.isNotEmpty) return custom;
    final exts = field.raw['accept'] ?? field.raw['extensions'];
    if (exts is List && exts.isNotEmpty) {
      return exts.map((e) => e.toString()).join(' · ');
    }
    if (field.raw['actionKind']?.toString() == 'excel-import') {
      return '.xlsx';
    }
    return '';
  }

  int _uploadMaxBytes(XflowField field) {
    final raw = field.raw['maxSizeBytes'] ?? field.raw['maxBytes'];
    if (raw is num) return raw.toInt();
    return 5 * 1024 * 1024;
  }

  Widget _buildExcelImportField(XflowField field) {
    if (_state == _UploadState.uploading || _pickingFile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (field.label.trim().isNotEmpty) ...[
            Text(
              field.label.trim(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _PDColors.ink,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _PDColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _PDColors.line2, width: 0.6),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: _PDColors.coral,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      );
    }

    final parsed = _parsed;
    if (_state == _UploadState.parsed && parsed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (field.label.trim().isNotEmpty) ...[
            Text(
              field.label.trim(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _PDColors.ink,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildFileHeader(parsed),
        ],
      );
    }

    final placeholder = field.placeholder.trim();
    final acceptHint = _uploadAcceptHint(field);
    final helpText = _uploadHelpText(field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field.label.trim().isNotEmpty) ...[
          Row(
            children: [
              Text(
                field.label.trim(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _PDColors.ink,
                ),
              ),
              if (field.required)
                const Text(
                  ' *',
                  style: TextStyle(fontSize: 11.5, color: _PDColors.coral),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        if (placeholder.isNotEmpty) ...[
          Text(
            placeholder,
            style: const TextStyle(
              fontSize: 12,
              color: _PDColors.mute,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickingFile || _state == _UploadState.uploading
                ? null
                : _handleUpload,
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: _PDColors.ink.withAlpha(78),
                strokeWidth: 1.4,
                radius: 12,
                dashLen: 6,
                gapLen: 4,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _PDColors.ink.withAlpha(14),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        _pickingFile
                            ? Icons.hourglass_top_outlined
                            : Icons.cloud_upload_outlined,
                        size: 26,
                        color: _PDColors.ink,
                      ),
                    ),
                    if (acceptHint.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        acceptHint,
                        style: const TextStyle(
                          fontSize: 10,
                          color: _PDColors.mute,
                          letterSpacing: 0.3,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (helpText != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _PDColors.coral.withAlpha(13),
              border: const Border(
                left: BorderSide(color: _PDColors.coral, width: 1.5),
              ),
            ),
            child: Text(
              helpText,
              style: const TextStyle(
                fontSize: 10,
                color: _PDColors.mute,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkflowSection() {
    final stageCount = _approvalStages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _badgeKicker(
          '审批流程',
          stageCount > 0 ? '$stageCount-STEP FLOW' : 'NO STAGES',
        ),
        const SizedBox(height: 10),
        _buildStageWorkflow(),
      ],
    );
  }

  List<_ProposalSection> _previewSectionsFor(_ParsedProposal parsed) {
    final byId = <String, _ProposalSection>{
      for (final section in parsed.sections) section.id: section,
    };
    final out = <_ProposalSection>[];
    for (final cfg in _previewSectionConfig) {
      final section = byId[cfg.id];
      if (section == null) continue;
      out.add(
        _ProposalSection(
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

  Widget _buildFileHeader(_ParsedProposal p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _PDColors.line2, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _PDColors.ink.withAlpha(14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 20,
              color: _PDColors.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fileName,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _PDColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.fileSize} · ${p.sheetCount} sheet · 刚刚',
                  style: const TextStyle(
                    fontSize: 9,
                    color: _PDColors.mute,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _resetUpload,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: _PDColors.line, width: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '重新',
                  style: TextStyle(
                    fontSize: 9,
                    color: _PDColors.mute,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExcelPreviewButton(_ParsedProposal p) {
    return Material(
      color: _PDColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: p.archiveId.isEmpty ? null : () => _openExcelPreview(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _PDColors.line2, width: 0.6),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _PDColors.coral.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.table_chart_outlined,
                  size: 17,
                  color: _PDColors.coral,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Excel 原文预览',
                      style: TextStyle(
                        fontSize: 12,
                        color: _PDColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '打开完整工作簿 · 保留表格、图片与布局',
                      style: TextStyle(
                        fontSize: 9,
                        color: _PDColors.mute,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _PDColors.mute2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExcelPreview(_ParsedProposal p) async {
    await openProposalExcelPreview(
      context: context,
      session: widget.session,
      archiveId: p.archiveId,
      fileName: p.fileName,
    );
  }

  Widget _buildExtractedFields(_ParsedProposal p) {
    final summaryData = uploadSummaryData(
      proposalId: p.proposalId,
      proposalType: p.proposalType,
      productTags: p.productTags,
      channel: p.channel,
      province: p.province,
      profitModel: p.profitModel,
      fileName: p.fileName,
    );
    final fields = _summaryFields;
    final rows = <Widget>[];
    for (final field in fields) {
      final value = summaryFieldValue(summaryData, field);
      if (!summaryFieldHasDisplayValue(value)) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 7));
      rows.add(_buildSummaryFieldRow(field, value));
    }
    if (rows.isEmpty) {
      rows.add(
        const Text(
          '未配置识别摘要字段（recognitionConfig.summaryFields）',
          style: TextStyle(fontSize: 11, color: _PDColors.mute, height: 1.5),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _PDColors.line2, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _buildSummaryFieldRow(UploadSummaryFieldConfig field, dynamic value) {
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

  Widget _buildSectionCard(_ProposalSection s) {
    final expanded = _expandedIds.contains(s.id);
    final isFinance = s.isFinancial;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFinance ? _PDColors.coral.withAlpha(90) : _PDColors.line2,
          width: 0.6,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: isFinance
                ? _PDColors.coral.withAlpha(13)
                : Colors.transparent,
            child: InkWell(
              onTap: () => _toggleSection(s.id),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: isFinance
                      ? const Border(
                          left: BorderSide(color: _PDColors.coral, width: 2),
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          s.orderCn,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: isFinance
                                ? _PDColors.coral
                                : _PDColors.mute2,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: _PDColors.ink,
                            fontWeight: isFinance
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        if (isFinance) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _PDColors.coral.withAlpha(38),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text(
                              '灯塔基线',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 8,
                                color: _PDColors.coral,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: isFinance
                                ? _PDColors.coral
                                : _PDColors.mute2,
                          ),
                        ),
                      ],
                    ),
                    if (!expanded) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.preview,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: _PDColors.mute,
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
          if (expanded) _buildSectionExpanded(s),
        ],
      ),
    );
  }

  Widget _buildSectionExpanded(_ProposalSection s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < s.rows.length; i++) ...[
            _rowKV(s.rows[i].label, s.rows[i].value),
            if (i != s.rows.length - 1) const SizedBox(height: 5),
          ],
          if (s.tierRows != null && s.tierRows!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '阶梯利润测算 · TIER MODEL',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8,
                color: _PDColors.mute2,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            _buildTierTable(s.tierRows!),
          ],
          if (s.isFinancial) ...[
            const SizedBox(height: 12),
            _buildBaselineEmbed(
              _parsed!.baselineMarginRate,
              _parsed!.baselineDiscountRate,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTierTable(List<_TierRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: _PDColors.cardAlt,
        border: Border.all(color: _PDColors.line2, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _PDColors.ink.withAlpha(8),
              border: const Border(
                bottom: BorderSide(color: _PDColors.line2, width: 0.5),
              ),
            ),
            child: Row(
              children: const [
                Expanded(child: _TierHeaderCell('规模', Alignment.centerLeft)),
                Expanded(child: _TierHeaderCell('供货', Alignment.centerRight)),
                Expanded(child: _TierHeaderCell('销售', Alignment.centerRight)),
                Expanded(child: _TierHeaderCell('净利', Alignment.centerRight)),
              ],
            ),
          ),
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: i != rows.length - 1
                    ? const Border(
                        bottom: BorderSide(
                          color: Color(0xFFF2EFE6),
                          width: 0.5,
                        ),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TierCell(
                      rows[i].scale,
                      Alignment.centerLeft,
                      color: _PDColors.ink,
                    ),
                  ),
                  Expanded(
                    child: _TierCell(
                      '${rows[i].supply.toStringAsFixed(1)}%',
                      Alignment.centerRight,
                      color: _PDColors.ink,
                    ),
                  ),
                  Expanded(
                    child: _TierCell(
                      '${rows[i].sell.toStringAsFixed(1)}%',
                      Alignment.centerRight,
                      color: _PDColors.ink,
                    ),
                  ),
                  Expanded(
                    child: _TierCell(
                      rows[i].netProfit.toStringAsFixed(0),
                      Alignment.centerRight,
                      color: rows[i].netProfit < 0
                          ? _PDColors.danger
                          : (rows[i].netProfit >= 2000
                                ? _PDColors.success
                                : _PDColors.ink),
                      weight: rows[i].netProfit >= 5000
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBaselineEmbed(double marginRate, double discountRate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _PDColors.coral.withAlpha(90), width: 0.6),
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
          const SizedBox(height: 8),
          Container(height: 0.5, color: _PDColors.coral.withAlpha(60)),
          const SizedBox(height: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF5F5C55),
                fontFamily: 'monospace',
                height: 1.5,
                letterSpacing: 0.2,
              ),
              children: [
                TextSpan(text: '→ 归档后作为该产品在灯塔的'),
                TextSpan(
                  text: '违背检测基准',
                  style: TextStyle(
                    color: _PDColors.coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
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
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 8,
            color: _PDColors.mute,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value.toStringAsFixed(1),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: _PDColors.coral,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 1),
            const Text(
              '%',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: _PDColors.coral,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStageWorkflow() {
    final stages = _approvalStages;
    if (stages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _PDColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _PDColors.line2, width: 0.6),
        ),
        child: const Text(
          '未配置审批阶段，请在模板设计器「审批阶段」中维护',
          style: TextStyle(fontSize: 11, color: _PDColors.mute, height: 1.5),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _PDColors.line2, width: 0.6),
      ),
      child: Column(
        children: [
          for (int i = 0; i < stages.length; i++)
            _buildStageRow(
              stages[i],
              stepNo: i + 1,
              isLast: i == stages.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildStageRow(
    Map<String, dynamic> stage, {
    required int stepNo,
    required bool isLast,
  }) {
    final stageName =
        (stage['stageName'] ?? stage['name'] ?? stage['label'] ?? '审批步骤')
            .toString();
    final meta = uploadStageMetaLabel(stage);
    const dotSize = 12.0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: dotSize + 2,
            child: Column(
              children: [
                _pendingStageDot(),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 0.5,
                      color: _PDColors.line2,
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
                          '$stepNo. $stageName',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _PDColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '待发起',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 8,
                          color: _PDColors.mute2,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      color: _PDColors.mute2,
                      letterSpacing: 0.2,
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

  Widget _pendingStageDot() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: _PDColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFC9C3B7), width: 1),
      ),
    );
  }

  // ────────── helpers ──────────

  Widget _badgeKicker(String label, String subLabel, {String? trailing}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _PDColors.coral.withAlpha(31),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              color: _PDColors.coral,
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
            color: _PDColors.mute2,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.5, color: _PDColors.line)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: _PDColors.coral,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldRow(
    String label, {
    String? valueText,
    String? valueMono,
    Widget? child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: _PDColors.mute),
        ),
        const Spacer(),
        if (child != null)
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: child),
          )
        else if (valueMono != null)
          Text(
            valueMono,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: _PDColors.ink,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            valueText ?? '—',
            style: const TextStyle(
              fontSize: 11,
              color: _PDColors.ink,
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
            style: const TextStyle(
              fontSize: 10.5,
              color: _PDColors.mute,
              letterSpacing: 0.1,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 10.5,
              color: _PDColors.ink,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _coralChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: _PDColors.coral.withAlpha(31),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          color: _PDColors.coral,
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
        color: _PDColors.ink.withAlpha(14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          color: _PDColors.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Tier table cells (extracted to reduce main class size)
// ══════════════════════════════════════════════════════════════════════
class _TierHeaderCell extends StatelessWidget {
  final String text;
  final Alignment align;
  const _TierHeaderCell(this.text, this.align);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 8,
          color: _PDColors.mute,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TierCell extends StatelessWidget {
  final String text;
  final Alignment align;
  final Color color;
  final FontWeight weight;
  const _TierCell(
    this.text,
    this.align, {
    required this.color,
    this.weight = FontWeight.w500,
  });

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

// ══════════════════════════════════════════════════════════════════════
// Dashed border painter (drop zone)
// ══════════════════════════════════════════════════════════════════════
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLen;
  final double gapLen;

  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLen,
    required this.gapLen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final endDist = distance + dashLen;
        canvas.drawPath(
          metric.extractPath(distance, endDist.clamp(0, metric.length)),
          paint,
        );
        distance = endDist + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius ||
      old.dashLen != dashLen ||
      old.gapLen != gapLen;
}
