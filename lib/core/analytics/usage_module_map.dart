import '../navigation/generated/screen_registry.dart';

const kUsageModuleLabels = <String, String>{
  'comm': '通讯',
  'nova': '小饕', // 只有小饕会话：QJ、C4、C11
  'workbench': '工作台', // 千机工作台及其子页
  'lighthouse': '灯塔',
  'me': '我的',
  'approval': '审批',
  'task': '任务',
  'kb': '知识库',
  'meeting': '会议',
  'drive': '微盘',
  'h5': '网页应用',
  'other': '其他',
};

/// 热力/埋点用的页面名。覆盖 HTML 原型里写死的人名、群名和旧英文。
const kUsageScreenLabels = <String, String>{
  'C1': '消息',
  'C2': '群聊',
  'C3': '通讯录',
  'C4': '小饕',
  'C5': '私聊',
  'C6': '群信息',
  'C7': '新建会话',
  'CR': '机器人会话',
  'C8': '语音通话',
  'C9': '联系人名片',
  'CF': '我的收藏',
  'C10': '公司广播',
  'C11': '小饕对话历史',
  'C12': '群聊搜索',
  'C13': '群文件',
  'QJ': '饕',
  'QJA': '工作台',
  'QJR': '机器人咨询',
  'QJRA': '新建咨询',
  'QJRC': '咨询详情',
  'QJC': 'Cursor 账号',
  'QJCD': 'Cursor 账号详情',
  'QJMM': '会议纪要监管',
  'QJMD': '会议纪要详情',
  'QJMA': '会议纪要助理',
  'QJTO': '三桶油渠道对接',
  'QJAM': '资管助理',
  'QJDE': '三桶油助理',
  'QJSS': '会话监管',
  'QJKB': '知识库监管',
  'QJEA': '效能分析',
  'QJEAB': '工作情况',
  'QJUH': '使用热力',
  'QJUHD': '人员使用详情',
  'QJFS': '资金借调',
  'QJFSD': '资金借调详情',
  'QJTR': '差旅管理',
  'QJTI': '差旅列表',
  'QJCF': '资金流向',
  'QJMB': '月结',
  'QJD': '产品详情',
  'QJI': '迭代详情',
  'QJM': '我的项目',
  'QJMT': '项目任务',
  'QJTD': '任务详情',
  'QJT': '团队考核',
  'QJP': '我的绩效',
  'AA1': '审批助手',
  'AA2': '审批助手详情',
  'AA3': '审批助手操作',
  'TA1': '任务助手',
  'KA1': '绩效助手',
  'XA1': '薪人薪事助手',
  'RA1': '对账助手',
  'LH': '灯塔',
  'B2': '我的中心',
  'Z4': '全局搜索',
  'PH1': '差旅申请',
  'PH2': '电子报销',
  'PH3': '薪酬福利',
  'PH4': '物品领用',
  'PH5': '驻外补贴',
};

final _privateChatTitle = RegExp(r'^私聊\s*[·\-.—/]\s*.+');
final _placeholderSuffix = RegExp(r'[(（]\s*占位\s*[)）]');
final _routeCode = RegExp(r'^[A-Za-z]{1,6}\d{0,4}[A-Za-z]{0,4}$');

String usageModuleLabel(String moduleKey, [String fallback = '']) {
  final key = moduleKey.trim();
  final mapped =
      kUsageModuleLabels[key] ?? kUsageModuleLabels[key.toLowerCase()];
  if (mapped != null) return mapped;
  final name = fallback.trim();
  if (name.isNotEmpty) return _sanitizeUsageLabel(name);
  return _sanitizeUsageLabel(key);
}

String usageScreenName(String screenId) {
  return usagePageLabel(screenId: screenId, screenName: screenId);
}

String usagePageLabel({String screenId = '', String screenName = ''}) {
  final id = screenId.trim();
  if (id.isNotEmpty) {
    final fromId = _lookupUsageScreen(id);
    if (fromId != null) return fromId;
    final info = dunesScreenById(id);
    final registryName = info?.name.trim() ?? '';
    if (registryName.isNotEmpty) {
      return _readableUsageLabel(registryName, fallbackId: id);
    }
  }
  final name = screenName.trim();
  if (name.isNotEmpty) {
    final fromName = _lookupUsageScreen(name);
    if (fromName != null) return fromName;
    return _readableUsageLabel(name, fallbackId: id.isNotEmpty ? id : name);
  }
  return _readableUsageLabel(id, fallbackId: id);
}

String? _lookupUsageScreen(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final upper = trimmed.toUpperCase();
  final alias = kUsageScreenLabels[upper] ?? kUsageScreenLabels[trimmed];
  if (alias != null) return alias;
  final sanitized = _sanitizeUsageLabel(trimmed);
  if (sanitized != trimmed &&
      (kUsageScreenLabels.containsValue(sanitized) ||
          sanitized == '私聊' ||
          sanitized == '小饕' ||
          sanitized == '群聊')) {
    return sanitized;
  }
  return null;
}

String _sanitizeUsageLabel(String raw) {
  var name = raw.trim();
  if (name.isEmpty) return name;
  if (_privateChatTitle.hasMatch(name)) return '私聊';
  if (name == '审批工作群') return '群聊';
  name = name.replaceAll(_placeholderSuffix, '');
  name = name.replaceAll(RegExp('NOVA', caseSensitive: false), '小饕');
  name = name.replaceAll(' · ', ' ').replaceAll('·', '');
  name = name.trim();
  if (_looksLikeRouteCode(name)) {
    final alias = kUsageScreenLabels[name.toUpperCase()];
    if (alias != null) return alias;
  }
  return name.isEmpty ? raw.trim() : name;
}

String _readableUsageLabel(String raw, {String fallbackId = ''}) {
  final sanitized = _sanitizeUsageLabel(raw);
  if (!_looksLikeRouteCode(sanitized)) return sanitized;
  final id = fallbackId.trim().isNotEmpty ? fallbackId : raw;
  return usageModuleLabel(usageModuleKeyForScreen(id));
}

bool _looksLikeRouteCode(String name) {
  final trimmed = name.trim();
  return trimmed.length <= 10 && _routeCode.hasMatch(trimmed);
}

/// 功能停留、最常用按接口 moduleKey 汇总，不再用页面编号前缀改写。
String usageResolvedModuleKey({
  String screenId = '',
  String screenName = '',
  String moduleKey = '',
}) {
  final key = moduleKey.trim().toLowerCase();
  if (key.isNotEmpty && key != '_session') return key;
  // 接口没给模块时才按页面归类，避免把已拆开的工作台画回小饕。
  final fromId = usageModuleKeyForScreen(screenId);
  if (fromId != 'other') return fromId;
  final fromName = usageModuleKeyForScreen(screenName);
  if (fromName != 'other') return fromName;
  return 'other';
}

/// 单点免登应用的模块键，须匹配服务端 `h5:` + 最多 29 位。
String enterpriseUsageModuleKey(String appKey) {
  final slug = enterpriseAppSlug(appKey);
  if (slug.isEmpty) return 'h5';
  return 'h5:$slug';
}

/// 单点免登应用的页面编号。导航仍走 AM1，埋点用这个编号把各应用拆开。
String enterpriseUsageScreenId(String appKey) {
  final slug = enterpriseAppSlug(appKey);
  if (slug.isEmpty) return 'AM1';
  return 'AM:$slug';
}

String enterpriseAppSlug(String appKey) {
  final raw = appKey.trim().toLowerCase();
  if (raw.isEmpty) return '';
  final ascii = raw.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  final slug = ascii.isNotEmpty ? ascii : _hexSlug(raw);
  if (slug.length <= 29) return slug;
  return slug.substring(0, 29);
}

String _hexSlug(String raw) {
  final buf = StringBuffer();
  for (final unit in raw.codeUnits) {
    buf.write(unit.toRadixString(16));
    if (buf.length >= 29) break;
  }
  final hex = buf.toString();
  return hex.length > 29 ? hex.substring(0, 29) : hex;
}

String usageModuleKeyForScreen(String screenId) {
  final id = screenId.trim().toUpperCase();
  if (id.isEmpty) return 'other';
  if (id == 'C4' || id == 'C11' || id == 'QJ') return 'nova';
  if (id.startsWith('QJ')) return 'workbench';
  if (id == 'LH' || id == 'LM') return 'lighthouse';
  if (id == 'B2' || id.startsWith('B2')) return 'me';
  if (id == 'FD1') return 'drive';
  // 企业应用按实际打开的系统拆开，不再并进同一个「网页应用」。
  if (id == 'XR1') return 'h5:xrxs';
  if (id == 'CT1') return 'h5:ctrip';
  if (id.startsWith('AM:')) {
    final slug = id.substring(3).toLowerCase();
    if (RegExp(r'^[a-z0-9_-]{1,29}$').hasMatch(slug)) return 'h5:$slug';
    return 'h5';
  }
  if (id == 'AM1') return 'h5';
  // 绩效助手 KA1 不能按 K 前缀算进知识库
  if (id == 'KA1' || id == 'XA1' || id == 'RA1') return 'comm';
  if (id.startsWith('K')) return 'kb';
  if (id.startsWith('MM')) return 'meeting';
  if (id.startsWith('TA')) return 'task';
  if (id.startsWith('C')) return 'comm';
  if (id.startsWith('B') ||
      id.startsWith('P') ||
      id.startsWith('XF') ||
      id.startsWith('R') ||
      id.startsWith('PY') ||
      id.startsWith('A') ||
      id.startsWith('E') ||
      id.startsWith('M') ||
      id.startsWith('PH') ||
      id.startsWith('W')) {
    return 'approval';
  }
  return 'other';
}
