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
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/dunes_defaults.dart';
import '../auth/auth_session.dart';

class ProposalUploadPage extends StatefulWidget {
  const ProposalUploadPage({super.key, this.onBack, this.session});

  final VoidCallback? onBack;
  final AuthSession? session;

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

enum _ApprovalStatus { done, current, pending }

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
  final List<_Approver> approvers;
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
    required this.approvers,
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
      approvers: _buildApprovers(owners),
      owners: owners,
    );
  }

  Map<String, dynamic> toXflowSubmitValues() {
    final financeScale = _sectionValue(sections, const [
      '销售规模',
      '承诺月规模',
      '月规模',
    ]);
    final financeProfit = _sectionValue(sections, const ['利润', '承诺月毛利', '月毛利']);
    final launchDate = _sectionValue(sections, const ['上线日期', '计划上线日期']);
    final txType = _sectionValue(sections, const ['交易类型']);
    final goodType =
        _sectionValue(sections, const ['商品类型']) ?? _inferGoodType(productTags);
    final techPlatform = _sectionValue(sections, const [
      '技术平台',
      '技术标签',
      '技术能力',
    ]);
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
      'owner1Level': _sectionValue(sections, const ['第一责任人等级', '任务等级']) ?? '',
      'owner2': owner2,
      'owner2Level': _sectionValue(sections, const ['第二责任人等级']) ?? '',
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

class _Approver {
  final String role;
  final String name;
  final String? subLabel;
  final _ApprovalStatus status;

  const _Approver({
    required this.role,
    required this.name,
    this.subLabel,
    required this.status,
  });
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

List<_Approver> _buildApprovers(Map<String, dynamic> owners) {
  final rows = <_Approver>[];
  void addOwner(String role, Object? raw) {
    final name = _string(raw);
    if (name.isEmpty) return;
    rows.add(
      _Approver(role: role, name: name, status: _ApprovalStatus.pending),
    );
  }

  addOwner('国线负责人', owners['national']);
  addOwner('大区负责人', owners['regional']);
  addOwner('分省负责人', owners['provincial']);
  addOwner('技术负责人', owners['tech']);
  if (rows.isEmpty) {
    return const [
      _Approver(
        role: '审批人',
        name: 'Excel 未识别审批人',
        subLabel: '请在原表补充负责人后重新上传',
        status: _ApprovalStatus.pending,
      ),
    ];
  }
  return rows;
}

// ══════════════════════════════════════════════════════════════════════
// State
// ══════════════════════════════════════════════════════════════════════
class _ProposalUploadPageState extends State<ProposalUploadPage> {
  _UploadState _state = _UploadState.empty;
  _ParsedProposal? _parsed;
  final Set<String> _expandedIds = <String>{'finance'}; // 财务默认展开
  bool _submitting = false;

  Future<void> _handleUpload() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Excel 提案',
          extensions: ['xlsx'],
          mimeTypes: [
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ],
        ),
      ],
    );
    if (file == null) return;

    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      _showUploadError('请选择 .xlsx 格式的提案文件');
      return;
    }

    setState(() => _state = _UploadState.uploading);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw const _UploadException('文件超过 5 MB 限制');
      }
      final parsed = await _uploadAndParse(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _state = _UploadState.parsed;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _state = _UploadState.empty);
      _showUploadError(err is _UploadException ? err.message : '上传解析失败：$err');
    }
  }

  Future<_ParsedProposal> _uploadAndParse(
    String fileName,
    Uint8List bytes,
  ) async {
    final uri = Uri.parse('${DunesDefaults.apiBase}/proposals/upload');
    final req = http.MultipartRequest('POST', uri);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _handleSubmit() async {
    final parsed = _parsed;
    if (parsed == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final res = await _submitToXflow(parsed.toXflowSubmitValues());
      final businessId = _int(
        res['businessId'] ?? res['proposalId'] ?? res['id'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(businessId > 0 ? '已提交审批 · 提案 #$businessId' : '已提交审批'),
          duration: const Duration(seconds: 2),
        ),
      );
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
      '${DunesDefaults.flowApiBase}/xflow/templates/sales-proposal/submit',
    );
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = widget.session?.token.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
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
        title: const Text(
          '提案归档',
          style: TextStyle(
            color: _PDColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: switch (_state) {
        _UploadState.empty => _buildEmpty(),
        _UploadState.uploading => _buildUploading(),
        _UploadState.parsed => _buildParsed(_parsed!),
      },
    );
  }

  // ────────── Empty state ──────────
  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        Row(
          children: [
            const Text(
              'PROPOSAL ARCHIVE · 提案归档',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.5,
                color: _PDColors.mute,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 0.5, color: _PDColors.line)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '上传新提案',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: _PDColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '把 Excel 提案拖进来，系统自动识别字段、启动 6 步签字。',
          style: TextStyle(fontSize: 12, color: _PDColors.mute, height: 1.6),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _handleUpload,
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _PDColors.ink.withAlpha(78),
              strokeWidth: 1.4,
              radius: 12,
              dashLen: 6,
              gapLen: 4,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _PDColors.ink.withAlpha(14),
                      borderRadius: BorderRadius.circular(27),
                    ),
                    child: const Icon(
                      Icons.cloud_upload_outlined,
                      size: 28,
                      color: _PDColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '点击选择 · 或拖拽到此处',
                    style: TextStyle(
                      fontSize: 13,
                      color: _PDColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '.xlsx · 单文件 ≤ 5 MB',
                    style: TextStyle(
                      fontSize: 10,
                      color: _PDColors.mute,
                      letterSpacing: 0.3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _PDColors.coral.withAlpha(13),
            border: const Border(
              left: BorderSide(color: _PDColors.coral, width: 1.5),
            ),
          ),
          child: RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 10,
                color: _PDColors.mute,
                height: 1.6,
                letterSpacing: 0.2,
                fontFamily: 'monospace',
              ),
              children: [
                TextSpan(
                  text: '命名规则  ',
                  style: TextStyle(
                    color: _PDColors.coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: 'NY / YYS − 项目简称 − YYYYMMDD\n'),
                TextSpan(
                  text: '示例  ',
                  style: TextStyle(color: _PDColors.mute2),
                ),
                TextSpan(text: 'NY-ZSHPAYWTA-20260413'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ────────── Uploading state ──────────
  Widget _buildUploading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: _PDColors.coral,
              strokeWidth: 2.2,
              backgroundColor: _PDColors.line,
            ),
          ),
          SizedBox(height: 14),
          Text(
            '解析中',
            style: TextStyle(
              color: _PDColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'PARSING EXCEL · 提取 5 个板块字段',
            style: TextStyle(
              color: _PDColors.mute2,
              fontSize: 9,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ────────── Parsed state ──────────
  Widget _buildParsed(_ParsedProposal p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _buildFileHeader(p),
        const SizedBox(height: 10),
        _buildExcelPreviewButton(p),
        const SizedBox(height: 16),
        _badgeKicker('已识别', 'EXTRACTED'),
        const SizedBox(height: 10),
        _buildExtractedFields(p),
        const SizedBox(height: 18),
        _badgeKicker('内容预览', 'PREVIEW · ${p.sections.length} SECTIONS'),
        const SizedBox(height: 10),
        for (final s in p.sections) ...[
          _buildSectionCard(s),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 12),
        _badgeKicker(
          '审批',
          '6-STEP FLOW',
          trailing: '1 / ${p.approvers.length}',
        ),
        const SizedBox(height: 10),
        _buildWorkflow(p),
        const SizedBox(height: 20),
        _buildSubmitButton(),
      ],
    );
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
          GestureDetector(
            onTap: _resetUpload,
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
                Icons.open_in_new_rounded,
                size: 16,
                color: _PDColors.mute2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExcelPreview(_ParsedProposal p) async {
    final uri = Uri.parse(
      '${DunesDefaults.apiBase}/proposals/${Uri.encodeComponent(p.archiveId)}/preview.html',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showUploadError('无法打开 Excel 预览');
    }
  }

  Widget _buildExtractedFields(_ParsedProposal p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _PDColors.line2, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldRow('提案编号', valueMono: p.proposalId),
          const SizedBox(height: 7),
          _fieldRow('提案类型', child: _coralChip(p.proposalType)),
          const SizedBox(height: 7),
          _fieldRow(
            '产品属性',
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: p.productTags.map(_neutralChip).toList(),
            ),
          ),
          const SizedBox(height: 7),
          _fieldRow('上线渠道', valueText: '${p.channel} · ${p.province}'),
          const SizedBox(height: 7),
          _fieldRow('盈利模式', valueText: p.profitModel),
        ],
      ),
    );
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

  Widget _buildWorkflow(_ParsedProposal p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _PDColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _PDColors.line2, width: 0.6),
      ),
      child: Column(
        children: [
          for (int i = 0; i < p.approvers.length; i++)
            _buildApproverRow(
              p.approvers[i],
              isLast: i == p.approvers.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildApproverRow(_Approver a, {required bool isLast}) {
    const dotSize = 12.0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: dotSize + 2,
            child: Column(
              children: [
                _statusDot(a.status),
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
                          '${a.role} · ${a.name}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: a.status == _ApprovalStatus.pending
                                ? _PDColors.mute
                                : _PDColors.ink,
                            fontWeight: a.status == _ApprovalStatus.current
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _statusChip(a),
                    ],
                  ),
                  if (a.subLabel != null && a.subLabel!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      a.subLabel!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: _PDColors.mute2,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(_ApprovalStatus s) {
    switch (s) {
      case _ApprovalStatus.done:
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _PDColors.success,
            shape: BoxShape.circle,
            border: Border.all(color: _PDColors.card, width: 2),
          ),
        );
      case _ApprovalStatus.current:
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _PDColors.card,
            shape: BoxShape.circle,
            border: Border.all(color: _PDColors.coral, width: 2),
            boxShadow: [
              BoxShadow(
                color: _PDColors.coral.withAlpha(45),
                blurRadius: 0,
                spreadRadius: 3,
              ),
            ],
          ),
        );
      case _ApprovalStatus.pending:
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
  }

  Widget _statusChip(_Approver a) {
    switch (a.status) {
      case _ApprovalStatus.done:
        return const Text(
          '已完成',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 8,
            color: _PDColors.success,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        );
      case _ApprovalStatus.current:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _PDColors.coral.withAlpha(38),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Text(
            '当前',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              color: _PDColors.coral,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        );
      case _ApprovalStatus.pending:
        return const Text(
          '待',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 8,
            color: _PDColors.mute2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        );
    }
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _submitting ? null : _handleSubmit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _PDColors.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_submitting)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      color: _PDColors.bg,
                      strokeWidth: 1.8,
                    ),
                  )
                else
                  const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: _PDColors.bg,
                  ),
                const SizedBox(width: 8),
                Text(
                  _submitting ? '提交中' : '提交归档',
                  style: const TextStyle(
                    color: _PDColors.bg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'SUBMIT · 提交后进入业务签字环节',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.5,
                color: _PDColors.bg.withAlpha(140),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
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
