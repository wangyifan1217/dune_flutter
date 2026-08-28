abstract final class DigitalAutoConfig {
  static const mcpPath = '/qianji/digital-auto/mcp';
  static const chatPath = '/qianji/digital-auto/chat';
  static const historyPath = '/qianji/digital-auto/history';

  /// Backend forces this via IM_SUMMARY service token. App does not pick a Nova model.
  static const chatModel = 'deepseek-v4-pro';

  static const welcomePrompts = <String>[
    '给渠道 mcp0828 新增渠道产品 连接测试券',
    '创建一个券包产品',
    '新建一个渠道并完成授权',
  ];

  static const systemPrompt =
      '你是三桶油.渠道对接助理。必须通过 function calling 使用当前提供的工具查询或写入数商测试环境，'
      '不要编造工具结果或雪花 ID，也不要声称工具未接入。缺省参数会落到测试商户/批次；调用前用中文简述你要做的事。'
      '工具参数里的雪花 ID 必须用字符串。若用户没给足够信息，先问再调工具。';

  static const meetingMinutes = DigitalAutoAssistantConfig(
    employeeKey: 'meeting-minutes',
    welcomeTitle: '你好，我是会议纪要助理',
    welcomeBody: '我可以帮你查询、整理和完善会议纪要；涉及完成待办时会先请你确认。',
    headerTitle: '会议纪要',
    headerSubtitle: '对话整理会议纪要与行动项',
    welcomePrompts: <String>['帮我查找今天的会议纪要', '总结最近会议的待办事项', '完善这份会议纪要'],
    mcpPath: '/qianji/meeting-minutes/mcp',
    chatPath: '/qianji/meeting-minutes/chat',
    historyPath: '/qianji/meeting-minutes/history',
    systemPrompt:
        '你是会议纪要助理。使用提供的工具查询和整理会议纪要，不要编造会议、纪要或待办结果。'
        '当需要调用 minutes_complete_action_item 完成行动项时，先说明将完成的事项，等待用户在界面上确认后再执行。',
  );

  static const channelDock = DigitalAutoAssistantConfig(
    employeeKey: 'channel-dock',
    welcomeTitle: '你好，我是三桶油.渠道对接助理',
    welcomeBody: '可以直接说要给哪个渠道加产品、建券包或新建渠道。写入会落到测试环境。',
    headerTitle: '三桶油.渠道对接',
    headerSubtitle: '对话完成渠道与产品配置',
    welcomePrompts: welcomePrompts,
    mcpPath: mcpPath,
    chatPath: chatPath,
    historyPath: historyPath,
    systemPrompt: systemPrompt,
  );
}

class DigitalAutoAssistantConfig {
  const DigitalAutoAssistantConfig({
    required this.employeeKey,
    required this.welcomeTitle,
    required this.welcomeBody,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.welcomePrompts,
    required this.mcpPath,
    required this.chatPath,
    required this.historyPath,
    required this.systemPrompt,
  });

  final String employeeKey;
  final String welcomeTitle;
  final String welcomeBody;
  final String headerTitle;
  final String headerSubtitle;
  final List<String> welcomePrompts;
  final String mcpPath;
  final String chatPath;
  final String historyPath;
  final String systemPrompt;

  factory DigitalAutoAssistantConfig.fromJson(
    Map<String, dynamic>? json, {
    required DigitalAutoAssistantConfig defaults,
    String? employeeKey,
  }) {
    final source = json ?? const <String, dynamic>{};
    final intro = source['intro'] is Map
        ? Map<String, dynamic>.from(source['intro'] as Map)
        : const <String, dynamic>{};
    final runtime = source['runtime'] is Map
        ? Map<String, dynamic>.from(source['runtime'] as Map)
        : const <String, dynamic>{};
    String stringValue(
      Map<String, dynamic> values,
      String key,
      String fallback,
    ) {
      final value = values[key];
      return value is String && value.trim().isNotEmpty
          ? value.trim()
          : fallback;
    }

    String pathValue(String key, String fallback) {
      final value = stringValue(
        runtime,
        key,
        stringValue(source, key, fallback),
      );
      return value.startsWith('/qianji/') ? value : fallback;
    }

    final rawPrompts = source['prompts'] ?? source['welcomePrompts'];
    final prompts = rawPrompts is List
        ? rawPrompts
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : defaults.welcomePrompts;
    return DigitalAutoAssistantConfig(
      employeeKey: employeeKey?.trim().isNotEmpty == true
          ? employeeKey!.trim()
          : defaults.employeeKey,
      welcomeTitle: stringValue(
        intro,
        'title',
        stringValue(source, 'welcomeTitle', defaults.welcomeTitle),
      ),
      welcomeBody: stringValue(
        intro,
        'body',
        stringValue(source, 'welcomeBody', defaults.welcomeBody),
      ),
      headerTitle: stringValue(source, 'headerTitle', defaults.headerTitle),
      headerSubtitle: stringValue(
        intro,
        'headerSubtitle',
        stringValue(source, 'headerSubtitle', defaults.headerSubtitle),
      ),
      welcomePrompts: prompts.isEmpty ? defaults.welcomePrompts : prompts,
      mcpPath: pathValue('mcpPath', defaults.mcpPath),
      chatPath: pathValue('chatPath', defaults.chatPath),
      historyPath: pathValue('historyPath', defaults.historyPath),
      systemPrompt: stringValue(source, 'systemPrompt', defaults.systemPrompt),
    );
  }
}
