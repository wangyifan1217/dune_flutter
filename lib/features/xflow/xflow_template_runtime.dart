import 'xflow_models.dart';

const kTemplateTypeUpload = 'upload';
const kPageModeExcelUpload = 'excel-upload';
const kPageModeXflowForm = 'xflow-form';

bool isRenderableField(XflowField field) {
  const skip = {'section', 'action', 'row', 'computed'};
  return !skip.contains(field.type);
}

/// Excel 识别上传（走 /proposals/upload）；普通附件 actionKind 为 file / 空。
bool isExcelImportField(XflowField field) {
  final kind = (field.raw['actionKind'] ?? '').toString().trim();
  if (kind == 'excel-import') return true;
  // 兼容旧配置：仅上传型主字段未写 actionKind，但 key 约定为提案 Excel。
  if (field.type == 'upload' &&
      kind.isEmpty &&
      field.key.trim() == 'proposalExcel') {
    return true;
  }
  return false;
}

bool isOrdinaryUploadField(XflowField field) {
  return field.type == 'upload' && !isExcelImportField(field);
}

/// 识别用主上传字段：优先 excel-import，避免普通附件（planFiles 等）抢占。
XflowField? findPrimaryUploadField(List<XflowField> fields) {
  for (final field in fields) {
    if (isExcelImportField(field)) return field;
  }
  for (final field in fields) {
    if (field.type == 'upload' ||
        field.raw['actionKind']?.toString() == 'excel-import') {
      return field;
    }
  }
  final renderable = fields.where(isRenderableField).toList(growable: false);
  if (renderable.length == 1 && renderable.first.type == 'upload') {
    return renderable.first;
  }
  return null;
}

bool isUploadTemplateConfig({
  Map<String, dynamic>? detailConfig,
  List<XflowField>? fields,
  String? pageMode,
}) {
  final mode = (pageMode ?? '').trim();
  if (mode == kPageModeExcelUpload) return true;
  if (mode == kPageModeXflowForm) return false;

  final cfg = detailConfig ?? const <String, dynamic>{};
  final templateType = (cfg['templateType'] ?? '').toString().trim();
  if (templateType == kTemplateTypeUpload) return true;

  final cfgPageMode = (cfg['pageMode'] ?? '').toString().trim();
  if (cfgPageMode == kPageModeExcelUpload) return true;
  if (cfgPageMode == kPageModeXflowForm) return false;

  final recognition = cfg['recognitionConfig'];
  if (recognition is Map && recognition['enabled'] == true) {
    return true;
  }

  final uploadField = findPrimaryUploadField(fields ?? const []);
  if (uploadField != null) {
    final renderable = (fields ?? const []).where(isRenderableField).length;
    return renderable <= 1;
  }
  return false;
}

String templateTitleFromDetail(
  XflowTemplateDetail? template, {
  String fallback = '销售提案',
}) {
  if (template == null) return fallback;
  if (template.title.trim().isNotEmpty) return template.title.trim();
  final rawTitle = template.raw['title'];
  if (rawTitle != null && rawTitle.toString().trim().isNotEmpty) {
    return rawTitle.toString().trim();
  }
  return fallback;
}

String templateSubtitleFromDetail(XflowTemplateDetail? template) {
  if (template == null) return '';
  final raw = template.raw['template'];
  if (raw is Map) {
    final subtitle = raw['subtitle'];
    if (subtitle != null && subtitle.toString().trim().isNotEmpty) {
      return subtitle.toString().trim();
    }
  }
  final subtitle = template.raw['subtitle'];
  return subtitle?.toString().trim() ?? '';
}
