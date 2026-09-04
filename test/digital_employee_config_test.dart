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
    expect(
      digitalEmployeeIcon('account_balance'),
      Icons.account_balance_outlined,
    );
    expect(digitalEmployeeIcon(null), Icons.auto_awesome_rounded);
  });

  test('uses am-settlement defaults and rejects unsafe mcp paths', () {
    final item = DigitalEmployeeItem.fromApi({
      'employeeKey': 'am-settlement',
      'name': '资管.AI助理',
      'screenId': 'QJAM',
      'assistantConfig': {
        'intro': {
          'title': '你好，自定义资管助手',
          'body': '查询结算行。',
          'headerSubtitle': '结算字典',
        },
        'prompts': ['能源有哪些渠道'],
        'runtime': {
          'mcpServerName': 'am-settlement',
          'mcpPath': 'unsafe-path',
          'chatPath': '/qianji/am-settlement/chat',
          'historyPath': '/qianji/am-settlement/history',
          'scope': 'am.settlement.read',
        },
      },
    });

    expect(item.isAmSettlement, isTrue);
    expect(item.chatConfig.welcomeTitle, '你好，自定义资管助手');
    expect(item.chatConfig.headerSubtitle, '结算字典');
    expect(item.chatConfig.welcomePrompts, ['能源有哪些渠道']);
    expect(item.chatConfig.chatPath, '/qianji/am-settlement/chat');
    expect(item.chatConfig.mcpPath, DigitalAutoConfig.amSettlement.mcpPath);
    expect(
      item.chatConfig.historyPath,
      DigitalAutoConfig.amSettlement.historyPath,
    );
  });

  test(
    'falls back to am-settlement defaults for a malformed catalog config',
    () {
      final item = DigitalEmployeeItem.fromApi({
        'employeeKey': 'am-settlement',
        'name': '资管.AI助理',
        'screenId': 'QJAM',
        'assistantConfig': '{invalid json',
      });

      expect(item.chatConfig.headerTitle, '资管.AI助理');
      expect(item.chatConfig.mcpPath, '/qianji/am-settlement/mcp');
      expect(item.chatConfig.chatPath, '/qianji/am-settlement/chat');
    },
  );
}
