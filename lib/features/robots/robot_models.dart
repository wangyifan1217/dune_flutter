import 'package:flutter/material.dart';

/// Tab NOVA「机器人」静态数据（与通讯 C4 NOVA 无关）。
/// 风格对齐：工作流场景 + 角色库；运行态对接未来 N8N 节点接口。

enum RobotNodeStatus { pending, running, success, failed, skipped }

class RobotRole {
  const RobotRole({
    required this.id,
    required this.name,
    required this.category,
    required this.desc,
    required this.skin,
    required this.hair,
    required this.accent,
    this.glasses = false,
    this.primaryScenarioId,
    /// 缺省 true：允许用户发起/继续会话；false=仅推送。
    this.canChat = true,
  });

  final String id;
  final String name;
  final String category;
  final String desc;
  final Color skin;
  final Color hair;
  final Color accent;
  final bool glasses;
  /// 首页「运行」默认绑定的 N8N 场景。
  final String? primaryScenarioId;
  final bool canChat;

  factory RobotRole.fromApi(Map<String, dynamic> json) {
    return RobotRole(
      id: '${json['robotKey'] ?? json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      category: '${json['category'] ?? ''}'.trim(),
      desc: '${json['description'] ?? json['desc'] ?? ''}'.trim(),
      skin: _parseColor(json['skinColor'], const Color(0xFFF3C9AE)),
      hair: _parseColor(json['hairColor'], const Color(0xFF2A2624)),
      accent: _parseColor(json['accentColor'], const Color(0xFF6C4DFF)),
      glasses: json['glasses'] == true,
      primaryScenarioId: () {
        final v = '${json['primaryScenarioKey'] ?? ''}'.trim();
        return v.isEmpty ? null : v;
      }(),
      // 缺省 true，兼容旧缓存 / 旧包。
      canChat: json['canChat'] != false,
    );
  }
}

Color _parseColor(dynamic raw, Color fallback) {
  var s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return fallback;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) {
    final v = int.tryParse(s, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return fallback;
}

class RobotFlowNode {
  const RobotFlowNode({
    required this.id,
    required this.name,
    required this.typeLabel,
    required this.status,
    this.reply = '',
    this.durationLabel = '',
  });

  final String id;
  final String name;
  final String typeLabel;
  final RobotNodeStatus status;
  final String reply;
  final String durationLabel;

  RobotFlowNode copyWith({
    RobotNodeStatus? status,
    String? reply,
    String? durationLabel,
  }) {
    return RobotFlowNode(
      id: id,
      name: name,
      typeLabel: typeLabel,
      status: status ?? this.status,
      reply: reply ?? this.reply,
      durationLabel: durationLabel ?? this.durationLabel,
    );
  }
}

class RobotScenario {
  const RobotScenario({
    required this.id,
    required this.title,
    required this.desc,
    required this.stepCount,
    required this.roleIds,
    required this.nodes,
  });

  final String id;
  final String title;
  final String desc;
  final int stepCount;
  final List<String> roleIds;
  final List<RobotFlowNode> nodes;
}

abstract final class RobotTheme {
  static const purple = Color(0xFF6C4DFF);
  static const purpleSoft = Color(0xFFF1EDFF);
  static const purpleDeep = Color(0xFF5438D6);
  static const pageBg = Color(0xFFF5F6F8);
  static const cardBorder = Color(0xFFE8EAED);
  static const text = Color(0xFF1F2421);
  static const text2 = Color(0xFF5A5C56);
  static const text3 = Color(0xFF94938A);
}

abstract final class RobotCatalog {
  /// 首页名片展示的唯一机器人。
  static const lighthouse = RobotRole(
    id: 'r_lighthouse',
    name: '灯塔机器人',
    category: '经营分析',
    desc: '灯塔经营分析助手，后续对接 N8N 流程节点状态与回复。',
    skin: Color(0xFFF3C9AE),
    hair: Color(0xFF2A2624),
    accent: Color(0xFF6C4DFF),
    primaryScenarioId: 'sc_meeting',
  );

  static const roles = <RobotRole>[
    lighthouse,
    RobotRole(
      id: 'r_ops',
      name: '流程调度员',
      category: '流程编排',
      desc: '负责触发 N8N 工作流、汇总节点结果，并把关键状态推送给你。',
      skin: Color(0xFFF3C9AE),
      hair: Color(0xFF2A2624),
      accent: Color(0xFF6C4DFF),
      primaryScenarioId: 'sc_meeting',
    ),
    RobotRole(
      id: 'r_doc',
      name: '文档整理官',
      category: '知识处理',
      desc: '读取附件与会议纪要，提炼要点、生成结构化摘要。',
      skin: Color(0xFFE8B896),
      hair: Color(0xFF4A3428),
      accent: Color(0xFF3B7BB5),
      glasses: true,
      primaryScenarioId: 'sc_meeting',
    ),
    RobotRole(
      id: 'r_qa',
      name: '质检小助手',
      category: '质量校验',
      desc: '检查上游节点输出是否完整，发现缺项时给出提醒。',
      skin: Color(0xFFF6D3B5),
      hair: Color(0xFF6A4030),
      accent: Color(0xFF2F8F7E),
      primaryScenarioId: 'sc_meeting',
    ),
    RobotRole(
      id: 'r_msg',
      name: '消息派送员',
      category: '通知触达',
      desc: '把流程结论发送到会话或邮件，并记录送达结果。',
      skin: Color(0xFFEBC4A4),
      hair: Color(0xFF1E1A18),
      accent: Color(0xFFE56B3A),
      primaryScenarioId: 'sc_cursor',
    ),
  ];

  static const categories = <String>[
    '全部',
    '流程编排',
    '知识处理',
    '质量校验',
    '通知触达',
  ];

  static RobotRole roleById(String id) {
    for (final r in roles) {
      if (r.id == id) return r;
    }
    return roles.first;
  }

  static final scenarios = <RobotScenario>[
    RobotScenario(
      id: 'sc_meeting',
      title: '会议纪要自动整理',
      desc: '拉取会议录音转写 → 摘要提炼 → 质检校对 → 推送结果到指定会话。',
      stepCount: 4,
      roleIds: const ['r_ops', 'r_doc', 'r_qa', 'r_msg'],
      nodes: const [
        RobotFlowNode(
          id: 'n1',
          name: '触发工作流',
          typeLabel: 'Webhook',
          status: RobotNodeStatus.pending,
        ),
        RobotFlowNode(
          id: 'n2',
          name: '转写与摘要',
          typeLabel: 'AI',
          status: RobotNodeStatus.pending,
        ),
        RobotFlowNode(
          id: 'n3',
          name: '质检校对',
          typeLabel: 'Code',
          status: RobotNodeStatus.pending,
        ),
        RobotFlowNode(
          id: 'n4',
          name: '推送结果',
          typeLabel: 'HTTP',
          status: RobotNodeStatus.pending,
        ),
      ],
    ),
    RobotScenario(
      id: 'sc_cursor',
      title: 'Cursor 用量周报',
      desc: '定时拉取账号用量 → 生成周报卡片 → 通知管理员关注异常用量。',
      stepCount: 3,
      roleIds: const ['r_ops', 'r_doc', 'r_msg'],
      nodes: const [
        RobotFlowNode(
          id: 'n1',
          name: '定时触发',
          typeLabel: 'Cron',
          status: RobotNodeStatus.pending,
        ),
        RobotFlowNode(
          id: 'n2',
          name: '汇总用量数据',
          typeLabel: 'HTTP',
          status: RobotNodeStatus.pending,
        ),
        RobotFlowNode(
          id: 'n3',
          name: '发送周报',
          typeLabel: 'Notify',
          status: RobotNodeStatus.pending,
        ),
      ],
    ),
  ];

  static RobotScenario scenarioById(String? id) {
    for (final s in scenarios) {
      if (s.id == id) return s;
    }
    return scenarios.first;
  }
}
