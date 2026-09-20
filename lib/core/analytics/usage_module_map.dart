import '../navigation/generated/screen_registry.dart';

const kUsageModuleLabels = <String, String>{
  'comm': '通讯',
  'nova': 'NOVA',
  'lighthouse': '灯塔',
  'me': '我的',
  'approval': '审批',
  'task': '任务',
  'kb': '知识库',
  'meeting': '会议',
  'drive': '微盘',
  'h5': 'H5',
  'other': '其他',
};

String usageModuleLabel(String moduleKey) =>
    kUsageModuleLabels[moduleKey] ?? moduleKey;

String usageScreenName(String screenId) {
  final id = screenId.trim();
  const aliases = <String, String>{
    'QJUH': '使用热力',
    'QJUHD': '人员使用详情',
    'AA1': '审批助手',
    'AA2': '审批助手详情',
    'AA3': '审批助手操作',
  };
  final alias = aliases[id.toUpperCase()];
  if (alias != null) return alias;
  final info = dunesScreenById(id);
  if (info != null && info.name.trim().isNotEmpty) return info.name;
  return id;
}

String usageModuleKeyForScreen(String screenId) {
  final id = screenId.trim().toUpperCase();
  if (id.isEmpty) return 'other';
  if (id == 'C4' || id == 'C11') return 'nova';
  if (id.startsWith('QJ')) return 'nova';
  if (id == 'LH' || id == 'LM') return 'lighthouse';
  if (id == 'B2' || id.startsWith('B2')) return 'me';
  if (id == 'FD1') return 'drive';
  if (id == 'XR1' || id == 'CT1' || id == 'AM1') return 'h5';
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
