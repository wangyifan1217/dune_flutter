import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NativeConversation conv({
    required String kind,
    String title = '',
    int id = 11,
    String preview = '',
  }) {
    return NativeConversation(
      id: id,
      kind: kind,
      title: title,
      unreadCount: 0,
      preview: preview,
      updatedAt: DateTime.utc(2026, 9, 21),
    );
  }

  test('对账/任务等 IM 助手可按会话列表名称搜索', () {
    final recon = conv(kind: 'RECONCILIATION_ASSISTANT', title: '对账通知');
    final task = conv(kind: 'TASK_ASSISTANT');
    final approval = conv(kind: 'APPROVAL_ASSISTANT');
    final group = conv(kind: 'WORKGROUP', title: '运营商组每日对账群');
    final person = conv(kind: 'PRIVATE', title: '王奕凡');

    expect(recon.isImAssistant, isTrue);
    expect(task.isImAssistant, isTrue);
    expect(approval.isImAssistant, isTrue);
    expect(group.isImAssistant, isFalse);
    expect(person.isImAssistant, isFalse);

    expect(recon.inboxDisplayTitle, '对账助手');
    expect(task.inboxDisplayTitle, '任务助手');
    expect(approval.inboxDisplayTitle, '审批助手');

    expect(recon.matchesSearchQuery('对账'), isTrue);
    expect(recon.matchesSearchQuery('助手'), isTrue);
    expect(task.matchesSearchQuery('任务'), isTrue);
    expect(task.matchesSearchQuery('任务助手'), isTrue);
    expect(approval.matchesSearchQuery('审批'), isTrue);
    expect(group.matchesSearchQuery('对账'), isTrue);
    expect(person.matchesSearchQuery('对账'), isFalse);
  });

  test('文件传输助手和绩效助手也能按名称命中', () {
    final memo = conv(kind: 'SELF_MEMO', title: '文件传输助手');
    final kpi = conv(kind: 'KPI_ASSISTANT');
    expect(memo.isImAssistant, isTrue);
    expect(memo.matchesSearchQuery('文件传输'), isTrue);
    expect(kpi.inboxDisplayTitle, '绩效助手');
    expect(kpi.matchesSearchQuery('绩效'), isTrue);
  });
}
