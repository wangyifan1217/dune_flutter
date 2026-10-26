import 'xflow_models.dart';

String approvalTodoCsvCell(String value) {
  final text = value
      .replaceAll('\r\n', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');
  if (text.contains(',') || text.contains('"')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String approvalTodoStatusText(XflowProposalItem item) {
  final key = (item.todoHint?.status ?? item.status).toUpperCase();
  return switch (key) {
    'OPEN' => '待办理',
    'DONE' => '已办理',
    'PENDING' => '审批中',
    'APPROVED' => '已通过',
    'REJECTED' => '已驳回',
    'CANCELLED' => '已取消',
    _ => key,
  };
}

String _stamp(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// 当前审批待办列表的 CSV。首行带 UTF-8 BOM，方便 Excel 打开中文。
String approvalTodoCsv(List<XflowProposalItem> items) {
  final lines = <String>[
    '编号,单据名称,提交人,办理动作,待办状态,模板,摘要,创建时间',
  ];
  for (final item in items) {
    final summary = item.highlights
        .map((row) => '${row.label}:${row.value}')
        .join('；');
    lines.add(
      [
        item.code,
        item.title,
        item.createdByName,
        item.actionTitle ?? item.primaryAction ?? '',
        approvalTodoStatusText(item),
        item.templateKey ?? '',
        summary,
        _stamp(item.createdAt),
      ].map(approvalTodoCsvCell).join(','),
    );
  }
  return '\uFEFF${lines.join('\n')}\n';
}
