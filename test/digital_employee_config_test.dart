import 'package:dunes_app/features/qianji/digital_auto/digital_auto_config.dart';
import 'package:dunes_app/features/qianji/digital_auto/digital_employee_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses channel defaults for a malformed assistant config', () {
    final item = DigitalEmployeeItem.fromApi({
      'employeeKey': 'channel-dock',
      'name': '渠道对接',
      'screenId': 'QJTO',
      'assistantConfig': '{invalid json',
    });

    expect(item.chatConfig.chatPath, DigitalAutoConfig.chatPath);
    expect(item.chatConfig.headerTitle, '三桶油.渠道对接');
  });

  test('applies valid catalog configuration over meeting defaults', () {
    final item = DigitalEmployeeItem.fromApi({
      'employeeKey': 'meeting-minutes',
      'name': '会议纪要',
      'screenId': 'QJMA',
      'assistantConfig': {
        'intro': {
          'title': '你好，自定义会议助手',
          'body': '查询会议和待办。',
          'headerSubtitle': '会议协作',
        },
        'prompts': ['整理本周会议'],
        'runtime': {
          'mcpServerName': 'meeting-minutes',
          'mcpPath': 'unsafe-path',
          'chatPath': '/qianji/meeting-minutes/chat',
          'scope': 'meeting.minutes.read',
        },
      },
    });

    expect(item.isMeetingMinutes, isTrue);
    expect(item.chatConfig.welcomeTitle, '你好，自定义会议助手');
    expect(item.chatConfig.headerSubtitle, '会议协作');
    expect(item.chatConfig.welcomePrompts, ['整理本周会议']);
    expect(item.chatConfig.chatPath, '/qianji/meeting-minutes/chat');
    expect(item.chatConfig.mcpPath, DigitalAutoConfig.meetingMinutes.mcpPath);
  });

  test('catalog iconKey maps to the same Material icon on hub and chat', () {
    expect(digitalEmployeeIcon('auto_awesome'), Icons.auto_awesome_rounded);
    expect(digitalEmployeeIcon('oil_barrel'), Icons.oil_barrel_rounded);
    expect(digitalEmployeeIcon(null), Icons.auto_awesome_rounded);
  });
}
