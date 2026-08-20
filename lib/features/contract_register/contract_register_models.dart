class ContractRegisterFile {
  const ContractRegisterFile({
    required this.fileName,
    this.objectKey = '',
    this.bucket = 'xflow-proposals',
    this.url = '',
    this.sizeBytes = 0,
    this.mimeType = '',
  });

  final String fileName;
  final String objectKey;
  final String bucket;
  final String url;
  final int sizeBytes;
  final String mimeType;

  factory ContractRegisterFile.fromJson(Map<String, dynamic> json) {
    return ContractRegisterFile(
      fileName: '${json['fileName'] ?? json['name'] ?? ''}'.trim(),
      objectKey: '${json['objectKey'] ?? ''}'.trim(),
      bucket: '${json['bucket'] ?? 'xflow-proposals'}'.trim().isEmpty
          ? 'xflow-proposals'
          : '${json['bucket']}'.trim(),
      url: '${json['url'] ?? ''}'.trim(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ??
          (json['size'] as num?)?.toInt() ??
          0,
      mimeType: '${json['mimeType'] ?? json['contentType'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fileName': fileName,
        'objectKey': objectKey,
        'bucket': bucket,
        if (url.isNotEmpty) 'url': url,
        if (sizeBytes > 0) 'sizeBytes': sizeBytes,
        if (mimeType.isNotEmpty) 'mimeType': mimeType,
      };
}

class ContractRegisterRow {
  const ContractRegisterRow({
    required this.id,
    required this.contractNo,
    required this.contractName,
    this.partyA = '',
    this.partyB = '',
    this.partyC = '',
    this.partyD = '',
    this.oaContact = '',
    this.sealDate = '',
    this.archiveDate = '',
    this.signDate = '',
    this.endDate = '',
    this.copies,
    this.companyContact = '',
    this.keywords = '',
    this.counterpartyNo = '',
    this.amount,
    this.remark = '',
    this.files = const <ContractRegisterFile>[],
    this.kbStatus = 'none',
    this.aiParseStatus = 'none',
    this.aiParseResult,
    this.aiParseCanWithdraw = false,
    this.proposalRelated,
    this.kbFile,
  });

  final int id;
  final String contractNo;
  final String contractName;
  final String partyA;
  final String partyB;
  final String partyC;
  final String partyD;
  final String oaContact;
  final String sealDate;
  final String archiveDate;
  final String signDate;
  final String endDate;
  final int? copies;
  final String companyContact;
  final String keywords;
  final String counterpartyNo;
  final double? amount;
  final String remark;
  final List<ContractRegisterFile> files;
  final String kbStatus;
  final String aiParseStatus;
  final Object? aiParseResult;
  final bool aiParseCanWithdraw;
  final ContractRegisterProposal? proposalRelated;
  final ContractRegisterKbFile? kbFile;

  factory ContractRegisterRow.fromJson(Map<String, dynamic> json) {
    final proposalRaw = json['proposalRelated'];
    final kbFileRaw = json['kbFile'];
    return ContractRegisterRow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      contractNo: '${json['contractNo'] ?? ''}'.trim(),
      contractName: '${json['contractName'] ?? ''}'.trim(),
      partyA: '${json['partyA'] ?? ''}'.trim(),
      partyB: '${json['partyB'] ?? ''}'.trim(),
      partyC: '${json['partyC'] ?? ''}'.trim(),
      partyD: '${json['partyD'] ?? ''}'.trim(),
      oaContact: '${json['oaContact'] ?? ''}'.trim(),
      sealDate: '${json['sealDate'] ?? ''}'.trim(),
      archiveDate: '${json['archiveDate'] ?? ''}'.trim(),
      signDate: '${json['signDate'] ?? ''}'.trim(),
      endDate: '${json['endDate'] ?? ''}'.trim(),
      copies: (json['copies'] as num?)?.toInt(),
      companyContact: '${json['companyContact'] ?? ''}'.trim(),
      keywords: '${json['keywords'] ?? ''}'.trim(),
      counterpartyNo: '${json['counterpartyNo'] ?? ''}'.trim(),
      amount: (json['amount'] as num?)?.toDouble(),
      remark: '${json['remark'] ?? ''}'.trim(),
      files: ((json['files'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ContractRegisterFile.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.fileName.isNotEmpty)
          .toList(growable: false),
      kbStatus: '${json['kbStatus'] ?? 'none'}'.trim().isEmpty
          ? 'none'
          : '${json['kbStatus']}'.trim(),
      aiParseStatus: '${json['aiParseStatus'] ?? 'none'}'.trim().isEmpty
          ? 'none'
          : '${json['aiParseStatus']}'.trim(),
      aiParseResult: json['aiParseResult'],
      aiParseCanWithdraw: json['aiParseCanWithdraw'] == true ||
          _aiParseCanWithdrawFromResult(
            '${json['aiParseStatus'] ?? ''}',
            json['aiParseResult'],
          ),
      proposalRelated: proposalRaw is Map
          ? ContractRegisterProposal.fromJson(Map<String, dynamic>.from(proposalRaw))
          : null,
      kbFile: kbFileRaw is Map
          ? ContractRegisterKbFile.fromJson(Map<String, dynamic>.from(kbFileRaw))
          : null,
    );
  }

  String get kbStatusLabel {
    switch (kbStatus) {
      case 'pending':
        return '已入库未解析';
      case 'ready':
        return '已解析';
      case 'failed':
        return '入库/解析失败';
      default:
        return '未入库';
    }
  }

  bool get kbParsed => kbStatus == 'ready';

  bool get aiParsePending => aiParseStatus == 'pending';

  String get aiParseMessage {
    final raw = aiParseResult;
    if (raw is Map) {
      final msg = '${raw['message'] ?? ''}'.trim();
      if (msg.isNotEmpty) return msg;
    }
    switch (aiParseStatus) {
      case 'pending':
        return '正在识别提案相关信息';
      case 'ready':
        return '已识别并填充提案相关字段';
      case 'failed':
        return '识别失败';
      case 'withdrawn':
        return '已撤回识别结果';
      default:
        return '';
    }
  }
}

bool _aiParseCanWithdrawFromResult(String status, Object? result) {
  if (status.trim() != 'ready' || result is! Map) return false;
  return result.containsKey('snapshot') && result['snapshot'] != null;
}

class ContractRegisterKbFile {
  const ContractRegisterKbFile({
    required this.fileName,
    this.ragflowDocId = '',
  });

  final String fileName;
  final String ragflowDocId;

  factory ContractRegisterKbFile.fromJson(Map<String, dynamic> json) {
    return ContractRegisterKbFile(
      fileName: '${json['fileName'] ?? json['name'] ?? ''}'.trim(),
      ragflowDocId: '${json['ragflowDocId'] ?? ''}'.trim(),
    );
  }

  bool get hasFile => fileName.isNotEmpty || ragflowDocId.isNotEmpty;
}

class ContractRegisterListResult {
  const ContractRegisterListResult({
    required this.items,
    required this.total,
  });

  final List<ContractRegisterRow> items;
  final int total;
}

class ContractRegisterAccess {
  const ContractRegisterAccess({
    this.view = false,
    this.config = false,
    this.kbSync = false,
  });

  final bool view;
  final bool config;
  final bool kbSync;
}

class ContractKbSyncResult {
  const ContractKbSyncResult({
    this.status = 'idle',
    this.listed = 0,
    this.matched = 0,
    this.updated = 0,
    this.skipped = 0,
    this.message = '',
    this.startedAt = '',
    this.finishedAt = '',
  });

  final String status;
  final int listed;
  final int matched;
  final int updated;
  final int skipped;
  final String message;
  final String startedAt;
  final String finishedAt;

  factory ContractKbSyncResult.fromJson(Map<String, dynamic> json) {
    return ContractKbSyncResult(
      status: '${json['status'] ?? 'idle'}'.trim().isEmpty
          ? 'idle'
          : '${json['status']}'.trim(),
      listed: (json['listed'] as num?)?.toInt() ?? 0,
      matched: (json['matched'] as num?)?.toInt() ?? 0,
      updated: (json['updated'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      message: '${json['message'] ?? ''}'.trim(),
      startedAt: '${json['startedAt'] ?? ''}'.trim(),
      finishedAt: '${json['finishedAt'] ?? ''}'.trim(),
    );
  }

  String get summary {
    if (status == 'idle') return '尚未同步知识库状态';
    if (status == 'running') return '正在同步…';
    final when = finishedAt.isNotEmpty
        ? finishedAt.replaceFirst('T', ' ')
        : startedAt.replaceFirst('T', ' ');
    if (status == 'failed') {
      return when.isEmpty
          ? '上次同步失败${message.isEmpty ? '' : '：$message'}'
          : '上次同步失败（$when）${message.isEmpty ? '' : '：$message'}';
    }
    if (when.isEmpty) {
      return '已同步：匹配 $matched · 更新 $updated';
    }
    return '上次同步 $when · 匹配 $matched · 更新 $updated';
  }
}

class ContractProposalFieldDef {
  const ContractProposalFieldDef(this.key, this.label, {this.maxLines = 1});

  final String key;
  final String label;
  final int maxLines;
}

const contractProposalFieldGroups =
    <String, List<ContractProposalFieldDef>>{
  '采购合同': [
    ContractProposalFieldDef('purchaseName', '采购合同名称'),
    ContractProposalFieldDef('purchaseNo', '采购合同编号'),
    ContractProposalFieldDef('purchaseSignDate', '采购合同签署时间'),
    ContractProposalFieldDef('purchaseOurParty', '采购合同我方签约主体'),
    ContractProposalFieldDef('purchaseCounterparty', '采购合同对方签约主体'),
    ContractProposalFieldDef('purchaseValidPeriod', '采购合同有效期'),
    ContractProposalFieldDef('purchaseCoreTerms', '采购合同核心条款', maxLines: 4),
  ],
  '销售合同': [
    ContractProposalFieldDef('salesName', '销售合同名称'),
    ContractProposalFieldDef('salesNo', '销售合同编号'),
    ContractProposalFieldDef('salesSignDate', '销售合同签署时间'),
    ContractProposalFieldDef('salesOurParty', '销售合同我方签约主体'),
    ContractProposalFieldDef('salesCounterparty', '销售合同对方签约主体'),
    ContractProposalFieldDef('salesValidPeriod', '销售合同有效期'),
    ContractProposalFieldDef('salesCoreTerms', '销售合同核心条款', maxLines: 4),
  ],
  '合同政策': [
    ContractProposalFieldDef('supplierPolicy', '供货商政策', maxLines: 3),
    ContractProposalFieldDef('channelPolicy', '渠道政策', maxLines: 3),
  ],
  '结算信息': [
    ContractProposalFieldDef('supplySettleMode', '供给侧结算模式', maxLines: 2),
    ContractProposalFieldDef('supplySettleCycle', '供给侧结算周期', maxLines: 2),
    ContractProposalFieldDef('supplyPayer', '供给侧付款主体'),
    ContractProposalFieldDef('supplyPayAccount', '供给侧付款账户'),
    ContractProposalFieldDef('channelSettleMode', '渠道侧结算模式', maxLines: 2),
    ContractProposalFieldDef('channelSettleCycle', '渠道侧结算周期', maxLines: 2),
    ContractProposalFieldDef('channelPayee', '渠道侧收款主体'),
    ContractProposalFieldDef('channelReceiveAccount', '渠道侧收款账户'),
  ],
};

List<ContractProposalFieldDef> get contractProposalFieldDefs => [
      for (final group in contractProposalFieldGroups.values) ...group,
    ];

class ContractRegisterProposal {
  const ContractRegisterProposal({
    this.contractNo = '',
    this.sourceFileName = '',
    this.fields = const <String, String>{},
  });

  final String contractNo;
  final String sourceFileName;
  final Map<String, String> fields;

  factory ContractRegisterProposal.fromJson(Map<String, dynamic> json) {
    String read(String key) => '${json[key] ?? ''}'.trim();
    final fields = <String, String>{};
    for (final def in contractProposalFieldDefs) {
      fields[def.key] = read(def.key);
    }
    return ContractRegisterProposal(
      contractNo: read('contractNo'),
      sourceFileName: read('sourceFileName'),
      fields: fields,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contractNo': contractNo,
        'sourceFileName': sourceFileName,
        for (final def in contractProposalFieldDefs) def.key: fields[def.key] ?? '',
      };

  String valueOf(String key) => (fields[key] ?? '').trim();

  bool get hasContent =>
      sourceFileName.trim().isNotEmpty ||
      fields.values.any((e) => e.trim().isNotEmpty);
}
