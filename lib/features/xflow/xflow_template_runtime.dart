import 'xflow_models.dart';

const kTemplateTypeUpload = 'upload';
const kPageModeExcelUpload = 'excel-upload';
const kPageModeXflowForm = 'xflow-form';

bool isRenderableField(XflowField field) {
  const skip = {'section', 'action', 'row', 'computed'};
  return !skip.contains(field.type);
}

XflowField? findPrimaryUploadField(List<XflowField> fields) {
  for (final field in fields) {
    if (field.type == 'upload' || field.raw['actionKind'] == 'excel-import') {
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
