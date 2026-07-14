import 'dart:convert';
import 'dart:typed_data';

bool novaIsMarkdownFile(String fileName, {String? mimeType}) {
  final name = fileName.trim().toLowerCase();
  if (name.endsWith('.md') || name.endsWith('.markdown')) return true;
  final mime = (mimeType ?? '').trim().toLowerCase();
  return mime.contains('markdown') || mime == 'text/x-markdown';
}

bool isDirectHttpUrl(String raw) {
  final s = raw.trim().toLowerCase();
  return s.startsWith('http://') || s.startsWith('https://');
}

/// Nova agent 交付物（/opt/data 等）走 `/v1/files/download` 多路径兜底，而非 storage 签名。
bool shouldUseNovaAgentFileDownload({
  required String url,
  required String objectKey,
  List<String> agentPathCandidates = const <String>[],
  String fileName = '',
}) {
  if (RegExp(r'/v1/files/download', caseSensitive: false).hasMatch(url)) {
    return true;
  }
  final key = objectKey.trim();
  if (key.startsWith('/opt/data/') ||
      key.startsWith('/workspace/') ||
      key.startsWith('/tmp/') ||
      key.startsWith('/root/')) {
    return true;
  }
  if (key.startsWith('/') &&
      RegExp(
        r'^(md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z|pptx?)$',
        caseSensitive: false,
      ).hasMatch(
        _fileExtFromName(fileName.isNotEmpty ? fileName : key.split('/').last),
      )) {
    return true;
  }
  if (agentPathCandidates.isNotEmpty) return true;
  if (key.isEmpty && fileName.trim().isNotEmpty && !isDirectHttpUrl(url)) {
    return true;
  }
  return false;
}

String _fileExtFromName(String name) {
  final path = name.split('?').first;
  final i = path.lastIndexOf('.');
  if (i < 0 || i == path.length - 1) return '';
  return path.substring(i + 1).toLowerCase();
}

/// 对话页当轮文件提问：支持扩展名（与 NOVA `/v1/app/chat/attachments` 一致）。
const kNovaChatAttachmentMaxBytes = 15 * 1024 * 1024;

const kNovaChatAttachmentExts = <String>{
  'txt',
  'md',
  'csv',
  'tsv',
  'json',
  'xml',
  'html',
  'log',
  'yaml',
  'yml',
  'toml',
  'docx',
  'xlsx',
  'pdf',
};

bool isNovaChatAttachmentSupported(String fileName) {
  final ext = _fileExtFromName(fileName);
  return ext.isNotEmpty && kNovaChatAttachmentExts.contains(ext);
}

String? novaChatAttachmentRejectReason({
  required String fileName,
  required int byteLength,
}) {
  if (byteLength <= 0) return '文件为空，请重新选择';
  if (byteLength > kNovaChatAttachmentMaxBytes) {
    return '文件超过 15MB，请压缩后再试';
  }
  final ext = _fileExtFromName(fileName);
  if (ext == 'doc' || ext == 'xls' || ext == 'ppt' || ext == 'pptx') {
    return '暂不支持 .$ext，请先转成 docx/xlsx/pdf/txt';
  }
  if (!isNovaChatAttachmentSupported(fileName)) {
    return '暂不支持该文件格式，请使用 Word/Excel/PDF/文本等';
  }
  return null;
}

/// 手机端能否直连该 URL（MinIO 签名常指向 127.0.0.1 / 内网 / Docker 主机名，不可达）。
bool isUrlLikelyDeviceReachable(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host == 'host.docker.internal') {
    return false;
  }
  if (RegExp(r'^10\.').hasMatch(host)) return false;
  if (RegExp(r'^192\.168\.').hasMatch(host)) return false;
  final m172 = RegExp(r'^172\.(\d+)\.').firstMatch(host);
  if (m172 != null) {
    final second = int.tryParse(m172.group(1) ?? '');
    if (second != null && second >= 16 && second <= 31) return false;
  }
  return true;
}

/// 优先使用 Nova 返回的可直链公网 URL（如 image.heunion.com），再回退 objectKey。
String pickNovaMediaSource({
  required String url,
  required String objectKey,
}) {
  final u = url.trim();
  final k = objectKey.trim();
  if (isDirectHttpUrl(u)) return u;
  if (isDirectHttpUrl(k)) return k;
  if (k.isNotEmpty) return k;
  return u;
}

/// Nova `/v1/files/download` 对不存在路径常返回 HTTP 200 + `{"success":false}`，需视为失败并尝试下一候选。
bool isNovaFilesApiErrorBody(
  Uint8List bytes, {
  String? contentType,
}) {
  if (bytes.isEmpty) return true;
  final ct = (contentType ?? '').toLowerCase();
  if (ct.contains('application/json') || bytes.length <= 512) {
    return _looksLikeNovaFilesErrorJson(bytes);
  }
  return false;
}

bool _looksLikeNovaFilesErrorJson(Uint8List bytes) {
  try {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (!text.startsWith('{') || !text.endsWith('}')) return false;
    final obj = jsonDecode(text);
    if (obj is! Map) return false;
    if (obj['success'] == false) return true;
    final msg = (obj['message'] ?? '').toString().toLowerCase();
    return msg.contains('not accessible') || msg.contains('not found');
  } catch (_) {
    return false;
  }
}

/// 后端 Markdown/文件正文均为 UTF-8；`package:http` 的 [Response.body] 在无 charset 时会按 Latin-1 解码导致乱码。
String decodeHttpResponseText(List<int> bodyBytes, {String? contentType}) {
  if (bodyBytes.isEmpty) return '';
  final ct = (contentType ?? '').toLowerCase();
  final charset = RegExp(r'charset=([^;\s]+)')
      .firstMatch(ct)
      ?.group(1)
      ?.trim()
      .toLowerCase();
  if (charset == 'utf-8' || charset == 'utf8') {
    return utf8.decode(bodyBytes, allowMalformed: true);
  }
  // 知识库 proxy、Nova agent 文件多为 UTF-8 且无 charset。
  return utf8.decode(bodyBytes, allowMalformed: true);
}
